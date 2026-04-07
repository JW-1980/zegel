import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Binary SHA-256 Merkle tree used by the Zegel format.
///
/// Leaf hashes are the SHA-256 digests of each block's plaintext. The tree is
/// built bottom-up: odd layers duplicate the last node, and parent hashes are
/// `SHA-256(left || right)` where left and right are raw 32-byte hashes.
///
/// A single leaf is its own root (no hashing step).
class MerkleTree {
  MerkleTree._();

  /// Builds the Merkle root hash from a list of [leafHashes].
  ///
  /// Each element of [leafHashes] must be exactly 32 bytes (a raw SHA-256
  /// digest). Returns the 32-byte root hash.
  ///
  /// Throws [ArgumentError] if [leafHashes] is empty.
  static Uint8List buildRoot(List<Uint8List> leafHashes) {
    if (leafHashes.isEmpty) {
      throw ArgumentError('Cannot build Merkle tree from zero leaves');
    }
    if (leafHashes.length == 1) {
      return Uint8List.fromList(leafHashes[0]);
    }

    List<Uint8List> layer = List<Uint8List>.from(leafHashes);

    while (layer.length > 1) {
      final List<Uint8List> nextLayer = <Uint8List>[];
      // Duplicate the last node if the layer has an odd count.
      if (layer.length.isOdd) {
        layer.add(Uint8List.fromList(layer.last));
      }
      for (int i = 0; i < layer.length; i += 2) {
        nextLayer.add(_hashPair(layer[i], layer[i + 1]));
      }
      layer = nextLayer;
    }

    return layer[0];
  }

  /// Builds the full Merkle tree, returning all layers from leaves (index 0)
  /// up to the root (last index).
  ///
  /// This is used to generate inclusion proofs.
  static List<List<Uint8List>> buildTree(List<Uint8List> leafHashes) {
    if (leafHashes.isEmpty) {
      throw ArgumentError('Cannot build Merkle tree from zero leaves');
    }

    final List<List<Uint8List>> layers = <List<Uint8List>>[];
    List<Uint8List> layer = List<Uint8List>.from(leafHashes);
    layers.add(List<Uint8List>.from(layer));

    while (layer.length > 1) {
      final List<Uint8List> nextLayer = <Uint8List>[];
      if (layer.length.isOdd) {
        layer.add(Uint8List.fromList(layer.last));
      }
      for (int i = 0; i < layer.length; i += 2) {
        nextLayer.add(_hashPair(layer[i], layer[i + 1]));
      }
      layer = nextLayer;
      layers.add(List<Uint8List>.from(layer));
    }

    return layers;
  }

  /// Generates an inclusion proof for the leaf at [index].
  ///
  /// Returns the list of sibling hashes needed to reconstruct the root from
  /// the leaf hash. Use [verifyInclusion] to check the proof.
  static List<Uint8List> generateProof(
    List<Uint8List> leafHashes,
    int index,
  ) {
    if (index < 0 || index >= leafHashes.length) {
      throw RangeError.range(index, 0, leafHashes.length - 1, 'index');
    }

    final List<List<Uint8List>> layers = buildTree(leafHashes);
    final List<Uint8List> proof = <Uint8List>[];
    int currentIndex = index;

    for (int i = 0; i < layers.length - 1; i++) {
      List<Uint8List> layer = layers[i];
      // If the layer has an odd count, the builder duplicated the last node.
      if (layer.length.isOdd) {
        layer = List<Uint8List>.from(layer)
          ..add(Uint8List.fromList(layer.last));
      }
      final int siblingIndex =
          currentIndex.isEven ? currentIndex + 1 : currentIndex - 1;
      proof.add(Uint8List.fromList(layer[siblingIndex]));
      currentIndex ~/= 2;
    }

    return proof;
  }

  /// Verifies a Merkle inclusion proof.
  ///
  /// Given the expected [root], the [leafHash] at [index] in a tree with
  /// [leafCount] total leaves, and the [proof] (sibling hashes), returns
  /// `true` if the proof is valid.
  static bool verifyInclusion(
    Uint8List root,
    Uint8List leafHash,
    int index,
    List<Uint8List> proof,
    int leafCount,
  ) {
    if (leafCount == 1 && proof.isEmpty) {
      return _constantTimeEquals(root, leafHash);
    }

    Uint8List currentHash = Uint8List.fromList(leafHash);
    int currentIndex = index;

    for (final Uint8List sibling in proof) {
      if (currentIndex.isEven) {
        currentHash = _hashPair(currentHash, sibling);
      } else {
        currentHash = _hashPair(sibling, currentHash);
      }
      currentIndex ~/= 2;
    }

    return _constantTimeEquals(root, currentHash);
  }

  /// Computes `SHA-256(left || right)` where both are raw 32-byte hashes.
  static Uint8List _hashPair(Uint8List left, Uint8List right) {
    final Uint8List combined = Uint8List(64);
    combined.setRange(0, 32, left);
    combined.setRange(32, 64, right);
    final digest = sha256.convert(combined);
    return Uint8List.fromList(digest.bytes);
  }

  /// Constant-time comparison of two byte arrays.
  ///
  /// Always iterates over all bytes to prevent timing side-channel attacks.
  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
