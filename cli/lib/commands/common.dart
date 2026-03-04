import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

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
  final cleaned =
      hex.startsWith('0x') || hex.startsWith('0X') ? hex.substring(2) : hex;

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

/// Simple base64 decode.
Uint8List _base64Decode(String input) {
  return Uint8List.fromList(base64.decode(input));
}

// =============================================================================
// Raw binary parsing for CLI commands that need internal header details.
//
// The library's ZegelInspection type exposes only high-level fields.
// Several CLI commands (attest, disclose, inspect --blocks, redact) need
// access to merkleRoot, salt, block directory entries, etc.
// =============================================================================

/// A parsed block directory entry from raw .zgl bytes.
class RawBlockEntry {
  const RawBlockEntry({
    required this.type,
    required this.plaintextHash,
    required this.ciphertextLength,
    required this.iv,
    required this.tag,
  });

  final int type;
  final Uint8List plaintextHash;
  final int ciphertextLength;
  final Uint8List iv;
  final Uint8List tag;
}

/// Lightweight parsed header from raw .zgl bytes.
///
/// Extracts all fields needed by CLI commands that cannot use the library's
/// [ZegelInspection] type (which intentionally omits cryptographic internals).
class RawZegelHeader {
  RawZegelHeader._();

  late final int versionMajor;
  late final int versionMinor;
  late final int flags;
  late final int timestamp;
  late final String contentType;
  late final String filename;
  late final Uint8List salt;
  late final int blockCount;
  late final Uint8List merkleRoot;
  late final List<RawBlockEntry> blockDirectory;
  late final int dataStart;

  // Extended header fields (nullable).
  int? argon2TimeCost;
  int? argon2MemoryCost;
  int? expirationTimestamp;
  Uint8List? recipientId;
  int? splitKeyThreshold;
  int? splitKeyTotal;
  Uint8List? versionChainHash;
  Map<String, dynamic>? publicMetadata;
  Uint8List? keyCommitment;

