import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../app/tone_card.dart';
import '../../../core/text.dart';
import '../../routing/presentation/route_page.dart';
import '../domain/facility.dart';
import 'labels.dart';

/// T04 Detalhe da unidade.
class FacilityDetailPage extends ConsumerWidget {
  const FacilityDetailPage({required this.facility, super.key});
  final Facility facility;

  Future<void> _call(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível abrir o discador. Telefone: ${formatPhone(phone)}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(installedCatalogProvider).value!.catalog;
    final f = facility;
    final theme = Theme.of(context);
    final offered = f.services
        .where((s) => s.availability == TriState.yes)
        .toList();

    Widget field(IconData icon, String label, String value, {String? hint}) =>
        ListTile(
          leading: Icon(icon),
          title: Text(label, style: theme.textTheme.labelLarge),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: theme.textTheme.bodyLarge),
              if (hint != null) Text(hint, style: theme.textTheme.bodySmall),
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Unidade')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.s32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s16,
              Space.s8,
              Space.s16,
              0,
            ),
            child: Semantics(
              header: true,
              child: Text(f.name, style: theme.textTheme.headlineSmall),
            ),
          ),
          if (f.legalName != null && f.legalName != f.name)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s16),
              child: Text(f.legalName!, style: theme.textTheme.bodyMedium),
            ),
          ToneCard(
            tone: f.reviewStatus == ReviewStatus.pending
                ? Tone.attention
                : Tone.info,
            margin: const EdgeInsets.all(Space.s16),
            child: Padding(
              padding: const EdgeInsets.all(Space.s12),
              child: Row(
                children: [
                  Icon(
                    f.reviewStatus == ReviewStatus.pending
                        ? Icons.help_outline
                        : Icons.verified_outlined,
                  ),
                  const SizedBox(width: Space.s12),
                  Expanded(
                    child: Text(
                      f.verifiedAt == null
                          ? '${reviewLabel(f)}. Confirme por telefone antes de ir.'
                          : '${reviewLabel(f)}. Dados verificados em ${formatDate(f.verifiedAt!)}.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s16),
            child: Wrap(
              spacing: Space.s8,
              runSpacing: Space.s8,
              children: [
                if (f.phone != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.call),
                    label: Text('Ligar ${formatPhone(f.phone!)}'),
                    onPressed: () => _call(context, f.phone!),
                  ),
                if (f.location != null)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.directions_car),
                    label: const Text('Traçar rota'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RoutePage(facility: f),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.s8),
          field(
            Icons.place_outlined,
            'Endereço',
            f.address.singleLine,
            hint: f.location == null
                ? 'Sem coordenada verificada: não é possível calcular rota.'
                : (f.address.postalCode == null
                      ? null
                      : 'CEP ${f.address.postalCode}'),
          ),
          field(
            Icons.phone_outlined,
            'Telefone',
            f.phone == null ? notInformed : formatPhone(f.phone!),
            hint: f.phone == null
                ? null
                : 'Telefone de cadastro; pode estar desatualizado.',
          ),
          field(
            Icons.account_balance_outlined,
            'Natureza administrativa',
            natureLabel(f.nature),
          ),
          field(
            Icons.local_hospital_outlined,
            'Atendimento pelo SUS',
            susLabel(f.susAccess),
          ),
          field(
            Icons.category_outlined,
            'Tipo de estabelecimento',
            f.facilityType?.name ?? notInformed,
          ),
          field(
            Icons.schedule,
            'Funcionamento',
            h24Label(f.is24h),
            hint: f.hoursDescription == null
                ? 'Horários detalhados não informados.'
                : 'Turno no cadastro: ${f.hoursDescription!.toLowerCase()}',
          ),
          field(
            Icons.medical_services_outlined,
            'Serviços',
            offered.isEmpty
                ? notInformed
                : offered
                      .map((s) {
                        final name =
                            catalog.service(s.serviceId)?.name ?? s.serviceId;
                        return s.is24h == TriState.yes ? '$name (24h)' : name;
                      })
                      .join('\n'),
            hint: 'Outros serviços: não informados.',
          ),
          field(
            Icons.health_and_safety_outlined,
            'Especialidades',
            f.specialties.where((s) => s.availability == TriState.yes).isEmpty
                ? notInformed
                : f.specialties
                      .where((s) => s.availability == TriState.yes)
                      .map(
                        (s) =>
                            catalog.specialtyName(s.specialtyId) ??
                            s.specialtyId,
                      )
                      .join('\n'),
          ),
          field(
            Icons.card_membership_outlined,
            'Planos de saúde',
            f.planAcceptance.isEmpty
                ? notInformed
                : f.planAcceptance
                      .map((p) {
                        final name = catalog.planName(p.planId) ?? p.planId;
                        final status = triLabel(p.accepted);
                        final conditions = p.conditions == null
                            ? ''
                            : ' — ${p.conditions}';
                        final date = p.verifiedAt == null
                            ? ''
                            : ' (verificado em ${formatDate(p.verifiedAt!)})';
                        return '$name: $status$conditions$date';
                      })
                      .join('\n'),
          ),
          field(
            Icons.login_outlined,
            'Como ter acesso',
            f.accessInstructions ?? notInformed,
          ),
          for (final note in f.notes)
            field(Icons.warning_amber_outlined, 'Observação', note),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(Space.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fontes', style: theme.textTheme.titleSmall),
                for (final p in f.provenance)
                  Text(
                    '${catalog.source(p.sourceId)?.name ?? p.sourceId}: consultado em '
                    '${formatDate(p.consultedAt)}'
                    '${p.sourceUpdatedAt == null ? '' : '; atualizado na fonte em ${p.sourceUpdatedAt}'}.',
                    style: theme.textTheme.bodySmall,
                  ),
                if (f.cnes != null)
                  Text('CNES ${f.cnes}', style: theme.textTheme.bodySmall),
                Text(
                  'Versão do catálogo: ${catalog.version}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
