import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

/// Output size assertion tests (v1.4).
///
/// These tests verify that the exact byte count of a sealed .zgl file
/// matches what FORMAT_SPEC.md predicts for given inputs. Any extra bytes
/// would indicate a potential steganographic / kleptographic channel where
/// a compromised implementation could leak key material.
///
/// The Zegel binary layout (per FORMAT_SPEC.md Section 3):
///
/// ```
/// Offset  Size       Field
/// 0       8          Magic bytes
/// 8       1          Version major
/// 9       1          Version minor
/// 10      2          Flags (uint16 BE)
/// 12      8          Created timestamp (uint64 BE)
/// 20      64         Content-Type (UTF-8, null-padded)
/// 84      2          Filename length
/// 86      N          Filename (UTF-8)
/// 86+N    32         Master salt
/// 118+N   4          Block count
/// 122+N   ???        Extended header (flag-dependent)
///         B*65       Block directory (65 bytes per block)
///         32         Merkle root
///         32         [Key commitment if HAS_KEY_COMMITMENT]
///         ???        Encrypted block data
///         64         Master seal (HMAC-SHA512)
/// ```
///
/// Each block's ciphertext length equals its plaintext length (GCM adds the
/// tag separately, stored in the directory entry, not concatenated to the
/// ciphertext in the data section).

/// Creates a 32-byte test master key.
Uint8List _testKey() {
  final key = Uint8List(32);
  key[31] = 0x01;
  return key;
}

/// Computes the expected size of a sealed .zgl file for given inputs.
int _expectedSize({
  required int plaintextLength,
  required int filenameLength,
  required int blockSize,
  bool hasKeyCommitment = false,
  int? publicMetadataLength,
  int metadataLength = 0, // 0 = no metadata block
}) {
  // Fixed header: 86 bytes + filename + salt(32) + block count(4) = 122 + N.
  int size = 122 + filenameLength;

  // Extended header - depends on flags.
  if (publicMetadataLength != null) {
    size += 4 + publicMetadataLength; // length prefix + metadata
  }

  // Number of content blocks.
  int blockCount;
  if (plaintextLength == 0) {
    blockCount = 1; // Empty content produces 1 empty block.
  } else {
    blockCount = (plaintextLength + blockSize - 1) ~/ blockSize;
  }

  // Metadata block adds 1 to block count.
  if (metadataLength > 0) {
    blockCount += 1;
  }

  // Block directory: 65 bytes per block (type 1 + hash 32 + ctLen 4 + iv 12 + tag 16).
  size += blockCount * 65;

  // Merkle root.
  size += 32;

  // Key commitment.
  if (hasKeyCommitment) {
    size += 32;
  }

  // Encrypted block data: ciphertext length = plaintext length for each block.
  // Metadata block contains the JSON-encoded metadata.
  if (metadataLength > 0) {
    size += metadataLength;
  }
  size += plaintextLength;

  // Master seal.
  size += 64;

  return size;
}

