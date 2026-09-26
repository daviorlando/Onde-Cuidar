import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/tone_card.dart';
import '../../facilities/domain/facility.dart';
import '../../offline/presentation/offline_page.dart';
import '../data/location_service.dart';
import 'road_map_view.dart';

/// T05 Origem e permissão. A localização só é pedida após explicação e toque.
class OriginPage extends ConsumerStatefulWidget {
  const OriginPage({super.key});

  @override
  ConsumerState<OriginPage> createState() => _OriginPageState();
}

class _OriginPageState extends ConsumerState<OriginPage> {
  bool _locating = false;
  LocationResult? _result;

  Future<void> _useLocation() async {
    setState(() {
      _locating = true;
      _result = null;
    });
    final result = await ref.read(locationServiceProvider).current();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _result = result;
    });
    if (result is LocationFound) {
      ref
          .read(originProvider.notifier)
          .set(
            Origin(
              result.point,
              OriginKind.gps,
              accuracyMeters: result.accuracyMeters,
            ),
          );
      if (!result.isImprecise) Navigator.of(context).pop();
    }
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.of(
      context,
    ).push<GeoPoint>(MaterialPageRoute(builder: (_) => const PickOriginPage()));
    if (picked != null && mounted) {
      ref.read(originProvider.notifier).set(Origin(picked, OriginKind.manual));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = ref.read(locationServiceProvider);
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('De onde você sai?')),
      body: ListView(
        padding: const EdgeInsets.all(Space.s16),
        children: [
          const Text(
            'A origem serve para ordenar as unidades pela distância e traçar rotas. '
            'Ela fica só no aparelho, enquanto o app estiver aberto, e não é enviada a nenhum servidor.',
          ),
          const SizedBox(height: Space.s24),
          FilledButton.icon(
            icon: _locating
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            label: Text(
              _locating ? 'Obtendo localização…' : 'Usar minha localização',
            ),
            onPressed: _locating ? null : _useLocation,
          ),
          const SizedBox(height: Space.s8),
          const Text(
            'O Android vai pedir permissão de localização. Você pode recusar e '
            'escolher o ponto no mapa.',
          ),
          const SizedBox(height: Space.s24),
          OutlinedButton.icon(
            icon: const Icon(Icons.touch_app_outlined),
            label: const Text('Escolher ponto no mapa'),
            onPressed: _pickOnMap,
          ),
          const SizedBox(height: Space.s24),
          if (result != null)
            ToneCard(
              tone: result is LocationFound && !result.isImprecise
                  ? Tone.info
                  : Tone.attention,
              child: Padding(
                padding: const EdgeInsets.all(Space.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: switch (result) {
                    LocationFound(:final accuracyMeters, :final isImprecise) => [
                      Text(
                        isImprecise
                            ? 'Localização imprecisa (cerca de ${accuracyMeters.round()} m). '
                                  'Ela foi usada, mas você pode ajustar escolhendo no mapa.'
                            : 'Localização obtida.',
                      ),
                      if (isImprecise)
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Continuar assim'),
                        ),
                    ],
                    LocationPermissionDenied(permanently: false) => [
                      const Text(
                        'Permissão negada. A busca continua funcionando; '
                        'escolha a origem no mapa se quiser distâncias.',
                      ),
                    ],
                    LocationPermissionDenied(permanently: true) => [
                      const Text(
                        'A permissão de localização está bloqueada para este app. '
                        'Você pode liberar nas configurações ou escolher no mapa.',
                      ),
                      TextButton(
                        onPressed: location.openAppSettings,
                        child: const Text('Abrir configurações do app'),
                      ),
                    ],
                    LocationServiceDisabled() => [
                      const Text(
                        'A localização do aparelho (GPS) está desligada.',
                      ),
                      TextButton(
                        onPressed: location.openLocationSettings,
                        child: const Text('Abrir configurações de localização'),
                      ),
                    ],
                    LocationUnavailable(:final detail) => [
                      Text('Localização indisponível: $detail'),
                    ],
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Seleção manual da origem no mapa offline.
class PickOriginPage extends ConsumerStatefulWidget {
  const PickOriginPage({super.key});

  @override
  ConsumerState<PickOriginPage> createState() => _PickOriginPageState();
}

class _PickOriginPageState extends ConsumerState<PickOriginPage> {
  GeoPoint? _picked;

  @override
  Widget build(BuildContext context) {
    final graph = ref.watch(roadGraphProvider);
    final current =
        ref.read(originProvider)?.point ?? ref.watch(catalogCenterProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Escolher origem')),
      body: graph == null
          ? Padding(
              padding: const EdgeInsets.all(Space.s24),
              child: Column(
                children: [
                  const Text(
                    'Para escolher no mapa sem internet, instale o mapa da região.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Space.s16),
                  FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const OfflinePage(),
                      ),
                    ),
                    child: const Text('Dados e mapas offline'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(Space.s12),
                  child: Text(
                    'Toque no mapa para marcar o ponto de saída. Arraste para mover; use + e − para zoom.',
                  ),
                ),
                Expanded(
                  child: RoadMapView(
                    graph: graph,
                    center: _picked ?? current,
                    semanticLabel:
                        'Mapa das vias. Toque para escolher a origem.',
                    markers: [
                      if (_picked != null)
                        MapMarker(
                          _picked!,
                          Theme.of(context).colorScheme.primary,
                          'Origem',
                        ),
                    ],
                    onTap: (p) => setState(() => _picked = p),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.s12),
                    child: FilledButton(
                      onPressed: _picked == null
                          ? null
                          : () => Navigator.of(context).pop(_picked),
                      child: Text(
                        _picked == null ? 'Toque no mapa' : 'Usar este ponto',
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
