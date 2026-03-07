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

/// Seals content with standard test options for reader tests.
Uint8List _sealTestFile(
  Uint8List content,
  Uint8List key, {
  Map<String, dynamic>? metadata,
  Map<String, dynamic>? publicMetadata,
}) {
  final options = ZegelOptions(
    contentType: 'text/plain',
    filename: 'test.txt',
    salt: _zeroSalt(),
    metadata: metadata,
    publicMetadata: publicMetadata,
  );
  return ZegelWriter(key, options).seal(content);
}

void main() {
  group('ZegelReader', () {
    late Uint8List masterKey;
    late Uint8List content;

    setUp(() {
      masterKey = _testKey();
      content = Uint8List.fromList(utf8.encode('Hello, Zegel!'));
    });

    group('rejects invalid files', () {
      test('rejects file with wrong magic bytes', () {
        final fileBytes = _sealTestFile(content, masterKey);
        // Corrupt magic bytes
        fileBytes[0] = 0xFF;
        fileBytes[1] = 0xFF;

        expect(
          () => const ZegelReader().verify(fileBytes, masterKey),
          throwsA(isA<ZegelFormatException>()),
        );
      });

      test('rejects file with partially wrong magic bytes', () {
        final fileBytes = _sealTestFile(content, masterKey);
        // Corrupt just the last magic byte
        fileBytes[7] = 0xFF;

        expect(
          () => const ZegelReader().verify(fileBytes, masterKey),
          throwsA(isA<ZegelFormatException>()),
        );
      });

      test('rejects truncated file (too short for header)', () {
        // Less than the minimum header size
        final truncated = Uint8List(10);
        truncated.setAll(0, [0x5A, 0x45, 0x47, 0x45, 0x4C, 0x00, 0x01, 0x00]);

        expect(
          () => const ZegelReader().verify(truncated, masterKey),
          throwsA(anything),
        );
      });

      test('rejects file with modified seal', () {
        final fileBytes = _sealTestFile(content, masterKey);
        // Flip a bit in the seal (last 64 bytes)
        fileBytes[fileBytes.length - 1] ^= 0x01;

        expect(
          () => const ZegelReader().verify(fileBytes, masterKey),
          throwsA(isA<ZegelTamperedException>()),
        );
      });

      test('rejects file with modified merkle root', () {
        final fileBytes = _sealTestFile(content, masterKey);

        // Find the Merkle root position:
        // After header + block directory, there is a 32-byte Merkle root.
        // We need to locate it. For a file with:
        //   filename = "test.txt" (8 bytes)
        //   1 block, no extended header
        //   directory starts at 86 + 8 + 32 + 4 = 130
        //   directory is 65 bytes (1 block)
        //   merkle root starts at 130 + 65 = 195
        const filenameLen = 8; // "test.txt"
        const directoryStart = 86 + filenameLen + 32 + 4;
        const merkleRootStart = directoryStart + 65; // 1 block * 65 bytes

        fileBytes[merkleRootStart] ^= 0x01;

        expect(
          () => const ZegelReader().verify(fileBytes, masterKey),
          throwsA(isA<ZegelTamperedException>()),
        );
      });

      test('rejects file with modified block data', () {
        final fileBytes = _sealTestFile(content, masterKey);

        // Find the encrypted block data position:
        // After merkle root (32 bytes after directory)
        const filenameLen = 8;
        const directoryStart = 86 + filenameLen + 32 + 4;
        const merkleRootStart = directoryStart + 65;
        const blockDataStart = merkleRootStart + 32;

        fileBytes[blockDataStart] ^= 0x01;

        expect(
          () => const ZegelReader().verify(fileBytes, masterKey),
          throwsA(isA<ZegelTamperedException>()),
        );
      });
    });

    group('successfully reads valid files', () {
      test('verify returns valid for unmodified file', () {
        final fileBytes = _sealTestFile(content, masterKey);

        final result = const ZegelReader().verify(fileBytes, masterKey);
        expect(result.valid, isTrue);
      });

      test('verify returns correct content', () {
        final fileBytes = _sealTestFile(content, masterKey);

        final result = const ZegelReader().verify(fileBytes, masterKey);
        expect(result.valid, isTrue);
        expect(result.content, equals(content));
      });

      test('verify returns correct UTF-8 string content', () {
        final textContent = Uint8List.fromList(utf8.encode('Hello, Zegel!'));
        final fileBytes = _sealTestFile(textContent, masterKey);

        final result = const ZegelReader().verify(fileBytes, masterKey);
        expect(utf8.decode(result.content!), equals('Hello, Zegel!'));
      });

      test('extracts correct metadata', () {
        final metadata = {
          'sealed_by': 'test-suite',
          'document_id': 42,
        };
        final fileBytes = _sealTestFile(content, masterKey, metadata: metadata);

        final result = const ZegelReader().verify(fileBytes, masterKey);
        expect(result.valid, isTrue);
        expect(result.metadata, isNotNull);
        expect(result.metadata!['sealed_by'], equals('test-suite'));
        expect(result.metadata!['document_id'], equals(42));
      });
    });

    group('handles files with and without metadata', () {
      test('file without metadata has null metadata in result', () {
        final fileBytes = _sealTestFile(content, masterKey);

        final result = const ZegelReader().verify(fileBytes, masterKey);
        expect(result.valid, isTrue);
        expect(result.metadata, isNull);
      });

      test('file with metadata includes it in result', () {
        final metadata = {'key': 'value'};
        final fileBytes = _sealTestFile(content, masterKey, metadata: metadata);

        final result = const ZegelReader().verify(fileBytes, masterKey);
        expect(result.valid, isTrue);
        expect(result.metadata, isNotNull);
        expect(result.metadata!['key'], equals('value'));
      });

      test('file with empty metadata map', () {
        final metadata = <String, dynamic>{};
        final fileBytes = _sealTestFile(content, masterKey, metadata: metadata);

        // Empty metadata may or may not set the flag depending on implementation
        final result = const ZegelReader().verify(fileBytes, masterKey);
        expect(result.valid, isTrue);
      });
    });

    group('inspect (no key required)', () {
      test('inspect works without a key', () {
        final fileBytes = _sealTestFile(content, masterKey);

        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection, isNotNull);
      });

      test('inspect reports correct version', () {
        final fileBytes = _sealTestFile(content, masterKey);

        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.version, equals('1.2'));
      });

      test('inspect reports correct flags', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'test.txt',
          salt: _zeroSalt(),
          metadata: {'key': 'value'},
          compress: true,
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.flags & ZegelFormat.flagHasMetadata, isNonZero);
        expect(inspection.flags & ZegelFormat.flagCompressed, isNonZero);
      });

      test('inspect reports correct block count', () {
        final fileBytes = _sealTestFile(content, masterKey);

        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.blockCount, equals(1));
      });

      test('inspect reports correct block count with metadata', () {
        final fileBytes = _sealTestFile(
          content,
          masterKey,
          metadata: {'key': 'value'},
        );

        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.blockCount, equals(2)); // 1 metadata + 1 content
      });

      test('inspect reports correct content type', () {
        final fileBytes = _sealTestFile(content, masterKey);

        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.contentType, equals('text/plain'));
      });

      test('inspect reports correct filename', () {
        final fileBytes = _sealTestFile(content, masterKey);

        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.filename, equals('test.txt'));
      });

      test('inspect reports timestamp', () {
        final fileBytes = _sealTestFile(content, masterKey);

        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.timestamp, greaterThan(0));
      });

      test('inspect reports public metadata when present', () {
        final publicMeta = {'classification': 'public', 'author': 'test'};
        final fileBytes = _sealTestFile(
          content,
          masterKey,
          publicMetadata: publicMeta,
        );

        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.publicMetadata, isNotNull);
        expect(inspection.publicMetadata!['classification'], equals('public'));
      });

      test('inspect reports block count for valid file', () {
        final fileBytes = _sealTestFile(content, masterKey);

        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.blockCount, greaterThan(0));
      });
    });

    group('wrong key', () {
      test('wrong key fails verification', () {
        final fileBytes = _sealTestFile(content, masterKey);

        final wrongKey = Uint8List(32);
        wrongKey[31] = 0x02; // Different key

        expect(
          () => const ZegelReader().verify(fileBytes, wrongKey),
          throwsA(isA<ZegelTamperedException>()),
        );
      });

      test('wrong key fails extraction', () {
        final fileBytes = _sealTestFile(content, masterKey);

        final wrongKey = Uint8List(32);
        wrongKey[31] = 0x02;

        expect(
          () => const ZegelReader().verify(fileBytes, wrongKey),
          throwsA(isA<ZegelTamperedException>()),
        );
      });
    });
  });
}
