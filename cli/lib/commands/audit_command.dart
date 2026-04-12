import 'dart:convert';
import 'dart:io' hide BytesBuilder;
import 'dart:math';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Parent command for audit trail operations.
///
/// Usage:
///   zegel audit <subcommand> [options]
///
/// Subcommands:
///   view          View audit trail entries in a .zgl file
///   add           Add a new audit entry to a .zgl file
///   verify-chain  Verify the integrity of the audit chain
class AuditCommand extends Command<int> {
  @override
  final String name = 'audit';

  @override
  String get description => 'Audit trail operations for .zgl files.\n'
      '\n'
      'The audit trail is a tamper-evident append-only log that records\n'
      'actions performed on a sealed file. Each entry is hash-chained to\n'
      'the previous entry, making any modification detectable.\n'
      '\n'
      'Subcommands:\n'
      '  view          View all audit trail entries\n'
      '  add           Add a new audit entry\n'
      '  verify-chain  Verify the audit chain integrity\n'
      '\n'
      'Examples:\n'
      '  zegel audit view document.zgl -k <key>\n'
      '  zegel audit add document.zgl -k <key> --actor "user:42" --action "verified"\n'
      '  zegel audit verify-chain document.zgl -k <key>';

  AuditCommand() {
    addSubcommand(AuditViewCommand());
    addSubcommand(AuditAddCommand());
    addSubcommand(AuditVerifyChainCommand());
  }

  @override
  Future<int> run() async {
    // Show help if no subcommand specified.
    printUsage();
    return 0;
  }
}

/// Views audit trail entries in a .zgl file.
class AuditViewCommand extends Command<int> {
  @override
  final String name = 'view';

  @override
  String get description => 'View audit trail entries in a .zgl file.\n'
      '\n'
      'Displays all audit entries including actor, action, timestamp,\n'
      'and chain hash for each entry.\n'
      '\n'
      'Exit codes:\n'
      '  0  Success\n'
      '  1  Error\n'
      '\n'
      'Examples:\n'
      '  zegel audit view document.zgl -k <key-hex>\n'
      '  zegel audit view report.zgl --key-file master.key --json';

  @override
  final String invocation = 'zegel audit view <file.zgl> [options]';

  AuditViewCommand() {
    addKeyOptions(argParser);
    argParser.addFlag(
      'json',
      help: 'Output entries as JSON array.',
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

    // Parse master key.
    final masterKey = parseKeyFromArgs(argResults!);
    if (masterKey.length != 32) {
      exitError(
        'Master key must be exactly 32 bytes (64 hex characters). '
        'Got ${masterKey.length} bytes.',
      );
    }

    final fileBytes = Uint8List.fromList(file.readAsBytesSync());

    // Verify the file first.
    const reader = ZegelReader();
    ZegelResult result;
    try {
      result = reader.verify(fileBytes, masterKey);
    } on ZegelException catch (e) {
      exitError('File verification failed: ${e.message}');
    }

    // Extract audit entries from the result.
    final auditTrail = result.auditTrail ?? <Map<String, dynamic>>[];
    final jsonOutput = argResults!['json'] as bool;

    if (jsonOutput) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(auditTrail));
      return 0;
    }

    if (auditTrail.isEmpty) {
      stdout.writeln(Ansi.info('No audit entries found in $filePath'));
      return 0;
    }

    stdout.writeln(Ansi.header('Audit Trail - $filePath'));
    stdout.writeln('${auditTrail.length} entries\n');

    for (int i = 0; i < auditTrail.length; i++) {
      final entry = auditTrail[i];
      final timestamp = entry['timestamp'] as int;
      final dt = DateTime.fromMillisecondsSinceEpoch(
        timestamp * 1000,
        isUtc: true,
      );

      stdout.writeln(Ansi.header('Entry ${i + 1}'));
      stdout.writeln('  Actor:      ${entry['actor']}');
      stdout.writeln('  Action:     ${entry['action']}');
      stdout.writeln('  Timestamp:  ${formatTimestamp(dt)}');
      if (entry['details'] != null) {
        stdout.writeln('  Details:    ${jsonEncode(entry['details'])}');
      }
      stdout.writeln('  Chain Hash: ${entry['chain_hash']}');
      stdout.writeln();
    }

    return 0;
  }
}

