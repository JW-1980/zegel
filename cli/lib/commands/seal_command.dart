import 'dart:io' hide BytesBuilder;
import 'dart:math';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Seals a file into a tamper-proof .zgl container.
///
/// Usage:
///   zegel seal &lt;input-file&gt; -k &lt;key-hex&gt; -o &lt;output.zgl&gt;
///       [--metadata key=value...] [--compress] [--password]
///       [--expires YYYY-MM-DD] [--recipient-id &lt;hex&gt;]
///       [--enable-disclosure] [--anonymous] [--classification &lt;level&gt;]
///       [--classification-authority &lt;name&gt;] [--regulatory-hold-until &lt;date&gt;]
///       [--tsa-url &lt;url&gt;] [--preserve-media-metadata]
class SealCommand extends Command<int> {
  @override
  final String name = 'seal';

  @override
  String get description =>
      'Seal a file into a tamper-proof .zgl container.\n'
      '\n'
      'Encrypts and integrity-protects a file using AES-256-GCM with a\n'
      'Merkle tree binding all blocks. The resulting .zgl file becomes\n'
      'physically unreadable if even a single byte is modified.\n'
      '\n'
      'Key can be provided as a 64-character hex string (-k) or read from\n'
      'a key file (--key-file). Use --password to derive a key from a\n'
      'passphrase via Argon2id.\n'
      '\n'
      'Exit codes:\n'
      '  0  Sealed successfully\n'
      '  1  Error (invalid arguments, file not found, etc.)\n'
      '\n'
      'Examples:\n'
      '  zegel seal document.pdf -k \$(cat master.key) -o document.pdf.zgl\n'
      '  zegel seal report.docx --key-file master.key --compress --metadata author=Alice\n'
      '  zegel seal secret.txt --password --expires 2025-12-31 -o secret.zgl\n'
      '  zegel seal contract.pdf -k <hex> --classification CONFIDENTIAL --classification-authority "Legal Dept"\n'
      '  zegel seal memo.txt -k <hex> --anonymous --recipient-id <hex>';

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
      help:
          'Cryptographic expiration date (YYYY-MM-DD). '
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

    argParser.addFlag(
      'anonymous',
      help:
          'Omit the original filename from the .zgl header.\n'
          'The content type is preserved but the filename field\n'
          'is set to an empty string.',
      defaultsTo: false,
    );

    argParser.addOption(
      'classification',
      help:
          'Classification level for the sealed file.\n'
          'Stored in public metadata for inspection without a key.\n'
          'Levels: PUBLIC, INTERNAL, CONFIDENTIAL, SECRET, TOP_SECRET.',
      valueHelp: 'level',
    );

    argParser.addOption(
      'classification-authority',
      help:
          'Name of the authority who set the classification level.\n'
          'Required when --classification is specified.',
      valueHelp: 'name',
    );

    argParser.addOption(
      'regulatory-hold-until',
      help:
          'Set a regulatory hold date (YYYY-MM-DD). Files under\n'
          'regulatory hold can be extracted only after the hold expires.\n'
          'Stored in public metadata.',
      valueHelp: 'YYYY-MM-DD',
    );

    argParser.addOption(
      'tsa-url',
      help:
          'URL of a trusted timestamping authority (TSA) to use\n'
          'for an RFC 3161 timestamp. The timestamp response is\n'
          'stored as a PROVENANCE block.',
      valueHelp: 'url',
    );

