import 'dart:typed_data';

import '../../facilities/domain/facility.dart';
import '../../search/domain/ranking.dart';
import 'road_graph.dart';

enum RouteFailureReason {
  originOutOfCoverage,
  originFarFromRoad,
  destinationOutOfCoverage,
  destinationFarFromRoad,
  noPath,
}

extension RouteFailureText on RouteFailureReason {
  String get message => switch (this) {
    RouteFailureReason.originOutOfCoverage =>
      'Origem fora da cobertura instalada',
    RouteFailureReason.originFarFromRoad => 'Origem longe de via mapeada',
    RouteFailureReason.destinationOutOfCoverage =>
      'Rota indisponível nesta cobertura',
    RouteFailureReason.destinationFarFromRoad => 'Unidade longe de via mapeada',
    RouteFailureReason.noPath => 'Sem caminho viário na malha instalada',
  };
}

class RoutePlan {
  const RoutePlan({
    required this.distanceMeters,
    required this.geometry,
    required this.originSnapMeters,
    required this.destinationSnapMeters,
  });

  /// Distância percorrida sobre a malha, entre os pontos projetados nas vias.
  final double distanceMeters;
  final List<GeoPoint> geometry;
  final double originSnapMeters;
  final double destinationSnapMeters;
}

sealed class RouteOutcome {
  const RouteOutcome();
}

class RouteFound extends RouteOutcome {
  const RouteFound(this.plan);
  final RoutePlan plan;
}

class RouteFailure extends RouteOutcome {
  const RouteFailure(this.reason);
  final RouteFailureReason reason;
}

/// Roteamento local por Dijkstra (menor distância, perfil automóvel).
/// Não faz nenhuma chamada de rede: usa apenas o grafo instalado.
class OfflineRouter {
  OfflineRouter(this.graph, {this.maxSnapMeters = 500});

  final RoadGraph graph;
  final double maxSnapMeters;

  RouteFailureReason? _snapFailure(
    GeoPoint p,
    SegmentSnap? snap, {
    required bool origin,
  }) {
    if (snap != null) return null;
    if (!graph.bounds.contains(p)) {
      return origin
          ? RouteFailureReason.originOutOfCoverage
          : RouteFailureReason.destinationOutOfCoverage;
    }
    return origin
        ? RouteFailureReason.originFarFromRoad
        : RouteFailureReason.destinationFarFromRoad;
  }

  RouteOutcome route(GeoPoint origin, GeoPoint destination) {
    final o = graph.index.nearest(origin, maxMeters: maxSnapMeters);
    final originFailure = _snapFailure(origin, o, origin: true);
    if (originFailure != null) return RouteFailure(originFailure);
    final d = graph.index.nearest(destination, maxMeters: maxSnapMeters);
    final destinationFailure = _snapFailure(destination, d, origin: false);
    if (destinationFailure != null) return RouteFailure(destinationFailure);

    final search = _Search(graph)
      ..run(_seeds(o!), targets: _arrivals(d!).map((a) => a.node).toSet());
    final best = _bestArrival(search, o, d);
    if (best == null) return const RouteFailure(RouteFailureReason.noPath);

    final geometry = <GeoPoint>[o.point];
    if (best.node >= 0) {
      final nodes = <int>[];
      for (var n = best.node; n >= 0; n = search.previous[n]) {
        nodes.add(n);
      }
      geometry.addAll(nodes.reversed.map(graph.point));
    }
    geometry.add(d.point);
    return RouteFound(
      RoutePlan(
        distanceMeters: best.cost,
        geometry: geometry,
        originSnapMeters: o.distanceMeters,
        destinationSnapMeters: d.distanceMeters,
      ),
    );
  }

  /// Distância viária da origem a cada destino, numa única busca.
  /// Destinos sem via próxima ou sem caminho recebem [Unreachable].
  Map<String, RoadDistance> distances(
    GeoPoint origin,
    Map<String, GeoPoint> destinations,
  ) {
    final o = graph.index.nearest(origin, maxMeters: maxSnapMeters);
    final originFailure = _snapFailure(origin, o, origin: true);
    if (originFailure != null) {
      return {
        for (final id in destinations.keys)
          id: Unreachable(originFailure.message),
      };
    }
    final result = <String, RoadDistance>{};
    final snaps = <String, SegmentSnap>{};
    final targets = <int>{};
    destinations.forEach((id, point) {
      final snap = graph.index.nearest(point, maxMeters: maxSnapMeters);
      final failure = _snapFailure(point, snap, origin: false);
      if (failure != null) {
        result[id] = Unreachable(failure.message);
      } else {
        snaps[id] = snap!;
        targets.addAll(_arrivals(snap).map((a) => a.node));
      }
    });
    final search = _Search(graph)..run(_seeds(o!), targets: targets);
    snaps.forEach((id, snap) {
      final best = _bestArrival(search, o, snap);
      result[id] = best == null
          ? Unreachable(RouteFailureReason.noPath.message)
          : Reachable(best.cost);
    });
    return result;
  }

