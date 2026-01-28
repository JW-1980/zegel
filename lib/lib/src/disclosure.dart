import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'format.dart';
import 'key_derivation.dart';

/// Selective disclosure (GEN-9, v1.2).
///
/// Allows the master key holder to generate tokens that enable third parties
/// to decrypt specific blocks without exposing the master key. Each token
/// contains the per-block derived keys for the authorised blocks only.
class SelectiveDisclosure {
  SelectiveDisclosure._();

  /// Generates a selective disclosure token for the specified [blockIndices].
  ///
  /// The token contains the per-block derived keys so that a token holder can
  /// decrypt exactly those blocks and no others. The token is distributed
  /// out-of-band (not embedded in the file).
  ///
  /// [masterKey] is the 32-byte master key.
  /// [merkleRoot] is the 32-byte Merkle root from the file header.
  /// [salt] is the 32-byte master salt from the file header.
  /// [blockIndices] is the list of zero-based block indices to disclose.
  /// [expirationDate] is the optional expiration date string (YYYY-MM-DD) if
  /// the file has `FLAG_HAS_EXPIRATION`.
  /// [expiresAt] is an optional Unix epoch timestamp after which the token
  /// is considered expired and should be rejected by extractors.
  ///
  /// Returns a JSON-serialisable map representing the token.
  static Map<String, dynamic> generateToken(
    Uint8List masterKey,
    Uint8List merkleRoot,
    Uint8List salt,
    List<int> blockIndices, {
    String? expirationDate,
    int? expiresAt,
  }) {
    final Map<String, String> blockKeys = <String, String>{};

    for (final int index in blockIndices) {
      final Uint8List key = KeyDerivation.deriveBlockKey(
        masterKey,
        merkleRoot,
        salt,
        index,
        expirationDate: expirationDate,
      );
      blockKeys[index.toString()] = _bytesToHex(key);
    }

    final int createdAt =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    final Map<String, dynamic> token = <String, dynamic>{
      'version': 1,
      'merkle_root': _bytesToHex(merkleRoot),
      'block_keys': blockKeys,
      'created_at': createdAt,
    };

    if (expiresAt != null) {
      token['expires_at'] = expiresAt;
    }

    return token;
  }

  /// Checks if a selective disclosure token has expired.
  ///
  /// Returns `false` if the token has no `expires_at` field (tokens without
  /// expiration never expire). Returns `true` if the current UTC time is
  /// past the token's `expires_at` timestamp.
  static bool isTokenExpired(Map<String, dynamic> token) {
    if (!token.containsKey('expires_at')) return false;
    final int expiresAt = token['expires_at'] as int;
    final int nowEpoch =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    return nowEpoch > expiresAt;
  }

  /// Extracts and decrypts a single block using a selective disclosure token.
  ///
  /// [fileBytes] is the complete .zgl file.
  /// [token] is the disclosure token (as returned by [generateToken]).
  /// [blockIndex] is the zero-based index of the block to extract.
  ///
  /// Returns the decrypted block content, or `null` if the block index is not
  /// included in the token or decryption fails.
  static Uint8List? extractBlock(
    Uint8List fileBytes,
    Map<String, dynamic> token,
    int blockIndex,
  ) {
    final Map<String, dynamic> blockKeysMap =
        token['block_keys'] as Map<String, dynamic>;
    final String indexStr = blockIndex.toString();

    if (!blockKeysMap.containsKey(indexStr)) {
      return null; // Block not in token.
    }

    final Uint8List blockKey = _hexToBytes(blockKeysMap[indexStr] as String);

    // Parse the file to locate the block's directory entry and ciphertext.
    try {
      final _BlockInfo? info = _parseBlockInfo(fileBytes, blockIndex);
      if (info == null) return null;

      // Decrypt with AES-256-GCM.
      final GCMBlockCipher cipher = GCMBlockCipher(AESEngine());
      cipher.init(
        false,
        AEADParameters(
          KeyParameter(blockKey),
          ZegelFormat.tagSize * 8,
          info.iv,
          Uint8List(0),
        ),
      );

      // Input to GCM decryption = ciphertext || tag.
      final Uint8List input = Uint8List(
        info.ciphertext.length + info.tag.length,
      );
      input.setRange(0, info.ciphertext.length, info.ciphertext);
      input.setRange(info.ciphertext.length, input.length, info.tag);

      return cipher.process(input);
    } on Exception {
      return null;
    }
  }

