import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pinenacl/ed25519.dart' as pinenacl;

/// Supply chain verification: binary integrity and build provenance (v1.2+).
///
/// Provides self-verification capabilities so that the Zegel tooling can
/// detect if its own binary has been tampered with, and build provenance
/// records that cryptographically link a .zgl file to the specific build
/// of the software that created it.
///
/// Build attestations are stored as PROVENANCE blocks (type 0x05) and can be
/// verified against a set of trusted builder public keys.
class SupplyChainVerifier {
  SupplyChainVerifier._();

  /// Computes the SHA-256 hash of a binary file at [binaryPath].
  ///
  /// Reads the file in 64 KiB chunks for memory efficiency.
  ///
  /// Returns the 32-byte SHA-256 digest.
  ///
  /// Throws [FileSystemException] if the file cannot be read.
  static Future<Uint8List> computeBinaryHash(String binaryPath) async {
    final File file = File(binaryPath);
    if (!await file.exists()) {
      throw FileSystemException('Binary not found', binaryPath);
    }

    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);

    final Stream<List<int>> stream = file.openRead();
    await for (final List<int> chunk in stream) {
      input.add(chunk);
    }
    input.close();

    return Uint8List.fromList(output.events.single.bytes);
  }

  /// Computes the SHA-256 hash of a binary file synchronously.
  ///
  /// [binaryPath] is the path to the binary to hash.
  ///
  /// Returns the 32-byte SHA-256 digest.
  static Uint8List computeBinaryHashSync(String binaryPath) {
    final File file = File(binaryPath);
    if (!file.existsSync()) {
      throw FileSystemException('Binary not found', binaryPath);
    }

    final Uint8List bytes = file.readAsBytesSync();
    return Uint8List.fromList(sha256.convert(bytes).bytes);
  }

  /// Verifies binary integrity against a known-good hash.
  ///
  /// [expectedHash] is the trusted SHA-256 hash (32 bytes or 64-char hex).
  ///
  /// Returns a [BinaryIntegrityResult] with the verification outcome.
  static Future<BinaryIntegrityResult> verifyBinaryIntegrity(
    String binaryPath,
    Uint8List expectedHash,
  ) async {
    final Uint8List actualHash = await computeBinaryHash(binaryPath);
    final bool matches = _constantTimeEquals(actualHash, expectedHash);

    return BinaryIntegrityResult(
      path: binaryPath,
      expectedHash: expectedHash,
      actualHash: actualHash,
      matches: matches,
    );
  }

  /// Creates a signed build provenance record.
  ///
  /// [buildInfo] contains the build metadata.
  /// [signingKey] is a 32-byte Ed25519 private key seed belonging to the
  /// builder.
  ///
  /// Returns a JSON-serialisable map suitable for storage as a PROVENANCE
  /// block (type 0x05).
  static Map<String, dynamic> createBuildAttestation(
    BuildInfo buildInfo,
    Uint8List signingKey,
  ) {
    if (signingKey.length != 32) {
      throw ArgumentError('Signing key must be exactly 32 bytes');
    }

    final Map<String, dynamic> infoMap = buildInfo.toJson();
    final String infoJson = jsonEncode(infoMap);
    final Uint8List infoBytes = Uint8List.fromList(utf8.encode(infoJson));

    // Sign the build info with Ed25519.
    final Uint8List digest = Uint8List.fromList(
      sha256.convert(infoBytes).bytes,
    );

    final sk = pinenacl.SigningKey.fromSeed(signingKey);
    final signature = Uint8List.fromList(sk.sign(digest).signature.asTypedList);
    final publicKey = Uint8List.fromList(sk.verifyKey.asTypedList);

    return <String, dynamic>{
      'type': 'build_attestation',
      'build_info': infoMap,
      'signature_hex': _bytesToHex(Uint8List.fromList(signature)),
      'public_key_hex': _bytesToHex(Uint8List.fromList(publicKey)),
      'algorithm': 'Ed25519',
    };
  }

  /// Verifies a build attestation against a set of trusted builder public keys.
  ///
  /// [attestation] is the build attestation map (as produced by
  /// [createBuildAttestation]).
  /// [trustedKeys] is a list of 32-byte Ed25519 public keys belonging to
  /// trusted builders.
  ///
  /// Returns a [BuildAttestationResult] with the verification outcome.
  static BuildAttestationResult verifyBuildAttestation(
    Map<String, dynamic> attestation,
    List<Uint8List> trustedKeys,
  ) {
    // Verify the attestation type.
    if (attestation['type'] != 'build_attestation') {
      return const BuildAttestationResult(
        valid: false,
        trustedBuilder: false,
        buildInfo: null,
        reason: 'Not a build attestation',
      );
    }

    final Map<String, dynamic> infoMap =
        attestation['build_info'] as Map<String, dynamic>;
    final String infoJson = jsonEncode(infoMap);
    final Uint8List infoBytes = Uint8List.fromList(utf8.encode(infoJson));
    final Uint8List digest = Uint8List.fromList(
      sha256.convert(infoBytes).bytes,
    );

    final Uint8List signatureBytes = _hexToBytes(
      attestation['signature_hex'] as String,
    );
    final Uint8List embeddedPubKey = _hexToBytes(
      attestation['public_key_hex'] as String,
    );

    // First verify the signature with the embedded public key.
    bool signatureValid;
    try {
      final verifyKey = pinenacl.VerifyKey(embeddedPubKey);
      signatureValid = verifyKey.verify(
        signature: pinenacl.Signature(signatureBytes),
        message: digest,
      );
    } on Exception {
      signatureValid = false;
    }

    if (!signatureValid) {
      return BuildAttestationResult(
        valid: false,
        trustedBuilder: false,
        buildInfo: BuildInfo.fromJson(infoMap),
        reason: 'Signature verification failed',
      );
    }

    // Check if the embedded public key is in the trusted set.
    bool isTrusted = false;
    for (final Uint8List trustedKey in trustedKeys) {
      if (_constantTimeEquals(embeddedPubKey, trustedKey)) {
        isTrusted = true;
        break;
      }
    }

    return BuildAttestationResult(
      valid: true,
      trustedBuilder: isTrusted,
      buildInfo: BuildInfo.fromJson(infoMap),
      reason: isTrusted
          ? 'Signature valid, builder trusted'
          : 'Signature valid, but builder key not in trusted set',
    );
  }

  /// Computes the hash of the currently running Dart executable.
  ///
  /// Uses [Platform.resolvedExecutable] to find the binary path.
  /// Returns the 32-byte SHA-256 hash.
  static Uint8List computeSelfHash() {
    final String binaryPath = Platform.resolvedExecutable;
    return computeBinaryHashSync(binaryPath);
  }

  static String _bytesToHex(Uint8List bytes) {
    final StringBuffer buf = StringBuffer();
    for (final byte in bytes) {
      buf.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  static Uint8List _hexToBytes(String hex) {
    if (hex.length.isOdd) {
      throw FormatException('Hex string has odd length: ${hex.length}');
    }
    final int length = hex.length ~/ 2;
    final Uint8List bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      final int? parsed = int.tryParse(
        hex.substring(i * 2, i * 2 + 2),
        radix: 16,
      );
      if (parsed == null) {
        throw const FormatException('Hex string contains non-hex characters');
      }
      bytes[i] = parsed;
    }
    return bytes;
  }

  /// Constant-time comparison of two byte arrays.
  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Build information for provenance tracking.
class BuildInfo {
  /// Deserialises from a JSON-compatible map.
  factory BuildInfo.fromJson(Map<String, dynamic> json) {
    return BuildInfo(
      version: json['version'] as String,
      commitHash: json['commit_hash'] as String,
      buildTimestamp: json['build_timestamp'] as int,
      builderIdentity: json['builder_identity'] as String,
      reproducibleBuildHash: json['reproducible_build_hash'] as String?,
    );
  }

  /// Creates a [BuildInfo].
  const BuildInfo({
    required this.version,
    required this.commitHash,
    required this.buildTimestamp,
    required this.builderIdentity,
    this.reproducibleBuildHash,
  });

  /// Software version string (e.g. "1.2.0").
  final String version;

  /// Git commit hash of the source code.
  final String commitHash;

  /// Unix epoch seconds when the build was produced.
  final int buildTimestamp;

  /// Identity of the builder (e.g. "CI:github-actions:repo/zegel").
  final String builderIdentity;

  /// SHA-256 hash of the reproducible build output (if applicable).
  /// When non-null, others can reproduce the build and compare hashes.
  final String? reproducibleBuildHash;

  /// Serialises to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = <String, dynamic>{
      'version': version,
      'commit_hash': commitHash,
      'build_timestamp': buildTimestamp,
      'builder_identity': builderIdentity,
    };
    if (reproducibleBuildHash != null) {
      result['reproducible_build_hash'] = reproducibleBuildHash;
    }
    return result;
  }
}

