import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/tone_card.dart';
import '../../../core/text.dart';
import '../../about/about_page.dart';
import '../../facilities/domain/facility.dart';
import '../../facilities/presentation/facility_detail_page.dart';
import '../../facilities/presentation/labels.dart';
import '../../offline/presentation/offline_page.dart';
import '../../routing/presentation/origin_page.dart';
import '../domain/eligibility.dart';
import '../domain/ranking.dart';
import '../domain/search_criteria.dart';
import 'filters_sheet.dart';

/// T01 Início e busca + T03 Lista de resultados.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Leitura local primeiro; sincronização depois, sem bloquear.
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoSync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _autoSync();
  }

  Future<void> _autoSync() async {
    await ref.read(installedCatalogProvider.future);
    if (!mounted) return;
    await ref.read(syncControllerProvider.notifier).refresh();
  }

  void _onText(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      ref.read(criteriaProvider.notifier).setText(text);
    });
  }

  @override
  Widget build(BuildContext context) {
    final installed = ref.watch(installedCatalogProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Onde Cuidar'),
        actions: [
          IconButton(
            tooltip: 'Dados e mapas offline',
            icon: const Icon(Icons.offline_pin_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const OfflinePage()),
            ),
          ),
          IconButton(
            tooltip: 'Sobre, fontes e privacidade',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const AboutPage())),
          ),
        ],
      ),
      body: switch (installed) {
        AsyncData() => _SearchBody(search: _search, onText: _onText),
        AsyncError(:final error) => _InstallError(error: error),
        _ => const _PreparingBase(),
      },
    );
  }
}

class _PreparingBase extends StatelessWidget {
  const _PreparingBase();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: Space.s16),
        Text('Preparando a base de unidades…'),
      ],
    ),
  );
}

class _InstallError extends ConsumerWidget {
  const _InstallError({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: Space.s16),
          const Text(
            'Não foi possível preparar a base de unidades no aparelho.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.s8),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: Space.s16),
          FilledButton(
            onPressed: () => ref.invalidate(installedCatalogProvider),
            child: const Text('Tentar novamente'),
          ),
        ],
      ),
    ),
  );
}

class _SearchBody extends ConsumerWidget {
  const _SearchBody({required this.search, required this.onText});

  final TextEditingController search;
  final ValueChanged<String> onText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final criteria = ref.watch(criteriaProvider);
    final origin = ref.watch(originProvider);
    final ranking = ref.watch(rankingProvider);
    // Durante um novo cálculo, nunca exibir o resultado de critérios antigos.
    final provisional = ref.watch(provisionalRankingProvider);
    final RankedResults results = ranking.isLoading || ranking.hasError
        ? provisional
        : (ranking.value ?? provisional);
    final approximate = results.mode == OrderingMode.straightLine;
    final computing = ranking.isLoading && origin != null;
    final package = ref.watch(roadPackageProvider);

    return CustomScrollView(
      // Teclado some ao rolar a lista (achado no S20 FE).
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s16,
              Space.s8,
              Space.s16,
              0,
            ),
            child: TextField(
              controller: search,
              onChanged: onText,
              textInputAction: TextInputAction.search,
              // Tocar fora (filtros, cartões) tira o foco; assim o teclado não
              // reabre ao voltar de outra tela e não cobre o estado vazio.
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Nome, serviço ou bairro',
                labelText: 'Buscar unidade',
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar busca',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          search.clear();
                          ref.read(criteriaProvider.notifier).setText('');
                        },
                      ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _ControlsRow(criteria: criteria, origin: origin),
        ),
        if (criteria.hasFilters)
          SliverToBoxAdapter(child: _ActiveFilters(criteria: criteria)),
        if (!package.isInstalled && package.status != PackageStatus.checking)
          const SliverToBoxAdapter(child: _PackageBanner()),
        SliverToBoxAdapter(
          child: _OrderingInfo(results: results, computing: computing),
        ),
        if (results.total == 0)
          SliverToBoxAdapter(child: _EmptyResults(criteria: criteria))
        else ...[
          SliverList.builder(
            itemCount: results.ordered.length,
            itemBuilder: (context, i) => FacilityCard(
              item: results.ordered[i],
              approximate: approximate,
            ),
          ),
          if (results.withoutDistance.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.s16,
                  Space.s24,
                  Space.s16,
                  Space.s8,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    'Sem distância calculada (${results.withoutDistance.length})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ),
            ),
            SliverList.builder(
              itemCount: results.withoutDistance.length,
              itemBuilder: (context, i) =>
                  FacilityCard(item: results.withoutDistance[i]),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: Space.s32)),
        ],
      ],
    );
  }
}

