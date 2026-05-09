import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('MetadataStripper', () {
    test('stripJpeg returns the original for non-JPEG inputs', () {
      final result = MetadataStripper.stripJpeg(
        Uint8List.fromList(<int>[0, 1, 2, 3]),
      );
      expect(result.stripped, isFalse);
      expect(result.removedBytes, 0);
    });

    test('stripJpeg removes APP1 (EXIF) segments', () {
      // Minimal JPEG: SOI + APP1 (len=6, 4 bytes payload) + EOI
      final bytes = Uint8List.fromList(<int>[
        0xFF, 0xD8, // SOI
        0xFF, 0xE1, // APP1
        0x00, 0x06, // length = 6 (includes these 2 bytes)
        0xAA, 0xBB, 0xCC, 0xDD,
        0xFF, 0xD9, // EOI
      ]);
      final result = MetadataStripper.stripJpeg(bytes);
      expect(result.stripped, isTrue);
      expect(result.removedBytes, 8);
      // Result should be SOI + EOI.
      expect(result.bytes, <int>[0xFF, 0xD8, 0xFF, 0xD9]);
    });

    test('stripPng removes tEXt chunks but preserves IHDR/IEND', () {
      // Build a minimal PNG: signature + minimal IHDR block + tEXt + IEND.
      // Real CRCs aren't validated by the stripper so we can use zeros.
      int b(int v) => v & 0xFF;
      final chunk = <int>[];

      void addChunk(List<int> data, String type) {
        chunk.addAll(<int>[
          b(data.length >> 24),
          b(data.length >> 16),
          b(data.length >> 8),
          b(data.length),
          type.codeUnitAt(0),
          type.codeUnitAt(1),
          type.codeUnitAt(2),
          type.codeUnitAt(3),
          ...data,
          0, 0, 0, 0, // CRC
        ]);
      }

      final all = <int>[137, 80, 78, 71, 13, 10, 26, 10];
      chunk.clear();
      addChunk(<int>[0, 0, 0, 1, 0, 0, 0, 1, 8, 0, 0, 0, 0], 'IHDR');
      all.addAll(chunk);
      chunk.clear();
      addChunk(<int>[0x41, 0x42], 'tEXt');
      all.addAll(chunk);
      chunk.clear();
      addChunk(<int>[], 'IEND');
      all.addAll(chunk);

      final result = MetadataStripper.stripPng(Uint8List.fromList(all));
      expect(result.stripped, isTrue);
      expect(result.removedBytes, 14); // 4 length + 4 type + 2 data + 4 crc
      final output = result.bytes;
      // Find that the tEXt marker is absent from the output.
      var hasText = false;
      for (var i = 0; i < output.length - 3; i++) {
        if (output[i] == 0x74 &&
            output[i + 1] == 0x45 &&
            output[i + 2] == 0x58 &&
            output[i + 3] == 0x74) {
          hasText = true;
          break;
        }
      }
      expect(hasText, isFalse);
    });

    test('stripAny dispatches based on magic bytes', () {
      final jpegResult = MetadataStripper.stripAny(
        Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD9]),
      );
      expect(jpegResult.stripped, isFalse);
      expect(jpegResult.removedBytes, 0);

      final unknown = MetadataStripper.stripAny(
        Uint8List.fromList(<int>[1, 2, 3, 4]),
      );
      expect(unknown.stripped, isFalse);
    });
  });
}
