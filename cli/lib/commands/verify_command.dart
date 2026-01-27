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
    final reader = ZegelReader(fileBytes);
    final result = reader.verify(masterKey);

    switch (result.status) {
      case ZegelVerifyStatus.valid:
        if (quiet) {
          stdout.writeln('VALID');
        } else {
          stdout.writeln(Ansi.success('VALID') +
              ' - File integrity verified.');
          stdout.writeln();
          _printFileInfo(reader, result, filePath, verbose);
        }
        return 0;

      case ZegelVerifyStatus.tampered:
        if (quiet) {
          stdout.writeln('TAMPERED');
        } else {
          stdout.writeln(Ansi.error('TAMPERED') +
              ' - File integrity check FAILED.');
          stdout.writeln();
          if (result.errorMessage != null) {
            stderr.writeln('  Reason: ${result.errorMessage}');
          }
        }
        return 1;

      case ZegelVerifyStatus.expired:
        if (quiet) {
          stdout.writeln('EXPIRED');
        } else {
          stdout.writeln(Ansi.error('EXPIRED') +
              ' - File has passed its cryptographic expiration date.');
          stdout.writeln();
          final header = reader.inspectHeader();
          if (header.expiresAt != null) {
            stdout.writeln(
              '  Expired: ${formatTimestamp(header.expiresAt!)}',
            );
          }
        }
        return 2;
    }
  }

  /// Prints file information after successful verification.
  void _printFileInfo(
    ZegelReader reader,
    ZegelReadResult result,
    String filePath,
    bool verbose,
  ) {
    final header = reader.inspectHeader();

    stdout.writeln('  File:       $filePath');
    stdout.writeln('  Version:    ${header.versionMajor}.${header.versionMinor}');
    stdout.writeln('  Created:    ${formatTimestamp(header.createdAt)}');
    stdout.writeln('  Filename:   ${header.filename}');
    stdout.writeln('  Type:       ${header.contentType}');
    stdout.writeln('  Blocks:     ${header.blockCount}');

    if (header.expiresAt != null) {
      stdout.writeln('  Expires:    ${formatTimestamp(header.expiresAt!)}');
    }

    // Show flags.
    final flags = decodeFlagNames(header.flags);
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
    if (header.publicMetadata != null && header.publicMetadata!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Public Metadata:'));
      for (final entry in header.publicMetadata!.entries) {
        stdout.writeln('    ${entry.key}: ${entry.value}');
      }
    }

    // Show redacted blocks.
    if (result.redactedBlocks.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.warning(
        '  Redacted blocks: ${result.redactedBlocks.join(', ')}',
      ));
    }

    // Show attestations if present.
    if (result.attestations != null && result.attestations!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Attestations:'));
      for (final att in result.attestations!) {
        final valid = att['valid'] == true;
        final status = valid
            ? Ansi.success('VALID')
            : Ansi.error('INVALID');
        stdout.writeln('    [$status] ${att['signer_id']}');
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
        final chainValid = entry['chain_valid'] == true;
        final chainStatus = chainValid
            ? Ansi.success('OK')
            : Ansi.error('BROKEN');
        stdout.writeln(
          '    ${i + 1}. [${entry['action']}] by ${entry['actor']} '
          '${ts != null ? formatTimestamp(ts) : 'unknown time'} '
          '(chain: $chainStatus)',
        );
      }
    }

    if (verbose) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Block Directory:'));
      for (var i = 0; i < header.blockCount; i++) {
        final block = header.blockDirectory[i];
        stdout.writeln(
          '    [$i] ${blockTypeName(block.type)} '
          '${formatFileSize(block.ciphertextLength)} '
          'hash=${hexEncode(Uint8List.fromList(block.plaintextHash.take(8).toList()))}...',
        );
      }
    }
  }
}
