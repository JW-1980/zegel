import 'dart:typed_data';

/// Strips embedded metadata from common file formats (improvement #78).
///
/// Before a file is sealed, users may want to remove embedded metadata
/// (EXIF tags from JPEGs, author/last-modified from Office documents,
/// etc.) so the sealed version contains only the intentional content.
///
/// This is a conservative, format-aware implementation: it only touches
/// formats it recognises and leaves everything else untouched. For
/// unknown formats the bytes are returned as-is and `stripped` is false.
class MetadataStripper {
  MetadataStripper._();

  /// Removes all `APPn` marker segments from a JPEG (including EXIF,
  /// ICC profiles, XMP). Other marker segments (SOF, SOS, DQT, DHT)
  /// are preserved.
  static StripResult stripJpeg(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return StripResult(bytes: bytes, stripped: false, removedBytes: 0);
    }
    final out = BytesBuilder()
      ..addByte(0xFF)
      ..addByte(0xD8);
    var removed = 0;
    var i = 2;
    while (i < bytes.length - 1) {
      if (bytes[i] != 0xFF) {
        out.add(bytes.sublist(i));
        break;
      }
      final marker = bytes[i + 1];

      // Start of Scan: append the remainder and stop.
      if (marker == 0xDA) {
        out.add(bytes.sublist(i));
        break;
      }
      // End of Image.
      if (marker == 0xD9) {
        out
          ..addByte(0xFF)
          ..addByte(0xD9);
        i += 2;
        break;
      }
      // Standalone markers (no length).
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        out
          ..addByte(0xFF)
          ..addByte(marker);
        i += 2;
        continue;
      }
      if (i + 4 > bytes.length) break;
      final length = (bytes[i + 2] << 8) | bytes[i + 3];
      if (i + 2 + length > bytes.length) break;
      final isAppMarker = marker >= 0xE0 && marker <= 0xEF;
      final isComment = marker == 0xFE;
      if (isAppMarker || isComment) {
        removed += length + 2;
      } else {
        out.add(bytes.sublist(i, i + 2 + length));
      }
      i += 2 + length;
    }
    return StripResult(
      bytes: out.toBytes(),
      stripped: removed > 0,
      removedBytes: removed,
    );
  }

  /// Removes the 'tEXt', 'iTXt', 'zTXt' and 'tIME' chunks from a PNG
  /// file. Other chunks (IHDR, IDAT, IEND, PLTE, etc.) are preserved.
  static StripResult stripPng(Uint8List bytes) {
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    if (bytes.length < 8) {
      return StripResult(bytes: bytes, stripped: false, removedBytes: 0);
    }
    for (var j = 0; j < 8; j++) {
      if (bytes[j] != signature[j]) {
        return StripResult(bytes: bytes, stripped: false, removedBytes: 0);
      }
    }
    final out = BytesBuilder()..add(signature);
    var removed = 0;
    var i = 8;
    while (i + 8 <= bytes.length) {
      final length = (bytes[i] << 24) |
          (bytes[i + 1] << 16) |
          (bytes[i + 2] << 8) |
          bytes[i + 3];
      final type = String.fromCharCodes(bytes.sublist(i + 4, i + 8));
      final chunkEnd = i + 8 + length + 4;
      if (chunkEnd > bytes.length) break;
      const stripTypes = {'tEXt', 'iTXt', 'zTXt', 'tIME'};
      if (stripTypes.contains(type)) {
        removed += chunkEnd - i;
      } else {
        out.add(bytes.sublist(i, chunkEnd));
      }
      i = chunkEnd;
      if (type == 'IEND') break;
    }
    return StripResult(
      bytes: out.toBytes(),
      stripped: removed > 0,
      removedBytes: removed,
    );
  }

  /// Dispatches to the appropriate format-specific stripper based on
  /// magic bytes. Returns the original bytes unchanged for unknown
  /// formats.
  static StripResult stripAny(Uint8List bytes) {
    if (bytes.length >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return stripJpeg(bytes);
    }
    if (bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71) {
      return stripPng(bytes);
    }
    return StripResult(bytes: bytes, stripped: false, removedBytes: 0);
  }
}

class StripResult {
  const StripResult({
    required this.bytes,
    required this.stripped,
    required this.removedBytes,
  });

  final Uint8List bytes;
  final bool stripped;
  final int removedBytes;
}
