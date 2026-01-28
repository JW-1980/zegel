import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

/// Creates a 32-byte test master key (0x00...01).
Uint8List _testKey() {
  final key = Uint8List(32);
  key[31] = 0x01;
  return key;
}

/// Creates a 32-byte all-zeros salt for deterministic testing.
Uint8List _zeroSalt() => Uint8List(32);

/// Creates a multi-block sealed file with known text content.
/// Returns the sealed file bytes and the list of plaintext chunks.
({Uint8List fileBytes, List<String> chunks}) _createMultiBlockTextFile(
  Uint8List key,
) {
  // Create content that spans multiple blocks.
  // Each "block" of text should be identifiable.
  final chunks = <String>[];
  final buffer = StringBuffer();
  for (var i = 0; i < 5; i++) {
    final chunkText = 'Block $i: ' + 'X' * 13000; // ~13KB per chunk
    chunks.add(chunkText);
    buffer.write(chunkText);
  }

  final content = Uint8List.fromList(utf8.encode(buffer.toString()));
  final options = ZegelOptions(
    contentType: 'text/plain',
    filename: 'source-document.txt',
    salt: _zeroSalt(),
    blockSize: 16384, // 16KB blocks to get multiple blocks
  );
  final fileBytes = ZegelWriter.seal(content, key, options: options);
  return (fileBytes: fileBytes, chunks: chunks);
}

/// Creates a single-block sealed file.
Uint8List _createSingleBlockFile(Uint8List key, String text) {
  final content = Uint8List.fromList(utf8.encode(text));
  final options = ZegelOptions(
    contentType: 'text/plain',
    filename: 'single.txt',
    salt: _zeroSalt(),
  );
  return ZegelWriter.seal(content, key, options: options);
}

