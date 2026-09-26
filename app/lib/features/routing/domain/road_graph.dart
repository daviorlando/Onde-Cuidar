import 'dart:math' as math;
import 'dart:typed_data';

import '../../facilities/domain/facility.dart';

const roadGraphFormatVersion = 1;

class RoadGraphFormatException implements Exception {
  RoadGraphFormatException(this.message);
  final String message;

  @override
  String toString() => 'Pacote viário inválido: $message';
}

class GeoBounds {
  const GeoBounds(this.south, this.west, this.north, this.east);

  final double south;
  final double west;
  final double north;
  final double east;

  bool contains(GeoPoint p) =>
      p.lat >= south && p.lat <= north && p.lon >= west && p.lon <= east;

  GeoPoint get center => GeoPoint((south + north) / 2, (west + east) / 2);
}

/// Grafo viário dirigido em CSR, lido do formato OCRG v1 sem cópias.
class RoadGraph {
  RoadGraph._({
    required this.nodeCount,
    required this.edgeCount,
    required this.bounds,
    required this.latE7,
    required this.lonE7,
    required this.offsets,
    required this.targets,
    required this.lengths,
    required this.classes,
  });

  factory RoadGraph.fromBytes(Uint8List bytes) {
    if (bytes.length < 32) throw RoadGraphFormatException('arquivo curto');
    final data = ByteData.sublistView(bytes);
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'OCRG') {
      throw RoadGraphFormatException('assinatura ausente');
    }
    final version = data.getUint32(4, Endian.little);
    if (version != roadGraphFormatVersion) {
      throw RoadGraphFormatException('formato $version não suportado');
    }
    final n = data.getUint32(8, Endian.little);
    final m = data.getUint32(12, Endian.little);
    final expected = 32 + n * 4 * 2 + (n + 1) * 4 + m * 4 * 2 + m;
    if (bytes.length != expected) {
      throw RoadGraphFormatException('tamanho ${bytes.length} ≠ $expected');
    }
    double e7(int offset) => data.getInt32(offset, Endian.little) / 1e7;
    // Views exigem alinhamento de 4 bytes: copiar se o buffer não estiver alinhado.
    final aligned = bytes.offsetInBytes % 4 == 0
        ? bytes
        : Uint8List.fromList(bytes);
    final buffer = aligned.buffer;
    var offset = aligned.offsetInBytes + 32;
    Int32List i32(int count) {
      final view = buffer.asInt32List(offset, count);
      offset += count * 4;
      return view;
    }

    Uint32List u32(int count) {
      final view = buffer.asUint32List(offset, count);
      offset += count * 4;
      return view;
    }

    final lat = i32(n);
    final lon = i32(n);
    final offsets = u32(n + 1);
    final targets = u32(m);
    final lengths = buffer.asFloat32List(offset, m);
    offset += m * 4;
    final classes = buffer.asUint8List(offset, m);

    if (offsets[0] != 0 || offsets[n] != m) {
      throw RoadGraphFormatException('índice de arestas inconsistente');
    }
    for (var i = 0; i < n; i++) {
      if (offsets[i] > offsets[i + 1]) {
        throw RoadGraphFormatException('offsets não monotônicos');
      }
    }
    for (var e = 0; e < m; e++) {
      if (targets[e] >= n || !(lengths[e] >= 0)) {
        throw RoadGraphFormatException('aresta $e inválida');
      }
    }
    return RoadGraph._(
      nodeCount: n,
      edgeCount: m,
      bounds: GeoBounds(e7(16), e7(20), e7(24), e7(28)),
      latE7: lat,
      lonE7: lon,
      offsets: offsets,
      targets: targets,
      lengths: lengths,
      classes: classes,
    );
  }

  final int nodeCount;
  final int edgeCount;
  final GeoBounds bounds;
  final Int32List latE7;
  final Int32List lonE7;
  final Uint32List offsets;
  final Uint32List targets;
  final Float32List lengths;
  final Uint8List classes;

  late final Uint32List _sources = _computeSources();
  late final SegmentIndex index = SegmentIndex(this);

  double lat(int node) => latE7[node] / 1e7;
  double lon(int node) => lonE7[node] / 1e7;
  GeoPoint point(int node) => GeoPoint(lat(node), lon(node));

  int source(int edge) => _sources[edge];

  Uint32List _computeSources() {
    final s = Uint32List(edgeCount);
    for (var n = 0; n < nodeCount; n++) {
      for (var e = offsets[n]; e < offsets[n + 1]; e++) {
        s[e] = n;
      }
    }
    return s;
  }

  /// Aresta dirigida a→b, ou -1.
  int edgeBetween(int a, int b) {
    for (var e = offsets[a]; e < offsets[a + 1]; e++) {
      if (targets[e] == b) return e;
    }
    return -1;
  }

  /// Aresta representante do segmento (uma por par de nós, para desenho e índice).
  bool isCanonical(int edge) {
    final a = source(edge);
    final b = targets[edge];
    return a < b || edgeBetween(b, a) < 0;
  }
}

