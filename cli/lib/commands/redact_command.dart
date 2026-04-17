import 'dart:io' hide BytesBuilder;
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Permanently redacts specific blocks from a .zgl file.
///
/// Usage:
///   zegel redact &lt;file.zgl&gt; -k &lt;key-hex&gt; --blocks 1,3,5 -o &lt;redacted.zgl&gt;
///
/// Redaction is irreversible. The original content of redacted blocks
/// is permanently destroyed and replaced with random bytes.
/// The Merkle tree remains intact because original leaf hashes are preserved.
class RedactCommand extends Command<int> {
  @override
  final String name = 'redact';

  @override
  String get description =>
      'Permanently redact specific blocks from a .zgl file.\n'
      '\n'
      'Replaces the content of specified blocks with cryptographically\n'
      'random bytes, making the original content irrecoverable. The\n'
      'original plaintext hashes are preserved in the block directory\n'
      'so the Merkle tree remains valid.\n'
      '\n'
      'This allows non-redacted blocks to still be verified and\n'
      'extracted normally. Redaction is IRREVERSIBLE.\n'
      '\n'
      'Use --declassify to simultaneously redact blocks and lower the\n'
      'classification level of the file.\n'
      '\n'
      'Exit codes:\n'
      '  0  Redaction complete\n'
      '  1  Error (tampered, invalid format, block out of range)\n'
      '\n'
      'Examples:\n'
      '  zegel redact secret.zgl -k <hex> --blocks 1,3,5 -o redacted.zgl\n'
      '  zegel redact report.zgl -k <hex> --blocks 2 -o public.zgl --confirm\n'
      '  zegel redact classified.zgl -k <hex> --blocks 0,1 --declassify --new-classification INTERNAL -o declassified.zgl';

  @override
  final String invocation = 'zegel redact <file.zgl> [options]';

  RedactCommand() {
    addKeyOptions(argParser);
    addOutputOption(
      argParser,
      help: 'Output path for the redacted .zgl file (required).',
    );

    argParser.addOption(
      'blocks',
      abbr: 'b',
      help: 'Comma-separated list of block indices to redact.\n'
          'Use "zegel inspect --blocks" to see available indices.',
      valueHelp: '1,3,5',
      mandatory: true,
    );

    argParser.addFlag(
      'confirm',
      help: 'Skip confirmation prompt (dangerous).\n'
          'Use in scripts where interactive prompts are not possible.',
      defaultsTo: false,
    );

    argParser.addFlag(
      'declassify',
      help: 'Lower the classification level after redaction.\n'
          'Must be used with --new-classification.',
      defaultsTo: false,
    );

    argParser.addOption(
      'new-classification',
      help: 'New classification level after declassification.\n'
          'Must be lower than the current level.\n'
          'Levels: PUBLIC, INTERNAL, CONFIDENTIAL, SECRET, TOP_SECRET.',
      valueHelp: 'level',
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
        stderr.writeln(
          Ansi.warning('Warning: Block $index is already redacted.'),
        );
      }
    }

    // Confirmation prompt.
    final skipConfirm = argResults!['confirm'] as bool;
    if (!skipConfirm && stdin.hasTerminal) {
      stderr.writeln(Ansi.warning('WARNING: Redaction is IRREVERSIBLE.'));
      stderr.writeln('The following blocks will be permanently destroyed:');
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
    const reader = ZegelReader();
    try {
      reader.verify(fileBytes, masterKey);
    } on ZegelException catch (e) {
      exitError(
        'File verification failed. Cannot redact an already-tampered file. '
        '(${e.message})',
      );
    }

    // Handle declassification.
    final declassify = argResults!['declassify'] as bool;
    final newClassification = argResults!['new-classification'] as String?;

    if (declassify) {
      if (newClassification == null || newClassification.isEmpty) {
        exitError(
          '--new-classification is required when --declassify is specified.',
        );
      }
      try {
        validateClassificationLevel(newClassification);
      } on FormatException catch (e) {
        exitError(e.message);
      }

      // Validate that new level is lower than current level.
      if (rawHeader.publicMetadata != null) {
        final currentLevel =
            rawHeader.publicMetadata!['classification'] as String?;
        if (currentLevel != null) {
          final currentRank = classificationRank(currentLevel);
          final newRank = classificationRank(newClassification);
          if (newRank >= currentRank) {
            exitError(
              'New classification "$newClassification" must be lower than '
              'current classification "$currentLevel".',
            );
          }
        }
      }
    }

    // Perform redaction.
    final redactedBytes = Redaction.redactBlocks(
      fileBytes,
      masterKey,
      blockIndices,
    );

    // Write redacted file.
    final outputFile = File(outputPath);
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

    if (declassify) {
      stdout.writeln('  Declassified:    ${newClassification!.toUpperCase()}');
    }

    stdout.writeln();
    stdout.writeln(
      Ansi.info(
        'The Merkle tree remains intact. Non-redacted blocks can still be '
        'verified and extracted.',
      ),
    );

    SecureMemory.wipe(masterKey);
      return 0;
  }
}
