import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/text.dart';
import '../../facilities/domain/facility.dart';
import '../../offline/presentation/offline_page.dart';
import '../domain/offline_router.dart';
import 'origin_page.dart';
import 'road_map_view.dart';

final _routeProvider = FutureProvider.autoDispose
    .family<RouteOutcome?, (GeoPoint, GeoPoint)>((ref, pair) async {
      final worker = await ref.watch(routingWorkerProvider.future);
      if (worker == null) return null;
      return worker.route(pair.$1, pair.$2);
    });

/// T06 Rota calculada no aparelho, sem rede.
class RoutePage extends ConsumerWidget {
  const RoutePage({required this.facility, super.key});
  final Facility facility;

  Future<void> _openExternal(BuildContext context) async {
    final dest = facility.location!;
    final uri = Uri.parse(
      'geo:${dest.lat},${dest.lon}?q=${dest.lat},${dest.lon}(${Uri.encodeComponent(facility.name)})',
    );
    if (!await launchUrl(uri) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum aplicativo de mapas disponível.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final origin = ref.watch(originProvider);
    final package = ref.watch(roadPackageProvider);
    final graph = ref.watch(roadGraphProvider);
    final theme = Theme.of(context);
    final destination = facility.location!;

    Widget message(String text, {Widget? action}) => Padding(
      padding: const EdgeInsets.all(Space.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: Space.s16), action],
        ],
      ),
    );

    final Widget body;
    if (!package.isInstalled || graph == null) {
      body = message(
        'Baixe o mapa da região para calcular rotas sem internet. '
        'Endereço e telefone continuam disponíveis na página da unidade.',
        action: FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const OfflinePage())),
          child: const Text('Dados e mapas offline'),
        ),
      );
    } else if (origin == null) {
      body = message(
        'Defina de onde você sai: sua localização ou um ponto no mapa.',
        action: FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const OriginPage())),
          child: const Text('Definir origem'),
        ),
      );
    } else {
      final route = ref.watch(_routeProvider((origin.point, destination)));
      body = switch (route) {
        AsyncData(value: RouteFound(:final plan)) => Column(
          children: [
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.all(Space.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatDistance(plan.distanceMeters),
                      style: theme.textTheme.headlineMedium,
                    ),
                    Text('De: ${origin.label}'),
                    Text('Até: ${facility.name}'),
                    const Text(
                      'Perfil automóvel · distância pelas vias · calculada no aparelho, sem internet',
                    ),
                    if (plan.originSnapMeters > 50 ||
                        plan.destinationSnapMeters > 50)
                      Text(
                        'A rota começa/termina na via mapeada mais próxima '
                        '(${plan.originSnapMeters.round()} m da origem, '
                        '${plan.destinationSnapMeters.round()} m da unidade).',
                        style: theme.textTheme.bodySmall,
                      ),
                    Text(
                      'Sem trânsito, obras ou interdições em tempo real. Confira a sinalização.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: RoadMapView(
                graph: graph,
                route: plan.geometry,
                fitPoints: [origin.point, destination, ...plan.geometry],
                semanticLabel:
                    'Mapa da rota de ${formatDistance(plan.distanceMeters)} até ${facility.name}',
                markers: [
                  MapMarker(origin.point, theme.colorScheme.primary, 'Origem'),
                  MapMarker(destination, theme.colorScheme.error, 'Unidade'),
                ],
              ),
            ),
          ],
        ),
        AsyncData(value: RouteFailure(:final reason)) => message(
          '${reason.message}. Não desenhamos linha reta como se fosse caminho. '
          'Ajuste a origem ou use o telefone/endereço da unidade.',
          action: OutlinedButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const OriginPage())),
            child: const Text('Ajustar origem'),
          ),
        ),
        AsyncError(:final error) => message('Falha no cálculo da rota: $error'),
        _ => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: Space.s12),
              Text('Calculando rota…'),
            ],
          ),
        ),
      };
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rota'),
        actions: [
          IconButton(
            tooltip:
                'Abrir em outro aplicativo de mapas (pode exigir internet)',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => _openExternal(context),
          ),
        ],
      ),
      body: body,
    );
  }
}