/// Adds a new audit entry to a .zgl file.
class AuditAddCommand extends Command<int> {
  @override
  final String name = 'add';

  @override
  String get description => 'Add a new audit entry to a .zgl file.\n'
      '\n'
      'Creates an audit entry with the specified actor, action, and optional\n'
      'details. The entry is hash-chained to the previous entry in the trail.\n'
      '\n'
      'Valid actions: sealed, verified, redacted, attested, disclosed,\n'
      'accessed, shared, modified, exported.\n'
      '\n'
      'Exit codes:\n'
      '  0  Entry added successfully\n'
      '  1  Error\n'
      '\n'
      'Examples:\n'
      '  zegel audit add doc.zgl -k <key> --actor "user:42:alice@corp" --action "verified"\n'
      '  zegel audit add doc.zgl -k <key> --actor "admin:1" --action "exported" --details \'{"destination":"archive"}\'';

  @override
  final String invocation = 'zegel audit add <file.zgl> [options]';

  AuditAddCommand() {
    addKeyOptions(argParser);
    addOutputOption(
      argParser,
      help: 'Output path for the updated .zgl file.\n'
          'Defaults to overwriting the input file.',
    );

    argParser.addOption(
      'actor',
      help: 'Actor identifier string.\n'
          'Recommended format: "user:id:name@example.com" or\n'
          '"role:id:description".',
      valueHelp: 'id',
      mandatory: true,
    );

    argParser.addOption(
      'action',
      help: 'Action being recorded.\n'
          'Common values: sealed, verified, redacted, attested,\n'
          'disclosed, accessed, shared, modified, exported.',
      valueHelp: 'action',
      mandatory: true,
    );

    argParser.addOption(
      'details',
      abbr: 'd',
      help: 'Additional details as a JSON object.',
      valueHelp: 'json',
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

    final actor = argResults!['actor'] as String;
    final action = argResults!['action'] as String;
    final detailsJson = argResults!['details'] as String?;

    if (actor.isEmpty) {
      exitError('Actor cannot be empty.');
    }

    if (action.isEmpty) {
      exitError('Action cannot be empty.');
    }

    // Parse details JSON if provided.
    Map<String, dynamic>? details;
    if (detailsJson != null && detailsJson.isNotEmpty) {
      try {
        details = jsonDecode(detailsJson) as Map<String, dynamic>;
      } on FormatException catch (e) {
        exitError('Invalid JSON in --details: ${e.message}');
      }
    }

    final fileBytes = Uint8List.fromList(file.readAsBytesSync());

    // Verify the file first.
    const reader = ZegelReader();
    ZegelResult result;
    try {
      result = reader.verify(fileBytes, masterKey);
    } on ZegelException catch (e) {
      exitError('File verification failed: ${e.message}');
    }

    // Get the last chain hash from existing entries.
    final existingEntries = result.auditTrail ?? <Map<String, dynamic>>[];
    Uint8List? previousChainHash;
    if (existingEntries.isNotEmpty) {
      final lastEntry = existingEntries.last;
      final lastHashHex = lastEntry['chain_hash'] as String;
      previousChainHash = hexDecode(lastHashHex, label: 'previous chain hash');
    }

    // Create the new audit entry.
    final newEntry = AuditTrail.createEntry(
      actor,
      action,
      details: details,
      previousChainHash: previousChainHash,
    );

    // Re-seal the file with the new audit block.
    final rawHeader = RawZegelHeader.parse(fileBytes);
    final updatedBytes = _resealWithAuditEntry(
      fileBytes,
      masterKey,
      rawHeader,
      newEntry,
    );

    // Write output file.
    final outputPath = argResults!['output'] as String? ?? filePath;
    final outputFile = File(outputPath);
    outputFile.writeAsBytesSync(updatedBytes);

    // Print success message.
    stdout.writeln(Ansi.success('Audit entry added successfully.'));
    stdout.writeln();
    stdout.writeln(
      '  File:       ${outputPath == filePath ? '$filePath (updated)' : outputPath}',
    );
    stdout.writeln('  Actor:      $actor');
    stdout.writeln('  Action:     $action');
    if (details != null) {
      stdout.writeln('  Details:    ${jsonEncode(details)}');
    }
    stdout.writeln('  Chain Hash: ${newEntry['chain_hash']}');
    stdout.writeln('  Total:      ${existingEntries.length + 1} entries');

    return 0;
  }

  /// Re-seals a file with an additional audit entry block.
  Uint8List _resealWithAuditEntry(
    Uint8List originalFileBytes,
    Uint8List masterKey,
    RawZegelHeader header,
    Map<String, dynamic> auditEntry,
  ) {
    final random = Random.secure();

    // The audit entry is stored as JSON in an AUDIT block.
    final auditJson = jsonEncode(auditEntry);
    final auditPlaintext = Uint8List.fromList(utf8.encode(auditJson));

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
      final Uint8List plaintext = cipher.process(input);

      plaintexts.add(plaintext);
      blockTypes.add(entry.type);
    }

    // Add the new audit block.
    plaintexts.add(auditPlaintext);
    blockTypes.add(ZegelFormat.blockAudit);

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

    // Rebuild the binary.
    final output = BytesBuilder();

    // Header.
    output.add(ZegelFormat.magic);
    output.addByte(header.versionMajor);
    output.addByte(header.versionMinor);
    output.add(_uint16BE(header.flags));
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
    if (header.flags & ZegelFormat.flagPasswordDerived != 0) {
      output.add(_uint32BE(header.argon2TimeCost!));
      output.add(_uint32BE(header.argon2MemoryCost!));
    }
    if (header.flags & ZegelFormat.flagHasExpiration != 0) {
      output.add(_uint64BE(header.expirationTimestamp!));
    }
    if (header.flags & ZegelFormat.flagHasCanary != 0) {
      output.add(header.recipientId!);
    }
    if (header.flags & ZegelFormat.flagSplitKey != 0) {
      output.addByte(header.splitKeyThreshold!);
      output.addByte(header.splitKeyTotal!);
    }
    if (header.flags & ZegelFormat.flagVersioned != 0) {
      output.add(header.versionChainHash!);
    }
    if (header.flags & ZegelFormat.flagHasPublicMetadata != 0) {
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

/// Verifies the integrity of the audit chain in a .zgl file.
class AuditVerifyChainCommand extends Command<int> {
  @override
  final String name = 'verify-chain';

  @override
  String get description => 'Verify the integrity of the audit chain.\n'
      '\n'
      'Recomputes the chain hash for each audit entry and verifies it\n'
      'matches the stored value. If any entry has been tampered with,\n'
      'verification will fail.\n'
      '\n'
      'Exit codes:\n'
      '  0  Chain is valid\n'
      '  1  Chain is invalid or error\n'
      '\n'
      'Examples:\n'
      '  zegel audit verify-chain document.zgl -k <key-hex>\n'
      '  zegel audit verify-chain report.zgl --key-file master.key';

  @override
  final String invocation = 'zegel audit verify-chain <file.zgl> [options]';

  AuditVerifyChainCommand() {
    addKeyOptions(argParser);
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

    final fileBytes = Uint8List.fromList(file.readAsBytesSync());

    // Verify the file first.
    const reader = ZegelReader();
    ZegelResult result;
    try {
      result = reader.verify(fileBytes, masterKey);
    } on ZegelException catch (e) {
      exitError('File verification failed: ${e.message}');
    }

    // Get audit entries.
    final auditTrail = result.auditTrail ?? <Map<String, dynamic>>[];

    if (auditTrail.isEmpty) {
      stdout.writeln(Ansi.info('No audit entries found in $filePath'));
      stdout.writeln('Nothing to verify.');
      return 0;
    }

    // Verify the chain using the library.
    final isValid = AuditTrail.verifyChain(auditTrail);

    if (isValid) {
      stdout.writeln(Ansi.success('Audit chain is VALID.'));
      stdout.writeln();
      stdout.writeln('  File:    $filePath');
      stdout.writeln('  Entries: ${auditTrail.length}');
      stdout.writeln(
        '  First:   ${auditTrail.first['action']} by ${auditTrail.first['actor']}',
      );
      stdout.writeln(
        '  Last:    ${auditTrail.last['action']} by ${auditTrail.last['actor']}',
      );
      return 0;
    } else {
      stdout.writeln(Ansi.error('Audit chain is INVALID.'));
      stdout.writeln();
      stdout.writeln('The audit trail has been tampered with.');
      stdout.writeln('One or more entries have been modified after creation.');
      return 1;
    }
  }
}
