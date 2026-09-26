import 'dart:convert';

import '../domain/facility.dart';

/// Versão de esquema de catálogo que este app sabe ler.
const supportedCatalogSchema = 1;

/// Limite de registros aceito em um snapshot (proteção contra payload excessivo).
const maxCatalogFacilities = 20000;

class CatalogFormatException implements Exception {
  CatalogFormatException(this.message);
  final String message;

  @override
  String toString() => 'Catálogo inválido: $message';
}

/// Decodifica e valida um snapshot completo. Qualquer inconsistência rejeita
/// o snapshot inteiro; nunca aplica catálogo parcialmente válido.
Catalog decodeCatalog(String jsonText) {
  final Object? root;
  try {
    root = jsonDecode(jsonText);
  } on FormatException catch (e) {
    throw CatalogFormatException('JSON malformado (${e.message})');
  }
  try {
    return _CatalogReader().read(_map(root, 'raiz'));
  } on CatalogFormatException {
    rethrow;
  } on FormatException catch (e) {
    throw CatalogFormatException(e.message);
  } on TypeError catch (e) {
    throw CatalogFormatException('tipo inesperado ($e)');
  }
}

Map<String, Object?> _map(Object? v, String where) {
  if (v is Map<String, Object?>) return v;
  throw CatalogFormatException('$where deveria ser objeto');
}

List<Object?> _list(Object? v, String where) {
  if (v is List<Object?>) return v;
  throw CatalogFormatException('$where deveria ser lista');
}

String _str(Map<String, Object?> m, String key, String where) {
  final v = m[key];
  if (v is String && v.trim().isNotEmpty) return v;
  throw CatalogFormatException('$where.$key obrigatório');
}

String? _optStr(Map<String, Object?> m, String key) {
  final v = m[key];
  if (v == null) return null;
  if (v is String) return v.trim().isEmpty ? null : v;
  throw CatalogFormatException('$key deveria ser texto');
}

DateTime _date(Map<String, Object?> m, String key, String where) {
  final parsed = DateTime.tryParse(_str(m, key, where));
  if (parsed == null) throw CatalogFormatException('$where.$key data inválida');
  return parsed.toUtc();
}

DateTime? _optDate(Map<String, Object?> m, String key) {
  final v = _optStr(m, key);
  if (v == null) return null;
  final parsed = DateTime.tryParse(v);
  if (parsed == null) throw CatalogFormatException('$key data inválida');
  return parsed.toUtc();
}

class _CatalogReader {
  final _serviceIds = <String>{};
  final _specialtyIds = <String>{};
  final _planIds = <String>{};
  final _sourceIds = <String>{};

  Catalog read(Map<String, Object?> root) {
    final schema = root['schema_version'];
    if (schema is! int) throw CatalogFormatException('schema_version ausente');
    if (schema != supportedCatalogSchema) {
      throw CatalogFormatException('schema_version $schema não suportado');
    }

    final sources = [
      for (final (i, s) in _list(root['sources'], 'sources').indexed)
        _source(_map(s, 'sources[$i]')),
    ];
    final services = [
      for (final (i, s) in _list(root['services'], 'services').indexed)
        _service(_map(s, 'services[$i]')),
    ];
    final specialties = [
      for (final (i, s) in _list(root['specialties'], 'specialties').indexed)
        _specialty(_map(s, 'specialties[$i]')),
    ];
    final plans = [
      for (final (i, s) in _list(root['plans'], 'plans').indexed)
        _plan(_map(s, 'plans[$i]')),
    ];
    final rawFacilities = _list(root['facilities'], 'facilities');
    if (rawFacilities.length > maxCatalogFacilities) {
      throw CatalogFormatException('excesso de registros');
    }
    final ids = <String>{};
    final facilities = <Facility>[];
    for (final (i, raw) in rawFacilities.indexed) {
      final f = _facility(_map(raw, 'facilities[$i]'), 'facilities[$i]');
      if (!ids.add(f.id)) throw CatalogFormatException('ID duplicado ${f.id}');
      facilities.add(f);
    }

    final coverage = _map(root['coverage'], 'coverage');
    return Catalog(
      schemaVersion: schema,
      version: _str(root, 'catalog_version', 'raiz'),
      generatedAt: _date(root, 'generated_at', 'raiz'),
      coverage: CatalogCoverage(
        municipality: _str(coverage, 'municipality', 'coverage'),
        eligibleIdentified: coverage['eligible_identified'] as int,
        published: coverage['published'] as int,
        reviewed: coverage['reviewed'] as int,
        note: _optStr(coverage, 'note'),
      ),
      sources: sources,
      services: services,
      specialties: specialties,
      plans: plans,
      facilities: facilities,
    );
  }

