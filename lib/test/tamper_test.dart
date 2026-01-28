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

/// Creates a valid sealed file for tamper testing.
/// Uses multi-block content so we can test block swapping.
Uint8List _createValidFile({
  Uint8List? content,
  String filename = 'test.txt',
  Map<String, dynamic>? metadata,
}) {
  content ??= Uint8List.fromList(utf8.encode('Hello, Zegel!'));
  final options = ZegelOptions(
    contentType: 'text/plain',
    filename: filename,
    salt: _zeroSalt(),
    metadata: metadata,
  );
  return ZegelWriter(_testKey(), options).seal(content);
}

/// Creates a valid multi-block sealed file for advanced tamper tests.
Uint8List _createMultiBlockFile() {
  // 3 blocks: 65536 + 65536 + 100 bytes
  final content = Uint8List(65536 * 2 + 100);
  for (var i = 0; i < content.length; i++) {
    content[i] = i & 0xFF;
  }
  final options = ZegelOptions(
    contentType: 'application/octet-stream',
    filename: 'multi.bin',
    salt: _zeroSalt(),
  );
  return ZegelWriter(_testKey(), options).seal(content);
}

/// Computes offsets into the binary structure for a given filename length
/// and block count (no extended header fields).
Map<String, int> _computeOffsets(int filenameByteLen, int blockCount) {
  final saltOffset = 86 + filenameByteLen;
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
  group('Tamper detection', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    group('encrypted block data tampering', () {
      test('flip single bit in encrypted block data -> fails', () {
        final fileBytes = _createValidFile();

        // Locate encrypted block data:
        // For filename "test.txt" (8 bytes), 1 block, no extended header
        final offsets = _computeOffsets(8, 1);
        final blockDataOffset = offsets['merkleRoot']! + 32;

        // Copy and flip a bit
        final tampered = Uint8List.fromList(fileBytes);
        tampered[blockDataOffset] ^= 0x01;

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
          reason: 'Should detect flipped bit in encrypted block data',
        );
      });

      test('flip bit in middle of encrypted block data -> fails', () {
        final fileBytes = _createValidFile();
        final offsets = _computeOffsets(8, 1);
        final blockDataOffset = offsets['merkleRoot']! + 32;

        final tampered = Uint8List.fromList(fileBytes);
        // Flip a bit in the middle of the ciphertext
        final midOffset = blockDataOffset + 5;
        if (midOffset < fileBytes.length - 64) {
          tampered[midOffset] ^= 0x80;
        }

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
        );
      });
    });

    group('merkle root tampering', () {
      test('flip single bit in merkle root -> fails', () {
        final fileBytes = _createValidFile();
        final offsets = _computeOffsets(8, 1);

        final tampered = Uint8List.fromList(fileBytes);
        tampered[offsets['merkleRoot']!] ^= 0x01;

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
          reason: 'Should detect flipped bit in Merkle root',
        );
      });

      test('flip bit in last byte of merkle root -> fails', () {
        final fileBytes = _createValidFile();
        final offsets = _computeOffsets(8, 1);

        final tampered = Uint8List.fromList(fileBytes);
        tampered[offsets['merkleRoot']! + 31] ^= 0x01;

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
        );
      });
    });

    group('master seal tampering', () {
      test('flip single bit in master seal -> fails', () {
        final fileBytes = _createValidFile();

        final tampered = Uint8List.fromList(fileBytes);
        tampered[tampered.length - 1] ^= 0x01;

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
          reason: 'Should detect flipped bit in master seal',
        );
      });

      test('flip bit in first byte of master seal -> fails', () {
        final fileBytes = _createValidFile();

        final tampered = Uint8List.fromList(fileBytes);
        tampered[tampered.length - 64] ^= 0x01;

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
        );
      });

      test('flip bit in middle of master seal -> fails', () {
        final fileBytes = _createValidFile();

        final tampered = Uint8List.fromList(fileBytes);
        tampered[tampered.length - 32] ^= 0x01;

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
        );
      });
    });

    group('block directory tampering', () {
      test('flip single bit in block directory hash -> fails', () {
        final fileBytes = _createValidFile();
        final offsets = _computeOffsets(8, 1);

        // Block directory entry: type(1) + hash(32) + ciphertext_len(4) + iv(12) + tag(16)
        // The hash starts 1 byte after directory start
        final hashOffset = offsets['directory']! + 1;

        final tampered = Uint8List.fromList(fileBytes);
        tampered[hashOffset] ^= 0x01;

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
          reason: 'Should detect flipped bit in block directory hash',
        );
      });

      test('modify block directory ciphertext length -> fails', () {
        final fileBytes = _createValidFile();
        final offsets = _computeOffsets(8, 1);

        // Ciphertext length is at directory + 1 (type) + 32 (hash) = directory + 33
        final ctLenOffset = offsets['directory']! + 33;

        final tampered = Uint8List.fromList(fileBytes);
        // Increment the ciphertext length by 1
        final currentLen =
            ByteData.sublistView(tampered, ctLenOffset, ctLenOffset + 4)
                .getUint32(0, Endian.big);
        ByteData.sublistView(tampered, ctLenOffset, ctLenOffset + 4)
            .setUint32(0, currentLen + 1, Endian.big);

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
          reason: 'Should detect modified ciphertext length',
        );
      });
    });

    group('file size tampering', () {
      test('truncate file by 1 byte -> fails', () {
        final fileBytes = _createValidFile();

        final truncated = Uint8List.fromList(
            fileBytes.sublist(0, fileBytes.length - 1));

        expect(
          () => const ZegelReader().verify(truncated, masterKey),
          throwsA(anything),
          reason: 'Truncated file should fail verification',
        );
      });

      test('append 1 byte -> fails', () {
        final fileBytes = _createValidFile();

        final extended = Uint8List(fileBytes.length + 1);
        extended.setAll(0, fileBytes);
        extended[fileBytes.length] = 0xFF;

        expect(
          () => const ZegelReader().verify(extended, masterKey),
          throwsA(anything),
          reason: 'Appended file should fail verification',
        );
      });
    });

    group('block order tampering', () {
      test('swap two blocks -> fails', () {
        final fileBytes = _createMultiBlockFile();
        // filename "multi.bin" = 9 bytes, 3 blocks
        final offsets = _computeOffsets(9, 3);

        // Read ciphertext lengths from directory
        final dirStart = offsets['directory']!;
        final blockDataStart = offsets['merkleRoot']! + 32;

        // Parse directory entries to find ciphertext lengths
        final ctLengths = <int>[];
        for (var i = 0; i < 3; i++) {
          final entryStart = dirStart + i * 65;
          final ctLen =
              ByteData.sublistView(fileBytes, entryStart + 33, entryStart + 37)
                  .getUint32(0, Endian.big);
          ctLengths.add(ctLen);
        }

        // Find where block 0 and block 1 ciphertext data are
        final block0Start = blockDataStart;
        final block1Start = block0Start + ctLengths[0];

        // Only swap if both blocks exist
        if (block1Start + ctLengths[1] <= fileBytes.length - 64) {
          final tampered = Uint8List.fromList(fileBytes);

          // Swap the ciphertext of block 0 and block 1
          final block0Data =
              Uint8List.fromList(fileBytes.sublist(block0Start, block1Start));
          final block1End = block1Start + ctLengths[1];
          final block1Data =
              Uint8List.fromList(fileBytes.sublist(block1Start, block1End));

          // If blocks are the same size, we can swap directly
          // For different sizes, we need to handle the offset shift
          if (ctLengths[0] == ctLengths[1]) {
            tampered.setAll(block0Start, block1Data);
            tampered.setAll(block1Start, block0Data);
          } else {
            // Rebuild: block1Data first, then block0Data
            tampered.setAll(block0Start, block1Data);
            tampered.setAll(block0Start + ctLengths[1], block0Data);
          }

          expect(
            () => const ZegelReader().verify(tampered, masterKey),
            throwsA(anything),
            reason: 'Swapped blocks should fail verification',
          );
        }
      });

      test('replace one block with another -> fails', () {
        final fileBytes = _createMultiBlockFile();
        final offsets = _computeOffsets(9, 3);
        final blockDataStart = offsets['merkleRoot']! + 32;

        // Parse directory entries for ciphertext lengths
        final dirStart = offsets['directory']!;
        final ctLen0 =
            ByteData.sublistView(fileBytes, dirStart + 33, dirStart + 37)
                .getUint32(0, Endian.big);

        // Replace block 0 ciphertext with its bitwise complement
        final tampered = Uint8List.fromList(fileBytes);
        for (var i = 0; i < ctLen0; i++) {
          tampered[blockDataStart + i] ^= 0xFF;
        }

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
          reason: 'Replaced block should fail verification',
        );
      });
    });

    group('header tampering', () {
      test('modify header timestamp -> fails (seal mismatch)', () {
        final fileBytes = _createValidFile();

        final tampered = Uint8List.fromList(fileBytes);
        // Timestamp is at offset 12-19 (uint64 big-endian)
        // Increment the last byte
        tampered[19] ^= 0x01;

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
          reason: 'Modified timestamp should cause seal mismatch',
        );
      });

      test('modify flags -> fails', () {
        final fileBytes = _createValidFile();

        final tampered = Uint8List.fromList(fileBytes);
        // Flags at offset 10-11
        tampered[11] ^= 0x01;

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
          reason: 'Modified flags should cause seal mismatch',
        );
      });
    });

    group('IV tampering', () {
      test('zero out IV -> fails', () {
        final fileBytes = _createValidFile();
        final offsets = _computeOffsets(8, 1);

        // IV is at directory entry offset + 1 (type) + 32 (hash) + 4 (ct_len) = +37
        final ivOffset = offsets['directory']! + 37;

        final tampered = Uint8List.fromList(fileBytes);
        for (var i = 0; i < 12; i++) {
          tampered[ivOffset + i] = 0x00;
        }

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
          reason: 'Zeroed IV should cause seal mismatch or decryption failure',
        );
      });

      test('flip bit in IV -> fails', () {
        final fileBytes = _createValidFile();
        final offsets = _computeOffsets(8, 1);

        final ivOffset = offsets['directory']! + 37;

        final tampered = Uint8List.fromList(fileBytes);
        tampered[ivOffset] ^= 0x01;

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
        );
      });
    });

    group('auth tag tampering', () {
      test('flip bit in GCM auth tag -> fails', () {
        final fileBytes = _createValidFile();
        final offsets = _computeOffsets(8, 1);

        // Auth tag is at directory entry offset + 1 + 32 + 4 + 12 = +49
        final tagOffset = offsets['directory']! + 49;

        final tampered = Uint8List.fromList(fileBytes);
        tampered[tagOffset] ^= 0x01;

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
          reason: 'Flipped auth tag should cause seal mismatch or decryption failure',
        );
      });
    });

    group('content-type tampering', () {
      test('modify content-type field -> fails (seal mismatch)', () {
        final fileBytes = _createValidFile();

        final tampered = Uint8List.fromList(fileBytes);
        // Content-type is at offset 20-83
        tampered[20] ^= 0x01;

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
        );
      });
    });

    group('salt tampering', () {
      test('modify salt -> fails', () {
        final fileBytes = _createValidFile();
        final offsets = _computeOffsets(8, 1);

        final tampered = Uint8List.fromList(fileBytes);
        tampered[offsets['salt']!] ^= 0x01;

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
          reason: 'Modified salt should cause seal mismatch',
        );
      });
    });

    group('multiple simultaneous modifications', () {
      test('modify both header and block data -> fails', () {
        final fileBytes = _createValidFile();
        final offsets = _computeOffsets(8, 1);
        final blockDataOffset = offsets['merkleRoot']! + 32;

        final tampered = Uint8List.fromList(fileBytes);
        tampered[19] ^= 0x01; // timestamp
        tampered[blockDataOffset] ^= 0x01; // block data

        expect(
          () => const ZegelReader().verify(tampered, masterKey),
          throwsA(anything),
        );
      });
    });
  });
}
