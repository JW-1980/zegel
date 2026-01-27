import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';

/// ANSI color codes for terminal output.
class Ansi {
  static const String reset = '\x1B[0m';
  static const String bold = '\x1B[1m';
  static const String red = '\x1B[31m';
  static const String green = '\x1B[32m';
  static const String yellow = '\x1B[33m';
  static const String cyan = '\x1B[36m';
  static const String dim = '\x1B[2m';

  static String colorize(String text, String color) => '$color$text$reset';
  static String success(String text) => colorize(text, green);
  static String error(String text) => colorize(text, red);
  static String warning(String text) => colorize(text, yellow);
  static String info(String text) => colorize(text, cyan);
  static String header(String text) => colorize(text, bold);
}

/// Parses a 32-byte key from either a hex string (-k) or a key file (--key-file).
///
/// Throws [UsageException] if neither option is provided or the key is invalid.
Uint8List parseKeyFromArgs(
  dynamic argResults, {
  String keyFlag = 'key',
  String keyFileFlag = 'key-file',
  bool required = true,
}) {
  final String? keyHex = argResults[keyFlag] as String?;
  final String? keyFilePath = argResults[keyFileFlag] as String?;

  if (keyHex != null && keyHex.isNotEmpty) {
    return hexDecode(keyHex, label: 'key');
  }

  if (keyFilePath != null && keyFilePath.isNotEmpty) {
    return readKeyFile(keyFilePath);
  }

  if (required) {
    throw UsageException(
      'A key must be provided via -k <hex> or --key-file <path>.',
      '',
    );
  }

  return Uint8List(0);
}

/// Decodes a hexadecimal string to bytes.
///
/// Expects exactly 64 hex characters for a 32-byte key.
/// Throws [FormatException] if the input is invalid.
Uint8List hexDecode(String hex, {String label = 'value'}) {
  // Strip optional 0x prefix.
  final cleaned = hex.startsWith('0x') || hex.startsWith('0X')
      ? hex.substring(2)
      : hex;

  if (cleaned.length % 2 != 0) {
    throw FormatException(
      'Invalid hex $label: odd number of characters (${cleaned.length}).',
    );
  }

  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleaned)) {
    throw FormatException(
      'Invalid hex $label: contains non-hex characters.',
    );
  }

  final bytes = Uint8List(cleaned.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(cleaned.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

/// Encodes bytes as a lowercase hexadecimal string.
String hexEncode(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Reads a key from a file. Supports raw 32-byte files and hex-encoded files.
Uint8List readKeyFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    throw FileSystemException('Key file not found', path);
  }

  final rawBytes = file.readAsBytesSync();

  // Raw 32-byte key file.
  if (rawBytes.length == 32) {
    return Uint8List.fromList(rawBytes);
  }

  // Hex-encoded key file (64 hex characters, possibly with trailing newline).
  final text = file.readAsStringSync().trim();
  if (text.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(text)) {
    return hexDecode(text, label: 'key file');
  }

  // Base64-encoded key file.
  if (rawBytes.length > 32 && rawBytes.length <= 48) {
    // Likely base64: 32 bytes -> 44 base64 chars + possible padding.
    try {
      final decoded = _base64Decode(text);
      if (decoded.length == 32) {
        return decoded;
      }
    } catch (_) {
      // Not valid base64, fall through to error.
    }
  }

  throw FormatException(
    'Key file must contain exactly 32 raw bytes, 64 hex characters, '
    'or a base64-encoded 32-byte key. Got ${rawBytes.length} bytes.',
  );
}

/// Simple base64 decode without importing dart:convert to keep it contained.
Uint8List _base64Decode(String input) {
  // Use dart:convert through dart:io which re-exports it.
  final codec = const Base64Codec();
  return Uint8List.fromList(codec.decode(input));
}

/// Formats a file size in human-readable form.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Formats a DateTime as an ISO 8601 string.
String formatTimestamp(DateTime dt) {
  return dt.toUtc().toIso8601String().replaceFirst('T', ' ').split('.').first +
      ' UTC';
}

/// Parses a date string in YYYY-MM-DD format to a DateTime.
DateTime parseExpirationDate(String dateStr) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(dateStr);
  if (match == null) {
    throw FormatException(
      'Invalid expiration date format. Expected YYYY-MM-DD, got: $dateStr',
    );
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  return DateTime.utc(year, month, day, 23, 59, 59);
}

/// Adds common key options to an [ArgParser].
void addKeyOptions(ArgParser argParser) {
  argParser.addOption(
    'key',
    abbr: 'k',
    help: 'Master key as a 64-character hex string.',
    valueHelp: 'hex',
  );
  argParser.addOption(
    'key-file',
    help: 'Path to a file containing the master key (raw 32 bytes or hex).',
    valueHelp: 'path',
  );
}

/// Adds the output option to an [ArgParser].
void addOutputOption(ArgParser argParser, {String help = 'Output file path.'}) {
  argParser.addOption(
    'output',
    abbr: 'o',
    help: help,
    valueHelp: 'path',
  );
}

/// Decodes Zegel flags to a human-readable list of feature names.
List<String> decodeFlagNames(int flags) {
  final names = <String>[];
  const flagMap = <int, String>{
    0x0001: 'HAS_METADATA',
    0x0002: 'COMPRESSED',
    0x0004: 'PASSWORD_DERIVED',
    0x0008: 'HAS_KEY_COMMITMENT',
    0x0010: 'HAS_EXPIRATION',
    0x0020: 'HAS_PUBLIC_METADATA',
    0x0040: 'MULTI_FILE',
    0x0080: 'HAS_CANARY',
    0x0100: 'HAS_REDACTIONS',
    0x0200: 'SPLIT_KEY',
    0x0400: 'SELECTIVE_DISCLOSURE',
    0x0800: 'VERSIONED',
  };
  for (final entry in flagMap.entries) {
    if (flags & entry.key != 0) {
      names.add(entry.value);
    }
  }
  return names;
}

/// Decodes a block type byte to a human-readable name.
String blockTypeName(int type) {
  const typeMap = <int, String>{
    0x01: 'CONTENT',
    0x02: 'METADATA',
    0x03: 'PUBLIC_METADATA',
    0x04: 'FILE_HEADER',
    0x05: 'PROVENANCE',
    0x06: 'REDACTED',
    0x07: 'ATTESTATION',
    0x08: 'REFERENCE',
    0x09: 'AUDIT',
    0x0A: 'DISCLOSURE_INDEX',
  };
  return typeMap[type] ?? 'UNKNOWN(0x${type.toRadixString(16)})';
}

/// Writes an error message to stderr and exits with the given code.
Never exitError(String message, {int code = 1}) {
  stderr.writeln('${Ansi.error("Error:")} $message');
  exit(code);
}

/// Base64 codec helper.
class Base64Codec {
  const Base64Codec();

  List<int> decode(String input) {
    const table =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final cleanInput = input.replaceAll(RegExp(r'\s'), '');
    final output = <int>[];
    var buffer = 0;
    var bitsCollected = 0;

    for (var i = 0; i < cleanInput.length; i++) {
      final ch = cleanInput[i];
      if (ch == '=') break;
      final idx = table.indexOf(ch);
      if (idx < 0) throw FormatException('Invalid base64 character: $ch');
      buffer = (buffer << 6) | idx;
      bitsCollected += 6;
      if (bitsCollected >= 8) {
        bitsCollected -= 8;
        output.add((buffer >> bitsCollected) & 0xFF);
      }
    }
    return output;
  }
}
