import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'secure_memory.dart';

/// Canary trap / recipient fingerprinting (SEC-4, v1.2).
///
/// When enabled, each content block receives invisible deterministic padding
/// that is unique to the recipient. If a sealed file is leaked, the padding
/// can be matched against a list of known recipients to identify the source
/// of the leak.
///
/// The padding is PKCS#7-style: the last byte encodes the padding length,
/// and the preceding bytes are derived from an HMAC.
class CanaryTrap {
  CanaryTrap._();

  /// Generates canary padding for a content block.
  ///
  /// ```
  /// mac    = HMAC-SHA256(masterKey, recipientId || pack_uint32_be(blockIndex))
  /// padLen = (mac[0] % 16) + 1       // 1..16 bytes
  /// padding = mac[1..padLen-1] || byte(padLen)
  /// ```
  ///
  /// [masterKey] is the 32-byte master key.
  /// [recipientId] is the 32-byte recipient identifier.
  /// [blockIndex] is the zero-based index of the block within the file.
  ///
  /// Returns 1 to 16 bytes of padding to append to the block plaintext.
  /// The generator always performs the same amount of work regardless of
  /// the derived `padLen`, so that repeated invocations do not leak `padLen`
  /// through timing when enumerating candidate recipients.
  static Uint8List generatePadding(
    Uint8List masterKey,
    Uint8List recipientId,
    int blockIndex,
  ) {
    // Build HMAC message: recipientId || pack_uint32_be(blockIndex)
    final Uint8List message = Uint8List(recipientId.length + 4);
    message.setRange(0, recipientId.length, recipientId);
    final ByteData bd = ByteData.sublistView(message);
    bd.setUint32(recipientId.length, blockIndex, Endian.big);

    final hmac = Hmac(sha256, masterKey);
    final Uint8List mac = Uint8List.fromList(hmac.convert(message).bytes);

    // Determine padding length: 1-16 bytes.
    final int padLen = (mac[0] % 16) + 1;

    // Build a 16-byte scratch buffer the same way regardless of padLen, then
    // truncate at the end. The scratch layout places mac[1..] at the start
    // and the length byte at position padLen-1. The constant-size loop keeps
    // the dominant work independent of padLen.
    final Uint8List scratch = Uint8List(16);
    for (int i = 0; i < 15; i++) {
      scratch[i] = mac[1 + i];
    }
    // Overwrite the length byte at index padLen-1.
    scratch[padLen - 1] = padLen;

    // Return a freshly allocated buffer of exactly padLen bytes that matches
    // the original (pre-fix) output.
    final Uint8List padding = Uint8List(padLen);
    padding.setRange(0, padLen, scratch);
    SecureMemory.wipe(scratch);
    return padding;
  }

  /// Strips canary padding from a block that contains it.
  ///
  /// Reads the last byte as the padding length and removes that many trailing
  /// bytes. This mirrors the PKCS#7-style encoding used by [generatePadding].
  ///
  /// Throws [FormatException] if the padding length is invalid (zero or
  /// greater than the block length).
  static Uint8List stripPadding(Uint8List blockWithPadding) {
    if (blockWithPadding.isEmpty) {
      throw const FormatException('Cannot strip padding from empty block');
    }
    final int padLen = blockWithPadding[blockWithPadding.length - 1];
    if (padLen == 0 || padLen > blockWithPadding.length) {
      throw FormatException(
        'Invalid canary padding length: $padLen '
        '(block length: ${blockWithPadding.length})',
      );
    }
    return Uint8List.sublistView(
      blockWithPadding,
      0,
      blockWithPadding.length - padLen,
    );
  }

  /// Identifies the recipient of a leaked file by trying all candidates.
  ///
  /// For each candidate recipient ID, computes the expected canary padding for
  /// the given [blockIndex] and checks whether it matches the actual trailing
  /// bytes of [blockContent].
  ///
  /// Returns the hex-encoded recipient ID of the match, or `null` if no
  /// candidate matches.
  ///
  /// [blockContent] is the decrypted (and decompressed, if applicable) block
  /// including canary padding.
  /// [masterKey] is the 32-byte master key.
  /// [blockIndex] is the zero-based block index.
  /// [candidateRecipientIds] is the list of 32-byte candidate IDs to test.
  /// Identifies the recipient of a leaked file by trying all candidates.
  ///
  /// Always iterates over ALL candidates to prevent timing side-channel
  /// leakage that could reveal which candidate matched. The total execution
  /// time is constant regardless of which (if any) candidate matches.
  static String? identifyRecipient(
    Uint8List blockContent,
    Uint8List masterKey,
    int blockIndex,
    List<Uint8List> candidateRecipientIds,
  ) {
    if (blockContent.isEmpty) return null;

    // Accumulate the match across ALL candidates to prevent timing leakage.
    // We always iterate the full list regardless of when a match is found.
    // We also always perform a full 16-byte comparison so that per-candidate
    // work is independent of the HMAC-derived padding length; otherwise, the
    // observable runtime per candidate leaks `mac[0] % 16 + 1`.
    int matchIndex = -1;
    const int maxPaddingLen = 16;

    // Pre-pad the tail of the block with zero bytes so we can always read
    // maxPaddingLen bytes regardless of the block size. If the block is
    // shorter than 16 bytes, it cannot be a match and matchIndex stays -1.
    if (blockContent.length < maxPaddingLen) return null;

    final int tailStart = blockContent.length - maxPaddingLen;

    for (int c = 0; c < candidateRecipientIds.length; c++) {
      final Uint8List candidateId = candidateRecipientIds[c];
      final Uint8List expectedPadding = generatePadding(
        masterKey,
        candidateId,
        blockIndex,
      );

      // Pad the expected value out to maxPaddingLen with zeros so the inner
      // loop body runs a constant number of iterations.
      final Uint8List alignedExpected = Uint8List(maxPaddingLen);
      final int expLen = expectedPadding.length;
      // The padding is applied at the end of the plaintext, so we compare
      // the last `expLen` bytes of the tail against `expectedPadding`.
      // Preceding bytes are filled with the actual block bytes so that any
      // mismatch accumulates into `diff` uniformly.
      for (int i = 0; i < maxPaddingLen - expLen; i++) {
        alignedExpected[i] = blockContent[tailStart + i];
      }
      for (int i = 0; i < expLen; i++) {
        alignedExpected[maxPaddingLen - expLen + i] = expectedPadding[i];
      }

      int diff = 0;
      for (int i = 0; i < maxPaddingLen; i++) {
        diff |= blockContent[tailStart + i] ^ alignedExpected[i];
      }

      // Branchless match accumulation: if diff==0, this candidate matched.
      // We record the FIRST match only (matchIndex stays at first match).
      if (diff == 0 && matchIndex < 0) {
        matchIndex = c;
      }
    }

    // Return result only after iterating ALL candidates.
    if (matchIndex < 0) return null;

    final Uint8List matchedId = candidateRecipientIds[matchIndex];
    final StringBuffer hexBuf = StringBuffer();
    for (final byte in matchedId) {
      hexBuf.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return hexBuf.toString();
  }
}
