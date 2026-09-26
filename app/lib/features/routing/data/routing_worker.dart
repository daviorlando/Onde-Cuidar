import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../facilities/domain/facility.dart';
import '../../search/domain/ranking.dart';
import '../domain/offline_router.dart';
import '../domain/road_graph.dart';

/// Motor de rotas local executado fora da thread de interface. O isolate
/// mantém o grafo e o índice espacial carregados entre consultas.
class RoutingWorker {
  RoutingWorker._(this._isolate, this._requests, this._responses);

  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _responses;
  final _pending = <int, Completer<Object?>>{};
  var _nextId = 0;

  static Future<RoutingWorker> start(Uint8List graphBytes) async {
    final responses = ReceivePort();
    final isolate = await Isolate.spawn(_main, (
      responses.sendPort,
      TransferableTypedData.fromList([graphBytes]),
    ), debugName: 'routing');
    final first = Completer<SendPort>();
    late RoutingWorker worker;
    responses.listen((message) {
      if (message is SendPort) {
        first.complete(message);
      } else if (message is (int, Object?)) {
        worker._pending.remove(message.$1)?.complete(message.$2);
      } else if (message is (int, Error, StackTrace)) {
        worker._pending
            .remove(message.$1)
            ?.completeError(message.$2, message.$3);
      }
    });
    worker = RoutingWorker._(isolate, await first.future, responses);
    return worker;
  }

  Future<T> _call<T>(Object request) {
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _requests.send((id, request));
    return completer.future.then((value) => value as T);
  }

  Future<RouteOutcome> route(GeoPoint origin, GeoPoint destination) =>
      _call(_RouteRequest(origin, destination));

  Future<Map<String, RoadDistance>> distances(
    GeoPoint origin,
    Map<String, GeoPoint> destinations,
  ) => _call(_DistancesRequest(origin, destinations));

  void dispose() {
    _isolate.kill(priority: Isolate.immediate);
    _responses.close();
    for (final pending in _pending.values) {
      pending.completeError(StateError('motor de rotas encerrado'));
    }
    _pending.clear();
  }

  static void _main((SendPort, TransferableTypedData) args) {
    final (replies, data) = args;
    final graph = RoadGraph.fromBytes(data.materialize().asUint8List());
    final router = OfflineRouter(graph);
    graph.index; // constrói o índice antes da primeira consulta
    final requests = ReceivePort();
    replies.send(requests.sendPort);
    requests.listen((message) {
      final (id, request) = message as (int, Object);
      try {
        final result = switch (request) {
          _RouteRequest(:final origin, :final destination) => router.route(
            origin,
            destination,
          ),
          _DistancesRequest(:final origin, :final destinations) =>
            router.distances(origin, destinations),
          _ => throw ArgumentError('pedido desconhecido'),
        };
        replies.send((id, result));
      } on Object catch (error, stack) {
        // Exceções nem sempre são transferíveis entre isolates: enviar texto.
        replies.send((id, StateError('$error'), stack));
      }
    });
  }
}

class _RouteRequest {
  const _RouteRequest(this.origin, this.destination);
  final GeoPoint origin;
  final GeoPoint destination;
}

class _DistancesRequest {
  const _DistancesRequest(this.origin, this.destinations);
  final GeoPoint origin;
  final Map<String, GeoPoint> destinations;
}
