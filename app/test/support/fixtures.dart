// Dados SINTÉTICOS de teste. Não representam unidades reais de Petrolina.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:onde_cuidar/features/facilities/domain/facility.dart';

final testServices = [
  const Service(
    id: 'atencao-basica',
    name: 'Atenção básica',
    category: 'atendimento',
    synonyms: ['ubs'],
  ),
  const Service(
    id: 'urgencia',
    name: 'Urgência e emergência',
    category: 'atendimento',
    synonyms: ['upa'],
  ),
  const Service(
    id: 'cardiologia-amb',
    name: 'Ambulatório',
    category: 'atendimento',
  ),
];

Facility facility(
  String id, {
  String? name,
  AdministrativeNature nature = AdministrativeNature.public,
  TriState sus = TriState.yes,
  TriState is24h = TriState.no,
  List<FacilityService> services = const [],
  List<FacilitySpecialty> specialties = const [],
  List<PlanAcceptance> plans = const [],
  GeoPoint? location,
  String locality = 'Centro',
}) => Facility(
  id: id,
  name: name ?? 'Unidade $id',
  nature: nature,
  susAccess: sus,
  reviewStatus: ReviewStatus.pending,
  address: Address(
    street: 'Rua Sintética',
    locality: locality,
    city: 'Petrolina',
    state: 'PE',
  ),
  is24h: is24h,
  services: services,
  specialties: specialties,
  planAcceptance: plans,
  location: location,
  provenance: [
    Provenance(
      field: '*',
      sourceId: 'teste',
      consultedAt: DateTime.utc(2026),
      method: 'sintetico',
    ),
  ],
);

FacilityService offers(
  String serviceId, {
  TriState is24h = TriState.no,
  TriState availability = TriState.yes,
}) => FacilityService(
  serviceId: serviceId,
  availability: availability,
  is24h: is24h,
);

Catalog catalogOf(
  List<Facility> facilities, {
  List<HealthPlan> plans = const [],
  List<Specialty> specialties = const [],
}) => Catalog(
  schemaVersion: 1,
  version: '2026-01-01.1',
  generatedAt: DateTime.utc(2026),
  coverage: CatalogCoverage(
    municipality: 'Teste',
    eligibleIdentified: facilities.length,
    published: facilities.length,
    reviewed: 0,
  ),
  sources: [
    Source(
      id: 'teste',
      type: 'sintetico',
      name: 'Sintético',
      reference: '-',
      consultedAt: DateTime.utc(2026),
    ),
  ],
  services: testServices,
  specialties: specialties,
  plans: plans,
  facilities: facilities,
);

/// Catálogo JSON mínimo e válido (esquema v1) com unidades sintéticas.
Map<String, Object?> catalogJson({
  String version = '2026-01-01.1',
  int count = 2,
}) => {
  'schema_version': 1,
  'catalog_version': version,
  'generated_at': '2026-01-01T00:00:00Z',
  'coverage': {
    'municipality': 'Teste',
    'eligible_identified': count,
    'published': count,
    'reviewed': 0,
  },
  'sources': [
    {
      'id': 'teste',
      'type': 'sintetico',
      'name': 'Sintético',
      'reference': '-',
      'consulted_at': '2026-01-01T00:00:00Z',
    },
  ],
  'services': [
    {
      'id': 'atencao-basica',
      'name': 'Atenção básica',
      'category': 'atendimento',
      'synonyms': <String>[],
    },
  ],
  'specialties': <Object>[],
  'plans': <Object>[],
  'facilities': [
    for (var i = 0; i < count; i++)
      {
        'id': 'sint-$i',
        'name': 'UNIDADE SINTÉTICA $i',
        'administrative_nature': 'public',
        'sus_access': 'yes',
        'status': 'active',
        'review_status': 'pending',
        'address': {'street': 'Rua Sintética', 'city': 'Teste', 'state': 'PE'},
        'phone': null,
        'location': {'lat': -9.39 + i / 1000, 'lon': -40.5},
        'is_24h': 'unknown',
        'services': [
          {
            'service_id': 'atencao-basica',
            'availability': 'yes',
            'is_24h': 'unknown',
            'source_id': 'teste',
          },
        ],
        'specialties': <Object>[],
        'plan_acceptance': <Object>[],
        'provenance': [
          {
            'field': '*',
            'source_id': 'teste',
            'consulted_at': '2026-01-01T00:00:00Z',
            'method': 'sintetico',
          },
        ],
      },
  ],
};

String catalogText({String version = '2026-01-01.1', int count = 2}) =>
    jsonEncode(catalogJson(version: version, count: count));

/// Codifica um grafo OCRG v1 sintético. [edges]: (origem, destino); comprimento
/// calculado pela distância geodésica aproximada entre os nós.
Uint8List encodeGraph(
  List<(double, double)> nodes,
  List<(int, int)> edges, {
  List<double>? bbox,
}) {
  final sorted = [...edges]
    ..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  final n = nodes.length, m = sorted.length;
  final lats = nodes.map((p) => p.$1);
  final lons = nodes.map((p) => p.$2);
  final box =
      bbox ??
      [
        lats.reduce((a, b) => a < b ? a : b) - 0.01,
        lons.reduce((a, b) => a < b ? a : b) - 0.01,
        lats.reduce((a, b) => a > b ? a : b) + 0.01,
        lons.reduce((a, b) => a > b ? a : b) + 0.01,
      ];
  final data = ByteData(32 + n * 8 + (n + 1) * 4 + m * 8 + m);
  var o = 0;
  for (final c in 'OCRG'.codeUnits) {
    data.setUint8(o++, c);
  }
  void u32(int v) {
    data.setUint32(o, v, Endian.little);
    o += 4;
  }

  void i32(int v) {
    data.setInt32(o, v, Endian.little);
    o += 4;
  }

  u32(1);
  u32(n);
  u32(m);
  for (final v in box) {
    i32((v * 1e7).round());
  }
  for (final p in nodes) {
    i32((p.$1 * 1e7).round());
  }
  for (final p in nodes) {
    i32((p.$2 * 1e7).round());
  }
  final counts = List.filled(n + 1, 0);
  for (final e in sorted) {
    counts[e.$1 + 1]++;
  }
  for (var i = 0; i < n; i++) {
    counts[i + 1] += counts[i];
  }
  counts.forEach(u32);
  for (final e in sorted) {
    u32(e.$2);
  }
  for (final e in sorted) {
    data.setFloat32(o, metersBetween(nodes[e.$1], nodes[e.$2]), Endian.little);
    o += 4;
  }
  for (var i = 0; i < m; i++) {
    data.setUint8(o++, 4);
  }
  return data.buffer.asUint8List();
}

double metersBetween((double, double) a, (double, double) b) {
  const k = 111320.0;
  final dy = (b.$1 - a.$1) * k;
  final dx = (b.$2 - a.$2) * k * 0.98657; // cos(-9.4°)
  return math.sqrt(dx * dx + dy * dy);
}
