import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Seals a file into a tamper-proof .zgl container.
///
/// Usage:
///   zegel seal <input-file> -k <key-hex> -o <output.zgl>
///       [--metadata key=value...] [--compress] [--password]
///       [--expires YYYY-MM-DD] [--recipient-id <hex>]
///       [--enable-disclosure]
class SealCommand extends Command<int> {
  @override
  final String name = 'seal';

  @override
  final String description =
      'Seal a file into a tamper-proof .zgl container.';

  @override
  final String invocation = 'zegel seal <input-file> [options]';

  SealCommand() {
    addKeyOptions(argParser);
    addOutputOption(
      argParser,
      help: 'Output .zgl file path. Defaults to <input>.zgl.',
    );

    argParser.addMultiOption(
      'metadata',
      abbr: 'm',
      help: 'Encrypted metadata as key=value pairs.',
      valueHelp: 'key=value',
    );

    argParser.addMultiOption(
      'public-metadata',
      help: 'Public (unencrypted) metadata as key=value pairs.',
      valueHelp: 'key=value',
    );

    argParser.addFlag(
      'compress',
      help: 'Enable zlib compression of content blocks.',
      defaultsTo: false,
    );

    argParser.addFlag(
      'password',
      help: 'Derive the master key from a password using Argon2id.',
      defaultsTo: false,
    );

    argParser.addOption(
      'expires',
      help: 'Cryptographic expiration date (YYYY-MM-DD). '
          'Content becomes undecryptable after this date.',
      valueHelp: 'YYYY-MM-DD',
    );

    argParser.addOption(
      'recipient-id',
      help: 'Recipient ID (hex) for canary trap fingerprinting.',
      valueHelp: 'hex',
    );

    argParser.addFlag(
      'enable-disclosure',
      help: 'Enable selective disclosure (adds disclosure index block).',
      defaultsTo: false,
    );

    argParser.addFlag(
      'key-commitment',
      help: 'Include key commitment hash to prevent salamander attacks.',
      defaultsTo: true,
    );

    argParser.addOption(
      'content-type',
      help: 'MIME type of the input file.',
      valueHelp: 'type',
    );

    argParser.addOption(
      'block-size',
      help: 'Block size in bytes (default: 65536).',
      valueHelp: 'bytes',
      defaultsTo: '65536',
    );

    argParser.addOption(
      'previous-merkle-root',
      help: 'Merkle root (hex) of a previous version for version chaining.',
      valueHelp: 'hex',
    );

    argParser.addOption(
      'previous-seal',
      help: 'Master seal (hex) of a previous version for version chaining.',
      valueHelp: 'hex',
    );
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('No input file specified.', usage);
    }

    final inputPath = argResults!.rest.first;
    final inputFile = File(inputPath);

    if (!inputFile.existsSync()) {
      exitError('Input file not found: $inputPath');
    }

    // Determine output path.
    final outputPath = argResults!['output'] as String? ?? '$inputPath.zgl';

    // Parse master key.
    final bool usePassword = argResults!['password'] as bool;
    Uint8List masterKey;

    if (usePassword) {
      // Prompt for password securely.
      stderr.write('Enter password: ');
      final password = _readPassword();
      stderr.write('Confirm password: ');
      final confirm = _readPassword();

      if (password != confirm) {
        exitError('Passwords do not match.');
      }

      if (password.length < 8) {
        stderr.writeln(Ansi.warning(
          'Warning: Password is very short. Consider using at least 12 characters.',
        ));
      }

      // The library handles Argon2id derivation internally.
      masterKey = Uint8List.fromList(password.codeUnits);
    } else {
      masterKey = parseKeyFromArgs(argResults!);

      if (masterKey.length != 32) {
        exitError(
          'Master key must be exactly 32 bytes (64 hex characters). '
          'Got ${masterKey.length} bytes.',
        );
      }
    }

    // Read input file.
    final content = inputFile.readAsBytesSync();
    final filename = inputFile.uri.pathSegments.last;

    // Parse metadata.
    Map<String, dynamic>? metadata;
    final metadataArgs = argResults!['metadata'] as List<String>;
    if (metadataArgs.isNotEmpty) {
      metadata = <String, dynamic>{};
      for (final entry in metadataArgs) {
        final eqIndex = entry.indexOf('=');
        if (eqIndex < 1) {
          exitError(
            'Invalid metadata format: "$entry". Expected key=value.',
          );
        }
        metadata[entry.substring(0, eqIndex)] = entry.substring(eqIndex + 1);
      }
    }

    // Parse public metadata.
    Map<String, dynamic>? publicMetadata;
    final publicMetadataArgs = argResults!['public-metadata'] as List<String>;
    if (publicMetadataArgs.isNotEmpty) {
      publicMetadata = <String, dynamic>{};
      for (final entry in publicMetadataArgs) {
        final eqIndex = entry.indexOf('=');
        if (eqIndex < 1) {
          exitError(
            'Invalid public metadata format: "$entry". Expected key=value.',
          );
        }
        publicMetadata[entry.substring(0, eqIndex)] =
            entry.substring(eqIndex + 1);
      }
    }

