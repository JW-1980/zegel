import 'dart:math';
import 'dart:typed_data';

/// Secure memory wiping helpers (improvement #54).
///
/// Dart does not give us raw control over memory, but we can still make a
/// best-effort attempt to overwrite sensitive buffers before their storage
/// is released. The utilities here clear typed byte buffers using a random
/// overwrite followed by a zero pass, and support the common "copy into a
/// caller-owned buffer, wipe the source" pattern.
///
/// These routines are intended for keys, passwords, and other secret
/// material — not for large blobs. They are deliberately simple so callers
/// can audit them.
class SecureMemory {
  SecureMemory._();

  /// Overwrites [buffer] with random bytes then with zeros.
  ///
  /// The buffer is modified in place. Returns the same buffer for chaining.
  /// Throws [UnsupportedError] if the buffer is unmodifiable (e.g. a view
  /// backed by a ByteData of length 0).
  static Uint8List wipe(Uint8List buffer) {
    if (buffer.isEmpty) return buffer;
    final rng = Random.secure();
    for (var i = 0; i < buffer.length; i++) {
      buffer[i] = rng.nextInt(256);
    }
    for (var i = 0; i < buffer.length; i++) {
      buffer[i] = 0;
    }
    return buffer;
  }

  /// Wipes every buffer in [buffers].
  static void wipeAll(Iterable<Uint8List> buffers) {
    for (final buf in buffers) {
      wipe(buf);
    }
  }

  /// Allocates a fresh buffer with the contents of [source] and wipes
  /// [source] before returning.
  ///
  /// This is useful when a secret is loaded into a temporary buffer (e.g.
  /// from a file) and the ownership should be transferred to a long-lived
  /// location while erasing the original.
  static Uint8List takeAndWipe(Uint8List source) {
    final copy = Uint8List.fromList(source);
    wipe(source);
    return copy;
  }

  /// Compares [a] and [b] in constant time for the length of the shorter
  /// buffer; differing lengths always return false. This avoids revealing
  /// information through timing side channels when used to match secret
  /// material (e.g. password hashes).
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Returns a new buffer with random bytes of the given [length].
  static Uint8List randomBytes(int length) {
    if (length < 0) {
      throw ArgumentError.value(length, 'length', 'must be non-negative');
    }
    final rng = Random.secure();
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = rng.nextInt(256);
    }
    return out;
  }
}
