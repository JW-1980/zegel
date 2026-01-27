import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Inspects a .zgl file's header without requiring the master key.
///
/// Usage:
///   zegel inspect <file.zgl>
///
/// Displays version, flags, timestamp, content type, filename,
/// block count, and any public metadata.
class InspectCommand extends Command<int> {
  @override
  final String name = 'inspect';

  @override
  final String description =
      'Inspect a .zgl file header (no key required).';

  @override
  final String invocation = 'zegel inspect <file.zgl>';

  InspectCommand() {
    argParser.addFlag(
      'json',
      help: 'Output header information as JSON.',
      defaultsTo: false,
    );

    argParser.addFlag(
      'blocks',
      help: 'Show block directory details.',
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

    // Create reader and inspect header.
    ZegelHeader header;
    try {
      final reader = ZegelReader(fileBytes);
      header = reader.inspectHeader();
    } on ZegelFormatException catch (e) {
      exitError('Invalid .zgl file: ${e.message}');
    }

    if (jsonOutput) {
      _printJson(header);
    } else {
      _printHumanReadable(header, filePath, fileBytes.length, showBlocks);
    }

    return 0;
  }

  /// Prints header information in human-readable format.
  void _printHumanReadable(
    ZegelHeader header,
    String filePath,
    int fileSize,
    bool showBlocks,
  ) {
    stdout.writeln(Ansi.header('Zegel File Inspector'));
    stdout.writeln();
    stdout.writeln('  File:         $filePath');
    stdout.writeln('  File size:    ${formatFileSize(fileSize)}');
    stdout.writeln('  Version:      ${header.versionMajor}.${header.versionMinor}');
    stdout.writeln('  Created:      ${formatTimestamp(header.createdAt)}');
    stdout.writeln('  Content-Type: ${header.contentType}');
    stdout.writeln('  Filename:     ${header.filename}');
    stdout.writeln('  Block count:  ${header.blockCount}');

    // Flags.
    final flagNames = decodeFlagNames(header.flags);
    stdout.writeln(
      '  Flags:        0x${header.flags.toRadixString(16).padLeft(4, '0')}'
      '${flagNames.isNotEmpty ? ' (${flagNames.join(', ')})' : ' (none)'}',
    );

    // Merkle root.
    if (header.merkleRoot != null) {
      stdout.writeln(
        '  Merkle root:  ${hexEncode(header.merkleRoot!)}',
      );
    }

    // Extended header fields.
    stdout.writeln();
    stdout.writeln(Ansi.header('  Features:'));

    if (header.flags & 0x0004 != 0) {
      stdout.writeln('    Password-derived key (Argon2id)');
      if (header.argon2TimeCost != null) {
        stdout.writeln('      Time cost:   ${header.argon2TimeCost}');
        stdout.writeln('      Memory cost: ${header.argon2MemoryCost} KiB');
      }
    }

    if (header.expiresAt != null) {
      final now = DateTime.now().toUtc();
      final expired = now.isAfter(header.expiresAt!);
      final status = expired
          ? Ansi.error('EXPIRED')
          : Ansi.success('active');
      stdout.writeln(
        '    Expiration:    ${formatTimestamp(header.expiresAt!)} ($status)',
      );
    }

    if (header.flags & 0x0080 != 0) {
      stdout.writeln('    Canary trap:   enabled (recipient fingerprinted)');
    }

    if (header.flags & 0x0100 != 0) {
      stdout.writeln('    Redactions:    file contains redacted blocks');
    }

    if (header.splitKeyThreshold != null) {
      stdout.writeln(
        '    Split-key:     ${header.splitKeyThreshold}-of-'
        '${header.splitKeyShares} (Shamir SSS)',
      );
    }

    if (header.flags & 0x0400 != 0) {
      stdout.writeln('    Selective disclosure: enabled');
    }

    if (header.flags & 0x0800 != 0) {
      stdout.writeln('    Versioned:     linked to previous version');
      if (header.versionChainHash != null) {
        stdout.writeln(
          '      Chain hash:  ${hexEncode(header.versionChainHash!)}',
        );
      }
    }

    if (header.flags & 0x0002 != 0) {
      stdout.writeln('    Compression:   enabled (zlib)');
    }

    if (header.flags & 0x0008 != 0) {
      stdout.writeln('    Key commitment: present');
    }

    // Public metadata.
    if (header.publicMetadata != null && header.publicMetadata!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Public Metadata:'));
      for (final entry in header.publicMetadata!.entries) {
        stdout.writeln('    ${entry.key}: ${entry.value}');
      }
    }

    // Block directory.
    if (showBlocks && header.blockDirectory.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Block Directory:'));
      stdout.writeln(
        '    ${'#'.padRight(4)}'
        '${'Type'.padRight(20)}'
        '${'Cipher Size'.padRight(14)}'
        'Hash',
      );
      stdout.writeln('    ${'-' * 70}');
      for (var i = 0; i < header.blockDirectory.length; i++) {
        final block = header.blockDirectory[i];
        final hashPreview =
            hexEncode(Uint8List.fromList(block.plaintextHash.take(8).toList()));
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
  void _printJson(ZegelHeader header) {
    final buffer = StringBuffer();
    buffer.writeln('{');
    buffer.writeln('  "version": "${header.versionMajor}.${header.versionMinor}",');
    buffer.writeln('  "flags": ${header.flags},');
    buffer.writeln('  "flags_names": [${decodeFlagNames(header.flags).map((f) => '"$f"').join(', ')}],');
    buffer.writeln('  "created_at": ${header.createdAt.millisecondsSinceEpoch ~/ 1000},');
    buffer.writeln('  "created_at_iso": "${header.createdAt.toIso8601String()}",');
    buffer.writeln('  "content_type": "${_jsonEscape(header.contentType)}",');
    buffer.writeln('  "filename": "${_jsonEscape(header.filename)}",');
    buffer.writeln('  "block_count": ${header.blockCount},');

    if (header.merkleRoot != null) {
      buffer.writeln('  "merkle_root": "${hexEncode(header.merkleRoot!)}",');
    }

    if (header.expiresAt != null) {
      buffer.writeln('  "expires_at": ${header.expiresAt!.millisecondsSinceEpoch ~/ 1000},');
      buffer.writeln('  "expires_at_iso": "${header.expiresAt!.toIso8601String()}",');
    }

    if (header.splitKeyThreshold != null) {
      buffer.writeln('  "split_key_threshold": ${header.splitKeyThreshold},');
      buffer.writeln('  "split_key_shares": ${header.splitKeyShares},');
    }

    if (header.publicMetadata != null) {
      buffer.writeln('  "public_metadata": {');
      final entries = header.publicMetadata!.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        final comma = i < entries.length - 1 ? ',' : '';
        buffer.writeln(
          '    "${_jsonEscape(entries[i].key)}": '
          '"${_jsonEscape(entries[i].value.toString())}"$comma',
        );
      }
      buffer.writeln('  },');
    }

    // Block directory.
    buffer.writeln('  "blocks": [');
    for (var i = 0; i < header.blockDirectory.length; i++) {
      final block = header.blockDirectory[i];
      final comma = i < header.blockDirectory.length - 1 ? ',' : '';
      buffer.writeln('    {');
      buffer.writeln('      "index": $i,');
      buffer.writeln('      "type": ${block.type},');
      buffer.writeln('      "type_name": "${blockTypeName(block.type)}",');
      buffer.writeln('      "ciphertext_length": ${block.ciphertextLength},');
      buffer.writeln('      "plaintext_hash": "${hexEncode(block.plaintextHash)}"');
      buffer.writeln('    }$comma');
    }
    buffer.writeln('  ]');

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
