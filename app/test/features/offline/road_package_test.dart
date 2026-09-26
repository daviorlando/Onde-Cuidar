import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onde_cuidar/features/facilities/data/catalog_repository.dart';
import 'package:onde_cuidar/features/offline/data/road_package_repository.dart';

import '../../support/fixtures.dart';

Map<String, Uint8List> bundle(
  Uint8List graph, {
  Uint8List? compressedOverride,
}) {
  final compressed =
      compressedOverride ?? Uint8List.fromList(gzip.encode(graph));
  final manifest = {
    'id': 'teste-car',
    'format_version': 1,
    'version': '2026-01-01.1',
    'region': 'Teste',
    'profile': 'car',
    'bytes': graph.length,
    'sha256': sha256Hex(graph),
    'compressed_bytes': compressed.length,
    'compressed_sha256': sha256Hex(compressed),
    'source': 'sintético',
    'license': 'teste',
    'nodes': 2,
    'edges': 2,
  };
  return {
    bundledPackageAsset: compressed,
    bundledManifestAsset: Uint8List.fromList(utf8.encode(jsonEncode(manifest))),
  };
}

void main() {
  late Directory dir;
  final graph = encodeGraph([(-9.4, -40.5), (-9.4, -40.49)], [(0, 1), (1, 0)]);

  setUp(() async => dir = await Directory.systemTemp.createTemp('pacote'));
  tearDown(() => dir.delete(recursive: true));

  RoadPackageRepository repo(Map<String, Uint8List> assets) =>
      RoadPackageRepository(directory: dir, loadAsset: (k) async => assets[k]!);

  test('CT01: sem pacote instalado o estado é explícito', () async {
    expect(await repo(bundle(graph)).loadInstalled(), isNull);
  });

  test('instala, verifica e remove o pacote', () async {
    final r = repo(bundle(graph));
    await r.installBundled();
    final installed = await r.loadInstalled();
    expect(installed!.manifest.region, 'Teste');
    expect(installed.bytes, graph);
    expect(dir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
    await r.remove();
    expect(await r.loadInstalled(), isNull);
  });

  test('CT12: pacote corrompido no disco é detectado', () async {
    final r = repo(bundle(graph));
    await r.installBundled();
    final file = File('${dir.path}/road-package.ocrg');
    final bytes = await file.readAsBytes();
    bytes[40] ^= 0xff;
    await file.writeAsBytes(bytes);
    expect(r.loadInstalled(), throwsA(isA<RoadPackageException>()));
  });

  test('CT12: arquivo ausente com manifesto presente é detectado', () async {
    final r = repo(bundle(graph));
    await r.installBundled();
    await File('${dir.path}/road-package.ocrg').delete();
    expect(r.loadInstalled(), throwsA(isA<RoadPackageException>()));
  });

  test('CT12: pacote de origem corrompido não substitui o instalado', () async {
    await repo(bundle(graph)).installBundled();
    final bad = bundle(graph);
    final broken = Uint8List.fromList(bad[bundledPackageAsset]!)..[20] ^= 0xff;
    final r = repo({...bad, bundledPackageAsset: broken});
    expect(r.installBundled(), throwsA(isA<RoadPackageException>()));
    final still = await repo(bundle(graph)).loadInstalled();
    expect(still!.bytes, graph);
  });
}
