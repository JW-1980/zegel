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
  group('MediaMetadata', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    group('extractBasicMetadata', () {
      test('returns correct structure', () {
        final content = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
        final metadata =
            MediaMetadata.extractBasicMetadata(content, 'test.bin');

        expect(metadata, isA<Map<String, dynamic>>());
        expect(metadata.containsKey('filename'), isTrue);
        expect(metadata.containsKey('file_size'), isTrue);
        expect(metadata.containsKey('content_hash'), isTrue);
        expect(metadata.containsKey('detected_type'), isTrue);
      });

      test('includes correct filename', () {
        final content = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
        final metadata =
            MediaMetadata.extractBasicMetadata(content, 'document.pdf');

        expect(metadata['filename'], equals('document.pdf'));
      });

      test('includes correct file size', () {
        final content = Uint8List.fromList(List.generate(100, (i) => i));
        final metadata =
            MediaMetadata.extractBasicMetadata(content, 'data.bin');

        expect(metadata['file_size'], equals(100));
      });

      test('includes content hash as hex string', () {
        final content = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
        final metadata =
            MediaMetadata.extractBasicMetadata(content, 'test.bin');

        final hash = metadata['content_hash'] as String;
        expect(hash.length, equals(64),
            reason: 'SHA-256 hash should be 64 hex characters');
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(hash), isTrue,
            reason: 'Hash should be lowercase hex');
      });

      test('detects JPEG content type', () {
        // JPEG magic bytes: FF D8 FF
        final content =
            Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
        final metadata =
            MediaMetadata.extractBasicMetadata(content, 'photo.jpg');

        expect(metadata['detected_type'], equals('image/jpeg'));
      });

      test('detects PNG content type', () {
        // PNG magic bytes: 89 50 4E 47
        final content =
            Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]);
        final metadata =
            MediaMetadata.extractBasicMetadata(content, 'image.png');

        expect(metadata['detected_type'], equals('image/png'));
      });

      test('detects PDF content type', () {
        // PDF magic bytes: 25 50 44 46 (%PDF)
        final content =
            Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31]);
        final metadata =
            MediaMetadata.extractBasicMetadata(content, 'report.pdf');

        expect(metadata['detected_type'], equals('application/pdf'));
      });

      test('detects ZIP content type', () {
        // ZIP magic bytes: 50 4B 03 04
        final content =
            Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00]);
        final metadata =
            MediaMetadata.extractBasicMetadata(content, 'archive.zip');

        expect(metadata['detected_type'], equals('application/zip'));
      });

      test('detects GIF content type', () {
        // GIF magic bytes: 47 49 46 (GIF)
        final content =
            Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]);
        final metadata =
            MediaMetadata.extractBasicMetadata(content, 'anim.gif');

        expect(metadata['detected_type'], equals('image/gif'));
      });

      test('returns octet-stream for unknown content', () {
        final content = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
        final metadata =
            MediaMetadata.extractBasicMetadata(content, 'mystery.dat');

        expect(metadata['detected_type'], equals('application/octet-stream'));
      });

      test('handles very small content', () {
        // Content smaller than 4 bytes
        final content = Uint8List.fromList([0x01]);
        final metadata =
            MediaMetadata.extractBasicMetadata(content, 'tiny.bin');

        expect(metadata['file_size'], equals(1));
        expect(metadata['detected_type'], equals('unknown'));
      });
    });

    group('stripMetadata', () {
      test('returns content with same length for basic types', () {
        final content =
            Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
        final stripped =
            MediaMetadata.stripMetadata(content, 'image/jpeg');

        expect(stripped.length, equals(content.length));
      });

      test('populates strippedFields list', () {
        final content =
            Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
        final strippedFields = <String>[];
        MediaMetadata.stripMetadata(
          content,
          'image/jpeg',
          strippedFields: strippedFields,
        );

        expect(strippedFields, isNotEmpty,
            reason: 'Should report fields that would be stripped');
        expect(strippedFields, contains('GPS coordinates'));
        expect(strippedFields, contains('Camera make/model'));
      });
    });

    group('createProvenanceEntry', () {
      test('returns correct structure', () {
        final entry = MediaMetadata.createProvenanceEntry(
          'photo.jpg',
          'captured',
          'camera-device-001',
        );

        expect(entry, isA<Map<String, dynamic>>());
        expect(entry['filename'], equals('photo.jpg'));
        expect(entry['action'], equals('captured'));
        expect(entry['actor'], equals('camera-device-001'));
        expect(entry.containsKey('timestamp'), isTrue);
      });

      test('includes timestamp as epoch seconds', () {
        final beforeEpoch =
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

        final entry = MediaMetadata.createProvenanceEntry(
          'doc.pdf',
          'scanned',
          'scanner-01',
        );

        final afterEpoch =
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

        final timestamp = entry['timestamp'] as int;
        expect(timestamp, greaterThanOrEqualTo(beforeEpoch));
        expect(timestamp, lessThanOrEqualTo(afterEpoch));
      });

      test('includes additional fields when provided', () {
        final entry = MediaMetadata.createProvenanceEntry(
          'evidence.jpg',
          'captured',
          'bodycam-42',
          additionalFields: {
            'location': 'Building A',
            'case_number': 'C-2026-001',
          },
        );

        expect(entry['location'], equals('Building A'));
        expect(entry['case_number'], equals('C-2026-001'));
      });
    });

    group('metadata in sealed files', () {
      test('basic metadata survives seal/extract roundtrip', () {
        final content =
            Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);

        // Extract basic metadata
        final basicMeta =
            MediaMetadata.extractBasicMetadata(content, 'photo.jpg');

        // Seal with metadata
        final options = ZegelOptions(
          contentType: 'image/jpeg',
          filename: 'photo.jpg',
          salt: _zeroSalt(),
          metadata: basicMeta,
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        // Verify and extract
        final result = const ZegelReader().verify(fileBytes, masterKey);
        expect(result.valid, isTrue);
        expect(result.metadata, isNotNull);
        expect(result.metadata!['filename'], equals('photo.jpg'));
        expect(result.metadata!['file_size'], equals(6));
        expect(result.metadata!['detected_type'], equals('image/jpeg'));
      });

      test('file with non-media metadata round-trips correctly', () {
        final content = Uint8List.fromList(utf8.encode('Text document'));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'doc.txt',
          salt: _zeroSalt(),
          metadata: {'author': 'Alice', 'version': 1},
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final result = const ZegelReader().verify(fileBytes, masterKey);
        expect(result.valid, isTrue);
        expect(result.metadata, isNotNull);
        expect(result.metadata!['author'], equals('Alice'));
        expect(result.metadata!['version'], equals(1));
      });

      test('sealed file without metadata returns null metadata', () {
        final content = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
        final options = ZegelOptions(
          contentType: 'application/x-unknown-format',
          filename: 'mystery.dat',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final result = const ZegelReader().verify(fileBytes, masterKey);
        expect(result.valid, isTrue);
        expect(result.metadata, isNull,
            reason: 'File sealed without metadata should have null metadata');
      });
    });
  });
}
