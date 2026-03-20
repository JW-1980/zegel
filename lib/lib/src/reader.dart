import 'dart:convert'
;


import 'dart:typed_data'
;


import 'package:archive/archive.dart'
;


import 'package:crypto/crypto.dart'
;


import 'package:pointycastle/export.dart'
;


import 'canary.dart'
;


import 'format.dart'
;


import 'key_derivation.dart'
;


import 'merkle_tree.dart'
;


// ======================================================================// Result types
// ======================================================================
/// Result of verifying and extracting a .zgl file.
class ZegelResult
{


  /// Creates a [ZegelResult].
  const ZegelResult(
{


    required this.valid,
    this.content,
    this.metadata,
    this.filename,
    this.contentType,
    this.publicMetadata,
    this.attestations,
    this.auditTrail,
    this.provenance,
    this.redactedBlocks,
    this.disclosedBlocks,

}

)
;


  /// Whether all cryptographic checks passed.
  final bool valid
;


  /// Extracted content bytes (only non-null when [valid] is `true`).
  final Uint8List? content
;


  /// Decrypted metadata from block 0 (if `HAS_METADATA` flag was set).
  final Map<String, dynamic>? metadata
;


  /// Original filename from the header.
  final String? filename
;


  /// Content-Type from the header.
  final String? contentType
;


  /// Public metadata from the extended header (readable without the key).
  final Map<String, dynamic>? publicMetadata
;


  /// Attestation entries (block type 0x07).
  final List<Map<String, dynamic>>? attestations
;


  /// Audit trail entries (block type 0x09).
  final List<Map<String, dynamic>>? auditTrail
;


  /// Provenance entries (block type 0x05).
  final List<Map<String, dynamic>>? provenance
;


  /// Zero-based indices of redacted blocks (block type 0x06).
  final List<int>? redactedBlocks
;


  /// Zero-based indices of blocks successfully disclosed (only for selective disclosure).
  final List<int>? disclosedBlocks
;


}


/// Header-only inspection result (no master key required).
class ZegelInspection
{


  /// Creates a [ZegelInspection].
  const ZegelInspection(
{


    required this.version,
    required this.flags,
    required this.timestamp,
    this.contentType,
    this.filename,
    required this.blockCount,
    this.publicMetadata,
    this.splitKeyParams,
    this.expirationTimestamp,
    this.blocks = const [],
  });

  /// Format version string (e.g. `"1.2"`).
  final String version;

  /// Raw flags bitmask (uint16).
  final int flags;

  /// File creation time as Unix epoch seconds.
  final int timestamp;

  /// Content-Type from the header.
  final String? contentType;

  /// Original filename.
  final String? filename;

  /// Total number of blocks in the file.
  final int blockCount;

  /// Public metadata from the extended header.
  final Map<String, dynamic>? publicMetadata;

  /// Shamir split-key parameters: `{'threshold': M, 'total': N}`.
  final Map<String, int>? splitKeyParams;

  /// Expiration timestamp as Unix epoch seconds.
  final int? expirationTimestamp;

  /// Information about each block in the directory.
  final List<Map<String, dynamic>> blocks;
}


  /// Format version string (e.g. `"1.2"`).
  final String version
;


  /// Raw flags bitmask (uint16).
  final int flags
;


  /// File creation time as Unix epoch seconds.
  final int timestamp
;


  /// Content-Type from the header.
  final String? contentType
;


  /// Original filename.
  final String? filename
;


  /// Total number of blocks in the file.
  final int blockCount
;


  /// Public metadata from the extended header.
  final Map<String, dynamic>? publicMetadata
;


  /// Shamir split-key parameters: `{'threshold': M, 'total': N}`.
  final Map<String, int>? splitKeyParams
;


  /// Expiration timestamp as Unix epoch seconds.
  final int? expirationTimestamp
;


  /// Information about each block in the directory.
  final List<Map<String, dynamic>> blocks
;


}


// ======================================================================// Internal helpers
// ======================================================================
/// Parsed block directory entry (internal).
class _DirEntry
{


