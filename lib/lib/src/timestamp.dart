import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Trusted timestamp support (v1.3, RFC 3161 compatible).
///
/// Provides timestamp request generation and response verification for
/// establishing provable creation times independent of local system clocks.
/// This helps prevent time-manipulation attacks on expiration features.
class TrustedTimestamp {
  TrustedTimestamp._();

  /// Creates a timestamp request for a .zgl file.
  ///
  /// The request contains a hash of the file's Merkle root and master seal,
  /// which uniquely identifies the sealed file at a point in time.
  ///
  /// [merkleRoot] is the 32-byte Merkle root from the file header.
  /// [masterSeal] is the 64-byte master seal from the file footer.
  ///
  /// Returns a map representing the timestamp request.
  static Map<String, dynamic> createRequest(
    Uint8List merkleRoot,
    Uint8List masterSeal,
  ) {
    // Hash the identifying data: SHA-256(merkleRoot || masterSeal)
    final combined = Uint8List(merkleRoot.length + masterSeal.length);
    combined.setRange(0, merkleRoot.length, merkleRoot);
    combined.setRange(merkleRoot.length, combined.length, masterSeal);
    final digest = sha256.convert(combined);

    return {
      'version': 1,
      'algorithm': 'SHA-256',
      'message_imprint': digest.toString(),
      'nonce': DateTime.now().toUtc().microsecondsSinceEpoch.toString(),
      'cert_req': true,
    };
  }

  /// Creates a local timestamp token (for use when no TSA is available).
  ///
  /// This provides a signed timestamp that can be verified later, though
  /// it does not have the independent authority of an external TSA.
  ///
  /// [merkleRoot] is the 32-byte Merkle root.
  /// [masterSeal] is the 64-byte master seal.
  /// [signerKey] is the key used to sign the timestamp.
  static Map<String, dynamic> createLocalToken(
    Uint8List merkleRoot,
    Uint8List masterSeal,
    Uint8List signerKey, {
    DateTime? timestamp,
  }) {
    final ts = timestamp ?? DateTime.now().toUtc();
    final epochSeconds = ts.millisecondsSinceEpoch ~/ 1000;

    // Create the message to sign
    final combined = Uint8List(merkleRoot.length + masterSeal.length + 8);
    combined.setRange(0, merkleRoot.length, merkleRoot);
    combined.setRange(
      merkleRoot.length,
      merkleRoot.length + masterSeal.length,
      masterSeal,
    );
    final bd = ByteData(8);
    bd.setUint64(0, epochSeconds, Endian.big);
    combined.setRange(
      merkleRoot.length + masterSeal.length,
      combined.length,
      bd.buffer.asUint8List(),
    );

    final hmac = Hmac(sha256, signerKey);
    final signature = Uint8List.fromList(hmac.convert(combined).bytes);

    return {
      'version': 1,
      'type': 'local',
      'timestamp': epochSeconds,
      'merkle_root': _bytesToHex(merkleRoot),
      'signature': _bytesToHex(signature),
    };
  }

  /// Verifies a local timestamp token.
  static bool verifyLocalToken(
    Map<String, dynamic> token,
    Uint8List merkleRoot,
    Uint8List masterSeal,
    Uint8List signerKey,
  ) {
    if (token['type'] != 'local') return false;

    final epochSeconds = token['timestamp'] as int;
    final storedSig = token['signature'] as String;

    final combined = Uint8List(merkleRoot.length + masterSeal.length + 8);
    combined.setRange(0, merkleRoot.length, merkleRoot);
    combined.setRange(
      merkleRoot.length,
      merkleRoot.length + masterSeal.length,
      masterSeal,
    );
    final bd = ByteData(8);
    bd.setUint64(0, epochSeconds, Endian.big);
    combined.setRange(
      merkleRoot.length + masterSeal.length,
      combined.length,
      bd.buffer.asUint8List(),
    );

    final hmac = Hmac(sha256, signerKey);
    final computed = Uint8List.fromList(hmac.convert(combined).bytes);
    final computedHex = _bytesToHex(computed);

    return _constantTimeEquals(storedSig, computedHex);
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
