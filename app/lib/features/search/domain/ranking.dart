import '../../../core/geo.dart';
import '../../facilities/domain/facility.dart';

enum OrderingMode {
  /// Distância viária calculada pelo motor local para todos os elegíveis roteáveis.
  road,

  /// Sem motor/pacote: aproximação geográfica, rotulada como "em linha reta".
  straightLine,

  /// Sem origem: ordem alfabética.
  alphabetical,
}

/// Resultado de distância viária de um destino.
sealed class RoadDistance {
  const RoadDistance();
}

class Reachable extends RoadDistance {
  const Reachable(this.meters);
  final double meters;
}

/// Sem caminho na malha instalada, destino fora da cobertura ou longe de via.
class Unreachable extends RoadDistance {
  const Unreachable(this.reason);
  final String reason;
}

class RankedFacility {
  const RankedFacility(this.facility, {this.distanceMeters, this.note});

  final Facility facility;
  final double? distanceMeters;

  /// Motivo de não ter distância (sem coordenada, sem rota…).
  final String? note;
}

class RankedResults {
  const RankedResults({
    required this.mode,
    required this.ordered,
    required this.withoutDistance,
    required this.partial,
  });

  final OrderingMode mode;

  /// Elegíveis com distância (ou todos, na ordem alfabética).
  final List<RankedFacility> ordered;

  /// Destinos não roteáveis: grupo identificado ao final, sem distância inventada.
  final List<RankedFacility> withoutDistance;

  /// Algum destino roteável ficou sem cálculo: "ordenação incompleta".
  final bool partial;

  int get total => ordered.length + withoutDistance.length;
}

int _byName(Facility a, Facility b) {
  final c = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// Ordena somente o conjunto já elegível. Desempate estável por ID.
RankedResults rank(
  List<Facility> eligible, {
  GeoPoint? origin,
  Map<String, RoadDistance>? roadDistances,
}) {
  if (origin == null) {
    return RankedResults(
      mode: OrderingMode.alphabetical,
      ordered: [
        for (final f in [...eligible]..sort(_byName)) RankedFacility(f),
      ],
      withoutDistance: const [],
      partial: false,
    );
  }

  final ordered = <RankedFacility>[];
  final without = <RankedFacility>[];
  var partial = false;
  final mode = roadDistances == null
      ? OrderingMode.straightLine
      : OrderingMode.road;

  for (final f in eligible) {
    final location = f.location;
    if (location == null) {
      without.add(RankedFacility(f, note: 'Sem coordenada verificada'));
      continue;
    }
    if (mode == OrderingMode.straightLine) {
      ordered.add(
        RankedFacility(f, distanceMeters: haversineMeters(origin, location)),
      );
      continue;
    }
    switch (roadDistances![f.id]) {
      case Reachable(:final meters):
        ordered.add(RankedFacility(f, distanceMeters: meters));
      case Unreachable(:final reason):
        without.add(RankedFacility(f, note: reason));
      case null:
        partial = true;
        without.add(RankedFacility(f, note: 'Distância não calculada'));
    }
  }

  ordered.sort((a, b) {
    final c = a.distanceMeters!.compareTo(b.distanceMeters!);
    return c != 0 ? c : a.facility.id.compareTo(b.facility.id);
  });
  without.sort((a, b) => _byName(a.facility, b.facility));
  return RankedResults(
    mode: mode,
    ordered: ordered,
    withoutDistance: without,
    partial: partial,
  );
}
