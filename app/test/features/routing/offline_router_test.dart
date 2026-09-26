import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onde_cuidar/features/facilities/domain/facility.dart';
import 'package:onde_cuidar/features/routing/domain/offline_router.dart';
import 'package:onde_cuidar/features/routing/domain/road_graph.dart';
import 'package:onde_cuidar/features/search/domain/ranking.dart';

import '../../support/fixtures.dart';

// Malha sintética: 0 ↔ 1 → 2 (mão única), 2 ↔ 3 ↔ 1; ilha 4 ↔ 5 desconectada.
const nodes = [
  (-9.400, -40.500),
  (-9.400, -40.490),
  (-9.400, -40.480),
  (-9.410, -40.490),
  (-9.380, -40.470),
  (-9.380, -40.465),
];
const edges = [
  (0, 1),
  (1, 0),
  (1, 2),
  (2, 3),
  (3, 2),
  (3, 1),
  (1, 3),
  (4, 5),
  (5, 4),
];

void main() {
  final graph = RoadGraph.fromBytes(encodeGraph(nodes, edges));
  final router = OfflineRouter(graph);
  const nearNode1 = GeoPoint(-9.3999, -40.4900);
  const nearNode2 = GeoPoint(-9.3999, -40.4800);
  const nearNode0 = GeoPoint(-9.3999, -40.5000);
  const nearIsland = GeoPoint(-9.3801, -40.4675);

  test('lê o formato OCRG e rejeita arquivo adulterado', () {
    expect(graph.nodeCount, 6);
    expect(graph.edgeCount, edges.length);
    final bytes = encodeGraph(nodes, edges);
    expect(
      () => RoadGraph.fromBytes(bytes.sublist(0, bytes.length - 1)),
      throwsA(isA<RoadGraphFormatException>()),
    );
    final corrupted = Uint8List.fromList(bytes)..[0] = 0x58;
    expect(
      () => RoadGraph.fromBytes(corrupted),
      throwsA(isA<RoadGraphFormatException>()),
    );
  });

  test('respeita sentido único: 1→2 direto, 2→1 contorna por 3', () {
    final forward = router.route(nearNode1, nearNode2) as RouteFound;
    final backward = router.route(nearNode2, nearNode1) as RouteFound;
    final direct = metersBetween(nodes[1], nodes[2]);
    final detour =
        metersBetween(nodes[2], nodes[3]) + metersBetween(nodes[3], nodes[1]);
    expect(forward.plan.distanceMeters, closeTo(direct, 15));
    expect(backward.plan.distanceMeters, closeTo(detour, 15));
    // Geometria acompanha a malha: passa pelo nó 3.
    expect(backward.plan.geometry, contains(graph.point(3)));
  });

  test('CT11: grafo desconectado não gera rota nem distância', () {
    final outcome = router.route(nearNode0, nearIsland);
    expect((outcome as RouteFailure).reason, RouteFailureReason.noPath);
  });

  test('CT11: origem fora da cobertura e longe de via', () {
    expect(
      (router.route(
        const GeoPoint(-8.0, -39.0),
        nearNode1,
      ) as RouteFailure).reason,
      RouteFailureReason.originOutOfCoverage,
    );
    expect(
      (router.route(
        const GeoPoint(-9.3905, -40.500),
        nearNode1,
      ) as RouteFailure).reason,
      RouteFailureReason.originFarFromRoad,
    );
    expect(
      (router.route(
        nearNode1,
        const GeoPoint(-8.0, -39.0),
      ) as RouteFailure).reason,
      RouteFailureReason.destinationOutOfCoverage,
    );
  });

  test('origem e destino no mesmo segmento, no sentido permitido', () {
    const a = GeoPoint(-9.4001, -40.4880);
    const b = GeoPoint(-9.4001, -40.4820);
    final ab = router.route(a, b) as RouteFound;
    expect(ab.plan.distanceMeters, closeTo(0.006 * 111320 * 0.98657, 15));
    final ba = router.route(b, a) as RouteFound; // contramão: precisa contornar
    expect(ba.plan.distanceMeters, greaterThan(ab.plan.distanceMeters * 2));
  });

  test('um-para-muitos equivale às rotas individuais', () {
    final destinations = {
      'n1': nearNode1,
      'n0': nearNode0,
      'ilha': nearIsland,
      'fora': const GeoPoint(-8.0, -39.0),
    };
    final distances = router.distances(nearNode2, destinations);
    for (final id in ['n1', 'n0']) {
      final single = router.route(nearNode2, destinations[id]!) as RouteFound;
      expect(
        (distances[id] as Reachable).meters,
        closeTo(single.plan.distanceMeters, 0.001),
      );
    }
    expect(distances['ilha'], isA<Unreachable>());
    expect(distances['fora'], isA<Unreachable>());
  });

  test('origem inválida marca todos os destinos como não roteáveis', () {
    final distances = router.distances(const GeoPoint(-8.0, -39.0), {
      'n1': nearNode1,
    });
    expect(distances['n1'], isA<Unreachable>());
  });
}
