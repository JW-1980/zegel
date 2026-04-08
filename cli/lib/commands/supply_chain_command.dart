import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Command to verify the integrity of a Zegel binary.
///
/// ```
/// zegel verify-binary --binary <path> --expected-hash <hex>
/// ```
class VerifyBinaryCommand extends Command<int> {
  @override
  final String name = 'verify-binary';

  @override
  final String description =
      'Verify the integrity of a Zegel binary against a known-good hash.\n'
      '\n'
      'This helps detect if your copy of the Zegel tool has been modified\n'
      'by a supply chain attack, trojanized download, or other compromise.';

  VerifyBinaryCommand() {
    argParser
      ..addOption(
        'binary',
        abbr: 'b',
        help: 'Path to the binary to verify. If omitted, verifies the '
            'currently running binary.',
      )
      ..addOption(
        'expected-hash',
        abbr: 'e',
        help: 'Expected SHA-256 hash (64-char hex string).',
        mandatory: true,
      );
  }

  @override
  Future<int> run() async {
    final binaryPath = argResults!['binary'] as String? ??
        Platform.resolvedExecutable;
    final expectedHashHex = argResults!['expected-hash'] as String;

    stdout.writeln('Verifying binary: $binaryPath');

    final Uint8List actualHash =
        await SupplyChainVerifier.computeBinaryHash(binaryPath);
    final String actualHex = actualHash
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    stdout.writeln('  SHA-256: $actualHex');

    final expectedHash = _hexToBytes(expectedHashHex);
    final result = await SupplyChainVerifier.verifyBinaryIntegrity(
      binaryPath,
      expectedHash,
    );

    if (result.matches) {
      stdout.writeln('PASSED - Binary integrity verified.');
      return 0;
    } else {
      stderr.writeln('FAILED - Binary hash does NOT match expected value!');
      stderr.writeln('  Expected: $expectedHashHex');
      stderr.writeln('  Actual:   $actualHex');
      stderr.writeln('');
      stderr.writeln('WARNING: Your copy of Zegel may have been compromised.');
      stderr.writeln('Download a fresh copy from the official source.');
      return 1;
    }
  }
}

/// Command to create a build provenance attestation.
///
/// ```
/// zegel build-attest --version 1.4.0 --commit <hash> --builder <identity> --signing-key <key> -o <attestation.json>
/// ```
class BuildAttestCommand extends Command<int> {
  @override
  final String name = 'build-attest';

  @override
  final String description =
      'Create a cryptographically signed build provenance attestation.\n'
      '\n'
      'Records build metadata (version, commit hash, builder identity) and\n'
      'signs it with an Ed25519 key. This can be distributed alongside the\n'
      'binary to prove it was produced by a trusted builder.';

  BuildAttestCommand() {
    argParser
      ..addOption('build-version', help: 'Software version.', mandatory: true)
      ..addOption('commit', help: 'Git commit hash.', mandatory: true)
      ..addOption('builder', help: 'Builder identity.', mandatory: true)
      ..addOption('signing-key', help: 'Ed25519 private key file.', mandatory: true)
      ..addOption('reproducible-hash', help: 'Reproducible build hash.')
      ..addOption('output', abbr: 'o', help: 'Output JSON file.', defaultsTo: 'build-attestation.json');
  }

  @override
  Future<int> run() async {
    final version = argResults!['build-version'] as String;
    final commit = argResults!['commit'] as String;
    final builder = argResults!['builder'] as String;
    final signingKeyPath = argResults!['signing-key'] as String;
    final reproducibleHash = argResults!['reproducible-hash'] as String?;
    final outputPath = argResults!['output'] as String;

    final Uint8List signingKey = readKeyFile(signingKeyPath);
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    final buildInfo = BuildInfo(
      version: version,
      commitHash: commit,
      buildTimestamp: now,
      builderIdentity: builder,
      reproducibleBuildHash: reproducibleHash,
    );

    final attestation = SupplyChainVerifier.createBuildAttestation(
      buildInfo,
      signingKey,
    );

    File(outputPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(attestation),
    );

    stdout.writeln('Build attestation created:');
    stdout.writeln('  Version: $version');
    stdout.writeln('  Commit:  $commit');
    stdout.writeln('  Builder: $builder');
    stdout.writeln('  Output:  $outputPath');

    return 0;
  }
}

/// Command to verify a build attestation.
///
/// ```
/// zegel verify-build --attestation <file.json> --trusted-key <key-file>
/// ```
class VerifyBuildCommand extends Command<int> {
  @override
  final String name = 'verify-build';

  @override
  final String description =
      'Verify a build provenance attestation against trusted builder keys.';

  VerifyBuildCommand() {
    argParser
      ..addOption('attestation', abbr: 'a', help: 'Attestation JSON file.', mandatory: true)
      ..addMultiOption('trusted-key', abbr: 't', help: 'Trusted builder public key file(s).');
  }

  @override
  Future<int> run() async {
    final attPath = argResults!['attestation'] as String;
    final trustedKeyPaths = argResults!['trusted-key'] as List<String>;

    final attestation =
        jsonDecode(File(attPath).readAsStringSync()) as Map<String, dynamic>;
    final List<Uint8List> trustedKeys = trustedKeyPaths.map((p) => readKeyFile(p)).toList();

    final result = SupplyChainVerifier.verifyBuildAttestation(
      attestation,
      trustedKeys,
    );

    stdout.writeln('Build attestation verification:');
    stdout.writeln('  Signature valid: ${result.valid}');
    stdout.writeln('  Trusted builder: ${result.trustedBuilder}');
    stdout.writeln('  Reason: ${result.reason}');

    if (result.buildInfo != null) {
      stdout.writeln('  Version: ${result.buildInfo!.version}');
      stdout.writeln('  Commit:  ${result.buildInfo!.commitHash}');
      stdout.writeln('  Builder: ${result.buildInfo!.builderIdentity}');
    }

    return (result.valid && result.trustedBuilder) ? 0 : 1;
  }
}

/// Command to audit entropy quality in a sealed .zgl file.
///
/// ```
/// zegel audit-entropy <file.zgl>
/// ```
class AuditEntropyCommand extends Command<int> {
  @override
  final String name = 'audit-entropy';

  @override
  final String description =
      'Audit the randomness quality of IVs and salt in a .zgl file.\n'
      '\n'
      'Checks that random bytes have sufficient Shannon entropy and that\n'
      'no IVs are reused. Low entropy may indicate a compromised tool\n'
      'with a weakened random number generator.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      usageException('No input file specified.');
    }

    final inputPath = rest[0];
    final Uint8List fileBytes = File(inputPath).readAsBytesSync();

    //


    if (entropyOk) {
      stdout.writeln('PASSED - Entropy audit successful.');
      stdout.writeln('  Salt has sufficient randomness.');
      stdout.writeln('  No IV reuse detected.');
      stdout.writeln('  No constant-value random fields found.');
      return 0;
    } else {
      stderr.writeln('FAILED - Entropy audit detected issues!');
      stderr.writeln('');
      stderr.writeln('This may indicate:');
      stderr.writeln('  - A compromised or backdoored Zegel tool');
      stderr.writeln('  - A weak random number generator');
      stderr.writeln('  - IV reuse (critical security vulnerability)');
      stderr.writeln('');
      stderr.writeln('DO NOT trust this file. Re-seal with a verified tool.');
      return 1;
    }
  }
}

Uint8List _hexToBytes(String hex) {
  final int length = hex.length ~/ 2;
  final Uint8List bytes = Uint8List(length);
  for (int i = 0; i < length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}
