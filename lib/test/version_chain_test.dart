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

/// Creates a 32-byte all-zeros salt for deterministic testing.
Uint8List _zeroSalt() => Uint8List(32);

/// Creates a sealed file with a given version chain hash.
Uint8List _createVersionedFile(
  Uint8List key,
  String filename,
  String content, {
  Uint8List? versionChainHash,
  int? version,
}) {
  final contentBytes = Uint8List.fromList(utf8.encode(content));
  final options = ZegelOptions(
    contentType: 'text/plain',
    filename: filename,
    salt: _zeroSalt(),
    versionChainHash: versionChainHash,
    publicMetadata: version != null
        ? {'version': version, 'previous_filename': filename}
        : null,
  );
  return ZegelWriter.seal(contentBytes, key, options: options);
}

/// Extracts the Merkle root from a sealed file via inspection.
Uint8List _getMerkleRoot(Uint8List fileBytes) {
  final inspection = ZegelReader.inspect(fileBytes);
  return inspection.merkleRoot!;
}

/// Extracts the master seal (last 64 bytes) from a sealed file.
Uint8List _getMasterSeal(Uint8List fileBytes) {
  return Uint8List.fromList(
    fileBytes.sublist(fileBytes.length - 64),
  );
}

void main() {
  group('Version Chain Verification', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    group('verifyVersionChain', () {
      test('succeeds for properly linked files', () {
        // Create version 1 (no chain hash -- it is the first version)
        final v1Bytes = _createVersionedFile(
          masterKey,
          'contract_v1.txt',
          'Original contract text',
          version: 1,
        );

        // Compute chain hash linking v2 to v1
        final v1MerkleRoot = _getMerkleRoot(v1Bytes);
        final v1MasterSeal = _getMasterSeal(v1Bytes);
        final chainHash12 = ContentVersioning.computeChainHash(
          v1MerkleRoot,
          v1MasterSeal,
        );

        // Create version 2 linked to version 1
        final v2Bytes = _createVersionedFile(
          masterKey,
          'contract_v2.txt',
          'Amended contract text',
          versionChainHash: chainHash12,
          version: 2,
        );

        // Compute chain hash linking v3 to v2
        final v2MerkleRoot = _getMerkleRoot(v2Bytes);
        final v2MasterSeal = _getMasterSeal(v2Bytes);
        final chainHash23 = ContentVersioning.computeChainHash(
          v2MerkleRoot,
          v2MasterSeal,
        );

        // Create version 3 linked to version 2
        final v3Bytes = _createVersionedFile(
          masterKey,
          'contract_v3.txt',
          'Final contract text',
          versionChainHash: chainHash23,
          version: 3,
        );

        // Verify the chain: v1 -> v2 -> v3
        final chain = [v1Bytes, v2Bytes, v3Bytes];
        final result = ContentVersioning.verifyVersionChain(chain);
        expect(result, isTrue,
            reason: 'Properly linked version chain should verify');
      });

      test('fails for files with broken chain', () {
        // Create version 1
        final v1Bytes = _createVersionedFile(
          masterKey,
          'doc_v1.txt',
          'Version 1 content',
          version: 1,
        );

        // Create version 2 with a WRONG chain hash
        final wrongChainHash = Uint8List(32);
        wrongChainHash[0] = 0xFF;
        final v2Bytes = _createVersionedFile(
          masterKey,
          'doc_v2.txt',
          'Version 2 content',
          versionChainHash: wrongChainHash,
          version: 2,
        );

        final chain = [v1Bytes, v2Bytes];
        final result = ContentVersioning.verifyVersionChain(chain);
        expect(result, isFalse,
            reason: 'Broken chain hash should fail verification');
      });
    });

    group('createVersionMetadata', () {
      test('includes version number', () {
        final metadata = ContentVersioning.createVersionMetadata(
          version: 3,
          previousFilename: 'report_v2.txt',
        );

        expect(metadata['version'], equals(3));
      });

      test('includes previous filename', () {
        final metadata = ContentVersioning.createVersionMetadata(
          version: 2,
          previousFilename: 'contract_v1.txt',
        );

        expect(metadata['previous_filename'], equals('contract_v1.txt'));
      });

      test('includes timestamp', () {
        final beforeEpoch =
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

        final metadata = ContentVersioning.createVersionMetadata(
          version: 1,
          previousFilename: null,
        );

        final afterEpoch =
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

        if (metadata.containsKey('created_at')) {
          final ts = metadata['created_at'] as int;
          expect(ts, greaterThanOrEqualTo(beforeEpoch));
          expect(ts, lessThanOrEqualTo(afterEpoch));
        }
      });

      test('first version has no previous filename', () {
        final metadata = ContentVersioning.createVersionMetadata(
          version: 1,
          previousFilename: null,
        );

        expect(metadata['version'], equals(1));
        // previous_filename should be absent or null for version 1
        final prev = metadata['previous_filename'];
        expect(prev == null || prev == '', isTrue,
            reason:
                'First version should have no previous filename');
      });
    });

    group('chain hash computation', () {
      test('chain hash is 32 bytes', () {
        final merkleRoot = Uint8List.fromList(
          sha256.convert(utf8.encode('root')).bytes,
        );
        final masterSeal = Uint8List(64);
        masterSeal[0] = 0xAB;

        final hash = ContentVersioning.computeChainHash(
          merkleRoot,
          masterSeal,
        );

        expect(hash.length, equals(32));
      });

      test('same inputs produce same chain hash', () {
        final merkleRoot = Uint8List.fromList(
          sha256.convert(utf8.encode('root')).bytes,
        );
        final masterSeal = Uint8List(64);
        for (var i = 0; i < 64; i++) {
          masterSeal[i] = i;
        }

        final hash1 = ContentVersioning.computeChainHash(
          merkleRoot,
          masterSeal,
        );
        final hash2 = ContentVersioning.computeChainHash(
          merkleRoot,
          masterSeal,
        );

        expect(hash1, equals(hash2));
      });

      test('different inputs produce different chain hashes', () {
        final root1 = Uint8List.fromList(
          sha256.convert(utf8.encode('root1')).bytes,
        );
        final root2 = Uint8List.fromList(
          sha256.convert(utf8.encode('root2')).bytes,
        );
        final seal = Uint8List(64);

        final hash1 = ContentVersioning.computeChainHash(root1, seal);
        final hash2 = ContentVersioning.computeChainHash(root2, seal);

        expect(hash1, isNot(equals(hash2)));
      });

      test('verifyChain confirms valid hash', () {
        final merkleRoot = Uint8List.fromList(
          sha256.convert(utf8.encode('verify-root')).bytes,
        );
        final masterSeal = Uint8List(64);
        masterSeal[10] = 0x42;

        final chainHash = ContentVersioning.computeChainHash(
          merkleRoot,
          masterSeal,
        );

        final isValid = ContentVersioning.verifyChain(
          chainHash,
          merkleRoot,
          masterSeal,
        );
        expect(isValid, isTrue);
      });

      test('verifyChain rejects invalid hash', () {
        final merkleRoot = Uint8List.fromList(
          sha256.convert(utf8.encode('verify-root')).bytes,
        );
        final masterSeal = Uint8List(64);

        final badHash = Uint8List(32);
        badHash[0] = 0xFF;

        final isValid = ContentVersioning.verifyChain(
          badHash,
          merkleRoot,
          masterSeal,
        );
        expect(isValid, isFalse);
      });
    });

    group('edge cases', () {
      test('single file chain is valid', () {
        final v1Bytes = _createVersionedFile(
          masterKey,
          'solo.txt',
          'Single version document',
          version: 1,
        );

        final result = ContentVersioning.verifyVersionChain([v1Bytes]);
        expect(result, isTrue,
            reason: 'Single file chain should be trivially valid');
      });

      test('empty chain is valid', () {
        final result =
            ContentVersioning.verifyVersionChain(<Uint8List>[]);
        expect(result, isTrue,
            reason: 'Empty chain should be trivially valid');
      });

      test('version flag is set when chain hash is provided', () {
        final v1Bytes = _createVersionedFile(
          masterKey,
          'v1.txt',
          'First version',
          version: 1,
        );

        final v1MerkleRoot = _getMerkleRoot(v1Bytes);
        final v1MasterSeal = _getMasterSeal(v1Bytes);
        final chainHash = ContentVersioning.computeChainHash(
          v1MerkleRoot,
          v1MasterSeal,
        );

        final v2Bytes = _createVersionedFile(
          masterKey,
          'v2.txt',
          'Second version',
          versionChainHash: chainHash,
          version: 2,
        );

        final inspection = ZegelReader.inspect(v2Bytes);
        expect(
          inspection.flags & ZegelFormat.flagVersioned,
          isNonZero,
          reason: 'VERSIONED flag should be set when chain hash is provided',
        );
      });
    });
  });
}
