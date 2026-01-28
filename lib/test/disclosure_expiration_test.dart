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
  return ZegelWriter.seal(content, key, options: options);
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
        final token = ZegelDisclosure.generateToken(
          fileBytes,
          masterKey,
          [0, 1],
        );
        final tokenJson = jsonDecode(token) as Map<String, dynamic>;

        // Token without 'expires_at' field should not be expired
        expect(tokenJson.containsKey('expires_at'), isFalse,
            reason:
                'Token generated without expiration should not have expires_at');

        final expired = ZegelDisclosure.isTokenExpired(token);
        expect(expired, isFalse,
            reason: 'Token without expiration should never be expired');
      });

      test('token with future expiration is not expired', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final futureEpoch =
            DateTime.now()
                    .add(const Duration(days: 365))
                    .toUtc()
                    .millisecondsSinceEpoch ~/
                1000;

        final token = ZegelDisclosure.generateToken(
          fileBytes,
          masterKey,
          [0, 1],
          expiresAt: futureEpoch,
        );

        final expired = ZegelDisclosure.isTokenExpired(token);
        expect(expired, isFalse,
            reason: 'Token expiring in the future should not be expired');
      });

      test('token with past expiration is expired', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final pastEpoch =
            DateTime.now()
                    .subtract(const Duration(days: 1))
                    .toUtc()
                    .millisecondsSinceEpoch ~/
                1000;

        final token = ZegelDisclosure.generateToken(
          fileBytes,
          masterKey,
          [0, 1],
          expiresAt: pastEpoch,
        );

        final expired = ZegelDisclosure.isTokenExpired(token);
        expect(expired, isTrue,
            reason: 'Token with past expiration should be expired');
      });
    });

    group('extractBlock with expired token', () {
      test('refuses expired token', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final pastEpoch =
            DateTime.now()
                    .subtract(const Duration(days: 1))
                    .toUtc()
                    .millisecondsSinceEpoch ~/
                1000;

        final token = ZegelDisclosure.generateToken(
          fileBytes,
          masterKey,
          [0, 1],
          expiresAt: pastEpoch,
        );

        // Attempting extraction with an expired token should fail
        expect(
          () => ZegelDisclosure.extractWithToken(fileBytes, token),
          throwsA(anything),
          reason:
              'Extracting with an expired token should throw or return invalid',
        );
      });

      test('accepts non-expired token', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final futureEpoch =
            DateTime.now()
                    .add(const Duration(days: 30))
                    .toUtc()
                    .millisecondsSinceEpoch ~/
                1000;

        final token = ZegelDisclosure.generateToken(
          fileBytes,
          masterKey,
          [0, 1],
          expiresAt: futureEpoch,
        );

        final result = ZegelDisclosure.extractWithToken(fileBytes, token);
        expect(result.valid, isTrue,
            reason: 'Non-expired token should allow extraction');
      });
    });

    group('token JSON structure', () {
      test('token expiration field is in the JSON', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final expiresAt =
            DateTime.now()
                    .add(const Duration(hours: 24))
                    .toUtc()
                    .millisecondsSinceEpoch ~/
                1000;

        final token = ZegelDisclosure.generateToken(
          fileBytes,
          masterKey,
          [0],
          expiresAt: expiresAt,
        );

        final tokenJson = jsonDecode(token) as Map<String, dynamic>;
        expect(tokenJson.containsKey('expires_at'), isTrue,
            reason:
                'Token with expiration should include expires_at field');
        expect(tokenJson['expires_at'], equals(expiresAt));
      });

      test('token without expiration omits expires_at field', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final token = ZegelDisclosure.generateToken(
          fileBytes,
          masterKey,
          [0],
        );

        final tokenJson = jsonDecode(token) as Map<String, dynamic>;
        expect(tokenJson.containsKey('expires_at'), isFalse,
            reason:
                'Token without expiration should not include expires_at');
      });

      test('token preserves all standard fields alongside expiration', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        final expiresAt =
            DateTime.now()
                    .add(const Duration(days: 7))
                    .toUtc()
                    .millisecondsSinceEpoch ~/
                1000;

        final token = ZegelDisclosure.generateToken(
          fileBytes,
          masterKey,
          [0, 1, 2],
          expiresAt: expiresAt,
        );

        final tokenJson = jsonDecode(token) as Map<String, dynamic>;
        expect(tokenJson.containsKey('version'), isTrue);
        expect(tokenJson.containsKey('merkle_root'), isTrue);
        expect(tokenJson.containsKey('block_keys'), isTrue);
        expect(tokenJson.containsKey('created_at'), isTrue);
        expect(tokenJson.containsKey('expires_at'), isTrue);
      });
    });

    group('edge cases', () {
      test('token expiring right now (within same second)', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        // Expire exactly now (may be slightly in the past by execution time)
        final nowEpoch =
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

        final token = ZegelDisclosure.generateToken(
          fileBytes,
          masterKey,
          [0],
          expiresAt: nowEpoch,
        );

        // This is a boundary case -- the token may or may not be expired
        // depending on timing. We just verify it doesn't crash.
        final expired = ZegelDisclosure.isTokenExpired(token);
        expect(expired, isA<bool>());
      });

      test('very far future expiration is not expired', () {
        final fileBytes = _createMultiBlockFile(masterKey);
        // Year 2100
        final farFuture =
            DateTime.utc(2100, 1, 1).millisecondsSinceEpoch ~/ 1000;

        final token = ZegelDisclosure.generateToken(
          fileBytes,
          masterKey,
          [0],
          expiresAt: farFuture,
        );

        expect(ZegelDisclosure.isTokenExpired(token), isFalse);
      });
    });
  });
}
