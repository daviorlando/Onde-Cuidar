// Prepara artefatos imutáveis de publicação do catálogo:
// catalog-<versão>.json.gz, manifest.json e manifest-<versão>.sig (base64).
//
// Uso (na pasta app/):
//   dart run tool/publish_catalog.dart ../data/catalog/catalog.json \
//       ../secrets/catalog-key-1.json <pasta-de-saída>
//
// Publicar primeiro o .json.gz e a assinatura; o manifest.json por último.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:onde_cuidar/app/config.dart';
import 'package:onde_cuidar/features/facilities/data/catalog_codec.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln(
      'uso: dart run tool/publish_catalog.dart <catalog.json> <chave-privada.json> <saída>',
    );
    exit(64);
  }
  final [catalogPath, keyPath, outPath] = args;
  final text = await File(catalogPath).readAsString();
  final catalog = decodeCatalog(text); // mesma validação usada pelo app
  final key =
      jsonDecode(await File(keyPath).readAsString()) as Map<String, Object?>;
  final keyId = key['key_id']! as String;
  final pair = await Ed25519().newKeyPairFromSeed(
    base64.decode(key['private_seed_base64']! as String),
  );

  final out = Directory(outPath)..createSync(recursive: true);
  final compressed = GZipCodec(level: 9).encode(utf8.encode(text));
  final file = 'catalog-${catalog.version}.json.gz';
  final signatureFile = 'manifest-${catalog.version}.sig';
  final manifest = utf8.encode(
    const JsonEncoder.withIndent(' ').convert({
      'schema_version': catalog.schemaVersion,
      'catalog_version': catalog.version,
      'min_app_version': appVersion,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'file': file,
      'bytes': compressed.length,
      'sha256': sha256.convert(compressed).toString(),
      'record_count': catalog.facilities.length,
      'key_id': keyId,
      'signature_file': signatureFile,
    }),
  );
  final signature = await Ed25519().sign(manifest, keyPair: pair);
  await File('${out.path}/$file').writeAsBytes(compressed);
  await File('${out.path}/$signatureFile')
      .writeAsString(base64.encode(signature.bytes));
  await File('${out.path}/manifest.json').writeAsBytes(manifest);
  stdout.writeln(
    'Catálogo ${catalog.version}: ${catalog.facilities.length} unidades, '
    '${compressed.length} bytes comprimidos, assinado com $keyId em ${out.path}.',
  );
}
