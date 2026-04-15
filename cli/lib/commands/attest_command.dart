import 'dart:convert';
import 'dart:io' hide BytesBuilder;
import 'dart:math';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Adds a co-signature attestation to a .zgl file.
///
/// Usage:
///   zegel attest &lt;file.zgl&gt; --signer-key &lt;hex&gt; --signer-id &lt;string&gt;
///       --statement "text" -k &lt;master-key-hex&gt; [--role &lt;role&gt;]
///
/// The attestation is an HMAC-SHA256 over the Merkle root, signer ID,
/// timestamp, and statement. Adding an attestation block changes the Merkle
/// tree, so the entire file is re-encrypted and re-sealed.
class AttestCommand extends Command<int> {
  @override
  final String name = 'attest';

  @override
  String get description => 'Add a co-signature attestation to a .zgl file.\n'
      '\n'
      'Creates an HMAC-SHA256 attestation over the Merkle root, signer ID,\n'
      'timestamp, statement, and role. The attestation is stored as an\n'
      'ATTESTATION block, which changes the Merkle tree and requires\n'
      're-encryption of all blocks.\n'
      '\n'
      'Both the signer key (--signer-key) and the master key (-k) are\n'
      'needed: the signer key creates the HMAC, and the master key is\n'
      'needed to re-encrypt the file after adding the attestation block.\n'
      '\n'
      'Use --role to specify the signer\'s role for attestation policy\n'
      'enforcement (see "zegel verify --check-attestation-policy").\n'
      '\n'
      'Exit codes:\n'
      '  0  Attestation added successfully\n'
      '  1  Error\n'
      '\n'
      'Examples:\n'
      '  zegel attest contract.zgl --signer-key <hex> --signer-id "alice@corp" -s "Reviewed" -k <master-hex>\n'
      '  zegel attest doc.zgl --signer-key-file signer.key --signer-id "notary:42" --role notary -s "Notarized" -k <hex> -o attested.zgl';

  @override
  final String invocation = 'zegel attest <file.zgl> [options]';

