import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../facilities/domain/facility.dart';
import '../domain/road_graph.dart';

const _metersPerDegree = 111320.0;

class MapMarker {
  const MapMarker(this.point, this.color, this.label);
  final GeoPoint point;
  final Color color;
  final String label;
}

/// Mapa esquemático das vias do pacote instalado: pan, zoom e toque.
/// Funciona sem rede; não usa tiles externos.
class RoadMapView extends StatefulWidget {
  const RoadMapView({
    required this.graph,
    this.center,
    this.markers = const [],
    this.route = const [],
    this.onTap,
    this.fitPoints,
    this.semanticLabel = 'Mapa das vias',
    super.key,
  });

  final RoadGraph graph;
  final GeoPoint? center;
  final List<MapMarker> markers;
  final List<GeoPoint> route;
  final ValueChanged<GeoPoint>? onTap;

  /// Enquadra estes pontos ao abrir.
  final List<GeoPoint>? fitPoints;
  final String semanticLabel;

  @override
  State<RoadMapView> createState() => _RoadMapViewState();
}

class _RoadMapViewState extends State<RoadMapView> {
  late GeoPoint _center = widget.center ?? widget.graph.bounds.center;
  double _metersPerPixel = 8;
  double _startMpp = 8;
  Offset _lastFocal = Offset.zero;
  bool _fitted = false;

  double get _cosLat => math.cos(_center.lat * math.pi / 180);

  Offset _toScreen(GeoPoint p, Size size) => Offset(
    size.width / 2 +
        (p.lon - _center.lon) * _cosLat * _metersPerDegree / _metersPerPixel,
    size.height / 2 -
        (p.lat - _center.lat) * _metersPerDegree / _metersPerPixel,
  );

  GeoPoint _toGeo(Offset o, Size size) => GeoPoint(
    _center.lat - (o.dy - size.height / 2) * _metersPerPixel / _metersPerDegree,
    _center.lon +
        (o.dx - size.width / 2) *
            _metersPerPixel /
            (_cosLat * _metersPerDegree),
  );

  void _fit(Size size) {
    final points = widget.fitPoints;
    if (_fitted || points == null || points.isEmpty) return;
    _fitted = true;
    final lats = points.map((p) => p.lat), lons = points.map((p) => p.lon);
    final south = lats.reduce(math.min), north = lats.reduce(math.max);
    final west = lons.reduce(math.min), east = lons.reduce(math.max);
    _center = GeoPoint((south + north) / 2, (west + east) / 2);
    final heightM = (north - south) * _metersPerDegree;
    final widthM = (east - west) * _metersPerDegree * _cosLat;
    _metersPerPixel = math.max(
      2,
      // 60% da área: margem para rótulos dos marcadores e botões de zoom.
      math.max(heightM / (size.height * 0.6), widthM / (size.width * 0.6)),
    );
  }

