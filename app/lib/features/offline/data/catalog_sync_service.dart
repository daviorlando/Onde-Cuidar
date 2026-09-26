import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;

import '../../facilities/data/app_database.dart';
import '../../facilities/data/catalog_codec.dart';
import '../../facilities/data/catalog_repository.dart';

const maxManifestBytes = 16 * 1024;
const maxSignatureBytes = 1024;
const maxCompressedCatalogBytes = 20 * 1024 * 1024;
const maxCatalogBytes = 80 * 1024 * 1024;
const automaticInterval = Duration(hours: 24);
const retryBackoff = [
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 30),
];

enum SyncFailureKind {
  notConfigured,
  network,
  http,
  signature,
  integrity,
  format,
  downgrade,
  incompatible,
}

sealed class SyncOutcome {
  const SyncOutcome();
}

/// Automático adiado (intervalo de 24h ou espera após falha).
class SyncSkipped extends SyncOutcome {
  const SyncSkipped();
}

class SyncUpToDate extends SyncOutcome {
  const SyncUpToDate(this.version);
  final String version;
}

class SyncUpdated extends SyncOutcome {
  const SyncUpdated(this.version, this.recordCount);
  final String version;
  final int recordCount;
}

class SyncFailed extends SyncOutcome {
  const SyncFailed(this.kind, this.detail);
  final SyncFailureKind kind;
  final String detail;

  String get message => switch (kind) {
    SyncFailureKind.notConfigured =>
      'Servidor de atualização não configurado nesta versão.',
    SyncFailureKind.network =>
      'Sem acesso ao servidor. Os dados instalados continuam disponíveis.',
    SyncFailureKind.http => 'O servidor respondeu com erro ($detail).',
    SyncFailureKind.signature => 'Atualização recusada: assinatura inválida.',
    SyncFailureKind.integrity =>
      'Atualização recusada: arquivo corrompido ou incompleto.',
    SyncFailureKind.format => 'Atualização recusada: conteúdo inválido.',
    SyncFailureKind.downgrade =>
      'Atualização recusada: versão anterior à instalada.',
    SyncFailureKind.incompatible =>
      'Esta atualização exige uma versão mais nova do aplicativo.',
  };
}

class _SyncError implements Exception {
  _SyncError(this.kind, this.detail);
  final SyncFailureKind kind;
  final String detail;
}

/// Manifesto remoto do catálogo (bytes exatos assinados à parte).
class CatalogManifest {
  CatalogManifest._(this.json);

  factory CatalogManifest.parse(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      throw _SyncError(SyncFailureKind.format, 'manifesto malformado');
    }
    if (json is! Map<String, Object?>) {
      throw _SyncError(SyncFailureKind.format, 'manifesto não é objeto');
    }
    final m = CatalogManifest._(json);
    try {
      m.schemaVersion;
      m.catalogVersion;
      m.minAppVersion;
      m.file;
      m.bytes;
      m.sha256;
      m.recordCount;
      m.keyId;
      m.signatureFile;
      compareCatalogVersions(m.catalogVersion, m.catalogVersion);
    } on Object {
      throw _SyncError(SyncFailureKind.format, 'manifesto incompleto');
    }
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(m.file) ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(m.signatureFile)) {
      throw _SyncError(SyncFailureKind.format, 'nome de arquivo não permitido');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(m.sha256)) {
      throw _SyncError(SyncFailureKind.format, 'hash inválido');
    }
    return m;
  }

  final Map<String, Object?> json;

  int get schemaVersion => json['schema_version']! as int;
  String get catalogVersion => json['catalog_version']! as String;
  String get minAppVersion => json['min_app_version']! as String;
  String get file => json['file']! as String;
  int get bytes => json['bytes']! as int;
  String get sha256 => json['sha256']! as String;
  int get recordCount => json['record_count']! as int;
  String get keyId => json['key_id']! as String;
  String get signatureFile => json['signature_file']! as String;
}

/// Compara versões semânticas simples `X.Y.Z`.
int compareSemver(String a, String b) {
  List<int> parts(String v) =>
      v.split('+').first.split('.').map(int.parse).toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final c = pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return 0;
}

