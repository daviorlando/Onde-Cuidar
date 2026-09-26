// Gera par de chaves Ed25519 para assinar o manifesto do catálogo.
//
// Uso (na pasta app/): dart run tool/catalog_keys.dart <key_id> <arquivo-privado>
// Exemplo: dart run tool/catalog_keys.dart catalog-key-1 ../secrets/catalog-key-1.json
//
// A chave privada NÃO deve entrar no Git (secrets/ está no .gitignore) nem em
// workflows de PR. A pública é impressa para ser adicionada a
// lib/app/config.dart (trustedCatalogKeys).
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'uso: dart run tool/catalog_keys.dart <key_id> <arquivo-privado>',
    );
    exit(64);
  }
  final [keyId, path] = args;
  final file = File(path);
  if (file.existsSync()) {
    stderr.writeln('$path já existe; não sobrescrevo chaves.');
    exit(1);
  }
  final pair = await Ed25519().newKeyPair();
  final private = await pair.extractPrivateKeyBytes();
  final public = (await pair.extractPublicKey()).bytes;
  await file.parent.create(recursive: true);
  await file.writeAsString(
    jsonEncode({
      'key_id': keyId,
      'private_seed_base64': base64.encode(private),
    }),
  );
  if (!Platform.isWindows) await Process.run('chmod', ['600', path]);
  stdout
    ..writeln('Chave privada gravada em $path (manter fora do Git).')
    ..writeln('Adicionar em lib/app/config.dart → trustedCatalogKeys:')
    ..writeln("  '$keyId': $public,");
}
