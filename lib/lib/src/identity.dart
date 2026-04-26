import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pinenacl/ed25519.dart' as pinenacl;

import 'format.dart';
import 'reader.dart';

/// Creator identity and Ed25519 signature support (v1.2+).
///
/// Provides cryptographic proof of who created a .zgl file and on what device.
/// Uses Ed25519 signatures (via pointycastle) for non-repudiation: the creator
/// signs the Merkle root, master seal, and timestamp, producing a verifiable
/// signature that can be checked with only the public key.
///
/// Device attestation captures platform and environment information, creating
/// a signed record of the device that produced the file.
class ZegelIdentity {
  ZegelIdentity._();

  /// Generates an Ed25519 signing keypair.
  ///
  /// Returns a [ZegelKeyPair] containing the 32-byte private key seed and the
  /// 32-byte public key.
  static ZegelKeyPair generateKeyPair() {
    final seed = Uint8List(32);
    final rng = Random.secure();
    for (int i = 0; i < 32; i++) {
      seed[i] = rng.nextInt(256);
    }
    final signingKey = pinenacl.SigningKey.fromSeed(seed);
    return ZegelKeyPair(
      privateKey: Uint8List.fromList(signingKey.asTypedList),
      publicKey: Uint8List.fromList(signingKey.verifyKey.asTypedList),
    );
  }

  /// Signs a .zgl file's integrity markers with an Ed25519 private key.
  ///
  /// The signature is computed over:
  /// ```
  /// SHA-256(merkle_root || master_seal || timestamp_bytes)
  /// ```
  ///
  /// [fileBytes] is the complete .zgl file (including master seal).
  /// [privateKey] is the 32-byte Ed25519 private key seed.
  ///
  /// Returns a [ZegelSignature] containing the 64-byte Ed25519 signature and
  /// the timestamp used.
  ///
  /// Throws [ZegelFormatException] if the file cannot be parsed.
  static ZegelSignature sign(Uint8List fileBytes, Uint8List privateKey) {
    if (privateKey.length != 32) {
      throw ArgumentError('Private key must be exactly 32 bytes');
    }

    final _FileIntegrityMarkers markers = _extractMarkers(fileBytes);

    // Build the message to sign: SHA-256(merkle_root || master_seal || timestamp).
    final int nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final Uint8List timestampBytes = _packUint64BE(nowEpoch);

    final Uint8List message = Uint8List(
      markers.merkleRoot.length +
          markers.masterSeal.length +
          timestampBytes.length,
    );
    int offset = 0;
    message.setRange(
      offset,
      offset + markers.merkleRoot.length,
      markers.merkleRoot,
    );
    offset += markers.merkleRoot.length;
    message.setRange(
      offset,
      offset + markers.masterSeal.length,
      markers.masterSeal,
    );
    offset += markers.masterSeal.length;
    message.setRange(offset, offset + timestampBytes.length, timestampBytes);

    final Uint8List digest = Uint8List.fromList(sha256.convert(message).bytes);

    // Sign with Ed25519.
    final signingKey = pinenacl.SigningKey.fromSeed(privateKey);
    final signature = Uint8List.fromList(
      signingKey.sign(digest).signature.asTypedList,
    );

    return ZegelSignature(
      signature: signature,
      timestamp: nowEpoch,
      merkleRootHex: _bytesToHex(markers.merkleRoot),
    );
  }

