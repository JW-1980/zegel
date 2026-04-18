import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'format.dart';

/// Content versioning (GEN-10, v1.2+).
///
/// When `FLAG_VERSIONED` is set, the extended header contains a 32-byte version
/// chain hash that cryptographically links this file to its predecessor. This
/// allows verification that a file is a legitimate successor of another without
/// needing the predecessor's master key.
///
/// v1.3 adds [verifyVersionChain] for verifying an ordered sequence of .zgl
/// files, and [createVersionMetadata] for embedding version information in
/// public metadata.
class ContentVersioning {
  ContentVersioning._();

  /// Computes the version chain hash that links to a predecessor file.
  ///
  /// ```
  /// chainHash = SHA-256(previousMerkleRoot || previousMasterSeal)
  /// ```
  ///
  /// [previousMerkleRoot] is the 32-byte Merkle root of the predecessor file.
  /// [previousMasterSeal] is the 64-byte master seal of the predecessor file.
  ///
  /// Returns a 32-byte SHA-256 hash.
  static Uint8List computeChainHash(
    Uint8List previousMerkleRoot,
    Uint8List previousMasterSeal,
  ) {
    final Uint8List input = Uint8List(
      previousMerkleRoot.length + previousMasterSeal.length,
    );
    input.setRange(0, previousMerkleRoot.length, previousMerkleRoot);
    input.setRange(previousMerkleRoot.length, input.length, previousMasterSeal);
    return Uint8List.fromList(sha256.convert(input).bytes);
  }

  /// Verifies that a [chainHash] correctly links to the given predecessor
  /// file's [previousMerkleRoot] and [previousMasterSeal].
  ///
  /// Returns `true` if the chain hash matches.
  static bool verifyChain(
    Uint8List chainHash,
    Uint8List previousMerkleRoot,
    Uint8List previousMasterSeal,
  ) {
    final Uint8List expected = computeChainHash(
      previousMerkleRoot,
      previousMasterSeal,
    );

    // Constant-time comparison.
    if (chainHash.length != expected.length) return false;
    int diff = 0;
    for (int i = 0; i < chainHash.length; i++) {
      diff |= chainHash[i] ^ expected[i];
    }
    return diff == 0;
  }

  /// Verifies a chain of .zgl files are linked via version chain hashes.
  ///
  /// Given an ordered list of file bytes (oldest first), verifies that each
  /// consecutive pair is linked: the later file's version chain hash must
  /// equal `SHA-256(prev_merkle_root || prev_master_seal)`.
  ///
  /// [fileBytesList] is the ordered list of .zgl file bytes, from the
  /// earliest version to the latest.
  ///
  /// Returns `true` if the entire chain is valid and unbroken.
  ///
  /// Throws [ArgumentError] if fewer than two files are provided.
  /// Throws [ZegelFormatException] if any file cannot be parsed.
  static bool verifyVersionChain(List<Uint8List> fileBytesList) {
    if (fileBytesList.length < 2) {
      throw ArgumentError(
        'At least two files are required to verify a version chain',
      );
    }

    for (int i = 1; i < fileBytesList.length; i++) {
      final _VersionInfo? prevInfo = _extractVersionInfo(fileBytesList[i - 1]);
      final _VersionInfo? currInfo = _extractVersionInfo(fileBytesList[i]);

      if (prevInfo == null ||
          prevInfo.merkleRoot == null ||
          prevInfo.masterSeal == null) {
        return false;
      }

      if (currInfo == null || currInfo.versionChainHash == null) {
        return false;
      }

      if (!verifyChain(
        currInfo.versionChainHash!,
        prevInfo.merkleRoot!,
        prevInfo.masterSeal!,
      )) {
        return false;
      }
    }

    return true;
  }

