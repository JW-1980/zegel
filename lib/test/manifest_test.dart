import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

/// Creates a 32-byte test master key (0x00...01).
Uint8List _testKey() {
  final key = Uint8List(32);
  key[31] = 0x01;
  return key;
}

/// Creates a second test key that differs from the primary key.
Uint8List _otherKey() {
  final key = Uint8List(32);
  key[31] = 0x02;
  return key;
}

/// Creates a 32-byte all-zeros salt for deterministic testing.
Uint8List _zeroSalt() => Uint8List(32);

/// Creates a sealed file and returns a ManifestFileEntry for it.
ManifestFileEntry _createFileEntry(
  Uint8List key,
  String filename,
  String content,
) {
  final contentBytes = Uint8List.fromList(utf8.encode(content));
  final options = ZegelOptions(
    contentType: 'text/plain',
    filename: filename,
    salt: _zeroSalt(),
  );
  final fileBytes = ZegelWriter.seal(contentBytes, key, options: options);
  final inspection = ZegelReader.inspect(fileBytes);

  return ManifestFileEntry(
    filename: filename,
    merkleRoot: inspection.merkleRoot!,
    contentType: 'text/plain',
    fileSize: fileBytes.length,
    fileBytes: fileBytes,
  );
}

/// Creates a 32-byte signer key from a string identifier.
Uint8List _signerKey(String id) {
  return Uint8List.fromList(sha256.convert(utf8.encode(id)).bytes);
}

