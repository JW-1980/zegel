import 'dart:math';
import 'dart:typed_data';

import 'format.dart';
import 'key_derivation.dart';

/// Partial redaction (SEC-5, v1.2).
///
/// Allows permanently redacting specific blocks from a sealed file while
/// preserving the Merkle tree integrity. Redacted blocks have their ciphertext
/// replaced with cryptographically random bytes, their block type changed to
/// REDACTED (0x06), and their original plaintext hash preserved so that the
/// Merkle root remains valid.
///
/// Redaction is irreversible. Only the file owner should have redaction
/// authority.
class Redaction {
  Redaction._();

  /// Redacts the specified blocks from a sealed .zgl file.
  ///
  /// The file is first verified for integrity. For each block in
  /// [blockIndices], the ciphertext is replaced with random bytes of the same
  /// length, the block type is changed to REDACTED (0x06), and the original
  /// hash/IV/tag are preserved.
  ///
  /// The `FLAG_HAS_REDACTIONS` flag (0x0100) is set in the header, and the
  /// master seal is recomputed over the modified file.
  ///
  /// [fileBytes] is the original .zgl file.
  /// [masterKey] is the 32-byte master key.
  /// [blockIndices] is the list of zero-based block indices to redact.
  ///
  /// Returns the modified file bytes.
  ///
  /// Throws [ZegelFormatException] if the file cannot be parsed.
  /// Throws [ZegelTamperedException] if the original file fails integrity
  /// verification.
  /// Throws [ArgumentError] if any block index is out of range.
  static Uint8List redactBlocks(
    Uint8List fileBytes,
    Uint8List masterKey,
    List<int> blockIndices,
  ) {
    // Work on a mutable copy.
    final Uint8List result = Uint8List.fromList(fileBytes);
    final ByteData bd = ByteData.sublistView(result);

    // --- Parse header ---
    _validateMagic(result);
    final int flags = bd.getUint16(10, Endian.big);
    final int filenameLen = bd.getUint16(84, Endian.big);

    // Salt starts at offset 86 + filenameLen.
    final int saltOffset = 86 + filenameLen;
    final Uint8List salt = Uint8List.sublistView(
      result,
      saltOffset,
      saltOffset + ZegelFormat.saltSize,
    );

    // Block count at saltOffset + 32.
    final int blockCountOffset = saltOffset + ZegelFormat.saltSize;
    final int blockCount = bd.getUint32(blockCountOffset, Endian.big);

    // Validate block indices.
    for (final int idx in blockIndices) {
      if (idx < 0 || idx >= blockCount) {
        throw ArgumentError(
          'Block index $idx out of range [0, $blockCount)',
        );
      }
    }

    // Compute extended header size.
    final int extHeaderSize = _computeExtendedHeaderSize(result, flags, blockCountOffset + 4);

    // Block directory starts after extended header.
    final int directoryStart = blockCountOffset + 4 + extHeaderSize;

    // Merkle root is after the block directory.
    final int merkleRootOffset =
        directoryStart + (blockCount * ZegelFormat.blockDirectoryEntrySize);
    final Uint8List merkleRoot = Uint8List.sublistView(
      result,
      merkleRootOffset,
      merkleRootOffset + ZegelFormat.hashSize,
    );

    // Key commitment offset (if present).
    int dataStart = merkleRootOffset + ZegelFormat.hashSize;
    if (flags & ZegelFormat.flagHasKeyCommitment != 0) {
      dataStart += ZegelFormat.hashSize;
    }

    // --- Verify the master seal of the original file ---
    final Uint8List originalSealKey = KeyDerivation.computeSealKey(
      merkleRoot,
      masterKey,
      salt,
    );
    final Uint8List preSealBytes = Uint8List.sublistView(
      fileBytes,
      0,
      fileBytes.length - ZegelFormat.sealSize,
    );
    final Uint8List expectedSeal = KeyDerivation.computeMasterSeal(
      originalSealKey,
      preSealBytes,
    );
    final Uint8List storedSeal = Uint8List.sublistView(
      fileBytes,
      fileBytes.length - ZegelFormat.sealSize,
    );
    if (!_constantTimeEquals(expectedSeal, storedSeal)) {
      throw const ZegelTamperedException(
        'Original file seal verification failed before redaction',
      );
    }

    // --- Set the HAS_REDACTIONS flag ---
    final int newFlags = flags | ZegelFormat.flagHasRedactions;
    bd.setUint16(10, newFlags, Endian.big);

    // --- Redact each specified block ---
    final random = Random.secure();

    // Build a map of ciphertext offsets.
    int ciphertextOffset = dataStart;
    final List<int> blockCiphertextOffsets = <int>[];
    final List<int> blockCiphertextLengths = <int>[];
    for (int i = 0; i < blockCount; i++) {
      final int entryOffset =
          directoryStart + (i * ZegelFormat.blockDirectoryEntrySize);
      final int ctLen = bd.getUint32(entryOffset + 33, Endian.big);
      blockCiphertextOffsets.add(ciphertextOffset);
      blockCiphertextLengths.add(ctLen);
      ciphertextOffset += ctLen;
    }

    for (final int idx in blockIndices) {
      final int entryOffset =
          directoryStart + (idx * ZegelFormat.blockDirectoryEntrySize);

      // Change block type to REDACTED.
      result[entryOffset] = ZegelFormat.blockRedacted;

      // Replace ciphertext with random bytes.
      final int ctOffset = blockCiphertextOffsets[idx];
      final int ctLen = blockCiphertextLengths[idx];
      for (int b = 0; b < ctLen; b++) {
        result[ctOffset + b] = random.nextInt(256);
      }
    }

    // --- Recompute master seal ---
    final Uint8List modifiedPreSeal = Uint8List.sublistView(
      result,
      0,
      result.length - ZegelFormat.sealSize,
    );
    final Uint8List newSealKey = KeyDerivation.computeSealKey(
      merkleRoot,
      masterKey,
      salt,
    );
    final Uint8List newSeal = KeyDerivation.computeMasterSeal(
      newSealKey,
      modifiedPreSeal,
    );

    // Write the new seal.
    result.setRange(
      result.length - ZegelFormat.sealSize,
      result.length,
      newSeal,
    );

    return result;
  }

  /// Validates the magic bytes at the start of the file.
  static void _validateMagic(Uint8List fileBytes) {
    if (fileBytes.length < 8) {
      throw const ZegelFormatException('File too short for magic bytes');
    }
    for (int i = 0; i < ZegelFormat.magic.length; i++) {
      if (fileBytes[i] != ZegelFormat.magic[i]) {
        throw const ZegelFormatException('Invalid magic bytes');
      }
    }
  }

  /// Computes the total size of the extended header.
  static int _computeExtendedHeaderSize(
    Uint8List fileBytes,
    int flags,
    int extStart,
  ) {
    final ByteData bd = ByteData.sublistView(fileBytes);
    int size = 0;

    if (flags & ZegelFormat.flagPasswordDerived != 0) size += 8;
    if (flags & ZegelFormat.flagHasExpiration != 0) size += 8;
    if (flags & ZegelFormat.flagHasCanary != 0) size += 32;
    if (flags & ZegelFormat.flagSplitKey != 0) size += 2;
    if (flags & ZegelFormat.flagVersioned != 0) size += 32;
    if (flags & ZegelFormat.flagHasPublicMetadata != 0) {
      final int pubMetaLenOffset = extStart + size;
      final int pubMetaLen = bd.getUint32(pubMetaLenOffset, Endian.big);
      size += 4 + pubMetaLen;
    }

    return size;
  }

  /// Constant-time comparison of two byte arrays.
  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
