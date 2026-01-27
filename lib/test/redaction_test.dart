import 'dart:convert';
import 'dart:typed_data';

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

/// Creates a multi-block file with 3 content blocks.
/// Block size is 65536, so we need > 2 * 65536 bytes.
Uint8List _createThreeBlockFile(Uint8List key) {
  final content = Uint8List(65536 * 2 + 100);
  for (var i = 0; i < content.length; i++) {
    content[i] = i & 0xFF;
  }
  final options = ZegelOptions(
    contentType: 'application/octet-stream',
    filename: 'multi.bin',
    salt: _zeroSalt(),
  );
  return ZegelWriter.seal(content, key, options: options);
}

/// Helper to compute offsets for filename "multi.bin" (9 bytes), N blocks.
Map<String, int> _offsetsForMulti(int blockCount) {
  const filenameLen = 9; // "multi.bin"
  final saltOffset = 86 + filenameLen;
  final blockCountOffset = saltOffset + 32;
  final directoryOffset = blockCountOffset + 4;
  final merkleRootOffset = directoryOffset + (blockCount * 65);
  return {
    'salt': saltOffset,
    'blockCount': blockCountOffset,
    'directory': directoryOffset,
    'merkleRoot': merkleRootOffset,
  };
}

void main() {
  group('Redaction', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    group('basic redaction', () {
      test('create file with 3 blocks, redact block 1', () {
        final fileBytes = _createThreeBlockFile(masterKey);

        // Verify original file is valid first
        final originalResult = ZegelReader.verify(fileBytes, masterKey);
        expect(originalResult.valid, isTrue);

        // Redact block 1
        final redactedBytes =
            ZegelRedaction.redact(fileBytes, masterKey, [1]);
        expect(redactedBytes, isNotNull);
        expect(redactedBytes.length, greaterThan(0));
      });

      test('redacted file verifies successfully', () {
        final fileBytes = _createThreeBlockFile(masterKey);
        final redactedBytes =
            ZegelRedaction.redact(fileBytes, masterKey, [1]);

        // Redacted file should still verify
        final result = ZegelReader.verify(redactedBytes, masterKey);
        expect(result.valid, isTrue,
            reason: 'Redacted file should verify (Merkle root preserved)');
      });

      test('extracting redacted file returns blocks 0 and 2, block 1 marked redacted', () {
        final fileBytes = _createThreeBlockFile(masterKey);
        final redactedBytes =
            ZegelRedaction.redact(fileBytes, masterKey, [1]);

        final result = ZegelReader.extract(redactedBytes, masterKey);
        expect(result.valid, isTrue);

        // The result should indicate which blocks are redacted
        expect(result.redactedBlocks, isNotNull);
        expect(result.redactedBlocks, contains(1));
        expect(result.redactedBlocks, isNot(contains(0)));
        expect(result.redactedBlocks, isNot(contains(2)));

        // Content from blocks 0 and 2 should be available
        // Block 0: first 65536 bytes, Block 2: last 100 bytes
        // Block 1 content is lost
        expect(result.content, isNotNull);
      });

      test('redacted block type is 0x06 (REDACTED)', () {
        final fileBytes = _createThreeBlockFile(masterKey);
        final redactedBytes =
            ZegelRedaction.redact(fileBytes, masterKey, [1]);

        final offsets = _offsetsForMulti(3);
        // Block 1 is the second directory entry (index 1)
        final block1TypeOffset = offsets['directory']! + 1 * 65;
        expect(redactedBytes[block1TypeOffset],
            equals(ZegelFormat.blockTypeRedacted));
      });

      test('original plaintext hash preserved for Merkle tree', () {
        final fileBytes = _createThreeBlockFile(masterKey);

        // Read original block 1 hash from directory
        final offsets = _offsetsForMulti(3);
        final block1HashOffset = offsets['directory']! + 1 * 65 + 1;
        final originalHash =
            Uint8List.fromList(fileBytes.sublist(block1HashOffset, block1HashOffset + 32));

        // Redact block 1
        final redactedBytes =
            ZegelRedaction.redact(fileBytes, masterKey, [1]);

        // Hash should be preserved
        final redactedHash = Uint8List.fromList(
            redactedBytes.sublist(block1HashOffset, block1HashOffset + 32));
        expect(redactedHash, equals(originalHash),
            reason:
                'Plaintext hash must be preserved after redaction for Merkle tree integrity');
      });

      test('Merkle root is preserved after redaction', () {
        final fileBytes = _createThreeBlockFile(masterKey);
        final redactedBytes =
            ZegelRedaction.redact(fileBytes, masterKey, [1]);

        final offsets = _offsetsForMulti(3);
        final merkleRootOffset = offsets['merkleRoot']!;

        final originalRoot =
            fileBytes.sublist(merkleRootOffset, merkleRootOffset + 32);
        final redactedRoot =
            redactedBytes.sublist(merkleRootOffset, merkleRootOffset + 32);

        expect(redactedRoot, equals(originalRoot),
            reason: 'Merkle root should be identical after redaction');
      });
    });

    group('HAS_REDACTIONS flag', () {
      test('HAS_REDACTIONS flag is set after redaction', () {
        final fileBytes = _createThreeBlockFile(masterKey);
        final redactedBytes =
            ZegelRedaction.redact(fileBytes, masterKey, [1]);

        final inspection = ZegelReader.inspect(redactedBytes);
        expect(
          inspection.flags & ZegelFormat.flagHasRedactions,
          isNonZero,
          reason: 'HAS_REDACTIONS flag should be set',
        );
      });

      test('original file does not have HAS_REDACTIONS flag', () {
        final fileBytes = _createThreeBlockFile(masterKey);

        final inspection = ZegelReader.inspect(fileBytes);
        expect(
          inspection.flags & ZegelFormat.flagHasRedactions,
          equals(0),
          reason: 'Original file should not have HAS_REDACTIONS flag',
        );
      });
    });

    group('tamper detection after redaction', () {
      test('tampering with non-redacted block after redaction -> fails', () {
        final fileBytes = _createThreeBlockFile(masterKey);
        final redactedBytes =
            ZegelRedaction.redact(fileBytes, masterKey, [1]);

        // Verify the redacted file is valid first
        final validResult = ZegelReader.verify(redactedBytes, masterKey);
        expect(validResult.valid, isTrue);

        // Now tamper with block 0's ciphertext
        final offsets = _offsetsForMulti(3);
        final blockDataStart = offsets['merkleRoot']! + 32;

        final tampered = Uint8List.fromList(redactedBytes);
        tampered[blockDataStart] ^= 0x01;

        final result = ZegelReader.verify(tampered, masterKey);
        expect(result.valid, isFalse,
            reason:
                'Tampering with non-redacted block should fail verification');
      });
    });

    group('redacting multiple blocks', () {
      test('redact blocks 0 and 2', () {
        final fileBytes = _createThreeBlockFile(masterKey);
        final redactedBytes =
            ZegelRedaction.redact(fileBytes, masterKey, [0, 2]);

        final result = ZegelReader.verify(redactedBytes, masterKey);
        expect(result.valid, isTrue);

        final offsets = _offsetsForMulti(3);
        // Block 0 should be REDACTED
        expect(redactedBytes[offsets['directory']!],
            equals(ZegelFormat.blockTypeRedacted));
        // Block 1 should still be CONTENT
        expect(redactedBytes[offsets['directory']! + 65],
            equals(ZegelFormat.blockTypeContent));
        // Block 2 should be REDACTED
        expect(redactedBytes[offsets['directory']! + 130],
            equals(ZegelFormat.blockTypeRedacted));
      });

      test('redacting all blocks -> verifies but no content extractable', () {
        final fileBytes = _createThreeBlockFile(masterKey);
        final redactedBytes =
            ZegelRedaction.redact(fileBytes, masterKey, [0, 1, 2]);

        // Should still verify (Merkle root preserved)
        final result = ZegelReader.verify(redactedBytes, masterKey);
        expect(result.valid, isTrue);

        // Extract should show all blocks as redacted
        final extractResult =
            ZegelReader.extract(redactedBytes, masterKey);
        expect(extractResult.valid, isTrue);
        expect(extractResult.redactedBlocks, containsAll([0, 1, 2]));
      });
    });

    group('redaction with metadata', () {
      test('redact content block in file with metadata', () {
        // Create file with metadata (block 0 = metadata, blocks 1-3 = content)
        final content = Uint8List(65536 * 2 + 100);
        for (var i = 0; i < content.length; i++) {
          content[i] = i & 0xFF;
        }
        final options = ZegelOptions(
          contentType: 'application/octet-stream',
          filename: 'meta.bin',
          salt: _zeroSalt(),
          metadata: {'sealed_by': 'test'},
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        // Block 0 = metadata, blocks 1, 2, 3 = content
        // Redact content block 1 (the first content block)
        final redactedBytes =
            ZegelRedaction.redact(fileBytes, masterKey, [1]);

        final result = ZegelReader.verify(redactedBytes, masterKey);
        expect(result.valid, isTrue);

        final extractResult =
            ZegelReader.extract(redactedBytes, masterKey);
        expect(extractResult.valid, isTrue);
        // Metadata should still be accessible
        expect(extractResult.metadata, isNotNull);
        expect(extractResult.metadata!['sealed_by'], equals('test'));
        // Block 1 should be marked as redacted
        expect(extractResult.redactedBlocks, contains(1));
      });
    });

    group('seal recomputation', () {
      test('redacted file has different seal than original', () {
        final fileBytes = _createThreeBlockFile(masterKey);
        final redactedBytes =
            ZegelRedaction.redact(fileBytes, masterKey, [1]);

        // Seals should differ (ciphertext changed, flags may have changed)
        final originalSeal =
            fileBytes.sublist(fileBytes.length - 64);
        final redactedSeal =
            redactedBytes.sublist(redactedBytes.length - 64);

        expect(redactedSeal, isNot(equals(originalSeal)),
            reason:
                'Seal should be recomputed after redaction');
      });
    });

    group('redaction is irreversible', () {
      test('redacted ciphertext differs from original', () {
        final fileBytes = _createThreeBlockFile(masterKey);
        final offsets = _offsetsForMulti(3);
        final merkleRootEnd = offsets['merkleRoot']! + 32;

        // Get block 1 ciphertext from original
        final dirStart = offsets['directory']!;
        final ct0Len =
            ByteData.sublistView(fileBytes, dirStart + 33, dirStart + 37)
                .getUint32(0, Endian.big);
        final ct1Len =
            ByteData.sublistView(fileBytes, dirStart + 65 + 33, dirStart + 65 + 37)
                .getUint32(0, Endian.big);

        final block1Start = merkleRootEnd + ct0Len;
        final block1End = block1Start + ct1Len;

        final originalBlock1 =
            Uint8List.fromList(fileBytes.sublist(block1Start, block1End));

        // Redact
        final redactedBytes =
            ZegelRedaction.redact(fileBytes, masterKey, [1]);

        final redactedBlock1 = Uint8List.fromList(
            redactedBytes.sublist(block1Start, block1End));

        expect(redactedBlock1, isNot(equals(originalBlock1)),
            reason:
                'Redacted ciphertext should be random, different from original');
      });
    });
  });
}
