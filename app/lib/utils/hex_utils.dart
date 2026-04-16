import 'dart:typed_data';

/// Utility class for hex conversions.
class HexUtils {
  /// Converts a hex string to a Uint8List.
  static Uint8List hexToBytes(String hex) {
    final length = hex.length ~/ 2;
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