void main() {
  group('ZegelManifest', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    group('manifest creation and signature', () {
      test('create manifest from 5 file entries and verify signature', () {
        final entries = <ManifestFileEntry>[];
        for (var i = 0; i < 5; i++) {
          entries.add(_createFileEntry(
            masterKey,
            'file_$i.txt',
            'Content of file $i',
          ));
        }

        final signerKey = _signerKey('manifest-signer');
        final manifest = ZegelManifest.create(
          entries: entries,
          signerId: 'auditor@example.com',
          signerKey: signerKey,
        );

        expect(manifest, isNotNull);
        expect(manifest.entries.length, equals(5));

        // Verify the manifest signature
        final isValid = ZegelManifest.verifySignature(
          manifest,
          signerKey,
        );
        expect(isValid, isTrue,
            reason: 'Manifest signature should verify with correct key');
      });

      test('manifest with wrong signer key fails verification', () {
        final entries = <ManifestFileEntry>[
          _createFileEntry(masterKey, 'doc.txt', 'Document content'),
        ];

        final signerKey = _signerKey('manifest-signer');
        final wrongKey = _signerKey('wrong-signer');

        final manifest = ZegelManifest.create(
          entries: entries,
          signerId: 'auditor@example.com',
          signerKey: signerKey,
        );

        final isValid = ZegelManifest.verifySignature(
          manifest,
          wrongKey,
        );
        expect(isValid, isFalse,
            reason: 'Manifest signature should fail with wrong key');
      });
    });

    group('deep verification', () {
      test('deep verify with matching files succeeds', () {
        final entries = <ManifestFileEntry>[];
        for (var i = 0; i < 3; i++) {
          entries.add(_createFileEntry(
            masterKey,
            'report_$i.txt',
            'Report content $i',
          ));
        }

        final signerKey = _signerKey('deep-verify-signer');
        final manifest = ZegelManifest.create(
          entries: entries,
          signerId: 'verifier@example.com',
          signerKey: signerKey,
        );

        // Provide the actual file bytes for deep verification
        final fileMap = <String, Uint8List>{};
        for (final entry in entries) {
          fileMap[entry.filename] = entry.fileBytes!;
        }

        final deepResult = ZegelManifest.deepVerify(
          manifest,
          signerKey,
          fileMap,
        );
        expect(deepResult.valid, isTrue);
        expect(deepResult.missingFiles, isEmpty);
        expect(deepResult.tamperedFiles, isEmpty);
      });

      test('deep verify detects missing file', () {
        final entries = <ManifestFileEntry>[];
        for (var i = 0; i < 3; i++) {
          entries.add(_createFileEntry(
            masterKey,
            'doc_$i.txt',
            'Document $i',
          ));
        }

        final signerKey = _signerKey('missing-file-signer');
        final manifest = ZegelManifest.create(
          entries: entries,
          signerId: 'verifier@example.com',
          signerKey: signerKey,
        );

        // Provide only 2 of 3 files
        final fileMap = <String, Uint8List>{};
        fileMap[entries[0].filename] = entries[0].fileBytes!;
        fileMap[entries[1].filename] = entries[1].fileBytes!;
        // entries[2] is missing

        final deepResult = ZegelManifest.deepVerify(
          manifest,
          signerKey,
          fileMap,
        );
        expect(deepResult.valid, isFalse,
            reason: 'Missing file should cause deep verify failure');
        expect(deepResult.missingFiles, contains('doc_2.txt'));
      });

      test('deep verify detects tampered file (wrong Merkle root)', () {
        final entries = <ManifestFileEntry>[];
        for (var i = 0; i < 3; i++) {
          entries.add(_createFileEntry(
            masterKey,
            'audit_$i.txt',
            'Audit content $i',
          ));
        }

        final signerKey = _signerKey('tampered-file-signer');
        final manifest = ZegelManifest.create(
          entries: entries,
          signerId: 'verifier@example.com',
          signerKey: signerKey,
        );

        // Replace one file with a different sealed file (different content)
        final differentEntry = _createFileEntry(
          masterKey,
          'audit_1.txt',
          'TAMPERED content that differs from original',
        );

        final fileMap = <String, Uint8List>{};
        fileMap[entries[0].filename] = entries[0].fileBytes!;
        fileMap['audit_1.txt'] = differentEntry.fileBytes!; // tampered
        fileMap[entries[2].filename] = entries[2].fileBytes!;

        final deepResult = ZegelManifest.deepVerify(
          manifest,
          signerKey,
          fileMap,
        );
        expect(deepResult.valid, isFalse,
            reason: 'Tampered file should cause deep verify failure');
        expect(deepResult.tamperedFiles, contains('audit_1.txt'));
      });
    });

    group('manifest metadata', () {
      test('manifest includes metadata', () {
        final entries = <ManifestFileEntry>[
          _createFileEntry(masterKey, 'report.txt', 'Report content'),
        ];

        final signerKey = _signerKey('meta-signer');
        final manifest = ZegelManifest.create(
          entries: entries,
          signerId: 'admin@example.com',
          signerKey: signerKey,
          metadata: {
            'audit_period': 'Q1-2026',
            'department': 'Finance',
          },
        );

        expect(manifest.metadata, isNotNull);
        expect(manifest.metadata!['audit_period'], equals('Q1-2026'));
        expect(manifest.metadata!['department'], equals('Finance'));
      });
    });

    group('edge cases', () {
      test('empty manifest is valid', () {
        final signerKey = _signerKey('empty-signer');
        final manifest = ZegelManifest.create(
          entries: <ManifestFileEntry>[],
          signerId: 'admin@example.com',
          signerKey: signerKey,
        );

        expect(manifest.entries, isEmpty);

        final isValid = ZegelManifest.verifySignature(manifest, signerKey);
        expect(isValid, isTrue,
            reason: 'Empty manifest should still have a valid signature');
      });

      test('manifest preserves file order', () {
        final entries = <ManifestFileEntry>[];
        final filenames = ['z-last.txt', 'a-first.txt', 'm-middle.txt'];
        for (final name in filenames) {
          entries.add(_createFileEntry(masterKey, name, 'Content for $name'));
        }

        final signerKey = _signerKey('order-signer');
        final manifest = ZegelManifest.create(
          entries: entries,
          signerId: 'admin@example.com',
          signerKey: signerKey,
        );

        // Order should be preserved, not sorted
        expect(manifest.entries[0].filename, equals('z-last.txt'));
        expect(manifest.entries[1].filename, equals('a-first.txt'));
        expect(manifest.entries[2].filename, equals('m-middle.txt'));
      });

      test('manifest entry includes file size', () {
        final entry = _createFileEntry(
          masterKey,
          'sized.txt',
          'Some content here',
        );

        expect(entry.fileSize, greaterThan(0),
            reason: 'File size should be positive');
      });
    });
  });
}
