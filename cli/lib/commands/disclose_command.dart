import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Generates a selective disclosure token for specific blocks.
///
/// Usage:
///   zegel disclose <file.zgl> -k <key-hex> --blocks 0,2 -o <token.json>
///
/// The token contains per-block derived keys that allow a third party
/// to decrypt only the specified blocks without having the master key.
class DiscloseCommand extends Command<int> {
  @override
  final String name = 'disclose';

  @override
  String get description =>
      'Generate a selective disclosure token for specific blocks.\n'
      '\n'
      'Creates a JSON token containing per-block derived keys that allow\n'
      'a third party to decrypt only the specified blocks without having\n'
      'the master key. The token holder cannot access any blocks not\n'
      'listed in the token.\n'
      '\n'
      'Tokens can be time-limited with --token-expires or --expires-in.\n'
      'The token recipient can use "zegel extract-with-token" to extract\n'
      'the disclosed content.\n'
      '\n'
      'Exit codes:\n'
      '  0  Token generated successfully\n'
      '  1  Error\n'
      '\n'
      'Examples:\n'
      '  zegel disclose report.zgl -k <hex> --blocks 0,2 -o token.json\n'
      '  zegel disclose doc.zgl -k <hex> --blocks 0 --expires-in 24h -o token.json\n'
      '  zegel disclose doc.zgl -k <hex> --blocks 0,1 --token-expires 2025-06-01 --recipient auditor@corp -o token.json';

  @override
  final String invocation = 'zegel disclose <file.zgl> [options]';

