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
  return ZegelWriter.seal(content, key, options: options);
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
        final files = <BatchEntry>[];
        for (var i = 0; i < 5; i++) {
          final fileBytes = _createSealedFile(masterKey, 'file_$i');
          files.add(BatchEntry(
            label: 'file_$i',
            fileBytes: fileBytes,
            key: masterKey,
          ));
        }

        final results = BatchOperations.batchVerify(files);

        expect(results.length, equals(5));
        for (final result in results) {
          expect(result.valid, isTrue,
              reason: '${result.label} should verify successfully');
        }
      });

      test('detects tampered file in batch', () {
        final files = <BatchEntry>[];
        for (var i = 0; i < 5; i++) {
          var fileBytes = _createSealedFile(masterKey, 'file_$i');
          // Tamper with file at index 2
          if (i == 2) {
            fileBytes = _tamperFile(fileBytes);
          }
          files.add(BatchEntry(
            label: 'file_$i',
            fileBytes: fileBytes,
            key: masterKey,
          ));
        }

        final results = BatchOperations.batchVerify(files);

        expect(results.length, equals(5));
        // Files 0, 1, 3, 4 should be valid
        expect(results[0].valid, isTrue);
        expect(results[1].valid, isTrue);
        // File 2 should be invalid
        expect(results[2].valid, isFalse,
            reason: 'Tampered file should fail verification');
        expect(results[3].valid, isTrue);
        expect(results[4].valid, isTrue);
      });

      test('stops on first failure when configured', () {
        final files = <BatchEntry>[];
        for (var i = 0; i < 5; i++) {
          var fileBytes = _createSealedFile(masterKey, 'file_$i');
          // Tamper with file at index 1
          if (i == 1) {
            fileBytes = _tamperFile(fileBytes);
          }
          files.add(BatchEntry(
            label: 'file_$i',
            fileBytes: fileBytes,
            key: masterKey,
          ));
        }

        final results = BatchOperations.batchVerify(
          files,
          stopOnFirstFailure: true,
        );

        // Should stop after file_1 fails, so only 2 results
        expect(results.length, equals(2));
        expect(results[0].valid, isTrue);
        expect(results[1].valid, isFalse);
      });

      test('returns elapsed time per file', () {
        final files = <BatchEntry>[];
        for (var i = 0; i < 3; i++) {
          final fileBytes = _createSealedFile(masterKey, 'file_$i');
          files.add(BatchEntry(
            label: 'file_$i',
            fileBytes: fileBytes,
            key: masterKey,
          ));
        }

        final results = BatchOperations.batchVerify(files);

        for (final result in results) {
          expect(result.elapsed, isNotNull,
              reason: 'Each result should include elapsed time');
          expect(result.elapsed, isA<Duration>());
          // Duration should be non-negative (could be zero on very fast systems)
          expect(result.elapsed.inMicroseconds, greaterThanOrEqualTo(0));
        }
      });

      test('handles empty input list', () {
        final results = BatchOperations.batchVerify(<BatchEntry>[]);

        expect(results, isEmpty,
            reason: 'Empty input should return empty results');
      });

      test('preserves labels in results', () {
        final files = <BatchEntry>[
          BatchEntry(
            label: 'quarterly-report-Q1',
            fileBytes: _createSealedFile(masterKey, 'q1'),
            key: masterKey,
          ),
          BatchEntry(
            label: 'quarterly-report-Q2',
            fileBytes: _createSealedFile(masterKey, 'q2'),
            key: masterKey,
          ),
          BatchEntry(
            label: 'quarterly-report-Q3',
            fileBytes: _createSealedFile(masterKey, 'q3'),
            key: masterKey,
          ),
        ];

        final results = BatchOperations.batchVerify(files);

        expect(results[0].label, equals('quarterly-report-Q1'));
        expect(results[1].label, equals('quarterly-report-Q2'));
        expect(results[2].label, equals('quarterly-report-Q3'));
      });
    });

    group('batchSeal', () {
      test('seals multiple files with same key', () {
        final inputs = <BatchSealInput>[];
        for (var i = 0; i < 3; i++) {
          inputs.add(BatchSealInput(
            content: Uint8List.fromList(utf8.encode('Document $i')),
            filename: 'doc_$i.txt',
            contentType: 'text/plain',
          ));
        }

        final sealedFiles = BatchOperations.batchSeal(
          inputs,
          masterKey,
        );

        expect(sealedFiles.length, equals(3));

        // Each sealed file should be verifiable
        for (final sealed in sealedFiles) {
          expect(sealed, isNotNull);
          expect(sealed.length, greaterThan(0));

          final result = ZegelReader.verify(sealed, masterKey);
          expect(result.valid, isTrue);
        }
      });

      test('applies base options to all files', () {
        final inputs = <BatchSealInput>[];
        for (var i = 0; i < 3; i++) {
          inputs.add(BatchSealInput(
            content: Uint8List.fromList(utf8.encode('AAAA' * 1000)),
            filename: 'doc_$i.txt',
            contentType: 'text/plain',
          ));
        }

        final baseOptions = ZegelOptions(
          compress: true,
          salt: _zeroSalt(),
        );

        final sealedFiles = BatchOperations.batchSeal(
          inputs,
          masterKey,
          baseOptions: baseOptions,
        );

        // All sealed files should have the COMPRESSED flag
        for (final sealed in sealedFiles) {
          final inspection = ZegelReader.inspect(sealed);
          expect(
            inspection.flags & ZegelFormat.flagCompressed,
            isNonZero,
            reason: 'All batch-sealed files should be compressed',
          );
        }
      });

      test('preserves individual filenames and content types', () {
        final inputs = <BatchSealInput>[
          BatchSealInput(
            content: Uint8List.fromList(utf8.encode('PDF content')),
            filename: 'report.pdf',
            contentType: 'application/pdf',
          ),
          BatchSealInput(
            content: Uint8List.fromList(utf8.encode('Image data')),
            filename: 'photo.jpg',
            contentType: 'image/jpeg',
          ),
          BatchSealInput(
            content: Uint8List.fromList(utf8.encode('Plain text')),
            filename: 'notes.txt',
            contentType: 'text/plain',
          ),
        ];

        final sealedFiles = BatchOperations.batchSeal(
          inputs,
          masterKey,
        );

        expect(sealedFiles.length, equals(3));

        final inspection0 = ZegelReader.inspect(sealedFiles[0]);
        expect(inspection0.filename, equals('report.pdf'));
        expect(inspection0.contentType, equals('application/pdf'));

        final inspection1 = ZegelReader.inspect(sealedFiles[1]);
        expect(inspection1.filename, equals('photo.jpg'));
        expect(inspection1.contentType, equals('image/jpeg'));

        final inspection2 = ZegelReader.inspect(sealedFiles[2]);
        expect(inspection2.filename, equals('notes.txt'));
        expect(inspection2.contentType, equals('text/plain'));
      });
    });
  });
}