  /// Creates version metadata suitable for inclusion in public metadata.
  ///
  /// This metadata is informational and does not affect cryptographic
  /// verification, but helps downstream systems understand the document's
  /// revision history.
  ///
  /// [versionNumber] is the sequential version number (starting from 1).
  /// [previousFilename] is the filename of the predecessor file, if any.
  /// [changeSummary] is an optional human-readable description of changes.
  ///
  /// Returns a structured map for merging into public metadata.
  static Map<String, dynamic> createVersionMetadata({
    required int versionNumber,
    required String? previousFilename,
    String? changeSummary,
  }) {
    return <String, dynamic>{
      'version_info': <String, dynamic>{
        'version_number': versionNumber,
        if (previousFilename != null) 'previous_filename': previousFilename,
        if (changeSummary != null) 'change_summary': changeSummary,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
    };
  }

  // ===========================================================================
  // Internal file parsing
  // ===========================================================================

  /// Extracts the Merkle root, master seal, and version chain hash from a
  /// .zgl file's raw bytes.
  ///
  /// Parses just enough of the header to locate these fields without
  /// requiring the master key. Applies the same DoS bounds as [ZegelReader]
  /// so a malicious file cannot trigger unbounded allocation.
  static _VersionInfo? _extractVersionInfo(Uint8List fileBytes) {
    if (fileBytes.length < 86) return null;

    final ByteData bd = ByteData.sublistView(fileBytes);

    // Verify magic bytes.
    for (int i = 0; i < ZegelFormat.magic.length; i++) {
      if (fileBytes[i] != ZegelFormat.magic[i]) return null;
    }

    final int flags = bd.getUint16(10, Endian.big);
    final int filenameLen = bd.getUint16(84, Endian.big);

    if (fileBytes.length < 86 + filenameLen + ZegelFormat.saltSize + 4) {
      return null;
    }

    final int blockCountOffset = 86 + filenameLen + ZegelFormat.saltSize;
    final int blockCount = bd.getUint32(blockCountOffset, Endian.big);

    // DoS prevention: reject an unreasonable block count before using it
    // as a multiplier for the directory skip-offset.
    if (blockCount < 0 || blockCount > ZegelFormat.maxBlockCount) {
      return null;
    }

    // Walk through the extended header to find the version chain hash.
    int cursor = blockCountOffset + 4;
    Uint8List? versionChainHash;

    if (flags & ZegelFormat.flagPasswordDerived != 0) cursor += 8;
    if (flags & ZegelFormat.flagHasExpiration != 0) cursor += 8;
    if (flags & ZegelFormat.flagHasCanary != 0) cursor += 32;
    if (flags & ZegelFormat.flagSplitKey != 0) cursor += 2;

    if (flags & ZegelFormat.flagVersioned != 0) {
      if (fileBytes.length < cursor + 32) return null;
      versionChainHash = Uint8List.fromList(
        fileBytes.sublist(cursor, cursor + 32),
      );
      cursor += 32;
    }

    if (flags & ZegelFormat.flagHasPublicMetadata != 0) {
      if (fileBytes.length < cursor + 4) return null;
      final int pubMetaLen = bd.getUint32(cursor, Endian.big);
      // DoS prevention: cap public metadata size.
      if (pubMetaLen < 0 || pubMetaLen > ZegelFormat.maxPublicMetadataSize) {
        return null;
      }
      cursor += 4 + pubMetaLen;
    }

    // Skip the block directory.
    cursor += blockCount * ZegelFormat.blockDirectoryEntrySize;

    // Read the Merkle root (32 bytes).
    Uint8List? merkleRoot;
    if (fileBytes.length >= cursor + ZegelFormat.hashSize) {
      merkleRoot = Uint8List.fromList(
        fileBytes.sublist(cursor, cursor + ZegelFormat.hashSize),
      );
    }

    // Master seal is the last 64 bytes of the file.
    Uint8List? masterSeal;
    if (fileBytes.length >= ZegelFormat.sealSize) {
      masterSeal = Uint8List.fromList(
        fileBytes.sublist(
          fileBytes.length - ZegelFormat.sealSize,
          fileBytes.length,
        ),
      );
    }

    return _VersionInfo(
      merkleRoot: merkleRoot,
      masterSeal: masterSeal,
      versionChainHash: versionChainHash,
    );
  }
}

/// Internal: Extracted version-related fields from a .zgl file.
class _VersionInfo {
  _VersionInfo({this.merkleRoot, this.masterSeal, this.versionChainHash});

  final Uint8List? merkleRoot;
  final Uint8List? masterSeal;
  final Uint8List? versionChainHash;
}