/// Posição projetada sobre um segmento da malha.
class SegmentSnap {
  const SegmentSnap({
    required this.nodeA,
    required this.nodeB,
    required this.t,
    required this.distanceMeters,
    required this.point,
  });

  final int nodeA;
  final int nodeB;

  /// Fração do segmento a partir de A (0..1).
  final double t;

  /// Distância do ponto original até a via.
  final double distanceMeters;
  final GeoPoint point;
}

/// Grade uniforme de segmentos canônicos para vizinhança e desenho do mapa.
class SegmentIndex {
  SegmentIndex(this.graph) {
    final b = graph.bounds;
    cols = math.max(1, ((b.east - b.west) / cellDegrees).ceil());
    rows = math.max(1, ((b.north - b.south) / cellDegrees).ceil());
    final counts = Uint32List(cols * rows + 1);
    final canonical = <int>[];
    for (var e = 0; e < graph.edgeCount; e++) {
      if (!graph.isCanonical(e)) continue;
      canonical.add(e);
      _forCells(e, (cell) => counts[cell + 1]++);
    }
    for (var i = 0; i < cols * rows; i++) {
      counts[i + 1] += counts[i];
    }
    cellStart = counts;
    final fill = Uint32List.fromList(counts);
    cellEdges = Uint32List(counts[cols * rows]);
    for (final e in canonical) {
      _forCells(e, (cell) => cellEdges[fill[cell]++] = e);
    }
    canonicalEdgeCount = canonical.length;
  }

  static const cellDegrees = 0.01;
  final RoadGraph graph;
  late final int cols;
  late final int rows;
  late final Uint32List cellStart;
  late final Uint32List cellEdges;
  late final int canonicalEdgeCount;

  int _col(double lon) =>
      ((lon - graph.bounds.west) / cellDegrees).floor().clamp(0, cols - 1);
  int _row(double lat) =>
      ((lat - graph.bounds.south) / cellDegrees).floor().clamp(0, rows - 1);

  void _forCells(int edge, void Function(int cell) visit) {
    final a = graph.source(edge);
    final b = graph.targets[edge];
    final c0 = _col(math.min(graph.lon(a), graph.lon(b)));
    final c1 = _col(math.max(graph.lon(a), graph.lon(b)));
    final r0 = _row(math.min(graph.lat(a), graph.lat(b)));
    final r1 = _row(math.max(graph.lat(a), graph.lat(b)));
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        visit(r * cols + c);
      }
    }
  }

  /// Segmentos canônicos que podem intersectar a caixa. Pode repetir arestas.
  Iterable<int> edgesIn(GeoBounds box) sync* {
    final c0 = _col(box.west), c1 = _col(box.east);
    final r0 = _row(box.south), r1 = _row(box.north);
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        final cell = r * cols + c;
        for (var i = cellStart[cell]; i < cellStart[cell + 1]; i++) {
          yield cellEdges[i];
        }
      }
    }
  }

  /// Segmento mais próximo dentro de [maxMeters], ou nulo.
  SegmentSnap? nearest(GeoPoint p, {double maxMeters = 500}) {
    if (!graph.bounds.contains(p)) return null;
    final dLat = maxMeters / 111320;
    final cosLat = math.cos(p.lat * math.pi / 180);
    final dLon = maxMeters / (111320 * cosLat);
    final box = GeoBounds(
      p.lat - dLat,
      p.lon - dLon,
      p.lat + dLat,
      p.lon + dLon,
    );
    SegmentSnap? best;
    for (final e in edgesIn(box)) {
      final a = graph.source(e);
      final b = graph.targets[e];
      // Projeção equiretangular local; erro desprezível na escala de metros.
      final ax = (graph.lon(a) - p.lon) * cosLat * 111320;
      final ay = (graph.lat(a) - p.lat) * 111320;
      final bx = (graph.lon(b) - p.lon) * cosLat * 111320;
      final by = (graph.lat(b) - p.lat) * 111320;
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
      final px = ax + t * dx, py = ay + t * dy;
      final dist = math.sqrt(px * px + py * py);
      if (dist <= maxMeters && (best == null || dist < best.distanceMeters)) {
        best = SegmentSnap(
          nodeA: a,
          nodeB: b,
          t: t,
          distanceMeters: dist,
          point: GeoPoint(
            graph.lat(a) + t * (graph.lat(b) - graph.lat(a)),
            graph.lon(a) + t * (graph.lon(b) - graph.lon(a)),
          ),
        );
      }
    }
    return best;
  }
}
