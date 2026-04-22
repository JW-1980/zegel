import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

/// Creates a list of leaf hashes for a multi-block scenario.
/// Each leaf hash is SHA-256 of the block content.
List<Uint8List> _createMultiBlockLeafHashes(int blockCount) {
  final leafHashes = <Uint8List>[];
  for (var i = 0; i < blockCount; i++) {
    final blockContent = Uint8List.fromList(
      utf8.encode('Block $i: ${'X' * 13000}'),
    );
    leafHashes.add(Uint8List.fromList(sha256.convert(blockContent).bytes));
  }
  return leafHashes;
}

/// Creates a single leaf hash.
List<Uint8List> _createSingleLeafHash(String text) {
  final content = Uint8List.fromList(utf8.encode(text));
  return [Uint8List.fromList(sha256.convert(content).bytes)];
}

/// Converts a hex string to bytes.
Uint8List _hexToBytes(String hex) {
  final length = hex.length ~/ 2;
  final bytes = Uint8List(length);
  for (int i = 0; i < length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

void main() {
  group('ExcerptProof', () {
    group('proof generation', () {
      test('generate proof for a known block', () {
        final leafHashes = _createMultiBlockLeafHashes(5);

        final proof = ExcerptProof.generateProof(leafHashes, 0);

        expect(proof, isNotNull);
        expect(proof['block_index'], equals(0));
        expect(proof['block_hash'], isNotNull);
        expect((proof['block_hash'] as String).isNotEmpty, isTrue);
        expect(proof['proof'], isNotNull);
        expect(proof['merkle_root'], isNotNull);
        expect(
          (proof['merkle_root'] as String).length,
          equals(64),
          reason: 'Merkle root hex should be 64 chars (32 bytes)',
        );
      });

      test('proof contains correct block hash', () {
        final leafHashes = _createMultiBlockLeafHashes(5);

        // Generate proof for the first block
        final proof = ExcerptProof.generateProof(leafHashes, 0);

        // The block hash should match the leaf hash
        final expectedHash = leafHashes[0]
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        expect(
          proof['block_hash'],
          equals(expectedHash),
          reason: 'Proof block hash should match the leaf hash',
        );
      });

      test('proof contains valid Merkle inclusion proof path', () {
        final leafHashes = _createMultiBlockLeafHashes(5);

        final proof = ExcerptProof.generateProof(leafHashes, 1);

        // The Merkle proof should be a list of sibling hashes
        final proofPath = proof['proof'] as List<dynamic>;
        expect(proofPath, isNotNull);
        expect(
          proofPath.isNotEmpty,
          isTrue,
          reason: 'Multi-block tree should have non-empty Merkle proof path',
        );

        // Each sibling hash hex should be 64 chars (32 bytes)
        for (final sibling in proofPath) {
          expect(
            (sibling as String).length,
            equals(64),
            reason: 'Each Merkle proof sibling hex should be 64 chars',
          );
        }
      });
    });

    group('proof verification', () {
      test('verifyProof succeeds with correct proof and root', () {
        final leafHashes = _createMultiBlockLeafHashes(5);
        final expectedRoot = MerkleTree.buildRoot(leafHashes);

        final proof = ExcerptProof.generateProof(leafHashes, 0);

        final isValid = ExcerptProof.verifyProof(proof, expectedRoot);
        expect(
          isValid,
          isTrue,
          reason: 'Valid proof should verify successfully',
        );
      });

      test('verifyProof fails with tampered block hash', () {
        final leafHashes = _createMultiBlockLeafHashes(5);
        final expectedRoot = MerkleTree.buildRoot(leafHashes);

        final proof = ExcerptProof.generateProof(leafHashes, 0);

        // Tamper with the block hash
        final tamperedHash = _hexToBytes(proof['block_hash'] as String);
        if (tamperedHash.isNotEmpty) {
          tamperedHash[0] ^= 0xFF;
        }
        final tamperedHashHex = tamperedHash
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();

        final tamperedProof = Map<String, dynamic>.from(proof);
        tamperedProof['block_hash'] = tamperedHashHex;

        final isValid = ExcerptProof.verifyProof(tamperedProof, expectedRoot);
        expect(
          isValid,
          isFalse,
          reason: 'Tampered block hash should fail verification',
        );
      });

      test('verifyProof fails with wrong Merkle root', () {
        final leafHashes = _createMultiBlockLeafHashes(5);

        final proof = ExcerptProof.generateProof(leafHashes, 0);

        // Replace expected root with garbage
        final wrongRoot = Uint8List(32);
        wrongRoot[0] = 0xFF;

        final isValid = ExcerptProof.verifyProof(proof, wrongRoot);
        expect(
          isValid,
          isFalse,
          reason: 'Wrong Merkle root should fail verification',
        );
      });

      test('verifyProof works with only the root (no master key needed)', () {
        final leafHashes = _createMultiBlockLeafHashes(5);
        final expectedRoot = MerkleTree.buildRoot(leafHashes);

        // Generate the proof
        final proof = ExcerptProof.generateProof(leafHashes, 0);

        // Verification only needs:
        // - The proof data (block hash + sibling hashes)
        // - The expected Merkle root
        // No master key is involved.
        final isValid = ExcerptProof.verifyProof(proof, expectedRoot);
        expect(
          isValid,
          isTrue,
          reason: 'Proof verification must work without the master key',
        );

        // Additionally, confirm the proof's merkle_root matches the computed root
        final proofRootHex = proof['merkle_root'] as String;
        final computedRootHex = expectedRoot
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
        expect(
          proofRootHex,
          equals(computedRootHex),
          reason: 'Proof root should match computed Merkle root',
        );
      });
    });

    group('block positions', () {
      test('proof for first block works', () {
        final leafHashes = _createMultiBlockLeafHashes(5);
        final expectedRoot = MerkleTree.buildRoot(leafHashes);

        final proof = ExcerptProof.generateProof(leafHashes, 0);

        expect(proof['block_index'], equals(0));
        expect(ExcerptProof.verifyProof(proof, expectedRoot), isTrue);
      });

      test('proof for last block works', () {
        final leafHashes = _createMultiBlockLeafHashes(5);
        final expectedRoot = MerkleTree.buildRoot(leafHashes);
        final lastBlockIndex = leafHashes.length - 1;

        final proof = ExcerptProof.generateProof(leafHashes, lastBlockIndex);

        expect(proof['block_index'], equals(lastBlockIndex));
        expect(ExcerptProof.verifyProof(proof, expectedRoot), isTrue);
      });

      test('proof for middle block works', () {
        final leafHashes = _createMultiBlockLeafHashes(5);
        final expectedRoot = MerkleTree.buildRoot(leafHashes);
        final middleIndex = leafHashes.length ~/ 2;

        final proof = ExcerptProof.generateProof(leafHashes, middleIndex);

        expect(proof['block_index'], equals(middleIndex));
        expect(ExcerptProof.verifyProof(proof, expectedRoot), isTrue);
      });

      test('proof for single-block file works', () {
        final leafHashes = _createSingleLeafHash('Short document');
        final expectedRoot = MerkleTree.buildRoot(leafHashes);

        final proof = ExcerptProof.generateProof(leafHashes, 0);

        expect(proof['block_index'], equals(0));
        expect(ExcerptProof.verifyProof(proof, expectedRoot), isTrue);

        // For a single-block file, the Merkle proof should be empty
        // because the leaf IS the root
        final proofPath = proof['proof'] as List<dynamic>;
        expect(
          proofPath,
          isEmpty,
          reason: 'Single leaf tree needs no sibling hashes in the proof',
        );
      });
    });

    group('edge cases', () {
      test('out of range block index throws', () {
        final leafHashes = _createSingleLeafHash('Single block');

        expect(
          () => ExcerptProof.generateProof(leafHashes, 99),
          throwsA(anything),
          reason: 'Block index beyond block count should throw',
        );
      });

      test('negative block index throws', () {
        final leafHashes = _createSingleLeafHash('Single block');

        expect(
          () => ExcerptProof.generateProof(leafHashes, -1),
          throwsA(anything),
          reason: 'Negative block index should throw',
        );
      });
    });
  });
}
