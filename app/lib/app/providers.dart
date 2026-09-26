import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../features/facilities/data/app_database.dart';
import '../features/facilities/data/catalog_repository.dart';
import '../features/facilities/domain/facility.dart';
import '../features/offline/data/catalog_sync_service.dart';
import '../features/offline/data/road_package_repository.dart';
import '../features/routing/data/location_service.dart';
import '../features/routing/data/routing_worker.dart';
import '../features/routing/domain/road_graph.dart';
import '../features/search/domain/eligibility.dart';
import '../features/search/domain/ranking.dart';
import '../features/search/domain/search_criteria.dart';
import 'config.dart';

// Dependências de infraestrutura: substituídas em main() e nos testes.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('databaseProvider não configurado'),
);
final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) =>
      throw UnimplementedError('catalogRepositoryProvider não configurado'),
);
final roadPackageRepositoryProvider = Provider<RoadPackageRepository>(
  (ref) =>
      throw UnimplementedError('roadPackageRepositoryProvider não configurado'),
);
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});
final locationServiceProvider = Provider<LocationService>(
  (ref) => const LocationService(),
);

final syncServiceProvider = Provider<CatalogSyncService>(
  (ref) => CatalogSyncService(
    db: ref.watch(databaseProvider),
    repository: ref.watch(catalogRepositoryProvider),
    client: ref.watch(httpClientProvider),
    manifestUrl: catalogManifestUrl,
    trustedKeys: trustedCatalogKeys,
    appVersion: appVersion,
  ),
);

/// Catálogo instalado, lido do SQLite imediatamente (ou do APK na 1ª abertura).
class InstalledCatalogNotifier extends AsyncNotifier<InstalledCatalog> {
  @override
  Future<InstalledCatalog> build() =>
      ref.watch(catalogRepositoryProvider).load();

  Future<void> reload() async {
    state = AsyncData(await ref.read(catalogRepositoryProvider).load());
  }
}

final installedCatalogProvider =
    AsyncNotifierProvider<InstalledCatalogNotifier, InstalledCatalog>(
      InstalledCatalogNotifier.new,
    );

class SyncStatus {
  const SyncStatus({this.running = false, this.lastOutcome, this.state});

  final bool running;
  final SyncOutcome? lastOutcome;
  final SyncState? state;
}

/// Sincronização em segundo plano da tela: não bloqueia a leitura local.
class SyncController extends Notifier<SyncStatus> {
  @override
  SyncStatus build() {
    unawaited(_loadState());
    return const SyncStatus();
  }

  Future<void> _loadState() async {
    final syncState = await ref.read(databaseProvider).syncState();
    if (!ref.mounted) return;
    state = SyncStatus(
      running: state.running,
      lastOutcome: state.lastOutcome,
      state: syncState,
    );
  }