  /// Parses a .zgl file's raw bytes and returns a [RawZegelHeader].
  ///
  /// Throws [FormatException] if the binary structure is invalid.
  static RawZegelHeader parse(Uint8List fileBytes) {
    final h = RawZegelHeader._();
    final bd = ByteData.sublistView(fileBytes);

    if (fileBytes.length < 86) {
      throw const FormatException('File too short for Zegel header.');
    }

    h.versionMajor = fileBytes[8];
    h.versionMinor = fileBytes[9];
    h.flags = bd.getUint16(10, Endian.big);
    h.timestamp = bd.getUint64(12, Endian.big);

    // Content-Type (64 bytes, null-padded).
    final ctRaw = Uint8List.sublistView(fileBytes, 20, 84);
    int ctEnd = ctRaw.indexOf(0);
    if (ctEnd < 0) ctEnd = ctRaw.length;
    h.contentType = utf8.decode(ctRaw.sublist(0, ctEnd));

    // Filename.
    final filenameLen = bd.getUint16(84, Endian.big);
    h.filename = utf8.decode(fileBytes.sublist(86, 86 + filenameLen));

    // Salt.
    final saltOffset = 86 + filenameLen;
    h.salt = Uint8List.fromList(
      fileBytes.sublist(saltOffset, saltOffset + ZegelFormat.saltSize),
    );

    // Block count.
    final blockCountOffset = saltOffset + ZegelFormat.saltSize;
    h.blockCount = bd.getUint32(blockCountOffset, Endian.big);

    // Extended header.
    int cursor = blockCountOffset + 4;

    if (h.flags & ZegelFormat.flagPasswordDerived != 0) {
      h.argon2TimeCost = bd.getUint32(cursor, Endian.big);
      cursor += 4;
      h.argon2MemoryCost = bd.getUint32(cursor, Endian.big);
      cursor += 4;
    }

    if (h.flags & ZegelFormat.flagHasExpiration != 0) {
      h.expirationTimestamp = bd.getUint64(cursor, Endian.big);
      cursor += 8;
    }

    if (h.flags & ZegelFormat.flagHasCanary != 0) {
      h.recipientId = Uint8List.fromList(
        fileBytes.sublist(cursor, cursor + 32),
      );
      cursor += 32;
    }

    if (h.flags & ZegelFormat.flagSplitKey != 0) {
      h.splitKeyThreshold = fileBytes[cursor];
      cursor += 1;
      h.splitKeyTotal = fileBytes[cursor];
      cursor += 1;
    }

    if (h.flags & ZegelFormat.flagVersioned != 0) {
      h.versionChainHash = Uint8List.fromList(
        fileBytes.sublist(cursor, cursor + 32),
      );
      cursor += 32;
    }

    if (h.flags & ZegelFormat.flagHasPublicMetadata != 0) {
      final pubMetaLen = bd.getUint32(cursor, Endian.big);
      cursor += 4;
      final pubMetaJson = utf8.decode(
        fileBytes.sublist(cursor, cursor + pubMetaLen),
      );
      h.publicMetadata = jsonDecode(pubMetaJson) as Map<String, dynamic>;
      cursor += pubMetaLen;
    }

    // Block directory.
    final directory = <RawBlockEntry>[];
    for (int i = 0; i < h.blockCount; i++) {
      final eo = cursor;
      directory.add(RawBlockEntry(
        type: fileBytes[eo],
        plaintextHash: Uint8List.fromList(fileBytes.sublist(eo + 1, eo + 33)),
        ciphertextLength: bd.getUint32(eo + 33, Endian.big),
        iv: Uint8List.fromList(fileBytes.sublist(eo + 37, eo + 49)),
        tag: Uint8List.fromList(fileBytes.sublist(eo + 49, eo + 65)),
      ));
      cursor += ZegelFormat.blockDirectoryEntrySize;
    }
    h.blockDirectory = directory;

    // Merkle root.
    h.merkleRoot = Uint8List.fromList(
      fileBytes.sublist(cursor, cursor + ZegelFormat.hashSize),
    );
    cursor += ZegelFormat.hashSize;

    // Key commitment (optional).
    if (h.flags & ZegelFormat.flagHasKeyCommitment != 0) {
      h.keyCommitment = Uint8List.fromList(
        fileBytes.sublist(cursor, cursor + ZegelFormat.hashSize),
      );
      cursor += ZegelFormat.hashSize;
    }

    h.dataStart = cursor;
    return h;
  }

  /// Returns the expiration as a DateTime, or null.
  DateTime? get expiresAt => expirationTimestamp != null
      ? DateTime.fromMillisecondsSinceEpoch(
          expirationTimestamp! * 1000,
          isUtc: true,
        )
      : null;

