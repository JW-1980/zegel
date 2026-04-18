import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// RFC 6238 TOTP (Time-based One-Time Passwords) implementation
/// (improvement #56).
///
/// The Flutter app and CLI can sit in front of sensitive operations
/// (e.g. unsealing a TOP SECRET file) with a second-factor prompt
/// backed by an authenticator app such as Google Authenticator or
/// 1Password. This class provides:
/// - [Totp.generate] to produce the current code from a shared secret
/// - [Totp.verify] to check a user-entered code with optional drift
/// - [Totp.provisioningUri] to emit the `otpauth://` URI a QR scanner
///   can import.
///
/// Only HMAC-SHA1 is implemented (the RFC 6238 default used by every
/// mainstream authenticator). Callers should use [period] = 30 and
/// [digits] = 6 unless they have a specific reason not to.
class Totp {
  const Totp({required this.secret, this.digits = 6, this.period = 30});

  /// The shared secret (raw bytes before base32 encoding).
  final Uint8List secret;

  /// Number of digits in the generated code.
  final int digits;

  /// Period in seconds between new codes.
  final int period;

  /// Base32-encodes the raw secret for display in auth apps / QR codes.
  String encodedSecret() => _base32Encode(secret);

  /// Generates the TOTP code valid at [now] (defaults to current time).
  String generate({DateTime? now}) {
    final t = (now ?? DateTime.now()).toUtc();
    final counter = t.millisecondsSinceEpoch ~/ 1000 ~/ period;
    return _hotp(secret, counter, digits: digits);
  }

  /// Verifies [code] against the expected code for [now], allowing a
  /// symmetric drift of [window] periods (default: 1, i.e. ±30 s).
  bool verify(String code, {DateTime? now, int window = 1}) {
    final t = (now ?? DateTime.now()).toUtc();
    final counter = t.millisecondsSinceEpoch ~/ 1000 ~/ period;
    for (var offset = -window; offset <= window; offset++) {
      final expected = _hotp(secret, counter + offset, digits: digits);
      if (_constantTimeEquals(code, expected)) return true;
    }
    return false;
  }

  /// Returns the `otpauth://` URI suitable for encoding into a QR code.
  Uri provisioningUri({required String accountName, required String issuer}) {
    return Uri(
      scheme: 'otpauth',
      host: 'totp',
      path: '/$issuer:$accountName',
      queryParameters: <String, String>{
        'secret': encodedSecret(),
        'issuer': issuer,
        'algorithm': 'SHA1',
        'digits': '$digits',
        'period': '$period',
      },
    );
  }

  static String _hotp(Uint8List secret, int counter, {required int digits}) {
    // Convert counter to 8-byte big-endian.
    final counterBytes = Uint8List(8);
    var remaining = counter;
    for (var i = 7; i >= 0; i--) {
      counterBytes[i] = remaining & 0xFF;
      remaining >>= 8;
    }
    final hmac = Hmac(sha1, secret);
    final digest = hmac.convert(counterBytes).bytes;
    final offset = digest.last & 0x0F;
    final binary =
        ((digest[offset] & 0x7F) << 24) |
        ((digest[offset + 1] & 0xFF) << 16) |
        ((digest[offset + 2] & 0xFF) << 8) |
        (digest[offset + 3] & 0xFF);
    final modulus = _pow10(digits);
    return (binary % modulus).toString().padLeft(digits, '0');
  }

  static int _pow10(int exp) {
    var result = 1;
    for (var i = 0; i < exp; i++) {
      result *= 10;
    }
    return result;
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Parses a base32 string into raw bytes.
  static Uint8List parseBase32(String input) {
    return Uint8List.fromList(_base32Decode(input));
  }

  static const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static String _base32Encode(Uint8List bytes) {
    final sb = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in bytes) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        sb.write(_base32Alphabet[(buffer >> bits) & 0x1F]);
      }
    }
    if (bits > 0) {
      sb.write(_base32Alphabet[(buffer << (5 - bits)) & 0x1F]);
    }
    return sb.toString();
  }

  static List<int> _base32Decode(String input) {
    final cleaned = input.toUpperCase().replaceAll(RegExp(r'[^A-Z2-7]'), '');
    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final ch in cleaned.codeUnits) {
      final idx = _base32Alphabet.indexOf(String.fromCharCode(ch));
      if (idx < 0) {
        throw FormatException(
          'Invalid base32 character: ${String.fromCharCode(ch)}',
        );
      }
      buffer = (buffer << 5) | idx;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xFF);
      }
    }
    return out;
  }
}
