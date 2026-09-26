import 'package:flutter_test/flutter_test.dart';
import 'package:onde_cuidar/features/facilities/domain/facility.dart';
import 'package:onde_cuidar/features/search/domain/eligibility.dart';
import 'package:onde_cuidar/features/search/domain/search_criteria.dart';

import '../../support/fixtures.dart';

List<String> ids(List<Facility> list) => list.map((f) => f.id).toList()..sort();

void main() {
  const plans = [
    HealthPlan(id: 'plano-a', name: 'Plano A'),
    HealthPlan(id: 'plano-b', name: 'Plano B'),
  ];

  test(
    'CT02: pública + serviço + 24h retorna apenas registros confirmados',
    () {
      final filter = EligibilityFilter(
        catalogOf([
          facility(
            'ok',
            services: [offers('urgencia', is24h: TriState.yes)],
            is24h: TriState.yes,
          ),
          facility(
            'desconhecido',
            services: [offers('urgencia', is24h: TriState.unknown)],
            is24h: TriState.yes,
          ),
          facility(
            'privada',
            nature: AdministrativeNature.private,
            services: [offers('urgencia', is24h: TriState.yes)],
          ),
          facility(
            'sem-servico',
            services: [offers('atencao-basica', is24h: TriState.yes)],
          ),
        ]),
      );
      final result = filter.apply(
        const SearchCriteria(
          natures: {AdministrativeNature.public},
          serviceIds: {'urgencia'},
          only24h: true,
        ),
      );
      expect(ids(result), ['ok']);
    },
  );

  test('US04: unidade 24h não torna todos os serviços 24h', () {
    final filter = EligibilityFilter(
      catalogOf([
        facility(
          'hospital',
          is24h: TriState.yes,
          services: [
            offers('urgencia', is24h: TriState.yes),
            offers('cardiologia-amb', is24h: TriState.no),
          ],
        ),
      ]),
    );
    expect(
      filter.apply(
        const SearchCriteria(serviceIds: {'cardiologia-amb'}, only24h: true),
      ),
      isEmpty,
    );
    expect(
      ids(
        filter.apply(
          const SearchCriteria(serviceIds: {'urgencia'}, only24h: true),
        ),
      ),
      ['hospital'],
    );
    expect(ids(filter.apply(const SearchCriteria(only24h: true))), [
      'hospital',
    ]);
  });

  test('CT03: plano desconhecido não passa pelo filtro afirmativo', () {
    final filter = EligibilityFilter(
      catalogOf(plans: plans, [
        facility(
          'aceita',
          nature: AdministrativeNature.private,
          plans: [
            const PlanAcceptance(planId: 'plano-a', accepted: TriState.yes),
          ],
        ),
        facility(
          'desconhecido',
          nature: AdministrativeNature.private,
          plans: [
            const PlanAcceptance(planId: 'plano-a', accepted: TriState.unknown),
          ],
        ),
        facility(
          'nao-aceita',
          nature: AdministrativeNature.private,
          plans: [
            const PlanAcceptance(planId: 'plano-a', accepted: TriState.no),
          ],
        ),
        facility('sem-informacao', nature: AdministrativeNature.private),
      ]),
    );
    expect(ids(filter.apply(const SearchCriteria(planIds: {'plano-a'}))), [
      'aceita',
    ]);
  });

  test(
    'plano confirmado só para outro serviço não atende o serviço pedido',
    () {
      final filter = EligibilityFilter(
        catalogOf(plans: plans, [
          facility(
            'x',
            nature: AdministrativeNature.private,
            services: [offers('urgencia'), offers('cardiologia-amb')],
            plans: [
              const PlanAcceptance(
                planId: 'plano-a',
                accepted: TriState.yes,
                serviceId: 'cardiologia-amb',
              ),
            ],
          ),
        ]),
      );
      expect(
        filter.apply(
          const SearchCriteria(planIds: {'plano-a'}, serviceIds: {'urgencia'}),
        ),
        isEmpty,
      );
      expect(
        filter.apply(
          const SearchCriteria(
            planIds: {'plano-a'},
            serviceIds: {'cardiologia-amb'},
          ),
        ),
        hasLength(1),
      );
    },
  );

  test('CT04: natureza privada com acesso SUS não se confunde com pública', () {
    final filter = EligibilityFilter(
      catalogOf([
        facility(
          'privada-sus',
          nature: AdministrativeNature.private,
          sus: TriState.yes,
        ),
        facility('publica', sus: TriState.yes),
        facility(
          'privada',
          nature: AdministrativeNature.private,
          sus: TriState.no,
        ),
        facility(
          'natureza-desconhecida',
          nature: AdministrativeNature.unknown,
          sus: TriState.unknown,
        ),
      ]),
    );
    expect(
      ids(
        filter.apply(
          const SearchCriteria(natures: {AdministrativeNature.public}),
        ),
      ),
      ['publica'],
    );
    expect(ids(filter.apply(const SearchCriteria(susOnly: true))), [
      'privada-sus',
      'publica',
    ]);
    expect(
      ids(
        filter.apply(
          const SearchCriteria(
            natures: {AdministrativeNature.private},
            susOnly: true,
          ),
        ),
      ),
      ['privada-sus'],
    );
    // Desconhecido não passa em nenhum filtro afirmativo de natureza.
    expect(
      filter.apply(
        const SearchCriteria(
          natures: {AdministrativeNature.public, AdministrativeNature.private},
        ),
      ),
      hasLength(3),
    );
  });

  test('CT05: OU dentro da categoria e E entre categorias', () {
    final filter = EligibilityFilter(
      catalogOf([
        facility('a', services: [offers('atencao-basica')]),
        facility('b', services: [offers('urgencia')]),
        facility(
          'b-privada',
          nature: AdministrativeNature.private,
          services: [offers('urgencia')],
        ),
        facility('c', services: [offers('cardiologia-amb')]),
        facility(
          'd',
          services: [offers('urgencia', availability: TriState.unknown)],
        ),
      ]),
    );
    expect(
      ids(
        filter.apply(
          const SearchCriteria(serviceIds: {'atencao-basica', 'urgencia'}),
        ),
      ),
      ['a', 'b', 'b-privada'],
    );
    expect(
      ids(
        filter.apply(
          const SearchCriteria(
            serviceIds: {'atencao-basica', 'urgencia'},
            natures: {AdministrativeNature.public},
          ),
        ),
      ),
      ['a', 'b'],
    );
  });

  test('especialidades: OU interno e somente disponibilidade confirmada', () {
    const specialties = [
      Specialty(id: 'cardio', name: 'Cardiologia'),
      Specialty(id: 'pediatria', name: 'Pediatria'),
    ];
    final filter = EligibilityFilter(
      catalogOf(specialties: specialties, [
        facility(
          'cardio',
          specialties: [
            const FacilitySpecialty(
              specialtyId: 'cardio',
              availability: TriState.yes,
            ),
          ],
        ),
        facility(
          'ped',
          specialties: [
            const FacilitySpecialty(
              specialtyId: 'pediatria',
              availability: TriState.yes,
            ),
          ],
        ),
        facility(
          'talvez',
          specialties: [
            const FacilitySpecialty(
              specialtyId: 'cardio',
              availability: TriState.unknown,
            ),
          ],
        ),
      ]),
    );
    expect(
      ids(
        filter.apply(
          const SearchCriteria(specialtyIds: {'cardio', 'pediatria'}),
        ),
      ),
      ['cardio', 'ped'],
    );
  });

  test('busca textual ignora caixa e acentos sem alterar o texto', () {
    final filter = EligibilityFilter(
      catalogOf([
        facility('x', name: 'UNIDADE SÃO JOSÉ', locality: 'José e Maria'),
        facility('y', name: 'Clínica Outra'),
      ]),
    );
    expect(ids(filter.apply(const SearchCriteria(text: 'sao jose'))), ['x']);
    expect(ids(filter.apply(const SearchCriteria(text: 'CLINICA'))), ['y']);
    expect(ids(filter.apply(const SearchCriteria(text: 'upa'))), isEmpty);
    expect(filter.catalog.facilities.first.name, 'UNIDADE SÃO JOSÉ');
  });

  test('busca textual encontra sinônimos de serviço oferecido', () {
    final filter = EligibilityFilter(
      catalogOf([
        facility('u', services: [offers('urgencia')]),
      ]),
    );
    expect(ids(filter.apply(const SearchCriteria(text: 'UPA'))), ['u']);
  });

  test('CT06: combinação vazia explica qual critério remover, sem relaxar', () {
    final filter = EligibilityFilter(
      catalogOf([
        facility('a', services: [offers('urgencia')]),
        facility('b', services: [offers('urgencia')]),
      ]),
    );
    const criteria = SearchCriteria(serviceIds: {'urgencia'}, only24h: true);
    expect(filter.apply(criteria), isEmpty);
    final hints = filter.relaxationHints(criteria);
    expect(hints.single.kind, CriterionKind.only24h);
    expect(hints.single.resultCount, 2);
  });
}