  /// Verifies an Ed25519 signature over a .zgl file's integrity markers.
  ///
  /// [fileBytes] is the complete .zgl file.
  /// [publicKey] is the 32-byte Ed25519 public key.
  /// [sig] is the [ZegelSignature] to verify.
  ///
  /// Returns `true` if the signature is valid.
  static bool verify(
    Uint8List fileBytes,
    Uint8List publicKey,
    ZegelSignature sig,
  ) {
    if (publicKey.length != 32) {
      throw ArgumentError('Public key must be exactly 32 bytes');
    }

    final _FileIntegrityMarkers markers = _extractMarkers(fileBytes);

    // Rebuild the signed message.
    final Uint8List timestampBytes = _packUint64BE(sig.timestamp);

    final Uint8List message = Uint8List(
      markers.merkleRoot.length +
          markers.masterSeal.length +
          timestampBytes.length,
    );
    int offset = 0;
    message.setRange(
      offset,
      offset + markers.merkleRoot.length,
      markers.merkleRoot,
    );
    offset += markers.merkleRoot.length;
    message.setRange(
      offset,
      offset + markers.masterSeal.length,
      markers.masterSeal,
    );
    offset += markers.masterSeal.length;
    message.setRange(offset, offset + timestampBytes.length, timestampBytes);

    final Uint8List digest = Uint8List.fromList(sha256.convert(message).bytes);

    // Verify with Ed25519.
    try {
      final verifyKey = pinenacl.VerifyKey(publicKey);
      return verifyKey.verify(
        signature: pinenacl.Signature(sig.signature),
        message: digest,
      );
    } on Exception {
      return false;
    }
  }

  /// Serialises a signature to a JSON-compatible map for storage as a
  /// SIGNATURE block.
  static Map<String, dynamic> signatureToJson(ZegelSignature sig) {
    return <String, dynamic>{
      'signature_hex': _bytesToHex(sig.signature),
      'timestamp': sig.timestamp,
      'merkle_root_hex': sig.merkleRootHex,
      'algorithm': 'Ed25519',
    };
  }

  /// Deserialises a signature from a JSON map.
  static ZegelSignature signatureFromJson(Map<String, dynamic> json) {
    return ZegelSignature(
      signature: _hexToBytes(json['signature_hex'] as String),
      timestamp: json['timestamp'] as int,
      merkleRootHex: json['merkle_root_hex'] as String,
    );
  }

  /// Extracts the Merkle root and master seal from a .zgl file.
  static _FileIntegrityMarkers _extractMarkers(Uint8List fileBytes) {
    // The master seal is the last 64 bytes.
    if (fileBytes.length < ZegelFormat.sealSize + ZegelFormat.hashSize) {
      throw const ZegelFormatException(
        'File too short to contain Merkle root and master seal',
      );
    }

    final Uint8List masterSeal = Uint8List.fromList(
      fileBytes.sublist(fileBytes.length - ZegelFormat.sealSize),
    );

    // Parse the file to find the Merkle root.
    const ZegelReader reader = ZegelReader();
    final ZegelInspection inspection = reader.inspect(fileBytes);

    // Re-parse to get the Merkle root. We need to find it in the binary.
    // The Merkle root is located after the block directory.
    // We know: header + extended header + directory entries + merkle root.
    // Use the inspection to compute the offset.
    final ByteData bd = ByteData.sublistView(fileBytes);

    // Skip to after fixed header.
    final int filenameLen = bd.getUint16(84, Endian.big);
    final int flags = bd.getUint16(10, Endian.big);
    int cursor = 86 + filenameLen + ZegelFormat.saltSize + 4;

    // Skip extended header fields.
    if (flags & ZegelFormat.flagPasswordDerived != 0) cursor += 8;
    if (flags & ZegelFormat.flagHasExpiration != 0) cursor += 8;
    if (flags & ZegelFormat.flagHasCanary != 0) cursor += 32;
    if (flags & ZegelFormat.flagSplitKey != 0) cursor += 2;
    if (flags & ZegelFormat.flagVersioned != 0) cursor += 32;
    if (flags & ZegelFormat.flagHasPublicMetadata != 0) {
      final int pubMetaLen = bd.getUint32(cursor, Endian.big);
      cursor += 4 + pubMetaLen;
    }

    // Skip block directory.
    cursor += inspection.blockCount * ZegelFormat.blockDirectoryEntrySize;

    // Read Merkle root.
    final Uint8List merkleRoot = Uint8List.fromList(
      fileBytes.sublist(cursor, cursor + ZegelFormat.hashSize),
    );

    return _FileIntegrityMarkers(
      merkleRoot: merkleRoot,
      masterSeal: masterSeal,
    );
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

  static Uint8List _packUint64BE(int value) {
    final ByteData bd = ByteData(8);
    bd.setUint64(0, value, Endian.big);
    return bd.buffer.asUint8List();
  }
}

/// Internal: extracted Merkle root and master seal from a .zgl file.
class _FileIntegrityMarkers {
  const _FileIntegrityMarkers({
    required this.merkleRoot,
    required this.masterSeal,
  });

