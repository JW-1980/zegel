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

void main() {
  group('ZegelWriter', () {
    late Uint8List masterKey;
    late Uint8List content;

    setUp(() {
      masterKey = _testKey();
      content = Uint8List.fromList(utf8.encode('Hello, Zegel!'));
    });

    group('magic bytes', () {
      test('file starts with correct magic bytes at offset 0', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final magic = fileBytes.sublist(0, 8);
        expect(magic, equals(ZegelFormat.magic));
      });

      test('first 5 bytes spell ZEGEL in ASCII', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);
        expect(String.fromCharCodes(fileBytes.sublist(0, 5)), equals('ZEGEL'));
      });
    });

    group('version bytes', () {
      test('version major at offset 8 is 1', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);
        expect(fileBytes[8], equals(1));
      });

      test('version minor at offset 9 is 2', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);
        expect(fileBytes[9], equals(4));
      });
    });

    group('flags', () {
      test('no options produce flags 0x0000', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final flagsValue = ByteData.sublistView(
          fileBytes,
          10,
          12,
        ).getUint16(0, Endian.big);
        expect(flagsValue, equals(0x0000));
      });

      test('metadata option sets HAS_METADATA flag', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
          metadata: {'key': 'value'},
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final flagsValue = ByteData.sublistView(
          fileBytes,
          10,
          12,
        ).getUint16(0, Endian.big);
        expect(flagsValue & ZegelFormat.flagHasMetadata, isNonZero);
      });

      test('compress option sets COMPRESSED flag', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
          compress: true,
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final flagsValue = ByteData.sublistView(
          fileBytes,
          10,
          12,
        ).getUint16(0, Endian.big);
        expect(flagsValue & ZegelFormat.flagCompressed, isNonZero);
      });

      test('key commitment option sets HAS_KEY_COMMITMENT flag', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
          enableKeyCommitment: true,
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final flagsValue = ByteData.sublistView(
          fileBytes,
          10,
          12,
        ).getUint16(0, Endian.big);
        expect(flagsValue & ZegelFormat.flagHasKeyCommitment, isNonZero);
      });

      test('expiration option sets HAS_EXPIRATION flag', () {
        final futureDate = DateTime.now().add(const Duration(days: 365));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
          expiration: futureDate,
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final flagsValue = ByteData.sublistView(
          fileBytes,
          10,
          12,
        ).getUint16(0, Endian.big);
        expect(flagsValue & ZegelFormat.flagHasExpiration, isNonZero);
      });

      test('public metadata option sets HAS_PUBLIC_METADATA flag', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
          publicMetadata: {'classification': 'public'},
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final flagsValue = ByteData.sublistView(
          fileBytes,
          10,
          12,
        ).getUint16(0, Endian.big);
        expect(flagsValue & ZegelFormat.flagHasPublicMetadata, isNonZero);
      });

      test('multiple options set multiple flags', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
          metadata: {'key': 'value'},
          compress: true,
          enableKeyCommitment: true,
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final flagsValue = ByteData.sublistView(
          fileBytes,
          10,
          12,
        ).getUint16(0, Endian.big);
        expect(flagsValue & ZegelFormat.flagHasMetadata, isNonZero);
        expect(flagsValue & ZegelFormat.flagCompressed, isNonZero);
        expect(flagsValue & ZegelFormat.flagHasKeyCommitment, isNonZero);
      });
    });

    group('timestamp', () {
      test('timestamp at offset 12-19 is valid Unix epoch', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final fileBytes = ZegelWriter(masterKey, options).seal(content);
        final after = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        final timestamp = ByteData.sublistView(
          fileBytes,
          12,
          20,
        ).getUint64(0, Endian.big);

        expect(timestamp, greaterThanOrEqualTo(before));
        expect(timestamp, lessThanOrEqualTo(after));
      });

      test('timestamp is non-zero', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final timestamp = ByteData.sublistView(
          fileBytes,
          12,
          20,
        ).getUint64(0, Endian.big);
        expect(timestamp, greaterThan(0));
      });
    });

    group('content-type', () {
      test('content-type is null-padded to 64 bytes starting at offset 20', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final contentTypeBytes = fileBytes.sublist(20, 84);
        expect(contentTypeBytes.length, equals(64));

        // First 10 bytes should be "text/plain"
        final textBytes = utf8.encode('text/plain');
        expect(
          contentTypeBytes.sublist(0, textBytes.length),
          equals(textBytes),
        );

        // Remaining bytes should be null (0x00)
        for (var i = textBytes.length; i < 64; i++) {
          expect(
            contentTypeBytes[i],
            equals(0),
            reason: 'Byte at position $i should be null padding',
          );
        }
      });

      test('empty content-type is all zeros', () {
        final options = ZegelOptions(
          contentType: '',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final contentTypeBytes = fileBytes.sublist(20, 84);
        for (var i = 0; i < 64; i++) {
          expect(contentTypeBytes[i], equals(0));
        }
      });
    });

    group('filename', () {
      test('filename length at offset 84-85 matches UTF-8 byte length', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final filenameLen = ByteData.sublistView(
          fileBytes,
          84,
          86,
        ).getUint16(0, Endian.big);
        expect(filenameLen, equals(utf8.encode('hello.txt').length));
      });

      test('filename bytes follow filename length field', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final filenameLen = ByteData.sublistView(
          fileBytes,
          84,
          86,
        ).getUint16(0, Endian.big);
        final filenameBytes = fileBytes.sublist(86, 86 + filenameLen);
        expect(utf8.decode(filenameBytes), equals('hello.txt'));
      });

      test('filename with Unicode characters encodes correctly', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'rapport\u00e9.txt', // rapporté.txt
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final filenameLen = ByteData.sublistView(
          fileBytes,
          84,
          86,
        ).getUint16(0, Endian.big);
        final filenameBytes = fileBytes.sublist(86, 86 + filenameLen);
        expect(utf8.decode(filenameBytes), equals('rapport\u00e9.txt'));
      });
    });

    group('salt', () {
      test('salt is 32 bytes after filename', () {
        const filename = 'hello.txt';
        final filenameLen = utf8.encode(filename).length;
        final saltOffset = 86 + filenameLen;

        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: filename,
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final salt = fileBytes.sublist(saltOffset, saltOffset + 32);
        expect(salt.length, equals(32));
        // With zero salt, all bytes should be 0
        expect(salt, equals(_zeroSalt()));
      });

      test('random salt is generated when not provided', () {
        const options1 = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
        );
        const options2 = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
        );
        final file1 = ZegelWriter(masterKey, options1).seal(content);
        final file2 = ZegelWriter(masterKey, options2).seal(content);

        const filename = 'hello.txt';
        final filenameLen = utf8.encode(filename).length;
        final saltOffset = 86 + filenameLen;

        final salt1 = file1.sublist(saltOffset, saltOffset + 32);
        final salt2 = file2.sublist(saltOffset, saltOffset + 32);

        // Two random salts should (almost certainly) differ
        expect(salt1, isNot(equals(salt2)));
      });
    });

    group('block count', () {
      test('block count is 1 for small content (< 64KB)', () {
        const filename = 'hello.txt';
        final filenameLen = utf8.encode(filename).length;
        final blockCountOffset = 86 + filenameLen + 32;

        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: filename,
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final blockCount = ByteData.sublistView(
          fileBytes,
          blockCountOffset,
          blockCountOffset + 4,
        ).getUint32(0, Endian.big);
        expect(blockCount, equals(1));
      });

      test('block count is 2 for exactly 64KB + 1 byte content', () {
        final largeContent = Uint8List(65537); // 64KB + 1
        const filename = 'large.bin';
        final filenameLen = utf8.encode(filename).length;
        final blockCountOffset = 86 + filenameLen + 32;

        final options = ZegelOptions(
          contentType: 'application/octet-stream',
          filename: filename,
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(largeContent);

        final blockCount = ByteData.sublistView(
          fileBytes,
          blockCountOffset,
          blockCountOffset + 4,
        ).getUint32(0, Endian.big);
        expect(blockCount, equals(2));
      });

      test('block count is 1 for exactly 64KB content', () {
        final exactContent = Uint8List(65536); // exactly 64KB
        const filename = 'exact.bin';
        final filenameLen = utf8.encode(filename).length;
        final blockCountOffset = 86 + filenameLen + 32;

        final options = ZegelOptions(
          contentType: 'application/octet-stream',
          filename: filename,
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(exactContent);

        final blockCount = ByteData.sublistView(
          fileBytes,
          blockCountOffset,
          blockCountOffset + 4,
        ).getUint32(0, Endian.big);
        expect(blockCount, equals(1));
      });

      test('block count includes metadata block when metadata is present', () {
        const filename = 'hello.txt';
        final filenameLen = utf8.encode(filename).length;
        final blockCountOffset = 86 + filenameLen + 32;

        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: filename,
          salt: _zeroSalt(),
          metadata: {'sealed_by': 'test'},
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final blockCount = ByteData.sublistView(
          fileBytes,
          blockCountOffset,
          blockCountOffset + 4,
        ).getUint32(0, Endian.big);
        // 1 metadata block + 1 content block = 2
        expect(blockCount, equals(2));
      });

      test('multiple content blocks for large file', () {
        // 3 blocks of content: 65536 + 65536 + remainder
        final largeContent = Uint8List(65536 * 2 + 100);
        const filename = 'big.bin';
        final filenameLen = utf8.encode(filename).length;
        final blockCountOffset = 86 + filenameLen + 32;

        final options = ZegelOptions(
          contentType: 'application/octet-stream',
          filename: filename,
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(largeContent);

        final blockCount = ByteData.sublistView(
          fileBytes,
          blockCountOffset,
          blockCountOffset + 4,
        ).getUint32(0, Endian.big);
        expect(blockCount, equals(3));
      });
    });

    group('metadata block', () {
      test('metadata block is first block when metadata present', () {
        const filename = 'hello.txt';
        final filenameLen = utf8.encode(filename).length;
        final blockCountOffset = 86 + filenameLen + 32;
        // Block directory starts after block count (4 bytes)
        final directoryOffset = blockCountOffset + 4;

        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: filename,
          salt: _zeroSalt(),
          metadata: {'sealed_by': 'test'},
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        // First byte of block directory is the block type
        final firstBlockType = fileBytes[directoryOffset];
        expect(firstBlockType, equals(ZegelFormat.blockMetadata));
      });

      test('content block type is CONTENT when no metadata', () {
        const filename = 'hello.txt';
        final filenameLen = utf8.encode(filename).length;
        final blockCountOffset = 86 + filenameLen + 32;
        final directoryOffset = blockCountOffset + 4;

        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: filename,
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final firstBlockType = fileBytes[directoryOffset];
        expect(firstBlockType, equals(ZegelFormat.blockContent));
      });
    });

    group('compression flag', () {
      test('COMPRESSED flag is set when compress=true', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
          compress: true,
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final flagsValue = ByteData.sublistView(
          fileBytes,
          10,
          12,
        ).getUint16(0, Endian.big);
        expect(flagsValue & ZegelFormat.flagCompressed, isNonZero);
      });

      test('COMPRESSED flag is not set when compress=false', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
          compress: false,
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final flagsValue = ByteData.sublistView(
          fileBytes,
          10,
          12,
        ).getUint16(0, Endian.big);
        expect(flagsValue & ZegelFormat.flagCompressed, equals(0));
      });
    });

    group('master seal', () {
      test('file ends with 64-byte master seal', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        expect(fileBytes.length, greaterThan(64));
        final seal = fileBytes.sublist(fileBytes.length - 64);
        expect(seal.length, equals(64));
        // Seal should not be all zeros (HMAC-SHA512 of real data)
        expect(seal, isNot(equals(Uint8List(64))));
      });
    });

    group('roundtrip', () {
      test('generated file can be read back successfully', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final result = const ZegelReader().verify(fileBytes, masterKey);
        expect(result.valid, isTrue);
        expect(result.content, equals(content));
      });
    });

    group('output size sanity checks', () {
      test('output is larger than input due to overhead', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        // Minimum overhead: 8 (magic) + 2 (version) + 2 (flags) + 8 (timestamp)
        // + 64 (content-type) + 2 (filename-len) + N (filename) + 32 (salt)
        // + 4 (block-count) + 65 (directory) + 32 (merkle root)
        // + ciphertext + 64 (seal) = ~283 + ciphertext
        expect(fileBytes.length, greaterThan(content.length));
      });

      test('master key must be 32 bytes', () {
        final shortKey = Uint8List(16);
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );

        expect(
          () => ZegelWriter(shortKey, options).seal(content),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  });
}
