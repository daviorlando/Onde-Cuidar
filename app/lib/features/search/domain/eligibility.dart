import '../../../core/text.dart';
import '../../facilities/domain/facility.dart';
import 'search_criteria.dart';

/// Critério que pode ser removido para explicar uma combinação sem resultados.
enum CriterionKind { text, services, specialties, natures, sus, only24h, plans }

class RelaxationHint {
  const RelaxationHint(this.kind, this.resultCount);

  final CriterionKind kind;
  final int resultCount;
}

/// Aplica os critérios obrigatórios. Nunca relaxa filtros silenciosamente.
class EligibilityFilter {
  EligibilityFilter(this.catalog)
    : _searchText = {
        for (final f in catalog.facilities) f.id: _indexText(catalog, f),
      };

  final Catalog catalog;
  final Map<String, String> _searchText;

  static String _indexText(Catalog catalog, Facility f) {
    final parts = <String>[
      f.name,
      if (f.legalName != null) f.legalName!,
      if (f.facilityType != null) f.facilityType!.name,
      f.address.street,
      if (f.address.locality != null) f.address.locality!,
      for (final s in f.services)
        if (s.availability == TriState.yes) ...[
          catalog.service(s.serviceId)?.name ?? '',
          ...?catalog.service(s.serviceId)?.synonyms,
        ],
      for (final s in f.specialties)
        if (s.availability == TriState.yes)
          catalog.specialtyName(s.specialtyId) ?? '',
    ];
    return ' ${normalizeForSearch(parts.join(' '))} ';
  }

  List<Facility> apply(SearchCriteria criteria) =>
      catalog.facilities.where((f) => matches(f, criteria)).toList();

  bool matches(Facility f, SearchCriteria c) =>
      _matchesText(f, c.text) &&
      _matchesServices(f, c.serviceIds) &&
      _matchesSpecialties(f, c.specialtyIds) &&
      _matchesNature(f, c.natures) &&
      (!c.susOnly || f.susAccess == TriState.yes) &&
      (!c.only24h || _matches24h(f, c.serviceIds)) &&
      _matchesPlans(f, c.planIds, c.serviceIds);

  bool _matchesText(Facility f, String text) {
    final tokens = normalizeForSearch(text)
        .split(' ')
        .where((t) => t.isNotEmpty);
    final haystack = _searchText[f.id]!;
    return tokens.every(haystack.contains);
  }

  static bool _offers(Facility f, String serviceId) => f.services.any(
    (s) => s.serviceId == serviceId && s.availability == TriState.yes,
  );

  static bool _matchesServices(Facility f, Set<String> ids) =>
      ids.isEmpty || ids.any((id) => _offers(f, id));

  static bool _matchesSpecialties(Facility f, Set<String> ids) =>
      ids.isEmpty ||
      f.specialties.any(
        (s) => ids.contains(s.specialtyId) && s.availability == TriState.yes,
      );

  static bool _matchesNature(Facility f, Set<AdministrativeNature> natures) =>
      natures.isEmpty ||
      (f.nature != AdministrativeNature.unknown && natures.contains(f.nature));

  /// Com serviço selecionado, o próprio serviço precisa ser 24h confirmado:
  /// unidade 24h não implica todos os serviços 24h.
  static bool _matches24h(Facility f, Set<String> serviceIds) {
    if (serviceIds.isNotEmpty) {
      return f.services.any(
        (s) =>
            serviceIds.contains(s.serviceId) &&
            s.availability == TriState.yes &&
            s.is24h == TriState.yes,
      );
    }
    return f.is24h == TriState.yes ||
        f.services.any(
          (s) => s.availability == TriState.yes && s.is24h == TriState.yes,
        );
  }

  /// Plano confirmado para a unidade inteira ou para um serviço selecionado.
  static bool _matchesPlans(
    Facility f,
    Set<String> planIds,
    Set<String> serviceIds,
  ) =>
      planIds.isEmpty ||
      f.planAcceptance.any(
        (p) =>
            planIds.contains(p.planId) &&
            p.accepted == TriState.yes &&
            (p.serviceId == null ||
                serviceIds.isEmpty ||
                serviceIds.contains(p.serviceId)),
      );

  /// Para combinação vazia: quantos resultados surgiriam removendo cada critério.
  List<RelaxationHint> relaxationHints(SearchCriteria c) {
    final candidates = <CriterionKind, SearchCriteria>{
      if (c.text.trim().isNotEmpty) CriterionKind.text: c.copyWith(text: ''),
      if (c.serviceIds.isNotEmpty)
        CriterionKind.services: c.copyWith(serviceIds: {}),
      if (c.specialtyIds.isNotEmpty)
        CriterionKind.specialties: c.copyWith(specialtyIds: {}),
      if (c.natures.isNotEmpty) CriterionKind.natures: c.copyWith(natures: {}),
      if (c.susOnly) CriterionKind.sus: c.copyWith(susOnly: false),
      if (c.only24h) CriterionKind.only24h: c.copyWith(only24h: false),
      if (c.planIds.isNotEmpty) CriterionKind.plans: c.copyWith(planIds: {}),
    };
    return [
        for (final entry in candidates.entries)
          RelaxationHint(entry.key, apply(entry.value).length),
      ].where((h) => h.resultCount > 0).toList()
      ..sort((a, b) => b.resultCount.compareTo(a.resultCount));
  }
}