  const _DirEntry(
{


    required this.type,
    required this.hash,
    required this.ciphertextLen,
    required this.iv,
    required this.tag,

}

)
;


  final int type
;


  final Uint8List hash
;


  final int ciphertextLen
;


  final Uint8List iv
;


  final Uint8List tag
;


}


/// Parsed header and extended header (internal).
class _ParsedHeader
{


  _ParsedHeader()
;


  int versionMajor = 0
;


  int versionMinor = 0
;


  int flags = 0
;


  int timestamp = 0
;


  String contentType = ''
;


  String filename = ''
;


  Uint8List salt = Uint8List(0)
;


  int blockCount = 0
;


  // Extended header fields.
  int? argon2TimeCost
;


  int? argon2MemoryCost
;


  int? expirationTimestamp
;


  Uint8List? recipientId
;


  int? splitKeyThreshold
;


  int? splitKeyTotal
;


  Uint8List? versionChainHash
;


  Map<String, dynamic>? publicMetadata
;


  // Byte offset where the block directory starts.
  int directoryStart = 0
;


  // Parsed block directory.
  List<_DirEntry> directory = <_DirEntry>[]
;


  // Merkle root.
  Uint8List merkleRoot = Uint8List(0)
;


  // Key commitment (if present).
  Uint8List? keyCommitment
;


  // Byte offset where encrypted block data starts.
  int dataStart = 0
;


}


// ======================================================================// ZegelReader
// ======================================================================
/// Reads, verifies, and extracts .zgl files.
///
/// The reader supports three modes of access:
/// - [verify]: Full cryptographic verification and content extraction (requires
///   the master key).
/// - [inspect]: Header-only inspection without the master key.
/// - [extractWithToken]: Selective disclosure using a token (requires only the
///   per-block keys included in the token, not the master key).
class ZegelReader
{


  /// Creates a [ZegelReader].
  const ZegelReader()
;


  /// Fully verifies and extracts a .zgl file.
  ///
  /// Performs all cryptographic checks described in the format specification
  /// (Section 11). Returns a [ZegelResult] with `valid = true` and the
  /// extracted content if all checks pass.
  ///
  /// Throws [ZegelFormatException] if the binary format is structurally
  /// invalid.
  /// Throws [ZegelTamperedException] if any integrity check fails.
  /// Throws [ZegelExpiredException] if the file's cryptographic expiration
  /// has passed.
  ZegelResult verify(Uint8List fileBytes, Uint8List masterKey) {
    // ==================================================================    // 1-4. Parse header, extended header, block directory
    // ==================================================================    final _ParsedHeader h = _parseAll(fileBytes);

    // ==================================================================    // 5. Check expiration
    // ==================================================================    if (h.expirationTimestamp != null) {
      final int nowEpoch =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      if (nowEpoch >= h.expirationTimestamp!) {
        throw ZegelExpiredException(
          'File expired at epoch $
{

h.expirationTimestamp
}

',
        );
      }
    }

