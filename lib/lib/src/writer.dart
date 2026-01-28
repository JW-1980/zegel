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
import 'shamir.dart';

// =============================================================================
// ZegelOptions
// =============================================================================

/// Configuration options for creating a sealed .zgl file.
///
/// All fields are optional. At a minimum, providing [contentType] is
/// recommended so that readers know how to interpret the content.
class ZegelOptions {
  /// Creates a new [ZegelOptions] instance.
  const ZegelOptions({
    this.contentType,
    this.filename,
    this.metadata,
    this.compress = false,
    this.argon2TimeCost,
    this.argon2MemoryCost,
    this.expiration,
    this.recipientId,
    this.splitKeyThreshold,
    this.splitKeyTotal,
    this.publicMetadata,
    this.versionChainHash,
    this.enableKeyCommitment = false,
    this.enableSelectiveDisclosure = false,
    this.blockSize = ZegelFormat.defaultBlockSize,
    this.salt,
  });

  /// MIME type of the original content (e.g. `"text/plain"`).
  /// Written to the 64-byte Content-Type header field, null-padded.
  final String? contentType;

  /// Original filename (max 255 bytes UTF-8).
  final String? filename;

  /// Private metadata encoded as encrypted JSON in block 0.
  /// When non-null, the `HAS_METADATA` flag is set and a metadata block is
  /// prepended before content blocks.
  final Map<String, dynamic>? metadata;

  /// Whether to zlib-compress content blocks before encryption.
  /// Uses zlib level 6.
  final bool compress;

  /// Argon2id time cost (iterations). When non-null together with
  /// [argon2MemoryCost], the `PASSWORD_DERIVED` flag is set.
  final int? argon2TimeCost;

  /// Argon2id memory cost in KiB.
  final int? argon2MemoryCost;

  /// Cryptographic expiration timestamp. After this time, readers refuse key
  /// derivation and extraction is impossible. The expiration date in
  /// `YYYY-MM-DD` format is baked into the HKDF info string.
  final DateTime? expiration;

  /// 32-byte recipient identifier for canary trap fingerprinting (SEC-4).
  /// When non-null, invisible deterministic padding is appended to each
  /// content block before compression/encryption.
  final Uint8List? recipientId;

  /// Shamir threshold (M): minimum shares needed to reconstruct the key.
  /// When non-null, the `SPLIT_KEY` flag is set and M/N are stored in the
  /// extended header.
  final int? splitKeyThreshold;

  /// Shamir total shares (N).
  final int? splitKeyTotal;

  /// Unencrypted metadata written to the extended header. Integrity-protected
  /// by the Merkle tree but readable without the master key.
  final Map<String, dynamic>? publicMetadata;

  /// 32-byte version chain hash linking to a previous version (GEN-10).
  /// Computed as `SHA-256(previousMerkleRoot || previousMasterSeal)`.
  final Uint8List? versionChainHash;

  /// Whether to include a key commitment hash (SEC-2) after the Merkle root.
  /// Prevents invisible salamander attacks on AES-GCM.
  final bool enableKeyCommitment;

  /// Whether to include a selective disclosure index block (GEN-9).
  final bool enableSelectiveDisclosure;

  /// Content block size in bytes. Defaults to 65536 (64 KiB).
  final int blockSize;

  /// Explicit master salt for deterministic output (testing only).
  /// In production, leave null and a CSPRNG salt is generated.
  final Uint8List? salt;
}

// =============================================================================
// ZegelWriter
// =============================================================================

/// Creates sealed .zgl files.
///
/// The writer takes a 32-byte master key and a [ZegelOptions] configuration,
/// then produces a self-contained binary container where any modification
/// after creation makes the content irrecoverable.
///
/// ```dart
/// final writer = ZegelWriter(masterKey, ZegelOptions(
///   contentType: 'application/pdf',
///   filename: 'report.pdf',
///   metadata: {'sealed_by': 'admin'},
/// ));
/// final sealed = writer.seal(pdfBytes);
/// ```
class ZegelWriter {
  /// Creates a writer with the given 32-byte [masterKey] and [options].
  ZegelWriter(this.masterKey, this.options) {
    if (masterKey.length != 32) {
      throw ArgumentError('Master key must be exactly 32 bytes');
    }
  }

