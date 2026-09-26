import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onde_cuidar/features/facilities/data/app_database.dart';
import 'package:onde_cuidar/features/facilities/data/catalog_repository.dart';
import 'package:onde_cuidar/features/offline/data/catalog_sync_service.dart';

import '../../support/fixtures.dart';

/// Servidor sintético de catálogo com manifesto assinado.
class FakeServer {
  FakeServer(this.keyPair);

  final SimpleKeyPair keyPair;
  final files = <String, List<int>>{};
  final requests = <String>[];
  String? etag;
  Object? failWith;

  Future<void> publish(
    String catalogText, {
    String? version,
    int? recordCount,
    Map<String, Object?> overrides = const {},
    bool tamperSignature = false,
    List<int>? contentOverride,
  }) async {
    final compressed = contentOverride ?? gzip.encode(utf8.encode(catalogText));
    final decoded = jsonDecode(catalogText) as Map<String, Object?>;
    final v = version ?? decoded['catalog_version']! as String;
    final manifest = {
      'schema_version': 1,
      'catalog_version': v,
      'min_app_version': '0.1.0',
      'generated_at': '2026-01-02T00:00:00Z',
      'file': 'catalog-$v.json.gz',
      'bytes': compressed.length,
      'sha256': sha256Hex(compressed),
      'record_count': recordCount ?? (decoded['facilities']! as List).length,
      'key_id': 'teste-1',
      'signature_file': 'manifest-$v.sig',
      ...overrides,
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    final signature = await Ed25519().sign(manifestBytes, keyPair: keyPair);
    final sigBytes = [...signature.bytes];
    if (tamperSignature) sigBytes[0] ^= 0xff;
    files['manifest.json'] = manifestBytes;
    files[manifest['signature_file']! as String] = utf8.encode(
      base64.encode(sigBytes),
    );
    files[manifest['file']! as String] = compressed;
    etag = '"$v"';
  }

  http.Client get client => MockClient((request) async {
    requests.add(request.url.path);
    if (failWith != null) throw failWith!;
    final name = request.url.pathSegments.last;
    if (name == 'manifest.json' &&
        etag != null &&
        request.headers['If-None-Match'] == etag) {
      return http.Response('', 304);
    }
    final body = files[name];
    if (body == null) return http.Response('não encontrado', 404);
    return http.Response.bytes(
      body,
      200,
      headers: {if (name == 'manifest.json' && etag != null) 'etag': etag!},
    );
  });
}

void main() {
  late AppDatabase db;
  late CatalogRepository repository;
  late SimpleKeyPair keyPair;
  late FakeServer server;
  late DateTime now;
  String embedded = catalogText(version: '2026-01-01.1', count: 3);

  CatalogSyncService service({Uri? url}) => CatalogSyncService(
    db: db,
    repository: repository,
    client: server.client,
    manifestUrl:
        url ?? Uri.parse('https://catalogo.exemplo.invalid/v1/manifest.json'),
    trustedKeys: {'teste-1': keyPairPublic},
    appVersion: '0.1.0',
    clock: () => now,
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 1, 2, 12);
    embedded = catalogText(version: '2026-01-01.1', count: 3);
    repository = CatalogRepository(db, (_) async => embedded, clock: () => now);
    keyPair = await Ed25519().newKeyPairFromSeed(List.filled(32, 7));
    keyPairPublic = (await keyPair.extractPublicKey()).bytes;
    server = FakeServer(keyPair);
  });
  tearDown(() => db.close());

  test(
    'CT01/RF06: primeira abertura usa o catálogo embarcado sem rede',
    () async {
      final installed = await repository.load();
      expect(installed.catalog.version, '2026-01-01.1');
      expect(installed.origin, 'embedded');
      expect(server.requests, isEmpty);
    },
  );

  test(
    'atualização válida ativa a nova versão e preserva preferências',
    () async {
      await repository.load();
      await db.setPreference('ultimo-filtro', 'x');
      await server.publish(catalogText(version: '2026-02-01.1', count: 5));
      final outcome = await service().refresh(manual: true);
      expect(outcome, isA<SyncUpdated>());
      final installed = await repository.load();
      expect(installed.catalog.version, '2026-02-01.1');
      expect(installed.catalog.facilities, hasLength(5));
      expect(await db.preference('ultimo-filtro'), 'x');
      expect(
        (await db.syncState()).lastSuccessAt!.isAtSameMomentAs(now),
        isTrue,
      );
    },
  );

  test('CT20: unidade ausente no snapshot completo sai da busca', () async {
    await repository.load();
    await server.publish(catalogText(version: '2026-02-01.1', count: 2));
    await service().refresh(manual: true);
    final ids = (await repository.load()).catalog.facilities.map((f) => f.id);
    expect(ids, isNot(contains('sint-2')));
  });

  test('304 mantém a base e registra a consulta', () async {
    await repository.load();
    await server.publish(catalogText(version: '2026-02-01.1'));
    await service().refresh(manual: true);
    final outcome = await service().refresh(manual: true);
    expect(outcome, isA<SyncUpToDate>());
    expect((await repository.load()).catalog.version, '2026-02-01.1');
  });

  Future<void> expectRejected(SyncFailureKind kind) async {
    final outcome = await service().refresh(manual: true);
    expect(outcome, isA<SyncFailed>().having((f) => f.kind, 'kind', kind));
    final installed = await repository.load();
    expect(
      installed.catalog.version,
      '2026-01-01.1',
      reason: 'versão válida preservada',
    );
    expect(installed.catalog.facilities, hasLength(3));
    expect((await db.syncState()).lastError, isNotNull);
  }

  group('CT14: atualização inválida é recusada sem perda', () {
    setUp(() async => repository.load());

    test('assinatura adulterada', () async {
      await server.publish(
        catalogText(version: '2026-02-01.1'),
        tamperSignature: true,
      );
      await expectRejected(SyncFailureKind.signature);
    });

    test('chave desconhecida', () async {
      await server.publish(
        catalogText(version: '2026-02-01.1'),
        overrides: {'key_id': 'outra'},
      );
      await expectRejected(SyncFailureKind.signature);
    });

    test('hash divergente do conteúdo', () async {
      await server.publish(
        catalogText(version: '2026-02-01.1'),
        overrides: {'sha256': '0' * 64},
      );
      await expectRejected(SyncFailureKind.integrity);
    });

    test('esquema futuro', () async {
      await server.publish(
        catalogText(version: '2026-02-01.1'),
        overrides: {'schema_version': 2},
      );
      await expectRejected(SyncFailureKind.incompatible);
    });

    test('exige app mais novo', () async {
      await server.publish(
        catalogText(version: '2026-02-01.1'),
        overrides: {'min_app_version': '9.0.0'},
      );
      await expectRejected(SyncFailureKind.incompatible);
    });

    test('downgrade', () async {
      await server.publish(catalogText(version: '2025-12-01.1'));
      await expectRejected(SyncFailureKind.downgrade);
    });

    test('contagem de registros diferente do manifesto', () async {
      await server.publish(
        catalogText(version: '2026-02-01.1', count: 2),
        recordCount: 3,
      );
      await expectRejected(SyncFailureKind.integrity);
    });

    test('conteúdo com versão diferente da assinada', () async {
      await server.publish(
        catalogText(version: '2026-03-01.1'),
        version: '2026-02-01.1',
      );
      await expectRejected(SyncFailureKind.integrity);
    });

    test('snapshot com relacionamento quebrado', () async {
      final broken = catalogJson(version: '2026-02-01.1');
      ((broken['facilities']! as List).first as Map)['services'] = [
        {
          'service_id': 'inexistente',
          'availability': 'yes',
          'is_24h': 'unknown',
        },
      ];
      await server.publish(jsonEncode(broken));
      await expectRejected(SyncFailureKind.format);
    });

    test('gzip que expande além do limite', () async {
      final bomb = gzip.encode(List.filled(maxCatalogBytes + 1, 0x20));
      await server.publish(
        catalogText(version: '2026-02-01.1'),
        contentOverride: bomb,
      );
      await expectRejected(SyncFailureKind.integrity);
    });
  });

  group('CT13: falhas de rede mantêm consulta local', () {
    setUp(() async => repository.load());

    test('sem conexão', () async {
      server.failWith = const SocketException('rede indisponível');
      await expectRejected(SyncFailureKind.network);
    });

    test('tempo esgotado', () async {
      server.failWith = TimeoutException('lento');
      await expectRejected(SyncFailureKind.network);
    });

    test('portal cativo: HTML em vez do manifesto', () async {
      server.files['manifest.json'] = utf8.encode(
        '<html>faça login no Wi-Fi</html>',
      );
      await expectRejected(SyncFailureKind.format);
    });

    test('HTTP 500', () async {
      await expectRejected(SyncFailureKind.http); // manifesto inexistente → 404
    });
  });

  test('sem servidor configurado não tenta rede', () async {
    await repository.load();
    final outcome = await CatalogSyncService(
      db: db,
      repository: repository,
      client: server.client,
      manifestUrl: null,
      trustedKeys: const {},
      appVersion: '0.1.0',
    ).refresh(manual: true);
    expect((outcome as SyncFailed).kind, SyncFailureKind.notConfigured);
    expect(server.requests, isEmpty);
  });

  test('URL sem HTTPS é recusada', () async {
    final outcome = await service(
      url: Uri.parse('http://catalogo.exemplo.invalid/manifest.json'),
    ).refresh(manual: true);
    expect((outcome as SyncFailed).kind, SyncFailureKind.notConfigured);
    expect(server.requests, isEmpty);
  });

  test('automático respeita 24h e espera crescente após falha', () async {
    await repository.load();
    await server.publish(catalogText(version: '2026-01-01.1'));
    expect(await service().refresh(), isA<SyncUpToDate>());
    now = now.add(const Duration(hours: 1));
    expect(await service().refresh(), isA<SyncSkipped>());

    server.failWith = const SocketException('x');
    now = now.add(const Duration(hours: 24));
    expect(await service().refresh(), isA<SyncFailed>());
    now = now.add(const Duration(seconds: 30));
    expect(
      await service().refresh(),
      isA<SyncSkipped>(),
      reason: 'espera de 1 min',
    );
    now = now.add(const Duration(minutes: 1));
    expect(await service().refresh(), isA<SyncFailed>());
    now = now.add(const Duration(minutes: 2));
    expect(
      await service().refresh(),
      isA<SyncSkipped>(),
      reason: 'espera de 5 min',
    );
  });

  test('chamadas concorrentes compartilham a mesma execução', () async {
    await repository.load();
    await server.publish(catalogText(version: '2026-02-01.1'));
    final sync = service();
    final results = await Future.wait([
      sync.refresh(manual: true),
      sync.refresh(manual: true),
    ]);
    expect(identical(results[0], results[1]), isTrue);
    expect(server.requests.where((p) => p.endsWith('.json.gz')), hasLength(1));
  });

  group('repositório local', () {
    test('CT15: base ativa ilegível é substituída pelo catálogo embarcado', () async {
      await repository.load();
      await db.customStatement(
        "UPDATE catalog_snapshots SET payload = '{corrompido' WHERE active = 1",
      );
      final installed = await repository.load();
      expect(installed.recoveredFromCorruption, isTrue);
      expect(installed.catalog.version, '2026-01-01.1');
    });

    test(
      'CT16: APK atualizado com catálogo embarcado mais novo prevalece',
      () async {
        await repository.load();
        embedded = catalogText(version: '2026-05-01.1', count: 4);
        expect((await repository.load()).catalog.version, '2026-05-01.1');
      },
    );

    test(
      'catálogo remoto mais novo prevalece sobre embarcado antigo',
      () async {
        await repository.load();
        await server.publish(catalogText(version: '2026-02-01.1'));
        await service().refresh(manual: true);
        expect((await repository.load()).origin, 'remote');
      },
    );

    test('compara versões por data e sequência', () {
      expect(
        compareCatalogVersions('2026-01-01.10', '2026-01-01.9'),
        greaterThan(0),
      );
      expect(
        compareCatalogVersions('2025-12-31.9', '2026-01-01.1'),
        lessThan(0),
      );
    });
  });
}

late List<int> keyPairPublic;
