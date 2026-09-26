import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/text.dart';
import '../data/catalog_sync_service.dart';

String _megabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';

/// T07 Dados e mapas offline.
class OfflinePage extends ConsumerWidget {
  const OfflinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final installed = ref.watch(installedCatalogProvider).value;
    final sync = ref.watch(syncControllerProvider);
    final syncService = ref.watch(syncServiceProvider);
    final package = ref.watch(roadPackageProvider);
    final controller = ref.read(roadPackageProvider.notifier);

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.s16,
        Space.s24,
        Space.s16,
        Space.s8,
      ),
      child: Semantics(
        header: true,
        child: Text(text, style: theme.textTheme.titleLarge),
      ),
    );
    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s16,
        vertical: Space.s4,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );

    final lastOutcome = sync.lastOutcome;
    final syncState = sync.state;
    final catalog = installed?.catalog;
    final manifest = package.package?.manifest ?? package.bundled;

    return Scaffold(
      appBar: AppBar(title: const Text('Dados e mapas offline')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.s32),
        children: [
          heading('Informações das unidades'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Space.s16),
            child: Text(
              'Ficam guardadas no aparelho e funcionam sem internet.',
            ),
          ),
          if (catalog != null) ...[
            line('Versão', catalog.version),
            line(
              'Origem',
              installed!.origin == 'embedded'
                  ? 'instalada com o aplicativo'
                  : 'atualização baixada',
            ),
            line('Instalada em', formatDateTime(installed.importedAt)),
            line('Unidades publicadas', '${catalog.coverage.published}'),
            line('Conferidas pela curadoria', '${catalog.coverage.reviewed}'),
            if (catalog.coverage.note != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s16,
                  vertical: Space.s4,
                ),
                child: Text(
                  catalog.coverage.note!,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
          line(
            'Última verificação',
            syncState?.lastAttemptAt == null
                ? 'nunca'
                : formatDateTime(syncState!.lastAttemptAt!),
          ),
          if (syncState?.lastSuccessAt != null)
            line(
              'Última verificação bem-sucedida',
              formatDateTime(syncState!.lastSuccessAt!),
            ),
          if (lastOutcome != null)
            Padding(
              padding: const EdgeInsets.all(Space.s16),
              child: Semantics(
                liveRegion: true,
                child: Text(switch (lastOutcome) {
                  SyncUpdated(:final version, :final recordCount) =>
                    'Atualizado para a versão $version ($recordCount unidades).',
                  SyncUpToDate() => 'Você já tem a versão mais recente.',
                  SyncSkipped() => 'Verificação automática adiada.',
                  SyncFailed() => lastOutcome.message,
                }),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s16),
            child: Row(
              children: [
                FilledButton.icon(
                  icon: sync.running
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(
                    sync.running ? 'Verificando…' : 'Verificar atualização',
                  ),
                  onPressed: sync.running || !syncService.isConfigured
                      ? null
                      : () => ref
                            .read(syncControllerProvider.notifier)
                            .refresh(manual: true),
                ),
              ],
            ),
          ),
          if (!syncService.isConfigured)
            Padding(
              padding: const EdgeInsets.all(Space.s16),
              child: Text(
                'Esta versão ainda não tem servidor de atualização configurado. '
                'Os dados mudam somente com uma nova versão do aplicativo.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          heading('Mapa e rotas sem internet'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: Space.s16),
            child: Text(
              'Com o mapa da região instalado, o aplicativo calcula rotas novas no próprio aparelho, '
              'sem internet, dentro da área coberta.',
            ),
          ),
          if (manifest != null) ...[
            line('Região', manifest.region),
            line(
              'Perfil',
              manifest.profile == 'car' ? 'automóvel' : manifest.profile,
            ),
            line('Versão do mapa', manifest.version),
            if (manifest.osmTimestamp != null &&
                manifest.osmTimestamp!.isNotEmpty)
              line(
                'Dados do OpenStreetMap de',
                manifest.osmTimestamp!.substring(0, 10),
              ),
            line('Tamanho no aparelho', _megabytes(manifest.bytes)),
            line('Fonte', manifest.source),
            line('Licença', manifest.license),
          ],
          Padding(
            padding: const EdgeInsets.all(Space.s16),
            child: Semantics(
              liveRegion: true,
              child: Text(switch (package.status) {
                PackageStatus.checking => 'Verificando mapa instalado…',
                PackageStatus.notInstalled => 'Mapa não instalado.',
                PackageStatus.installing => 'Instalando e verificando o mapa…',
                PackageStatus.installed => 'Mapa instalado e verificado.',
                PackageStatus.failed => 'Problema no mapa: ${package.error}',
              }, style: theme.textTheme.titleSmall),
            ),
          ),
          if (package.status == PackageStatus.installed &&
              package.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s16),
              child: Text(
                'A última tentativa falhou (${package.error}); o mapa anterior foi mantido.',
              ),
            ),
          if (package.status == PackageStatus.installing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Space.s16),
              child: LinearProgressIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s16),
            child: Wrap(
              spacing: Space.s8,
              runSpacing: Space.s8,
              children: [
                if (package.status == PackageStatus.notInstalled ||
                    package.status == PackageStatus.failed)
                  FilledButton.icon(
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: Text(
                      manifest == null
                          ? 'Instalar mapa da região'
                          : 'Instalar mapa da região (${_megabytes(manifest.bytes)})',
                    ),
                    onPressed: controller.install,
                  ),
                if (package.status == PackageStatus.installed) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Verificar integridade'),
                    onPressed: controller.verify,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remover mapa'),
                    onPressed: controller.remove,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
