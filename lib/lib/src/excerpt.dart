import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'merkle_tree.dart';

/// Excerpt proofs using Merkle inclusion (v1.3).
///
/// Allows proving that specific blocks belong to a sealed file without
/// revealing the full file, using Merkle tree inclusion proofs.
class ExcerptProof {
  ExcerptProof._();

  /// Generates an excerpt proof for a specific block.
  ///
  /// [leafHashes] is the list of all block hashes (leaves of the Merkle tree).
  /// [blockIndex] is the index of the block to prove.
  ///
  /// Returns a map containing the proof path (sibling hashes) and the
  /// Merkle root.
  static Map<String, dynamic> generateProof(
    List<Uint8List> leafHashes,
    int blockIndex,
  ) {
    if (blockIndex < 0 || blockIndex >= leafHashes.length) {
      throw RangeError('Block index $blockIndex out of range [0, ${leafHashes.length})');
    }

    final proof = MerkleTree.generateProof(leafHashes, blockIndex);
    final root = MerkleTree.buildRoot(leafHashes);

    return {
      'block_index': blockIndex,
      'block_hash': _bytesToHex(leafHashes[blockIndex]),
      'merkle_root': _bytesToHex(root),
      'proof': proof.map((p) => _bytesToHex(p)).toList(),
      'total_leaves': leafHashes.length,
    };
  }

  /// Verifies an excerpt proof.
  ///
  /// [proofData] is the map returned by [generateProof].
  /// [expectedRoot] is the 32-byte Merkle root from the file header.
  ///
  /// Returns true if the block hash can be traced to the expected root.
  static bool verifyProof(
    Map<String, dynamic> proofData,
    Uint8List expectedRoot,
  ) {
    final blockIndex = proofData['block_index'] as int;
    final blockHash = _hexToBytes(proofData['block_hash'] as String);
    final proofHashes = (proofData['proof'] as List<dynamic>)
        .map((h) => _hexToBytes(h as String))
        .toList();
    final totalLeaves = proofData['total_leaves'] as int;

    return MerkleTree.verifyInclusion(
      expectedRoot,
      blockHash,
      blockIndex,
      proofHashes,
      totalLeaves,
    );
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List _hexToBytes(String hex) {
    final length = hex.length ~/ 2;
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