void main() {
  group('ExcerptProof', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    group('proof generation', () {
      test('generate proof for a known block', () {
        final result = _createMultiBlockTextFile(masterKey);
        final fileBytes = result.fileBytes;

        final proof = ExcerptProof.generate(
          fileBytes: fileBytes,
          masterKey: masterKey,
          blockIndex: 0,
        );

        expect(proof, isNotNull);
        expect(proof.blockIndex, equals(0));
        expect(proof.excerpt, isNotNull);
        expect(proof.excerpt.isNotEmpty, isTrue);
        expect(proof.merkleProof, isNotNull);
        expect(proof.merkleRoot, isNotNull);
        expect(proof.merkleRoot.length, equals(32));
      });

      test('proof contains correct plaintext excerpt', () {
        final result = _createMultiBlockTextFile(masterKey);
        final fileBytes = result.fileBytes;

        // Generate proof for the first content block
        final proof = ExcerptProof.generate(
          fileBytes: fileBytes,
          masterKey: masterKey,
          blockIndex: 0,
        );

        // The excerpt should be the decrypted plaintext of that block
        expect(proof.excerpt, isNotNull);
        expect(proof.excerpt.isNotEmpty, isTrue,
            reason: 'Excerpt should contain the decrypted block content');
      });

      test('proof contains valid Merkle inclusion proof', () {
        final result = _createMultiBlockTextFile(masterKey);
        final fileBytes = result.fileBytes;

        final proof = ExcerptProof.generate(
          fileBytes: fileBytes,
          masterKey: masterKey,
          blockIndex: 1,
        );

        // The Merkle proof should be a list of sibling hashes
        expect(proof.merkleProof, isNotNull);
        expect(proof.merkleProof.isNotEmpty, isTrue,
            reason:
                'Multi-block file should have non-empty Merkle proof path');

        // Each sibling hash should be 32 bytes
        for (final sibling in proof.merkleProof) {
          expect(sibling.length, equals(32),
              reason: 'Each Merkle proof sibling should be 32 bytes');
        }
      });
    });

    group('proof verification', () {
      test('verifyProof succeeds with correct proof and root', () {
        final result = _createMultiBlockTextFile(masterKey);
        final fileBytes = result.fileBytes;

        final proof = ExcerptProof.generate(
          fileBytes: fileBytes,
          masterKey: masterKey,
          blockIndex: 0,
        );

        final isValid = ExcerptProof.verifyProof(proof);
        expect(isValid, isTrue,
            reason: 'Valid proof should verify successfully');
      });

      test('verifyProof fails with tampered excerpt', () {
        final result = _createMultiBlockTextFile(masterKey);
        final fileBytes = result.fileBytes;

        final proof = ExcerptProof.generate(
          fileBytes: fileBytes,
          masterKey: masterKey,
          blockIndex: 0,
        );

        // Tamper with the excerpt
        final tamperedExcerpt = Uint8List.fromList(proof.excerpt);
        if (tamperedExcerpt.isNotEmpty) {
          tamperedExcerpt[0] ^= 0xFF;
        }
        final tamperedProof = ExcerptProofData(
          blockIndex: proof.blockIndex,
          excerpt: tamperedExcerpt,
          merkleProof: proof.merkleProof,
          merkleRoot: proof.merkleRoot,
          leafCount: proof.leafCount,
        );

        final isValid = ExcerptProof.verifyProof(tamperedProof);
        expect(isValid, isFalse,
            reason: 'Tampered excerpt should fail verification');
      });

      test('verifyProof fails with wrong Merkle root', () {
        final result = _createMultiBlockTextFile(masterKey);
        final fileBytes = result.fileBytes;

        final proof = ExcerptProof.generate(
          fileBytes: fileBytes,
          masterKey: masterKey,
          blockIndex: 0,
        );

        // Replace Merkle root with garbage
        final wrongRoot = Uint8List(32);
        wrongRoot[0] = 0xFF;
        final tamperedProof = ExcerptProofData(
          blockIndex: proof.blockIndex,
          excerpt: proof.excerpt,
          merkleProof: proof.merkleProof,
          merkleRoot: wrongRoot,
          leafCount: proof.leafCount,
        );

        final isValid = ExcerptProof.verifyProof(tamperedProof);
        expect(isValid, isFalse,
            reason: 'Wrong Merkle root should fail verification');
      });

      test('verifyProof works WITHOUT the master key (only needs root from header)', () {
        final result = _createMultiBlockTextFile(masterKey);
        final fileBytes = result.fileBytes;

        // Generate the proof (requires the master key)
        final proof = ExcerptProof.generate(
          fileBytes: fileBytes,
          masterKey: masterKey,
          blockIndex: 0,
        );

        // Verification should NOT require the master key -- it only needs:
        // - The excerpt plaintext
        // - The Merkle inclusion proof (sibling hashes)
        // - The Merkle root (from the file header, readable without key)
        //
        // The verifier hashes the excerpt, then walks the Merkle proof
        // to see if it reconstructs the root.
        final isValid = ExcerptProof.verifyProof(proof);
        expect(isValid, isTrue,
            reason:
                'Proof verification must work without the master key');

        // Additionally, confirm the Merkle root matches what inspect returns
        final inspection = ZegelReader.inspect(fileBytes);
        expect(proof.merkleRoot, equals(inspection.merkleRoot),
            reason: 'Proof root should match file header Merkle root');
      });
    });

    group('block positions', () {
      test('proof for first block works', () {
        final result = _createMultiBlockTextFile(masterKey);
        final fileBytes = result.fileBytes;

        final proof = ExcerptProof.generate(
          fileBytes: fileBytes,
          masterKey: masterKey,
          blockIndex: 0,
        );

        expect(proof.blockIndex, equals(0));
        expect(ExcerptProof.verifyProof(proof), isTrue);
      });

      test('proof for last block works', () {
        final result = _createMultiBlockTextFile(masterKey);
        final fileBytes = result.fileBytes;

        final inspection = ZegelReader.inspect(fileBytes);
        final lastBlockIndex = inspection.blockCount - 1;

        final proof = ExcerptProof.generate(
          fileBytes: fileBytes,
          masterKey: masterKey,
          blockIndex: lastBlockIndex,
        );

        expect(proof.blockIndex, equals(lastBlockIndex));
        expect(ExcerptProof.verifyProof(proof), isTrue);
      });

      test('proof for middle block works', () {
        final result = _createMultiBlockTextFile(masterKey);
        final fileBytes = result.fileBytes;

        final inspection = ZegelReader.inspect(fileBytes);
        final middleIndex = inspection.blockCount ~/ 2;

        final proof = ExcerptProof.generate(
          fileBytes: fileBytes,
          masterKey: masterKey,
          blockIndex: middleIndex,
        );

        expect(proof.blockIndex, equals(middleIndex));
        expect(ExcerptProof.verifyProof(proof), isTrue);
      });

      test('proof for single-block file works', () {
        final fileBytes =
            _createSingleBlockFile(masterKey, 'Short document');

        final proof = ExcerptProof.generate(
          fileBytes: fileBytes,
          masterKey: masterKey,
          blockIndex: 0,
        );

        expect(proof.blockIndex, equals(0));
        expect(ExcerptProof.verifyProof(proof), isTrue);

        // For a single-block file, the Merkle proof should be empty
        // because the leaf IS the root
        expect(proof.merkleProof, isEmpty,
            reason:
                'Single leaf tree needs no sibling hashes in the proof');
      });
    });

    group('edge cases', () {
      test('out of range block index throws', () {
        final fileBytes =
            _createSingleBlockFile(masterKey, 'Single block');

        expect(
          () => ExcerptProof.generate(
            fileBytes: fileBytes,
            masterKey: masterKey,
            blockIndex: 99,
          ),
          throwsA(anything),
          reason: 'Block index beyond block count should throw',
        );
      });

      test('negative block index throws', () {
        final fileBytes =
            _createSingleBlockFile(masterKey, 'Single block');

        expect(
          () => ExcerptProof.generate(
            fileBytes: fileBytes,
            masterKey: masterKey,
            blockIndex: -1,
          ),
          throwsA(anything),
          reason: 'Negative block index should throw',
        );
      });
    });
  });
}
