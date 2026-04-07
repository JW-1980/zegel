import 'dart:convert';
import 'dart:io' hide BytesBuilder;
import 'dart:math';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Parent command for canary trap fingerprinting operations.
///
/// Usage:
///   zegel canary <subcommand> [options]
///
/// Subcommands:
///   embed    Embed a canary trap for a specific recipient
///   identify Identify which recipient leaked a file
class CanaryCommand extends Command<int> {
  @override
  final String name = 'canary';

  @override
  String get description => 'Canary trap fingerprinting operations.\n'
      '\n'
      'Canary traps embed invisible, recipient-specific markers in sealed\n'
      'files. If a file is leaked, the markers can identify which recipient\n'
      'was the source of the leak.\n'
      '\n'
      'Subcommands:\n'
      '  embed    Embed canary for a recipient in a .zgl file\n'
      '  identify Identify which recipient leaked a file\n'
      '\n'
      'Examples:\n'
      '  zegel canary embed doc.zgl -k <key> --recipient alice123 -o doc_alice.zgl\n'
      '  zegel canary identify leaked.zgl -k <key> --recipients alice123,bob456,charlie789';

  CanaryCommand() {
    addSubcommand(CanaryEmbedCommand());
    addSubcommand(CanaryIdentifyCommand());
  }

  @override
  Future<int> run() async {
    // Show help if no subcommand specified.
    printUsage();
    return 0;
  }
}

/// Embeds a canary trap for a specific recipient in a .zgl file.
class CanaryEmbedCommand extends Command<int> {
  @override
  final String name = 'embed';

  @override
  String get description => 'Embed a canary trap for a specific recipient.\n'
      '\n'
      'Creates a copy of the sealed file with invisible fingerprinting that\n'
      'is unique to the specified recipient. The canary padding is derived\n'
      'deterministically from the master key and recipient ID, so the same\n'
      'recipient always gets the same fingerprint.\n'
      '\n'
      'The recipient ID should be a unique identifier (e.g., email, user ID,\n'
      'department code). It is hashed internally to produce a 32-byte ID.\n'
      '\n'
      'Exit codes:\n'
      '  0  Canary embedded successfully\n'
      '  1  Error\n'
      '\n'
      'Examples:\n'
      '  zegel canary embed document.zgl -k <key> --recipient alice@corp.com -o document_alice.zgl\n'
      '  zegel canary embed report.zgl -k <key> --recipient "dept:legal:42" -o report_legal.zgl';

  @override
  final String invocation = 'zegel canary embed <file.zgl> [options]';

