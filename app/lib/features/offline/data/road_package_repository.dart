import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../facilities/data/catalog_repository.dart';
import '../../routing/domain/road_graph.dart';

const bundledPackageAsset = 'assets/routing/petrolina-car.ocrg.gz';
const bundledManifestAsset = 'assets/routing/manifest.json';
const _packageFile = 'road-package.ocrg';
const _manifestFile = 'road-package.json';

class RoadPackageManifest {
  RoadPackageManifest(this.json);

  factory RoadPackageManifest.parse(String text) =>
      RoadPackageManifest(jsonDecode(text) as Map<String, Object?>);

  final Map<String, Object?> json;

  String get id => json['id']! as String;
  String get version => json['version']! as String;
  String get region => json['region']! as String;
  String get profile => json['profile']! as String;
  int get formatVersion => json['format_version']! as int;
  int get bytes => json['bytes']! as int;
  String get sha256 => json['sha256']! as String;
  int get compressedBytes => json['compressed_bytes']! as int;
  String get compressedSha256 => json['compressed_sha256']! as String;
  String get source => json['source']! as String;
  String get license => json['license']! as String;
  String? get osmTimestamp => json['osm_timestamp'] as String?;
  int get nodes => json['nodes']! as int;
  int get edges => json['edges']! as int;
}

class RoadPackageException implements Exception {
  RoadPackageException(this.message);
  final String message;

  @override
  String toString() => message;
}

class InstalledRoadPackage {
  const InstalledRoadPackage(this.manifest, this.bytes);
  final RoadPackageManifest manifest;
  final Uint8List bytes;
}

/// Pacote viário regional no diretório privado do app. Instalação atômica:
/// grava em arquivo temporário, verifica e só então substitui o anterior.
class RoadPackageRepository {
  RoadPackageRepository({required this.directory, required this.loadAsset});

  final Directory directory;
  final Future<Uint8List> Function(String key) loadAsset;

  File get _package => File('${directory.path}/$_packageFile');
  File get _manifest => File('${directory.path}/$_manifestFile');

  Future<RoadPackageManifest> bundledManifest() async =>
      RoadPackageManifest.parse(
        utf8.decode(await loadAsset(bundledManifestAsset)),
      );

  /// Nulo quando não instalado. Lança [RoadPackageException] se corrompido.
  Future<InstalledRoadPackage?> loadInstalled() async {
    if (!await _manifest.exists()) return null;
    final RoadPackageManifest manifest;
    try {
      manifest = RoadPackageManifest.parse(await _manifest.readAsString());
    } on Object {
      throw RoadPackageException('Descrição do pacote ilegível.');
    }
    if (!await _package.exists()) {
      throw RoadPackageException('Arquivo do pacote ausente.');
    }
    final bytes = await _package.readAsBytes();
    _verify(bytes, manifest);
    return InstalledRoadPackage(manifest, bytes);
  }

  /// Instala o pacote empacotado no APK. A versão anterior só é substituída
  /// depois de o novo arquivo passar por tamanho, hash e leitura do formato.
  Future<InstalledRoadPackage> installBundled() async {
    final manifest = await bundledManifest();
    final compressed = await loadAsset(bundledPackageAsset);
    if (compressed.length != manifest.compressedBytes ||
        sha256Hex(compressed) != manifest.compressedSha256) {
      throw RoadPackageException('Pacote empacotado corrompido.');
    }
    final bytes = Uint8List.fromList(gzip.decode(compressed));
    _verify(bytes, manifest);

    await directory.create(recursive: true);
    final tmpPackage = File('${_package.path}.tmp');
    final tmpManifest = File('${_manifest.path}.tmp');
    try {
      await tmpPackage.writeAsBytes(bytes, flush: true);
      await tmpManifest.writeAsString(jsonEncode(manifest.json), flush: true);
      await tmpPackage.rename(_package.path);
      // Manifesto por último: sem ele o pacote não é considerado instalado.
      await tmpManifest.rename(_manifest.path);
    } on FileSystemException catch (e) {
      await _deleteQuietly(tmpPackage);
      await _deleteQuietly(tmpManifest);
      final noSpace = e.osError?.errorCode == 28; // ENOSPC
      throw RoadPackageException(
        noSpace
            ? 'Espaço insuficiente no aparelho para o pacote de rotas.'
            : 'Não foi possível gravar o pacote (${e.message}).',
      );
    }
    return InstalledRoadPackage(manifest, bytes);
  }

  Future<void> remove() async {
    await _deleteQuietly(_manifest);
    await _deleteQuietly(_package);
  }

  void _verify(Uint8List bytes, RoadPackageManifest manifest) {
    if (manifest.formatVersion != roadGraphFormatVersion) {
      throw RoadPackageException('Formato de pacote incompatível com o app.');
    }
    if (bytes.length != manifest.bytes || sha256Hex(bytes) != manifest.sha256) {
      throw RoadPackageException('Pacote corrompido (hash divergente).');
    }
    try {
      RoadGraph.fromBytes(bytes);
    } on RoadGraphFormatException catch (e) {
      throw RoadPackageException(e.toString());
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Limpeza oportunista; ignorar.
    }
  }
}
