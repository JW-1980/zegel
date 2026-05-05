import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

/// Helper to compute SHA-256 hash of bytes.
Uint8List _sha256(Uint8List data) {
  return Uint8List.fromList(sha256.convert(data).bytes);
}

/// Helper to concatenate two Uint8Lists.
Uint8List _concat(Uint8List a, Uint8List b) {
  final result = Uint8List(a.length + b.length);
  result.setAll(0, a);
  result.setAll(a.length, b);
  return result;
}

/// Domain-separated leaf hash per RFC 6962: SHA-256(0x00 || rawHash).
Uint8List _leafDs(Uint8List rawHash) {
  final prefixed = Uint8List(1 + rawHash.length);
  prefixed[0] = 0x00;
  prefixed.setRange(1, prefixed.length, rawHash);
  return _sha256(prefixed);
}

/// Domain-separated internal node per RFC 6962: SHA-256(0x01 || left || right).
Uint8List _nodeDs(Uint8List left, Uint8List right) {
  final prefixed = Uint8List(1 + left.length + right.length);
  prefixed[0] = 0x01;
  prefixed.setRange(1, 1 + left.length, left);
  prefixed.setRange(1 + left.length, prefixed.length, right);
  return _sha256(prefixed);
}

/// Helper to create a raw leaf hash from an index (for test convenience).
/// This is the hash of the plaintext, BEFORE domain separation is applied
/// by buildRoot.
Uint8List _leafHash(int index) {
  return _sha256(Uint8List.fromList([index]));
}

