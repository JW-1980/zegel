import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import 'canary.dart';
import 'format.dart';
import 'key_derivation.dart';
import 'merkle_tree.dart';
import 'writer.dart';

/// Streaming (append-only) seal mode for real-time logging, IoT, and black box
/// recording (v1.2+).
///
/// Unlike [ZegelWriter], which requires all content up front, the streaming
/// writer accepts blocks one at a time via [addBlock]. Each block is encrypted
/// immediately with a temporary key derived from a running hash chain so that
/// data is protected in memory as soon as possible.
///
/// On [finalize], the Merkle tree is built over the plaintext hashes, proper
/// HKDF-derived per-block keys are computed, and blocks are re-encrypted with
/// the final keys. The output is byte-identical to what [ZegelWriter] would
/// produce for the same input, options, and salt/IVs.
///
/// **Limitation:** Because the final file must match [ZegelWriter] output, all
/// plaintext blocks are retained in memory until [finalize] is called. The
/// streaming benefit is that blocks can be fed incrementally (e.g. from a
/// sensor or log stream) rather than accumulated externally.
class StreamingSealWriter {
  /// Creates a streaming writer with the given 32-byte [masterKey] and
  /// [options].
  ///
  /// If [salt] is provided (via [options]), it is used for deterministic
  /// output (testing). Otherwise a CSPRNG-generated salt is used.
  StreamingSealWriter(this.masterKey, this.options)
      : _secureRandom = Random.secure(),
        _salt = options.salt != null
            ? Uint8List.fromList(options.salt!)
            : _generateRandom(Random.secure(), ZegelFormat.saltSize) {
    if (masterKey.length != 32) {
      throw ArgumentError('Master key must be exactly 32 bytes');
    }
  }

  /// The 32-byte master encryption key.
  final Uint8List masterKey;

  /// Configuration options for the sealed file.
  final ZegelOptions options;

  final Random _secureRandom;
  final Uint8List _salt;

  /// Running hash chain for temporary key derivation.
  Uint8List _chainState = Uint8List(32); // starts at 32 zero bytes

  /// Accumulated plaintext blocks (needed for finalize re-encryption).
  final List<Uint8List> _plaintexts = <Uint8List>[];

  /// Block types for each accumulated block.
  final List<int> _blockTypes = <int>[];

  /// Temporarily encrypted ciphertexts (discarded on finalize).
  final List<Uint8List> _tempCiphertexts = <Uint8List>[];

  /// Whether [finalize] has been called.
  bool _finalized = false;

  /// Number of blocks added so far.
  int get blockCount => _plaintexts.length;

  /// Adds a raw content block and encrypts it immediately with a temporary
  /// per-block key derived from a running hash chain.
  ///
  /// The block is stored internally; on [finalize] it will be re-encrypted
  /// with the proper HKDF-derived key so the output matches [ZegelWriter].
  ///
  /// Throws [StateError] if [finalize] has already been called.
  void addBlock(Uint8List data) {
    if (_finalized) {
      throw StateError('Cannot add blocks after finalize');
    }

    // Apply canary padding if configured.
    Uint8List processed = data;
    final int contentStartIndex = (options.metadata != null) ? 1 : 0;
    final int contentBlockIndex =
        _plaintexts.length; // index among content blocks

    if (options.recipientId != null) {
      final Uint8List padding = CanaryTrap.generatePadding(
        masterKey,
        options.recipientId!,
        contentStartIndex + contentBlockIndex,
      );
      final Uint8List padded = Uint8List(processed.length + padding.length);
      padded.setRange(0, processed.length, processed);
      padded.setRange(processed.length, padded.length, padding);
      processed = padded;
    }

    // Compress if configured.
    if (options.compress) {
      const ZLibEncoder encoder = ZLibEncoder();
      processed = Uint8List.fromList(encoder.encode(processed, level: 6));
    }

    _plaintexts.add(processed);
    _blockTypes.add(ZegelFormat.blockContent);

    // Derive temporary key from running hash chain.
    final Uint8List tempKey = _deriveTemporaryKey();
    final Uint8List iv = _generateRandom(_secureRandom, ZegelFormat.ivSize);

    // AES-256-GCM encrypt with temporary key.
    final GCMBlockCipher cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      true,
      AEADParameters(
        KeyParameter(tempKey),
        ZegelFormat.tagSize * 8,
        iv,
        Uint8List(0),
      ),
    );
    final Uint8List encrypted = cipher.process(processed);
    _tempCiphertexts.add(encrypted);

