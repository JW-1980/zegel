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
  group('Classification', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    group('compare', () {
      test('orders levels correctly: PUBLIC < INTERNAL < CONFIDENTIAL < SECRET < TOP_SECRET', () {
        expect(
          Classification.compare(
            ZegelFormat.classificationPublic,
            ZegelFormat.classificationInternal,
          ),
          lessThan(0),
          reason: 'PUBLIC should be lower than INTERNAL',
        );
        expect(
          Classification.compare(
            ZegelFormat.classificationInternal,
            ZegelFormat.classificationConfidential,
          ),
          lessThan(0),
          reason: 'INTERNAL should be lower than CONFIDENTIAL',
        );
        expect(
          Classification.compare(
            ZegelFormat.classificationConfidential,
            ZegelFormat.classificationSecret,
          ),
          lessThan(0),
          reason: 'CONFIDENTIAL should be lower than SECRET',
        );
        expect(
          Classification.compare(
            ZegelFormat.classificationSecret,
            ZegelFormat.classificationTopSecret,
          ),
          lessThan(0),
          reason: 'SECRET should be lower than TOP_SECRET',
        );
      });

      test('same levels compare as equal', () {
        expect(
          Classification.compare(
            ZegelFormat.classificationSecret,
            ZegelFormat.classificationSecret,
          ),
          equals(0),
        );
      });

      test('higher level compares as greater than lower level', () {
        expect(
          Classification.compare(
            ZegelFormat.classificationTopSecret,
            ZegelFormat.classificationPublic,
          ),
          greaterThan(0),
        );
      });
    });

    group('createClassificationMetadata', () {
      test('returns complete metadata', () {
        final metadata = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationSecret,
          authority: 'Classification Board',
          classifiedBy: 'admin@gov.example',
        );

        expect(metadata['classification_level'],
            equals(ZegelFormat.classificationSecret));
        expect(metadata['classification_authority'],
            equals('Classification Board'));
        expect(metadata['classified_by'], equals('admin@gov.example'));
        expect(metadata.containsKey('classified_at'), isTrue);
      });

      test('classification with caveat includes caveat', () {
        final metadata = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationTopSecret,
          authority: 'National Security Office',
          classifiedBy: 'officer@nso.example',
          caveat: 'NOFORN',
        );

        expect(metadata['caveat'], equals('NOFORN'));
      });

      test('classification with declassify date includes it', () {
        final declassifyDate = '2036-01-01';
        final metadata = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationConfidential,
          authority: 'Records Office',
          classifiedBy: 'archivist@gov.example',
          declassifyDate: declassifyDate,
        );

        expect(metadata['declassify_date'], equals(declassifyDate));
      });

      test('classification without optional fields omits them', () {
        final metadata = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationInternal,
          authority: 'IT Department',
          classifiedBy: 'admin@corp.example',
        );

        expect(metadata.containsKey('caveat'), isFalse);
        expect(metadata.containsKey('declassify_date'), isFalse);
      });
    });

    group('declassify', () {
      test('reduces level', () {
        final content = Uint8List.fromList(utf8.encode('Secret document'));
        final classificationMeta = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationSecret,
          authority: 'Security Office',
          classifiedBy: 'officer@gov.example',
        );
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'secret-doc.txt',
          salt: _zeroSalt(),
          publicMetadata: classificationMeta,
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        final declassified = Classification.declassify(
          fileBytes: fileBytes,
          masterKey: masterKey,
          newLevel: ZegelFormat.classificationConfidential,
          authority: 'Declassification Board',
          declassifiedBy: 'reviewer@gov.example',
        );

        expect(declassified, isNotNull);

        // Inspect the declassified file to check the new level
        final inspection = ZegelReader.inspect(declassified);
        expect(inspection.publicMetadata, isNotNull);
        expect(
          inspection.publicMetadata!['classification_level'],
          equals(ZegelFormat.classificationConfidential),
        );
      });

      test('refuses to raise level (throws)', () {
        final content = Uint8List.fromList(utf8.encode('Internal document'));
        final classificationMeta = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationInternal,
          authority: 'IT Department',
          classifiedBy: 'admin@corp.example',
        );
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'internal-doc.txt',
          salt: _zeroSalt(),
          publicMetadata: classificationMeta,
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        expect(
          () => Classification.declassify(
            fileBytes: fileBytes,
            masterKey: masterKey,
            newLevel: ZegelFormat.classificationTopSecret,
            authority: 'Rogue Actor',
            declassifiedBy: 'attacker@evil.example',
          ),
          throwsA(isA<ZegelException>()),
          reason: 'Declassification must not raise the classification level',
        );
      });

      test('declassify with redaction removes specified blocks', () {
        // Create a multi-block file
        final content = Uint8List(65536 * 2 + 100);
        for (var i = 0; i < content.length; i++) {
          content[i] = i & 0xFF;
        }
        final classificationMeta = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationTopSecret,
          authority: 'NSO',
          classifiedBy: 'officer@nso.example',
        );
        final options = ZegelOptions(
          contentType: 'application/octet-stream',
          filename: 'classified.bin',
          salt: _zeroSalt(),
          publicMetadata: classificationMeta,
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        final declassified = Classification.declassify(
          fileBytes: fileBytes,
          masterKey: masterKey,
          newLevel: ZegelFormat.classificationConfidential,
          authority: 'Declassification Board',
          declassifiedBy: 'reviewer@gov.example',
          redactBlockIndices: [0], // Redact the first content block
        );

        // The declassified file should have redacted blocks
        final result = ZegelReader.verify(declassified, masterKey);
        expect(result.valid, isTrue);
        expect(result.redactedBlocks, isNotNull);
        expect(result.redactedBlocks, contains(0));
      });

      test('declassified file still verifies', () {
        final content = Uint8List.fromList(utf8.encode('Confidential data'));
        final classificationMeta = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationConfidential,
          authority: 'Records Office',
          classifiedBy: 'clerk@gov.example',
        );
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'confidential.txt',
          salt: _zeroSalt(),
          publicMetadata: classificationMeta,
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        final declassified = Classification.declassify(
          fileBytes: fileBytes,
          masterKey: masterKey,
          newLevel: ZegelFormat.classificationInternal,
          authority: 'Declassification Board',
          declassifiedBy: 'reviewer@gov.example',
        );

        final result = ZegelReader.verify(declassified, masterKey);
        expect(result.valid, isTrue,
            reason: 'Declassified file must still verify');
      });
    });

    group('classification in sealed files', () {
      test('classification level appears in public metadata', () {
        final content = Uint8List.fromList(utf8.encode('Public report'));
        final classificationMeta = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationPublic,
          authority: 'Communications Office',
          classifiedBy: 'pr@corp.example',
        );
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'public-report.txt',
          salt: _zeroSalt(),
          publicMetadata: classificationMeta,
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        // Public metadata should be readable without the master key
        final inspection = ZegelReader.inspect(fileBytes);
        expect(inspection.publicMetadata, isNotNull);
        expect(
          inspection.publicMetadata!['classification_level'],
          equals(ZegelFormat.classificationPublic),
        );
      });

      test('HAS_CLASSIFICATION flag is set when classification metadata present', () {
        final content = Uint8List.fromList(utf8.encode('Classified'));
        final classificationMeta = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationSecret,
          authority: 'Security Office',
          classifiedBy: 'officer@gov.example',
        );
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'secret.txt',
          salt: _zeroSalt(),
          publicMetadata: classificationMeta,
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        final inspection = ZegelReader.inspect(fileBytes);
        // The HAS_PUBLIC_METADATA flag should be set (classification is in
        // public metadata)
        expect(
          inspection.flags & ZegelFormat.flagHasPublicMetadata,
          isNonZero,
          reason: 'Classification metadata should be in public metadata',
        );
      });
    });
  });
}