class _ControlsRow extends ConsumerWidget {
  const _ControlsRow({required this.criteria, required this.origin});

  final SearchCriteria criteria;
  final Origin? origin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = criteria.filterCount;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s16,
        vertical: Space.s8,
      ),
      child: Wrap(
        spacing: Space.s8,
        runSpacing: Space.s8,
        children: [
          FilledButton.tonalIcon(
            icon: const Icon(Icons.tune),
            label: Text(count == 0 ? 'Filtros' : 'Filtros ($count)'),
            onPressed: () => showFiltersSheet(context),
          ),
          // Botão de origem e "remover" ficam juntos na mesma linha.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: OutlinedButton.icon(
                  icon: Icon(
                    origin == null ? Icons.near_me_outlined : Icons.near_me,
                  ),
                  label: Text(
                    origin == null
                        ? 'Perto de mim'
                        : 'Origem: ${origin!.label}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const OriginPage()),
                  ),
                ),
              ),
              if (origin != null)
                IconButton(
                  tooltip: 'Remover origem',
                  icon: const Icon(Icons.close),
                  onPressed: () => ref.read(originProvider.notifier).set(null),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters({required this.criteria});
  final SearchCriteria criteria;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(installedCatalogProvider).value!.catalog;
    final notifier = ref.read(criteriaProvider.notifier);
    Widget chip(String label, SearchCriteria without) => InputChip(
      label: Text(label),
      onDeleted: () => notifier.set(without),
      deleteButtonTooltipMessage: 'Remover filtro $label',
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s16),
      child: Wrap(
        spacing: Space.s8,
        runSpacing: Space.s4,
        children: [
          for (final id in criteria.serviceIds)
            chip(
              catalog.service(id)?.name ?? id,
              criteria.copyWith(
                serviceIds: {...criteria.serviceIds}..remove(id),
              ),
            ),
          for (final id in criteria.specialtyIds)
            chip(
              catalog.specialtyName(id) ?? id,
              criteria.copyWith(
                specialtyIds: {...criteria.specialtyIds}..remove(id),
              ),
            ),
          for (final n in criteria.natures)
            chip(
              natureLabel(n),
              criteria.copyWith(natures: {...criteria.natures}..remove(n)),
            ),
          if (criteria.susOnly)
            chip('Atende pelo SUS', criteria.copyWith(susOnly: false)),
          if (criteria.only24h)
            chip('24 horas', criteria.copyWith(only24h: false)),
          for (final id in criteria.planIds)
            chip(
              catalog.planName(id) ?? id,
              criteria.copyWith(planIds: {...criteria.planIds}..remove(id)),
            ),
          TextButton(
            onPressed: notifier.clearFilters,
            child: const Text('Limpar filtros'),
          ),
        ],
      ),
    );
  }
}

class _PackageBanner extends StatelessWidget {
  const _PackageBanner();

  @override
  Widget build(BuildContext context) => ToneCard(
    tone: Tone.info,
    child: ListTile(
      leading: const Icon(Icons.map_outlined),
      title: const Text(
        'Baixe o mapa da região para calcular rotas sem internet',
      ),
      subtitle: const Text(
        'As informações das unidades já funcionam sem internet.',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const OfflinePage())),
    ),
  );
}