  double _edgeLength(int a, int b) {
    final e = graph.edgeBetween(a, b);
    return e < 0 ? -1 : graph.lengths[e];
  }

  /// Nós alcançáveis a partir do ponto projetado, respeitando sentido único.
  List<_Cost> _seeds(SegmentSnap s) {
    final seeds = <_Cost>[];
    final ab = _edgeLength(s.nodeA, s.nodeB);
    if (ab >= 0) seeds.add(_Cost(s.nodeB, (1 - s.t) * ab));
    final ba = _edgeLength(s.nodeB, s.nodeA);
    if (ba >= 0) seeds.add(_Cost(s.nodeA, s.t * ba));
    return seeds;
  }

  /// Nós a partir dos quais se chega ao ponto projetado, com custo restante.
  List<_Cost> _arrivals(SegmentSnap s) {
    final arrivals = <_Cost>[];
    final ab = _edgeLength(s.nodeA, s.nodeB);
    if (ab >= 0) arrivals.add(_Cost(s.nodeA, s.t * ab));
    final ba = _edgeLength(s.nodeB, s.nodeA);
    if (ba >= 0) arrivals.add(_Cost(s.nodeB, (1 - s.t) * ba));
    return arrivals;
  }

  /// Melhor chegada; `node == -1` indica trajeto direto no mesmo segmento.
  _Cost? _bestArrival(_Search search, SegmentSnap o, SegmentSnap d) {
    _Cost? best;
    for (final a in _arrivals(d)) {
      final base = search.distance[a.node];
      if (base.isInfinite) continue;
      final cost = base + a.cost;
      if (best == null || cost < best.cost) best = _Cost(a.node, cost);
    }
    final direct = _sameSegment(o, d);
    if (direct != null && (best == null || direct < best.cost)) {
      best = _Cost(-1, direct);
    }
    return best;
  }

  double? _sameSegment(SegmentSnap o, SegmentSnap d) {
    double? tD;
    if (o.nodeA == d.nodeA && o.nodeB == d.nodeB) tD = d.t;
    if (o.nodeA == d.nodeB && o.nodeB == d.nodeA) tD = 1 - d.t;
    if (tD == null) return null;
    final ab = _edgeLength(o.nodeA, o.nodeB);
    if (ab >= 0 && tD >= o.t) return (tD - o.t) * ab;
    final ba = _edgeLength(o.nodeB, o.nodeA);
    if (ba >= 0 && tD <= o.t) return (o.t - tD) * ba;
    return null;
  }
}

class _Cost {
  const _Cost(this.node, this.cost);
  final int node;
  final double cost;
}

class _Search {
  _Search(this.graph)
    : distance = Float64List(graph.nodeCount)
        ..fillRange(0, graph.nodeCount, double.infinity),
      previous = Int32List(graph.nodeCount)..fillRange(0, graph.nodeCount, -1);

  final RoadGraph graph;
  final Float64List distance;
  final Int32List previous;

  void run(List<_Cost> seeds, {required Set<int> targets}) {
    final heap = _MinHeap();
    for (final s in seeds) {
      if (s.cost < distance[s.node]) {
        distance[s.node] = s.cost;
        previous[s.node] = -1;
        heap.push(s.cost, s.node);
      }
    }
    final pending = {...targets};
    final settled = Uint8List(graph.nodeCount);
    while (heap.isNotEmpty && pending.isNotEmpty) {
      final cost = heap.peekKey;
      final node = heap.pop();
      if (settled[node] == 1 || cost > distance[node]) continue;
      settled[node] = 1;
      pending.remove(node);
      for (var e = graph.offsets[node]; e < graph.offsets[node + 1]; e++) {
        final next = graph.targets[e];
        final candidate = cost + graph.lengths[e];
        if (candidate < distance[next]) {
          distance[next] = candidate;
          previous[next] = node;
          heap.push(candidate, next);
        }
      }
    }
  }
}

/// Heap binária mínima com remoção preguiçosa.
class _MinHeap {
  final _keys = <double>[];
  final _values = <int>[];

  bool get isNotEmpty => _keys.isNotEmpty;
  double get peekKey => _keys.first;

  void push(double key, int value) {
    _keys.add(key);
    _values.add(value);
    var i = _keys.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_keys[parent] <= key) break;
      _keys[i] = _keys[parent];
      _values[i] = _values[parent];
      i = parent;
    }
    _keys[i] = key;
    _values[i] = value;
  }

  int pop() {
    final top = _values.first;
    final lastKey = _keys.removeLast();
    final lastValue = _values.removeLast();
    if (_keys.isNotEmpty) {
      var i = 0;
      final n = _keys.length;
      while (true) {
        final left = 2 * i + 1;
        if (left >= n) break;
        final right = left + 1;
        final child = right < n && _keys[right] < _keys[left] ? right : left;
        if (_keys[child] >= lastKey) break;
        _keys[i] = _keys[child];
        _values[i] = _values[child];
        i = child;
      }
      _keys[i] = lastKey;
      _values[i] = lastValue;
    }
    return top;
  }
}
