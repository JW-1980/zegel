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

/// Creates a 32-byte Merkle root for testing.
Uint8List _testMerkleRoot() {
  return Uint8List.fromList(
    sha256.convert(utf8.encode('test-merkle-root')).bytes,
  );
}

/// Creates a 64-byte fake master seal for testing.
Uint8List _testMasterSeal() {
  return Uint8List.fromList(
    sha256.convert(utf8.encode('test-master-seal-part1')).bytes +
        sha256.convert(utf8.encode('test-master-seal-part2')).bytes,
  );
}

void main() {
  group('TrustedTimestamp', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    group('createRequest', () {
      test('produces a non-empty map', () {
        final merkleRoot = _testMerkleRoot();
        final masterSeal = _testMasterSeal();
        final request = TrustedTimestamp.createRequest(
          merkleRoot,
          masterSeal,
        );

        expect(request, isNotNull);
        expect(request, isNotEmpty,
            reason: 'Timestamp request should be non-empty');
      });

      test('request contains required fields', () {
        final merkleRoot = _testMerkleRoot();
        final masterSeal = _testMasterSeal();
        final request = TrustedTimestamp.createRequest(
          merkleRoot,
          masterSeal,
        );

        expect(request.containsKey('version'), isTrue);
        expect(request['version'], equals(1));
        expect(request.containsKey('algorithm'), isTrue);
        expect(request['algorithm'], equals('SHA-256'));
        expect(request.containsKey('message_imprint'), isTrue);
        expect(request.containsKey('nonce'), isTrue);
        expect(request.containsKey('cert_req'), isTrue);
        expect(request['cert_req'], isTrue);
      });

      test('different inputs produce different message imprints', () {
        final root1 = Uint8List.fromList(
          sha256.convert(utf8.encode('root-1')).bytes,
        );
        final root2 = Uint8List.fromList(
          sha256.convert(utf8.encode('root-2')).bytes,
        );
        final masterSeal = _testMasterSeal();

        final request1 = TrustedTimestamp.createRequest(root1, masterSeal);
        final request2 = TrustedTimestamp.createRequest(root2, masterSeal);

        expect(
          request1['message_imprint'],
          isNot(equals(request2['message_imprint'])),
          reason:
              'Different Merkle roots should produce different message imprints',
        );
      });
    });

    group('createLocalToken', () {
      test('returns complete map', () {
        final merkleRoot = _testMerkleRoot();
        final masterSeal = _testMasterSeal();
        final signerKey = masterKey;

        final token = TrustedTimestamp.createLocalToken(
          merkleRoot,
          masterSeal,
          signerKey,
        );

        expect(token, isNotNull);
        expect(token, isA<Map<String, dynamic>>());
      });

      test('local token includes type field', () {
        final merkleRoot = _testMerkleRoot();
        final masterSeal = _testMasterSeal();
        final signerKey = masterKey;

        final token = TrustedTimestamp.createLocalToken(
          merkleRoot,
          masterSeal,
          signerKey,
        );

        expect(token['type'], equals('local'));
      });

      test('local token includes merkle_root hex', () {
        final merkleRoot = _testMerkleRoot();
        final masterSeal = _testMasterSeal();
        final signerKey = masterKey;

        final token = TrustedTimestamp.createLocalToken(
          merkleRoot,
          masterSeal,
          signerKey,
        );

        expect(token.containsKey('merkle_root'), isTrue);
        final rootHex = token['merkle_root'] as String;
        expect(rootHex.length, equals(64),
            reason: 'Merkle root hex should be 64 characters (32 bytes)');
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(rootHex), isTrue,
            reason: 'Merkle root hex should be lowercase hex');
      });

      test('local token includes current timestamp', () {
        final merkleRoot = _testMerkleRoot();
        final masterSeal = _testMasterSeal();
        final signerKey = masterKey;

        final beforeEpoch =
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

        final token = TrustedTimestamp.createLocalToken(
          merkleRoot,
          masterSeal,
          signerKey,
        );

        final afterEpoch =
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

        expect(token.containsKey('timestamp'), isTrue);
        final timestamp = token['timestamp'] as int;
        expect(timestamp, greaterThanOrEqualTo(beforeEpoch));
        expect(timestamp, lessThanOrEqualTo(afterEpoch));
      });

      test('local token includes version', () {
        final merkleRoot = _testMerkleRoot();
        final masterSeal = _testMasterSeal();
        final signerKey = masterKey;
        final token = TrustedTimestamp.createLocalToken(
          merkleRoot,
          masterSeal,
          signerKey,
        );

        expect(token.containsKey('version'), isTrue);
        expect(token['version'], equals(1));
      });

      test('local token can be JSON-serialized', () {
        final merkleRoot = _testMerkleRoot();
        final masterSeal = _testMasterSeal();
        final signerKey = masterKey;
        final token = TrustedTimestamp.createLocalToken(
          merkleRoot,
          masterSeal,
          signerKey,
        );

        // Should not throw
        final json = jsonEncode(token);
        expect(json, isNotEmpty);

        // Should round-trip
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        expect(decoded['type'], equals(token['type']));
        expect(decoded['merkle_root'], equals(token['merkle_root']));
      });

      test('local token includes signature', () {
        final merkleRoot = _testMerkleRoot();
        final masterSeal = _testMasterSeal();
        final signerKey = masterKey;

        final token = TrustedTimestamp.createLocalToken(
          merkleRoot,
          masterSeal,
          signerKey,
        );

        expect(token.containsKey('signature'), isTrue);
        final sigHex = token['signature'] as String;
        expect(sigHex.length, equals(64),
            reason: 'Signature hex should be 64 chars for HMAC-SHA256');
      });
    });

    group('verifyLocalToken', () {
      test('verifies valid local token', () {
        final merkleRoot = _testMerkleRoot();
        final masterSeal = _testMasterSeal();
        final signerKey = masterKey;

        final token = TrustedTimestamp.createLocalToken(
          merkleRoot,
          masterSeal,
          signerKey,
        );

        final isValid = TrustedTimestamp.verifyLocalToken(
          token,
          merkleRoot,
          masterSeal,
          signerKey,
        );
        expect(isValid, isTrue,
            reason: 'Valid local token should pass verification');
      });

      test('fails with wrong signer key', () {
        final merkleRoot = _testMerkleRoot();
        final masterSeal = _testMasterSeal();
        final signerKey = masterKey;

        final token = TrustedTimestamp.createLocalToken(
          merkleRoot,
          masterSeal,
          signerKey,
        );

        final wrongKey = Uint8List(32);
        wrongKey[31] = 0x02;

        final isValid = TrustedTimestamp.verifyLocalToken(
          token,
          merkleRoot,
          masterSeal,
          wrongKey,
        );
        expect(isValid, isFalse,
            reason: 'Token signed with different key should fail verification');
      });
    });

    group('timestamp in sealed files', () {
      test('sealed file can be inspected for timestamp block context', () {
        final content = Uint8List.fromList(utf8.encode('Timestamped doc'));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'timestamped.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        // Inspect the sealed file
        final inspection = const ZegelReader().inspect(fileBytes);
        expect(inspection, isNotNull);
        expect(inspection.blockCount, greaterThan(0));

        // Create a local token using test Merkle root / master seal
        final merkleRoot = _testMerkleRoot();
        final masterSeal = _testMasterSeal();
        final token = TrustedTimestamp.createLocalToken(
          merkleRoot,
          masterSeal,
          masterKey,
        );
        expect(token['merkle_root'], isNotNull);
      });
    });
  });
}