  /// Returns the creation timestamp as a DateTime.
  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(
        timestamp * 1000,
        isUtc: true,
      );
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
  return '${dt.toUtc().toIso8601String().replaceFirst('T', ' ').split('.').first} UTC';
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

// =============================================================================
// Duration parsing
// =============================================================================

/// Parses a human-readable duration string into a [Duration].
///
/// Supported formats:
///   - "30m" or "30min" -> 30 minutes
///   - "24h" -> 24 hours
///   - "7d" -> 7 days
///   - "2w" -> 2 weeks
///
/// Throws [FormatException] if the format is invalid.
Duration parseDuration(String s) {
  final trimmed = s.trim().toLowerCase();
  final match = RegExp(r'^(\d+)\s*(m|min|h|d|w)$').firstMatch(trimmed);
  if (match == null) {
    throw FormatException(
      'Invalid duration format: "$s". '
      'Expected a number followed by a unit (m/min, h, d, w). '
      'Examples: "30m", "24h", "7d", "2w".',
    );
  }

  final value = int.parse(match.group(1)!);
  final unit = match.group(2)!;

  switch (unit) {
    case 'm':
    case 'min':
      return Duration(minutes: value);
    case 'h':
      return Duration(hours: value);
    case 'd':
      return Duration(days: value);
    case 'w':
      return Duration(days: value * 7);
    default:
      throw FormatException('Unknown duration unit: "$unit".');
  }
}

// =============================================================================
// Table formatting
// =============================================================================

/// Prints a list of rows as an aligned text table.
///
/// The first row is treated as a header and separated with dashes.
/// Each row should have the same number of columns.
///
/// Example:
/// ```dart
/// printTable([
///   ['File', 'Status', 'Time'],
///   ['doc.zgl', 'VALID', '12ms'],
///   ['img.zgl', 'TAMPERED', '8ms'],
/// ]);
/// ```
void printTable(List<List<String>> rows) {
  if (rows.isEmpty) return;

  final columnCount = rows[0].length;
  final widths = List<int>.filled(columnCount, 0);

  // Compute maximum width per column.
  for (final row in rows) {
    for (int i = 0; i < row.length && i < columnCount; i++) {
      if (row[i].length > widths[i]) {
        widths[i] = row[i].length;
      }
    }
  }

  // Print header.
  final headerLine = StringBuffer('  ');
  for (int i = 0; i < columnCount; i++) {
    headerLine.write(rows[0][i].padRight(widths[i] + 2));
  }
  stdout.writeln(Ansi.header(headerLine.toString()));

  // Print separator.
  final totalWidth = widths.fold<int>(0, (a, b) => a + b) + (columnCount * 2);
  stdout.writeln('  ${'-' * totalWidth}');

  // Print data rows.
  for (int r = 1; r < rows.length; r++) {
    final line = StringBuffer('  ');
    for (int i = 0; i < columnCount; i++) {
      final cell = (i < rows[r].length) ? rows[r][i] : '';
      line.write(cell.padRight(widths[i] + 2));
    }
    stdout.writeln(line.toString());
  }
}

// =============================================================================
// Standard help output
// =============================================================================

/// Prints standardized help text for a command with description and examples.
void printHelp(String command, String description, List<String> examples) {
  stdout.writeln(Ansi.header('zegel $command'));
  stdout.writeln();
  stdout.writeln(description);

  if (examples.isNotEmpty) {
    stdout.writeln();
    stdout.writeln(Ansi.header('Examples:'));
    for (final example in examples) {
      stdout.writeln('  \$ $example');
    }
  }
}

// =============================================================================
// Classification level validation
// =============================================================================

/// Valid classification levels in ascending order of sensitivity.
const classificationLevels = [
  'PUBLIC',
  'INTERNAL',
  'CONFIDENTIAL',
  'SECRET',
  'TOP_SECRET',
];

/// Validates a classification level string.
///
/// Returns the normalized (uppercased) level string.
/// Throws [FormatException] if the level is invalid.
String validateClassificationLevel(String level) {
  final normalized = level.toUpperCase().replaceAll('-', '_');
  if (!classificationLevels.contains(normalized)) {
    throw FormatException(
      'Invalid classification level: "$level". '
      'Must be one of: ${classificationLevels.join(', ')}.',
    );
  }
  return normalized;
}

/// Returns the numeric rank of a classification level (0 = PUBLIC, 4 = TOP_SECRET).
int classificationRank(String level) {
  final index = classificationLevels.indexOf(level.toUpperCase());
  if (index < 0) {
    throw FormatException('Invalid classification level: "$level".');
  }
  return index;
}

// =============================================================================
// Role validation
// =============================================================================

/// Valid attestation roles.
const attestationRoles = [
  'owner',
  'signer',
  'witness',
  'notary',
  'auditor',
  'reviewer',
];

/// Validates an attestation role string.
///
/// Returns the normalized (lowercased) role string.
/// Throws [FormatException] if the role is invalid.
String validateRole(String role) {
  final normalized = role.toLowerCase();
  if (!attestationRoles.contains(normalized)) {
    throw FormatException(
      'Invalid attestation role: "$role". '
      'Must be one of: ${attestationRoles.join(', ')}.',
    );
  }
  return normalized;
}
