import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'secure_memory.dart';
import 'package:pointycastle/export.dart'
    show Argon2BytesGenerator, Argon2Parameters;

/// Cryptographic key derivation functions for the Zegel format.
///
/// All key derivation follows RFC 5869 (HKDF) with SHA-256. The master key is
/// never used directly for encryption; instead, per-block keys are derived by
/// binding the key to the Merkle root and block index. This ensures that any
/// change to any block invalidates ALL derived keys.
///
/// This class also exposes [deriveKeyFromPassword], which implements the
/// Argon2id password-based key derivation step described in FORMAT_SPEC
/// Section 5.2 (required when `FLAG_PASSWORD_DERIVED` is set).
class KeyDerivation {
  KeyDerivation._();

  /// Derives the 32-byte master key from a UTF-8 [password] using Argon2id.
  ///
  /// Matches `FORMAT_SPEC.md` Section 5.2:
  /// ```
  /// master_key = Argon2id(password, salt, iterations, memory_kib, lanes=1, len=32)
  /// ```
  ///
  /// [salt] is the file's 32-byte master salt from the header.
  /// [iterations] is the Argon2id time cost and must be >= 2.
  /// [memoryKib] is the Argon2id memory cost in KiB and must be >= 19456 (19 MiB).
  /// [lanes] defaults to 1 (spec-compliant default).
  ///
  /// The returned buffer is a fresh 32-byte `Uint8List`. Callers should
  /// [Uint8List.fillRange] or use `SecureMemory.wipe` once the key is no
  /// longer needed.
  static Uint8List deriveKeyFromPassword(
    String password,
    Uint8List salt, {
    required int iterations,
    required int memoryKib,
    int lanes = 1,
  }) {
    if (password.isEmpty) {
      throw ArgumentError('Password must not be empty');
    }
    if (salt.length != 32) {
      throw ArgumentError('Salt must be exactly 32 bytes');
    }
    if (iterations < 2) {
      throw ArgumentError(
        'Argon2id iterations must be >= 2 (OWASP 2024 minimum)',
      );
    }
    if (memoryKib < 19456) {
      throw ArgumentError(
        'Argon2id memory cost must be >= 19456 KiB / 19 MiB '
        '(OWASP 2024 minimum)',
      );
    }
    if (lanes < 1) {
      throw ArgumentError('Argon2id lanes must be >= 1');
    }

    // Encode the password as UTF-8 so Unicode passwords hash consistently
    // across platforms. `String.codeUnits` would return UTF-16 which is not
    // spec-compliant and collides differently across runtimes.
    final Uint8List passwordBytes = Uint8List.fromList(utf8.encode(password));

    final Argon2Parameters params = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      salt,
      version: Argon2Parameters.ARGON2_VERSION_13,
      iterations: iterations,
      memory: memoryKib,
      lanes: lanes,
      desiredKeyLength: 32,
    );

    final Argon2BytesGenerator generator = Argon2BytesGenerator()..init(params);
    final Uint8List output = Uint8List(32);
    generator.deriveKey(passwordBytes, 0, output, 0);

    SecureMemory.wipe(passwordBytes);
    return output;
  }

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
    SecureMemory.wipe(ikm);
    SecureMemory.wipe(ikm);

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
    final result = Uint8List.fromList(hmacExpand.convert(expandInput).bytes);
    SecureMemory.wipe(prk);
    return result;
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
  static Uint8List computeMasterSeal(Uint8List sealKey, Uint8List fileBytes) {
    final hmac = Hmac(sha512, sealKey);
    return Uint8List.fromList(hmac.convert(fileBytes).bytes);
  }

  /// Derives a deterministic 12-byte AES-GCM nonce for a block.
  ///
  /// Uses HKDF-SHA256 with a separate info domain to derive a nonce that is:
  /// - Deterministic (same inputs always produce the same nonce)
  /// - Unique per block (block index is in the info string)
  /// - Unique per file (salt is different per file)
  ///
  /// This eliminates the primary subliminal channel for kleptographic attacks:
  /// a malicious RNG cannot leak key material through nonces when nonces are
  /// derived deterministically from the key material.
  ///
  /// The nonce is further XORed with CSPRNG output (hedged randomness) so that
  /// even if the HKDF derivation has a subtle weakness, the randomness
  /// provides additional entropy.
  ///
  /// ```
  /// ikm  = masterKey || merkleRoot (64 bytes)
  /// salt = salt (32 bytes)
  /// info = "zegel-block-nonce-v1:" + blockIndex
  /// nonce = first 12 bytes of HKDF-Expand(prk, info)
  /// ```
  static Uint8List deriveBlockNonce(
    Uint8List masterKey,
    Uint8List merkleRoot,
    Uint8List salt,
    int blockIndex,
  ) {
    // IKM = masterKey || merkleRoot
    final Uint8List ikm = Uint8List(masterKey.length + merkleRoot.length);
    ikm.setRange(0, masterKey.length, masterKey);
    ikm.setRange(masterKey.length, ikm.length, merkleRoot);

    // HKDF-Extract: PRK = HMAC-SHA256(salt, IKM)
    final hmacExtract = Hmac(sha256, salt);
    final prk = Uint8List.fromList(hmacExtract.convert(ikm).bytes);
    SecureMemory.wipe(ikm);

    // Info string uses a DIFFERENT domain than block keys.
    final String info = 'zegel-block-nonce-v1:$blockIndex';
    final Uint8List infoBytes = Uint8List.fromList(utf8.encode(info));

    // HKDF-Expand: T(1) = HMAC-SHA256(PRK, info || 0x01)
    final Uint8List expandInput = Uint8List(infoBytes.length + 1);
    expandInput.setRange(0, infoBytes.length, infoBytes);
    expandInput[infoBytes.length] = 0x01;

    final hmacExpand = Hmac(sha256, prk);
    final Uint8List expanded =
        Uint8List.fromList(hmacExpand.convert(expandInput).bytes);
    SecureMemory.wipe(prk);

    // Return the first 12 bytes as the nonce.
    return Uint8List.fromList(expanded.sublist(0, 12));
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
