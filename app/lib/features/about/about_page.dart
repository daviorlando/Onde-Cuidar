import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/text.dart';

/// T08 Sobre, fontes e privacidade.
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final catalog = ref.watch(installedCatalogProvider).value?.catalog;
    final package = ref.watch(roadPackageProvider);
    final map = package.package?.manifest ?? package.bundled;

    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.s16, Space.s16, Space.s16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: Space.s4),
          ...children,
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Sobre')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.s32),
        children: [
          section('Onde Cuidar', [
            const Text(
              'Projeto extensionista para encontrar unidades de saúde em Petrolina–PE, '
              'consultar informações e calcular rotas mesmo sem internet. '
              'Não substitui orientação profissional nem atendimento de urgência: '
              'em emergência, ligue 192 (SAMU).',
            ),
            const SizedBox(height: Space.s8),
            Text('Aplicativo: versão $appVersion'),
            if (catalog != null) Text('Catálogo: versão ${catalog.version}'),
            if (map != null) Text('Mapa: ${map.region}, versão ${map.version}'),
          ]),
          section('De onde vêm os dados', [
            if (catalog != null)
              for (final s in catalog.sources)
                Text(
                  '• ${s.name}, consultado em ${formatDate(s.consultedAt)}.',
                ),
            const Text(
              '• Vias e mapa: © colaboradores do OpenStreetMap, disponíveis sob a licença '
              'Open Database License (ODbL) 1.0.',
            ),
            const SizedBox(height: Space.s8),
            if (catalog != null)
              Text(
                'Cobertura: ${catalog.coverage.published} unidades publicadas, '
                '${catalog.coverage.reviewed} conferidas pela curadoria. '
                '${catalog.coverage.note ?? ''}',
              ),
            const SizedBox(height: Space.s8),
            const Text(
              'Telefones, horários e serviços podem mudar. Quando uma informação não foi '
              'confirmada, o aplicativo mostra "Não informado" ou "Informação não confirmada".',
            ),
          ]),
          section('Privacidade', [
            const Text(
              'Sem conta, sem cadastro e sem estatísticas de uso. Sua localização só é pedida '
              'quando você toca em "Usar minha localização", fica apenas na memória do aparelho '
              'e não é enviada a nenhum servidor. O histórico de buscas não é guardado.',
            ),
            const SizedBox(height: Space.s8),
            const Text(
              'A internet é usada somente para verificar atualizações do catálogo, '
              'quando houver servidor configurado.',
            ),
          ]),
          section('Corrigir uma informação', [
            const Text(
              'Encontrou um dado errado? Informe a equipe do projeto Onde Cuidar, dizendo o nome '
              'da unidade e o que mudou. O canal oficial de correção será divulgado pela equipe.',
            ),
          ]),
          Padding(
            padding: const EdgeInsets.all(Space.s16),
            child: OutlinedButton(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'Onde Cuidar',
                applicationVersion: appVersion,
              ),
              child: const Text('Licenças de software'),
            ),
          ),
        ],
      ),
    );
  }
}
