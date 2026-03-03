import re

with open("app/lib/services/zegel_service.dart", "r") as f:
    content = f.read()

hex_method = """
  // ======================================================================
  // Private Helpers
  // ======================================================================

  /// Converts a hex string to bytes.
  static Uint8List _hexToBytes(String hex) {
    final int length = hex.length ~/ 2;
    final Uint8List bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
"""

if "_hexToBytes" not in content:
    content = content.rstrip()
    if content.endswith("}"):
        content = content[:-1] + hex_method

    with open("app/lib/services/zegel_service.dart", "w") as f:
        f.write(content)
    print("Method added")
else:
    print("Method already exists")
