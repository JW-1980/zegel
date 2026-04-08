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

/// Converts bytes to lowercase hex string.
String _bytesToHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Extracts the 32-byte salt from a sealed .zgl file.
Uint8List _extractSalt(Uint8List fileBytes) {
  final bd = ByteData.sublistView(fileBytes);
  final filenameLen = bd.getUint16(84, Endian.big);
  final saltOffset = 86 + filenameLen;
  return Uint8List.fromList(
    fileBytes.sublist(saltOffset, saltOffset + ZegelFormat.saltSize),
  );
}

/// Extracts the 32-byte Merkle root from a sealed .zgl file.
Uint8List _extractMerkleRoot(Uint8List fileBytes) {
  final bd = ByteData.sublistView(fileBytes);
  final flags = bd.getUint16(10, Endian.big);
  final filenameLen = bd.getUint16(84, Endian.big);
  final saltOffset = 86 + filenameLen;
  final blockCountOffset = saltOffset + ZegelFormat.saltSize;
  final blockCount = bd.getUint32(blockCountOffset, Endian.big);

  // Compute extended header size.
  int extSize = 0;
  if (flags & ZegelFormat.flagPasswordDerived != 0) extSize += 8;
  if (flags & ZegelFormat.flagHasExpiration != 0) extSize += 8;
  if (flags & ZegelFormat.flagHasCanary != 0) extSize += 32;
  if (flags & ZegelFormat.flagSplitKey != 0) extSize += 2;
  if (flags & ZegelFormat.flagVersioned != 0) extSize += 32;
  if (flags & ZegelFormat.flagHasPublicMetadata != 0) {
    final pubMetaLenOffset = blockCountOffset + 4 + extSize;
    final pubMetaLen = bd.getUint32(pubMetaLenOffset, Endian.big);
    extSize += 4 + pubMetaLen;
  }

  final directoryStart = blockCountOffset + 4 + extSize;
  final merkleRootOffset =
      directoryStart + (blockCount * ZegelFormat.blockDirectoryEntrySize);
  return Uint8List.fromList(
    fileBytes.sublist(
      merkleRootOffset,
      merkleRootOffset + ZegelFormat.hashSize,
    ),
  );
}

/// Generates a selective disclosure token for the given file and block indices.
Map<String, dynamic> _generateToken(
  Uint8List fileBytes,
  Uint8List masterKey,
  List<int> blockIndices, {
  int? expiresAt,
}) {
  final salt = _extractSalt(fileBytes);
  final merkleRoot = _extractMerkleRoot(fileBytes);
  return SelectiveDisclosure.generateToken(
    masterKey,
    merkleRoot,
    salt,
    blockIndices,
    expiresAt: expiresAt,
  );
}

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

