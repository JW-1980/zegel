import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Permanently redacts specific blocks from a .zgl file.
///
/// Usage:
///   zegel redact <file.zgl> -k <key-hex> --blocks 1,3,5 -o <redacted.zgl>
///
/// Redaction is irreversible. The original content of redacted blocks
/// is permanently destroyed and replaced with random bytes.
/// The Merkle tree remains intact because original leaf hashes are preserved.
class RedactCommand extends Command<int> {
  @override
  final String name = 'redact';

  @override
  final String description =
      'Permanently redact specific blocks from a .zgl file.';

  @override
  final String invocation = 'zegel redact <file.zgl> [options]';

  RedactCommand() {
    addKeyOptions(argParser);
    addOutputOption(
      argParser,
      help: 'Output path for the redacted .zgl file.',
    );

    argParser.addOption(
      'blocks',
      abbr: 'b',
      help: 'Comma-separated list of block indices to redact.',
      valueHelp: '1,3,5',
      mandatory: true,
    );

    argParser.addFlag(
      'confirm',
      help: 'Skip confirmation prompt (dangerous).',
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

    // Parse block indices.
    final blocksStr = argResults!['blocks'] as String;
    final blockIndices = <int>[];
    for (final part in blocksStr.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final index = int.tryParse(trimmed);
      if (index == null || index < 0) {
        exitError(
          'Invalid block index: "$trimmed". Must be a non-negative integer.',
        );
      }
      blockIndices.add(index);
    }

    if (blockIndices.isEmpty) {
      exitError('No block indices specified.');
    }

    // Determine output path.
    final outputPath = argResults!['output'] as String?;
    if (outputPath == null) {
      exitError('Output path is required for redaction (-o <path>).');
    }

    final fileBytes = Uint8List.fromList(file.readAsBytesSync());

    // Parse raw header to validate block indices and check types.
    RawZegelHeader rawHeader;
    try {
      rawHeader = RawZegelHeader.parse(fileBytes);
    } on FormatException catch (e) {
      exitError('Invalid .zgl file: ${e.message}');
    }

    // Validate block indices are within range.
    for (final index in blockIndices) {
      if (index >= rawHeader.blockCount) {
        exitError(
          'Block index $index is out of range. '
          'File has ${rawHeader.blockCount} blocks '
          '(0-${rawHeader.blockCount - 1}).',
        );
      }
      // Check if block is already redacted.
      if (rawHeader.blockDirectory[index].type == ZegelFormat.blockRedacted) {
        stderr.writeln(Ansi.warning(
          'Warning: Block $index is already redacted.',
        ));
      }
    }

    // Confirmation prompt.
    final skipConfirm = argResults!['confirm'] as bool;
    if (!skipConfirm && stdin.hasTerminal) {
      stderr.writeln(Ansi.warning('WARNING: Redaction is IRREVERSIBLE.'));
      stderr.writeln(
        'The following blocks will be permanently destroyed:',
      );
      for (final index in blockIndices) {
        final block = rawHeader.blockDirectory[index];
        stderr.writeln(
          '  Block $index: ${blockTypeName(block.type)} '
          '(${formatFileSize(block.ciphertextLength)})',
        );
      }
      stderr.write('\nType "REDACT" to confirm: ');
      final confirmation = stdin.readLineSync();
      if (confirmation != 'REDACT') {
        stderr.writeln('Redaction cancelled.');
        return 1;
      }
    }

    // Verify the file before redacting.
    final reader = const ZegelReader();
    try {
      reader.verify(fileBytes, masterKey);
    } on ZegelException catch (e) {
      exitError(
        'File verification failed. Cannot redact an already-tampered file. '
        '(${e.message})',
      );
    }

    // Perform redaction.
    final redactedBytes = Redaction.redactBlocks(
      fileBytes,
      masterKey,
      blockIndices,
    );

    // Write redacted file.
    final outputFile = File(outputPath!);
    outputFile.writeAsBytesSync(redactedBytes);

    // Print success message.
    stdout.writeln(Ansi.success('Redaction complete.'));
    stdout.writeln();
    stdout.writeln('  Source:          $filePath');
    stdout.writeln('  Output:          $outputPath');
    stdout.writeln('  Redacted blocks: ${blockIndices.join(', ')}');
    stdout.writeln('  Total blocks:    ${rawHeader.blockCount}');
    stdout.writeln(
      '  Remaining:       ${rawHeader.blockCount - blockIndices.length} '
      'accessible',
    );
    stdout.writeln();
    stdout.writeln(Ansi.info(
      'The Merkle tree remains intact. Non-redacted blocks can still be '
      'verified and extracted.',
    ));

    return 0;
  }
}
