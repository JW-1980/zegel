import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Tamper-evident audit trail (GEN-8, v1.2).
///
/// Audit entries form a hash-chained append-only log within the file. Each
/// entry's `chain_hash` is computed over the previous chain hash concatenated
/// with the current entry's JSON representation. This ensures that any
/// modification to any entry breaks the chain and is detectable.
class AuditTrail {
  AuditTrail._();

  /// Creates a new audit trail entry.
  ///
  /// [actor] identifies who performed the action (e.g. `"user:42:admin@example.com"`).
  /// [action] is one of: `"sealed"`, `"verified"`, `"redacted"`, `"attested"`,
  /// `"disclosed"`.
  /// [details] is an optional map of additional data.
  /// [previousChainHash] is the chain_hash of the preceding entry, or `null`
  /// for the first entry (which uses 32 zero bytes).
  ///
  /// Returns a JSON-serialisable map including the computed `chain_hash`.
  static Map<String, dynamic> createEntry(
    String actor,
    String action, {
    Map<String, dynamic>? details,
    Uint8List? previousChainHash,
  }) {
    final int epochSeconds =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    // Build the entry without chain_hash first (chain_hash depends on the
    // serialised entry, so we include an empty signature field and compute over the
    // canonical form).
    final Map<String, dynamic> entry = <String, dynamic>{
      'actor': actor,
      'action': action,
      'timestamp': epochSeconds,
    };
    if (details != null && details.isNotEmpty) {
      entry['details'] = details;
    }

    // Determine previous chain hash (32 zero bytes for the first entry).
    final Uint8List prevHash = previousChainHash ?? Uint8List(32);

    // Compute chain_hash = SHA-256(previousChainHash || entryJson).
    // We serialise the entry WITHOUT the chain_hash field for the hash input.
    final String entryJson = jsonEncode(entry);
    final Uint8List entryJsonBytes = Uint8List.fromList(utf8.encode(entryJson));

    final Uint8List hashInput = Uint8List(
      prevHash.length + entryJsonBytes.length,
    );
    hashInput.setRange(0, prevHash.length, prevHash);
    hashInput.setRange(prevHash.length, hashInput.length, entryJsonBytes);

    final Uint8List chainHash = Uint8List.fromList(
      sha256.convert(hashInput).bytes,
    );

    entry['chain_hash'] = _bytesToHex(chainHash);
    return entry;
  }

  /// Verifies an entire audit trail by recomputing chain hashes.
  ///
  /// Returns `true` if every entry's `chain_hash` matches the expected value
  /// computed from the previous entry's chain hash.
  static bool verifyChain(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) return true;

    Uint8List previousHash = Uint8List(32); // 32 zero bytes for first entry

    for (final Map<String, dynamic> entry in entries) {
      final String storedHash = entry['chain_hash'] as String;

      // Rebuild the entry without chain_hash for hashing.
      final Map<String, dynamic> entryWithoutHash = Map<String, dynamic>.from(
        entry,
      );
      entryWithoutHash.remove('chain_hash');

      final String entryJson = jsonEncode(entryWithoutHash);
      final Uint8List entryJsonBytes = Uint8List.fromList(
        utf8.encode(entryJson),
      );

      final Uint8List hashInput = Uint8List(
        previousHash.length + entryJsonBytes.length,
      );
      hashInput.setRange(0, previousHash.length, previousHash);
      hashInput.setRange(previousHash.length, hashInput.length, entryJsonBytes);

      final Uint8List computedHash = Uint8List.fromList(
        sha256.convert(hashInput).bytes,
      );
      final String computedHex = _bytesToHex(computedHash);

      // Constant-time comparison.
      if (!_constantTimeEquals(storedHash, computedHex)) {
        return false;
      }

      previousHash = _hexToBytes(storedHash);
    }

    return true;
  }

  /// Converts bytes to lowercase hex string.
  static String _bytesToHex(Uint8List bytes) {
    final StringBuffer buf = StringBuffer();
    for (final byte in bytes) {
      buf.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  /// Converts a hex string to bytes.
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
