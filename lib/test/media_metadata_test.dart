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

void main() {
  group('MediaMetadata', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    group('createGpsMetadata', () {
      test('returns correct structure', () {
        final gps = MediaMetadata.createGpsMetadata(
          latitude: 52.3676,
          longitude: 4.9041,
        );

        expect(gps, isA<Map<String, dynamic>>());
        expect(gps.containsKey('gps'), isTrue);
        expect(gps['gps'], isA<Map<String, dynamic>>());
      });

      test('GPS metadata includes latitude and longitude', () {
        final gps = MediaMetadata.createGpsMetadata(
          latitude: 48.8566,
          longitude: 2.3522,
        );

        final gpsData = gps['gps'] as Map<String, dynamic>;
        expect(gpsData['latitude'], closeTo(48.8566, 0.0001));
        expect(gpsData['longitude'], closeTo(2.3522, 0.0001));
      });

      test('GPS metadata includes optional altitude', () {
        final gps = MediaMetadata.createGpsMetadata(
          latitude: 46.8182,
          longitude: 8.2275,
          altitude: 1450.0,
        );

        final gpsData = gps['gps'] as Map<String, dynamic>;
        expect(gpsData['altitude'], closeTo(1450.0, 0.01));
      });

      test('GPS metadata includes optional timestamp', () {
        final captureTime = DateTime.utc(2026, 1, 15, 14, 30, 0);
        final gps = MediaMetadata.createGpsMetadata(
          latitude: 40.7128,
          longitude: -74.0060,
          timestamp: captureTime,
        );

        final gpsData = gps['gps'] as Map<String, dynamic>;
        expect(gpsData.containsKey('timestamp'), isTrue);
        // Timestamp should be stored as ISO 8601 string or epoch seconds
        final storedTimestamp = gpsData['timestamp'];
        expect(storedTimestamp, isNotNull);
      });

      test('GPS metadata without optional fields omits them', () {
        final gps = MediaMetadata.createGpsMetadata(
          latitude: 35.6762,
          longitude: 139.6503,
        );

        final gpsData = gps['gps'] as Map<String, dynamic>;
        expect(gpsData.containsKey('latitude'), isTrue);
        expect(gpsData.containsKey('longitude'), isTrue);
        // Altitude and timestamp should not be present when not provided
        expect(gpsData.containsKey('altitude'), isFalse);
        expect(gpsData.containsKey('timestamp'), isFalse);
      });

      test('GPS metadata handles negative coordinates (Southern/Western hemisphere)', () {
        final gps = MediaMetadata.createGpsMetadata(
          latitude: -33.8688,
          longitude: -151.2093, // Note: this is actually positive but testing negative
        );

        final gpsData = gps['gps'] as Map<String, dynamic>;
        expect(gpsData['latitude'], closeTo(-33.8688, 0.0001));
        expect(gpsData['longitude'], closeTo(-151.2093, 0.0001));
      });

      test('GPS metadata handles zero coordinates', () {
        final gps = MediaMetadata.createGpsMetadata(
          latitude: 0.0,
          longitude: 0.0,
        );

        final gpsData = gps['gps'] as Map<String, dynamic>;
        expect(gpsData['latitude'], equals(0.0));
        expect(gpsData['longitude'], equals(0.0));
      });
    });

    group('extractFromFile', () {
      test('handles JPEG content type', () {
        // Simulate JPEG content (just the magic bytes for test purposes)
        final content =
            Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
        final gps = MediaMetadata.createGpsMetadata(
          latitude: 52.3676,
          longitude: 4.9041,
          altitude: 10.5,
        );
        final options = ZegelOptions(
          contentType: 'image/jpeg',
          filename: 'photo.jpg',
          salt: _zeroSalt(),
          metadata: gps,
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        final extracted = MediaMetadata.extractFromFile(
          fileBytes: fileBytes,
          masterKey: masterKey,
        );

        expect(extracted, isNotNull);
        expect(extracted!.containsKey('gps'), isTrue);
        final gpsData = extracted['gps'] as Map<String, dynamic>;
        expect(gpsData['latitude'], closeTo(52.3676, 0.0001));
        expect(gpsData['longitude'], closeTo(4.9041, 0.0001));
      });

      test('handles unknown content type gracefully', () {
        final content = Uint8List.fromList([0x00, 0x01, 0x02, 0x03]);
        final options = ZegelOptions(
          contentType: 'application/x-unknown-format',
          filename: 'mystery.dat',
          salt: _zeroSalt(),
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        // Should return null or empty metadata for unknown content type
        // with no metadata block
        final extracted = MediaMetadata.extractFromFile(
          fileBytes: fileBytes,
          masterKey: masterKey,
        );

        // Either null (no media metadata found) or an empty map is acceptable
        expect(
          extracted == null || extracted.isEmpty,
          isTrue,
          reason:
              'Unknown content type without metadata should return null or empty',
        );
      });

      test('handles file with metadata but no GPS data', () {
        final content = Uint8List.fromList(utf8.encode('Text document'));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'doc.txt',
          salt: _zeroSalt(),
          metadata: {'author': 'Alice', 'version': 1},
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        final extracted = MediaMetadata.extractFromFile(
          fileBytes: fileBytes,
          masterKey: masterKey,
        );

        // Should either return null or not contain GPS data
        if (extracted != null) {
          expect(extracted.containsKey('gps'), isFalse,
              reason: 'Text file should not have GPS metadata');
        }
      });
    });

    group('GPS metadata in sealed files', () {
      test('GPS metadata survives seal/extract roundtrip', () {
        final content = Uint8List.fromList([0xFF, 0xD8, 0xFF]);
        final gps = MediaMetadata.createGpsMetadata(
          latitude: 51.5074,
          longitude: -0.1278,
          altitude: 30.0,
          timestamp: DateTime.utc(2026, 3, 15, 10, 0, 0),
        );
        final options = ZegelOptions(
          contentType: 'image/jpeg',
          filename: 'london.jpg',
          salt: _zeroSalt(),
          metadata: gps,
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        final result = ZegelReader.extract(fileBytes, masterKey);
        expect(result.valid, isTrue);
        expect(result.metadata, isNotNull);
        expect(result.metadata!.containsKey('gps'), isTrue);

        final gpsData = result.metadata!['gps'] as Map<String, dynamic>;
        expect(gpsData['latitude'], closeTo(51.5074, 0.0001));
        expect(gpsData['longitude'], closeTo(-0.1278, 0.0001));
        expect(gpsData['altitude'], closeTo(30.0, 0.01));
      });
    });
  });
}
