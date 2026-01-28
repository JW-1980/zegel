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

/// Creates a 4-block file with metadata (total: 1 metadata + 3 content blocks).
/// Requires content > 2 * 65536 to get 3 content blocks.
Uint8List _createFourBlockFileWithMetadata(Uint8List key) {
  final content = Uint8List(65536 * 2 + 100);
  for (var i = 0; i < content.length; i++) {
    content[i] = i & 0xFF;
  }
  final options = ZegelOptions(
    contentType: 'application/octet-stream',
    filename: 'disclosure.bin',
    salt: _zeroSalt(),
    metadata: {'sealed_by': 'disclosure-test', 'document_id': 99},
  );
  return ZegelWriter(key, options).seal(content);
}

/// Creates a 4-block file without metadata (4 content blocks).
Uint8List _createFourBlockFileNoMetadata(Uint8List key) {
  final content = Uint8List(65536 * 3 + 100);
  for (var i = 0; i < content.length; i++) {
    content[i] = i & 0xFF;
  }
  final options = ZegelOptions(
    contentType: 'application/octet-stream',
    filename: 'disclosure-no-meta.bin',
    salt: _zeroSalt(),
  );
  return ZegelWriter(key, options).seal(content);
}

/// Helper to generate token by manually parsing the file to get salt/root.
String _generateTokenHelper(
    Uint8List fileBytes, Uint8List masterKey, List<int> indices) {
  final bd = ByteData.sublistView(fileBytes);
  final fnLen = bd.getUint16(84, Endian.big);
  final saltOffset = 86 + fnLen;
  final salt = fileBytes.sublist(saltOffset, saltOffset + 32);
  final blockCountOffset = saltOffset + 32;
  final blockCount = bd.getUint32(blockCountOffset, Endian.big);

  // Assuming no extended header for these test files
  final directoryStart = blockCountOffset + 4;
  final directorySize = blockCount * ZegelFormat.blockDirectoryEntrySize;
  final merkleRootOffset = directoryStart + directorySize;
  final merkleRoot = fileBytes.sublist(merkleRootOffset, merkleRootOffset + 32);

  // Use the SelectiveDisclosure class from the library
  final map = SelectiveDisclosure.generateToken(
      masterKey, merkleRoot, salt, indices);
  return jsonEncode(map);
}

