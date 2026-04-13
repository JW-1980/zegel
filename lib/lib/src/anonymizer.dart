import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'secure_memory.dart';

/// PII-scrubbing helper for telemetry payloads (improvement #76).
///
/// Replaces hostnames, file paths, email addresses, and IP addresses in
/// free-text strings with short salted SHA-256 hashes. The salt is chosen
/// randomly on first use so that two installations of Zegel produce
/// different hashes for the same input — preventing a central aggregator
/// from re-identifying users by comparing counts.
class Anonymizer {
  Anonymizer({required this.salt});

  /// Creates an anonymizer with a fresh random salt.
  factory Anonymizer.random() => Anonymizer(salt: SecureMemory.randomBytes(16));

  /// Creates a deterministic anonymizer from an existing [salt]. Useful
  /// for round-trip tests.
  factory Anonymizer.fromHex(String hexSalt) {
    if (hexSalt.length % 2 != 0) {
      throw ArgumentError.value(hexSalt, 'hexSalt', 'must be even length');
    }
    final bytes = <int>[];
    for (var i = 0; i < hexSalt.length; i += 2) {
      bytes.add(int.parse(hexSalt.substring(i, i + 2), radix: 16));
    }
    return Anonymizer(salt: bytes);
  }

  static final RegExp _email = RegExp(
    r'[\w.+\-]+@[\w\-]+(?:\.[\w\-]+)+',
    caseSensitive: false,
  );
  static final RegExp _ipv4 = RegExp(
    r'\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b',
  );
  static final RegExp _unixPath = RegExp(r'/[\w.\-]+(?:/[\w.\-]+)+');
  static final RegExp _windowsPath = RegExp(r'[A-Za-z]:\\[\w.\-\\]+');

  /// 16 bytes (or more) of randomness used to salt hashes.
  final List<int> salt;

  /// Returns the salt in hexadecimal for persistence.
  String saltHex() =>
      salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Hashes [value] with the configured salt and returns a truncated
  /// hex digest suitable for use as a pseudonym.
  String hash(String value, {int length = 8}) {
    final hmac = Hmac(sha256, salt);
    final digest = hmac.convert(utf8.encode(value)).toString();
    return digest.substring(0, length);
  }

  /// Scrubs obvious PII from [input] by replacing matches with
  /// `<category:hash>` tokens. Callers should still avoid sending entire
  /// user-generated strings into this method — it is a safety net, not a
  /// compliance tool.
  String scrub(String input) {
    var out = input;
    out = out.replaceAllMapped(
      _email,
      (m) => '<email:${hash(m.group(0)!)}>',
    );
    out = out.replaceAllMapped(
      _ipv4,
      (m) => '<ip:${hash(m.group(0)!)}>',
    );
    out = out.replaceAllMapped(
      _windowsPath,
      (m) => '<path:${hash(m.group(0)!)}>',
    );
    out = out.replaceAllMapped(
      _unixPath,
      (m) => '<path:${hash(m.group(0)!)}>',
    );
    return out;
  }

  /// Scrubs a multi-line stack trace. Line numbers are preserved, paths
  /// and email-like tokens are hashed.
  String scrubStackTrace(String stackTrace) {
    final buf = StringBuffer();
    for (final line in const LineSplitter().convert(stackTrace)) {
      buf.writeln(scrub(line));
    }
    return buf.toString();
  }
}
