import 'dart:math' as math;

import '../features/facilities/domain/facility.dart';

const earthRadiusMeters = 6371008.8;

double _rad(double deg) => deg * math.pi / 180;

/// Distância geodésica aproximada (haversine). Não é distância viária.
double haversineMeters(GeoPoint a, GeoPoint b) {
  final dLat = _rad(b.lat - a.lat);
  final dLon = _rad(b.lon - a.lon);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.lat)) *
          math.cos(_rad(b.lat)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusMeters * math.asin(math.min(1, math.sqrt(h)));
}
