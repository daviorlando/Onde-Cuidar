// Medição do motor local no aparelho (CT18 / RNF03), com o pacote embarcado.
// Pares origem–destino: coordenadas públicas das próprias unidades do catálogo
// (nenhuma residência). Imprime linhas "MEDIDA" para o relatório.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:onde_cuidar/features/facilities/data/catalog_codec.dart';
import 'package:onde_cuidar/features/facilities/domain/facility.dart';
import 'package:onde_cuidar/features/routing/data/routing_worker.dart';
import 'package:onde_cuidar/features/routing/domain/offline_router.dart';
import 'package:onde_cuidar/features/search/domain/ranking.dart';

double percentile(List<int> values, double p) {
  final sorted = [...values]..sort();
  final index = ((sorted.length - 1) * p).round();
  return sorted[index].toDouble();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('30 rotas inéditas e ordenação de todas as unidades', (
    tester,
  ) async {
    final catalog = decodeCatalog(
      await rootBundle.loadString('assets/catalog/catalog.json'),
    );
    final compressed = (await rootBundle.load(
      'assets/routing/petrolina-car.ocrg.gz',
    )).buffer.asUint8List();
    final bytes = Uint8List.fromList(gzip.decode(compressed));

    final cold = Stopwatch()..start();
    final worker = await RoutingWorker.start(bytes);
    final first = await worker.route(
      const GeoPoint(-9.39, -40.50),
      const GeoPoint(-9.40, -40.51),
    );
    cold.stop();
    debugPrint(
      'MEDIDA inicializacao_fria_ms=${cold.elapsedMilliseconds} primeira=${first.runtimeType}',
    );

    final located = [
      for (final f in catalog.facilities)
        if (f.location != null) f,
    ];
    final random = math.Random(42); // pares reprodutíveis
    final times = <int>[];
    final results = <String>[];
    var found = 0;
    while (times.length < 30) {
      final a = located[random.nextInt(located.length)];
      final b = located[random.nextInt(located.length)];
      if (a.id == b.id) continue;
      final sw = Stopwatch()..start();
      final outcome = await worker.route(a.location!, b.location!);
      sw.stop();
      times.add(sw.elapsedMilliseconds);
      if (outcome is RouteFound) found++;
      results.add(
        '${a.id}->${b.id}: ${switch (outcome) {
          RouteFound(:final plan) => '${plan.distanceMeters.round()} m, ${plan.geometry.length} pontos',
          RouteFailure(:final reason) => reason.message,
        }} (${sw.elapsedMilliseconds} ms)',
      );
    }
    results.forEach(debugPrint);
    debugPrint(
      'MEDIDA rotas=${times.length} encontradas=$found '
      'p50_ms=${percentile(times, 0.5)} p95_ms=${percentile(times, 0.95)} max_ms=${times.reduce(math.max)}',
    );

    final origin = located[random.nextInt(located.length)].location!;
    final sw = Stopwatch()..start();
    final distances = await worker.distances(origin, {
      for (final f in located) f.id: f.location!,
    });
    sw.stop();
    final reachable = distances.values.whereType<Reachable>().length;
    debugPrint(
      'MEDIDA distancias_todas_ms=${sw.elapsedMilliseconds} destinos=${distances.length} alcancaveis=$reachable',
    );
    debugPrint(
      'MEDIDA ${jsonEncode({'nao_alcancaveis': distances.entries.where((e) => e.value is Unreachable).map((e) => e.key).toList()})}',
    );
    worker.dispose();
    expect(found, greaterThan(0));
  });
}
