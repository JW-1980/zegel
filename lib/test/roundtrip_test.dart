import 'dart:convert';
import 'dart:math';
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

/// Seals, verifies, and extracts content. Returns the extraction result.
ZegelResult _roundtrip(
  Uint8List content,
  Uint8List key, {
  ZegelOptions? options,
}) {
  options ??= ZegelOptions(
    contentType: 'application/octet-stream',
    filename: 'test.bin',
    salt: _zeroSalt(),
  );

  final fileBytes = ZegelWriter(key, options).seal(content);

  // verify (also extracts content)
  final result = const ZegelReader().verify(fileBytes, key);
  expect(result.valid, isTrue, reason: 'Verification failed during roundtrip');

  return result;
}

/// Generates random bytes using a seeded Random for reproducibility in tests.
Uint8List _randomBytes(int length, {int seed = 42}) {
  final rng = Random(seed);
  return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
}

void main() {
  group('Roundtrip tests', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    group('content sizes', () {
      test('small file: 13 bytes ("Hello, Zegel!")', () {
        final content = Uint8List.fromList(utf8.encode('Hello, Zegel!'));
        final result = _roundtrip(content, masterKey);
        expect(result.content, equals(content));
        expect(utf8.decode(result.content!), equals('Hello, Zegel!'));
      });

      test('exact block size: 65536 bytes', () {
        final content = Uint8List(65536);
        for (var i = 0; i < content.length; i++) {
          content[i] = i & 0xFF;
        }
        final result = _roundtrip(content, masterKey);
        expect(result.content, equals(content));
      });

      test('multi-block file: 3 blocks (65536 * 2 + 100 bytes)', () {
        final content = Uint8List(65536 * 2 + 100);
        for (var i = 0; i < content.length; i++) {
          content[i] = i & 0xFF;
        }
        final result = _roundtrip(content, masterKey);
        expect(result.content, equals(content));
        expect(result.content!.length, equals(65536 * 2 + 100));
      });

      test('large file: 256 KB', () {
        final content = _randomBytes(256 * 1024);
        final result = _roundtrip(content, masterKey);
        expect(result.content, equals(content));
      });

      test('empty content: 0 bytes', () {
        final content = Uint8List(0);
        final options = ZegelOptions(
          contentType: 'application/octet-stream',
          filename: 'empty.bin',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);
        final result = const ZegelReader().verify(fileBytes, masterKey);
        expect(result.valid, isTrue);
        expect(result.content, isNotNull);
        expect(result.content!.length, equals(0));
      });

      test('one byte content', () {
        final content = Uint8List.fromList([0x42]);
        final result = _roundtrip(content, masterKey);
        expect(result.content, equals(content));
      });

      test('just under block size: 65535 bytes', () {
        final content = Uint8List(65535);
        for (var i = 0; i < content.length; i++) {
          content[i] = i & 0xFF;
        }
        final result = _roundtrip(content, masterKey);
        expect(result.content, equals(content));
      });

      test('just over block size: 65537 bytes', () {
        final content = Uint8List(65537);
        for (var i = 0; i < content.length; i++) {
          content[i] = i & 0xFF;
        }
        final result = _roundtrip(content, masterKey);
        expect(result.content, equals(content));
      });
    });

    group('content types', () {
      test('binary content with all byte values', () {
        final content = Uint8List(256);
        for (var i = 0; i < 256; i++) {
          content[i] = i;
        }
        final result = _roundtrip(content, masterKey);
        expect(result.content, equals(content));
      });

      test('random binary content', () {
        final content = _randomBytes(1024, seed: 123);
        final result = _roundtrip(content, masterKey);
        expect(result.content, equals(content));
      });

      test('UTF-8 content with Unicode characters', () {
        const text =
            'Hello \u{1F600} World \u00e9\u00e8\u00ea '
            '\u4e16\u754c \u0410\u0411\u0412';
        final content = Uint8List.fromList(utf8.encode(text));
        final options = ZegelOptions(
          contentType: 'text/plain; charset=utf-8',
          filename: 'unicode.txt',
          salt: _zeroSalt(),
        );
        final result = _roundtrip(content, masterKey, options: options);
        expect(utf8.decode(result.content!), equals(text));
      });

      test('JSON content', () {
        final jsonObj = {
          'key': 'value',
          'number': 42,
          'array': [1, 2, 3],
        };
        final jsonStr = jsonEncode(jsonObj);
        final content = Uint8List.fromList(utf8.encode(jsonStr));
        final options = ZegelOptions(
          contentType: 'application/json',
          filename: 'data.json',
          salt: _zeroSalt(),
        );
        final result = _roundtrip(content, masterKey, options: options);
        expect(utf8.decode(result.content!), equals(jsonStr));
      });
    });

    group('with metadata', () {
      test('preserves simple metadata', () {
        final content = Uint8List.fromList(utf8.encode('content'));
        final metadata = {'sealed_by': 'test-suite', 'document_id': 42};
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'meta.txt',
          salt: _zeroSalt(),
          metadata: metadata,
        );
        final result = _roundtrip(content, masterKey, options: options);

        expect(result.content, equals(content));
        expect(result.metadata, isNotNull);
        expect(result.metadata!['sealed_by'], equals('test-suite'));
        expect(result.metadata!['document_id'], equals(42));
      });

      test('preserves complex metadata with nested objects', () {
        final content = Uint8List.fromList(utf8.encode('content'));
        final metadata = {
          'sealed_at': '2026-01-27T12:00:00Z',
          'sealed_by': 'roundtrip-test',
          'company_id': 1,
          'tags': ['important', 'confidential'],
          'nested': {'a': 1, 'b': 'two'},
        };
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'complex-meta.txt',
          salt: _zeroSalt(),
          metadata: metadata,
        );
        final result = _roundtrip(content, masterKey, options: options);

        expect(result.metadata!['sealed_at'], equals('2026-01-27T12:00:00Z'));
        expect(result.metadata!['tags'], equals(['important', 'confidential']));
        expect(result.metadata!['nested']['a'], equals(1));
      });

      test('metadata with Unicode values', () {
        final content = Uint8List.fromList(utf8.encode('content'));
        final metadata = {
          'author': 'Fran\u00e7ois M\u00fcller',
          'title': '\u6587\u66f8',
        };
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'unicode-meta.txt',
          salt: _zeroSalt(),
          metadata: metadata,
        );
        final result = _roundtrip(content, masterKey, options: options);

        expect(result.metadata!['author'], equals('Fran\u00e7ois M\u00fcller'));
        expect(result.metadata!['title'], equals('\u6587\u66f8'));
      });
    });

    group('with compression', () {
      test('compressible text content roundtrips correctly', () {
        // Highly compressible: repeated pattern
        final text = 'AAAA' * 10000;
        final content = Uint8List.fromList(utf8.encode(text));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'compressible.txt',
          salt: _zeroSalt(),
          compress: true,
        );
        final result = _roundtrip(content, masterKey, options: options);
        expect(result.content, equals(content));
      });

      test(
        'compressed file is smaller than uncompressed for compressible data',
        () {
          final text = 'AAAA' * 10000;
          final content = Uint8List.fromList(utf8.encode(text));

          final optionsCompressed = ZegelOptions(
            contentType: 'text/plain',
            filename: 'test.txt',
            salt: _zeroSalt(),
            compress: true,
          );
          final optionsUncompressed = ZegelOptions(
            contentType: 'text/plain',
            filename: 'test.txt',
            salt: _zeroSalt(),
            compress: false,
          );

          final compressed = ZegelWriter(
            masterKey,
            optionsCompressed,
          ).seal(content);
          final uncompressed = ZegelWriter(
            masterKey,
            optionsUncompressed,
          ).seal(content);

          expect(compressed.length, lessThan(uncompressed.length));
        },
      );

      test('binary content with compression roundtrips', () {
        final content = _randomBytes(8192);
        final options = ZegelOptions(
          contentType: 'application/octet-stream',
          filename: 'random.bin',
          salt: _zeroSalt(),
          compress: true,
        );
        final result = _roundtrip(content, masterKey, options: options);
        expect(result.content, equals(content));
      });
    });

    group('with public metadata', () {
      test('public metadata survives roundtrip', () {
        final content = Uint8List.fromList(utf8.encode('content'));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'public-meta.txt',
          salt: _zeroSalt(),
          publicMetadata: {'classification': 'public', 'file_size': 7},
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        // Public metadata should be visible via inspect (no key)
        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.publicMetadata, isNotNull);
        expect(inspection.publicMetadata!['classification'], equals('public'));

        // Full extraction should also work
        final result = const ZegelReader().verify(fileBytes, masterKey);
        expect(result.valid, isTrue);
        expect(result.content, equals(content));
      });
    });

    group('with expiration', () {
      test('future expiration: file can be extracted', () {
        final content = Uint8List.fromList(utf8.encode('not expired'));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'expires-later.txt',
          salt: _zeroSalt(),
          expiration: DateTime.now().add(const Duration(days: 365)),
        );
        final result = _roundtrip(content, masterKey, options: options);
        expect(result.content, equals(content));
      });

      test('past expiration: extraction is refused', () {
        final content = Uint8List.fromList(utf8.encode('expired'));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'expired.txt',
          salt: _zeroSalt(),
          expiration: DateTime.now().subtract(const Duration(days: 1)),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        // verify() throws ZegelExpiredException for expired files
        expect(
          () => const ZegelReader().verify(fileBytes, masterKey),
          throwsA(isA<ZegelExpiredException>()),
        );
      });
    });

    group('with key commitment', () {
      test('key commitment roundtrip succeeds', () {
        final content = Uint8List.fromList(utf8.encode('committed'));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'committed.txt',
          salt: _zeroSalt(),
          enableKeyCommitment: true,
        );
        final result = _roundtrip(content, masterKey, options: options);
        expect(result.content, equals(content));
      });

      test('key commitment flag is set in file', () {
        final content = Uint8List.fromList(utf8.encode('committed'));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'committed.txt',
          salt: _zeroSalt(),
          enableKeyCommitment: true,
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.flags & ZegelFormat.flagHasKeyCommitment, isNonZero);
      });
    });

    group('filenames', () {
      test('short filename', () {
        final content = Uint8List.fromList([1, 2, 3]);
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'a.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);
        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.filename, equals('a.txt'));
      });

      test('long filename (255 bytes)', () {
        // Create a filename that is exactly 255 bytes in UTF-8
        final longName = '${'a' * 251}.txt'; // 251 + 4 = 255
        final content = Uint8List.fromList([1, 2, 3]);
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: longName,
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);
        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.filename, equals(longName));
      });

      test('Unicode filename', () {
        final content = Uint8List.fromList([1, 2, 3]);
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'rapport\u00e9_2026.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);
        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.filename, equals('rapport\u00e9_2026.txt'));
      });

      test('filename with spaces and special characters', () {
        final content = Uint8List.fromList([1, 2, 3]);
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'my document (final) [v2].txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);
        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.filename, equals('my document (final) [v2].txt'));
      });
    });

    group('various content-types', () {
      test('text/plain', () {
        final content = Uint8List.fromList(utf8.encode('plain text'));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'test.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);
        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.contentType, equals('text/plain'));
      });

      test('application/pdf', () {
        final content = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]); // %PDF
        final options = ZegelOptions(
          contentType: 'application/pdf',
          filename: 'doc.pdf',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);
        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.contentType, equals('application/pdf'));
      });

      test('image/png', () {
        final content = _randomBytes(100);
        final options = ZegelOptions(
          contentType: 'image/png',
          filename: 'image.png',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);
        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.contentType, equals('image/png'));
      });

      test('application/octet-stream', () {
        final content = _randomBytes(100);
        final options = ZegelOptions(
          contentType: 'application/octet-stream',
          filename: 'data.bin',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);
        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.contentType, equals('application/octet-stream'));
      });

      test('content-type with parameters', () {
        final content = Uint8List.fromList(utf8.encode('text'));
        final options = ZegelOptions(
          contentType: 'text/plain; charset=utf-8',
          filename: 'test.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);
        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.contentType, equals('text/plain; charset=utf-8'));
      });
    });

    group('combined options', () {
      test('metadata + compression', () {
        final content = Uint8List.fromList(utf8.encode('AAAA' * 1000));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'combo.txt',
          salt: _zeroSalt(),
          metadata: {'sealed_by': 'test'},
          compress: true,
        );
        final result = _roundtrip(content, masterKey, options: options);
        expect(result.content, equals(content));
        expect(result.metadata!['sealed_by'], equals('test'));
      });

      test('metadata + key commitment + public metadata', () {
        final content = Uint8List.fromList(utf8.encode('full featured'));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'full.txt',
          salt: _zeroSalt(),
          metadata: {'sealed_by': 'test', 'document_id': 1},
          enableKeyCommitment: true,
          publicMetadata: {'classification': 'internal'},
        );
        final result = _roundtrip(content, masterKey, options: options);
        expect(result.content, equals(content));
        expect(result.metadata!['sealed_by'], equals('test'));
      });

      test('compression + expiration + key commitment', () {
        final content = Uint8List.fromList(utf8.encode('BBBB' * 500));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'multi-option.txt',
          salt: _zeroSalt(),
          compress: true,
          expiration: DateTime.now().add(const Duration(days: 30)),
          enableKeyCommitment: true,
        );
        final result = _roundtrip(content, masterKey, options: options);
        expect(result.content, equals(content));
      });
    });

    group('determinism', () {
      test('same inputs produce same output with fixed salt', () {
        final content = Uint8List.fromList(utf8.encode('deterministic'));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'det.txt',
          salt: _zeroSalt(),
        );

        // Note: IV is random, so files may differ unless IV is also controlled.
        // This test verifies the structural aspects are deterministic.
        final file1 = ZegelWriter(masterKey, options).seal(content);
        final file2 = ZegelWriter(masterKey, options).seal(content);

        // Magic, version, flags, content-type, filename, salt, block count
        // should all be identical
        expect(file1.sublist(0, 10), equals(file2.sublist(0, 10)));
        // Content-type
        expect(file1.sublist(20, 84), equals(file2.sublist(20, 84)));
      });
    });
  });
}
