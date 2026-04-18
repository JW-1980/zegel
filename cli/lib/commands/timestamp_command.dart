import 'dart:convert';
import 'dart:io' hide BytesBuilder;
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Parent command for trusted timestamp operations.
///
/// Usage:
///   zegel timestamp &lt;subcommand&gt; [options]
///
/// Subcommands:
///   create  Create a timestamp for a .zgl file
///   verify  Verify an embedded timestamp
class TimestampCommand extends Command<int> {
  @override
  final String name = 'timestamp';

  @override
  String get description =>
      'Trusted timestamp operations.\n'
      '\n'
      'Timestamps provide provable creation times for sealed files,\n'
      'independent of local system clocks. This helps prevent\n'
      'time-manipulation attacks on expiration features.\n'
      '\n'
      'Subcommands:\n'
      '  create  Create a timestamp for a .zgl file\n'
      '  verify  Verify an embedded timestamp\n'
      '\n'
      'Examples:\n'
      '  zegel timestamp create document.zgl -k <key> --tsa https://tsa.example.com\n'
      '  zegel timestamp verify document.zgl -k <key>';

  TimestampCommand() {
    addSubcommand(TimestampCreateCommand());
    addSubcommand(TimestampVerifyCommand());
  }

  @override
  Future<int> run() async {
    // Show help if no subcommand specified.
    printUsage();
    return 0;
  }
}

/// Creates a timestamp for a .zgl file.
class TimestampCreateCommand extends Command<int> {
  @override
  final String name = 'create';

  @override
  String get description =>
      'Create a timestamp for a .zgl file.\n'
      '\n'
      'Creates a timestamp token that binds the file\'s Merkle root and\n'
      'master seal to a specific point in time. The timestamp can be\n'
      'created locally (signed with a provided key) or requested from\n'
      'an external TSA (RFC 3161).\n'
      '\n'
      'Local timestamps are signed with the master key by default, or\n'
      'with a separate signer key if specified. TSA timestamps require\n'
      'network access to the specified TSA URL.\n'
      '\n'
      'Exit codes:\n'
      '  0  Timestamp created successfully\n'
      '  1  Error\n'
      '\n'
      'Examples:\n'
      '  zegel timestamp create document.zgl -k <key> -o timestamp.json\n'
      '  zegel timestamp create document.zgl -k <key> --tsa https://freetsa.org/tsr\n'
      '  zegel timestamp create document.zgl -k <key> --signer-key <hex> -o timestamp.json';

  @override
  final String invocation = 'zegel timestamp create <file.zgl> [options]';