  Source _source(Map<String, Object?> m) {
    final id = _str(m, 'id', 'source');
    if (!_sourceIds.add(id)) {
      throw CatalogFormatException('fonte duplicada $id');
    }
    return Source(
      id: id,
      type: _str(m, 'type', 'source'),
      name: _str(m, 'name', 'source'),
      reference: _str(m, 'reference', 'source'),
      consultedAt: _date(m, 'consulted_at', 'source'),
    );
  }

  Service _service(Map<String, Object?> m) {
    final id = _str(m, 'id', 'service');
    if (!_serviceIds.add(id)) {
      throw CatalogFormatException('serviço duplicado $id');
    }
    return Service(
      id: id,
      name: _str(m, 'name', 'service'),
      category: _str(m, 'category', 'service'),
      synonyms: [
        for (final s in _list(m['synonyms'] ?? [], 'synonyms')) s as String,
      ],
    );
  }

  Specialty _specialty(Map<String, Object?> m) {
    final id = _str(m, 'id', 'specialty');
    if (!_specialtyIds.add(id)) {
      throw CatalogFormatException('especialidade duplicada $id');
    }
    return Specialty(id: id, name: _str(m, 'name', 'specialty'));
  }

  HealthPlan _plan(Map<String, Object?> m) {
    final id = _str(m, 'id', 'plan');
    if (!_planIds.add(id)) throw CatalogFormatException('plano duplicado $id');
    return HealthPlan(
      id: id,
      name: _str(m, 'name', 'plan'),
      operator: _optStr(m, 'operator'),
    );
  }

  String? _sourceRef(Map<String, Object?> m, String where) {
    final id = _optStr(m, 'source_id');
    if (id != null && !_sourceIds.contains(id)) {
      throw CatalogFormatException('$where referencia fonte inexistente $id');
    }
    return id;
  }

  String? _serviceRef(Map<String, Object?> m, String where) {
    final id = _optStr(m, 'service_id');
    if (id != null && !_serviceIds.contains(id)) {
      throw CatalogFormatException('$where referencia serviço inexistente $id');
    }
    return id;
  }

  Facility _facility(Map<String, Object?> m, String where) {
    final id = _str(m, 'id', where);
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{1,63}$').hasMatch(id)) {
      throw CatalogFormatException('$where ID inválido');
    }
    if (_str(m, 'status', where) != 'active') {
      throw CatalogFormatException(
        '$where: snapshot publica apenas unidades ativas',
      );
    }
    final address = _map(m['address'], '$where.address');
    final rawLocation = m['location'];
    GeoPoint? location;
    if (rawLocation != null) {
      final loc = _map(rawLocation, '$where.location');
      location = GeoPoint(
        (loc['lat'] as num).toDouble(),
        (loc['lon'] as num).toDouble(),
      );
      if (!location.isValid) {
        throw CatalogFormatException('$where coordenada inválida');
      }
    }
    final phone = _optStr(m, 'phone');
    if (phone != null && !RegExp(r'^\d{10,11}$').hasMatch(phone)) {
      throw CatalogFormatException('$where telefone fora do formato');
    }
    final type = m['facility_type'];
    final provenance = [
      for (final (i, p) in _list(m['provenance'], '$where.provenance').indexed)
        _provenance(_map(p, '$where.provenance[$i]'), '$where.provenance[$i]'),
    ];
    if (provenance.isEmpty) {
      throw CatalogFormatException('$where sem proveniência');
    }