  CanaryEmbedCommand() {
    addKeyOptions(argParser);
    addOutputOption(
      argParser,
      help: 'Output path for the fingerprinted .zgl file.',
    );

    argParser.addOption(
      'recipient',
      abbr: 'r',
      help: 'Recipient identifier string.\n'
          'This is hashed to produce a 32-byte canary ID.',
      valueHelp: 'id',
      mandatory: true,
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

    final recipientStr = argResults!['recipient'] as String;
    if (recipientStr.isEmpty) {
      exitError('Recipient cannot be empty.');
    }

    // Hash the recipient string to get a 32-byte ID.
    final recipientId = Uint8List.fromList(
      crypto.sha256.convert(utf8.encode(recipientStr)).bytes,
    );

    final outputPath = argResults!['output'] as String?;
    if (outputPath == null || outputPath.isEmpty) {
      exitError('Output path is required for canary embed.');
    }

    final fileBytes = Uint8List.fromList(file.readAsBytesSync());

    // Verify the file first.
    const reader = ZegelReader();
    try {
      reader.verify(fileBytes, masterKey);
    } on ZegelException catch (e) {
      exitError('File verification failed: ${e.message}');
    }

    // Parse header and re-seal with canary flag.
    final rawHeader = RawZegelHeader.parse(fileBytes);
    final canaryBytes = _resealWithCanary(
      fileBytes,
      masterKey,
      rawHeader,
      recipientId,
    );

    // Write output file.
    final outputFile = File(outputPath);
    outputFile.writeAsBytesSync(canaryBytes);

    // Print success message.
    stdout.writeln(Ansi.success('Canary trap embedded successfully.'));
    stdout.writeln();
    stdout.writeln('  Input:     $filePath');
    stdout.writeln('  Output:    $outputPath');
    stdout.writeln('  Recipient: $recipientStr');
    stdout.writeln('  ID (hex):  ${hexEncode(recipientId)}');

    return 0;
  }

  /// Re-seals a file with canary trap fingerprinting for a recipient.
  Uint8List _resealWithCanary(
    Uint8List originalFileBytes,
    Uint8List masterKey,
    RawZegelHeader header,
    Uint8List recipientId,
  ) {
    final random = Random.secure();

    // Build expiration date string for key derivation.
    String? expirationDateStr;
    if (header.expirationTimestamp != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(
        header.expirationTimestamp! * 1000,
        isUtc: true,
      );
      expirationDateStr = '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    }

    // Decrypt all existing blocks.
    final List<Uint8List> plaintexts = [];
    final List<int> blockTypes = [];
    int dataOffset = header.dataStart;

    for (int i = 0; i < header.blockCount; i++) {
      final entry = header.blockDirectory[i];
      final Uint8List ciphertext = Uint8List.sublistView(
        originalFileBytes,
        dataOffset,
        dataOffset + entry.ciphertextLength,
      );
      dataOffset += entry.ciphertextLength;

      if (entry.type == ZegelFormat.blockRedacted) {
        plaintexts.add(ciphertext);
        blockTypes.add(ZegelFormat.blockRedacted);
        continue;
      }

      // Derive original block key.
      final Uint8List blockKey = KeyDerivation.deriveBlockKey(
        masterKey,
        header.merkleRoot,
        header.salt,
        i,
        expirationDate: expirationDateStr,
      );

      // Decrypt.
      final cipher = _createGCMCipher(false, blockKey, entry.iv);
      final Uint8List input = Uint8List(ciphertext.length + entry.tag.length);
      input.setRange(0, ciphertext.length, ciphertext);
      input.setRange(ciphertext.length, input.length, entry.tag);
      Uint8List plaintext = cipher.process(input);

      // If this is a CONTENT block, add canary padding.
      if (entry.type == ZegelFormat.blockContent) {
        final padding = CanaryTrap.generatePadding(masterKey, recipientId, i);
        final bb = BytesBuilder(copy: false)
          ..add(plaintext)
          ..add(padding);
        plaintext = bb.takeBytes();
      }

      plaintexts.add(plaintext);
      blockTypes.add(entry.type);
    }

    // Compute new leaf hashes.
    final List<Uint8List> leafHashes = [];
    for (int i = 0; i < plaintexts.length; i++) {
      if (blockTypes[i] == ZegelFormat.blockRedacted) {
        leafHashes.add(header.blockDirectory[i].plaintextHash);
      } else {
        leafHashes.add(
          Uint8List.fromList(crypto.sha256.convert(plaintexts[i]).bytes),
        );
      }
    }

    // Build new Merkle tree.
    final Uint8List newMerkleRoot = MerkleTree.buildRoot(leafHashes);

    // Update flags to include HAS_CANARY.
    final newFlags = header.flags | ZegelFormat.flagHasCanary;

    // Derive new keys and re-encrypt.
    final List<Uint8List> newIvs = [];
    final List<Uint8List> newCiphertexts = [];
    final List<Uint8List> newTags = [];
    final List<Uint8List> newBlockKeys = [];

    for (int i = 0; i < plaintexts.length; i++) {
      if (blockTypes[i] == ZegelFormat.blockRedacted) {
        newIvs.add(header.blockDirectory[i].iv);
        newCiphertexts.add(plaintexts[i]);
        newTags.add(header.blockDirectory[i].tag);
        newBlockKeys.add(Uint8List(32));
        continue;
      }

      final Uint8List key = KeyDerivation.deriveBlockKey(
        masterKey,
        newMerkleRoot,
        header.salt,
        i,
        expirationDate: expirationDateStr,
      );
      newBlockKeys.add(key);

      final Uint8List iv = _randomBytes(random, ZegelFormat.ivSize);
      newIvs.add(iv);

      final cipher = _createGCMCipher(true, key, iv);
      final Uint8List encrypted = cipher.process(plaintexts[i]);

      final int ctLen = encrypted.length - ZegelFormat.tagSize;
      newCiphertexts.add(Uint8List.fromList(encrypted.sublist(0, ctLen)));
      newTags.add(Uint8List.fromList(encrypted.sublist(ctLen)));
    }

    // Compute key commitment if originally present.
    Uint8List? keyCommitment;
    if (header.flags & ZegelFormat.flagHasKeyCommitment != 0) {
      keyCommitment = KeyDerivation.computeKeyCommitment(newBlockKeys);
    }

    // Rebuild the binary with canary flag and recipient ID.
    final output = BytesBuilder();

    // Header.
    output.add(ZegelFormat.magic);
    output.addByte(header.versionMajor);
    output.addByte(header.versionMinor);
    output.add(_uint16BE(newFlags));
    output.add(_uint64BE(header.timestamp));

    // Content-Type.
    final Uint8List ctPadded = Uint8List(ZegelFormat.contentTypeSize);
    final ctEncoded = utf8.encode(header.contentType);
    final ctLen = ctEncoded.length > ZegelFormat.contentTypeSize
        ? ZegelFormat.contentTypeSize
        : ctEncoded.length;
    ctPadded.setRange(0, ctLen, ctEncoded);
    output.add(ctPadded);

    // Filename.
    final fnBytes = utf8.encode(header.filename);
    output.add(_uint16BE(fnBytes.length));
    output.add(fnBytes);

    // Salt.
    output.add(header.salt);

    // Block count.
    output.add(_uint32BE(plaintexts.length));

    // Extended header.
    if (newFlags & ZegelFormat.flagPasswordDerived != 0) {
      output.add(_uint32BE(header.argon2TimeCost!));
      output.add(_uint32BE(header.argon2MemoryCost!));
    }
    if (newFlags & ZegelFormat.flagHasExpiration != 0) {
      output.add(_uint64BE(header.expirationTimestamp!));
    }
    // Always write recipient ID since we're adding the canary flag.
    output.add(recipientId);

    if (newFlags & ZegelFormat.flagSplitKey != 0) {
      output.addByte(header.splitKeyThreshold!);
      output.addByte(header.splitKeyTotal!);
    }
    if (newFlags & ZegelFormat.flagVersioned != 0) {
      output.add(header.versionChainHash!);
    }
    if (newFlags & ZegelFormat.flagHasPublicMetadata != 0) {
      final pubMetaBytes = utf8.encode(jsonEncode(header.publicMetadata));
      output.add(_uint32BE(pubMetaBytes.length));
      output.add(pubMetaBytes);
    }

    // Block directory.
    for (int i = 0; i < plaintexts.length; i++) {
      output.addByte(blockTypes[i]);
      output.add(leafHashes[i]);
      output.add(_uint32BE(newCiphertexts[i].length));
      output.add(newIvs[i]);
      output.add(newTags[i]);
    }

    // Merkle root.
    output.add(newMerkleRoot);

    // Key commitment.
    if (keyCommitment != null) {
      output.add(keyCommitment);
    }

    // Encrypted block data.
    for (final ct in newCiphertexts) {
      output.add(ct);
    }

    // Master seal.
    final Uint8List preSealBytes = Uint8List.fromList(output.toBytes());
    final Uint8List sealKey = KeyDerivation.computeSealKey(
      newMerkleRoot,
      masterKey,
      header.salt,
    );
    final Uint8List masterSeal = KeyDerivation.computeMasterSeal(
      sealKey,
      preSealBytes,
    );
    output.add(masterSeal);

    return Uint8List.fromList(output.toBytes());
  }

  static GCMBlockCipher _createGCMCipher(
    bool encrypt,
    Uint8List key,
    Uint8List iv,
  ) {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      encrypt,
      AEADParameters(
        KeyParameter(key),
        ZegelFormat.tagSize * 8,
        iv,
        Uint8List(0),
      ),
    );
    return cipher;
  }

  static Uint8List _randomBytes(Random random, int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Uint8List _uint16BE(int value) {
    final bd = ByteData(2);
    bd.setUint16(0, value, Endian.big);
    return bd.buffer.asUint8List();
  }

  static Uint8List _uint32BE(int value) {
    final bd = ByteData(4);
    bd.setUint32(0, value, Endian.big);
    return bd.buffer.asUint8List();
  }

  static Uint8List _uint64BE(int value) {
    final bd = ByteData(8);
    bd.setUint64(0, value, Endian.big);
    return bd.buffer.asUint8List();
  }
}

/// Identifies which recipient leaked a file by checking canary traps.
class CanaryIdentifyCommand extends Command<int> {
  @override
  final String name = 'identify';

  @override
  String get description => 'Identify which recipient leaked a file.\n'
      '\n'
      'Given a potentially leaked file and a list of candidate recipients,\n'
      'this command checks the canary padding in content blocks to identify\n'
      'which recipient\'s copy was leaked.\n'
      '\n'
      'The recipient IDs should match those used during embedding. Each ID\n'
      'is hashed to produce the 32-byte canary ID for comparison.\n'
      '\n'
      'Exit codes:\n'
      '  0  Recipient identified\n'
      '  1  No match found or error\n'
      '\n'
      'Examples:\n'
      '  zegel canary identify leaked.zgl -k <key> --recipients alice@corp.com,bob@corp.com\n'
      '  zegel canary identify leaked.zgl -k <key> --recipients-file recipients.txt';

  @override
  final String invocation = 'zegel canary identify <file.zgl> [options]';

  CanaryIdentifyCommand() {
    addKeyOptions(argParser);

    argParser.addOption(
      'recipients',
      abbr: 'r',
      help: 'Comma-separated list of candidate recipient identifiers.',
      valueHelp: 'id1,id2,...',
    );

    argParser.addOption(
      'recipients-file',
      help: 'File containing recipient identifiers (one per line).',
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

    // Parse recipients list.
    final recipientsStr = argResults!['recipients'] as String?;
    final recipientsFile = argResults!['recipients-file'] as String?;

    List<String> recipientNames = [];
    if (recipientsStr != null && recipientsStr.isNotEmpty) {
      recipientNames = recipientsStr.split(',').map((s) => s.trim()).toList();
    } else if (recipientsFile != null && recipientsFile.isNotEmpty) {
      final rf = File(recipientsFile);
      if (!rf.existsSync()) {
        exitError('Recipients file not found: $recipientsFile');
      }
      recipientNames = rf
          .readAsStringSync()
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      exitError(
        'Recipient list must be provided via --recipients or --recipients-file.',
      );
    }

    if (recipientNames.isEmpty) {
      exitError('No recipients specified.');
    }

    // Hash each recipient name to get 32-byte IDs.
    final candidateIds = recipientNames.map((name) {
      return Uint8List.fromList(
        crypto.sha256.convert(utf8.encode(name)).bytes,
      );
    }).toList();

    final fileBytes = Uint8List.fromList(file.readAsBytesSync());

    // Verify the file first.
    const reader = ZegelReader();
    try {
      reader.verify(fileBytes, masterKey);
    } on ZegelException catch (e) {
      exitError('File verification failed: ${e.message}');
    }

    // Parse header for block access.
    final rawHeader = RawZegelHeader.parse(fileBytes);

    // Check if file has canary flag.
    if (rawHeader.flags & ZegelFormat.flagHasCanary == 0) {
      stdout.writeln(Ansi.warning(
        'Warning: This file does not have the HAS_CANARY flag set.',
      ));
      stdout.writeln('It may not contain canary fingerprinting.');
    }

    // Build expiration date string for key derivation.
    String? expirationDateStr;
    if (rawHeader.expirationTimestamp != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(
        rawHeader.expirationTimestamp! * 1000,
        isUtc: true,
      );
      expirationDateStr = '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    }

    // Decrypt CONTENT blocks and check for canary padding.
    int dataOffset = rawHeader.dataStart;
    String? identifiedRecipient;
    int matchedBlockIndex = -1;

    for (int i = 0; i < rawHeader.blockCount; i++) {
      final entry = rawHeader.blockDirectory[i];
      final Uint8List ciphertext = Uint8List.sublistView(
        fileBytes,
        dataOffset,
        dataOffset + entry.ciphertextLength,
      );
      dataOffset += entry.ciphertextLength;

      // Only check CONTENT blocks.
      if (entry.type != ZegelFormat.blockContent) continue;

      // Derive block key.
      final Uint8List blockKey = KeyDerivation.deriveBlockKey(
        masterKey,
        rawHeader.merkleRoot,
        rawHeader.salt,
        i,
        expirationDate: expirationDateStr,
      );

      // Decrypt.
      final cipher = _createGCMCipher(false, blockKey, entry.iv);
      final Uint8List input = Uint8List(ciphertext.length + entry.tag.length);
      input.setRange(0, ciphertext.length, ciphertext);
      input.setRange(ciphertext.length, input.length, entry.tag);
      final Uint8List blockContent = cipher.process(input);

      // Try to identify the recipient.
      final matchHex = CanaryTrap.identifyRecipient(
        blockContent,
        masterKey,
        i,
        candidateIds,
      );

      if (matchHex != null) {
        // Find the corresponding recipient name.
        for (int j = 0; j < candidateIds.length; j++) {
          if (hexEncode(candidateIds[j]) == matchHex) {
            identifiedRecipient = recipientNames[j];
            matchedBlockIndex = i;
            break;
          }
        }
        break;
      }
    }

    if (identifiedRecipient != null) {
      stdout.writeln(Ansi.success('Recipient IDENTIFIED.'));
      stdout.writeln();
      stdout.writeln('  File:      $filePath');
      stdout.writeln('  Recipient: $identifiedRecipient');
      stdout.writeln('  Block:     $matchedBlockIndex');
      stdout.writeln();
      stdout.writeln(
        'This copy of the file was distributed to "$identifiedRecipient".',
      );
      return 0;
    } else {
      stdout.writeln(Ansi.warning('No matching recipient found.'));
      stdout.writeln();
      stdout.writeln('  File:       $filePath');
      stdout.writeln('  Candidates: ${recipientNames.length}');
      stdout.writeln();
      stdout.writeln(
        'The file either has no canary padding or the source recipient\n'
        'is not in the provided candidate list.',
      );
      return 1;
    }
  }

  static GCMBlockCipher _createGCMCipher(
    bool encrypt,
    Uint8List key,
    Uint8List iv,
  ) {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      encrypt,
      AEADParameters(
        KeyParameter(key),
        ZegelFormat.tagSize * 8,
        iv,
        Uint8List(0),
      ),
    );
    return cipher;
  }
}
