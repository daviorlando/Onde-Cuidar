import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../facilities/domain/facility.dart';
import '../domain/search_criteria.dart';

Future<void> showFiltersSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const FiltersSheet(),
    );

/// T02 Filtros. Edita um rascunho e mostra a contagem antes de aplicar.
class FiltersSheet extends ConsumerStatefulWidget {
  const FiltersSheet({super.key});

  @override
  ConsumerState<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends ConsumerState<FiltersSheet> {
  late SearchCriteria draft = ref.read(criteriaProvider);

  Set<T> _toggle<T>(Set<T> set, T value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(installedCatalogProvider).value!.catalog;
    final filter = ref.watch(eligibilityFilterProvider)!;
    final count = filter.apply(draft).length;
    final theme = Theme.of(context);
    final care = catalog.services.where((s) => s.category == 'atendimento');
    final structure = catalog.services.where(
      (s) => s.category != 'atendimento',
    );

    Widget section(String title, String help, List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: Space.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          Text(help, style: theme.textTheme.bodySmall),
          const SizedBox(height: Space.s8),
          Wrap(spacing: Space.s8, runSpacing: Space.s4, children: children),
        ],
      ),
    );

    Widget unavailable(String text) => Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.symmetric(horizontal: Space.s16),
              children: [
                Text('Filtros', style: theme.textTheme.headlineSmall),
                const SizedBox(height: Space.s4),
                const Text(
                  'Entre grupos, a unidade precisa atender a todas as condições. '
                  'Dentro de um grupo, basta atender a uma das opções marcadas. '
                  'Informação não confirmada não passa pelos filtros.',
                ),
                const SizedBox(height: Space.s16),
                section('Atendimento', 'Uma das opções (OU)', [
                  for (final s in care)
                    FilterChip(
                      label: Text(s.name),
                      selected: draft.serviceIds.contains(s.id),
                      onSelected: (_) => setState(
                        () => draft = draft.copyWith(
                          serviceIds: _toggle(draft.serviceIds, s.id),
                        ),
                      ),
                    ),
                ]),
                section('Estrutura da unidade', 'Uma das opções (OU)', [
                  for (final s in structure)
                    FilterChip(
                      label: Text(s.name),
                      selected: draft.serviceIds.contains(s.id),
                      onSelected: (_) => setState(
                        () => draft = draft.copyWith(
                          serviceIds: _toggle(draft.serviceIds, s.id),
                        ),
                      ),
                    ),
                ]),
                section('Especialidade', 'Uma das opções (OU)', [
                  if (catalog.specialties.isEmpty)
                    unavailable(
                      'Nenhuma especialidade confirmada na base atual.',
                    ),
                  for (final s in catalog.specialties)
                    FilterChip(
                      label: Text(s.name),
                      selected: draft.specialtyIds.contains(s.id),
                      onSelected: (_) => setState(
                        () => draft = draft.copyWith(
                          specialtyIds: _toggle(draft.specialtyIds, s.id),
                        ),
                      ),
                    ),
                ]),
                section('Natureza administrativa', 'Uma das opções (OU)', [
                  for (final n in [
                    AdministrativeNature.public,
                    AdministrativeNature.private,
                  ])
                    FilterChip(
                      label: Text(
                        n == AdministrativeNature.public
                            ? 'Pública'
                            : 'Privada',
                      ),
                      selected: draft.natures.contains(n),
                      onSelected: (_) => setState(
                        () => draft = draft.copyWith(
                          natures: _toggle(draft.natures, n),
                        ),
                      ),
                    ),
                ]),
                section(
                  'Acesso e funcionamento',
                  'Natureza privada pode ter atendimento SUS; são informações diferentes.',
                  [
                    FilterChip(
                      label: const Text('Atende pelo SUS'),
                      selected: draft.susOnly,
                      onSelected: (v) =>
                          setState(() => draft = draft.copyWith(susOnly: v)),
                    ),
                    FilterChip(
                      label: const Text('24 horas'),
                      selected: draft.only24h,
                      tooltip: 'Com atendimento escolhido, o próprio atendimento precisa ser 24h',
                      onSelected: (v) =>
                          setState(() => draft = draft.copyWith(only24h: v)),
                    ),
                  ],
                ),
                section('Plano de saúde', 'Uma das opções (OU)', [
                  if (catalog.plans.isEmpty)
                    unavailable(
                      'Nenhum plano de saúde confirmado na base atual.',
                    ),
                  for (final p in catalog.plans)
                    FilterChip(
                      label: Text(p.name),
                      selected: draft.planIds.contains(p.id),
                      onSelected: (_) => setState(
                        () => draft = draft.copyWith(
                          planIds: _toggle(draft.planIds, p.id),
                        ),
                      ),
                    ),
                ]),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Space.s16),
              child: OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.end,
                overflowSpacing: Space.s8,
                children: [
                  TextButton(
                    onPressed: draft.hasFilters
                        ? () => setState(() => draft = draft.clearFilters())
                        : null,
                    child: const Text('Limpar'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final notifier = ref.read(criteriaProvider.notifier);
                      Navigator.of(context).pop();
                      notifier.set(draft);
                    },
                    child: Text(
                      count == 0
                          ? 'Aplicar (nenhum resultado)'
                          : 'Ver $count ${count == 1 ? 'resultado' : 'resultados'}',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
