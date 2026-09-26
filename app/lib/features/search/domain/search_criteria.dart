import '../../facilities/domain/facility.dart';

/// Critérios de pesquisa. Entre categorias: E. Dentro de uma categoria: OU.
class SearchCriteria {
  const SearchCriteria({
    this.text = '',
    this.serviceIds = const {},
    this.specialtyIds = const {},
    this.natures = const {},
    this.susOnly = false,
    this.only24h = false,
    this.planIds = const {},
  });

  final String text;
  final Set<String> serviceIds;
  final Set<String> specialtyIds;

  /// Somente `public`/`private`; natureza desconhecida nunca passa pelo filtro.
  final Set<AdministrativeNature> natures;
  final bool susOnly;
  final bool only24h;
  final Set<String> planIds;

  bool get hasFilters =>
      serviceIds.isNotEmpty ||
      specialtyIds.isNotEmpty ||
      natures.isNotEmpty ||
      susOnly ||
      only24h ||
      planIds.isNotEmpty;

  bool get isEmpty => text.trim().isEmpty && !hasFilters;

  int get filterCount =>
      serviceIds.length +
      specialtyIds.length +
      natures.length +
      planIds.length +
      (susOnly ? 1 : 0) +
      (only24h ? 1 : 0);

  SearchCriteria copyWith({
    String? text,
    Set<String>? serviceIds,
    Set<String>? specialtyIds,
    Set<AdministrativeNature>? natures,
    bool? susOnly,
    bool? only24h,
    Set<String>? planIds,
  }) => SearchCriteria(
    text: text ?? this.text,
    serviceIds: serviceIds ?? this.serviceIds,
    specialtyIds: specialtyIds ?? this.specialtyIds,
    natures: natures ?? this.natures,
    susOnly: susOnly ?? this.susOnly,
    only24h: only24h ?? this.only24h,
    planIds: planIds ?? this.planIds,
  );

  SearchCriteria clearFilters() => SearchCriteria(text: text);

  @override
  bool operator ==(Object other) =>
      other is SearchCriteria &&
      other.text == text &&
      _setEq(other.serviceIds, serviceIds) &&
      _setEq(other.specialtyIds, specialtyIds) &&
      _setEq(other.natures, natures) &&
      other.susOnly == susOnly &&
      other.only24h == only24h &&
      _setEq(other.planIds, planIds);

  @override
  int get hashCode => Object.hash(
    text,
    Object.hashAllUnordered(serviceIds),
    Object.hashAllUnordered(specialtyIds),
    Object.hashAllUnordered(natures),
    susOnly,
    only24h,
    Object.hashAllUnordered(planIds),
  );

  static bool _setEq<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);
}