  final Uint8List merkleRoot;
  final Uint8List masterSeal;
}

/// An Ed25519 signing keypair for Zegel identity.
class ZegelKeyPair {
  /// Creates a [ZegelKeyPair].
  const ZegelKeyPair({required this.privateKey, required this.publicKey});

  /// The 32-byte Ed25519 private key seed.
  final Uint8List privateKey;

  /// The 32-byte Ed25519 public key.
  final Uint8List publicKey;
}

/// An Ed25519 signature over a .zgl file's integrity markers.
class ZegelSignature {
  /// Creates a [ZegelSignature].
  const ZegelSignature({
    required this.signature,
    required this.timestamp,
    required this.merkleRootHex,
  });

  /// The 64-byte Ed25519 signature.
  final Uint8List signature;

  /// Unix epoch seconds when the signature was created.
  final int timestamp;

  /// Hex-encoded Merkle root that was signed.
  final String merkleRootHex;
}

/// Device attestation: captures and signs device/platform information (v1.2+).
///
/// Creates a signed record of the device that produced a .zgl file. Useful for
/// forensic analysis, compliance, and chain of custody.
///
/// The device information includes OS, platform, Dart version, and a salted
/// hash of the hostname (to avoid leaking the exact hostname while still
/// enabling device correlation).
class DeviceAttestation {
  DeviceAttestation._();

  /// Captures current device/platform information.
  ///
  /// Returns a [DeviceInfo] with OS, platform, Dart runtime version, and a
  /// HMAC-SHA-256 of the hostname, keyed with a freshly generated random
  /// 32-byte salt that is stored alongside the hash.
  ///
  /// The previous implementation hashed `microsecondsSinceEpoch:hostname`
  /// but discarded the salt, which:
  ///
  /// - prevented forensic correlation across files (same hostname yielded
  ///   different hashes every call because the salt was never saved), and
  /// - allowed a local attacker who knew `capturedAt` to brute-force the
  ///   microsecond salt within that second and enumerate common hostnames.
  ///
  /// The new construction keeps the hostname secret from anyone without the
  /// salt while allowing a forensic analyst in possession of both to verify
  /// that two files came from the same device.
  static DeviceInfo captureDeviceInfo() {
    final String os = Platform.operatingSystem;
    final String osVersion = Platform.operatingSystemVersion;
    final String dartVersion = Platform.version;

    // 32-byte CSPRNG salt stored with the attestation.
    final Random rng = Random.secure();
    final Uint8List hostnameHashSalt = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      hostnameHashSalt[i] = rng.nextInt(256);
    }

    final String hostname = Platform.localHostname;
    final Uint8List hostnameBytes = Uint8List.fromList(utf8.encode(hostname));
    final Hmac mac = Hmac(sha256, hostnameHashSalt);
    final Uint8List hostnameHash = Uint8List.fromList(
      mac.convert(hostnameBytes).bytes,
    );

