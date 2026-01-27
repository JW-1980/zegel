import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Content versioning (GEN-10, v1.2).
///
/// When `FLAG_VERSIONED` is set, the extended header contains a 32-byte version
/// chain hash that cryptographically links this file to its predecessor. This
/// allows verification that a file is a legitimate successor of another without
/// needing the predecessor's master key.
class ContentVersioning {
  ContentVersioning._();

  /// Computes the version chain hash that links to a predecessor file.
  ///
  /// ```
  /// chainHash = SHA-256(previousMerkleRoot || previousMasterSeal)
  /// ```
  ///
  /// [previousMerkleRoot] is the 32-byte Merkle root of the predecessor file.
  /// [previousMasterSeal] is the 64-byte master seal of the predecessor file.
  ///
  /// Returns a 32-byte SHA-256 hash.
  static Uint8List computeChainHash(
    Uint8List previousMerkleRoot,
    Uint8List previousMasterSeal,
  ) {
    final Uint8List input = Uint8List(
      previousMerkleRoot.length + previousMasterSeal.length,
    );
    input.setRange(0, previousMerkleRoot.length, previousMerkleRoot);
    input.setRange(
      previousMerkleRoot.length,
      input.length,
      previousMasterSeal,
    );
    return Uint8List.fromList(sha256.convert(input).bytes);
  }

  /// Verifies that a [chainHash] correctly links to the given predecessor
  /// file's [previousMerkleRoot] and [previousMasterSeal].
  ///
  /// Returns `true` if the chain hash matches.
  static bool verifyChain(
    Uint8List chainHash,
    Uint8List previousMerkleRoot,
    Uint8List previousMasterSeal,
  ) {
    final Uint8List expected = computeChainHash(
      previousMerkleRoot,
      previousMasterSeal,
    );

    // Constant-time comparison.
    if (chainHash.length != expected.length) return false;
    int diff = 0;
    for (int i = 0; i < chainHash.length; i++) {
      diff |= chainHash[i] ^ expected[i];
    }
    return diff == 0;
  }
}