  void _zoom(double factor) => setState(() {
    _metersPerPixel = (_metersPerPixel * factor).clamp(1.0, 400.0);
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        _fit(size);
        return Stack(
          children: [
            Semantics(
              label: widget.semanticLabel,
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    _zoom(event.scrollDelta.dy > 0 ? 1.2 : 1 / 1.2);
                  }
                },
                child: GestureDetector(
                  onScaleStart: (d) {
                    _startMpp = _metersPerPixel;
                    _lastFocal = d.localFocalPoint;
                  },
                  onScaleUpdate: (d) => setState(() {
                    final delta = d.localFocalPoint - _lastFocal;
                    _lastFocal = d.localFocalPoint;
                    _metersPerPixel = (_startMpp / d.scale).clamp(1.0, 400.0);
                    _center = GeoPoint(
                      _center.lat +
                          delta.dy * _metersPerPixel / _metersPerDegree,
                      _center.lon -
                          delta.dx *
                              _metersPerPixel /
                              (_cosLat * _metersPerDegree),
                    );
                  }),
                  onTapUp: widget.onTap == null
                      ? null
                      : (d) => widget.onTap!(_toGeo(d.localPosition, size)),
                  child: CustomPaint(
                    size: size,
                    painter: _RoadPainter(
                      graph: widget.graph,
                      toScreen: (p) => _toScreen(p, size),
                      toGeo: (o) => _toGeo(o, size),
                      metersPerPixel: _metersPerPixel,
                      markers: widget.markers,
                      route: widget.route,
                      scheme: scheme,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: Space.s8,
              top: Space.s8,
              child: Column(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Aproximar',
                    icon: const Icon(Icons.add),
                    onPressed: () => _zoom(1 / 1.6),
                  ),
                  const SizedBox(height: Space.s4),
                  IconButton.filledTonal(
                    tooltip: 'Afastar',
                    icon: const Icon(Icons.remove),
                    onPressed: () => _zoom(1.6),
                  ),
                ],
              ),
            ),
            Positioned(
              left: Space.s4,
              bottom: Space.s4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                color: scheme.surface.withValues(alpha: 0.85),
                child: Text(
                  '© colaboradores do OpenStreetMap (ODbL)',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RoadPainter extends CustomPainter {
  _RoadPainter({
    required this.graph,
    required this.toScreen,
    required this.toGeo,
    required this.metersPerPixel,
    required this.markers,
    required this.route,
    required this.scheme,
  });

  final RoadGraph graph;
  final Offset Function(GeoPoint) toScreen;
  final GeoPoint Function(Offset) toGeo;
  final double metersPerPixel;
  final List<MapMarker> markers;
  final List<GeoPoint> route;
  final ColorScheme scheme;

  /// Nível de detalhe: vias menores só aparecem com zoom próximo.
  int get _maxClass {
    if (metersPerPixel > 80) return 1;
    if (metersPerPixel > 30) return 3;
    if (metersPerPixel > 12) return 4;
    return 6;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = scheme.surfaceContainerLow,
    );
    final topLeft = toGeo(Offset.zero);
    final bottomRight = toGeo(Offset(size.width, size.height));
    final box = GeoBounds(
      bottomRight.lat,
      topLeft.lon,
      topLeft.lat,
      bottomRight.lon,
    );

    final paths = List.generate(7, (_) => Path());
    final maxClass = _maxClass;
    for (final e in graph.index.edgesIn(box)) {
      final cls = graph.classes[e];
      if (cls > maxClass) continue;
      final a = toScreen(graph.point(graph.source(e)));
      final b = toScreen(graph.point(graph.targets[e]));
      paths[cls]
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy);
    }
    for (var cls = 6; cls >= 0; cls--) {
      canvas.drawPath(
        paths[cls],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..color = cls <= 1
              ? scheme.outline
              : cls <= 3
              ? scheme.outline.withValues(alpha: 0.8)
              : scheme.outlineVariant
          ..strokeWidth = switch (cls) {
            0 => 4,
            1 => 3.5,
            2 || 3 => 2.5,
            6 => 1,
            _ => 1.5,
          },
      );
    }

    if (route.length >= 2) {
      final path = Path();
      final first = toScreen(route.first);
      path.moveTo(first.dx, first.dy);
      for (final p in route.skip(1)) {
        final o = toScreen(p);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round
          ..color = scheme.primary,
      );
    }

    // Círculos primeiro, rótulos depois (por cima de tudo); um rótulo que
    // colidiria com outro já desenhado desce abaixo dele.
    for (final m in markers) {
      final o = toScreen(m.point);
      canvas.drawCircle(o, 11, Paint()..color = scheme.surface);
      canvas.drawCircle(o, 8, Paint()..color = m.color);
    }
    final placed = <Rect>[];
    for (final m in markers) {
      final text = TextPainter(
        text: TextSpan(
          text: m.label,
          style: TextStyle(
            color: scheme.onSurface,
            backgroundColor: scheme.surface.withValues(alpha: 0.85),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 200);
      var rect = (toScreen(m.point) + const Offset(14, -8)) & text.size;
      for (var i = 0; i < 4 && placed.any(rect.overlaps); i++) {
        rect = rect.translate(0, text.height + 2);
      }
      placed.add(rect);
      text.paint(canvas, rect.topLeft);
    }
  }

  @override
  bool shouldRepaint(_RoadPainter old) =>
      old.metersPerPixel != metersPerPixel ||
      old.toScreen != toScreen ||
      old.markers != markers ||
      old.route != route ||
      old.scheme != scheme;
}
