import 'dart:io' hide BytesBuilder;
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Extracts the original content from a verified .zgl file.
///
/// Usage:
///   zegel extract &lt;file.zgl&gt; -k &lt;key-hex&gt; -o &lt;output-file&gt;
class ExtractCommand extends Command<int> {
  @override
  final String name = 'extract';

  @override
  String get description =>
      'Extract the original content from a .zgl file after verification.\n'
      '\n'
      'First verifies the file integrity (master seal, Merkle tree, block\n'
      'HMACs), then decrypts and writes the original content. Extraction\n'
      'fails if the file has been tampered with or has expired.\n'
      '\n'
      'If the file contains redacted blocks, the non-redacted content is\n'
      'still extractable (with gaps where redacted blocks were).\n'
      '\n'
      'Use --check-regulatory-hold to refuse extraction of files that\n'
      'are under a regulatory hold (exit code 3).\n'
      '\n'
      'Exit codes:\n'
      '  0  Extracted successfully\n'
      '  1  Error (tampered, format error, file not found)\n'
      '  2  Expired (cryptographic expiration reached)\n'
      '  3  Regulatory hold active (extraction refused)\n'
      '\n'
      'Examples:\n'
      '  zegel extract document.zgl -k \$(cat master.key) -o document.pdf\n'
      '  zegel extract archive.zgl --key-file master.key -o output.tar.gz\n'
      '  zegel extract secret.zgl -k <hex> --force\n'
      '  zegel extract legal.zgl -k <hex> --check-regulatory-hold -o legal.pdf';

  @override
  final String invocation = 'zegel extract <file.zgl> [options]';

  ExtractCommand() {
    addKeyOptions(argParser);
    addOutputOption(
      argParser,
      help: 'Output file path. Defaults to the original filename\n'
          'stored in the .zgl header.',
    );

    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Overwrite the output file if it already exists.',
      defaultsTo: false,
    );

    argParser.addFlag(
      'skip-redacted',
      help: 'Continue extraction even if some blocks are redacted.\n'
          'Redacted blocks are replaced with empty content.',
      defaultsTo: true,
    );

    argParser.addFlag(
      'check-regulatory-hold',
      help: 'Check for regulatory hold metadata. If a hold is active\n'
          '(hold date is in the future), refuse extraction with exit code 3.',
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

    // Create reader and verify/extract.
    const reader = ZegelReader();
    ZegelResult result;

    try {
      result = reader.verify(fileBytes, masterKey);
    } on ZegelTamperedException catch (e) {
      stderr.writeln(
        '${Ansi.error('TAMPERED')} - File integrity check FAILED. '
        'Cannot extract.',
      );
      stderr.writeln('  Reason: ${e.message}');
      return 1;
    } on ZegelExpiredException catch (e) {
      stderr.writeln(
        '${Ansi.error('EXPIRED')} - File has passed its cryptographic '
        'expiration date.',
      );
      stderr.writeln('  Detail: ${e.message}');

      try {
        final inspection = reader.inspect(fileBytes);
        if (inspection.expirationTimestamp != null) {
          final expiresAt = DateTime.fromMillisecondsSinceEpoch(
            inspection.expirationTimestamp! * 1000,
            isUtc: true,
          );
          stderr.writeln('  Expired: ${formatTimestamp(expiresAt)}');
        }
      } catch (_) {
        // Could not inspect header for expiration details.
      }
      return 2;
    } on ZegelFormatException catch (e) {
      stderr.writeln('${Ansi.error('ERROR')} - Invalid file format.');
      stderr.writeln('  Reason: ${e.message}');
      return 1;
    }

    if (result.content == null || result.content!.isEmpty) {
      exitError('File verified but contains no extractable content.');
    }

    // Determine output path.
    final inspection = reader.inspect(fileBytes);

    // Check regulatory hold if requested.
    final checkRegulatoryHold = argResults!['check-regulatory-hold'] as bool;
    if (checkRegulatoryHold && inspection.publicMetadata != null) {
      final holdTimestamp = inspection.publicMetadata!['regulatory_hold_until'];
      if (holdTimestamp != null) {
        final holdDate = DateTime.fromMillisecondsSinceEpoch(
          (holdTimestamp as int) * 1000,
          isUtc: true,
        );
        final now = DateTime.now().toUtc();
        if (now.isBefore(holdDate)) {
          final holdStr =
              inspection.publicMetadata!['regulatory_hold_date_str'] ??
                  formatTimestamp(holdDate);
          stderr.writeln(
            '${Ansi.error('REGULATORY HOLD')} - File is under regulatory hold.',
          );
          stderr.writeln('  Hold until: $holdStr');
          stderr.writeln('  Extraction is refused while the hold is active.');
          stderr.writeln(
            '  Use --no-check-regulatory-hold to bypass this check.',
          );
          return 3;
        }
      }
    }
    final outputPath =
        argResults!['output'] as String? ?? inspection.filename ?? '';

    if (outputPath.isEmpty) {
      exitError(
        'Could not determine output filename. '
        'Use -o to specify an output path.',
      );
    }

    // Check if output file exists.
    final outputFile = File(outputPath);
    final force = argResults!['force'] as bool;

    if (outputFile.existsSync() && !force) {
      exitError(
        'Output file already exists: $outputPath. '
        'Use --force to overwrite.',
      );
    }

    // Write extracted content.
    outputFile.writeAsBytesSync(result.content!);

    // Print success message.
    stdout.writeln(Ansi.success('Extracted successfully.'));
    stdout.writeln();
    stdout.writeln('  Source:   $filePath');
    stdout.writeln('  Output:   $outputPath');
    if (inspection.filename != null) {
      stdout.writeln('  Filename: ${inspection.filename}');
    }
    if (inspection.contentType != null) {
      stdout.writeln('  Type:     ${inspection.contentType}');
    }
    stdout.writeln('  Size:     ${formatFileSize(result.content!.length)}');

    if (result.redactedBlocks != null && result.redactedBlocks!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(
        Ansi.warning(
          '  Note: ${result.redactedBlocks!.length} block(s) were redacted '
          '(blocks: ${result.redactedBlocks!.join(', ')})',
        ),
      );
    }

    if (result.metadata != null && result.metadata!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Metadata:'));
      for (final entry in result.metadata!.entries) {
        stdout.writeln('    ${entry.key}: ${entry.value}');
      }
    }

    SecureMemory.wipe(masterKey);
    return 0;
  }
}