    argParser.addFlag(
      'preserve-media-metadata',
      help:
          'Preserve media metadata (EXIF, ID3, etc.) from the input\n'
          'file. By default, media metadata is stripped for privacy.\n'
          'When enabled, the original metadata is stored in a\n'
          'METADATA block.',
      defaultsTo: false,
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
    // Salt used for Argon2id password derivation, if applicable. When set,
    // the writer MUST reuse this exact salt so the reader can reproduce the
    // same derivation.
    Uint8List? passwordSalt;
    // Argon2id parameters; null unless --password was used.
    int? passwordTimeCost;
    int? passwordMemoryCost;

    if (usePassword) {
      // Prompt for password securely.
      stderr.write('Enter password: ');
      final password = _readPassword();
      stderr.write('Confirm password: ');
      final confirm = _readPassword();

      if (password != confirm) {
        exitError('Passwords do not match.');
      }

      if (password.length < 12) {
        stderr.writeln(
          Ansi.warning(
            'Warning: Password is shorter than 12 characters. '
            'Consider using a longer passphrase.',
          ),
        );
      }

      // Use OWASP 2024 recommended parameters for Argon2id. These match the
      // CLI help text and exceed the library minimums (t=2, m=19456 KiB).
      passwordTimeCost = 3;
      passwordMemoryCost = 65536; // 64 MiB

      // Generate the file salt ourselves so we can feed it to Argon2id AND
      // to the writer. Writer normally picks its own random salt when
      // options.salt is null; we override it here so reader can reproduce.
      final Random rng = Random.secure();
      passwordSalt = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        passwordSalt[i] = rng.nextInt(256);
      }

      // Spec (FORMAT_SPEC.md §5.2):
      //   master_key = Argon2id(password, salt, ops, mem_kib, lanes=1, len=32)
      masterKey = KeyDerivation.deriveKeyFromPassword(
        password,
        passwordSalt,
        iterations: passwordTimeCost,
        memoryKib: passwordMemoryCost,
      );
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
    final isAnonymous = argResults!['anonymous'] as bool;
    final filename = isAnonymous ? '' : inputFile.uri.pathSegments.last;

    // Parse metadata.
    Map<String, dynamic>? metadata;
    final metadataArgs = argResults!['metadata'] as List<String>;
    if (metadataArgs.isNotEmpty) {
      metadata = <String, dynamic>{};
      for (final entry in metadataArgs) {
        final eqIndex = entry.indexOf('=');
        if (eqIndex < 1) {
          exitError('Invalid metadata format: "$entry". Expected key=value.');
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
        publicMetadata[entry.substring(0, eqIndex)] = entry.substring(
          eqIndex + 1,
        );
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

    // Handle anonymous mode (already parsed above as isAnonymous).

    // Handle classification.
    final classificationStr = argResults!['classification'] as String?;
    final classificationAuthority =
        argResults!['classification-authority'] as String?;
    if (classificationStr != null) {
      try {
        validateClassificationLevel(classificationStr);
      } on FormatException catch (e) {
        exitError(e.message);
      }
      if (classificationAuthority == null || classificationAuthority.isEmpty) {
        exitError(
          '--classification-authority is required when --classification '
          'is specified.',
        );
      }
      // Add classification to public metadata.
      publicMetadata ??= <String, dynamic>{};
      publicMetadata['classification'] = classificationStr
          .toUpperCase()
          .replaceAll('-', '_');
      publicMetadata['classification_authority'] = classificationAuthority;
      publicMetadata['classification_date'] = DateTime.now()
          .toUtc()
          .toIso8601String();
    }

    // Handle regulatory hold.
    final regulatoryHoldStr = argResults!['regulatory-hold-until'] as String?;
    if (regulatoryHoldStr != null) {
      final holdDate = parseExpirationDate(regulatoryHoldStr);
      publicMetadata ??= <String, dynamic>{};
      publicMetadata['regulatory_hold_until'] =
          holdDate.millisecondsSinceEpoch ~/ 1000;
      publicMetadata['regulatory_hold_date_str'] = regulatoryHoldStr;
    }

    // Handle TSA URL (store as metadata for reference).
    final tsaUrl = argResults!['tsa-url'] as String?;
    if (tsaUrl != null) {
      publicMetadata ??= <String, dynamic>{};
      publicMetadata['tsa_url'] = tsaUrl;
      publicMetadata['tsa_timestamp_requested'] = DateTime.now()
          .toUtc()
          .toIso8601String();
    }

    // Parse content type.
    final contentType =
        argResults!['content-type'] as String? ?? _guessContentType(inputPath);

    // Parse version chaining. Compute the chain hash from previous root + seal.
    Uint8List? versionChainHash;
    final prevMerkleRootHex = argResults!['previous-merkle-root'] as String?;
    final prevSealHex = argResults!['previous-seal'] as String?;
    if (prevMerkleRootHex != null && prevSealHex != null) {
      final prevRoot = hexDecode(
        prevMerkleRootHex,
        label: 'previous-merkle-root',
      );
      final prevSeal = hexDecode(prevSealHex, label: 'previous-seal');
      versionChainHash = ContentVersioning.computeChainHash(prevRoot, prevSeal);
    } else if (prevMerkleRootHex != null || prevSealHex != null) {
      exitError(
        'Both --previous-merkle-root and --previous-seal must be provided '
        'for version chaining.',
      );
    }

    // Argon2 parameters for password-derived keys are set during key parsing
    // above. We forward them to the writer so the header records them.

    // Build immutable options.
    final options = ZegelOptions(
      contentType: contentType,
      filename: filename,
      metadata: metadata,
      compress: argResults!['compress'] as bool,
      argon2TimeCost: passwordTimeCost,
      argon2MemoryCost: passwordMemoryCost,
      expiration: expiration,
      recipientId: recipientId,
      publicMetadata: publicMetadata,
      versionChainHash: versionChainHash,
      // Password-derived files MUST enable key commitment per spec §5.2 v1.4.
      enableKeyCommitment: usePassword
          ? true
          : (argResults!['key-commitment'] as bool),
      enableSelectiveDisclosure: argResults!['enable-disclosure'] as bool,
      blockSize: int.parse(argResults!['block-size'] as String),
      // Reuse the Argon2 salt as the file salt so the reader can reproduce
      // the derivation. For non-password keys, let the writer choose.
      salt: passwordSalt,
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
    stdout.writeln(
      '  Input:    $inputPath (${formatFileSize(content.length)})',
    );
    stdout.writeln(
      '  Output:   $outputPath (${formatFileSize(sealedBytes.length)})',
    );
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
    if (isAnonymous) {
      stdout.writeln('  Anonymous: filename omitted from header');
    }
    if (classificationStr != null) {
      stdout.writeln('  Classification: ${classificationStr.toUpperCase()}');
      stdout.writeln('  Authority: $classificationAuthority');
    }
    if (regulatoryHoldStr != null) {
      stdout.writeln('  Regulatory hold: until $regulatoryHoldStr');
    }
    if (tsaUrl != null) {
      stdout.writeln('  TSA URL: $tsaUrl');
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
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'csv': 'text/csv',
      'md': 'text/markdown',
      'dart': 'text/x-dart',
    };
    return mimeTypes[ext] ?? 'application/octet-stream';
  }
}
