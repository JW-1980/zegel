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

/// Helper to create a leaf hash from index for test convenience.
Uint8List _leafHash(int index) {
  return _sha256(Uint8List.fromList([index]));
}

void main() {
  group('MerkleTree', () {
    group('single leaf', () {
      test('root equals the leaf hash itself', () {
        final leaf = _sha256(Uint8List.fromList([1, 2, 3]));
        final root = MerkleTree.buildRoot([leaf]);
        expect(root, equals(leaf));
      });

      test('single leaf root is 32 bytes', () {
        final leaf = _sha256(Uint8List.fromList([42]));
        final root = MerkleTree.buildRoot([leaf]);
        expect(root.length, equals(32));
      });
    });

    group('two leaves', () {
      test('root is SHA-256 of leaf0 concatenated with leaf1', () {
        final leaf0 = _sha256(Uint8List.fromList([0]));
        final leaf1 = _sha256(Uint8List.fromList([1]));

        final expectedRoot = _sha256(_concat(leaf0, leaf1));
        final root = MerkleTree.buildRoot([leaf0, leaf1]);

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
    });

    group('three leaves (odd count)', () {
      test('root = SHA-256(SHA-256(leaf0||leaf1) || SHA-256(leaf2||leaf2))', () {
        final leaf0 = _leafHash(0);
        final leaf1 = _leafHash(1);
        final leaf2 = _leafHash(2);

        // Odd number of leaves: duplicate last node
        final left = _sha256(_concat(leaf0, leaf1));
        final right = _sha256(_concat(leaf2, leaf2)); // leaf2 duplicated
        final expectedRoot = _sha256(_concat(left, right));

        final root = MerkleTree.buildRoot([leaf0, leaf1, leaf2]);
        expect(root, equals(expectedRoot));
      });
    });

    group('four leaves (balanced)', () {
      test('produces correct balanced tree root', () {
        final leaf0 = _leafHash(0);
        final leaf1 = _leafHash(1);
        final leaf2 = _leafHash(2);
        final leaf3 = _leafHash(3);

        final left = _sha256(_concat(leaf0, leaf1));
        final right = _sha256(_concat(leaf2, leaf3));
        final expectedRoot = _sha256(_concat(left, right));

        final root = MerkleTree.buildRoot([leaf0, leaf1, leaf2, leaf3]);
        expect(root, equals(expectedRoot));
      });
    });

    group('eight leaves (three-level tree)', () {
      test('produces correct three-level tree root', () {
        final leaves = List.generate(8, (i) => _leafHash(i));

        // Level 1: pair adjacent leaves
        final n01 = _sha256(_concat(leaves[0], leaves[1]));
        final n23 = _sha256(_concat(leaves[2], leaves[3]));
        final n45 = _sha256(_concat(leaves[4], leaves[5]));
        final n67 = _sha256(_concat(leaves[6], leaves[7]));

        // Level 2: pair level-1 nodes
        final n0123 = _sha256(_concat(n01, n23));
        final n4567 = _sha256(_concat(n45, n67));

        // Level 3: root
        final expectedRoot = _sha256(_concat(n0123, n4567));

        final root = MerkleTree.buildRoot(leaves);
        expect(root, equals(expectedRoot));
      });
    });

    group('edge cases', () {
      test('empty list throws ArgumentError', () {
        expect(
          () => MerkleTree.buildRoot([]),
          throwsA(isA<ArgumentError>()),
        );
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
        final leaves = List.generate(5, (i) => _leafHash(i));

        final root1 = MerkleTree.buildRoot(leaves);
        final root2 = MerkleTree.buildRoot(leaves);
        final root3 = MerkleTree.buildRoot(leaves);

        expect(root1, equals(root2));
        expect(root2, equals(root3));
      });

      test('different inputs produce different roots', () {
        final leaves1 = List.generate(3, (i) => _leafHash(i));
        final leaves2 = List.generate(3, (i) => _leafHash(i + 10));

        final root1 = MerkleTree.buildRoot(leaves1);
        final root2 = MerkleTree.buildRoot(leaves2);

        expect(root1, isNot(equals(root2)));
      });

      test('adding a leaf changes the root', () {
        final leaves3 = List.generate(3, (i) => _leafHash(i));
        final leaves4 = List.generate(4, (i) => _leafHash(i));

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
        final leaves = List.generate(8, (i) => _leafHash(i));
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
          expect(verified, isTrue,
              reason: 'Inclusion proof failed for leaf at index $i');
        }
      });

      test('verifies inclusion at each position in odd-count tree', () {
        final leaves = List.generate(5, (i) => _leafHash(i));
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
          expect(verified, isTrue,
              reason: 'Inclusion proof failed for leaf at index $i');
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
        final verified = MerkleTree.verifyInclusion(
          root,
          leaf,
          0,
          proof,
          1,
        );
        expect(verified, isTrue);
      });
    });
  });
}