    // ==================================================================    // 6. Verify master seal (HMAC-SHA512)
    // ==================================================================    final Uint8List preSealBytes = Uint8List.sublistView(
      fileBytes,
      0,
      fileBytes.length - ZegelFormat.sealSize,
    );
    final Uint8List storedSeal = Uint8List.sublistView(
      fileBytes,
      fileBytes.length - ZegelFormat.sealSize,
    );

    final Uint8List sealKey = KeyDerivation.computeSealKey(
      h.merkleRoot,
      masterKey,
      h.salt,
    );
    final Uint8List computedSeal = KeyDerivation.computeMasterSeal(
      sealKey,
      preSealBytes,
    );

    if (!_constantTimeEquals(computedSeal, storedSeal)) {
      throw const ZegelTamperedException('Master seal verification failed');
    }

    // =========================================================================
    // 7. Verify Merkle tree
    // =========================================================================
    final List<Uint8List> leafHashes = h.directory
        .map((_DirEntry e) => e.hash)
        .toList();
    final Uint8List computedRoot = MerkleTree.buildRoot(leafHashes);

    if (!_constantTimeEquals(computedRoot, h.merkleRoot)) {
      throw const ZegelTamperedException('Merkle root mismatch');
    }

    // ==================================================================    // 8. Build expiration date string for HKDF info
    // ==================================================================    String? expirationDate;
    if (h.expirationTimestamp != null) {
      final DateTime dt = DateTime.fromMillisecondsSinceEpoch(
        h.expirationTimestamp! * 1000,
        isUtc: true,
      );
      expirationDate = '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    }

    // ==================================================================    // 9. Verify key commitment (if present)
    // ==================================================================    if (h.flags & ZegelFormat.flagHasKeyCommitment != 0) {
      final List<Uint8List> blockKeys = <Uint8List>[];
      for (int i = 0; i < h.blockCount; i++) {
        blockKeys.add(
          KeyDerivation.deriveBlockKey(
            masterKey,
            h.merkleRoot,
            h.salt,
            i,
            expirationDate: expirationDate,
          ),
        );
      }
      final Uint8List computedCommitment = KeyDerivation.computeKeyCommitment(
        blockKeys,
      );

      if (!_constantTimeEquals(computedCommitment, h.keyCommitment!)) {
        throw const ZegelTamperedException('Key commitment mismatch');
      }
    }

    // ==================================================================    // 10. Decrypt each block, verify hashes, decompress, strip canary
    // ==================================================================    int dataOffset = h.dataStart;
    final BytesBuilder contentParts = BytesBuilder();
    Map<String, dynamic>? metadata;
    final List<Map<String, dynamic>> attestations = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> auditTrail = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> provenanceEntries =
        <Map<String, dynamic>>[];
    final List<int> redactedBlocks = <int>[];


    for (int i = 0; i < h.blockCount; i++) {
      final _DirEntry entry = h.directory[i];
      final Uint8List ciphertext = Uint8List.sublistView(
        fileBytes,
        dataOffset,
        dataOffset + entry.ciphertextLen,
      );
      dataOffset += entry.ciphertextLen;

      // Skip redacted blocks -- their hashes are kept for Merkle integrity.
      if (entry.type == ZegelFormat.blockRedacted) {
        redactedBlocks.add(i);
        continue;
      }

      // Derive per-block key.
      final Uint8List blockKey = KeyDerivation.deriveBlockKey(
        masterKey,
        h.merkleRoot,
        h.salt,
        i,
        expirationDate: expirationDate,
      );

      // AES-256-GCM decrypt (input = ciphertext || tag).
      Uint8List plaintext;
      try {
        final GCMBlockCipher cipher = GCMBlockCipher(AESEngine());
        cipher.init(
          false,
          AEADParameters(
            KeyParameter(blockKey),
            ZegelFormat.tagSize * 8,
            entry.iv,
            Uint8List(0),
          ),
        );
        final Uint8List gcmInput = Uint8List(
          ciphertext.length + entry.tag.length,
        );
        gcmInput.setRange(0, ciphertext.length, ciphertext);
        gcmInput.setRange(ciphertext.length, gcmInput.length, entry.tag);
        plaintext = cipher.process(gcmInput);
      } on Exception {
        throw ZegelTamperedException('Block $i: AES-GCM decryption failed');
      }

      // Verify plaintext hash BEFORE decompression.
      // Per spec: "The plaintext hash in the directory is computed from the
      // compressed data (before encryption)."
      final Uint8List ptHash = Uint8List.fromList(
        sha256.convert(plaintext).bytes,
      );
      if (!_constantTimeEquals(ptHash, entry.hash)) {
        throw ZegelTamperedException('Block $i: plaintext hash mismatch');
      }

      // Decompress content blocks (if COMPRESSED flag is set).
      if (h.flags & ZegelFormat.flagCompressed != 0 &&
          entry.type == ZegelFormat.blockContent) {
        plaintext = Uint8List.fromList(
          const ZLibDecoder().decodeBytes(plaintext),
        );
      }

      // Strip canary padding from content blocks.
      if (h.flags & ZegelFormat.flagHasCanary != 0 &&
          entry.type == ZegelFormat.blockContent) {
        plaintext = CanaryTrap.stripPadding(plaintext);
      }

      // Route by block type.
      switch (entry.type) {
        case ZegelFormat.blockContent:
          contentParts.add(plaintext);
        case ZegelFormat.blockMetadata:
          metadata = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
        case ZegelFormat.blockProvenance:
          provenanceEntries.add(
            jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>,
          );
        case ZegelFormat.blockAttestation:
          attestations.add(
            jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>,
          );
        case ZegelFormat.blockAudit:
          auditTrail.add(
            jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>,
          );
        default:
          // PUBLIC_METADATA, FILE_HEADER, REFERENCE, DISCLOSURE_INDEX:
          // silently consumed.
          break;
      }
    }

    // ==================================================================    // 11. Build result
    // ==================================================================    return ZegelResult(
      valid: true,
      content: contentParts.toBytes(),
      metadata: metadata,
      filename: h.filename.isNotEmpty ? h.filename : null,
      contentType: h.contentType.isNotEmpty ? h.contentType : null,
      publicMetadata: h.publicMetadata,
      attestations: attestations.isNotEmpty ? attestations : null,
      auditTrail: auditTrail.isNotEmpty ? auditTrail : null,
      provenance: provenanceEntries.isNotEmpty ? provenanceEntries : null,
      redactedBlocks: redactedBlocks.isNotEmpty ? redactedBlocks : null,
    );
  }

  /// Inspects the file header without requiring the master key.
  ///
  /// Returns public information including version, flags, timestamps,
  /// content type, filename, block count, public metadata, split-key params,
  /// and expiration timestamp.
  ///
  /// Throws [ZegelFormatException] if the binary format is invalid.
  ZegelInspection inspect(Uint8List fileBytes) {
    final _ParsedHeader h = _parseAll(fileBytes);

    Map<String, int>? splitKeyParams;
    if (h.splitKeyThreshold != null && h.splitKeyTotal != null) {
      splitKeyParams = <String, int>{
        'threshold': h.splitKeyThreshold!,
        'total': h.splitKeyTotal!,
      };
    }

    final blocks = <Map<String, dynamic>>[];
    for (int i = 0; i < h.blockCount; i++) {
      blocks.add({
        'index': i,
        'type': h.directory[i].type,
        'ciphertextLen': h.directory[i].ciphertextLen,
      });
    }

    return ZegelInspection(
      version: '$
{

h.versionMajor
}

.$
{

h.versionMinor
}

',
      flags: h.flags,
      timestamp: h.timestamp,
      contentType: h.contentType.isNotEmpty ? h.contentType : null,
      filename: h.filename.isNotEmpty ? h.filename : null,
      blockCount: h.blockCount,
      publicMetadata: h.publicMetadata,
      splitKeyParams: splitKeyParams,
      expirationTimestamp: h.expirationTimestamp,
      blocks: blocks,
    );
  }

  /// Extracts blocks using a selective disclosure [token].
  ///
  /// The token contains per-block derived keys for a subset of blocks.
  /// Only those blocks are decrypted; the master key is not required.
  ///
  /// Returns a [ZegelResult] containing the disclosed content and/or
  /// metadata. Blocks not in the token are inaccessible.
  ///
  /// Throws [ZegelFormatException] if the file format is invalid.
  /// Throws [ZegelTamperedException] if decryption or hash verification fails
  /// for any disclosed block.
  ZegelResult extractWithToken(
    Uint8List fileBytes,
    Map<String, dynamic> token,
  ) {
    final _ParsedHeader h = _parseAll(fileBytes);

    final Map<String, dynamic> blockKeysMap =
        token['block_keys'] as Map<String, dynamic>;

    // Verify token Merkle root matches file
    if (token.containsKey('merkle_root')) {
      final String tokenRoot = token['merkle_root'] as String;
      final String fileRoot = _bytesToHex(h.merkleRoot);
      if (tokenRoot != fileRoot) {
        throw const ZegelTamperedException(
          'Token Merkle root does not match file',
        );
      }
    }

    int dataOffset = h.dataStart;
    // Pre-compute data offsets for each block.
    final List<int> blockDataOffsets = <int>[];
    for (int i = 0; i < h.blockCount; i++) {
      blockDataOffsets.add(dataOffset);
      dataOffset += h.directory[i].ciphertextLen;
    }

    final BytesBuilder contentParts = BytesBuilder();
    Map<String, dynamic>? metadata;
    final List<Map<String, dynamic>> attestations = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> auditTrail = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> provenanceEntries =
        <Map<String, dynamic>>[];
    final List<int> redactedBlocks = <int>[];


    for (int i = 0; i < h.blockCount; i++) {
      final _DirEntry entry = h.directory[i];
      final String indexStr = i.toString();

      if (entry.type == ZegelFormat.blockRedacted) {
        redactedBlocks.add(i);
        continue;
      }

      // Only decrypt blocks for which we have a key.
      if (!blockKeysMap.containsKey(indexStr)) {
        continue;
      }





      final Uint8List blockKey = _hexToBytes(blockKeysMap[indexStr] as String);
      final int bOffset = blockDataOffsets[i];
      final Uint8List ciphertext = Uint8List.sublistView(
        fileBytes,
        bOffset,
        bOffset + entry.ciphertextLen,
      );

      Uint8List plaintext;
      try {
        final GCMBlockCipher cipher = GCMBlockCipher(AESEngine());
        cipher.init(
          false,
          AEADParameters(
            KeyParameter(blockKey),
            ZegelFormat.tagSize * 8,
            entry.iv,
            Uint8List(0),
          ),
        );
        final Uint8List gcmInput = Uint8List(
          ciphertext.length + entry.tag.length,
        );
        gcmInput.setRange(0, ciphertext.length, ciphertext);
        gcmInput.setRange(ciphertext.length, gcmInput.length, entry.tag);
        plaintext = cipher.process(gcmInput);
      } on Exception {
        throw ZegelTamperedException(
          'Block $i: AES-GCM decryption failed with token key',
        );
      }

      // Verify hash.
      final Uint8List ptHash = Uint8List.fromList(
        sha256.convert(plaintext).bytes,
      );
      if (!_constantTimeEquals(ptHash, entry.hash)) {
        throw ZegelTamperedException(
          'Block $i: plaintext hash mismatch (token extraction)',
        );
      }

      // Decompress if needed.
      if (h.flags & ZegelFormat.flagCompressed != 0 &&
          entry.type == ZegelFormat.blockContent) {
        plaintext = Uint8List.fromList(
          const ZLibDecoder().decodeBytes(plaintext),
        );
      }

      // Strip canary padding.
      if (h.flags & ZegelFormat.flagHasCanary != 0 &&
          entry.type == ZegelFormat.blockContent) {
        plaintext = CanaryTrap.stripPadding(plaintext);
      }

      switch (entry.type) {
        case ZegelFormat.blockContent:
          contentParts.add(plaintext);
        case ZegelFormat.blockMetadata:
          metadata = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
        case ZegelFormat.blockProvenance:
          provenanceEntries.add(
            jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>,
          );
        case ZegelFormat.blockAttestation:
          attestations.add(
            jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>,
          );
        case ZegelFormat.blockAudit:
          auditTrail.add(
            jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>,
          );
        default:
          break;
      }
    }

    return ZegelResult(
      valid: true,
      content: contentParts.toBytes(),
      metadata: metadata,
      filename: h.filename.isNotEmpty ? h.filename : null,
      contentType: h.contentType.isNotEmpty ? h.contentType : null,
      publicMetadata: h.publicMetadata,
      attestations: attestations.isNotEmpty ? attestations : null,
      auditTrail: auditTrail.isNotEmpty ? auditTrail : null,
      provenance: provenanceEntries.isNotEmpty ? provenanceEntries : null,
      redactedBlocks: redactedBlocks.isNotEmpty ? redactedBlocks : null,
      disclosedBlocks: null,
    );
  }

  // ====================================================================  // Internal parsing
  // ====================================================================
  /// Parses the complete file structure: header, extended header, block
  /// directory, Merkle root, and key commitment.
  _ParsedHeader _parseAll(Uint8List fileBytes) {
    final _ParsedHeader h = _ParsedHeader();
    final ByteData bd = ByteData.sublistView(fileBytes);

    // -------------------------------------------------------------------------
    // Magic bytes
    // -------------------------------------------------------------------------
    if (fileBytes.length < 8) {
      throw const ZegelFormatException('File too short for magic bytes');
    }
    for (int i = 0; i < ZegelFormat.magic.length; i++) {
      if (fileBytes[i] != ZegelFormat.magic[i]) {
        throw const ZegelFormatException('Invalid magic bytes');
      }
    }

    // -------------------------------------------------------------------------
    // Fixed header fields
    // -------------------------------------------------------------------------
    // Minimum header size: magic(8) + version(2) + flags(2) + timestamp(8) +
    //   content-type(64) + filename-length(2) = 86 bytes.
    if (fileBytes.length < 86) {
      throw const ZegelFormatException('File too short for header');
    }

    h.versionMajor = fileBytes[8];
    h.versionMinor = fileBytes[9];
    h.flags = bd.getUint16(10, Endian.big);
    h.timestamp = bd.getUint64(12, Endian.big);

    // Content-Type (64 bytes, null-padded).
    final Uint8List ctRaw = Uint8List.sublistView(fileBytes, 20, 84);
    int ctEnd = ctRaw.indexOf(0);
    if (ctEnd < 0) ctEnd = ctRaw.length;
    h.contentType = utf8.decode(ctRaw.sublist(0, ctEnd));

    // Filename.
    final int filenameLen = bd.getUint16(84, Endian.big);
    if (fileBytes.length < 86 + filenameLen) {
      throw const ZegelFormatException('File too short for filename');
    }
    h.filename = utf8.decode(fileBytes.sublist(86, 86 + filenameLen));

    // Salt.
    final int saltOffset = 86 + filenameLen;
    if (fileBytes.length < saltOffset + ZegelFormat.saltSize + 4) {
      throw const ZegelFormatException('File too short for salt + block count');
    }
    h.salt = Uint8List.fromList(
      fileBytes.sublist(saltOffset, saltOffset + ZegelFormat.saltSize),
    );

    // Block count.
    final int blockCountOffset = saltOffset + ZegelFormat.saltSize;
    h.blockCount = bd.getUint32(blockCountOffset, Endian.big);

    // -------------------------------------------------------------------------
    // Extended header (flag-dependent, in spec-defined order)
    // -------------------------------------------------------------------------
    int cursor = blockCountOffset + 4;

    if (h.flags & ZegelFormat.flagPasswordDerived != 0) {
      _requireBytes(fileBytes, cursor + 8, 'Argon2 params');
      h.argon2TimeCost = bd.getUint32(cursor, Endian.big);
      cursor += 4;
      h.argon2MemoryCost = bd.getUint32(cursor, Endian.big);
      cursor += 4;
    }

    if (h.flags & ZegelFormat.flagHasExpiration != 0) {
      _requireBytes(fileBytes, cursor + 8, 'expiration timestamp');
      h.expirationTimestamp = bd.getUint64(cursor, Endian.big);
      cursor += 8;
    }

    if (h.flags & ZegelFormat.flagHasCanary != 0) {
      _requireBytes(fileBytes, cursor + 32, 'recipient ID');
      h.recipientId = Uint8List.fromList(
        fileBytes.sublist(cursor, cursor + 32),
      );
      cursor += 32;
    }

    if (h.flags & ZegelFormat.flagSplitKey != 0) {
      _requireBytes(fileBytes, cursor + 2, 'split-key params');
      h.splitKeyThreshold = fileBytes[cursor];
      cursor += 1;
      h.splitKeyTotal = fileBytes[cursor];
      cursor += 1;
    }

    if (h.flags & ZegelFormat.flagVersioned != 0) {
      _requireBytes(fileBytes, cursor + 32, 'version chain hash');
      h.versionChainHash = Uint8List.fromList(
        fileBytes.sublist(cursor, cursor + 32),
      );
      cursor += 32;
    }

    if (h.flags & ZegelFormat.flagHasPublicMetadata != 0) {
      _requireBytes(fileBytes, cursor + 4, 'public metadata length');
      final int pubMetaLen = bd.getUint32(cursor, Endian.big);
      cursor += 4;
      _requireBytes(fileBytes, cursor + pubMetaLen, 'public metadata body');
      final String pubMetaJson = utf8.decode(
        fileBytes.sublist(cursor, cursor + pubMetaLen),
      );
      h.publicMetadata = jsonDecode(pubMetaJson) as Map<String, dynamic>;
      cursor += pubMetaLen;
    }

    // -------------------------------------------------------------------------
    // Block directory
    // -------------------------------------------------------------------------
    h.directoryStart = cursor;
    final int directorySize =
        h.blockCount * ZegelFormat.blockDirectoryEntrySize;
    _requireBytes(fileBytes, cursor + directorySize, 'block directory');

    h.directory = <_DirEntry>[];
    for (int i = 0; i < h.blockCount; i++) {
      final int eo = cursor; // entry offset
      h.directory.add(
        _DirEntry(
          type: fileBytes[eo],
          hash: Uint8List.fromList(fileBytes.sublist(eo + 1, eo + 33)),
          ciphertextLen: bd.getUint32(eo + 33, Endian.big),
          iv: Uint8List.fromList(fileBytes.sublist(eo + 37, eo + 49)),
          tag: Uint8List.fromList(fileBytes.sublist(eo + 49, eo + 65)),
        ),
      );
      cursor += ZegelFormat.blockDirectoryEntrySize;
    }

    // -------------------------------------------------------------------------
    // Merkle root
    // -------------------------------------------------------------------------
    _requireBytes(fileBytes, cursor + ZegelFormat.hashSize, 'Merkle root');
    h.merkleRoot = Uint8List.fromList(
      fileBytes.sublist(cursor, cursor + ZegelFormat.hashSize),
    );
    cursor += ZegelFormat.hashSize;

    // -------------------------------------------------------------------------
    // Key commitment (optional)
    // -------------------------------------------------------------------------
    if (h.flags & ZegelFormat.flagHasKeyCommitment != 0) {
      _requireBytes(fileBytes, cursor + ZegelFormat.hashSize, 'key commitment');
      h.keyCommitment = Uint8List.fromList(
        fileBytes.sublist(cursor, cursor + ZegelFormat.hashSize),
      );
      cursor += ZegelFormat.hashSize;
    }

    h.dataStart = cursor;
    return h;
  }

  /// Ensures the file has at least [requiredLength] bytes; throws otherwise.
  static void _requireBytes(
    Uint8List fileBytes,
    int requiredLength,
    String context,
  ) {
    if (fileBytes.length < requiredLength) {
      throw ZegelFormatException(
        'File too short: expected at least $requiredLength bytes for $context',
      );
    }
  }

  /// Converts bytes to lowercase hex string.
  static String _bytesToHex(Uint8List bytes) {
    final StringBuffer buf = StringBuffer();
    for (final byte in bytes) {
      buf.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  /// Constant-time comparison of two byte arrays.
  ///
  /// Iterates over all bytes regardless of mismatch position to prevent
  /// timing side-channel attacks.
  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Converts a hex string to bytes.
  static Uint8List _hexToBytes(String hex) {
    final int length = hex.length ~/ 2;
    final Uint8List bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
