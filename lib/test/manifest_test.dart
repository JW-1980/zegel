import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

/// Creates a 32-byte Merkle root stand-in by hashing the content string.
Uint8List _merkleRootFor(String content) {
  return Uint8List.fromList(sha256.convert(utf8.encode(content)).bytes);
}

/// Creates a 32-byte signer key from a string identifier.
Uint8List _signerKey(String id) {
  return Uint8List.fromList(sha256.convert(utf8.encode(id)).bytes);
}

void main() {
  group('ZegelManifest', () {
    group('manifest creation and signature', () {
      test('create manifest from 5 file entries and verify signature', () {
        final entries = <String, Uint8List>{};
        for (var i = 0; i < 5; i++) {
          entries['file_$i.txt'] = _merkleRootFor('Content of file $i');
        }

        final signerKey = _signerKey('manifest-signer');
        final manifest = ZegelManifest.create(
          entries,
          signerKey,
          'auditor@example.com',
        );

        expect(manifest, isNotNull);
        final files = manifest['files'] as List<dynamic>;
        expect(files.length, equals(5));

        // Verify the manifest signature
        final isValid = ZegelManifest.verify(manifest, signerKey);
        expect(isValid, isTrue,
            reason: 'Manifest signature should verify with correct key');
      });

      test('manifest with wrong signer key fails verification', () {
        final entries = <String, Uint8List>{
          'doc.txt': _merkleRootFor('Document content'),
        };

        final signerKey = _signerKey('manifest-signer');
        final wrongKey = _signerKey('wrong-signer');

        final manifest = ZegelManifest.create(
          entries,
          signerKey,
          'auditor@example.com',
        );

        final isValid = ZegelManifest.verify(manifest, wrongKey);
        expect(isValid, isFalse,
            reason: 'Manifest signature should fail with wrong key');
      });
    });

    group('file verification with checkFiles', () {
      test('checkFiles with matching roots succeeds', () {
        final entries = <String, Uint8List>{};
        for (var i = 0; i < 3; i++) {
          entries['report_$i.txt'] = _merkleRootFor('Report content $i');
        }

        final signerKey = _signerKey('deep-verify-signer');
        final manifest = ZegelManifest.create(
          entries,
          signerKey,
          'verifier@example.com',
        );

        // Provide the same Merkle roots for verification
        final actualRoots = <String, Uint8List>{};
        for (var i = 0; i < 3; i++) {
          actualRoots['report_$i.txt'] = _merkleRootFor('Report content $i');
        }

        final results = ZegelManifest.checkFiles(manifest, actualRoots);
        for (final entry in results.entries) {
          expect(entry.value, isTrue,
              reason: 'File ${entry.key} should match');
        }
      });

      test('checkFiles detects missing file', () {
        final entries = <String, Uint8List>{};
        for (var i = 0; i < 3; i++) {
          entries['doc_$i.txt'] = _merkleRootFor('Document $i');
        }

        final signerKey = _signerKey('missing-file-signer');
        final manifest = ZegelManifest.create(
          entries,
          signerKey,
          'verifier@example.com',
        );

        // Provide only 2 of 3 files
        final actualRoots = <String, Uint8List>{
          'doc_0.txt': _merkleRootFor('Document 0'),
          'doc_1.txt': _merkleRootFor('Document 1'),
          // doc_2.txt is missing
        };

        final results = ZegelManifest.checkFiles(manifest, actualRoots);
        expect(results['doc_2.txt'], isFalse,
            reason: 'Missing file should be reported as not matching');
      });

      test('checkFiles detects tampered file (wrong Merkle root)', () {
        final entries = <String, Uint8List>{};
        for (var i = 0; i < 3; i++) {
          entries['audit_$i.txt'] = _merkleRootFor('Audit content $i');
        }

        final signerKey = _signerKey('tampered-file-signer');
        final manifest = ZegelManifest.create(
          entries,
          signerKey,
          'verifier@example.com',
        );

        // Replace one file's root with a different hash
        final actualRoots = <String, Uint8List>{
          'audit_0.txt': _merkleRootFor('Audit content 0'),
          'audit_1.txt': _merkleRootFor('TAMPERED content that differs'),
          'audit_2.txt': _merkleRootFor('Audit content 2'),
        };

        final results = ZegelManifest.checkFiles(manifest, actualRoots);
        expect(results['audit_1.txt'], isFalse,
            reason: 'Tampered file should be reported as not matching');
        expect(results['audit_0.txt'], isTrue);
        expect(results['audit_2.txt'], isTrue);
      });
    });

    group('manifest structure', () {
      test('manifest includes signer ID and version', () {
        final entries = <String, Uint8List>{
          'report.txt': _merkleRootFor('Report content'),
        };

        final signerKey = _signerKey('meta-signer');
        final manifest = ZegelManifest.create(
          entries,
          signerKey,
          'admin@example.com',
        );

        expect(manifest['signer_id'], equals('admin@example.com'));
        expect(manifest['version'], equals(1));
        expect(manifest.containsKey('created_at'), isTrue);
        expect(manifest.containsKey('signature'), isTrue);
      });
    });

    group('edge cases', () {
      test('empty manifest is valid', () {
        final signerKey = _signerKey('empty-signer');
        final manifest = ZegelManifest.create(
          <String, Uint8List>{},
          signerKey,
          'admin@example.com',
        );

        final files = manifest['files'] as List<dynamic>;
        expect(files, isEmpty);

        final isValid = ZegelManifest.verify(manifest, signerKey);
        expect(isValid, isTrue,
            reason: 'Empty manifest should still have a valid signature');
      });

      test('manifest preserves file order', () {
        // Use a LinkedHashMap to preserve insertion order
        final entries = <String, Uint8List>{};
        final filenames = ['z-last.txt', 'a-first.txt', 'm-middle.txt'];
        for (final name in filenames) {
          entries[name] = _merkleRootFor('Content for $name');
        }

        final signerKey = _signerKey('order-signer');
        final manifest = ZegelManifest.create(
          entries,
          signerKey,
          'admin@example.com',
        );

        final files = manifest['files'] as List<dynamic>;
        // Order should be preserved, not sorted
        expect((files[0] as Map<String, dynamic>)['filename'],
            equals('z-last.txt'));
        expect((files[1] as Map<String, dynamic>)['filename'],
            equals('a-first.txt'));
        expect((files[2] as Map<String, dynamic>)['filename'],
            equals('m-middle.txt'));
      });

      test('manifest file entries include merkle_root', () {
        final entries = <String, Uint8List>{
          'sized.txt': _merkleRootFor('Some content here'),
        };

        final signerKey = _signerKey('size-signer');
        final manifest = ZegelManifest.create(
          entries,
          signerKey,
          'admin@example.com',
        );

        final files = manifest['files'] as List<dynamic>;
        final fileEntry = files[0] as Map<String, dynamic>;
        expect(fileEntry['filename'], equals('sized.txt'));
        expect(fileEntry['merkle_root'], isNotNull);
        expect((fileEntry['merkle_root'] as String).length, equals(64),
            reason: 'Merkle root hex should be 64 chars (32 bytes)');
      });
    });
  });
}
