import 'dart:io' hide BytesBuilder;
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Inspects a .zgl file's header without requiring the master key.
///
/// Usage:
///   zegel inspect &lt;file.zgl&gt;
///
/// Displays version, flags, timestamp, content type, filename,
/// block count, classification level, regulatory hold date,
/// attestation summary, and any public metadata.
class InspectCommand extends Command<int> {
  @override
  final String name = 'inspect';

  @override
  String get description =>
      'Inspect a .zgl file header without requiring the master key.\n'
      '\n'
      'Displays all unencrypted header information including:\n'
      '  - Format version and creation timestamp\n'
      '  - Content type and original filename\n'
      '  - Feature flags (compression, expiration, canary, etc.)\n'
      '  - Classification level and authority (if set)\n'
      '  - Regulatory hold date (if set)\n'
      '  - Attestation summary (count and block indices)\n'
      '  - Split-key parameters\n'
      '  - Public metadata\n'
      '  - Block directory (with --blocks)\n'
      '\n'
      'No master key is needed because only unencrypted header\n'
      'fields and public metadata are displayed.\n'
      '\n'
      'Exit codes:\n'
      '  0  Success\n'
      '  1  Error (file not found, invalid format)\n'
      '\n'
      'Examples:\n'
      '  zegel inspect document.zgl\n'
      '  zegel inspect document.zgl --blocks\n'
      '  zegel inspect document.zgl --json\n'
      '  zegel inspect document.zgl --json | jq .classification';

  @override
  final String invocation = 'zegel inspect <file.zgl> [options]';

  InspectCommand() {
    argParser.addFlag(
      'json',
      help:
          'Output header information as JSON.\n'
          'Useful for piping to jq or other tools.',
      defaultsTo: false,
    );

    argParser.addFlag(
      'blocks',
      help:
          'Show block directory with type, size, and hash\n'
          'for each block.',
      defaultsTo: false,
    );
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('No .zgl file specified.', usage);
    }

    final filePath = argResults!.rest.first;
    final file = File(filePath);

    if (!file.existsSync()) {
      exitError('File not found: $filePath');
    }

    final fileBytes = Uint8List.fromList(file.readAsBytesSync());
    final jsonOutput = argResults!['json'] as bool;
    final showBlocks = argResults!['blocks'] as bool;

    // Inspect header using the library.
    ZegelInspection inspection;
    try {
      const reader = ZegelReader();
      inspection = reader.inspect(fileBytes);
    } on ZegelFormatException catch (e) {
      exitError('Invalid .zgl file: ${e.message}');
    }

    // Parse raw header for detailed information.
    RawZegelHeader? rawHeader;
    try {
      rawHeader = RawZegelHeader.parse(fileBytes);
    } catch (_) {
      // Fall back to library-only inspection if raw parsing fails.
    }

    if (jsonOutput) {
      _printJson(inspection, rawHeader);
    } else {
      _printHumanReadable(
        inspection,
        rawHeader,
        filePath,
        fileBytes.length,
        showBlocks,
      );
    }

