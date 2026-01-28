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

void main() {
  group('TrustedTimestamp', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    group('createTimestampRequest', () {
      test('produces non-empty bytes', () {
        final merkleRoot = _testMerkleRoot();
        final request = TrustedTimestamp.createTimestampRequest(
          merkleRoot: merkleRoot,
        );

        expect(request, isNotNull);
        expect(request, isNotEmpty,
            reason: 'Timestamp request should be non-empty');
      });

      test('request is deterministic for same Merkle root', () {
        final merkleRoot = _testMerkleRoot();
        final request1 = TrustedTimestamp.createTimestampRequest(
          merkleRoot: merkleRoot,
        );
        final request2 = TrustedTimestamp.createTimestampRequest(
          merkleRoot: merkleRoot,
        );

        expect(request1, equals(request2),
            reason:
                'Same Merkle root should produce same timestamp request');
      });

      test('different Merkle roots produce different requests', () {
        final root1 = Uint8List.fromList(
          sha256.convert(utf8.encode('root-1')).bytes,
        );
        final root2 = Uint8List.fromList(
          sha256.convert(utf8.encode('root-2')).bytes,
        );

        final request1 = TrustedTimestamp.createTimestampRequest(
          merkleRoot: root1,
        );
        final request2 = TrustedTimestamp.createTimestampRequest(
          merkleRoot: root2,
        );

        expect(request1, isNot(equals(request2)),
            reason:
                'Different Merkle roots should produce different requests');
      });
    });

    group('createTimestampBlock', () {
      test('returns complete JSON', () {
        final merkleRoot = _testMerkleRoot();
        final tsaUrl = 'https://freetsa.org/tsr';

        final block = TrustedTimestamp.createTimestampBlock(
          merkleRoot: merkleRoot,
          tsaUrl: tsaUrl,
        );

        expect(block, isNotNull);
        expect(block, isA<Map<String, dynamic>>());
      });

      test('timestamp block includes tsa_url', () {
        final merkleRoot = _testMerkleRoot();
        final tsaUrl = 'https://timestamp.digicert.com';

        final block = TrustedTimestamp.createTimestampBlock(
          merkleRoot: merkleRoot,
          tsaUrl: tsaUrl,
        );

        expect(block['tsa_url'], equals(tsaUrl));
      });

      test('timestamp block includes merkle_root_hex', () {
        final merkleRoot = _testMerkleRoot();
        final tsaUrl = 'https://freetsa.org/tsr';

        final block = TrustedTimestamp.createTimestampBlock(
          merkleRoot: merkleRoot,
          tsaUrl: tsaUrl,
        );

        expect(block.containsKey('merkle_root_hex'), isTrue);
        final rootHex = block['merkle_root_hex'] as String;
        expect(rootHex.length, equals(64),
            reason: 'Merkle root hex should be 64 characters (32 bytes)');
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(rootHex), isTrue,
            reason: 'Merkle root hex should be lowercase hex');
      });

      test('timestamp block includes current timestamp', () {
        final merkleRoot = _testMerkleRoot();
        final tsaUrl = 'https://freetsa.org/tsr';

        final beforeEpoch =
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

        final block = TrustedTimestamp.createTimestampBlock(
          merkleRoot: merkleRoot,
          tsaUrl: tsaUrl,
        );

        final afterEpoch =
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

        expect(block.containsKey('timestamp'), isTrue);
        final timestamp = block['timestamp'] as int;
        expect(timestamp, greaterThanOrEqualTo(beforeEpoch));
        expect(timestamp, lessThanOrEqualTo(afterEpoch));
      });

      test('timestamp block includes version', () {
        final merkleRoot = _testMerkleRoot();
        final block = TrustedTimestamp.createTimestampBlock(
          merkleRoot: merkleRoot,
          tsaUrl: 'https://freetsa.org/tsr',
        );

        expect(block.containsKey('version'), isTrue);
        expect(block['version'], equals(1));
      });

      test('timestamp block can be JSON-serialized', () {
        final merkleRoot = _testMerkleRoot();
        final block = TrustedTimestamp.createTimestampBlock(
          merkleRoot: merkleRoot,
          tsaUrl: 'https://freetsa.org/tsr',
        );

        // Should not throw
        final json = jsonEncode(block);
        expect(json, isNotEmpty);

        // Should round-trip
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        expect(decoded['tsa_url'], equals(block['tsa_url']));
        expect(decoded['merkle_root_hex'], equals(block['merkle_root_hex']));
      });

      test('timestamp block includes optional response token when provided', () {
        final merkleRoot = _testMerkleRoot();
        final mockResponseToken = Uint8List.fromList(
          List.generate(64, (i) => i),
        );

        final block = TrustedTimestamp.createTimestampBlock(
          merkleRoot: merkleRoot,
          tsaUrl: 'https://freetsa.org/tsr',
          responseToken: mockResponseToken,
        );

        expect(block.containsKey('response_token_hex'), isTrue);
        final tokenHex = block['response_token_hex'] as String;
        expect(tokenHex.length, equals(128),
            reason: 'Token hex should be 128 chars for 64 bytes');
      });
    });

    group('timestamp in sealed files', () {
      test('sealed file with timestamp flag', () {
        final content = Uint8List.fromList(utf8.encode('Timestamped doc'));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'timestamped.txt',
          salt: _zeroSalt(),
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        // Get the Merkle root from the sealed file
        final inspection = ZegelReader.inspect(fileBytes);
        expect(inspection, isNotNull);

        // Create a timestamp block for this file
        final tsBlock = TrustedTimestamp.createTimestampBlock(
          merkleRoot: inspection.merkleRoot!,
          tsaUrl: 'https://freetsa.org/tsr',
        );
        expect(tsBlock['merkle_root_hex'], isNotNull);
      });
    });
  });
}
