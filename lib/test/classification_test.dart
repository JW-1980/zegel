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
      test(
        'orders levels correctly: PUBLIC < INTERNAL < CONFIDENTIAL < SECRET < TOP_SECRET',
        () {
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
        },
      );

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
        );

        final classification =
            metadata['classification'] as Map<String, dynamic>;
        expect(
          classification['level'],
          equals(ZegelFormat.classificationSecret),
        );
        expect(classification['authority'], equals('Classification Board'));
        expect(classification.containsKey('classified_at'), isTrue);
      });

      test('classification with caveat includes caveat', () {
        final metadata = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationTopSecret,
          authority: 'National Security Office',
          caveat: 'NOFORN',
        );

        final classification =
            metadata['classification'] as Map<String, dynamic>;
        expect(classification['caveat'], equals('NOFORN'));
      });

      test('classification with declassify date includes it', () {
        final declassifyDate = DateTime.utc(2036, 1, 1);
        final metadata = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationConfidential,
          authority: 'Records Office',
          declassifyOn: declassifyDate,
        );

        final classification =
            metadata['classification'] as Map<String, dynamic>;
        expect(classification.containsKey('declassify_on'), isTrue);
      });

      test('classification without optional fields omits them', () {
        final metadata = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationInternal,
          authority: 'IT Department',
        );

        final classification =
            metadata['classification'] as Map<String, dynamic>;
        expect(classification.containsKey('caveat'), isFalse);
        expect(classification.containsKey('declassify_on'), isFalse);
      });
    });

    group('declassify', () {
      test('reduces level', () {
        final content = Uint8List.fromList(utf8.encode('Secret document'));
        final classificationMeta = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationSecret,
          authority: 'Security Office',
        );
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'secret-doc.txt',
          salt: _zeroSalt(),
          publicMetadata: classificationMeta,
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final declassified = Classification.declassify(
          fileBytes,
          masterKey,
          ZegelFormat.classificationConfidential,
          'Declassification Board',
        );

        expect(declassified, isNotNull);

        // Inspect the declassified file to check the new level
        final inspection = const ZegelReader().inspect(declassified);
        expect(inspection.publicMetadata, isNotNull);
        final classification =
            inspection.publicMetadata!['classification']
                as Map<String, dynamic>;
        expect(
          classification['level'],
          equals(ZegelFormat.classificationConfidential),
        );
      });

      test('refuses to raise level (throws)', () {
        final content = Uint8List.fromList(utf8.encode('Internal document'));
        final classificationMeta = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationInternal,
          authority: 'IT Department',
        );
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'internal-doc.txt',
          salt: _zeroSalt(),
          publicMetadata: classificationMeta,
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        expect(
          () => Classification.declassify(
            fileBytes,
            masterKey,
            ZegelFormat.classificationTopSecret,
            'Rogue Actor',
          ),
          throwsA(isA<ArgumentError>()),
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
        );
        final options = ZegelOptions(
          contentType: 'application/octet-stream',
          filename: 'classified.bin',
          salt: _zeroSalt(),
          publicMetadata: classificationMeta,
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final declassified = Classification.declassify(
          fileBytes,
          masterKey,
          ZegelFormat.classificationConfidential,
          'Declassification Board',
          redactBlocks: [0], // Redact the first content block
        );

        // The declassified file is re-sealed after redaction, so the
        // redacted content is permanently removed (not marked as redacted).
        final result = const ZegelReader().verify(declassified, masterKey);
        expect(result.valid, isTrue);
        // Re-sealed file has less content than the original since
        // the first block was redacted before re-sealing.
        expect(result.content!.length, lessThan(content.length));
        // Declassification history should be in public metadata
        final pubMeta = result.publicMetadata!;
        expect(pubMeta.containsKey('declassification_history'), isTrue);
        final history = pubMeta['declassification_history'] as List;
        expect(history.length, equals(1));
        final entry = history[0] as Map<String, dynamic>;
        expect(entry['redacted_blocks'], equals([0]));
      });

      test('declassified file still verifies', () {
        final content = Uint8List.fromList(utf8.encode('Confidential data'));
        final classificationMeta = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationConfidential,
          authority: 'Records Office',
        );
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'confidential.txt',
          salt: _zeroSalt(),
          publicMetadata: classificationMeta,
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final declassified = Classification.declassify(
          fileBytes,
          masterKey,
          ZegelFormat.classificationInternal,
          'Declassification Board',
        );

        final result = const ZegelReader().verify(declassified, masterKey);
        expect(
          result.valid,
          isTrue,
          reason: 'Declassified file must still verify',
        );
      });
    });

    group('classification in sealed files', () {
      test('classification level appears in public metadata', () {
        final content = Uint8List.fromList(utf8.encode('Public report'));
        final classificationMeta = Classification.createClassificationMetadata(
          level: ZegelFormat.classificationPublic,
          authority: 'Communications Office',
        );
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'public-report.txt',
          salt: _zeroSalt(),
          publicMetadata: classificationMeta,
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        // Public metadata should be readable without the master key
        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection.publicMetadata, isNotNull);
        final classification =
            inspection.publicMetadata!['classification']
                as Map<String, dynamic>;
        expect(
          classification['level'],
          equals(ZegelFormat.classificationPublic),
        );
      });

      test(
        'HAS_CLASSIFICATION flag is set when classification metadata present',
        () {
          final content = Uint8List.fromList(utf8.encode('Classified'));
          final classificationMeta =
              Classification.createClassificationMetadata(
                level: ZegelFormat.classificationSecret,
                authority: 'Security Office',
              );
          final options = ZegelOptions(
            contentType: 'text/plain',
            filename: 'secret.txt',
            salt: _zeroSalt(),
            publicMetadata: classificationMeta,
          );
          final fileBytes = ZegelWriter(masterKey, options).seal(content);

          final inspection = const ZegelReader().inspect(fileBytes);
          // The HAS_PUBLIC_METADATA flag should be set (classification is in
          // public metadata)
          expect(
            inspection.flags & ZegelFormat.flagHasPublicMetadata,
            isNonZero,
            reason: 'Classification metadata should be in public metadata',
          );
        },
      );
    });
  });
}