void main() {
  final masterKey = _testKey();

  group('Output size assertions (anti-kleptographic)', () {
    test('empty content produces expected size', () {
      final content = Uint8List(0);
      const options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'empty.txt',
      );
      final sealed = ZegelWriter(masterKey, options).seal(content);

      final expected = _expectedSize(
        plaintextLength: 0,
        filenameLength: 9, // "empty.txt"
        blockSize: 65536,
      );

      expect(sealed.length, equals(expected),
          reason: 'Empty content should produce exactly $expected bytes');
    });

    test('13-byte content "Hello, Zegel!" produces expected size', () {
      final content = Uint8List.fromList(utf8.encode('Hello, Zegel!'));
      const options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'test.txt',
      );
      final sealed = ZegelWriter(masterKey, options).seal(content);

      final expected = _expectedSize(
        plaintextLength: 13,
        filenameLength: 8,
        blockSize: 65536,
      );

      expect(sealed.length, equals(expected));
    });

    test('exactly 65536 bytes produces 1 block of expected size', () {
      final content = Uint8List(65536);
      for (var i = 0; i < content.length; i++) {
        content[i] = i & 0xFF;
      }
      const options = ZegelOptions(
        contentType: 'application/octet-stream',
        filename: 'boundary.bin',
      );
      final sealed = ZegelWriter(masterKey, options).seal(content);

      final expected = _expectedSize(
        plaintextLength: 65536,
        filenameLength: 12, // "boundary.bin"
        blockSize: 65536,
      );

      expect(sealed.length, equals(expected));
    });

    test('65537 bytes produces 2 blocks of expected size', () {
      final content = Uint8List(65537);
      for (var i = 0; i < content.length; i++) {
        content[i] = i & 0xFF;
      }
      const options = ZegelOptions(
        contentType: 'application/octet-stream',
        filename: 'over.bin',
      );
      final sealed = ZegelWriter(masterKey, options).seal(content);

      final expected = _expectedSize(
        plaintextLength: 65537,
        filenameLength: 8, // "over.bin"
        blockSize: 65536,
      );

      expect(sealed.length, equals(expected));
    });

    test('large file (1 MiB = 16 blocks) produces expected size', () {
      final content = Uint8List(1024 * 1024);
      for (var i = 0; i < content.length; i++) {
        content[i] = i & 0xFF;
      }
      const options = ZegelOptions(
        contentType: 'application/octet-stream',
        filename: '1mb.bin',
      );
      final sealed = ZegelWriter(masterKey, options).seal(content);

      final expected = _expectedSize(
        plaintextLength: 1024 * 1024,
        filenameLength: 7, // "1mb.bin"
        blockSize: 65536,
      );

      expect(sealed.length, equals(expected));
    });

    test('file with key commitment adds exactly 32 bytes', () {
      final content = Uint8List.fromList(utf8.encode('kc test'));
      const optionsBase = ZegelOptions(
        contentType: 'text/plain',
        filename: 'kc.txt',
      );
      const optionsKc = ZegelOptions(
        contentType: 'text/plain',
        filename: 'kc.txt',
        enableKeyCommitment: true,
      );

      final sealedBase = ZegelWriter(masterKey, optionsBase).seal(content);
      final sealedKc = ZegelWriter(masterKey, optionsKc).seal(content);

      expect(sealedKc.length - sealedBase.length, equals(32),
          reason: 'Key commitment must add exactly 32 bytes');
    });

    test('two seals of same content produce same size', () {
      // This protects against steganographic channels where different
      // runs might use different amounts of "random padding".
      final content = Uint8List.fromList(utf8.encode('deterministic size'));
      const options1 = ZegelOptions(
        contentType: 'text/plain',
        filename: 'same.txt',
      );
      const options2 = ZegelOptions(
        contentType: 'text/plain',
        filename: 'same.txt',
      );

      final sealed1 = ZegelWriter(masterKey, options1).seal(content);
      final sealed2 = ZegelWriter(masterKey, options2).seal(content);

      expect(sealed1.length, equals(sealed2.length),
          reason: 'Same inputs must always produce same output size');
    });

    test('no extra bytes appended after master seal', () {
      // Verify the master seal is exactly the last 64 bytes, not followed
      // by any trailer (which could be a subliminal channel).
      final content = Uint8List.fromList(utf8.encode('trailer check'));
      const options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'trailer.txt',
      );
      final sealed = ZegelWriter(masterKey, options).seal(content);

      // The last 64 bytes are the master seal. Beyond that, nothing.
      // If there were extra bytes, the expected size calculation would fail.
      final expected = _expectedSize(
        plaintextLength: 13,
        filenameLength: 11, // "trailer.txt"
        blockSize: 65536,
      );
      expect(sealed.length, equals(expected));
    });

    test('filename length boundary (255 bytes) produces expected size', () {
      final longFilename = 'a' * 255;
      final content = Uint8List.fromList(utf8.encode('x'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: longFilename,
      );
      final sealed = ZegelWriter(masterKey, options).seal(content);

      final expected = _expectedSize(
        plaintextLength: 1,
        filenameLength: 255,
        blockSize: 65536,
      );

      expect(sealed.length, equals(expected));
    });

    test('roundtrip of size-asserted file works', () {
      // Ensure our size calculation doesn't compromise verifiability.
      final content = Uint8List.fromList(utf8.encode('roundtrip check'));
      const options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'rt.txt',
      );
      final sealed = ZegelWriter(masterKey, options).seal(content);
      final result = const ZegelReader().verify(sealed, masterKey);

      expect(result.valid, isTrue);
      expect(result.content, equals(content));
    });
  });

  group('Ciphertext length equals plaintext length (no GCM overhead inline)',
      () {
    test('single block ciphertext length matches directory entry', () {
      final content = Uint8List(1000);
      for (var i = 0; i < 1000; i++) {
        content[i] = i & 0xFF;
      }
      const options = ZegelOptions(
        contentType: 'application/octet-stream',
        filename: 'ct.bin',
      );
      final sealed = ZegelWriter(masterKey, options).seal(content);

      // Parse directory to get ciphertext length.
      // Header + filename(6) + salt(32) + count(4) = 128 bytes.
      // Then directory entry: type(1) + hash(32) + ctLen(4) + iv(12) + tag(16).
      const dirStart = 122 + 6; // 128
      const ctLenOffset = dirStart + 1 + 32; // type + hash = 33 bytes in
      final ctLen = ByteData.sublistView(sealed, ctLenOffset, ctLenOffset + 4)
          .getUint32(0, Endian.big);

      // Ciphertext length should equal plaintext length (1000 bytes).
      expect(ctLen, equals(1000),
          reason: 'Ciphertext length in directory should match plaintext');
    });
  });
}