/// Result of a binary integrity check.
class BinaryIntegrityResult {
  /// Creates a [BinaryIntegrityResult].
  const BinaryIntegrityResult({
    required this.path,
    required this.expectedHash,
    required this.actualHash,
    required this.matches,
  });

  /// Path to the binary that was checked.
  final String path;

  /// The expected (trusted) SHA-256 hash.
  final Uint8List expectedHash;

  /// The actual SHA-256 hash of the binary on disk.
  final Uint8List actualHash;

  /// Whether the hashes match.
  final bool matches;
}

/// Result of verifying a build attestation.
class BuildAttestationResult {
  /// Creates a [BuildAttestationResult].
  const BuildAttestationResult({
    required this.valid,
    required this.trustedBuilder,
    required this.buildInfo,
    required this.reason,
  });

  /// Whether the signature is cryptographically valid.
  final bool valid;

  /// Whether the builder's public key is in the trusted set.
  final bool trustedBuilder;

  /// Parsed build information (may be null if the attestation is malformed).
  final BuildInfo? buildInfo;

  /// Human-readable explanation of the result.
  final String reason;
}

/// Sink that accumulates events into a list.
class AccumulatorSink<T> implements Sink<T> {
  /// The accumulated events.
  final List<T> events = <T>[];

  @override
  void add(T event) {
    events.add(event);
  }

  @override
  void close() {}
}