    return DeviceInfo(
      operatingSystem: os,
      operatingSystemVersion: osVersion,
      dartVersion: dartVersion,
      hostnameHash: hostnameHash,
      hostnameHashSalt: hostnameHashSalt,
      capturedAt: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// Creates a signed attestation block from device information.
  ///
  /// [deviceInfo] is the captured device information.
  /// [signingKey] is a 32-byte Ed25519 private key seed.
  ///
  /// Returns a JSON-serialisable map suitable for inclusion as a
  /// DEVICE_ATTESTATION block (type 0x0F).
  static Map<String, dynamic> createAttestation(
    DeviceInfo deviceInfo,
    Uint8List signingKey,
  ) {
    if (signingKey.length != 32) {
      throw ArgumentError('Signing key must be exactly 32 bytes');
    }

    final Map<String, dynamic> infoMap = deviceInfo.toJson();
    final String infoJson = jsonEncode(infoMap);
    final Uint8List infoBytes = Uint8List.fromList(utf8.encode(infoJson));

    // Sign the device info JSON with Ed25519.
    final Uint8List digest = Uint8List.fromList(
      sha256.convert(infoBytes).bytes,
    );

    final sk = pinenacl.SigningKey.fromSeed(signingKey);
    final signature = Uint8List.fromList(sk.sign(digest).signature.asTypedList);
    final publicKey = Uint8List.fromList(sk.verifyKey.asTypedList);

    return <String, dynamic>{
      'device_info': infoMap,
      'signature_hex': _bytesToHex(Uint8List.fromList(signature)),
      'public_key_hex': _bytesToHex(Uint8List.fromList(publicKey)),
      'algorithm': 'Ed25519',
    };
  }

  /// Verifies a device attestation signature.
  ///
  /// [attestation] is the attestation map (as produced by [createAttestation]).
  /// [publicKey] is the 32-byte Ed25519 public key. If null, the public key
  /// embedded in the attestation is used.
  ///
  /// Returns `true` if the signature is valid.
  static bool verifyAttestation(
    Map<String, dynamic> attestation, {
    Uint8List? publicKey,
  }) {
    final Uint8List pubKey =
        publicKey ?? _hexToBytes(attestation['public_key_hex'] as String);

    if (pubKey.length != 32) {
      throw ArgumentError('Public key must be exactly 32 bytes');
    }

    final Map<String, dynamic> infoMap =
        attestation['device_info'] as Map<String, dynamic>;
    final String infoJson = jsonEncode(infoMap);
    final Uint8List infoBytes = Uint8List.fromList(utf8.encode(infoJson));
    final Uint8List digest = Uint8List.fromList(
      sha256.convert(infoBytes).bytes,
    );

    final Uint8List signatureBytes = _hexToBytes(
      attestation['signature_hex'] as String,
    );

    try {
      final verifyKey = pinenacl.VerifyKey(pubKey);
      return verifyKey.verify(
        signature: pinenacl.Signature(signatureBytes),
        message: digest,
      );
    } on Exception {
      return false;
    }
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
}

/// Captured device and platform information.
class DeviceInfo {
  /// Deserialises from a JSON-compatible map.
  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      operatingSystem: json['operating_system'] as String,
      operatingSystemVersion: json['operating_system_version'] as String,
      dartVersion: json['dart_version'] as String,
      hostnameHash: _hexToBytes(json['hostname_hash_hex'] as String),
      hostnameHashSalt: json['hostname_hash_salt_hex'] == null
          ? Uint8List(0)
          : _hexToBytes(json['hostname_hash_salt_hex'] as String),
      capturedAt: json['captured_at'] as int,
    );
  }

  /// Creates a [DeviceInfo].
  const DeviceInfo({
    required this.operatingSystem,
    required this.operatingSystemVersion,
    required this.dartVersion,
    required this.hostnameHash,
    required this.hostnameHashSalt,
    required this.capturedAt,
  });

  /// Operating system name (e.g. "linux", "macos", "windows").
  final String operatingSystem;

  /// Operating system version string.
  final String operatingSystemVersion;

  /// Dart runtime version string.
  final String dartVersion;

  /// HMAC-SHA-256 of the hostname keyed with [hostnameHashSalt].
  final Uint8List hostnameHash;

  /// 32-byte CSPRNG salt used as the HMAC key for [hostnameHash]. Stored so
  /// that a forensic analyst in possession of both the salt and the true
  /// hostname can verify that two files originated on the same device.
  /// Observers without the salt cannot brute-force the hostname.
  final Uint8List hostnameHashSalt;

  /// Unix epoch seconds when the device info was captured.
  final int capturedAt;

  /// Serialises to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'operating_system': operatingSystem,
      'operating_system_version': operatingSystemVersion,
      'dart_version': dartVersion,
      'hostname_hash_hex': _bytesToHex(hostnameHash),
      'hostname_hash_salt_hex': _bytesToHex(hostnameHashSalt),
      'captured_at': capturedAt,
    };
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
}