  Future<SyncOutcome> refresh({bool manual = false}) async {
    state = SyncStatus(
      running: true,
      lastOutcome: state.lastOutcome,
      state: state.state,
    );
    final outcome = await ref.read(syncServiceProvider).refresh(manual: manual);
    if (outcome is SyncUpdated) {
      await ref.read(installedCatalogProvider.notifier).reload();
    }
    final syncState = await ref.read(databaseProvider).syncState();
    if (ref.mounted) {
      state = SyncStatus(lastOutcome: outcome, state: syncState);
    }
    return outcome;
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

class CriteriaNotifier extends Notifier<SearchCriteria> {
  @override
  SearchCriteria build() => const SearchCriteria();

  void set(SearchCriteria criteria) => state = criteria;
  void setText(String text) => state = state.copyWith(text: text);
  void clearFilters() => state = state.clearFilters();
}

final criteriaProvider = NotifierProvider<CriteriaNotifier, SearchCriteria>(
  CriteriaNotifier.new,
);

enum OriginKind { gps, manual }

class Origin {
  const Origin(this.point, this.kind, {this.accuracyMeters});

  final GeoPoint point;
  final OriginKind kind;
  final double? accuracyMeters;

  String get label => switch (kind) {
    OriginKind.gps => 'Minha localização',
    OriginKind.manual => 'Ponto escolhido no mapa',
  };
}

/// Origem somente em memória: descartada ao fechar o app.
class OriginNotifier extends Notifier<Origin?> {
  @override
  Origin? build() => null;

  void set(Origin? origin) => state = origin;
}

final originProvider = NotifierProvider<OriginNotifier, Origin?>(
  OriginNotifier.new,
);

enum PackageStatus { checking, notInstalled, installing, installed, failed }

class RoadPackageState {
  const RoadPackageState(this.status, {this.package, this.bundled, this.error});

  final PackageStatus status;
  final InstalledRoadPackage? package;
  final RoadPackageManifest? bundled;
  final String? error;

  bool get isInstalled => status == PackageStatus.installed && package != null;
}

class RoadPackageController extends Notifier<RoadPackageState> {
  @override
  RoadPackageState build() {
    unawaited(verify());
    return const RoadPackageState(PackageStatus.checking);
  }

  RoadPackageRepository get _repo => ref.read(roadPackageRepositoryProvider);

  Future<void> verify() async {
    final bundled = await _repo.bundledManifest();
    try {
      final package = await _repo.loadInstalled();
      state = package == null
          ? RoadPackageState(PackageStatus.notInstalled, bundled: bundled)
          : RoadPackageState(
              PackageStatus.installed,
              package: package,
              bundled: bundled,
            );
    } on RoadPackageException catch (e) {
      state = RoadPackageState(
        PackageStatus.failed,
        bundled: bundled,
        error: e.message,
      );
    }
  }

  Future<void> install() async {
    final bundled = state.bundled ?? await _repo.bundledManifest();
    state = RoadPackageState(PackageStatus.installing, bundled: bundled);
    try {
      final package = await _repo.installBundled();
      state = RoadPackageState(
        PackageStatus.installed,
        package: package,
        bundled: bundled,
      );
    } on RoadPackageException catch (e) {
      // Pacote anterior (se havia) continua no disco; reavaliar.
      final previous = await _safeLoad();
      state = previous != null
          ? RoadPackageState(
              PackageStatus.installed,
              package: previous,
              bundled: bundled,
              error: e.message,
            )
          : RoadPackageState(
              PackageStatus.failed,
              bundled: bundled,
              error: e.message,
            );
    }
  }

  Future<InstalledRoadPackage?> _safeLoad() async {
    try {
      return await _repo.loadInstalled();
    } on RoadPackageException {
      return null;
    }
  }

  Future<void> remove() async {
    await _repo.remove();
    state = RoadPackageState(
      PackageStatus.notInstalled,
      bundled: state.bundled,
    );
  }
}

final roadPackageProvider =
    NotifierProvider<RoadPackageController, RoadPackageState>(
      RoadPackageController.new,
    );

/// Grafo no isolate principal (desenho do mapa).
final roadGraphProvider = Provider<RoadGraph?>((ref) {
  final package = ref.watch(roadPackageProvider).package;
  return package == null ? null : RoadGraph.fromBytes(package.bytes);
});

/// Motor local; nulo sem pacote instalado.
final routingWorkerProvider = FutureProvider<RoutingWorker?>((ref) async {
  final package = ref.watch(roadPackageProvider).package;
  if (package == null) return null;
  final worker = await RoutingWorker.start(package.bytes);
  ref.onDispose(worker.dispose);
  return worker;
});

/// Centro inicial do mapa: mediana das unidades com coordenada (área urbana).
final catalogCenterProvider = Provider<GeoPoint?>((ref) {
  final catalog = ref.watch(installedCatalogProvider).value?.catalog;
  final points = [
    for (final f in catalog?.facilities ?? const <Facility>[]) ?f.location,
  ];
  if (points.isEmpty) return null;
  final lats = points.map((p) => p.lat).toList()..sort();
  final lons = points.map((p) => p.lon).toList()..sort();
  return GeoPoint(lats[lats.length ~/ 2], lons[lons.length ~/ 2]);
});

final eligibilityFilterProvider = Provider<EligibilityFilter?>((ref) {
  final catalog = ref.watch(installedCatalogProvider).value?.catalog;
  return catalog == null ? null : EligibilityFilter(catalog);
});

/// Elegíveis: disponíveis imediatamente, antes de qualquer cálculo de rota.
final eligibleProvider = Provider<List<Facility>>((ref) {
  final filter = ref.watch(eligibilityFilterProvider);
  if (filter == null) return const [];
  return filter.apply(ref.watch(criteriaProvider));
});

/// Ordenação provisória (alfabética ou linha reta) enquanto a viária calcula.
final provisionalRankingProvider = Provider<RankedResults>(
  (ref) => rank(
    ref.watch(eligibleProvider),
    origin: ref.watch(originProvider)?.point,
  ),
);

/// Ordenação final. Respostas de buscas antigas são descartadas pelo Riverpod
/// quando filtros ou origem mudam.
final rankingProvider = FutureProvider<RankedResults>((ref) async {
  final eligible = ref.watch(eligibleProvider);
  final origin = ref.watch(originProvider)?.point;
  if (origin == null) return rank(eligible);
  final worker = await ref.watch(routingWorkerProvider.future);
  if (worker == null) return rank(eligible, origin: origin);
  final destinations = {
    for (final f in eligible)
      if (f.location != null) f.id: f.location!,
  };
  final distances = await worker.distances(origin, destinations);
  return rank(eligible, origin: origin, roadDistances: distances);
});