    return 0;
  }

  /// Prints header information in human-readable format.
  void _printHumanReadable(
    ZegelInspection inspection,
    RawZegelHeader? rawHeader,
    String filePath,
    int fileSize,
    bool showBlocks,
  ) {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      inspection.timestamp * 1000,
      isUtc: true,
    );

    stdout.writeln(Ansi.header('Zegel File Inspector'));
    stdout.writeln();
    stdout.writeln('  File:         $filePath');
    stdout.writeln('  File size:    ${formatFileSize(fileSize)}');
    stdout.writeln('  Version:      ${inspection.version}');
    stdout.writeln('  Created:      ${formatTimestamp(createdAt)}');
    if (inspection.contentType != null) {
      stdout.writeln('  Content-Type: ${inspection.contentType}');
    }
    if (inspection.filename != null) {
      stdout.writeln('  Filename:     ${inspection.filename}');
    }
    stdout.writeln('  Block count:  ${inspection.blockCount}');

    // Flags.
    final flagNames = decodeFlagNames(inspection.flags);
    stdout.writeln(
      '  Flags:        0x${inspection.flags.toRadixString(16).padLeft(4, '0')}'
      '${flagNames.isNotEmpty ? ' (${flagNames.join(', ')})' : ' (none)'}',
    );

    // Merkle root (from raw header).
    if (rawHeader != null) {
      stdout.writeln('  Merkle root:  ${hexEncode(rawHeader.merkleRoot)}');
    }

    // Extended header fields.
    stdout.writeln();
    stdout.writeln(Ansi.header('  Features:'));

    if (inspection.flags & ZegelFormat.flagPasswordDerived != 0) {
      stdout.writeln('    Password-derived key (Argon2id)');
      if (rawHeader != null && rawHeader.argon2TimeCost != null) {
        stdout.writeln('      Time cost:   ${rawHeader.argon2TimeCost}');
        stdout.writeln('      Memory cost: ${rawHeader.argon2MemoryCost} KiB');
      }
    }

    if (inspection.expirationTimestamp != null) {
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        inspection.expirationTimestamp! * 1000,
        isUtc: true,
      );
      final now = DateTime.now().toUtc();
      final expired = now.isAfter(expiresAt);
      final status = expired ? Ansi.error('EXPIRED') : Ansi.success('active');
      stdout.writeln(
        '    Expiration:    ${formatTimestamp(expiresAt)} ($status)',
      );
    }

    if (inspection.flags & ZegelFormat.flagHasCanary != 0) {
      stdout.writeln('    Canary trap:   enabled (recipient fingerprinted)');
    }

    if (inspection.flags & ZegelFormat.flagHasRedactions != 0) {
      stdout.writeln('    Redactions:    file contains redacted blocks');
    }

    if (inspection.splitKeyParams != null) {
      stdout.writeln(
        '    Split-key:     ${inspection.splitKeyParams!['threshold']}-of-'
        '${inspection.splitKeyParams!['total']} (Shamir SSS)',
      );
    }

    if (inspection.flags & ZegelFormat.flagSelectiveDisclosure != 0) {
      stdout.writeln('    Selective disclosure: enabled');
    }

    if (inspection.flags & ZegelFormat.flagVersioned != 0) {
      stdout.writeln('    Versioned:     linked to previous version');
      if (rawHeader != null && rawHeader.versionChainHash != null) {
        stdout.writeln(
          '      Chain hash:  ${hexEncode(rawHeader.versionChainHash!)}',
        );
      }
    }

    if (inspection.flags & ZegelFormat.flagCompressed != 0) {
      stdout.writeln('    Compression:   enabled (zlib)');
    }

    if (inspection.flags & ZegelFormat.flagHasKeyCommitment != 0) {
      stdout.writeln('    Key commitment: present');
    }

    // Classification level (from public metadata).
    if (inspection.publicMetadata != null) {
      final classification =
          inspection.publicMetadata!['classification'] as String?;
      if (classification != null) {
        stdout.writeln();
        stdout.writeln(Ansi.header('  Classification:'));
        stdout.writeln('    Level:       $classification');
        final authority =
            inspection.publicMetadata!['classification_authority'];
        if (authority != null) {
          stdout.writeln('    Authority:   $authority');
        }
        final classDate = inspection.publicMetadata!['classification_date'];
        if (classDate != null) {
          stdout.writeln('    Date:        $classDate');
        }
      }

      // Regulatory hold (from public metadata).
      final holdTimestamp = inspection.publicMetadata!['regulatory_hold_until'];
      if (holdTimestamp != null) {
        final holdDate = DateTime.fromMillisecondsSinceEpoch(
          (holdTimestamp as int) * 1000,
          isUtc: true,
        );
        final now = DateTime.now().toUtc();
        final holdActive = now.isBefore(holdDate);
        final holdStr =
            inspection.publicMetadata!['regulatory_hold_date_str'] ??
            formatTimestamp(holdDate);
        stdout.writeln();
        stdout.writeln(Ansi.header('  Regulatory Hold:'));
        stdout.writeln('    Until:       $holdStr');
        stdout.writeln(
          '    Status:      ${holdActive ? Ansi.warning('ACTIVE') : Ansi.success('Expired')}',
        );
      }
    }

    // Attestation summary (from block directory).
    if (rawHeader != null) {
      int attestationCount = 0;
      final attestationIndices = <int>[];
      for (var i = 0; i < rawHeader.blockDirectory.length; i++) {
        if (rawHeader.blockDirectory[i].type == 0x07) {
          // ATTESTATION
          attestationCount++;
          attestationIndices.add(i);
        }
      }
      if (attestationCount > 0) {
        stdout.writeln();
        stdout.writeln(Ansi.header('  Attestations:'));
        stdout.writeln('    Count:       $attestationCount');
        stdout.writeln('    Blocks:      ${attestationIndices.join(', ')}');
        stdout.writeln(
          '    ${Ansi.dim}(use "zegel verify" with key to see attestation details)${Ansi.reset}',
        );
      }
    }

    // Public metadata.
    if (inspection.publicMetadata != null &&
        inspection.publicMetadata!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Public Metadata:'));
      for (final entry in inspection.publicMetadata!.entries) {
        stdout.writeln('    ${entry.key}: ${entry.value}');
      }
    }

    // Block directory (from raw header).
    if (showBlocks &&
        rawHeader != null &&
        rawHeader.blockDirectory.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Block Directory:'));
      stdout.writeln(
        '    ${'#'.padRight(4)}'
        '${'Type'.padRight(20)}'
        '${'Cipher Size'.padRight(14)}'
        'Hash',
      );
      stdout.writeln('    ${'-' * 70}');
      for (var i = 0; i < rawHeader.blockDirectory.length; i++) {
        final block = rawHeader.blockDirectory[i];
        final hashPreview = hexEncode(
          Uint8List.fromList(block.plaintextHash.take(8).toList()),
        );
        stdout.writeln(
          '    ${i.toString().padRight(4)}'
          '${blockTypeName(block.type).padRight(20)}'
          '${formatFileSize(block.ciphertextLength).padRight(14)}'
          '$hashPreview...',
        );
      }
    }
  }

  /// Prints header information as JSON.
  void _printJson(ZegelInspection inspection, RawZegelHeader? rawHeader) {
    final buffer = StringBuffer();
    buffer.writeln('{');
    buffer.writeln('  "version": "${inspection.version}",');
    buffer.writeln('  "flags": ${inspection.flags},');
    buffer.writeln(
      '  "flags_names": [${decodeFlagNames(inspection.flags).map((f) => '"$f"').join(', ')}],',
    );
    buffer.writeln('  "created_at": ${inspection.timestamp},');

    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      inspection.timestamp * 1000,
      isUtc: true,
    );
    buffer.writeln('  "created_at_iso": "${createdAt.toIso8601String()}",');

    if (inspection.contentType != null) {
      buffer.writeln(
        '  "content_type": "${_jsonEscape(inspection.contentType!)}",',
      );
    }
    if (inspection.filename != null) {
      buffer.writeln('  "filename": "${_jsonEscape(inspection.filename!)}",');
    }
    buffer.writeln('  "block_count": ${inspection.blockCount},');

    if (rawHeader != null) {
      buffer.writeln('  "merkle_root": "${hexEncode(rawHeader.merkleRoot)}",');
    }

    if (inspection.expirationTimestamp != null) {
      buffer.writeln('  "expires_at": ${inspection.expirationTimestamp},');
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        inspection.expirationTimestamp! * 1000,
        isUtc: true,
      );
      buffer.writeln('  "expires_at_iso": "${expiresAt.toIso8601String()}",');
    }

    if (inspection.splitKeyParams != null) {
      buffer.writeln(
        '  "split_key_threshold": ${inspection.splitKeyParams!['threshold']},',
      );
      buffer.writeln(
        '  "split_key_shares": ${inspection.splitKeyParams!['total']},',
      );
    }

    if (inspection.publicMetadata != null) {
      buffer.writeln('  "public_metadata": {');
      final entries = inspection.publicMetadata!.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        final comma = i < entries.length - 1 ? ',' : '';
        buffer.writeln(
          '    "${_jsonEscape(entries[i].key)}": '
          '"${_jsonEscape(entries[i].value.toString())}"$comma',
        );
      }
      buffer.writeln('  },');
    }

    // Block directory (from raw header).
    if (rawHeader != null) {
      buffer.writeln('  "blocks": [');
      for (var i = 0; i < rawHeader.blockDirectory.length; i++) {
        final block = rawHeader.blockDirectory[i];
        final comma = i < rawHeader.blockDirectory.length - 1 ? ',' : '';
        buffer.writeln('    {');
        buffer.writeln('      "index": $i,');
        buffer.writeln('      "type": ${block.type},');
        buffer.writeln('      "type_name": "${blockTypeName(block.type)}",');
        buffer.writeln('      "ciphertext_length": ${block.ciphertextLength},');
        buffer.writeln(
          '      "plaintext_hash": "${hexEncode(block.plaintextHash)}"',
        );
        buffer.writeln('    }$comma');
      }
      buffer.writeln('  ]');
    }

    buffer.writeln('}');
    stdout.write(buffer.toString());
  }

  /// Escapes a string for JSON output.
  String _jsonEscape(String s) {
    return s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }
}
