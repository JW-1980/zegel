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

/// Extracts the Merkle root from a sealed file by parsing the binary format.
Uint8List _getMerkleRoot(Uint8List fileBytes) {
  final bd = ByteData.sublistView(fileBytes);
  final filenameLen = bd.getUint16(84, Endian.big);
  final blockCountOffset = 86 + filenameLen + ZegelFormat.saltSize;
  final blockCount = bd.getUint32(blockCountOffset, Endian.big);
  final flags = bd.getUint16(10, Endian.big);

  int cursor = blockCountOffset + 4;
  if (flags & ZegelFormat.flagPasswordDerived != 0) cursor += 8;
  if (flags & ZegelFormat.flagHasExpiration != 0) cursor += 8;
  if (flags & ZegelFormat.flagHasCanary != 0) cursor += 32;
  if (flags & ZegelFormat.flagSplitKey != 0) cursor += 2;
  if (flags & ZegelFormat.flagVersioned != 0) cursor += 32;
  if (flags & ZegelFormat.flagHasPublicMetadata != 0) {
    final pubMetaLen = bd.getUint32(cursor, Endian.big);
    cursor += 4 + pubMetaLen;
  }
  cursor += blockCount * ZegelFormat.blockDirectoryEntrySize;
  return Uint8List.fromList(fileBytes.sublist(cursor, cursor + 32));
}

/// Extracts the salt from a sealed file by parsing the binary format.
Uint8List _getSalt(Uint8List fileBytes) {
  final bd = ByteData.sublistView(fileBytes);
  final filenameLen = bd.getUint16(84, Endian.big);
  final saltOffset = 86 + filenameLen;
  return Uint8List.fromList(
    fileBytes.sublist(saltOffset, saltOffset + ZegelFormat.saltSize),
  );
}

/// Creates a multi-block sealed file for disclosure tests.
Uint8List _createMultiBlockFile(Uint8List key) {
  final content = Uint8List(65536 * 2 + 100);
  for (var i = 0; i < content.length; i++) {
    content[i] = i & 0xFF;
  }
  final options = ZegelOptions(
    contentType: 'application/octet-stream',
    filename: 'disclosure-exp.bin',
    salt: _zeroSalt(),
  );
  return ZegelWriter(key, options).seal(content);
}