    return Facility(
      id: id,
      cnes: _optStr(m, 'cnes'),
      name: _str(m, 'name', where),
      legalName: _optStr(m, 'legal_name'),
      nature: AdministrativeNature.parse(m['administrative_nature']),
      susAccess: TriState.parse(m['sus_access']),
      reviewStatus: ReviewStatus.parse(m['review_status']),
      facilityType: type == null
          ? null
          : FacilityType(
              code: _map(type, 'facility_type')['code'] as int,
              name: _str(_map(type, 'facility_type'), 'name', where),
            ),
      address: Address(
        street: _str(address, 'street', '$where.address'),
        number: _optStr(address, 'number'),
        complement: _optStr(address, 'complement'),
        locality: _optStr(address, 'locality'),
        postalCode: _optStr(address, 'postal_code'),
        city: _str(address, 'city', '$where.address'),
        state: _str(address, 'state', '$where.address'),
      ),
      phone: phone,
      location: location,
      is24h: TriState.parse(m['is_24h']),
      hoursDescription: _optStr(m, 'hours_description'),
      accessInstructions: _optStr(m, 'access_instructions'),
      services: [
        for (final (i, s) in _list(m['services'], '$where.services').indexed)
          _facilityService(
            _map(s, '$where.services[$i]'),
            '$where.services[$i]',
          ),
      ],
      specialties: [
        for (final (i, s) in _list(
          m['specialties'],
          '$where.specialties',
        ).indexed)
          _facilitySpecialty(
            _map(s, '$where.specialties[$i]'),
            '$where.specialties[$i]',
          ),
      ],
      planAcceptance: [
        for (final (i, p) in _list(
          m['plan_acceptance'],
          '$where.plan_acceptance',
        ).indexed)
          _planAcceptance(
            _map(p, '$where.plan_acceptance[$i]'),
            '$where.plan_acceptance[$i]',
          ),
      ],
      provenance: provenance,
      verifiedAt: _optDate(m, 'verified_at'),
      notes: [
        for (final n in _list(m['notes'] ?? [], '$where.notes')) n as String,
      ],
    );
  }

  FacilityService _facilityService(Map<String, Object?> m, String where) {
    final serviceId = _serviceRef(m, where);
    if (serviceId == null) {
      throw CatalogFormatException('$where.service_id obrigatório');
    }
    return FacilityService(
      serviceId: serviceId,
      availability: TriState.parse(m['availability']),
      is24h: TriState.parse(m['is_24h']),
      sourceId: _sourceRef(m, where),
      verifiedAt: _optDate(m, 'verified_at'),
    );
  }

  FacilitySpecialty _facilitySpecialty(Map<String, Object?> m, String where) {
    final id = _str(m, 'specialty_id', where);
    if (!_specialtyIds.contains(id)) {
      throw CatalogFormatException(
        '$where referencia especialidade inexistente $id',
      );
    }
    return FacilitySpecialty(
      specialtyId: id,
      availability: TriState.parse(m['availability']),
      serviceId: _serviceRef(m, where),
      sourceId: _sourceRef(m, where),
      verifiedAt: _optDate(m, 'verified_at'),
    );
  }

  PlanAcceptance _planAcceptance(Map<String, Object?> m, String where) {
    final id = _str(m, 'plan_id', where);
    if (!_planIds.contains(id)) {
      throw CatalogFormatException('$where referencia plano inexistente $id');
    }
    return PlanAcceptance(
      planId: id,
      accepted: TriState.parse(m['accepted']),
      serviceId: _serviceRef(m, where),
      conditions: _optStr(m, 'conditions'),
      sourceId: _sourceRef(m, where),
      verifiedAt: _optDate(m, 'verified_at'),
    );
  }

  Provenance _provenance(Map<String, Object?> m, String where) {
    final sourceId = _sourceRef(m, where);
    if (sourceId == null) {
      throw CatalogFormatException('$where.source_id obrigatório');
    }
    return Provenance(
      field: _str(m, 'field', where),
      sourceId: sourceId,
      consultedAt: _date(m, 'consulted_at', where),
      method: _str(m, 'method', where),
      sourceUpdatedAt: _optStr(m, 'source_updated_at'),
    );
  }
}
