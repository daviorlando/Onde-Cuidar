import 'package:flutter_test/flutter_test.dart';
import 'package:onde_cuidar/features/facilities/domain/facility.dart';
import 'package:onde_cuidar/features/search/domain/eligibility.dart';
import 'package:onde_cuidar/features/search/domain/ranking.dart';
import 'package:onde_cuidar/features/search/domain/search_criteria.dart';

import '../../support/fixtures.dart';

void main() {
  const origin = GeoPoint(-9.39, -40.50);

  test('CT07: compatível mais distante vence incompatível mais próxima', () {
    final catalog = catalogOf([
      facility(
        'incompativel-perto',
        services: [offers('atencao-basica')],
        location: const GeoPoint(-9.391, -40.50),
      ),
      facility(
        'compativel-longe',
        services: [offers('urgencia')],
        location: const GeoPoint(-9.45, -40.50),
      ),
    ]);
    final eligible = EligibilityFilter(catalog)
        .apply(const SearchCriteria(serviceIds: {'urgencia'}));
    final ranked = rank(
      eligible,
      origin: origin,
      roadDistances: {'compativel-longe': const Reachable(7000)},
    );
    expect(ranked.ordered.first.facility.id, 'compativel-longe');
    expect(ranked.total, 1);
  });

  test('CT08: ordena pela distância viária, não pela linha reta', () {
    final facilities = [
      facility('reta-perto', location: const GeoPoint(-9.391, -40.50)),
      facility('reta-longe', location: const GeoPoint(-9.40, -40.50)),
    ];
    final ranked = rank(
      facilities,
      origin: origin,
      roadDistances: {
        'reta-perto': const Reachable(5000), // rio no meio: volta longa
        'reta-longe': const Reachable(1500),
      },
    );
    expect(ranked.mode, OrderingMode.road);
    expect(ranked.ordered.map((r) => r.facility.id), [
      'reta-longe',
      'reta-perto',
    ]);
  });

  test('sem motor: linha reta rotulada; sem origem: alfabética', () {
    final facilities = [
      facility('b', name: 'Beta', location: const GeoPoint(-9.391, -40.50)),
      facility('a', name: 'Alfa', location: const GeoPoint(-9.45, -40.50)),
    ];
    final straight = rank(facilities, origin: origin);
    expect(straight.mode, OrderingMode.straightLine);
    expect(straight.ordered.map((r) => r.facility.id), ['b', 'a']);

    final alphabetical = rank(facilities);
    expect(alphabetical.mode, OrderingMode.alphabetical);
    expect(alphabetical.ordered.map((r) => r.facility.id), ['a', 'b']);
    expect(alphabetical.ordered.every((r) => r.distanceMeters == null), isTrue);
  });

  test(
    'não roteáveis ao final, sem distância inventada; parcial sinalizado',
    () {
      final facilities = [
        facility('sem-coordenada'),
        facility('sem-rota', location: const GeoPoint(-9.40, -40.50)),
        facility('ok', location: const GeoPoint(-9.40, -40.51)),
        facility('nao-calculado', location: const GeoPoint(-9.40, -40.52)),
      ];
      final ranked = rank(
        facilities,
        origin: origin,
        roadDistances: {
          'sem-rota': const Unreachable('Sem caminho'),
          'ok': const Reachable(900),
        },
      );
      expect(ranked.ordered.map((r) => r.facility.id), ['ok']);
      expect(ranked.withoutDistance.map((r) => r.facility.id).toSet(), {
        'sem-coordenada',
        'sem-rota',
        'nao-calculado',
      });
      expect(
        ranked.withoutDistance.every(
          (r) => r.distanceMeters == null && r.note != null,
        ),
        isTrue,
      );
      expect(ranked.partial, isTrue);
    },
  );

  test('desempate estável por ID', () {
    final facilities = [
      facility('z', location: origin),
      facility('a', location: origin),
    ];
    final ranked = rank(
      facilities,
      origin: origin,
      roadDistances: {'z': const Reachable(100), 'a': const Reachable(100)},
    );
    expect(ranked.ordered.map((r) => r.facility.id), ['a', 'z']);
  });
}