  TimestampCreateCommand() {
    addKeyOptions(argParser);
    addOutputOption(
      argParser,
      help: 'Output path for the timestamp token file.',
    );

    argParser.addOption(
      'tsa',
      help:
          'URL of a trusted timestamping authority (RFC 3161).\n'
          'If not specified, creates a local timestamp.',
      valueHelp: 'url',
    );

    argParser.addOption(
      'signer-key',
      help:
          'Key for signing local timestamps (hex).\n'
          'If not specified, uses the master key.',
      valueHelp: 'hex',
    );

    argParser.addOption(
      'signer-key-file',
      help: 'Path to a file containing the signer key.',
      valueHelp: 'path',
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

    // Parse master key.
    final masterKey = parseKeyFromArgs(argResults!);
    if (masterKey.length != 32) {
      exitError(
        'Master key must be exactly 32 bytes (64 hex characters). '
        'Got ${masterKey.length} bytes.',
      );
    }

    final tsaUrl = argResults!['tsa'] as String?;
    final outputPath = argResults!['output'] as String?;

    final fileBytes = Uint8List.fromList(file.readAsBytesSync());

    // Verify the file first.
    const reader = ZegelReader();
    try {
      reader.verify(fileBytes, masterKey);
    } on ZegelException catch (e) {
      exitError('File verification failed: ${e.message}');
    }

    // Parse header to get Merkle root.
    final rawHeader = RawZegelHeader.parse(fileBytes);

    // Extract master seal from file footer.
    final masterSeal = Uint8List.sublistView(
      fileBytes,
      fileBytes.length - ZegelFormat.sealSize,
    );

    Map<String, dynamic> timestampToken;

    if (tsaUrl != null && tsaUrl.isNotEmpty) {
      // Create TSA request (for external TSA).
      final request = TrustedTimestamp.createRequest(
        rawHeader.merkleRoot,
        masterSeal,
      );

      // Note: Actual TSA communication would require HTTP client.
      // For now, we create a local timestamp and note the TSA URL.
      stdout.writeln(
        Ansi.warning('Note: External TSA communication not implemented.'),
      );
      stdout.writeln('Creating local timestamp instead.');
      stdout.writeln('TSA URL would be: $tsaUrl');
      stdout.writeln();

      // Parse signer key.
      Uint8List signerKey = masterKey;
      final signerKeyHex = argResults!['signer-key'] as String?;
      final signerKeyFilePath = argResults!['signer-key-file'] as String?;

      if (signerKeyHex != null && signerKeyHex.isNotEmpty) {
        signerKey = hexDecode(signerKeyHex, label: 'signer-key');
      } else if (signerKeyFilePath != null && signerKeyFilePath.isNotEmpty) {
        signerKey = readKeyFile(signerKeyFilePath);
      }

      timestampToken = TrustedTimestamp.createLocalToken(
        rawHeader.merkleRoot,
        masterSeal,
        signerKey,
      );
      timestampToken['tsa_url'] = tsaUrl;
      timestampToken['tsa_request'] = request;
    } else {
      // Create local timestamp.
      Uint8List signerKey = masterKey;
      final signerKeyHex = argResults!['signer-key'] as String?;
      final signerKeyFilePath = argResults!['signer-key-file'] as String?;

      if (signerKeyHex != null && signerKeyHex.isNotEmpty) {
        signerKey = hexDecode(signerKeyHex, label: 'signer-key');
      } else if (signerKeyFilePath != null && signerKeyFilePath.isNotEmpty) {
        signerKey = readKeyFile(signerKeyFilePath);
      }

      if (signerKey.length != 32) {
        exitError(
          'Signer key must be exactly 32 bytes. '
          'Got ${signerKey.length} bytes.',
        );
      }

      timestampToken = TrustedTimestamp.createLocalToken(
        rawHeader.merkleRoot,
        masterSeal,
        signerKey,
      );
    }

    // Add file info to token.
    timestampToken['file'] = filePath;
    timestampToken['created'] = DateTime.now().toUtc().toIso8601String();

    // Output the token.
    final tokenJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(timestampToken);

    if (outputPath != null && outputPath.isNotEmpty) {
      final outputFile = File(outputPath);
      outputFile.writeAsStringSync(tokenJson);
      stdout.writeln(Ansi.success('Timestamp created successfully.'));
      stdout.writeln();
      stdout.writeln('  File:      $filePath');
      stdout.writeln('  Output:    $outputPath');
      stdout.writeln('  Type:      ${timestampToken['type']}');
      final epochSeconds = timestampToken['timestamp'] as int;
      final dt = DateTime.fromMillisecondsSinceEpoch(
        epochSeconds * 1000,
        isUtc: true,
      );
      stdout.writeln('  Timestamp: ${formatTimestamp(dt)}');
    } else {
      // Output to stdout.
      stdout.writeln(tokenJson);
    }

    return 0;
  }
}

/// Verifies an embedded timestamp in a .zgl file.
class TimestampVerifyCommand extends Command<int> {
  @override
  final String name = 'verify';

  @override
  String get description =>
      'Verify a timestamp token for a .zgl file.\n'
      '\n'
      'Verifies that a timestamp token matches the specified .zgl file\n'
      'and that the signature is valid. For local timestamps, the signer\n'
      'key must be provided (or the master key is used by default).\n'
      '\n'
      'Exit codes:\n'
      '  0  Timestamp is valid\n'
      '  1  Timestamp is invalid or error\n'
      '\n'
      'Examples:\n'
      '  zegel timestamp verify document.zgl -k <key> --token timestamp.json\n'
      '  zegel timestamp verify document.zgl -k <key> --token timestamp.json --signer-key <hex>';

  @override
  final String invocation = 'zegel timestamp verify <file.zgl> [options]';