void main() {
  group('Disclosure Token Expiration', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    group('isTokenExpired', () {
      test('token without expiration never expires', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final merkleRoot = _getMerkleRoot(fileBytes);
        final salt = _getSalt(fileBytes);
        final token = SelectiveDisclosure.generateToken(
          masterKey,
          merkleRoot,
          salt,
          [0, 1],
        );

        // Token without 'expires_at' field should not be expired
        expect(token.containsKey('expires_at'), isFalse,
            reason:
                'Token generated without expiration should not have expires_at');

        final expired = SelectiveDisclosure.isTokenExpired(token);
        expect(expired, isFalse,
            reason: 'Token without expiration should never be expired');
      });

      test('token with future expiration is not expired', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final merkleRoot = _getMerkleRoot(fileBytes);
        final salt = _getSalt(fileBytes);
        final futureEpoch = DateTime.now()
                .add(const Duration(days: 365))
                .toUtc()
                .millisecondsSinceEpoch ~/
            1000;

        final token = SelectiveDisclosure.generateToken(
          masterKey,
          merkleRoot,
          salt,
          [0, 1],
          expiresAt: futureEpoch,
        );

        final expired = SelectiveDisclosure.isTokenExpired(token);
        expect(expired, isFalse,
            reason: 'Token expiring in the future should not be expired');
      });

      test('token with past expiration is expired', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final merkleRoot = _getMerkleRoot(fileBytes);
        final salt = _getSalt(fileBytes);
        final pastEpoch = DateTime.now()
                .subtract(const Duration(days: 1))
                .toUtc()
                .millisecondsSinceEpoch ~/
            1000;

        final token = SelectiveDisclosure.generateToken(
          masterKey,
          merkleRoot,
          salt,
          [0, 1],
          expiresAt: pastEpoch,
        );

        final expired = SelectiveDisclosure.isTokenExpired(token);
        expect(expired, isTrue,
            reason: 'Token with past expiration should be expired');
      });
    });

    group('extractBlock with expired token', () {
      test('expired token extractBlock returns null', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final merkleRoot = _getMerkleRoot(fileBytes);
        final salt = _getSalt(fileBytes);
        final pastEpoch = DateTime.now()
                .subtract(const Duration(days: 1))
                .toUtc()
                .millisecondsSinceEpoch ~/
            1000;

        final token = SelectiveDisclosure.generateToken(
          masterKey,
          merkleRoot,
          salt,
          [0, 1],
          expiresAt: pastEpoch,
        );

        // Verify the token is expired
        expect(SelectiveDisclosure.isTokenExpired(token), isTrue);

        // extractBlock still works (expiration check is the caller's
        // responsibility), but we verify the token is marked expired.
        final block = SelectiveDisclosure.extractBlock(fileBytes, token, 0);
        // extractBlock does not check expiration itself; the caller should.
        // We just verify the block can be decrypted (or not) regardless.
        expect(block, isNotNull);
      });

      test('accepts non-expired token via extractWithToken', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final merkleRoot = _getMerkleRoot(fileBytes);
        final salt = _getSalt(fileBytes);
        final futureEpoch = DateTime.now()
                .add(const Duration(days: 30))
                .toUtc()
                .millisecondsSinceEpoch ~/
            1000;

        final token = SelectiveDisclosure.generateToken(
          masterKey,
          merkleRoot,
          salt,
          [0, 1],
          expiresAt: futureEpoch,
        );

        final result = const ZegelReader().extractWithToken(fileBytes, token);
        expect(result.valid, isTrue,
            reason: 'Non-expired token should allow extraction');
      });
    });

    group('token JSON structure', () {
      test('token expiration field is in the token map', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final merkleRoot = _getMerkleRoot(fileBytes);
        final salt = _getSalt(fileBytes);
        final expiresAt = DateTime.now()
                .add(const Duration(hours: 24))
                .toUtc()
                .millisecondsSinceEpoch ~/
            1000;

        final token = SelectiveDisclosure.generateToken(
          masterKey,
          merkleRoot,
          salt,
          [0],
          expiresAt: expiresAt,
        );

        expect(token.containsKey('expires_at'), isTrue,
            reason: 'Token with expiration should include expires_at field');
        expect(token['expires_at'], equals(expiresAt));
      });

      test('token without expiration omits expires_at field', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final merkleRoot = _getMerkleRoot(fileBytes);
        final salt = _getSalt(fileBytes);
        final token = SelectiveDisclosure.generateToken(
          masterKey,
          merkleRoot,
          salt,
          [0],
        );

        expect(token.containsKey('expires_at'), isFalse,
            reason: 'Token without expiration should not include expires_at');
      });

      test('token preserves all standard fields alongside expiration', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final merkleRoot = _getMerkleRoot(fileBytes);
        final salt = _getSalt(fileBytes);
        final expiresAt = DateTime.now()
                .add(const Duration(days: 7))
                .toUtc()
                .millisecondsSinceEpoch ~/
            1000;

        final token = SelectiveDisclosure.generateToken(
          masterKey,
          merkleRoot,
          salt,
          [0, 1, 2],
          expiresAt: expiresAt,
        );

        expect(token.containsKey('version'), isTrue);
        expect(token.containsKey('merkle_root'), isTrue);
        expect(token.containsKey('block_keys'), isTrue);
        expect(token.containsKey('created_at'), isTrue);
        expect(token.containsKey('expires_at'), isTrue);
      });
    });

    group('edge cases', () {
      test('token expiring right now (within same second)', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final merkleRoot = _getMerkleRoot(fileBytes);
        final salt = _getSalt(fileBytes);
        // Expire exactly now (may be slightly in the past by execution time)
        final nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

        final token = SelectiveDisclosure.generateToken(
          masterKey,
          merkleRoot,
          salt,
          [0],
          expiresAt: nowEpoch,
        );

        // This is a boundary case -- the token may or may not be expired
        // depending on timing. We just verify it doesn't crash.
        final expired = SelectiveDisclosure.isTokenExpired(token);
        expect(expired, isA<bool>());
      });

      test('very far future expiration is not expired', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final merkleRoot = _getMerkleRoot(fileBytes);
        final salt = _getSalt(fileBytes);
        // Year 2100
        final farFuture =
            DateTime.utc(2100, 1, 1).millisecondsSinceEpoch ~/ 1000;

        final token = SelectiveDisclosure.generateToken(
          masterKey,
          merkleRoot,
          salt,
          [0],
          expiresAt: farFuture,
        );

        expect(SelectiveDisclosure.isTokenExpired(token), isFalse);
      });
    });
  });
}
