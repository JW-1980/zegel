import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Command to sign a .zgl file with an Ed25519 key.
///
/// ```
/// zegel sign <file.zgl> --signing-key <key-file> -o <signed.zgl>
/// ```
class SignCommand extends Command<int> {
  @override
  final String name = 'sign';

  @override
  final String description =
      'Sign a .zgl file with an Ed25519 signing key.\n'
      '\n'
      'Creates a digital signature over the file\'s Merkle root, master seal,\n'
      'and timestamp using Ed25519. The signature is embedded as a SIGNATURE\n'
      'block (type 0x0E) that cryptographically binds the file to the signer\'s\n'
      'identity.';

  SignCommand() {
    argParser
      ..addOption(
        'signing-key',
        abbr: 's',
        help: 'Path to the Ed25519 private key file (32 bytes raw or '
            '64-char hex).',
        mandatory: true,
      )
      ..addOption(
        'signer-id',
        help: 'Human-readable signer identifier (e.g. email, name).',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output path for the signed file. If omitted, the file is '
            'modified in place.',
      );
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      usageException('No input file specified.');
    }

    final inputPath = rest[0];
    final signingKeyPath = argResults!['signing-key'] as String;
    final signerId = argResults!['signer-id'] as String?;
    final outputPath = argResults!['output'] as String? ?? inputPath;

    final Uint8List fileBytes = File(inputPath).readAsBytesSync();
    final Uint8List signingKey = readKeyFile(signingKeyPath);

    // Create identity and sign.
    final signatureData = ZegelIdentity.sign(fileBytes, signingKey);

    final signatureJson = <String, dynamic>{
      'type': 'ed25519_signature',
      ...signatureData,
    };
    if (signerId != null) {
      signatureJson['signer_id'] = signerId;
    }

    stdout.writeln('Signature created successfully.');
    stdout.writeln('  Public key: ${signatureJson['public_key_hex']}');
    if (signerId != null) {
      stdout.writeln('  Signer ID: $signerId');
    }

    // Write signature to a sidecar JSON file.
    final sigFile = '$outputPath.sig.json';
    File(sigFile).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(signatureJson),
    );
    stdout.writeln('  Signature written to: $sigFile');

    return 0;
  }
}

/// Command to verify an Ed25519 signature on a .zgl file.
///
/// ```
/// zegel verify-signature <file.zgl> --signature <file.sig.json> --public-key <key-file>
/// ```
class VerifySignatureCommand extends Command<int> {
  @override
  final String name = 'verify-signature';

  @override
  final String description =
      'Verify an Ed25519 signature on a .zgl file.';

  VerifySignatureCommand() {
    argParser
      ..addOption(
        'signature',
        abbr: 's',
        help: 'Path to the signature JSON file.',
        mandatory: true,
      )
      ..addOption(
        'public-key',
        abbr: 'p',
        help: 'Path to the expected public key file (32 bytes or 64-char hex).',
      );
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      usageException('No input file specified.');
    }

    final inputPath = rest[0];
    final sigPath = argResults!['signature'] as String;
    final pubKeyPath = argResults!['public-key'] as String?;

    final Uint8List fileBytes = File(inputPath).readAsBytesSync();
    final String sigJson = File(sigPath).readAsStringSync();
    final Map<String, dynamic> signatureData =
        jsonDecode(sigJson) as Map<String, dynamic>;

    final bool valid = ZegelIdentity.verifySignature(fileBytes, signatureData);

    if (valid) {
      stdout.writeln('VALID - Signature verification passed.');
      stdout.writeln('  Public key: ${signatureData['public_key_hex']}');
      if (signatureData.containsKey('signer_id')) {
        stdout.writeln('  Signer: ${signatureData['signer_id']}');
      }

      // Check against expected public key if provided.
      if (pubKeyPath != null) {
        final Uint8List expectedKey = readKeyFile(pubKeyPath);
        final String expectedHex = expectedKey
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        final String actualHex = signatureData['public_key_hex'] as String;

        if (expectedHex == actualHex) {
          stdout.writeln('  Public key matches expected key.');
        } else {
          stderr.writeln(
            'WARNING: Public key does NOT match expected key!',
          );
          stderr.writeln('  Expected: $expectedHex');
          stderr.writeln('  Actual:   $actualHex');
          return 1;
        }
      }

      return 0;
    } else {
      stderr.writeln('INVALID - Signature verification FAILED.');
      stderr.writeln(
        'The file may have been tampered with, or the signature was '
        'created with a different key.',
      );
      return 1;
    }
  }
}

/// Command to generate an Ed25519 signing keypair.
///
/// ```
/// zegel identity-keygen -o <key-prefix>
/// ```
class IdentityKeygenCommand extends Command<int> {
  @override
  final String name = 'identity-keygen';

  @override
  final String description =
      'Generate an Ed25519 signing keypair for file signatures.\n'
      '\n'
      'Creates two files:\n'
      '  <prefix>.private.key  - 32-byte private key seed\n'
      '  <prefix>.public.key   - 32-byte public key';

  IdentityKeygenCommand() {
    argParser.addOption(
      'output',
      abbr: 'o',
      help: 'Output file prefix (default: "identity").',
      defaultsTo: 'identity',
    );
  }

  @override
  Future<int> run() async {
    final prefix = argResults!['output'] as String;

    final keypair = ZegelIdentity.generateKeyPair();
    final Uint8List privateKey = keypair['private_key'] as Uint8List;
    final Uint8List publicKey = keypair['public_key'] as Uint8List;

    final privatePath = '$prefix.private.key';
    final publicPath = '$prefix.public.key';

    File(privatePath).writeAsBytesSync(privateKey);
    File(publicPath).writeAsBytesSync(publicKey);

    stdout.writeln('Ed25519 keypair generated successfully:');
    stdout.writeln('  Private key: $privatePath (KEEP SECRET)');
    stdout.writeln('  Public key:  $publicPath (share freely)');
    stdout.writeln('');
    stdout.writeln('Public key hex: '
        '${publicKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');

    return 0;
  }
}