/// Sincronização unidirecional do catálogo. Serializada; em qualquer falha a
/// versão instalada permanece ativa.
class CatalogSyncService {
  CatalogSyncService({
    required this.db,
    required this.repository,
    required this.client,
    required this.manifestUrl,
    required this.trustedKeys,
    required this.appVersion,
    DateTime Function()? clock,
    this.timeout = const Duration(seconds: 20),
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final CatalogRepository repository;
  final http.Client client;

  /// HTTPS obrigatório; nulo quando não há servidor configurado.
  final Uri? manifestUrl;

  /// key_id → chave pública Ed25519 (32 bytes).
  final Map<String, List<int>> trustedKeys;
  final String appVersion;
  final Duration timeout;
  final DateTime Function() _clock;
  Future<SyncOutcome>? _running;

  bool get isConfigured => manifestUrl != null;

  /// Evita duas instalações simultâneas: chamadas concorrentes recebem o
  /// mesmo resultado.
  Future<SyncOutcome> refresh({bool manual = false}) {
    return _running ??= _refresh(manual).whenComplete(() => _running = null);
  }

  Future<SyncOutcome> _refresh(bool manual) async {
    final url = manifestUrl;
    if (url == null || url.scheme != 'https') {
      return const SyncFailed(SyncFailureKind.notConfigured, '');
    }
    final state = await db.syncState();
    final now = _clock().toUtc();
    if (!manual && !_dueForAutomatic(state, now)) return const SyncSkipped();

    await db.updateSyncState(SyncStatesCompanion(lastAttemptAt: Value(now)));
    try {
      final outcome = await _download(url, state.etag);
      await db.updateSyncState(
        SyncStatesCompanion(
          lastSuccessAt: Value(_clock().toUtc()),
          lastError: const Value(null),
          consecutiveFailures: const Value(0),
        ),
      );
      return outcome;
    } on Object catch (error) {
      final failure = switch (error) {
        _SyncError(:final kind, :final detail) => SyncFailed(kind, detail),
        TimeoutException() => const SyncFailed(
          SyncFailureKind.network,
          'tempo esgotado',
        ),
        SocketException() || http.ClientException() || HandshakeException() =>
          const SyncFailed(SyncFailureKind.network, 'sem conexão'),
        CatalogFormatException(:final message) => SyncFailed(
          SyncFailureKind.format,
          message,
        ),
        _ => SyncFailed(SyncFailureKind.format, error.runtimeType.toString()),
      };
      await db.updateSyncState(
        SyncStatesCompanion(
          lastError: Value(failure.message),
          consecutiveFailures: Value(state.consecutiveFailures + 1),
        ),
      );
      return failure;
    }
  }

  bool _dueForAutomatic(SyncState state, DateTime now) {
    final lastAttempt = state.lastAttemptAt;
    if (lastAttempt == null) return true;
    if (state.consecutiveFailures > 0) {
      final wait =
          retryBackoff[(state.consecutiveFailures - 1).clamp(
            0,
            retryBackoff.length - 1,
          )];
      // Após esgotar as tentativas curtas, volta ao intervalo normal.
      final limit = state.consecutiveFailures > retryBackoff.length
          ? automaticInterval
          : wait;
      return now.difference(lastAttempt) >= limit;
    }
    final lastSuccess = state.lastSuccessAt ?? lastAttempt;
    return now.difference(lastSuccess) >= automaticInterval;
  }

  Future<SyncOutcome> _download(Uri url, String? etag) async {
    final manifestResponse = await _get(
      url,
      maxManifestBytes,
      headers: {'If-None-Match': ?etag},
    );
    final installed = await repository.load();
    if (manifestResponse.statusCode == 304) {
      return SyncUpToDate(installed.catalog.version);
    }
    final manifestBytes = manifestResponse.bodyBytes;

    final manifest = CatalogManifest.parse(utf8.decode(manifestBytes));
    final signature = await _get(
      url.resolve(manifest.signatureFile),
      maxSignatureBytes,
    );
    await _verifySignature(manifestBytes, signature.bodyBytes, manifest.keyId);

    if (manifest.schemaVersion != supportedCatalogSchema) {
      throw _SyncError(
        SyncFailureKind.incompatible,
        'esquema ${manifest.schemaVersion}',
      );
    }
    if (compareSemver(manifest.minAppVersion, appVersion) > 0) {
      throw _SyncError(SyncFailureKind.incompatible, manifest.minAppVersion);
    }
    final order = compareCatalogVersions(
      manifest.catalogVersion,
      installed.catalog.version,
    );
    if (order < 0) {
      throw _SyncError(SyncFailureKind.downgrade, manifest.catalogVersion);
    }
    if (order == 0) {
      await _saveEtag(manifestResponse);
      return SyncUpToDate(installed.catalog.version);
    }
    if (manifest.bytes > maxCompressedCatalogBytes) {
      throw _SyncError(SyncFailureKind.integrity, 'arquivo excede o limite');
    }

    final file = await _get(url.resolve(manifest.file), manifest.bytes);
    final compressed = file.bodyBytes;
    if (compressed.length != manifest.bytes ||
        sha256Hex(compressed) != manifest.sha256) {
      throw _SyncError(SyncFailureKind.integrity, 'hash ou tamanho divergente');
    }
    final payload = _gunzipLimited(compressed);
    final catalog = decodeCatalog(payload);
    if (catalog.version != manifest.catalogVersion ||
        catalog.facilities.length != manifest.recordCount) {
      throw _SyncError(
        SyncFailureKind.integrity,
        'conteúdo não confere com o manifesto',
      );
    }
    await repository.activateValidated(catalog, payload);
    await _saveEtag(manifestResponse);
    return SyncUpdated(catalog.version, catalog.facilities.length);
  }

  Future<void> _saveEtag(http.Response response) async {
    final etag = response.headers['etag'];
    if (etag != null) {
      await db.updateSyncState(SyncStatesCompanion(etag: Value(etag)));
    }
  }

  Future<void> _verifySignature(
    List<int> message,
    List<int> signature,
    String keyId,
  ) async {
    final key = trustedKeys[keyId];
    if (key == null) {
      throw _SyncError(SyncFailureKind.signature, 'chave desconhecida');
    }
    final bytes = _decodeSignature(signature);
    final valid = await Ed25519().verify(
      message,
      signature: Signature(
        bytes,
        publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
      ),
    );
    if (!valid) throw _SyncError(SyncFailureKind.signature, 'inválida');
  }

  /// Assinatura destacada: 64 bytes brutos ou em base64.
  List<int> _decodeSignature(List<int> raw) {
    if (raw.length == 64) return raw;
    try {
      final decoded = base64.decode(ascii.decode(raw).trim());
      if (decoded.length == 64) return decoded;
    } on FormatException {
      // Tratado abaixo.
    }
    throw _SyncError(SyncFailureKind.signature, 'formato');
  }

  Future<http.Response> _get(
    Uri url,
    int maxBytes, {
    Map<String, String> headers = const {},
  }) async {
    if (url.scheme != 'https' || url.host != manifestUrl!.host) {
      throw _SyncError(SyncFailureKind.format, 'URL não permitida');
    }
    final request = http.Request('GET', url)
      ..headers.addAll(headers)
      ..followRedirects = false;
    final response = await client.send(request).timeout(timeout);
    if (response.statusCode == 304) {
      return http.Response('', 304, headers: response.headers);
    }
    if (response.statusCode != 200) {
      throw _SyncError(SyncFailureKind.http, 'HTTP ${response.statusCode}');
    }
    final declared = response.contentLength;
    if (declared != null && declared > maxBytes) {
      throw _SyncError(SyncFailureKind.integrity, 'resposta excede o limite');
    }
    final body = <int>[];
    await for (final chunk in response.stream.timeout(timeout)) {
      body.addAll(chunk);
      if (body.length > maxBytes) {
        throw _SyncError(SyncFailureKind.integrity, 'resposta excede o limite');
      }
    }
    return http.Response.bytes(body, 200, headers: response.headers);
  }

  String _gunzipLimited(List<int> compressed) {
    final output = BytesBuilder(copy: false);
    final sink = ByteConversionSink.withCallback((bytes) => output.add(bytes));
    final decoder = gzip.decoder.startChunkedConversion(
      _LimitedSink(sink, maxCatalogBytes),
    );
    try {
      decoder
        ..add(compressed)
        ..close();
    } on _SyncError {
      rethrow;
    } on FormatException {
      throw _SyncError(SyncFailureKind.integrity, 'gzip inválido');
    }
    try {
      return utf8.decode(output.takeBytes());
    } on FormatException {
      throw _SyncError(SyncFailureKind.format, 'texto não UTF-8');
    }
  }
}

/// Interrompe a descompressão acima do limite (proteção contra "zip bomb").
class _LimitedSink implements Sink<List<int>> {
  _LimitedSink(this._inner, this._limit);
  final Sink<List<int>> _inner;
  final int _limit;
  int _count = 0;

  @override
  void add(List<int> data) {
    _count += data.length;
    if (_count > _limit) {
      throw _SyncError(
        SyncFailureKind.integrity,
        'descompressão excede o limite',
      );
    }
    _inner.add(data);
  }

  @override
  void close() => _inner.close();
}
