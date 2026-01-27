import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Cryptographic key derivation functions for the Zegel format.
///
/// All key derivation follows RFC 5869 (HKDF) with SHA-256. The master key is
/// never used directly for encryption; instead, per-block keys are derived by
/// binding the key to the Merkle root and block index. This ensures that any
/// change to any block invalidates ALL derived keys.
class KeyDerivation {
  KeyDerivation._();

  /// Derives a per-block AES-256 encryption key.
  ///
  /// Uses HKDF (RFC 5869) with SHA-256:
  /// - IKM  = [masterKey] || [merkleRoot] (64 bytes)
  /// - salt = [salt] (32 bytes from the file header)
  /// - info = "zegel-block-key-v1:" + [blockIndex] as decimal string
  ///          (+ ":exp=" + YYYY-MM-DD if [expirationDate] is provided)
  ///
  /// Returns a 32-byte derived key.
  static Uint8List deriveBlockKey(
    Uint8List masterKey,
    Uint8List merkleRoot,
    Uint8List salt,
    int blockIndex, {
    String? expirationDate,
  }) {
    // IKM = masterKey || merkleRoot
    final Uint8List ikm = Uint8List(masterKey.length + merkleRoot.length);
    ikm.setRange(0, masterKey.length, masterKey);
    ikm.setRange(masterKey.length, ikm.length, merkleRoot);

    // HKDF-Extract: PRK = HMAC-SHA256(salt, IKM)
    final hmacExtract = Hmac(sha256, salt);
    final prk = Uint8List.fromList(hmacExtract.convert(ikm).bytes);

    // Build info string
    final StringBuffer infoBuf = StringBuffer('zegel-block-key-v1:');
    infoBuf.write(blockIndex.toString());
    if (expirationDate != null) {
      infoBuf.write(':exp=');
      infoBuf.write(expirationDate);
    }
    final Uint8List infoBytes = Uint8List.fromList(
      utf8.encode(infoBuf.toString()),
    );

    // HKDF-Expand: T(1) = HMAC-SHA256(PRK, info || 0x01)
    // Since we need exactly 32 bytes and HMAC-SHA256 produces 32 bytes,
    // only T(1) is required.
    final Uint8List expandInput = Uint8List(infoBytes.length + 1);
    expandInput.setRange(0, infoBytes.length, infoBytes);
    expandInput[infoBytes.length] = 0x01;

    final hmacExpand = Hmac(sha256, prk);
    return Uint8List.fromList(hmacExpand.convert(expandInput).bytes);
  }

  /// Computes the seal key used to produce the master seal.
  ///
  /// ```
  /// sealKey = HMAC-SHA256(merkleRoot, masterKey || salt)
  /// ```
  ///
  /// The Merkle root is used as the HMAC key, and the concatenation of
  /// [masterKey] and [salt] is the message.
  static Uint8List computeSealKey(
    Uint8List merkleRoot,
    Uint8List masterKey,
    Uint8List salt,
  ) {
    final Uint8List message = Uint8List(masterKey.length + salt.length);
    message.setRange(0, masterKey.length, masterKey);
    message.setRange(masterKey.length, message.length, salt);

    final hmac = Hmac(sha256, merkleRoot);
    return Uint8List.fromList(hmac.convert(message).bytes);
  }

  /// Computes the master seal over the file bytes preceding the seal.
  ///
  /// ```
  /// seal = HMAC-SHA512(sealKey, fileBytes)
  /// ```
  ///
  /// Returns a 64-byte HMAC-SHA512 digest.
  static Uint8List computeMasterSeal(
    Uint8List sealKey,
    Uint8List fileBytes,
  ) {
    final hmac = Hmac(sha512, sealKey);
    return Uint8List.fromList(hmac.convert(fileBytes).bytes);
  }

  /// Computes the key commitment hash (SEC-2).
  ///
  /// ```
  /// commitment = SHA-256(key_0 || key_1 || ... || key_n)
  /// ```
  ///
  /// This prevents invisible salamander attacks where AES-GCM could decrypt
  /// different content under different keys.
  static Uint8List computeKeyCommitment(List<Uint8List> blockKeys) {
    int totalLength = 0;
    for (final key in blockKeys) {
      totalLength += key.length;
    }
    final Uint8List concatenated = Uint8List(totalLength);
    int offset = 0;
    for (final key in blockKeys) {
      concatenated.setRange(offset, offset + key.length, key);
      offset += key.length;
    }
    return Uint8List.fromList(sha256.convert(concatenated).bytes);
  }
}
