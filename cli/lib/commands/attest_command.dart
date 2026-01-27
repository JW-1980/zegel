import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Adds a co-signature attestation to a .zgl file.
///
/// Usage:
///   zegel attest <file.zgl> --signer-key <hex> --signer-id <string>
///       --statement "text" -k <master-key-hex>
///
/// The attestation is an HMAC-SHA256 over the Merkle root, signer ID,
/// timestamp, and statement. Adding an attestation block changes the Merkle
/// tree, so the entire file is re-encrypted and re-sealed.
class AttestCommand extends Command<int> {
  @override
  final String name = 'attest';

  @override
  final String description =
      'Add a co-signature attestation to a .zgl file.';

  @override
  final String invocation = 'zegel attest <file.zgl> [options]';

  AttestCommand() {
    argParser.addOption(
      'signer-key',
      help: 'Signer\'s 32-byte key as hex.',
      valueHelp: 'hex',
    );

    argParser.addOption(
      'signer-key-file',
      help: 'Path to a file containing the signer key.',
      valueHelp: 'path',
    );

    argParser.addOption(
      'signer-id',
      help: 'Signer identifier (e.g., "user:42:name@example.com").',
      valueHelp: 'id',
      mandatory: true,
    );

    argParser.addOption(
      'statement',
      abbr: 's',
      help: 'Attestation statement text.',
      valueHelp: 'text',
      mandatory: true,
    );

    addKeyOptions(argParser);
    addOutputOption(
      argParser,
      help: 'Output path for the attested .zgl file. '
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

    if (signerId.isEmpty) {
      exitError('Signer ID cannot be empty.');
    }

    if (statement.isEmpty) {
      exitError('Statement cannot be empty.');
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

    // Verify the file first.
    final reader = ZegelReader(fileBytes);
    final header = reader.inspectHeader();
    final verifyResult = reader.verify(masterKey);

    if (verifyResult.status != ZegelVerifyStatus.valid) {
      exitError(
        'File verification failed. Cannot attest to a tampered file.',
      );
    }

    if (header.merkleRoot == null) {
      exitError('Could not extract Merkle root from file.');
    }

    // Create the attestation using the CURRENT Merkle root.
    // Note: after adding the attestation block, the Merkle root will change.
    // The attestation HMAC is bound to the original Merkle root, which proves
    // the signer attested to the file as it was before the block was added.
    final timestamp = DateTime.now().toUtc();
    final attestation = Attestation.createAttestation(
      header.merkleRoot!,
      signerId,
      signerKey,
      statement,
      timestamp: timestamp,
    );

    // The attestation block plaintext is the JSON encoding.
    final attestationJson = jsonEncode(attestation);

    // Re-seal the file with the attestation block added.
    // Since a new block changes the Merkle root, all block keys change,
    // requiring re-encryption of every block.
    final attestedBytes = _resealWithAttestation(
      fileBytes,
      masterKey,
      header,
      verifyResult,
      Uint8List.fromList(utf8.encode(attestationJson)),
    );

    // Write output file.
    final outputPath = argResults!['output'] as String? ?? filePath;
    final outputFile = File(outputPath);
    outputFile.writeAsBytesSync(attestedBytes);

    // Print success message.
    stdout.writeln(Ansi.success('Attestation added successfully.'));
    stdout.writeln();
    stdout.writeln('  File:      ${outputPath == filePath ? '$filePath (updated)' : outputPath}');
    stdout.writeln('  Signer:    $signerId');
    stdout.writeln('  Statement: $statement');
    stdout.writeln('  Time:      ${formatTimestamp(timestamp)}');
    stdout.writeln('  HMAC:      ${attestation['hmac_hex']}');

    if (verifyResult.attestations != null) {
      stdout.writeln(
        '  Total:     ${verifyResult.attestations!.length + 1} attestation(s)',
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
    ZegelHeader header,
    ZegelReadResult verifyResult,
    Uint8List attestationPlaintext,
  ) {
    final random = Random.secure();

    // Reconstruct all block plaintexts from the verified extraction.
    // We re-read the file to get the raw encrypted blocks, then decrypt them
    // to recover the exact plaintexts (including compression and canary padding).
    // This preserves the exact block structure.

    // Parse block data offsets from the original file.
    final bd = ByteData.sublistView(originalFileBytes);
    final int filenameLen = bd.getUint16(84, Endian.big);
    final int saltOffset = 86 + filenameLen;
    final Uint8List salt = Uint8List.fromList(
      originalFileBytes.sublist(saltOffset, saltOffset + ZegelFormat.saltSize),
    );
    final int blockCountOffset = saltOffset + ZegelFormat.saltSize;

    // Use the original salt for consistency.

    // We need the original per-block plaintexts (as stored, including
    // compression/canary). The leaf hashes in the directory ARE the SHA-256
    // of these plaintexts, so we can decrypt and verify.

    // Find data start.
    int cursor = blockCountOffset + 4;
    if (header.flags & ZegelFormat.flagPasswordDerived != 0) cursor += 8;
    if (header.flags & ZegelFormat.flagHasExpiration != 0) cursor += 8;
    if (header.flags & ZegelFormat.flagHasCanary != 0) cursor += 32;
    if (header.flags & ZegelFormat.flagSplitKey != 0) cursor += 2;
    if (header.flags & ZegelFormat.flagVersioned != 0) cursor += 32;
    if (header.flags & ZegelFormat.flagHasPublicMetadata != 0) {
      final int pubMetaLen = bd.getUint32(cursor, Endian.big);
      cursor += 4 + pubMetaLen;
    }
    cursor += header.blockCount * ZegelFormat.blockDirectoryEntrySize;
    cursor += ZegelFormat.hashSize; // Merkle root
    if (header.flags & ZegelFormat.flagHasKeyCommitment != 0) {
      cursor += ZegelFormat.hashSize;
    }
    final int dataStart = cursor;

    // Build expiration date string for key derivation.
    String? expirationDateStr;
    if (header.expiresAt != null) {
      final dt = header.expiresAt!.toUtc();
      expirationDateStr =
          '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    }

    // Decrypt all existing blocks to recover their plaintexts.
    final List<Uint8List> plaintexts = [];
    final List<int> blockTypes = [];
    int dataOffset = dataStart;

    for (int i = 0; i < header.blockCount; i++) {
      final entry = header.blockDirectory[i];
      final Uint8List ciphertext = Uint8List.sublistView(
        originalFileBytes,
        dataOffset,
        dataOffset + entry.ciphertextLength,
      );
      dataOffset += entry.ciphertextLength;

      if (entry.type == ZegelFormat.blockRedacted) {
        // Preserve redacted blocks as-is (use their original hash).
        plaintexts.add(ciphertext); // Random bytes, won't be re-encrypted.
        blockTypes.add(ZegelFormat.blockRedacted);
        continue;
      }

      // Derive original block key.
      final Uint8List blockKey = KeyDerivation.deriveBlockKey(
        masterKey,
        header.merkleRoot!,
        salt,
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
          Uint8List.fromList(
            _sha256(plaintexts[i]),
          ),
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
        salt,
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

    // Header (copy from original up to block count).
    output.add(ZegelFormat.magic);
    output.addByte(header.versionMajor);
    output.addByte(header.versionMinor);
    output.add(_uint16BE(header.flags));
    output.add(_uint64BE(
      header.createdAt.millisecondsSinceEpoch ~/ 1000,
    ));

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
    output.add(salt);

    // Block count (now includes attestation).
    output.add(_uint32BE(plaintexts.length));

    // Extended header (copy from original).
    if (header.flags & ZegelFormat.flagPasswordDerived != 0) {
      output.add(_uint32BE(header.argon2TimeCost!));
      output.add(_uint32BE(header.argon2MemoryCost!));
    }
    if (header.flags & ZegelFormat.flagHasExpiration != 0) {
      output.add(_uint64BE(
        header.expiresAt!.millisecondsSinceEpoch ~/ 1000,
      ));
    }
    if (header.flags & ZegelFormat.flagHasCanary != 0) {
      output.add(header.recipientId!);
    }
    if (header.flags & ZegelFormat.flagSplitKey != 0) {
      output.addByte(header.splitKeyThreshold!);
      output.addByte(header.splitKeyShares!);
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
      salt,
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

  static List<int> _sha256(Uint8List data) {
    // Use the same SHA-256 as the library.
    // Import crypto through the zegel library re-export.
    final digest = sha256Hash(data);
    return digest;
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