  AttestCommand() {
    argParser.addOption(
      'signer-key',
      help: 'Signer\'s 32-byte key as hex (64 characters).',
      valueHelp: 'hex',
    );

    argParser.addOption(
      'signer-key-file',
      help: 'Path to a file containing the signer key.',
      valueHelp: 'path',
    );

    argParser.addOption(
      'signer-id',
      help: 'Signer identifier string.\n'
          'Recommended format: "user:id:name@example.com" or\n'
          '"role:id:description".',
      valueHelp: 'id',
      mandatory: true,
    );

    argParser.addOption(
      'statement',
      abbr: 's',
      help: 'Attestation statement text describing what is being attested.',
      valueHelp: 'text',
      mandatory: true,
    );

    argParser.addOption(
      'role',
      abbr: 'r',
      help: 'Signer\'s role in the attestation workflow.\n'
          'Valid roles: owner, signer, witness, notary, auditor, reviewer.\n'
          'Roles are used by --check-attestation-policy during verification.',
      valueHelp: 'role',
    );

    addKeyOptions(argParser);
    addOutputOption(
      argParser,
      help: 'Output path for the attested .zgl file.\n'
          'Defaults to overwriting the input file.',
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

    // Parse signer key.
    final signerKeyHex = argResults!['signer-key'] as String?;
    final signerKeyFilePath = argResults!['signer-key-file'] as String?;
    Uint8List signerKey;

    if (signerKeyHex != null && signerKeyHex.isNotEmpty) {
      signerKey = hexDecode(signerKeyHex, label: 'signer-key');
    } else if (signerKeyFilePath != null && signerKeyFilePath.isNotEmpty) {
      signerKey = readKeyFile(signerKeyFilePath);
    } else {
      exitError(
        'Signer key must be provided via --signer-key <hex> or '
        '--signer-key-file <path>.',
      );
    }

    if (signerKey.length != 32) {
      exitError(
        'Signer key must be exactly 32 bytes. Got ${signerKey.length} bytes.',
      );
    }

    final signerId = argResults!['signer-id'] as String;
    final statement = argResults!['statement'] as String;
    final roleStr = argResults!['role'] as String?;

    if (signerId.isEmpty) {
      exitError('Signer ID cannot be empty.');
    }

    if (statement.isEmpty) {
      exitError('Statement cannot be empty.');
    }

    // Validate role if specified.
    String? role;
    if (roleStr != null && roleStr.isNotEmpty) {
      try {
        role = validateRole(roleStr);
      } on FormatException catch (e) {
        exitError(e.message);
      }
    }

    // Parse master key (needed to re-encrypt all blocks after adding
    // the attestation, since the Merkle root changes).
    final masterKey = parseKeyFromArgs(argResults!);
    if (masterKey.length != 32) {
      exitError(
        'Master key must be exactly 32 bytes (64 hex characters). '
        'Got ${masterKey.length} bytes.',
      );
    }

    final fileBytes = Uint8List.fromList(file.readAsBytesSync());

    // Parse raw header for detailed binary information.
    RawZegelHeader rawHeader;
    try {
      rawHeader = RawZegelHeader.parse(fileBytes);
    } on FormatException catch (e) {
      exitError('Invalid .zgl file: ${e.message}');
    }

    // Verify the file first using the library.
    const reader = ZegelReader();
    ZegelResult result;
    try {
      result = reader.verify(fileBytes, masterKey);
    } on ZegelException catch (e) {
      exitError(
        'File verification failed. Cannot attest to a tampered file. '
        '(${e.message})',
      );
    }

    // Create the attestation using the CURRENT Merkle root.
    // Note: after adding the attestation block, the Merkle root will change.
    // The attestation HMAC is bound to the original Merkle root, which proves
    // the signer attested to the file as it was before the block was added.
    final timestamp = DateTime.now().toUtc();
    final attestation = Attestation.createAttestation(
      rawHeader.merkleRoot,
      signerId,
      signerKey,
      statement,
      timestamp: timestamp,
    );

    // Add the role to the attestation if specified.
    if (role != null) {
      attestation['role'] = role;
    }

    // The attestation block plaintext is the JSON encoding.
    final attestationJson = jsonEncode(attestation);

    // Re-seal the file with the attestation block added.
    // Since a new block changes the Merkle root, all block keys change,
    // requiring re-encryption of every block.
    final attestedBytes = _resealWithAttestation(
      fileBytes,
      masterKey,
      rawHeader,
      Uint8List.fromList(utf8.encode(attestationJson)),
    );

    // Write output file.
    final outputPath = argResults!['output'] as String? ?? filePath;
    final outputFile = File(outputPath);
    outputFile.writeAsBytesSync(attestedBytes);

    // Print success message.
    stdout.writeln(Ansi.success('Attestation added successfully.'));
    stdout.writeln();
    stdout.writeln(
      '  File:      ${outputPath == filePath ? '$filePath (updated)' : outputPath}',
    );
    stdout.writeln('  Signer:    $signerId');
    if (role != null) {
      stdout.writeln('  Role:      $role');
    }
    stdout.writeln('  Statement: $statement');
    stdout.writeln('  Time:      ${formatTimestamp(timestamp)}');
    stdout.writeln('  HMAC:      ${attestation['hmac_hex']}');

    if (result.attestations != null) {
      stdout.writeln(
        '  Total:     ${result.attestations!.length + 1} attestation(s)',
      );
    }

    return 0;
  }

  /// Re-seals a file with an additional attestation block.
  ///
  /// This reconstructs the entire .zgl binary because adding a block changes
  /// the Merkle tree, invalidating all derived keys.
  Uint8List _resealWithAttestation(
    Uint8List originalFileBytes,
    Uint8List masterKey,
    RawZegelHeader header,
    Uint8List attestationPlaintext,
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

    // Decrypt all existing blocks to recover their plaintexts.
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
        // Preserve redacted blocks as-is.
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

      // Decrypt with the AAD bound to the original block position and salt.
      final Uint8List decryptAad = _buildBlockAad(
        entry.type,
        i,
        header.salt,
      );
      final cipher = _createGCMCipher(false, blockKey, entry.iv, decryptAad);
      final Uint8List input = Uint8List(ciphertext.length + entry.tag.length);
      input.setRange(0, ciphertext.length, ciphertext);
      input.setRange(ciphertext.length, input.length, entry.tag);
      final Uint8List plaintext = cipher.process(input);

      plaintexts.add(plaintext);
      blockTypes.add(entry.type);
    }

    // Add the attestation block.
    plaintexts.add(attestationPlaintext);
    blockTypes.add(ZegelFormat.blockAttestation);

    // Compute new leaf hashes.
    final List<Uint8List> leafHashes = [];
    for (int i = 0; i < plaintexts.length; i++) {
      if (blockTypes[i] == ZegelFormat.blockRedacted) {
        // Preserve the original hash for redacted blocks.
        leafHashes.add(header.blockDirectory[i].plaintextHash);
      } else {
        leafHashes.add(
          Uint8List.fromList(crypto.sha256.convert(plaintexts[i]).bytes),
        );
      }
    }

    // Build new Merkle tree.
    final Uint8List newMerkleRoot = MerkleTree.buildRoot(leafHashes);

    // Derive new per-block keys and re-encrypt.
    final List<Uint8List> newIvs = [];
    final List<Uint8List> newCiphertexts = [];
    final List<Uint8List> newTags = [];
    final List<Uint8List> newBlockKeys = [];

    for (int i = 0; i < plaintexts.length; i++) {
      if (blockTypes[i] == ZegelFormat.blockRedacted) {
        // Redacted blocks keep their random ciphertext.
        newIvs.add(header.blockDirectory[i].iv);
        newCiphertexts.add(plaintexts[i]);
        newTags.add(header.blockDirectory[i].tag);
        newBlockKeys.add(Uint8List(32)); // Placeholder.
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

      // Hedged nonce matching ZegelWriter: HKDF-derived XOR CSPRNG.
      final Uint8List derivedNonce = KeyDerivation.deriveBlockNonce(
        masterKey,
        newMerkleRoot,
        header.salt,
        i,
      );
      final Uint8List randomNonce = _randomBytes(random, ZegelFormat.ivSize);
      final Uint8List iv = Uint8List(ZegelFormat.ivSize);
      for (int b = 0; b < ZegelFormat.ivSize; b++) {
        iv[b] = derivedNonce[b] ^ randomNonce[b];
      }
      newIvs.add(iv);

      // AAD must match ZegelWriter: blockType(1) || blockIndex(4 BE) || salt(32).
      final Uint8List encryptAad = _buildBlockAad(
        blockTypes[i],
        i,
        header.salt,
      );
      final cipher = _createGCMCipher(true, key, iv, encryptAad);
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

    // Block count (now includes attestation).
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

  // Helpers.

  static GCMBlockCipher _createGCMCipher(
    bool encrypt,
    Uint8List key,
    Uint8List iv,
    Uint8List aad,
  ) {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      encrypt,
      AEADParameters(
        KeyParameter(key),
        ZegelFormat.tagSize * 8,
        iv,
        aad,
      ),
    );
    return cipher;
  }

  /// Builds the AEAD associated data:
  /// `blockType(1) || blockIndex(4 BE) || salt(32)`.
  /// Must match [ZegelWriter] exactly so re-sealed files remain verifiable.
  static Uint8List _buildBlockAad(int blockType, int blockIndex, Uint8List salt) {
    final Uint8List aad = Uint8List(1 + 4 + ZegelFormat.saltSize);
    aad[0] = blockType;
    final ByteData bd = ByteData.sublistView(aad);
    bd.setUint32(1, blockIndex, Endian.big);
    aad.setRange(5, 5 + ZegelFormat.saltSize, salt);
    return aad;
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