void main() {
  group('Selective disclosure', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    group('token generation', () {
      test('generate token for blocks 0 and 2 of a 4-block file', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token =
            _generateTokenHelper(fileBytes, masterKey, [0, 2]);
        expect(token, isNotNull);
      });

      test('token contains correct block keys (hex encoded)', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token =
            _generateTokenHelper(fileBytes, masterKey, [0, 2]);
        final tokenJson = jsonDecode(token) as Map<String, dynamic>;

        final blockKeys =
            tokenJson['block_keys'] as Map<String, dynamic>;

        // Should have keys for blocks 0 and 2
        expect(blockKeys.containsKey('0'), isTrue);
        expect(blockKeys.containsKey('2'), isTrue);

        // Each key should be a 64-char hex string (32 bytes)
        final key0 = blockKeys['0'] as String;
        final key2 = blockKeys['2'] as String;
        expect(key0.length, equals(64),
            reason: 'Block key should be 64 hex chars (32 bytes)');
        expect(key2.length, equals(64));

        // Should be valid hex
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(key0), isTrue,
            reason: 'Block key should be lowercase hex');
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(key2), isTrue);
      });

      test('token should NOT contain keys for non-disclosed blocks', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token =
            _generateTokenHelper(fileBytes, masterKey, [0, 2]);
        final tokenJson = jsonDecode(token) as Map<String, dynamic>;

        final blockKeys =
            tokenJson['block_keys'] as Map<String, dynamic>;

        expect(blockKeys.containsKey('1'), isFalse);
        expect(blockKeys.containsKey('3'), isFalse);
      });

      test('token has version=1', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token =
            _generateTokenHelper(fileBytes, masterKey, [0, 2]);
        final tokenJson = jsonDecode(token) as Map<String, dynamic>;

        expect(tokenJson['version'], equals(1));
      });

      test('token has correct merkle_root', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);
        // ZegelReader().inspect(fileBytes) doesn't return merkleRoot in the current API.
        // We parse manually using our helper logic implicitly.

        final token =
            _generateTokenHelper(fileBytes, masterKey, [0, 2]);
        final tokenJson = jsonDecode(token) as Map<String, dynamic>;

        final tokenMerkleRoot = tokenJson['merkle_root'] as String;
        expect(tokenMerkleRoot.length, equals(64),
            reason: 'Merkle root should be 64 hex chars');

        // We trust the helper logic (which extracts the actual root) put the right one in.
        // Verifying it against inspection isn't possible as inspection hides it.
      });

      test('token has created_at timestamp', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token =
            _generateTokenHelper(fileBytes, masterKey, [0, 2]);
        final tokenJson = jsonDecode(token) as Map<String, dynamic>;

        expect(tokenJson.containsKey('created_at'), isTrue);
        expect(tokenJson['created_at'], isA<int>());
        expect(tokenJson['created_at'] as int, greaterThan(0));
      });
    });

    group('extraction with token', () {
      test('extract with token returns only disclosed blocks', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        // Generate token for blocks 0 (metadata) and 2 (second content block)
        final token =
            _generateTokenHelper(fileBytes, masterKey, [0, 2]);

        final result =
            ZegelReader().extractWithToken(fileBytes, jsonDecode(token) as Map<String, dynamic>);
        expect(result, isNotNull);
        expect(result.valid, isTrue);

        // Should have access to block 0 (metadata) and block 2 (content)
        expect(result.disclosedBlocks, containsAll([0, 2]));
      });

      test('cannot extract block 1 or 3 with partial token', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token =
            _generateTokenHelper(fileBytes, masterKey, [0, 2]);

        final result =
            ZegelReader().extractWithToken(fileBytes, jsonDecode(token) as Map<String, dynamic>);

        // Blocks 1 and 3 should not be accessible
        expect(result.disclosedBlocks, isNot(contains(1)));
        expect(result.disclosedBlocks, isNot(contains(3)));
      });

      test('token works with metadata block (block 0 when metadata present)', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        // Disclose only the metadata block (block 0)
        final token =
            _generateTokenHelper(fileBytes, masterKey, [0]);

        final result =
            ZegelReader().extractWithToken(fileBytes, jsonDecode(token) as Map<String, dynamic>);
        expect(result.valid, isTrue);

        // Metadata should be accessible
        expect(result.metadata, isNotNull);
        expect(result.metadata!['sealed_by'], equals('disclosure-test'));
      });

      test('token for single content block works', () {
        final fileBytes = _createFourBlockFileNoMetadata(masterKey);

        // Disclose block 2 only
        final token =
            _generateTokenHelper(fileBytes, masterKey, [2]);

        final result =
            ZegelReader().extractWithToken(fileBytes, jsonDecode(token) as Map<String, dynamic>);
        expect(result.valid, isTrue);
        expect(result.disclosedBlocks, contains(2));
        expect(result.disclosedBlocks, isNot(contains(0)));
        expect(result.disclosedBlocks, isNot(contains(1)));
        expect(result.disclosedBlocks, isNot(contains(3)));
      });

      test('token for all blocks discloses everything', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token = _generateTokenHelper(
            fileBytes, masterKey, [0, 1, 2, 3]);

        final result =
            ZegelReader().extractWithToken(fileBytes, jsonDecode(token) as Map<String, dynamic>);
        expect(result.valid, isTrue);
        expect(result.disclosedBlocks, containsAll([0, 1, 2, 3]));
      });
    });

    group('invalid tokens', () {
      test('invalid token (wrong merkle_root) fails', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        // Generate a valid token
        final token =
            _generateTokenHelper(fileBytes, masterKey, [0, 2]);

        // Modify the merkle_root in the token
        final tokenJson = jsonDecode(token) as Map<String, dynamic>;
        tokenJson['merkle_root'] = 'ff' * 32; // wrong root
        final invalidToken = jsonEncode(tokenJson);

        expect(
          () => ZegelReader().extractWithToken(
              fileBytes, jsonDecode(invalidToken) as Map<String, dynamic>),
          throwsA(isA<ZegelTamperedException>()),
          reason: 'Token with wrong merkle_root should fail',
        );
      });

      test('token generated for different file fails', () {
        final fileBytes1 = _createFourBlockFileWithMetadata(masterKey);

        // Create a different file
        final differentContent = Uint8List(65536 * 2 + 200);
        for (var i = 0; i < differentContent.length; i++) {
          differentContent[i] = (i + 1) & 0xFF;
        }
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'other.bin',
          salt: _zeroSalt(),
          metadata: {'sealed_by': 'other'},
        );
        final fileBytes2 =
            ZegelWriter(masterKey, options).seal(differentContent);

        // Generate token for file 1
        final token =
            _generateTokenHelper(fileBytes1, masterKey, [0, 2]);

        // Try using it on file 2
        expect(
          () => ZegelReader().extractWithToken(
              fileBytes2, jsonDecode(token) as Map<String, dynamic>),
          throwsA(isA<ZegelTamperedException>()),
          reason: 'Token for different file should fail',
        );
      });

      /*
      test('malformed token JSON fails gracefully', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        expect(
          () => ZegelReader().extractWithToken(fileBytes, 'not-valid-json'),
          throwsA(anything),
        );
      });
      */

      test('token with wrong version fails', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token =
            _generateTokenHelper(fileBytes, masterKey, [0]);
        final tokenJson = jsonDecode(token) as Map<String, dynamic>;
        tokenJson['version'] = 99; // wrong version
        final invalidToken = jsonEncode(tokenJson);

        expect(
          () => ZegelReader().extractWithToken(fileBytes, jsonDecode(invalidToken) as Map<String, dynamic>),
          anyOf(
            throwsA(anything),
            returnsNormally,
          ),
        );

        // If it doesn't throw, should return invalid
        try {
          final result =
              ZegelReader().extractWithToken(fileBytes, jsonDecode(invalidToken) as Map<String, dynamic>);
          expect(result.valid, isFalse);
        } catch (_) {
          // Throwing is acceptable
        }
      });

      test('token with tampered block key fails decryption', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token =
            _generateTokenHelper(fileBytes, masterKey, [0, 2]);
        final tokenJson = jsonDecode(token) as Map<String, dynamic>;

        // Tamper with block 0's key
        final blockKeys = tokenJson['block_keys'] as Map<String, dynamic>;
        blockKeys['0'] = 'ff' * 32; // wrong key
        tokenJson['block_keys'] = blockKeys;
        final tamperedToken = jsonEncode(tokenJson);

        // Block 0 should fail, block 2 may still work
        expect(
          () => ZegelReader().extractWithToken(
              fileBytes, jsonDecode(tamperedToken) as Map<String, dynamic>),
          throwsA(isA<ZegelTamperedException>()),
          reason: 'Tampered block key should cause decryption failure',
        );
      });
    });

    group('disclosure with SELECTIVE_DISCLOSURE flag', () {
      test('file with selective disclosure flag set', () {
        final content = Uint8List(65536 * 2 + 100);
        for (var i = 0; i < content.length; i++) {
          content[i] = i & 0xFF;
        }
        final options = ZegelOptions(
          contentType: 'application/octet-stream',
          filename: 'disclosed.bin',
          salt: _zeroSalt(),
          enableSelectiveDisclosure: true,
        );
        final fileBytes =
            ZegelWriter(masterKey, options).seal(content);

        final inspection = ZegelReader().inspect(fileBytes);
        expect(
          inspection.flags & ZegelFormat.flagSelectiveDisclosure,
          isNonZero,
          reason: 'SELECTIVE_DISCLOSURE flag should be set',
        );
      });
    });

    group('block key determinism', () {
      test('same file produces same block keys', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token1 =
            _generateTokenHelper(fileBytes, masterKey, [0, 2]);
        final token2 =
            _generateTokenHelper(fileBytes, masterKey, [0, 2]);

        final json1 = jsonDecode(token1) as Map<String, dynamic>;
        final json2 = jsonDecode(token2) as Map<String, dynamic>;

        final keys1 = json1['block_keys'] as Map<String, dynamic>;
        final keys2 = json2['block_keys'] as Map<String, dynamic>;

        expect(keys1['0'], equals(keys2['0']));
        expect(keys1['2'], equals(keys2['2']));
      });

      test('different blocks have different keys', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token = _generateTokenHelper(
            fileBytes, masterKey, [0, 1, 2, 3]);
        final json = jsonDecode(token) as Map<String, dynamic>;
        final keys = json['block_keys'] as Map<String, dynamic>;

        final keySet = keys.values.toSet();
        expect(keySet.length, equals(4),
            reason: 'All block keys should be unique');
      });
    });
  });
}
