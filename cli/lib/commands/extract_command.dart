import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Extracts the original content from a verified .zgl file.
///
/// Usage:
///   zegel extract <file.zgl> -k <key-hex> -o <output-file>
class ExtractCommand extends Command<int> {
  @override
  final String name = 'extract';

  @override
  final String description =
      'Extract the original content from a .zgl file after verification.';

  @override
  final String invocation = 'zegel extract <file.zgl> [options]';

  ExtractCommand() {
    addKeyOptions(argParser);
    addOutputOption(
      argParser,
      help: 'Output file path. Defaults to the original filename.',
    );

    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Overwrite the output file if it already exists.',
      defaultsTo: false,
    );

    argParser.addFlag(
      'skip-redacted',
      help: 'Continue extraction even if some blocks are redacted.',
      defaultsTo: true,
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
    final reader = const ZegelReader();
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
      stdout.writeln(Ansi.warning(
        '  Note: ${result.redactedBlocks!.length} block(s) were redacted '
        '(blocks: ${result.redactedBlocks!.join(', ')})',
      ));
    }

    if (result.metadata != null && result.metadata!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Metadata:'));
      for (final entry in result.metadata!.entries) {
        stdout.writeln('    ${entry.key}: ${entry.value}');
      }
    }

    return 0;
  }
}
