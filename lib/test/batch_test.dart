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

/// Creates a sealed .zgl file with the given [label] baked into the content.
Uint8List _createSealedFile(Uint8List key, String label) {
  final content = Uint8List.fromList(utf8.encode('Content for $label'));
  final options = ZegelOptions(
    contentType: 'text/plain',
    filename: '$label.txt',
    salt: _zeroSalt(),
  );
  return ZegelWriter(key, options).seal(content);
}

/// Tampers with a sealed file by flipping a bit in the ciphertext area.
Uint8List _tamperFile(Uint8List fileBytes) {
  final tampered = Uint8List.fromList(fileBytes);
  // Flip a bit in the ciphertext region (well past the header).
  final offset = tampered.length - 100;
  tampered[offset] ^= 0x01;
  return tampered;
}

void main() {
  group('BatchOperations', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    group('batchVerify', () {
      test('verifies multiple valid files', () {
        final files = <MapEntry<String, Uint8List>>[];
        for (var i = 0; i < 5; i++) {
          final fileBytes = _createSealedFile(masterKey, 'file_$i');
          files.add(MapEntry('file_$i', fileBytes));
        }

        final results = BatchOperations.batchVerify(files, masterKey);

        expect(results.length, equals(5));
        for (final result in results) {
          expect(
            result['success'],
            isTrue,
            reason: '${result['name']} should verify successfully',
          );
        }
      });

      test('detects tampered file in batch', () {
        final files = <MapEntry<String, Uint8List>>[];
        for (var i = 0; i < 5; i++) {
          var fileBytes = _createSealedFile(masterKey, 'file_$i');
          // Tamper with file at index 2
          if (i == 2) {
            fileBytes = _tamperFile(fileBytes);
          }
          files.add(MapEntry('file_$i', fileBytes));
        }

        final results = BatchOperations.batchVerify(files, masterKey);

        expect(results.length, equals(5));
        // Files 0, 1, 3, 4 should be valid
        expect(results[0]['success'], isTrue);
        expect(results[1]['success'], isTrue);
        // File 2 should be invalid
        expect(
          results[2]['success'],
          isFalse,
          reason: 'Tampered file should fail verification',
        );
        expect(results[3]['success'], isTrue);
        expect(results[4]['success'], isTrue);
      });

      test('stops on first failure when configured', () {
        final files = <MapEntry<String, Uint8List>>[];
        for (var i = 0; i < 5; i++) {
          var fileBytes = _createSealedFile(masterKey, 'file_$i');
          // Tamper with file at index 1
          if (i == 1) {
            fileBytes = _tamperFile(fileBytes);
          }
          files.add(MapEntry('file_$i', fileBytes));
        }

        final results = BatchOperations.batchVerify(
          files,
          masterKey,
          stopOnFirstFailure: true,
        );

        // Should stop after file_1 fails, so only 2 results
        expect(results.length, equals(2));
        expect(results[0]['success'], isTrue);
        expect(results[1]['success'], isFalse);
      });

      test('returns elapsed time per file', () {
        final files = <MapEntry<String, Uint8List>>[];
        for (var i = 0; i < 3; i++) {
          final fileBytes = _createSealedFile(masterKey, 'file_$i');
          files.add(MapEntry('file_$i', fileBytes));
        }

        final results = BatchOperations.batchVerify(files, masterKey);

        for (final result in results) {
          expect(
            result['duration_ms'],
            isNotNull,
            reason: 'Each result should include elapsed time',
          );
          expect(result['duration_ms'], isA<int>());
          // Duration should be non-negative
          expect(result['duration_ms'] as int, greaterThanOrEqualTo(0));
        }
      });

      test('handles empty input list', () {
        final results = BatchOperations.batchVerify(
          <MapEntry<String, Uint8List>>[],
          masterKey,
        );

        expect(
          results,
          isEmpty,
          reason: 'Empty input should return empty results',
        );
      });

      test('preserves names in results', () {
        final files = <MapEntry<String, Uint8List>>[
          MapEntry('quarterly-report-Q1', _createSealedFile(masterKey, 'q1')),
          MapEntry('quarterly-report-Q2', _createSealedFile(masterKey, 'q2')),
          MapEntry('quarterly-report-Q3', _createSealedFile(masterKey, 'q3')),
        ];

        final results = BatchOperations.batchVerify(files, masterKey);

        expect(results[0]['name'], equals('quarterly-report-Q1'));
        expect(results[1]['name'], equals('quarterly-report-Q2'));
        expect(results[2]['name'], equals('quarterly-report-Q3'));
      });
    });

    group('batchSeal', () {
      test('seals multiple files with same key', () {
        final inputs = <MapEntry<String, Uint8List>>[];
        for (var i = 0; i < 3; i++) {
          inputs.add(
            MapEntry(
              'doc_$i.txt',
              Uint8List.fromList(utf8.encode('Document $i')),
            ),
          );
        }

        const baseOptions = ZegelOptions(contentType: 'text/plain');

        final sealedFiles = BatchOperations.batchSeal(
          inputs,
          masterKey,
          baseOptions,
        );

        expect(sealedFiles.length, equals(3));

        // Each sealed file should be verifiable
        const reader = ZegelReader();
        for (final sealed in sealedFiles) {
          expect(sealed.value, isNotNull);
          expect(sealed.value.length, greaterThan(0));

          final result = reader.verify(sealed.value, masterKey);
          expect(result.valid, isTrue);
        }
      });

      test('applies base options to all files', () {
        final inputs = <MapEntry<String, Uint8List>>[];
        for (var i = 0; i < 3; i++) {
          inputs.add(
            MapEntry(
              'doc_$i.txt',
              Uint8List.fromList(utf8.encode('AAAA' * 1000)),
            ),
          );
        }

        const baseOptions = ZegelOptions(compress: true);

        final sealedFiles = BatchOperations.batchSeal(
          inputs,
          masterKey,
          baseOptions,
        );

        // All sealed files should have the COMPRESSED flag
        const reader = ZegelReader();
        for (final sealed in sealedFiles) {
          final inspection = reader.inspect(sealed.value);
          expect(
            inspection.flags & ZegelFormat.flagCompressed,
            isNonZero,
            reason: 'All batch-sealed files should be compressed',
          );
        }
      });

      test('preserves individual filenames', () {
        final inputs = <MapEntry<String, Uint8List>>[
          MapEntry(
            'report.pdf',
            Uint8List.fromList(utf8.encode('PDF content')),
          ),
          MapEntry('photo.jpg', Uint8List.fromList(utf8.encode('Image data'))),
          MapEntry('notes.txt', Uint8List.fromList(utf8.encode('Plain text'))),
        ];

        const baseOptions = ZegelOptions(
          contentType: 'application/octet-stream',
        );

        final sealedFiles = BatchOperations.batchSeal(
          inputs,
          masterKey,
          baseOptions,
        );

        expect(sealedFiles.length, equals(3));

        const reader = ZegelReader();
        final inspection0 = reader.inspect(sealedFiles[0].value);
        expect(inspection0.filename, equals('report.pdf'));

        final inspection1 = reader.inspect(sealedFiles[1].value);
        expect(inspection1.filename, equals('photo.jpg'));

        final inspection2 = reader.inspect(sealedFiles[2].value);
        expect(inspection2.filename, equals('notes.txt'));
      });
    });
  });
}