void main() {
  group('Selective disclosure', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    group('token generation', () {
      test('generate token for blocks 0 and 2 of a 4-block file', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token = _generateToken(fileBytes, masterKey, [0, 2]);
        expect(token, isNotNull);
      });

      test('token contains correct block keys (hex encoded)', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token = _generateToken(fileBytes, masterKey, [0, 2]);

        final blockKeys = token['block_keys'] as Map<String, dynamic>;

        // Should have keys for blocks 0 and 2
        expect(blockKeys.containsKey('0'), isTrue);
        expect(blockKeys.containsKey('2'), isTrue);

        // Each key should be a 64-char hex string (32 bytes)
        final key0 = blockKeys['0'] as String;
        final key2 = blockKeys['2'] as String;
        expect(
          key0.length,
          equals(64),
          reason: 'Block key should be 64 hex chars (32 bytes)',
        );
        expect(key2.length, equals(64));

        // Should be valid hex
        expect(
          RegExp(r'^[0-9a-f]+$').hasMatch(key0),
          isTrue,
          reason: 'Block key should be lowercase hex',
        );
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(key2), isTrue);
      });

      test('token should NOT contain keys for non-disclosed blocks', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token = _generateToken(fileBytes, masterKey, [0, 2]);

        final blockKeys = token['block_keys'] as Map<String, dynamic>;

        expect(blockKeys.containsKey('1'), isFalse);
        expect(blockKeys.containsKey('3'), isFalse);
      });

      test('token has version=1', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token = _generateToken(fileBytes, masterKey, [0, 2]);

        expect(token['version'], equals(1));
      });

      test('token has correct merkle_root', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);
        final merkleRoot = _extractMerkleRoot(fileBytes);

        final token = _generateToken(fileBytes, masterKey, [0, 2]);

        final tokenMerkleRoot = token['merkle_root'] as String;
        expect(
          tokenMerkleRoot.length,
          equals(64),
          reason: 'Merkle root should be 64 hex chars',
        );

        // Convert extracted merkle root to hex for comparison
        final expectedHex = _bytesToHex(merkleRoot);
        expect(tokenMerkleRoot, equals(expectedHex));
      });

      test('token has created_at timestamp', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token = _generateToken(fileBytes, masterKey, [0, 2]);

        expect(token.containsKey('created_at'), isTrue);
        expect(token['created_at'], isA<int>());
        expect(token['created_at'] as int, greaterThan(0));
      });
    });

    group('extraction with token', () {
      test('extract with token returns valid result', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        // Generate token for blocks 0 (metadata) and 2 (second content block)
        final token = _generateToken(fileBytes, masterKey, [0, 2]);

        final result = const ZegelReader().extractWithToken(fileBytes, token);
        expect(result, isNotNull);
        expect(result.valid, isTrue);

        // Should have access to block 0 (metadata) and block 2 (content)
        // Metadata should be accessible since block 0 is disclosed
        expect(result.metadata, isNotNull);
      });

      test('partial token yields less content than full extraction', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        // Full extraction with master key
        final fullResult = const ZegelReader().verify(fileBytes, masterKey);

        // Partial token for blocks 0 and 2 only
        final token = _generateToken(fileBytes, masterKey, [0, 2]);

        final partialResult = const ZegelReader().extractWithToken(
          fileBytes,
          token,
        );
        expect(partialResult.valid, isTrue);

        // Partial extraction should have less content since block 1 and 3 are skipped
        expect(
          partialResult.content!.length,
          lessThan(fullResult.content!.length),
          reason: 'Partial token should yield less content than full key',
        );
      });

      test(
        'token works with metadata block (block 0 when metadata present)',
        () {
          final fileBytes = _createFourBlockFileWithMetadata(masterKey);

          // Disclose only the metadata block (block 0)
          final token = _generateToken(fileBytes, masterKey, [0]);

          final result = const ZegelReader().extractWithToken(fileBytes, token);
          expect(result.valid, isTrue);

          // Metadata should be accessible
          expect(result.metadata, isNotNull);
          expect(result.metadata!['sealed_by'], equals('disclosure-test'));
        },
      );

      test('token for single content block works', () {
        final fileBytes = _createFourBlockFileNoMetadata(masterKey);

        // Disclose block 2 only
        final token = _generateToken(fileBytes, masterKey, [2]);

        final result = const ZegelReader().extractWithToken(fileBytes, token);
        expect(result.valid, isTrue);
        // Should have some content from the disclosed block
        expect(result.content, isNotNull);
        expect(result.content!.length, greaterThan(0));
      });

      test('token for all blocks discloses everything', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        // Full extraction with master key for comparison
        final fullResult = const ZegelReader().verify(fileBytes, masterKey);

        final token = _generateToken(fileBytes, masterKey, [0, 1, 2, 3]);

        final result = const ZegelReader().extractWithToken(fileBytes, token);
        expect(result.valid, isTrue);
        // Content should match full extraction
        expect(result.content, equals(fullResult.content));
        // Metadata should also match
        expect(result.metadata, equals(fullResult.metadata));
      });
    });

    group('invalid tokens', () {
      test('token generated for different file fails decryption', () {
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
        final fileBytes2 = ZegelWriter(
          masterKey,
          options,
        ).seal(differentContent);

        // Generate token for file 1
        final token = _generateToken(fileBytes1, masterKey, [0, 2]);

        // Try using it on file 2 -- block keys derived from file 1's merkle
        // root won't decrypt file 2's blocks.
        expect(
          () => const ZegelReader().extractWithToken(fileBytes2, token),
          throwsA(isA<ZegelTamperedException>()),
          reason: 'Token for different file should fail',
        );
      });

      test('token with missing block_keys fails gracefully', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        // Create a token map missing block_keys
        final invalidToken = <String, dynamic>{
          'version': 1,
          'merkle_root': 'ff' * 32,
          'created_at': 1234567890,
        };

        expect(
          () => const ZegelReader().extractWithToken(fileBytes, invalidToken),
          throwsA(anything),
        );
      });

      test(
        'token with wrong version still works if block keys are correct',
        () {
          final fileBytes = _createFourBlockFileWithMetadata(masterKey);

          final token = _generateToken(fileBytes, masterKey, [0]);
          token['version'] = 99; // wrong version

          // The reader does not validate the version field in the token,
          // so extraction should still succeed with correct block keys.
          final result = const ZegelReader().extractWithToken(fileBytes, token);
          expect(result.valid, isTrue);
        },
      );

      test('token with tampered block key fails decryption', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token = _generateToken(fileBytes, masterKey, [0, 2]);

        // Tamper with block 0's key
        final blockKeys = token['block_keys'] as Map<String, dynamic>;
        blockKeys['0'] = 'ff' * 32; // wrong key
        token['block_keys'] = blockKeys;

        // Block 0 decryption should fail, causing a ZegelTamperedException.
        expect(
          () => const ZegelReader().extractWithToken(fileBytes, token),
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
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final inspection = const ZegelReader().inspect(fileBytes);
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

        final token1 = _generateToken(fileBytes, masterKey, [0, 2]);
        final token2 = _generateToken(fileBytes, masterKey, [0, 2]);

        final keys1 = token1['block_keys'] as Map<String, dynamic>;
        final keys2 = token2['block_keys'] as Map<String, dynamic>;

        expect(keys1['0'], equals(keys2['0']));
        expect(keys1['2'], equals(keys2['2']));
      });

      test('different blocks have different keys', () {
        final fileBytes = _createFourBlockFileWithMetadata(masterKey);

        final token = _generateToken(fileBytes, masterKey, [0, 1, 2, 3]);
        final keys = token['block_keys'] as Map<String, dynamic>;

        final keySet = keys.values.toSet();
        expect(
          keySet.length,
          equals(4),
          reason: 'All block keys should be unique',
        );
      });
    });
  });
}