void main() {
  group('MerkleTree (RFC 6962 domain-separated)', () {
    group('single leaf', () {
      test('root is domain-separated leaf hash (not raw leaf)', () {
        final rawLeaf = _sha256(Uint8List.fromList([1, 2, 3]));
        final root = MerkleTree.buildRoot([rawLeaf]);
        // Single leaf root must be SHA-256(0x00 || rawLeaf), not rawLeaf.
        expect(root, equals(_leafDs(rawLeaf)));
        expect(root, isNot(equals(rawLeaf)));
      });

      test('single leaf root is 32 bytes', () {
        final leaf = _sha256(Uint8List.fromList([42]));
        final root = MerkleTree.buildRoot([leaf]);
        expect(root.length, equals(32));
      });

      test('hashLeaf helper matches domain-separated format', () {
        final rawHash = _sha256(Uint8List.fromList([99]));
        expect(MerkleTree.hashLeaf(rawHash), equals(_leafDs(rawHash)));
      });
    });

    group('two leaves', () {
      test('root is domain-separated node of domain-separated leaves', () {
        final raw0 = _sha256(Uint8List.fromList([0]));
        final raw1 = _sha256(Uint8List.fromList([1]));

        final expectedRoot = _nodeDs(_leafDs(raw0), _leafDs(raw1));
        final root = MerkleTree.buildRoot([raw0, raw1]);

        expect(root, equals(expectedRoot));
      });

      test('root is 32 bytes', () {
        final leaf0 = _sha256(Uint8List.fromList([10]));
        final leaf1 = _sha256(Uint8List.fromList([20]));

        final root = MerkleTree.buildRoot([leaf0, leaf1]);
        expect(root.length, equals(32));
      });

      test('order matters - swapping leaves changes root', () {
        final leaf0 = _sha256(Uint8List.fromList([0]));
        final leaf1 = _sha256(Uint8List.fromList([1]));

        final root1 = MerkleTree.buildRoot([leaf0, leaf1]);
        final root2 = MerkleTree.buildRoot([leaf1, leaf0]);

        expect(root1, isNot(equals(root2)));
      });

      test('domain separation prevents second preimage attack', () {
        // This is the RFC 6962 second-preimage mitigation test.
        // A leaf whose plaintext data is exactly the concatenation of two
        // child hashes must NOT hash to the same value as the internal node.
        final raw0 = _sha256(Uint8List.fromList([1]));
        final raw1 = _sha256(Uint8List.fromList([2]));

        // Two-leaf tree root.
        final root = MerkleTree.buildRoot([raw0, raw1]);

        // Now build a combined leaf whose contents = leafDs(raw0) || leafDs(raw1).
        // Without domain separation, this would hash to the same as the
        // internal node and could be used as a second preimage.
        final concatenatedLeafData = _concat(_leafDs(raw0), _leafDs(raw1));
        final concatenatedLeafRaw = _sha256(concatenatedLeafData);
        final concatenatedTreeRoot = MerkleTree.buildRoot([concatenatedLeafRaw]);

        // The single-leaf root must differ from the two-leaf root.
        expect(concatenatedTreeRoot, isNot(equals(root)));
      });
    });

    group('three leaves (odd count)', () {
      test('root uses duplicated last node for odd layers', () {
        final raw0 = _leafHash(0);
        final raw1 = _leafHash(1);
        final raw2 = _leafHash(2);

        // Apply domain separation to leaves.
        final l0 = _leafDs(raw0);
        final l1 = _leafDs(raw1);
        final l2 = _leafDs(raw2);

        // Odd number of leaves: duplicate last, then pair.
        final left = _nodeDs(l0, l1);
        final right = _nodeDs(l2, l2); // l2 duplicated
        final expectedRoot = _nodeDs(left, right);

        final root = MerkleTree.buildRoot([raw0, raw1, raw2]);
        expect(root, equals(expectedRoot));
      });
    });

    group('four leaves (balanced)', () {
      test('produces correct balanced tree root', () {
        final raw0 = _leafHash(0);
        final raw1 = _leafHash(1);
        final raw2 = _leafHash(2);
        final raw3 = _leafHash(3);

        final l0 = _leafDs(raw0);
        final l1 = _leafDs(raw1);
        final l2 = _leafDs(raw2);
        final l3 = _leafDs(raw3);

        final left = _nodeDs(l0, l1);
        final right = _nodeDs(l2, l3);
        final expectedRoot = _nodeDs(left, right);

        final root = MerkleTree.buildRoot([raw0, raw1, raw2, raw3]);
        expect(root, equals(expectedRoot));
      });
    });

    group('eight leaves (three-level tree)', () {
      test('produces correct three-level tree root', () {
        final rawLeaves = List.generate(8, _leafHash);
        final leaves = rawLeaves.map(_leafDs).toList();

        // Level 1: pair adjacent leaves
        final n01 = _nodeDs(leaves[0], leaves[1]);
        final n23 = _nodeDs(leaves[2], leaves[3]);
        final n45 = _nodeDs(leaves[4], leaves[5]);
        final n67 = _nodeDs(leaves[6], leaves[7]);

        // Level 2
        final n0123 = _nodeDs(n01, n23);
        final n4567 = _nodeDs(n45, n67);

        // Level 3
        final expectedRoot = _nodeDs(n0123, n4567);

        final root = MerkleTree.buildRoot(rawLeaves);
        expect(root, equals(expectedRoot));
      });
    });

    group('edge cases', () {
      test('empty list throws ArgumentError', () {
        expect(() => MerkleTree.buildRoot([]), throwsA(isA<ArgumentError>()));
      });

      test('large number of leaves (128) produces 32-byte root', () {
        final leaves = List.generate(128, (i) {
          final data = Uint8List(4);
          data.buffer.asByteData().setUint32(0, i);
          return _sha256(data);
        });

        final root = MerkleTree.buildRoot(leaves);
        expect(root.length, equals(32));
      });

      test('large number of leaves (100, not power of 2)', () {
        final leaves = List.generate(100, (i) {
          final data = Uint8List(4);
          data.buffer.asByteData().setUint32(0, i);
          return _sha256(data);
        });

        final root = MerkleTree.buildRoot(leaves);
        expect(root.length, equals(32));
      });
    });

    group('determinism', () {
      test('same inputs always produce the same root', () {
        final leaves = List.generate(5, _leafHash);

        final root1 = MerkleTree.buildRoot(leaves);
        final root2 = MerkleTree.buildRoot(leaves);
        final root3 = MerkleTree.buildRoot(leaves);

        expect(root1, equals(root2));
        expect(root2, equals(root3));
      });

      test('different inputs produce different roots', () {
        final leaves1 = List.generate(3, _leafHash);
        final leaves2 = List.generate(3, (i) => _leafHash(i + 10));

        final root1 = MerkleTree.buildRoot(leaves1);
        final root2 = MerkleTree.buildRoot(leaves2);

        expect(root1, isNot(equals(root2)));
      });

      test('adding a leaf changes the root', () {
        final leaves3 = List.generate(3, _leafHash);
        final leaves4 = List.generate(4, _leafHash);

        final root3 = MerkleTree.buildRoot(leaves3);
        final root4 = MerkleTree.buildRoot(leaves4);

        expect(root3, isNot(equals(root4)));
      });
    });

    group('inclusion proofs', () {
      test('verifies inclusion of first leaf in two-leaf tree', () {
        final leaves = [_leafHash(0), _leafHash(1)];
        final root = MerkleTree.buildRoot(leaves);

        final proof = MerkleTree.generateProof(leaves, 0);
        final verified = MerkleTree.verifyInclusion(
          root,
          leaves[0],
          0,
          proof,
          leaves.length,
        );
        expect(verified, isTrue);
      });

      test('verifies inclusion of second leaf in two-leaf tree', () {
        final leaves = [_leafHash(0), _leafHash(1)];
        final root = MerkleTree.buildRoot(leaves);

        final proof = MerkleTree.generateProof(leaves, 1);
        final verified = MerkleTree.verifyInclusion(
          root,
          leaves[1],
          1,
          proof,
          leaves.length,
        );
        expect(verified, isTrue);
      });

      test('verifies inclusion at each position in 8-leaf tree', () {
        final leaves = List.generate(8, _leafHash);
        final root = MerkleTree.buildRoot(leaves);

        for (var i = 0; i < 8; i++) {
          final proof = MerkleTree.generateProof(leaves, i);
          final verified = MerkleTree.verifyInclusion(
            root,
            leaves[i],
            i,
            proof,
            leaves.length,
          );
          expect(
            verified,
            isTrue,
            reason: 'Inclusion proof failed for leaf at index $i',
          );
        }
      });

      test('verifies inclusion at each position in odd-count tree', () {
        final leaves = List.generate(5, _leafHash);
        final root = MerkleTree.buildRoot(leaves);

        for (var i = 0; i < 5; i++) {
          final proof = MerkleTree.generateProof(leaves, i);
          final verified = MerkleTree.verifyInclusion(
            root,
            leaves[i],
            i,
            proof,
            leaves.length,
          );
          expect(
            verified,
            isTrue,
            reason: 'Inclusion proof failed for leaf at index $i',
          );
        }
      });

      test('rejects wrong leaf with valid proof', () {
        final leaves = [_leafHash(0), _leafHash(1)];
        final root = MerkleTree.buildRoot(leaves);

        final proof = MerkleTree.generateProof(leaves, 0);
        // Try verifying with the wrong leaf
        final verified = MerkleTree.verifyInclusion(
          root,
          _leafHash(99),
          0,
          proof,
          leaves.length,
        );
        expect(verified, isFalse);
      });

      test('rejects valid leaf with wrong root', () {
        final leaves = [_leafHash(0), _leafHash(1)];
        final wrongRoot = _sha256(Uint8List(32)); // wrong root

        final proof = MerkleTree.generateProof(leaves, 0);
        final verified = MerkleTree.verifyInclusion(
          wrongRoot,
          leaves[0],
          0,
          proof,
          leaves.length,
        );
        expect(verified, isFalse);
      });

      test('single leaf inclusion proof is trivial', () {
        final leaf = _leafHash(0);
        final root = MerkleTree.buildRoot([leaf]);

        final proof = MerkleTree.generateProof([leaf], 0);
        final verified = MerkleTree.verifyInclusion(root, leaf, 0, proof, 1);
        expect(verified, isTrue);
      });
    });
  });
}
