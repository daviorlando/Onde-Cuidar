import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/facility.dart';
import 'app_database.dart';
import 'catalog_codec.dart';

const embeddedCatalogAsset = 'assets/catalog/catalog.json';

/// Catálogo carregado e metadados da versão instalada.
class InstalledCatalog {
  const InstalledCatalog({
    required this.catalog,
    required this.origin,
    required this.importedAt,
    this.recoveredFromCorruption = false,
  });

  final Catalog catalog;

  /// `embedded` ou `remote`.
  final String origin;
  final DateTime importedAt;

  /// A versão ativa estava ilegível e o catálogo embarcado foi restaurado.
  final bool recoveredFromCorruption;
}

/// Compara `AAAA-MM-DD.N`: data e depois sequência numérica.
int compareCatalogVersions(String a, String b) {
  final pattern = RegExp(r'^(\d{4}-\d{2}-\d{2})\.(\d+)$');
  final ma = pattern.firstMatch(a), mb = pattern.firstMatch(b);
  if (ma == null || mb == null) {
    throw FormatException('versão de catálogo inválida: $a / $b');
  }
  final byDate = ma[1]!.compareTo(mb[1]!);
  return byDate != 0 ? byDate : int.parse(ma[2]!).compareTo(int.parse(mb[2]!));
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Lê o catálogo local imediatamente; nunca depende de rede.
class CatalogRepository {
  CatalogRepository(this.db, this.loadAsset, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase db;

  /// Lê um asset empacotado no APK (rootBundle em produção).
  final Future<String> Function(String key) loadAsset;
  final DateTime Function() _clock;

  Future<InstalledCatalog> load() async {
    final stored = await db.activeCatalog();
    Catalog? active;
    var corrupted = false;
    if (stored != null) {
      try {
        if (sha256Hex(utf8.encode(stored.payload)) != stored.sha256) {
          throw CatalogFormatException('hash local divergente');
        }
        active = decodeCatalog(stored.payload);
      } on CatalogFormatException {
        corrupted = true;
      }
    }

    // Primeira abertura, base ilegível ou APK com catálogo embarcado mais novo.
    final embeddedText = await loadAsset(embeddedCatalogAsset);
    final embedded = decodeCatalog(embeddedText);
    if (active == null ||
        compareCatalogVersions(embedded.version, active.version) > 0) {
      final now = _clock().toUtc();
      await _activate(embedded, embeddedText, 'embedded', now);
      return InstalledCatalog(
        catalog: embedded,
        origin: 'embedded',
        importedAt: now,
        recoveredFromCorruption: corrupted,
      );
    }
    return InstalledCatalog(
      catalog: active,
      origin: stored!.origin,
      importedAt: stored.importedAt,
    );
  }

  /// Ativa um snapshot já validado (hash, assinatura e conteúdo).
  Future<void> activateValidated(Catalog catalog, String payload) =>
      _activate(catalog, payload, 'remote', _clock().toUtc());

  Future<void> _activate(
    Catalog catalog,
    String payload,
    String origin,
    DateTime now,
  ) => db.activateSnapshot(
    version: catalog.version,
    schemaVersion: catalog.schemaVersion,
    sha256: sha256Hex(utf8.encode(payload)),
    payload: payload,
    origin: origin,
    importedAt: now,
  );
}