class _OrderingInfo extends StatelessWidget {
  const _OrderingInfo({required this.results, required this.computing});

  final RankedResults results;
  final bool computing;

  @override
  Widget build(BuildContext context) {
    final text = switch (results.mode) {
      OrderingMode.alphabetical =>
        'Ordem alfabética. Use "Perto de mim" para ordenar por distância.',
      OrderingMode.straightLine => 'Distância em linha reta (aproximada). Instale o mapa da região para distância pelas ruas.',
      OrderingMode.road =>
        'Ordenado pela distância pelas ruas, calculada no aparelho.',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.s16,
        Space.s8,
        Space.s16,
        Space.s8,
      ),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${results.total} ${results.total == 1 ? 'unidade compatível' : 'unidades compatíveis'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(text, style: Theme.of(context).textTheme.bodySmall),
            if (computing) ...[
              const SizedBox(height: Space.s4),
              const Text('Calculando distâncias pelas ruas…'),
              const LinearProgressIndicator(),
            ],
            if (results.partial)
              const Text('Ordenação por distância incompleta.'),
          ],
        ),
      ),
    );
  }
}

class _EmptyResults extends ConsumerWidget {
  const _EmptyResults({required this.criteria});
  final SearchCriteria criteria;

  static String _kindLabel(CriterionKind kind) => switch (kind) {
    CriterionKind.text => 'o texto da busca',
    CriterionKind.services => 'o filtro de atendimento',
    CriterionKind.specialties => 'o filtro de especialidade',
    CriterionKind.natures => 'o filtro de natureza',
    CriterionKind.sus => 'o filtro "Atende pelo SUS"',
    CriterionKind.only24h => 'o filtro "24 horas"',
    CriterionKind.plans => 'o filtro de plano',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hints =
        ref.watch(eligibilityFilterProvider)?.relaxationHints(criteria) ?? [];
    return Padding(
      padding: const EdgeInsets.all(Space.s24),
      child: Column(
        children: [
          const Icon(Icons.search_off, size: 48),
          const SizedBox(height: Space.s12),
          const Text(
            'Nenhuma unidade atende a todas as condições escolhidas.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.s8),
          const Text(
            'Unidades com informação não confirmada não aparecem em filtros. '
            'Você pode remover um filtro:',
            textAlign: TextAlign.center,
          ),
          for (final h in hints)
            Text(
              '• Sem ${_kindLabel(h.kind)}: ${h.resultCount} unidade(s)',
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: Space.s12),
          if (criteria.hasFilters)
            OutlinedButton(
              onPressed: () => showFiltersSheet(context),
              child: const Text('Editar filtros'),
            ),
        ],
      ),
    );
  }
}

class FacilityCard extends StatelessWidget {
  const FacilityCard({required this.item, this.approximate = false, super.key});
  final RankedFacility item;

  /// Distância em linha reta, não pelas ruas.
  final bool approximate;

  @override
  Widget build(BuildContext context) {
    final f = item.facility;
    final theme = Theme.of(context);
    final distance = item.distanceMeters;
    final details = [
      natureLabel(f.nature),
      if (f.susAccess == TriState.yes) 'SUS',
      if (f.is24h == TriState.yes) '24h',
      ?f.facilityType?.name,
    ].join(' · ');
    return Card(
      child: InkWell(
        borderRadius: const BorderRadius.all(Radii.medium),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FacilityDetailPage(facility: f),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Space.s12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: Space.s4),
                    Text(details, style: theme.textTheme.bodySmall),
                    Text(
                      f.address.singleLine,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (item.note != null)
                      Text(item.note!, style: theme.textTheme.bodySmall),
                    if (f.reviewStatus == ReviewStatus.pending)
                      Text(
                        notConfirmed,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
              if (distance != null) ...[
                const SizedBox(width: Space.s8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatDistance(distance),
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      approximate ? 'em linha reta' : 'pelas ruas',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