  /// Parses the file header to extract block info at the given index.
  static _BlockInfo? _parseBlockInfo(Uint8List fileBytes, int blockIndex) {
    if (fileBytes.length < 122) return null;

    final ByteData bd = ByteData.sublistView(fileBytes);

    // Parse filename length at offset 84.
    final int filenameLen = bd.getUint16(84, Endian.big);
    final int blockCountOffset = 86 + filenameLen + 32; // after salt
    if (fileBytes.length < blockCountOffset + 4) return null;

    final int blockCount = bd.getUint32(blockCountOffset, Endian.big);
    if (blockIndex >= blockCount) return null;

    // Parse flags to determine extended header size.
    final int flags = bd.getUint16(10, Endian.big);
    int extHeaderSize = 0;
    if (flags & ZegelFormat.flagPasswordDerived != 0) extHeaderSize += 8;
    if (flags & ZegelFormat.flagHasExpiration != 0) extHeaderSize += 8;
    if (flags & ZegelFormat.flagHasCanary != 0) extHeaderSize += 32;
    if (flags & ZegelFormat.flagSplitKey != 0) extHeaderSize += 2;
    if (flags & ZegelFormat.flagVersioned != 0) extHeaderSize += 32;
    if (flags & ZegelFormat.flagHasPublicMetadata != 0) {
      final int pubMetaOffset = blockCountOffset + 4 + extHeaderSize -
          (flags & ZegelFormat.flagHasPublicMetadata != 0 ? 0 : 0);
      // We need to compute offset up to the public metadata length field.
      int tempOffset = blockCountOffset + 4;
      if (flags & ZegelFormat.flagPasswordDerived != 0) tempOffset += 8;
      if (flags & ZegelFormat.flagHasExpiration != 0) tempOffset += 8;
      if (flags & ZegelFormat.flagHasCanary != 0) tempOffset += 32;
      if (flags & ZegelFormat.flagSplitKey != 0) tempOffset += 2;
      if (flags & ZegelFormat.flagVersioned != 0) tempOffset += 32;
      if (fileBytes.length < tempOffset + 4) return null;
      final int pubMetaLen = bd.getUint32(tempOffset, Endian.big);
      extHeaderSize += 4 + pubMetaLen;
    }

    final int directoryStart = blockCountOffset + 4 + extHeaderSize;
    final int directoryEnd =
        directoryStart + (blockCount * ZegelFormat.blockDirectoryEntrySize);

    // Parse the block directory entry for blockIndex.
    final int entryOffset =
        directoryStart + (blockIndex * ZegelFormat.blockDirectoryEntrySize);
    if (fileBytes.length < entryOffset + ZegelFormat.blockDirectoryEntrySize) {
      return null;
    }

    // Block type (1 byte), hash (32 bytes), ciphertext length (4 bytes),
    // IV (12 bytes), tag (16 bytes)
    final int blockType = fileBytes[entryOffset];
    final Uint8List hash = Uint8List.sublistView(
      fileBytes, entryOffset + 1, entryOffset + 33,
    );
    final int ciphertextLen = bd.getUint32(entryOffset + 33, Endian.big);
    final Uint8List iv = Uint8List.sublistView(
      fileBytes, entryOffset + 37, entryOffset + 49,
    );
    final Uint8List tag = Uint8List.sublistView(
      fileBytes, entryOffset + 49, entryOffset + 65,
    );

    // Compute the offset of the ciphertext data.
    int dataStart = directoryEnd + ZegelFormat.hashSize; // after merkle root
    if (flags & ZegelFormat.flagHasKeyCommitment != 0) {
      dataStart += ZegelFormat.hashSize;
    }

    // Sum up ciphertext lengths of all preceding blocks.
    for (int i = 0; i < blockIndex; i++) {
      final int prevEntryOffset =
          directoryStart + (i * ZegelFormat.blockDirectoryEntrySize);
      dataStart += bd.getUint32(prevEntryOffset + 33, Endian.big);
    }

    if (fileBytes.length < dataStart + ciphertextLen) return null;

    final Uint8List ciphertext = Uint8List.sublistView(
      fileBytes, dataStart, dataStart + ciphertextLen,
    );

    return _BlockInfo(
      blockType: blockType,
      hash: hash,
      ciphertextLen: ciphertextLen,
      iv: Uint8List.fromList(iv),
      tag: Uint8List.fromList(tag),
      ciphertext: Uint8List.fromList(ciphertext),
    );
  }

  /// Converts bytes to lowercase hex string.
  static String _bytesToHex(Uint8List bytes) {
    final StringBuffer buf = StringBuffer();
    for (final byte in bytes) {
      buf.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
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

/// Internal helper holding parsed block info.
class _BlockInfo {
  _BlockInfo({
    required this.blockType,
    required this.hash,
    required this.ciphertextLen,
    required this.iv,
    required this.tag,
    required this.ciphertext,
  });

  final int blockType;
  final Uint8List hash;
  final int ciphertextLen;
  final Uint8List iv;
  final Uint8List tag;
  final Uint8List ciphertext;
}