  /// The 32-byte master encryption key.
  final Uint8List masterKey;

  /// Configuration options for the sealed file.
  final ZegelOptions options;

  /// Seals [content] into a .zgl binary container.
  ///
  /// Returns the complete .zgl file as a [Uint8List] ready to write to disk.
  /// The content is split into blocks, each independently encrypted with a key
  /// derived from the Merkle tree root, making it impossible to extract content
  /// from a tampered file.
  Uint8List seal(Uint8List content) {
    final Random secureRandom = Random.secure();

    // =========================================================================
    // 1. Determine flags
    // =========================================================================
    int flags = 0;
    if (options.metadata != null) {
      flags |= ZegelFormat.flagHasMetadata;
    }
    if (options.compress) {
      flags |= ZegelFormat.flagCompressed;
    }
    if (options.argon2TimeCost != null && options.argon2MemoryCost != null) {
      flags |= ZegelFormat.flagPasswordDerived;
    }
    if (options.enableKeyCommitment) {
      flags |= ZegelFormat.flagHasKeyCommitment;
    }
    if (options.expiration != null) {
      flags |= ZegelFormat.flagHasExpiration;
    }
    if (options.publicMetadata != null) {
      flags |= ZegelFormat.flagHasPublicMetadata;
    }
    if (options.recipientId != null) {
      flags |= ZegelFormat.flagHasCanary;
    }
    if (options.splitKeyThreshold != null && options.splitKeyTotal != null) {
      flags |= ZegelFormat.flagSplitKey;
    }
    if (options.enableSelectiveDisclosure) {
      flags |= ZegelFormat.flagSelectiveDisclosure;
    }
    if (options.versionChainHash != null) {
      flags |= ZegelFormat.flagVersioned;
    }

    // =========================================================================
    // 2. Generate or use provided salt
    // =========================================================================
    final Uint8List salt =
        options.salt != null
            ? Uint8List.fromList(options.salt!)
            : _randomBytes(secureRandom, ZegelFormat.saltSize);

    // =========================================================================
    // 3. Split content into chunks
    // =========================================================================
    final List<Uint8List> contentChunks = _splitContent(content);

    // Count leading non-content blocks so canary knows actual block index.
    final int contentStartIndex = (options.metadata != null) ? 1 : 0;

    // =========================================================================
    // 4. Apply canary padding to each content chunk (before compression)
    // =========================================================================
    if (options.recipientId != null) {
      for (int i = 0; i < contentChunks.length; i++) {
        final int blockIndex = contentStartIndex + i;
        final Uint8List padding = CanaryTrap.generatePadding(
          masterKey,
          options.recipientId!,
          blockIndex,
        );
        final Uint8List padded = Uint8List(
          contentChunks[i].length + padding.length,
        );
        padded.setRange(0, contentChunks[i].length, contentChunks[i]);
        padded.setRange(contentChunks[i].length, padded.length, padding);
        contentChunks[i] = padded;
      }
    }

    // =========================================================================
    // 5. Compress content chunks (after canary padding, before hashing)
    // =========================================================================
    if (options.compress) {
      final ZLibEncoder encoder = ZLibEncoder();
      for (int i = 0; i < contentChunks.length; i++) {
        contentChunks[i] = Uint8List.fromList(
          encoder.encode(contentChunks[i], level: 6),
        );
      }
    }

    // =========================================================================
    // 6. Assemble all block plaintexts and types
    // =========================================================================
    final List<Uint8List> plaintexts = <Uint8List>[];
    final List<int> blockTypes = <int>[];

    // Metadata block: always block 0 when present.
    if (options.metadata != null) {
      final String metaJson = jsonEncode(options.metadata!);
      plaintexts.add(Uint8List.fromList(utf8.encode(metaJson)));
      blockTypes.add(ZegelFormat.blockMetadata);
    }

    // Content blocks.
    for (final Uint8List chunk in contentChunks) {
      plaintexts.add(chunk);
      blockTypes.add(ZegelFormat.blockContent);
    }

    // Selective disclosure index block (if enabled).
    if (options.enableSelectiveDisclosure) {
      final Map<String, dynamic> disclosureIndex = <String, dynamic>{
        'version': 1,
        'total_blocks': plaintexts.length + 1,
        'disclosable': List<int>.generate(plaintexts.length, (i) => i),
      };
      plaintexts.add(
        Uint8List.fromList(utf8.encode(jsonEncode(disclosureIndex))),
      );
      blockTypes.add(ZegelFormat.blockDisclosureIndex);
    }

    // =========================================================================
    // 7. Compute leaf hashes
    // =========================================================================
    final List<Uint8List> leafHashes = <Uint8List>[];
    for (final Uint8List pt in plaintexts) {
      leafHashes.add(Uint8List.fromList(sha256.convert(pt).bytes));
    }

    // =========================================================================
    // 8. Build Merkle tree
    // =========================================================================
    final Uint8List merkleRoot = MerkleTree.buildRoot(leafHashes);

    // =========================================================================
    // 9. Derive expiration date string for HKDF
    // =========================================================================
    String? expirationDate;
    if (options.expiration != null) {
      final DateTime dt = options.expiration!.toUtc();
      expirationDate =
          '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    }

    // =========================================================================
    // 10. Derive per-block keys and encrypt each block
    // =========================================================================
    final List<Uint8List> blockKeys = <Uint8List>[];
    final List<Uint8List> ivs = <Uint8List>[];
    final List<Uint8List> ciphertexts = <Uint8List>[];
    final List<Uint8List> gcmTags = <Uint8List>[];

    for (int i = 0; i < plaintexts.length; i++) {
      final Uint8List key = KeyDerivation.deriveBlockKey(
        masterKey,
        merkleRoot,
        salt,
        i,
        expirationDate: expirationDate,
      );
      blockKeys.add(key);

      final Uint8List iv = _randomBytes(secureRandom, ZegelFormat.ivSize);
      ivs.add(iv);

      // AES-256-GCM encrypt.
      final GCMBlockCipher cipher = GCMBlockCipher(AESEngine());
      cipher.init(
        true,
        AEADParameters(
          KeyParameter(key),
          ZegelFormat.tagSize * 8, // 128 bits
          iv,
          Uint8List(0), // empty AAD
        ),
      );
      final Uint8List encrypted = cipher.process(plaintexts[i]);

      // encrypted = ciphertext || tag (last 16 bytes).
      final int ctLen = encrypted.length - ZegelFormat.tagSize;
      ciphertexts.add(Uint8List.fromList(encrypted.sublist(0, ctLen)));
      gcmTags.add(Uint8List.fromList(encrypted.sublist(ctLen)));
    }

    // =========================================================================
    // 11. Compute key commitment (optional)
    // =========================================================================
    Uint8List? keyCommitment;
    if (options.enableKeyCommitment) {
      keyCommitment = KeyDerivation.computeKeyCommitment(blockKeys);
    }

    // =========================================================================
    // 12. Build the binary file
    // =========================================================================
    final BytesBuilder builder = BytesBuilder();

    // --- Header ---

    // Magic bytes (8).
    builder.add(ZegelFormat.magic);

    // Version major (1) + minor (1).
    builder.addByte(ZegelFormat.versionMajor);
    builder.addByte(ZegelFormat.versionMinor);

    // Flags (uint16 BE).
    builder.add(_packUint16BE(flags));

    // Created timestamp (uint64 BE, Unix epoch seconds).
    final int nowEpoch =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    builder.add(_packUint64BE(nowEpoch));

    // Content-Type (64 bytes, UTF-8, null-padded).
    final Uint8List ctPadded = Uint8List(ZegelFormat.contentTypeSize);
    if (options.contentType != null) {
      final List<int> ctEncoded = utf8.encode(options.contentType!);
      final int ctCopyLen = ctEncoded.length < ZegelFormat.contentTypeSize
          ? ctEncoded.length
          : ZegelFormat.contentTypeSize;
      ctPadded.setRange(0, ctCopyLen, ctEncoded);
    }
    builder.add(ctPadded);

    // Filename length (uint16 BE) + filename (variable).
    final Uint8List fnBytes =
        options.filename != null
            ? Uint8List.fromList(utf8.encode(options.filename!))
            : Uint8List(0);
    if (fnBytes.length > ZegelFormat.maxFilenameLength) {
      throw ZegelFormatException(
        'Filename exceeds maximum of ${ZegelFormat.maxFilenameLength} bytes',
      );
    }
    builder.add(_packUint16BE(fnBytes.length));
    if (fnBytes.isNotEmpty) {
      builder.add(fnBytes);
    }

    // Master salt (32 bytes).
    builder.add(salt);

    // Block count (uint32 BE).
    builder.add(_packUint32BE(plaintexts.length));

    // --- Extended Header (flag-dependent, in spec-defined order) ---

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

    // --- Block Directory ---

    for (int i = 0; i < plaintexts.length; i++) {
      builder.addByte(blockTypes[i]); // Block type (1 byte).
      builder.add(leafHashes[i]); // Plaintext hash (32 bytes).
      builder.add(_packUint32BE(ciphertexts[i].length)); // CT length (4).
      builder.add(ivs[i]); // IV/Nonce (12 bytes).
      builder.add(gcmTags[i]); // Auth tag (16 bytes).
    }

    // --- Merkle Root (32 bytes) ---
    builder.add(merkleRoot);

    // --- Key Commitment (32 bytes, if enabled) ---
    if (keyCommitment != null) {
      builder.add(keyCommitment);
    }

    // --- Encrypted Block Data ---
    for (final Uint8List ct in ciphertexts) {
      builder.add(ct);
    }

    // =========================================================================
    // 13. Compute and append master seal
    // =========================================================================
    final Uint8List preSealBytes = builder.toBytes();

    final Uint8List sealKey = KeyDerivation.computeSealKey(
      merkleRoot,
      masterKey,
      salt,
    );
    final Uint8List masterSeal = KeyDerivation.computeMasterSeal(
      sealKey,
      preSealBytes,
    );

    // =========================================================================
    // 14. Assemble final file
    // =========================================================================
    final Uint8List finalFile = Uint8List(
      preSealBytes.length + masterSeal.length,
    );
    finalFile.setRange(0, preSealBytes.length, preSealBytes);
    finalFile.setRange(preSealBytes.length, finalFile.length, masterSeal);

    return finalFile;
  }

  /// Splits the master key using Shamir's Secret Sharing over GF(256).
  ///
  /// Returns [total] shares, any [threshold] of which can reconstruct the
  /// master key. Each share is 33 bytes: 1-byte x-coordinate + 32 y-values.
  List<Uint8List> splitKey(int threshold, int total) {
    return ShamirSecretSharing.split(masterKey, threshold, total);
  }

  // ===========================================================================
  // Private helpers
  // ===========================================================================

  /// Splits [content] into chunks of [options.blockSize] bytes.
  ///
  /// The last chunk may be smaller. Empty content produces a single empty
  /// chunk (matching PHP str_split behaviour).
  List<Uint8List> _splitContent(Uint8List content) {
    if (content.isEmpty) {
      return <Uint8List>[Uint8List(0)];
    }
    final List<Uint8List> chunks = <Uint8List>[];
    int offset = 0;
    while (offset < content.length) {
      final int end = (offset + options.blockSize) < content.length
          ? offset + options.blockSize
          : content.length;
      chunks.add(Uint8List.fromList(content.sublist(offset, end)));
      offset = end;
    }
    return chunks;
  }

  /// Generates [length] cryptographically random bytes.
  static Uint8List _randomBytes(Random random, int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  /// Packs [value] as a 2-byte big-endian unsigned integer.
  static Uint8List _packUint16BE(int value) {
    final ByteData bd = ByteData(2);
    bd.setUint16(0, value, Endian.big);
    return bd.buffer.asUint8List();
  }

  /// Packs [value] as a 4-byte big-endian unsigned integer.
  static Uint8List _packUint32BE(int value) {
    final ByteData bd = ByteData(4);
    bd.setUint32(0, value, Endian.big);
    return bd.buffer.asUint8List();
  }

  /// Packs [value] as an 8-byte big-endian unsigned integer.
  static Uint8List _packUint64BE(int value) {
    final ByteData bd = ByteData(8);
    bd.setUint64(0, value, Endian.big);
    return bd.buffer.asUint8List();
  }
}
