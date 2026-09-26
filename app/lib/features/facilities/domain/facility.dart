/// Modelo de domínio do catálogo. Dart puro: sem Flutter, SQLite ou HTTP.
library;

/// Valor triestado: desconhecido não equivale a falso nem a confirmado.
enum TriState {
  yes,
  no,
  unknown;

  static TriState parse(Object? value) => switch (value) {
    'yes' => TriState.yes,
    'no' => TriState.no,
    null || 'unknown' => TriState.unknown,
    _ => throw FormatException('valor triestado inválido: $value'),
  };
}

enum AdministrativeNature {
  public,
  private,
  unknown;

  static AdministrativeNature parse(Object? value) => switch (value) {
    'public' => AdministrativeNature.public,
    'private' => AdministrativeNature.private,
    null || 'unknown' => AdministrativeNature.unknown,
    _ => throw FormatException('natureza inválida: $value'),
  };
}

enum ReviewStatus {
  /// Importado de fonte, ainda sem conferência da curadoria.
  pending,

  /// Conferido pela curadoria.
  approved;

  static ReviewStatus parse(Object? value) => switch (value) {
    'pending' => ReviewStatus.pending,
    'approved' => ReviewStatus.approved,
    _ => throw FormatException('status de revisão inválido: $value'),
  };
}

/// Coordenada WGS84 em graus.
class GeoPoint {
  const GeoPoint(this.lat, this.lon);

  final double lat;
  final double lon;

  bool get isValid => lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'GeoPoint($lat, $lon)';
}

class Address {
  const Address({
    required this.street,
    required this.city,
    required this.state,
    this.number,
    this.complement,
    this.locality,
    this.postalCode,
  });

  final String street;
  final String? number;
  final String? complement;
  final String? locality;
  final String? postalCode;
  final String city;
  final String state;

  String get singleLine {
    final parts = <String>[
      [street, if (number != null) number].join(', '),
      ?complement,
      ?locality,
      '$city–$state',
    ];
    return parts.join(' · ');
  }
}

class Service {
  const Service({
    required this.id,
    required this.name,
    required this.category,
    this.synonyms = const [],
  });

  final String id;
  final String name;

  /// `atendimento` (tipo de cuidado) ou `estrutura` (recurso da unidade).
  final String category;
  final List<String> synonyms;
}

class Specialty {
  const Specialty({required this.id, required this.name});

  final String id;
  final String name;
}

class HealthPlan {
  const HealthPlan({required this.id, required this.name, this.operator});

  final String id;
  final String name;
  final String? operator;
}

/// Oferta de um serviço por uma unidade. `is24h` pertence ao serviço, não à unidade.
class FacilityService {
  const FacilityService({
    required this.serviceId,
    required this.availability,
    required this.is24h,
    this.sourceId,
    this.verifiedAt,
  });

  final String serviceId;
  final TriState availability;
  final TriState is24h;
  final String? sourceId;
  final DateTime? verifiedAt;
}

class FacilitySpecialty {
  const FacilitySpecialty({
    required this.specialtyId,
    required this.availability,
    this.serviceId,
    this.sourceId,
    this.verifiedAt,
  });

  final String specialtyId;
  final TriState availability;
  final String? serviceId;
  final String? sourceId;
  final DateTime? verifiedAt;
}

class PlanAcceptance {
  const PlanAcceptance({
    required this.planId,
    required this.accepted,
    this.serviceId,
    this.conditions,
    this.sourceId,
    this.verifiedAt,
  });

  final String planId;
  final TriState accepted;

  /// Nulo quando a aceitação vale para a unidade inteira.
  final String? serviceId;
  final String? conditions;
  final String? sourceId;
  final DateTime? verifiedAt;
}

class Provenance {
  const Provenance({
    required this.field,
    required this.sourceId,
    required this.consultedAt,
    required this.method,
    this.sourceUpdatedAt,
  });

  final String field;
  final String sourceId;
  final DateTime consultedAt;
  final String method;
  final String? sourceUpdatedAt;
}

class Source {
  const Source({
    required this.id,
    required this.type,
    required this.name,
    required this.reference,
    required this.consultedAt,
  });

  final String id;
  final String type;
  final String name;
  final String reference;
  final DateTime consultedAt;
}

class FacilityType {
  const FacilityType({required this.code, required this.name});

  final int code;
  final String name;
}

class Facility {
  const Facility({
    required this.id,
    required this.name,
    required this.nature,
    required this.susAccess,
    required this.reviewStatus,
    required this.address,
    required this.is24h,
    required this.services,
    required this.provenance,
    this.cnes,
    this.legalName,
    this.facilityType,
    this.phone,
    this.location,
    this.hoursDescription,
    this.accessInstructions,
    this.specialties = const [],
    this.planAcceptance = const [],
    this.verifiedAt,
    this.notes = const [],
  });

  final String id;
  final String? cnes;
  final String name;
  final String? legalName;
  final AdministrativeNature nature;

  /// Canal de acesso pelo SUS; independente da natureza administrativa.
  final TriState susAccess;
  final ReviewStatus reviewStatus;
  final FacilityType? facilityType;
  final Address address;

  /// Somente dígitos, com DDD.
  final String? phone;

  /// Nulo: a unidade aparece no catálogo, mas não pode gerar rota.
  final GeoPoint? location;

  /// Funcionamento 24h da unidade como um todo.
  final TriState is24h;
  final String? hoursDescription;
  final String? accessInstructions;
  final List<FacilityService> services;
  final List<FacilitySpecialty> specialties;
  final List<PlanAcceptance> planAcceptance;
  final List<Provenance> provenance;
  final DateTime? verifiedAt;
  final List<String> notes;
}

class CatalogCoverage {
  const CatalogCoverage({
    required this.municipality,
    required this.eligibleIdentified,
    required this.published,
    required this.reviewed,
    this.note,
  });

  final String municipality;
  final int eligibleIdentified;
  final int published;
  final int reviewed;
  final String? note;
}

/// Snapshot completo e validado do catálogo.
class Catalog {
  Catalog({
    required this.schemaVersion,
    required this.version,
    required this.generatedAt,
    required this.coverage,
    required this.sources,
    required this.services,
    required this.specialties,
    required this.plans,
    required this.facilities,
  }) : _servicesById = {for (final s in services) s.id: s},
       _sourcesById = {for (final s in sources) s.id: s};

  final int schemaVersion;
  final String version;
  final DateTime generatedAt;
  final CatalogCoverage coverage;
  final List<Source> sources;
  final List<Service> services;
  final List<Specialty> specialties;
  final List<HealthPlan> plans;
  final List<Facility> facilities;
  final Map<String, Service> _servicesById;
  final Map<String, Source> _sourcesById;

  Service? service(String id) => _servicesById[id];
  Source? source(String id) => _sourcesById[id];
  String? specialtyName(String id) =>
      specialties.where((s) => s.id == id).firstOrNull?.name;
  String? planName(String id) =>
      plans.where((p) => p.id == id).firstOrNull?.name;
}