    // Parse expiration date.
    DateTime? expiration;
    final expiresStr = argResults!['expires'] as String?;
    if (expiresStr != null) {
      expiration = parseExpirationDate(expiresStr);
    }

    // Parse recipient ID for canary trap.
    Uint8List? recipientId;
    final recipientIdHex = argResults!['recipient-id'] as String?;
    if (recipientIdHex != null) {
      recipientId = hexDecode(recipientIdHex, label: 'recipient-id');
      if (recipientId.length != 32) {
        exitError(
          'Recipient ID must be exactly 32 bytes (64 hex characters). '
          'Got ${recipientId.length} bytes.',
        );
      }
    }

    // Parse content type.
    final contentType = argResults!['content-type'] as String? ??
        _guessContentType(inputPath);

    // Parse version chaining. Compute the chain hash from previous root + seal.
    Uint8List? versionChainHash;
    final prevMerkleRootHex =
        argResults!['previous-merkle-root'] as String?;
    final prevSealHex = argResults!['previous-seal'] as String?;
    if (prevMerkleRootHex != null && prevSealHex != null) {
      final prevRoot =
          hexDecode(prevMerkleRootHex, label: 'previous-merkle-root');
      final prevSeal = hexDecode(prevSealHex, label: 'previous-seal');
      versionChainHash = ContentVersioning.computeChainHash(prevRoot, prevSeal);
    } else if (prevMerkleRootHex != null || prevSealHex != null) {
      exitError(
        'Both --previous-merkle-root and --previous-seal must be provided '
        'for version chaining.',
      );
    }

    // Parse Argon2 parameters (password-derived keys).
    int? argon2TimeCost;
    int? argon2MemoryCost;
    if (usePassword) {
      argon2TimeCost = 3;
      argon2MemoryCost = 65536;
    }

    // Build immutable options.
    final options = ZegelOptions(
      contentType: contentType,
      filename: filename,
      metadata: metadata,
      compress: argResults!['compress'] as bool,
      argon2TimeCost: argon2TimeCost,
      argon2MemoryCost: argon2MemoryCost,
      expiration: expiration,
      recipientId: recipientId,
      publicMetadata: publicMetadata,
      versionChainHash: versionChainHash,
      enableKeyCommitment: argResults!['key-commitment'] as bool,
      enableSelectiveDisclosure: argResults!['enable-disclosure'] as bool,
      blockSize: int.parse(argResults!['block-size'] as String),
    );

    // Create the sealed container.
    final writer = ZegelWriter(masterKey, options);
    final sealedBytes = writer.seal(Uint8List.fromList(content));

    // Write output file.
    final outputFile = File(outputPath);
    outputFile.writeAsBytesSync(sealedBytes);

    // Print success message.
    stdout.writeln(Ansi.success('Sealed successfully.'));
    stdout.writeln();
    stdout.writeln('  Input:    $inputPath (${formatFileSize(content.length)})');
    stdout.writeln('  Output:   $outputPath (${formatFileSize(sealedBytes.length)})');
    stdout.writeln('  Filename: $filename');
    stdout.writeln('  Type:     $contentType');

    if (metadataArgs.isNotEmpty) {
      stdout.writeln('  Metadata: ${metadataArgs.length} entries (encrypted)');
    }
    if (publicMetadataArgs.isNotEmpty) {
      stdout.writeln('  Public:   ${publicMetadataArgs.length} entries');
    }
    if (expiresStr != null) {
      stdout.writeln('  Expires:  $expiresStr');
    }
    if (recipientIdHex != null) {
      stdout.writeln('  Canary:   enabled (recipient fingerprinted)');
    }
    if (argResults!['compress'] as bool) {
      stdout.writeln('  Compress: enabled');
    }
    if (argResults!['enable-disclosure'] as bool) {
      stdout.writeln('  Disclosure: enabled');
    }

    return 0;
  }

  /// Reads a password from stdin without echoing characters.
  String _readPassword() {
    if (stdin.hasTerminal) {
      stdin.echoMode = false;
      try {
        final password = stdin.readLineSync() ?? '';
        stderr.writeln(); // Newline after hidden input.
        return password;
      } finally {
        stdin.echoMode = true;
      }
    }
    // Non-interactive: just read a line.
    return stdin.readLineSync() ?? '';
  }

  /// Guesses the MIME content type from the file extension.
  String _guessContentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    const mimeTypes = <String, String>{
      'txt': 'text/plain',
      'html': 'text/html',
      'htm': 'text/html',
      'css': 'text/css',
      'js': 'application/javascript',
      'json': 'application/json',
      'xml': 'application/xml',
      'pdf': 'application/pdf',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'svg': 'image/svg+xml',
      'mp3': 'audio/mpeg',
      'mp4': 'video/mp4',
      'zip': 'application/zip',
      'gz': 'application/gzip',
      'tar': 'application/x-tar',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'csv': 'text/csv',
      'md': 'text/markdown',
      'dart': 'text/x-dart',
    };
    return mimeTypes[ext] ?? 'application/octet-stream';
  }
}
