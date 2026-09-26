import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onde_cuidar/features/facilities/data/catalog_codec.dart';
import 'package:onde_cuidar/features/facilities/domain/facility.dart';
import 'package:onde_cuidar/features/search/domain/eligibility.dart';
import 'package:onde_cuidar/features/search/domain/search_criteria.dart';

void main() {
  test('catálogo embarcado passa pela mesma validação da sincronização', () {
    final catalog = decodeCatalog(
      File('assets/catalog/catalog.json').readAsStringSync(),
    );
    expect(catalog.facilities, isNotEmpty);
    expect(catalog.coverage.published, catalog.facilities.length);
    // Nenhum registro foi conferido: a UI precisa sinalizar isso.
    expect(
      catalog.facilities
          .where((f) => f.reviewStatus == ReviewStatus.approved)
          .length,
      catalog.coverage.reviewed,
    );
    // Planos e especialidades não vieram da fonte: filtro afirmativo fica vazio.
    final filter = EligibilityFilter(catalog);
    expect(filter.apply(const SearchCriteria(planIds: {'qualquer'})), isEmpty);
  });

  test('JSON malformado ou esquema desconhecido é recusado', () {
    expect(() => decodeCatalog('{'), throwsA(isA<CatalogFormatException>()));
    expect(
      () => decodeCatalog('{"schema_version": 2}'),
      throwsA(isA<CatalogFormatException>()),
    );
  });
}
