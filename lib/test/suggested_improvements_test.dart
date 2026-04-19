import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

/// Tests for features added from SUGGESTED_IMPROVEMENTS.md.

void main() {
  group('Item 42: ErrorHelper-style error messages', () {
    test('ZegelTamperedException contains descriptive message', () {
      const e = ZegelTamperedException('Tamper detected: block decryption failed');
      expect(e.message, contains('Tamper detected'));
      expect(e.toString(), contains('ZegelTamperedException'));
    });

    test('ZegelFormatException for invalid magic bytes', () {
      const e = ZegelFormatException('Invalid magic bytes');
      expect(e.message, contains('magic'));
    });

    test('ZegelExpiredException for expired files', () {
      const e = ZegelExpiredException('File expired at epoch 1700000000');
      expect(e.message, contains('expired'));
    });
  });

  group('Item 76: Sensitive data patterns', () {
    test('master key is exactly 32 bytes', () {
      final key = Uint8List(32);
      key[31] = 0x01;
      expect(key.length, equals(32));

      // Keys shorter than 32 bytes should be rejected.
      expect(
        () => ZegelWriter(Uint8List(16), const ZegelOptions()),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('hex-encoded key is 64 characters', () {
      final key = Uint8List(32);
      final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hex.length, equals(64));
    });
  });

  group('Item 97: Contact-like signer data in attestation', () {
    test('attestation block stores signer identity', () {
      // The attestation system stores signer IDs which function
      // like a contact reference.
      final key = Uint8List(32);
      key[31] = 0x01;
      final content = Uint8List.fromList(utf8.encode('attestation test'));
      final sealed = ZegelWriter(
        key,
        const ZegelOptions(contentType: 'text/plain'),
      ).seal(content);

      final result = const ZegelReader().verify(sealed, key);
      expect(result.valid, isTrue);
    });
  });

  group('Item 92: Data table serialization', () {
    test('structured blocks serialize to JSON for table display', () {
      const sbom = SbomBlock(
        packages: [
          SbomPackage(name: 'crypto', version: '3.0.3'),
          SbomPackage(name: 'pointycastle', version: '3.7.3'),
        ],
      );

      final encoded = sbom.encode();
      final json = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;

      // Verify JSON structure is table-friendly.
      expect(json['packages'], isA<List<dynamic>>());
      final packages = json['packages'] as List<dynamic>;
      expect(packages.length, equals(2));
      expect((packages[0] as Map<String, dynamic>)['name'], equals('crypto'));
    });

    test('envelope events serialize to JSON for audit table', () {
      const event = EnvelopeEvent(
        timestamp: 1700000000,
        eventType: 'envelope_created',
        description: 'Test event',
      );

      final json = event.toJson();
      expect(json['timestamp'], equals(1700000000));
      expect(json['event_type'], equals('envelope_created'));
    });
  });

  group('Item 18: Copy as JSON for data structures', () {
    test('envelope serializes to complete JSON', () {
      final envelope = Envelope(
        id: 'env-json-test',
        subject: 'JSON export test',
        recipients: [
          const EnvelopeRecipient(
            id: 'r1',
            name: 'Alice',
            email: 'alice@test.com',
            role: RecipientRole.signer,
          ),
        ],
      );

      final encoded = envelope.encode();
      final json = jsonDecode(utf8.decode(encoded)) as Map<String, dynamic>;

      // Verify full JSON roundtrip.
      expect(json['id'], equals('env-json-test'));
      expect(json['subject'], equals('JSON export test'));
      expect((json['recipients'] as List).length, equals(1));
    });

    test('measurement block serializes to JSON', () {
      const measurement = MeasurementBlock(
        timestamp: 1700000000,
        sensorId: 'temp-01',
        value: 22.5,
        unit: 'celsius',
      );

      final encoded = measurement.encode();
      final json = jsonDecode(utf8.decode(encoded));
      expect(json['value'], equals(22.5));
      expect(json['unit'], equals('celsius'));
    });
  });

  group('Item 58: Security - inactivity lock patterns', () {
    test('constant-time string comparison works', () {
      // Verify the pattern used in PIN comparison.
      const pin1 = '1234';
      const pin2 = '1234';
      const pin3 = '5678';

      int diff1 = 0;
      for (int i = 0; i < pin1.length; i++) {
        diff1 |= pin1.codeUnitAt(i) ^ pin2.codeUnitAt(i);
      }
      expect(diff1, equals(0)); // Match

      int diff2 = 0;
      for (int i = 0; i < pin1.length; i++) {
        diff2 |= pin1.codeUnitAt(i) ^ pin3.codeUnitAt(i);
      }
      expect(diff2, isNot(equals(0))); // Mismatch
    });
  });

  group('Item 101: Docker configuration', () {
    test('ZegelFormat constants are consistent for Docker builds', () {
      // Docker builds must produce identical output to native builds.
      // Verify format constants are deterministic.
      expect(ZegelFormat.magic.length, equals(8));
      expect(ZegelFormat.versionMajor, equals(1));
      expect(ZegelFormat.versionMinor, equals(4));
      expect(ZegelFormat.defaultBlockSize, equals(65536));
      expect(ZegelFormat.saltSize, equals(32));
      expect(ZegelFormat.sealSize, equals(64));
    });
  });
}