  DiscloseCommand() {
    addKeyOptions(argParser);
    addOutputOption(
      argParser,
      help: 'Output path for the disclosure token JSON file (required).',
    );

    argParser.addOption(
      'blocks',
      abbr: 'b',
      help: 'Comma-separated list of block indices to disclose.\n'
          'Use "zegel inspect --blocks" to see available indices.',
      valueHelp: '0,2,4',
      mandatory: true,
    );

    argParser.addOption(
      'token-expires',
      help: 'Expiration date for the token (YYYY-MM-DD).\n'
          'After this date, the token cannot be used.',
      valueHelp: 'YYYY-MM-DD',
    );

    argParser.addOption(
      'expires-in',
      help: 'Duration after which the token expires.\n'
          'Formats: "30m" (minutes), "24h" (hours), "7d" (days), "2w" (weeks).\n'
          'Cannot be used with --token-expires.',
      valueHelp: 'duration',
    );

    argParser.addOption(
      'recipient',
      help: 'Optional recipient identifier for the token.\n'
          'Stored in the token JSON for audit purposes.',
      valueHelp: 'name',
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

    final outputPath = argResults!['output'] as String?;
    if (outputPath == null) {
      exitError('Output path is required for token file (-o <path>).');
    }

    final fileBytes = Uint8List.fromList(file.readAsBytesSync());

    // Parse raw header for merkleRoot, salt, and block directory.
    RawZegelHeader rawHeader;
    try {
      rawHeader = RawZegelHeader.parse(fileBytes);
    } on FormatException catch (e) {
      exitError('Invalid .zgl file: ${e.message}');
    }

    // Validate block indices.
    for (final index in blockIndices) {
      if (index >= rawHeader.blockCount) {
        exitError(
          'Block index $index is out of range. '
          'File has ${rawHeader.blockCount} blocks '
          '(0-${rawHeader.blockCount - 1}).',
        );
      }
      if (rawHeader.blockDirectory[index].type == ZegelFormat.blockRedacted) {
        exitError(
          'Block $index is redacted and cannot be disclosed.',
        );
      }
    }

    // Verify the file first.
    final reader = const ZegelReader();
    try {
      reader.verify(fileBytes, masterKey);
    } on ZegelException catch (e) {
      exitError(
        'File verification failed. Cannot generate disclosure token. '
        '(${e.message})',
      );
    }

    // Build expiration date string for key derivation (from file's expiration).
    String? expirationDateStr;
    if (rawHeader.expirationTimestamp != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(
        rawHeader.expirationTimestamp! * 1000,
        isUtc: true,
      );
      expirationDateStr =
          '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    }

    // Parse optional token expiration.
    DateTime? tokenExpires;
    final tokenExpiresStr = argResults!['token-expires'] as String?;
    final expiresInStr = argResults!['expires-in'] as String?;

    if (tokenExpiresStr != null && expiresInStr != null) {
      exitError(
        'Cannot specify both --token-expires and --expires-in. Use one or the other.',
      );
    }

    if (tokenExpiresStr != null) {
      tokenExpires = parseExpirationDate(tokenExpiresStr);
    } else if (expiresInStr != null) {
      try {
        final duration = parseDuration(expiresInStr);
        tokenExpires = DateTime.now().toUtc().add(duration);
      } on FormatException catch (e) {
        exitError(e.message);
      }
    }

    // Generate the disclosure token.
    final token = SelectiveDisclosure.generateToken(
      masterKey,
      rawHeader.merkleRoot,
      rawHeader.salt,
      blockIndices,
      expirationDate: expirationDateStr,
    );

    // Add optional fields to the token.
    if (tokenExpires != null) {
      token['token_expires'] = tokenExpires.millisecondsSinceEpoch ~/ 1000;
    }

    final recipient = argResults!['recipient'] as String?;
    if (recipient != null) {
      token['recipient'] = recipient;
    }

    // Write token as JSON.
    final jsonString = const JsonEncoder.withIndent('  ').convert(token);
    final outputFile = File(outputPath!);
    outputFile.writeAsStringSync('$jsonString\n');

    // Print success message.
    stdout.writeln(Ansi.success('Disclosure token generated.'));
    stdout.writeln();
    stdout.writeln('  Source:      $filePath');
    stdout.writeln('  Token file:  $outputPath');
    stdout.writeln('  Blocks:      ${blockIndices.join(', ')}');
    stdout.writeln(
      '  Block count: ${blockIndices.length} of ${rawHeader.blockCount}',
    );

    if (tokenExpires != null) {
      stdout.writeln('  Expires:     ${formatTimestamp(tokenExpires)}');
    }

    if (recipient != null) {
      stdout.writeln('  Recipient:   $recipient');
    }

    // Show block details.
    stdout.writeln();
    stdout.writeln(Ansi.header('  Disclosed blocks:'));
    for (final index in blockIndices) {
      final block = rawHeader.blockDirectory[index];
      stdout.writeln(
        '    [$index] ${blockTypeName(block.type)} '
        '(${formatFileSize(block.ciphertextLength)})',
      );
    }

    stdout.writeln();
    stderr.writeln(Ansi.warning('Security Warning:'));
    stderr.writeln(
      '  This token grants permanent read access to the specified blocks.',
    );
    stderr.writeln(
      '  Distribute it with the same care as a key.',
    );
    stderr.writeln(
      '  The token holder cannot access any blocks not listed in the token.',
    );

    return 0;
  }
}

/// Extracts content from a .zgl file using a selective disclosure token.
///
/// Usage:
///   zegel extract-with-token <file.zgl> --token <token.json> -o <output-file>
///
/// Only the blocks listed in the token can be decrypted and extracted.
/// No master key is required - the token contains per-block keys.
class ExtractWithTokenCommand extends Command<int> {
  @override
  final String name = 'extract-with-token';

  @override
  String get description =>
      'Extract content from a .zgl file using a disclosure token.\n'
      '\n'
      'Decrypts and extracts only the blocks listed in the token.\n'
      'No master key is required - the token contains per-block\n'
      'derived keys. Blocks not included in the token remain\n'
      'encrypted and inaccessible.\n'
      '\n'
      'The token is typically generated by "zegel disclose" and\n'
      'sent to a third party who needs partial access.\n'
      '\n'
      'Exit codes:\n'
      '  0  Extraction complete\n'
      '  1  Error (tampered, invalid format, expired token)\n'
      '\n'
      'Examples:\n'
      '  zegel extract-with-token report.zgl --token token.json -o partial.pdf\n'
      '  zegel extract-with-token doc.zgl -t token.json --metadata-only\n'
      '  zegel extract-with-token doc.zgl -t token.json -o output.pdf --force';

  @override
  final String invocation =
      'zegel extract-with-token <file.zgl> [options]';

  ExtractWithTokenCommand() {
    argParser.addOption(
      'token',
      abbr: 't',
      help: 'Path to the disclosure token JSON file\n'
          '(generated by "zegel disclose").',
      valueHelp: 'path',
      mandatory: true,
    );

    addOutputOption(
      argParser,
      help: 'Output file path for the extracted content.\n'
          'Defaults to "partial_<original-filename>".',
    );

    argParser.addFlag(
      'force',
      abbr: 'f',
      help: 'Overwrite the output file if it already exists.',
      defaultsTo: false,
    );

    argParser.addFlag(
      'metadata-only',
      help: 'Only extract metadata blocks (no file content).\n'
          'Prints metadata to stdout.',
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

    // Read the disclosure token.
    final tokenPath = argResults!['token'] as String;
    final tokenFile = File(tokenPath);

    if (!tokenFile.existsSync()) {
      exitError('Token file not found: $tokenPath');
    }

    Map<String, dynamic> token;
    try {
      final tokenJson = tokenFile.readAsStringSync();
      token = jsonDecode(tokenJson) as Map<String, dynamic>;
    } on FormatException catch (e) {
      exitError('Invalid token file: ${e.message}');
    }

    // Validate token structure.
    if (token['version'] == null) {
      exitError('Invalid token: missing "version" field.');
    }
    if (token['merkle_root'] == null) {
      exitError('Invalid token: missing "merkle_root" field.');
    }
    if (token['block_keys'] == null) {
      exitError('Invalid token: missing "block_keys" field.');
    }

    // Check token expiration.
    if (token['token_expires'] != null) {
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        (token['token_expires'] as int) * 1000,
        isUtc: true,
      );
      if (DateTime.now().toUtc().isAfter(expiresAt)) {
        exitError(
          'Disclosure token has expired (${formatTimestamp(expiresAt)}).',
        );
      }
    }

    final fileBytes = Uint8List.fromList(file.readAsBytesSync());
    final metadataOnly = argResults!['metadata-only'] as bool;

    // Extract using the token via the library's reader.
    final reader = const ZegelReader();
    ZegelResult result;
    try {
      result = reader.extractWithToken(fileBytes, token);
    } on ZegelTamperedException catch (e) {
      stderr.writeln(
        '${Ansi.error('TAMPERED')} - File does not match the disclosure token.',
      );
      stderr.writeln('  Reason: ${e.message}');
      return 1;
    } on ZegelFormatException catch (e) {
      stderr.writeln('${Ansi.error('ERROR')} - Invalid file format.');
      stderr.writeln('  Reason: ${e.message}');
      return 1;
    }

    // Determine what we extracted.
    final blockKeys = token['block_keys'] as Map<String, dynamic>;
    final disclosedBlockCount = blockKeys.length;

    if (metadataOnly) {
      // Only print metadata.
      if (result.metadata != null && result.metadata!.isNotEmpty) {
        stdout.writeln(Ansi.header('Metadata:'));
        for (final entry in result.metadata!.entries) {
          stdout.writeln('  ${entry.key}: ${entry.value}');
        }
      } else {
        stdout.writeln('No metadata available in disclosed blocks.');
      }
      return 0;
    }

    // Write extracted content.
    if (result.content == null || result.content!.isEmpty) {
      stderr.writeln(Ansi.warning(
        'No content blocks were disclosed. '
        'Token may only contain metadata or non-content blocks.',
      ));

      // Still show metadata if available.
      if (result.metadata != null && result.metadata!.isNotEmpty) {
        stdout.writeln();
        stdout.writeln(Ansi.header('Metadata from disclosed blocks:'));
        for (final entry in result.metadata!.entries) {
          stdout.writeln('  ${entry.key}: ${entry.value}');
        }
      }
      return 0;
    }

    // Determine output path.
    final inspection = reader.inspect(fileBytes);
    final defaultFilename = inspection.filename ?? 'extracted';
    final outputPath =
        argResults!['output'] as String? ?? 'partial_$defaultFilename';

    if (outputPath.isEmpty) {
      exitError(
        'Could not determine output filename. Use -o to specify.',
      );
    }

    // Check if output exists.
    final outputFile = File(outputPath);
    final force = argResults!['force'] as bool;

    if (outputFile.existsSync() && !force) {
      exitError(
        'Output file already exists: $outputPath. Use --force to overwrite.',
      );
    }

    outputFile.writeAsBytesSync(result.content!);

    // Print success message.
    stdout.writeln(Ansi.success('Partial extraction complete.'));
    stdout.writeln();
    stdout.writeln('  Source:     $filePath');
    stdout.writeln('  Token:      $tokenPath');
    stdout.writeln('  Output:     $outputPath');
    stdout.writeln(
      '  Disclosed:  $disclosedBlockCount of ${inspection.blockCount} blocks',
    );
    stdout.writeln('  Size:       ${formatFileSize(result.content!.length)}');

    if (result.metadata != null && result.metadata!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('  Metadata:'));
      for (final entry in result.metadata!.entries) {
        stdout.writeln('    ${entry.key}: ${entry.value}');
      }
    }

    if (result.redactedBlocks != null && result.redactedBlocks!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.warning(
        '  Redacted blocks: ${result.redactedBlocks!.join(', ')}',
      ));
    }

    stdout.writeln();
    stdout.writeln(Ansi.info(
      'Note: This is a partial extraction. Blocks not included in the token '
      'are unavailable.',
    ));

    return 0;
  }
}
