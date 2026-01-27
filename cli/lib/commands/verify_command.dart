import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Verifies the integrity of a .zgl file.
///
/// Usage:
///   zegel verify <file.zgl> -k <key-hex>
///
/// Exit codes:
///   0 = valid (intact)
///   1 = tampered (integrity check failed)
///   2 = expired (cryptographic expiration reached)
class VerifyCommand extends Command<int> {
  @override
  final String name = 'verify';

  @override
  final String description =
      'Verify the integrity of a .zgl file.';

  @override
  final String invocation = 'zegel verify <file.zgl> [options]';

  VerifyCommand() {
    addKeyOptions(argParser);

    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Show detailed verification information.',
      defaultsTo: false,
    );

    argParser.addFlag(
      'quiet',
      abbr: 'q',
      help: 'Only output the result (VALID, TAMPERED, or EXPIRED).',
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

    final masterKey = parseKeyFromArgs(argResults!);
    if (masterKey.length != 32) {
      exitError(
        'Master key must be exactly 32 bytes (64 hex characters). '
        'Got ${masterKey.length} bytes.',
      );
    }

    final fileBytes = Uint8List.fromList(file.readAsBytesSync());
    final verbose = argResults!['verbose'] as bool;
    final quiet = argResults!['quiet'] as bool;

    // Create reader and verify.
    final reader = const ZegelReader();

    try {
      final result = reader.verify(fileBytes, masterKey);

      if (quiet) {
        stdout.writeln('VALID');
      } else {
        stdout.writeln('${Ansi.success('VALID')} - File integrity verified.');
        stdout.writeln();
        _printFileInfo(reader, result, fileBytes, filePath, verbose);
      }
      return 0;
    } on ZegelTamperedException catch (e) {
      if (quiet) {
        stdout.writeln('TAMPERED');
      } else {
        stdout.writeln(
          '${Ansi.error('TAMPERED')} - File integrity check FAILED.',
        );
        stdout.writeln();
        stderr.writeln('  Reason: ${e.message}');
      }
      return 1;
    } on ZegelExpiredException catch (e) {
      if (quiet) {
        stdout.writeln('EXPIRED');
      } else {
        stdout.writeln(
          '${Ansi.error('EXPIRED')} - File has passed its cryptographic '
          'expiration date.',
        );
        stdout.writeln();
        stderr.writeln('  Detail: ${e.message}');

        try {
          final inspection = reader.inspect(fileBytes);
          if (inspection.expirationTimestamp != null) {
            final expiresAt = DateTime.fromMillisecondsSinceEpoch(
              inspection.expirationTimestamp! * 1000,
              isUtc: true,
            );
            stdout.writeln('  Expired: ${formatTimestamp(expiresAt)}');
          }
        } catch (_) {
          // Could not inspect header for expiration details.
        }
      }
      return 2;
    } on ZegelFormatException catch (e) {
      if (quiet) {
        stdout.writeln('TAMPERED');
      } else {
        stderr.writeln('${Ansi.error('ERROR')} - Invalid file format.');
        stderr.writeln('  Reason: ${e.message}');
      }
      return 1;
    }
  }

  /// Prints file information after successful verification.
  void _printFileInfo(
    ZegelReader reader,
    ZegelResult result,
    Uint8List fileBytes,
    String filePath,
    bool verbose,
  ) {
    final inspection = reader.inspect(fileBytes);

    final createdAt = DateTime.fromMillisecondsSinceEpoch(
      inspection.timestamp * 1000,
      isUtc: true,
    );

    stdout.writeln('  File:       $filePath');
    stdout.writeln('  Version:    ${inspection.version}');
    stdout.writeln('  Created:    ${formatTimestamp(createdAt)}');
    if (inspection.filename != null) {
      stdout.writeln('  Filename:   ${inspection.filename}');
    }
    if (inspection.contentType != null) {
      stdout.writeln('  Type:       ${inspection.contentType}');
    }
    stdout.writeln('  Blocks:     ${inspection.blockCount}');

    if (inspection.expirationTimestamp != null) {
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        inspection.expirationTimestamp! * 1000,
        isUtc: true,
      );
      stdout.writeln('  Expires:    ${formatTimestamp(expiresAt)}');
    }

    // Show flags.
    final flags = decodeFlagNames(inspection.flags);
    if (flags.isNotEmpty) {
      stdout.writeln('  Flags:      ${flags.join(', ')}');
    }

    // Show encrypted metadata if present.
    if (result.metadata != null && result.metadata!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Metadata:'));
      for (final entry in result.metadata!.entries) {
        stdout.writeln('    ${entry.key}: ${entry.value}');
      }
    }

    // Show public metadata if present.
    if (inspection.publicMetadata != null &&
        inspection.publicMetadata!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Public Metadata:'));
      for (final entry in inspection.publicMetadata!.entries) {
        stdout.writeln('    ${entry.key}: ${entry.value}');
      }
    }

    // Show redacted blocks.
    if (result.redactedBlocks != null && result.redactedBlocks!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.warning(
        '  Redacted blocks: ${result.redactedBlocks!.join(', ')}',
      ));
    }

    // Show attestations if present.
    if (result.attestations != null && result.attestations!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Attestations:'));
      for (final att in result.attestations!) {
        stdout.writeln('    Signer: ${att['signer_id']}');
        stdout.writeln('      Statement: ${att['statement']}');
        if (att['timestamp'] != null) {
          final ts = DateTime.fromMillisecondsSinceEpoch(
            (att['timestamp'] as int) * 1000,
            isUtc: true,
          );
          stdout.writeln('      Time:      ${formatTimestamp(ts)}');
        }
      }
    }

    // Show audit trail if present.
    if (result.auditTrail != null && result.auditTrail!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Audit Trail:'));
      for (var i = 0; i < result.auditTrail!.length; i++) {
        final entry = result.auditTrail![i];
        final ts = entry['timestamp'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (entry['timestamp'] as int) * 1000,
                isUtc: true,
              )
            : null;
        stdout.writeln(
          '    ${i + 1}. [${entry['action']}] by ${entry['actor']} '
          '${ts != null ? formatTimestamp(ts) : 'unknown time'}',
        );
      }
    }

    if (verbose) {
      // Use raw binary parsing to show block directory details.
      try {
        final rawHeader = RawZegelHeader.parse(fileBytes);
        stdout.writeln();
        stdout.writeln(Ansi.header('  Block Directory:'));
        for (var i = 0; i < rawHeader.blockCount; i++) {
          final block = rawHeader.blockDirectory[i];
          stdout.writeln(
            '    [$i] ${blockTypeName(block.type)} '
            '${formatFileSize(block.ciphertextLength)} '
            'hash=${hexEncode(Uint8List.fromList(block.plaintextHash.take(8).toList()))}...',
          );
        }
      } catch (_) {
        // Could not parse block directory.
      }
    }
  }
}
