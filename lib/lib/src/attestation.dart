import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Co-signature / multi-party attestation (GEN-6, v1.2).
///
/// Attestation blocks allow third parties to cryptographically attest to a
/// file's integrity by signing a message that includes the Merkle root, the
/// signer's identity, a timestamp, and a free-text statement.
///
/// The attestation uses HMAC-SHA256 with the signer's key, so verification
/// requires the same key. For public verifiability, consider distributing the
/// signer key hash or using a PKI-based scheme on top.
class Attestation {
  Attestation._();

  /// Creates an attestation for the given [merkleRoot].
  ///
  /// The [signerId] is a human-readable identifier such as
  /// `"user:42:accountant@example.com"`.
  ///
  /// The [signerKey] is a 32-byte secret key belonging to the signer. The
  /// recommended derivation is:
  /// `HMAC-SHA256(company_key, "zegel-signer-v1:" + signer_id)`.
  ///
  /// The [statement] is free-text such as `"Reviewed and approved"`.
  ///
  /// If [timestamp] is null, the current UTC time is used.
  ///
  /// Returns a JSON-serialisable map containing the attestation fields and
  /// the hex-encoded HMAC.
  static Map<String, dynamic> createAttestation(
    Uint8List merkleRoot,
    String signerId,
    Uint8List signerKey,
    String statement, {
    DateTime? timestamp,
  }) {
    final DateTime ts = timestamp ?? DateTime.now().toUtc();
    final int epochSeconds = ts.millisecondsSinceEpoch ~/ 1000;

    // message = merkleRoot || signerIdBytes || pack_uint64_be(timestamp) || statementBytes
    final Uint8List signerIdBytes = Uint8List.fromList(utf8.encode(signerId));
    final Uint8List statementBytes = Uint8List.fromList(utf8.encode(statement));

    final int messageLen =
        merkleRoot.length +
        signerIdBytes.length +
        8 +
        statementBytes.length;
    final Uint8List message = Uint8List(messageLen);
    int offset = 0;

    message.setRange(offset, offset + merkleRoot.length, merkleRoot);
    offset += merkleRoot.length;

    message.setRange(offset, offset + signerIdBytes.length, signerIdBytes);
    offset += signerIdBytes.length;

    final ByteData bd = ByteData(8);
    bd.setUint64(0, epochSeconds, Endian.big);
    message.setRange(offset, offset + 8, bd.buffer.asUint8List());
    offset += 8;

    message.setRange(offset, offset + statementBytes.length, statementBytes);

    // hmac = HMAC-SHA256(signerKey, message)
    final hmac = Hmac(sha256, signerKey);
    final Uint8List hmacBytes = Uint8List.fromList(
      hmac.convert(message).bytes,
    );

    return <String, dynamic>{
      'signer_id': signerId,
      'statement': statement,
      'timestamp': epochSeconds,
      'hmac_hex': _bytesToHex(hmacBytes),
    };
  }

  /// Verifies an attestation against a [merkleRoot] and [signerKey].
  ///
  /// Recomputes the HMAC from the attestation fields and compares it with
  /// the stored `hmac_hex` value using constant-time comparison.
  ///
  /// Returns `true` if the attestation is valid.
  static bool verifyAttestation(
    Map<String, dynamic> attestation,
    Uint8List merkleRoot,
    Uint8List signerKey,
  ) {
    final String signerId = attestation['signer_id'] as String;
    final String statement = attestation['statement'] as String;
    final int epochSeconds = attestation['timestamp'] as int;
    final String storedHmacHex = attestation['hmac_hex'] as String;

    // Rebuild the message.
    final Uint8List signerIdBytes = Uint8List.fromList(utf8.encode(signerId));
    final Uint8List statementBytes = Uint8List.fromList(utf8.encode(statement));

    final int messageLen =
        merkleRoot.length +
        signerIdBytes.length +
        8 +
        statementBytes.length;
    final Uint8List message = Uint8List(messageLen);
    int offset = 0;

    message.setRange(offset, offset + merkleRoot.length, merkleRoot);
    offset += merkleRoot.length;

    message.setRange(offset, offset + signerIdBytes.length, signerIdBytes);
    offset += signerIdBytes.length;

    final ByteData bd = ByteData(8);
    bd.setUint64(0, epochSeconds, Endian.big);
    message.setRange(offset, offset + 8, bd.buffer.asUint8List());
    offset += 8;

    message.setRange(offset, offset + statementBytes.length, statementBytes);

    // Compute HMAC.
    final hmac = Hmac(sha256, signerKey);
    final Uint8List computedHmac = Uint8List.fromList(
      hmac.convert(message).bytes,
    );
    final String computedHex = _bytesToHex(computedHmac);

    return _constantTimeEquals(storedHmacHex, computedHex);
  }

  /// Converts bytes to lowercase hex string.
  static String _bytesToHex(Uint8List bytes) {
    final StringBuffer buf = StringBuffer();
    for (final byte in bytes) {
      buf.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  /// Constant-time string comparison.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