  TimestampVerifyCommand() {
    addKeyOptions(argParser);

    argParser.addOption(
      'token',
      abbr: 't',
      help: 'Path to the timestamp token file.',
      valueHelp: 'path',
      mandatory: true,
    );

    argParser.addOption(
      'signer-key',
      help:
          'Key used for signing local timestamps (hex).\n'
          'If not specified, uses the master key.',
      valueHelp: 'hex',
    );

    argParser.addOption(
      'signer-key-file',
      help: 'Path to a file containing the signer key.',
      valueHelp: 'path',
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

    // Parse master key.
    final masterKey = parseKeyFromArgs(argResults!);
    if (masterKey.length != 32) {
      exitError(
        'Master key must be exactly 32 bytes (64 hex characters). '
        'Got ${masterKey.length} bytes.',
      );
    }

    // Read timestamp token.
    final tokenPath = argResults!['token'] as String;
    final tokenFile = File(tokenPath);

    if (!tokenFile.existsSync()) {
      exitError('Token file not found: $tokenPath');
    }

    Map<String, dynamic> token;
    try {
      token = jsonDecode(tokenFile.readAsStringSync()) as Map<String, dynamic>;
    } on FormatException catch (e) {
      exitError('Invalid token file: ${e.message}');
    }

    final fileBytes = Uint8List.fromList(file.readAsBytesSync());

    // Verify the file first.
    const reader = ZegelReader();
    try {
      reader.verify(fileBytes, masterKey);
    } on ZegelException catch (e) {
      exitError('File verification failed: ${e.message}');
    }

    // Parse header to get Merkle root.
    final rawHeader = RawZegelHeader.parse(fileBytes);

    // Extract master seal from file footer.
    final masterSeal = Uint8List.sublistView(
      fileBytes,
      fileBytes.length - ZegelFormat.sealSize,
    );

    // Determine signer key.
    Uint8List signerKey = masterKey;
    final signerKeyHex = argResults!['signer-key'] as String?;
    final signerKeyFilePath = argResults!['signer-key-file'] as String?;

    if (signerKeyHex != null && signerKeyHex.isNotEmpty) {
      signerKey = hexDecode(signerKeyHex, label: 'signer-key');
    } else if (signerKeyFilePath != null && signerKeyFilePath.isNotEmpty) {
      signerKey = readKeyFile(signerKeyFilePath);
    }

    if (signerKey.length != 32) {
      exitError(
        'Signer key must be exactly 32 bytes. '
        'Got ${signerKey.length} bytes.',
      );
    }

    // Check token type.
    final tokenType = token['type'] as String?;
    if (tokenType != 'local') {
      stdout.writeln(
        Ansi.warning(
          'Warning: Token type "$tokenType" may not be verifiable locally.',
        ),
      );
    }

    // Verify the token.
    final isValid = TrustedTimestamp.verifyLocalToken(
      token,
      rawHeader.merkleRoot,
      masterSeal,
      signerKey,
    );

    // Check Merkle root matches.
    final tokenMerkleRoot = token['merkle_root'] as String?;
    final fileMerkleRoot = hexEncode(rawHeader.merkleRoot);
    final merkleRootMatches = tokenMerkleRoot == fileMerkleRoot;

    if (isValid && merkleRootMatches) {
      final epochSeconds = token['timestamp'] as int;
      final dt = DateTime.fromMillisecondsSinceEpoch(
        epochSeconds * 1000,
        isUtc: true,
      );

      stdout.writeln(Ansi.success('Timestamp is VALID.'));
      stdout.writeln();
      stdout.writeln('  File:        $filePath');
      stdout.writeln('  Token:       $tokenPath');
      stdout.writeln('  Timestamp:   ${formatTimestamp(dt)}');
      stdout.writeln('  Type:        ${token['type']}');
      stdout.writeln('  Merkle root: matches');
      return 0;
    } else {
      stdout.writeln(Ansi.error('Timestamp is INVALID.'));
      stdout.writeln();
      stdout.writeln('  File:        $filePath');
      stdout.writeln('  Token:       $tokenPath');

      if (!merkleRootMatches) {
        stdout.writeln('  Merkle root: MISMATCH');
        stdout.writeln('    Token:  $tokenMerkleRoot');
        stdout.writeln('    File:   $fileMerkleRoot');
      } else {
        stdout.writeln('  Signature:   INVALID');
      }

      stdout.writeln();
      stdout.writeln(
        'The timestamp does not match the file or has been tampered with.',
      );
      return 1;
    }
  }
}