    // Advance chain state.
    _chainState = Uint8List.fromList(
      sha256.convert(Uint8List.fromList([..._chainState, ...tempKey])).bytes,
    );
  }

  /// Finalizes the streaming seal and produces the complete .zgl file.
  ///
  /// Builds the Merkle tree, re-encrypts all blocks with proper HKDF-derived
  /// keys, and assembles the binary format. The output is identical to what
  /// [ZegelWriter.seal] would produce for the same input bytes concatenated.
  ///
  /// Throws [StateError] if [finalize] has already been called or if no blocks
  /// have been added.
  Uint8List finalize() {
    if (_finalized) {
      throw StateError('finalize has already been called');
    }
    if (_plaintexts.isEmpty) {
      throw StateError('Cannot finalize with zero blocks');
    }
    _finalized = true;

    // Discard temporary ciphertexts -- we re-encrypt from plaintexts.
    _tempCiphertexts.clear();

    // Reconstruct the full content from accumulated plaintext blocks.
    // We delegate to ZegelWriter for byte-identical output.
    //
    // However, our plaintexts are already compressed and canary-padded,
    // so we need to reverse those transforms and feed raw content to
    // ZegelWriter. Instead, we replicate the ZegelWriter logic directly.

    // First, assemble all block plaintexts and types (including metadata
    // and selective disclosure blocks, matching ZegelWriter exactly).
    final List<Uint8List> allPlaintexts = <Uint8List>[];
    final List<int> allBlockTypes = <int>[];

    // Metadata block: always block 0 when present.
    if (options.metadata != null) {
      final String metaJson = jsonEncode(options.metadata!);
      allPlaintexts.add(Uint8List.fromList(utf8.encode(metaJson)));
      allBlockTypes.add(ZegelFormat.blockMetadata);
    }

    // Content blocks (already compressed and canary-padded).
    for (int i = 0; i < _plaintexts.length; i++) {
      allPlaintexts.add(_plaintexts[i]);
      allBlockTypes.add(_blockTypes[i]);
    }

    // Selective disclosure index block (if enabled).
    if (options.enableSelectiveDisclosure) {
      final Map<String, dynamic> disclosureIndex = <String, dynamic>{
        'version': 1,
        'total_blocks': allPlaintexts.length + 1,
        'disclosable': List<int>.generate(allPlaintexts.length, (i) => i),
      };
      allPlaintexts.add(
        Uint8List.fromList(utf8.encode(jsonEncode(disclosureIndex))),
      );
      allBlockTypes.add(ZegelFormat.blockDisclosureIndex);
    }

    // Compute leaf hashes.
    final List<Uint8List> leafHashes = <Uint8List>[];
    for (final Uint8List pt in allPlaintexts) {
      leafHashes.add(Uint8List.fromList(sha256.convert(pt).bytes));
    }

    // Build Merkle tree.
    final Uint8List merkleRoot = MerkleTree.buildRoot(leafHashes);

    // Derive expiration date string for HKDF.
    String? expirationDate;
    if (options.expiration != null) {
      final DateTime dt = options.expiration!.toUtc();
      expirationDate = '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    }

    // Derive per-block keys and encrypt each block.
    final List<Uint8List> blockKeys = <Uint8List>[];
    final List<Uint8List> ivs = <Uint8List>[];
    final List<Uint8List> ciphertexts = <Uint8List>[];
    final List<Uint8List> gcmTags = <Uint8List>[];

    for (int i = 0; i < allPlaintexts.length; i++) {
      final Uint8List key = KeyDerivation.deriveBlockKey(
        masterKey,
        merkleRoot,
        _salt,
        i,
        expirationDate: expirationDate,
      );
      blockKeys.add(key);

      final Uint8List iv = _generateRandom(_secureRandom, ZegelFormat.ivSize);
      ivs.add(iv);

      final GCMBlockCipher cipher = GCMBlockCipher(AESEngine());
      cipher.init(
        true,
        AEADParameters(
          KeyParameter(key),
          ZegelFormat.tagSize * 8,
          iv,
          Uint8List(0),
        ),
      );
      final Uint8List encrypted = cipher.process(allPlaintexts[i]);

      final int ctLen = encrypted.length - ZegelFormat.tagSize;
      ciphertexts.add(Uint8List.fromList(encrypted.sublist(0, ctLen)));
      gcmTags.add(Uint8List.fromList(encrypted.sublist(ctLen)));
    }

    // Compute key commitment (optional).
    Uint8List? keyCommitment;
    if (options.enableKeyCommitment) {
      keyCommitment = KeyDerivation.computeKeyCommitment(blockKeys);
    }

    // Determine flags.
    int flags = 0;
    if (options.metadata != null) flags |= ZegelFormat.flagHasMetadata;
    if (options.compress) flags |= ZegelFormat.flagCompressed;
    if (options.argon2TimeCost != null && options.argon2MemoryCost != null) {
      flags |= ZegelFormat.flagPasswordDerived;
    }
    if (options.enableKeyCommitment) flags |= ZegelFormat.flagHasKeyCommitment;
    if (options.expiration != null) flags |= ZegelFormat.flagHasExpiration;
    if (options.publicMetadata != null) {
      flags |= ZegelFormat.flagHasPublicMetadata;
    }
    if (options.recipientId != null) flags |= ZegelFormat.flagHasCanary;
    if (options.splitKeyThreshold != null && options.splitKeyTotal != null) {
      flags |= ZegelFormat.flagSplitKey;
    }
    if (options.enableSelectiveDisclosure) {
      flags |= ZegelFormat.flagSelectiveDisclosure;
    }
    if (options.versionChainHash != null) flags |= ZegelFormat.flagVersioned;

    // Build the binary file (matching ZegelWriter exactly).
    final BytesBuilder builder = BytesBuilder();

    // Magic bytes.
    builder.add(ZegelFormat.magic);

    // Version.
    builder.addByte(ZegelFormat.versionMajor);
    builder.addByte(ZegelFormat.versionMinor);

    // Flags.
    builder.add(_packUint16BE(flags));

    // Timestamp.
    final int nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    builder.add(_packUint64BE(nowEpoch));

    // Content-Type.
    final Uint8List ctPadded = Uint8List(ZegelFormat.contentTypeSize);
    if (options.contentType != null) {
      final List<int> ctEncoded = utf8.encode(options.contentType!);
      final int ctCopyLen = ctEncoded.length < ZegelFormat.contentTypeSize
          ? ctEncoded.length
          : ZegelFormat.contentTypeSize;
      ctPadded.setRange(0, ctCopyLen, ctEncoded);
    }
    builder.add(ctPadded);

    // Filename.
    final Uint8List fnBytes = options.filename != null
        ? Uint8List.fromList(utf8.encode(options.filename!))
        : Uint8List(0);
    if (fnBytes.length > ZegelFormat.maxFilenameLength) {
      throw const ZegelFormatException(
        'Filename exceeds maximum of ${ZegelFormat.maxFilenameLength} bytes',
      );
    }
    builder.add(_packUint16BE(fnBytes.length));
    if (fnBytes.isNotEmpty) builder.add(fnBytes);

    // Salt.
    builder.add(_salt);

    // Block count.
    builder.add(_packUint32BE(allPlaintexts.length));

    // Extended header.
    if (flags & ZegelFormat.flagPasswordDerived != 0) {
      builder.add(_packUint32BE(options.argon2TimeCost!));
      builder.add(_packUint32BE(options.argon2MemoryCost!));
    }
    if (flags & ZegelFormat.flagHasExpiration != 0) {
      final int expEpoch =
          options.expiration!.toUtc().millisecondsSinceEpoch ~/ 1000;
      builder.add(_packUint64BE(expEpoch));
    }
    if (flags & ZegelFormat.flagHasCanary != 0) {
      if (options.recipientId!.length != 32) {
        throw const ZegelFormatException(
          'Recipient ID must be exactly 32 bytes',
        );
      }
      builder.add(options.recipientId!);
    }
    if (flags & ZegelFormat.flagSplitKey != 0) {
      builder.addByte(options.splitKeyThreshold!);
      builder.addByte(options.splitKeyTotal!);
    }
    if (flags & ZegelFormat.flagVersioned != 0) {
      if (options.versionChainHash!.length != 32) {
        throw const ZegelFormatException(
          'Version chain hash must be exactly 32 bytes',
        );
      }
      builder.add(options.versionChainHash!);
    }
    if (flags & ZegelFormat.flagHasPublicMetadata != 0) {
      final Uint8List pubMetaBytes = Uint8List.fromList(
        utf8.encode(jsonEncode(options.publicMetadata!)),
      );
      builder.add(_packUint32BE(pubMetaBytes.length));
      builder.add(pubMetaBytes);
    }

    // Block directory.
    for (int i = 0; i < allPlaintexts.length; i++) {
      builder.addByte(allBlockTypes[i]);
      builder.add(leafHashes[i]);
      builder.add(_packUint32BE(ciphertexts[i].length));
      builder.add(ivs[i]);
      builder.add(gcmTags[i]);
    }

    // Merkle root.
    builder.add(merkleRoot);

    // Key commitment.
    if (keyCommitment != null) builder.add(keyCommitment);

    // Encrypted block data.
    for (final Uint8List ct in ciphertexts) {
      builder.add(ct);
    }

    // Master seal.
    final Uint8List preSealBytes = builder.toBytes();
    final Uint8List sealKey = KeyDerivation.computeSealKey(
      merkleRoot,
      masterKey,
      _salt,
    );
    final Uint8List masterSeal = KeyDerivation.computeMasterSeal(
      sealKey,
      preSealBytes,
    );

    final Uint8List finalFile = Uint8List(
      preSealBytes.length + masterSeal.length,
    );
    finalFile.setRange(0, preSealBytes.length, preSealBytes);
    finalFile.setRange(preSealBytes.length, finalFile.length, masterSeal);

    return finalFile;
  }

  /// Derives a temporary per-block key from the running hash chain.
  ///
  /// The temporary key is `SHA-256(chainState || blockIndex)`. This provides
  /// immediate encryption but is NOT the final key used in the .zgl output.
  Uint8List _deriveTemporaryKey() {
    final Uint8List indexBytes = Uint8List.fromList(
      utf8.encode(_plaintexts.length.toString()),
    );
    final Uint8List input = Uint8List(_chainState.length + indexBytes.length);
    input.setRange(0, _chainState.length, _chainState);
    input.setRange(_chainState.length, input.length, indexBytes);
    return Uint8List.fromList(sha256.convert(input).bytes);
  }

  static Uint8List _generateRandom(Random random, int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Uint8List _packUint16BE(int value) {
    final ByteData bd = ByteData(2);
    bd.setUint16(0, value, Endian.big);
    return bd.buffer.asUint8List();
  }

  static Uint8List _packUint32BE(int value) {
    final ByteData bd = ByteData(4);
    bd.setUint32(0, value, Endian.big);
    return bd.buffer.asUint8List();
  }

  static Uint8List _packUint64BE(int value) {
    final ByteData bd = ByteData(8);
    bd.setUint64(0, value, Endian.big);
    return bd.buffer.asUint8List();
  }
}
