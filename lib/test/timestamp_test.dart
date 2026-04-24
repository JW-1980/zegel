// ignore_for_file: deprecated_member_use_from_same_package
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
        final request = TrustedTimestamp.createRequest(merkleRoot, masterSeal);

        expect(request, isNotNull);
        expect(
          request,
          isNotEmpty,
          reason: 'Timestamp request should be non-empty',
        );
      });

      test('request contains required fields', () {
        final merkleRoot = _testMerkleRoot();
        final masterSeal = _testMasterSeal();
        final request = TrustedTimestamp.createRequest(merkleRoot, masterSeal);

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
        expect(
          rootHex.length,
          equals(64),
          reason: 'Merkle root hex should be 64 characters (32 bytes)',
        );
        expect(
          RegExp(r'^[0-9a-f]+$').hasMatch(rootHex),
          isTrue,
          reason: 'Merkle root hex should be lowercase hex',
        );
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
        expect(
          sigHex.length,
          equals(64),
          reason: 'Signature hex should be 64 chars for HMAC-SHA256',
        );
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
        expect(
          isValid,
          isTrue,
          reason: 'Valid local token should pass verification',
        );
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
        expect(
          isValid,
          isFalse,
          reason: 'Token signed with different key should fail verification',
        );
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

  // ===========================================================================
  // v1.3 Timestamp anchoring tests
  // ===========================================================================

  group('TimestampBlockData serialization', () {
    test('roundtrip encode/decode preserves protocol and payload', () {
      final payload =
          Uint8List.fromList(utf8.encode('{"protocol":"roughtime"}'));
      final data = TimestampBlockData(
        protocol: TimestampProtocol.roughtime,
        payload: payload,
        verifiedTime: const VerifiedCreationTime(selfAsserted: false),
      );

      final bytes = data.toBytes();
      expect(bytes[0], 1); // roughtime wire value
      final bd = ByteData.sublistView(bytes);
      expect(bd.getUint32(1, Endian.big), payload.length);
      expect(bytes.sublist(5), payload);
    });

    test('protocol wire values match spec', () {
      expect(TimestampProtocol.roughtime.wireValue, 1);
      expect(TimestampProtocol.rfc3161.wireValue, 2);
      expect(TimestampProtocol.localHmac.wireValue, 3);
    });

    test('fromWireValue round-trips', () {
      for (final p in TimestampProtocol.values) {
        expect(TimestampProtocol.fromWireValue(p.wireValue), p);
      }
    });

    test('unknown wire value throws', () {
      expect(
        () => TimestampProtocol.fromWireValue(99),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('VerifiedCreationTime', () {
    test('self-asserted toJson', () {
      const vct = VerifiedCreationTime(selfAsserted: true);
      final json = vct.toJson();
      expect(json['self_asserted'], isTrue);
      expect(json.containsKey('not_before'), isFalse);
      expect(json.containsKey('anchor_source'), isFalse);
    });

    test('anchored toJson includes all fields', () {
      final vct = VerifiedCreationTime(
        selfAsserted: false,
        notBefore: DateTime.utc(2026, 4, 19, 10, 0, 0),
        notAfter: DateTime.utc(2026, 4, 19, 10, 0, 5),
        anchorSource: 'Cloudflare Roughtime',
        protocol: TimestampProtocol.roughtime,
      );
      final json = vct.toJson();
      expect(json['self_asserted'], isFalse);
      expect(json['anchor_source'], 'Cloudflare Roughtime');
      expect(json['protocol'], 'roughtime');
      expect(json.containsKey('not_before'), isTrue);
      expect(json.containsKey('not_after'), isTrue);
    });
  });

  group('TrustedTimestamp.computeMessageImprint', () {
    test('produces 32-byte SHA-256 hash', () {
      final imprint = TrustedTimestamp.computeMessageImprint(
        _testMerkleRoot(),
        _testMasterSeal(),
      );
      expect(imprint.length, 32);
    });

    test('different inputs produce different imprints', () {
      final root1 = Uint8List(32)..[0] = 1;
      final root2 = Uint8List(32)..[0] = 2;
      final seal = _testMasterSeal();
      final i1 = TrustedTimestamp.computeMessageImprint(root1, seal);
      final i2 = TrustedTimestamp.computeMessageImprint(root2, seal);
      expect(i1, isNot(equals(i2)));
    });
  });

  group('TimestampConfig', () {
    test('roughtime constructor', () {
      const config = TimestampConfig.roughtime();
      expect(config.protocol, TimestampProtocol.roughtime);
      expect(config.offline, isFalse);
    });

    test('rfc3161 constructor', () {
      final config = TimestampConfig.rfc3161(
        tsaUrl: Uri.parse('https://tsa.example.com'),
      );
      expect(config.protocol, TimestampProtocol.rfc3161);
      expect(config.rfc3161TsaUrl?.host, 'tsa.example.com');
    });

    test('offline constructor', () {
      const config = TimestampConfig.offline();
      expect(config.offline, isTrue);
      expect(config.protocol, isNull);
    });

    test('preObtainedToken constructor', () {
      final config = TimestampConfig.preObtainedToken(
        token: Uint8List.fromList([0x30, 0x00]),
      );
      expect(config.protocol, TimestampProtocol.rfc3161);
      expect(config.preObtainedToken, isNotNull);
    });
  });

  group('Seal/verify integration without timestamp', () {
    test('produces self-asserted creation time', () {
      final key = _testKey();
      final content = Uint8List.fromList(utf8.encode('no timestamp'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        salt: _zeroSalt(),
      );
      final sealed = ZegelWriter(key, options).seal(content);
      final result = const ZegelReader().verify(sealed, key);
      expect(result.valid, isTrue);
      expect(result.verifiedCreationTime, isNotNull);
      expect(result.verifiedCreationTime!.selfAsserted, isTrue);
    });
  });

  group('Seal/verify with pre-obtained token', () {
    test('sets FLAG_HAS_TIMESTAMP and embeds appendix', () {
      final key = _testKey();
      final content = Uint8List.fromList(utf8.encode('timestamped'));
      final fakeToken = _buildFakeRfc3161Token();
      final options = ZegelOptions(
        contentType: 'text/plain',
        salt: _zeroSalt(),
        timestampConfig: TimestampConfig.preObtainedToken(token: fakeToken),
      );
      final sealed = ZegelWriter(key, options).seal(content);
      // NOTE: preObtainedToken creates a TIMESTAMP block during seal(), not an appendix

      // Flag should be set.
      final inspection = const ZegelReader().inspect(sealed);
      expect(inspection.flags & ZegelFormat.flagHasTimestamp, isNot(0));

      // Verify should still work and produce a valid result.
      final result = const ZegelReader().verify(sealed, key);
      expect(result.valid, isTrue);
      expect(utf8.decode(result.content!), 'timestamped');
      expect(result.verifiedCreationTime, isNotNull);
    });
  });

  group('Seal with offline mode', () {
    test('does not set FLAG_HAS_TIMESTAMP', () {
      final key = _testKey();
      final content = Uint8List.fromList(utf8.encode('offline'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        salt: _zeroSalt(),
        timestampConfig: const TimestampConfig.offline(),
      );
      final sealed = ZegelWriter(key, options).seal(content);

      final inspection = const ZegelReader().inspect(sealed);
      expect(inspection.flags & ZegelFormat.flagHasTimestamp, 0);

      final result = const ZegelReader().verify(sealed, key);
      expect(result.valid, isTrue);
      expect(result.verifiedCreationTime!.selfAsserted, isTrue);
    });
  });

  group('Backward compatibility (no timestampConfig)', () {
    test('roundtrip works without timestampConfig', () {
      final key = _testKey();
      final content = Uint8List.fromList(utf8.encode('backward compat'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        salt: _zeroSalt(),
      );
      final sealed = ZegelWriter(key, options).seal(content);
      final result = const ZegelReader().verify(sealed, key);
      expect(result.valid, isTrue);
      expect(utf8.decode(result.content!), 'backward compat');
    });

    test('roundtrip with metadata + compression still works', () {
      final key = _testKey();
      final content = Uint8List.fromList(utf8.encode('compressed + meta'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        salt: _zeroSalt(),
        metadata: {'test': 'value'},
        compress: true,
      );
      final sealed = ZegelWriter(key, options).seal(content);
      final result = const ZegelReader().verify(sealed, key);
      expect(result.valid, isTrue);
      expect(utf8.decode(result.content!), 'compressed + meta');
      expect(result.metadata?['test'], 'value');
    });
  });

  group('Roughtime wire format', () {
    test('encodeMessage / decodeMessage roundtrip', () {
      final tags = [RoughtimeTag(tagNonc, Uint8List(64))];
      final encoded = encodeMessage(tags);
      final decoded = decodeMessage(encoded);
      expect(decoded.containsKey(tagNonc), isTrue);
      expect(decoded[tagNonc]!.length, 64);
    });

    test('empty message roundtrip', () {
      final encoded = encodeMessage([]);
      final decoded = decodeMessage(encoded);
      expect(decoded, isEmpty);
    });

    test('multiple tags preserved', () {
      final tag1 = 0x01000000;
      final tag2 = 0x02000000;
      final tags = [
        RoughtimeTag(tag1, Uint8List.fromList([1, 2, 3])),
        RoughtimeTag(tag2, Uint8List.fromList([4, 5])),
      ];
      final encoded = encodeMessage(tags);
      final decoded = decodeMessage(encoded);
      expect(decoded[tag1], Uint8List.fromList([1, 2, 3]));
      expect(decoded[tag2], Uint8List.fromList([4, 5]));
    });
  });

  group('RoughtimeChain', () {
    test('computes tightest time bounds', () {
      final chain = RoughtimeChain(
        responses: [
          RoughtimeResponse(
            midpoint: DateTime.utc(2026, 4, 19, 10, 0, 0),
            radius: const Duration(seconds: 10),
            serverName: 'A',
            rawResponse: Uint8List(0),
          ),
          RoughtimeResponse(
            midpoint: DateTime.utc(2026, 4, 19, 10, 0, 2),
            radius: const Duration(seconds: 5),
            serverName: 'B',
            rawResponse: Uint8List(0),
          ),
        ],
      );
      // notBefore = max(09:59:50, 09:59:57) = 09:59:57
      expect(chain.notBefore, DateTime.utc(2026, 4, 19, 9, 59, 57));
      // notAfter = min(10:00:10, 10:00:07) = 10:00:07
      expect(chain.notAfter, DateTime.utc(2026, 4, 19, 10, 0, 7));
    });

    test('toJson includes all fields', () {
      final chain = RoughtimeChain(
        responses: [
          RoughtimeResponse(
            midpoint: DateTime.utc(2026, 1, 1),
            radius: const Duration(seconds: 1),
            serverName: 'Test',
            rawResponse: Uint8List(0),
          ),
        ],
      );
      final json = chain.toJson();
      expect(json['protocol'], 'roughtime');
      expect(json['responses'], isA<List>());
      expect(json.containsKey('not_before_us'), isTrue);
      expect(json.containsKey('not_after_us'), isTrue);
    });
  });

  group('verifyTimestampBlock', () {
    test('localHmac returns self-asserted', () {
      final vct = TrustedTimestamp.verifyTimestampBlock(
        TimestampProtocol.localHmac,
        Uint8List(0),
        Uint8List(32),
      );
      expect(vct.selfAsserted, isTrue);
      expect(vct.anchorSource, contains('self-asserted'));
    });

    test('roughtime with valid JSON returns anchored', () {
      final payload = utf8.encode(jsonEncode({
        'protocol': 'roughtime',
        'responses': [
          {
            'server': 'TestServer',
            'midpoint_us': DateTime.utc(2026, 4, 19).microsecondsSinceEpoch,
            'radius_us': 1000000,
          }
        ],
        'not_before_us':
            DateTime.utc(2026, 4, 19).microsecondsSinceEpoch - 1000000,
        'not_after_us':
            DateTime.utc(2026, 4, 19).microsecondsSinceEpoch + 1000000,
      }));

      final vct = TrustedTimestamp.verifyTimestampBlock(
        TimestampProtocol.roughtime,
        Uint8List.fromList(payload),
        Uint8List(32),
      );
      expect(vct.selfAsserted, isFalse);
      expect(vct.anchorSource, contains('TestServer'));
    });

    test('roughtime with invalid JSON returns self-asserted', () {
      final vct = TrustedTimestamp.verifyTimestampBlock(
        TimestampProtocol.roughtime,
        Uint8List.fromList([0, 1, 2, 3]),
        Uint8List(32),
      );
      expect(vct.selfAsserted, isTrue);
    });
  });
}

/// Builds a minimal fake DER structure resembling an RFC 3161 response.
Uint8List _buildFakeRfc3161Token() {
  final genTimeStr = utf8.encode('20260419100000Z');
  final inner = <int>[
    0x18,
    genTimeStr.length,
    ...genTimeStr,
    0x04,
    0x20,
    ...List.filled(32, 0),
  ];
  return Uint8List.fromList([0x30, inner.length, ...inner]);
}
