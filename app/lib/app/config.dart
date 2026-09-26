/// Configuração de build. Nada aqui é segredo: o app só carrega chaves públicas.
library;

/// Versão exibida e usada para `min_app_version`; manter igual ao pubspec.
const appVersion = '0.1.0';

/// Manifesto remoto do catálogo. Vazio enquanto não houver hospedagem escolhida
/// Definir com
/// `--dart-define=CATALOG_MANIFEST_URL=https://…/manifest.json`.
const _manifestUrl = String.fromEnvironment('CATALOG_MANIFEST_URL');

final Uri? catalogManifestUrl = _manifestUrl.isEmpty
    ? null
    : Uri.parse(_manifestUrl);

/// Chaves públicas Ed25519 aceitas para o manifesto do catálogo (key_id → bytes).
/// A chave privada correspondente fica fora do Git (ver tool/catalog_keys.dart).
/// Vazio até o responsável gerar a chave de publicação.
const Map<String, List<int>> trustedCatalogKeys = {};
