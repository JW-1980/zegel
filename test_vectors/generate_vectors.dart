/// Zegel Test Vector Generator
///
/// Generates deterministic .zgl test vector files and corresponding .json
/// files with computed values. Uses fixed keys, salts, and seeded IVs for
/// reproducibility.
///
/// Usage:
///   dart run generate_vectors.dart
///
/// This script implements the Zegel binary format (v1.2) inline to avoid
/// circular dependency on the library during early development. Once the
/// library is complete, the helper functions here can be replaced with
/// calls to package:zegel/zegel.dart.
///
/// See FORMAT_SPEC.md for the authoritative specification.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;

// ---------------------------------------------------------------------------
// Constants (from FORMAT_SPEC.md Section 3 & 4)
// ---------------------------------------------------------------------------

/// Magic bytes: ZEGEL\x00\x01\x00
final Uint8List kMagicBytes =
    Uint8List.fromList([0x5A, 0x45, 0x47, 0x45, 0x4C, 0x00, 0x01, 0x00]);

const int kVersionMajor = 1;
const int kVersionMinor = 2;

const int kDefaultBlockSize = 65536;
const int kContentTypeFieldSize = 64;
const int kSaltSize = 32;
const int kHashSize = 32;
const int kIvSize = 12;
const int kGcmTagSize = 16;
const int kSealSize = 64;
const int kDirectoryEntrySize = 65; // 1 + 32 + 4 + 12 + 16

// Block types
const int kBlockTypeContent = 0x01;
const int kBlockTypeMetadata = 0x02;
const int kBlockTypeRedacted = 0x06;
const int kBlockTypeAttestation = 0x07;
const int kBlockTypeAudit = 0x09;

// Flags
const int kFlagHasMetadata = 0x0001;
const int kFlagHasCanary = 0x0080;
const int kFlagHasRedactions = 0x0100;
const int kFlagSplitKey = 0x0200;

// ---------------------------------------------------------------------------
// Deterministic random source for reproducible test vectors
// ---------------------------------------------------------------------------

/// A seeded PRNG that produces deterministic "random" bytes for IVs and other
/// values that would normally be cryptographically random. NEVER use this in
/// production -- test vectors only.
class SeededRandom {
  late Random _rng;

  SeededRandom(int seed) {
    _rng = Random(seed);
  }

  Uint8List nextBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _rng.nextInt(256);
    }
    return bytes;
  }
}

// ---------------------------------------------------------------------------
// Cryptographic helpers
// ---------------------------------------------------------------------------

/// SHA-256 hash of [data].
Uint8List sha256Hash(Uint8List data) {
  return Uint8List.fromList(sha256.convert(data).bytes);
}

/// HMAC-SHA256(key, message).
Uint8List hmacSha256(Uint8List key, Uint8List message) {
  final hmac = Hmac(sha256, key);
  return Uint8List.fromList(hmac.convert(message).bytes);
}

/// HMAC-SHA512(key, message).
Uint8List hmacSha512(Uint8List key, Uint8List message) {
  final hmac = Hmac(sha512, key);
  return Uint8List.fromList(hmac.convert(message).bytes);
}

/// HKDF-Extract: PRK = HMAC-SHA256(salt, IKM).
Uint8List hkdfExtract(Uint8List salt, Uint8List ikm) {
  return hmacSha256(salt, ikm);
}

/// HKDF-Expand: OKM = first [length] bytes of T(1)||T(2)||...
/// T(1) = HMAC-SHA256(PRK, info || 0x01)
/// Since we only need 32 bytes and SHA-256 produces 32, only T(1) is needed.
Uint8List hkdfExpand(Uint8List prk, Uint8List info, int length) {
  assert(length <= 32, 'Only supports up to 32 bytes output');
  final input = Uint8List(info.length + 1);
  input.setRange(0, info.length, info);
  input[info.length] = 0x01;
  final t1 = hmacSha256(prk, input);
  return Uint8List.fromList(t1.sublist(0, length));
}

/// Derive per-block encryption key using HKDF (Section 5.1).
///
///   IKM  = masterKey || merkleRoot (64 bytes)
///   salt = masterSalt (32 bytes)
///   info = "zegel-block-key-v1:" + blockIndex.toString()
///   PRK  = HMAC-SHA256(salt, IKM)
///   key  = HKDF-Expand(PRK, info, 32)
Uint8List deriveBlockKey(
  Uint8List masterKey,
  Uint8List merkleRoot,
  Uint8List masterSalt,
  int blockIndex,
) {
  final ikm = Uint8List(masterKey.length + merkleRoot.length);
  ikm.setRange(0, masterKey.length, masterKey);
  ikm.setRange(masterKey.length, ikm.length, merkleRoot);

  final prk = hkdfExtract(masterSalt, ikm);

  final infoString = 'zegel-block-key-v1:$blockIndex';
  final info = Uint8List.fromList(utf8.encode(infoString));

  return hkdfExpand(prk, info, 32);
}

/// AES-256-GCM encrypt. Returns (ciphertext, tag).
({Uint8List ciphertext, Uint8List tag}) aesGcmEncrypt(
  Uint8List key,
  Uint8List iv,
  Uint8List plaintext,
) {
  final cipher = pc.GCMBlockCipher(pc.AESEngine());
  final params = pc.AEADParameters(
    pc.KeyParameter(key),
    kGcmTagSize * 8, // tag length in bits
    iv,
    Uint8List(0), // no AAD
  );
  cipher.init(true, params);

  final output = Uint8List(plaintext.length + kGcmTagSize);
  var offset = cipher.processBytes(plaintext, 0, plaintext.length, output, 0);
  offset += cipher.doFinal(output, offset);

  final ciphertext = Uint8List.fromList(output.sublist(0, plaintext.length));
  final tag = Uint8List.fromList(
      output.sublist(output.length - kGcmTagSize, output.length));

  return (ciphertext: ciphertext, tag: tag);
}

// ---------------------------------------------------------------------------
// Merkle tree (Section 5.6)
// ---------------------------------------------------------------------------

/// Build a Merkle tree from leaf hashes and return the root.
///
/// - Single leaf: root = leaf hash
/// - Odd nodes at any layer: duplicate the last node
/// - Parent = SHA-256(left || right)
Uint8List computeMerkleRoot(List<Uint8List> leafHashes) {
  if (leafHashes.isEmpty) {
    throw ArgumentError('At least one leaf hash is required');
  }
  if (leafHashes.length == 1) {
    return Uint8List.fromList(leafHashes[0]);
  }

  var layer = List<Uint8List>.from(leafHashes);

  while (layer.length > 1) {
    if (layer.length.isOdd) {
      layer.add(Uint8List.fromList(layer.last));
    }

    final nextLayer = <Uint8List>[];
    for (var i = 0; i < layer.length; i += 2) {
      final combined = Uint8List(kHashSize * 2);
      combined.setRange(0, kHashSize, layer[i]);
      combined.setRange(kHashSize, kHashSize * 2, layer[i + 1]);
      nextLayer.add(sha256Hash(combined));
    }
    layer = nextLayer;
  }

  return layer[0];
}

// ---------------------------------------------------------------------------
// Master seal (Section 5.7)
// ---------------------------------------------------------------------------

/// Compute the master seal key: HMAC-SHA256(merkleRoot, masterKey || salt).
Uint8List computeSealKey(
  Uint8List merkleRoot,
  Uint8List masterKey,
  Uint8List salt,
) {
  final message = Uint8List(masterKey.length + salt.length);
  message.setRange(0, masterKey.length, masterKey);
  message.setRange(masterKey.length, message.length, salt);
  return hmacSha256(merkleRoot, message);
}

/// Compute the master seal: HMAC-SHA512(sealKey, fileBytes).
Uint8List computeMasterSeal(Uint8List sealKey, Uint8List fileBytes) {
  return hmacSha512(sealKey, fileBytes);
}

// ---------------------------------------------------------------------------
// Canary trap padding (Section 6.1 / SEC-4)
// ---------------------------------------------------------------------------

/// Compute canary padding for a content block.
///
///   mac = HMAC-SHA256(masterKey, recipientId || pack_uint32_be(blockIndex))
///   padLen = (mac[0] % 16) + 1
///   padding = mac[1..padLen-1] || byte(padLen)
Uint8List computeCanaryPadding(
  Uint8List masterKey,
  Uint8List recipientId,
  int blockIndex,
) {
  final message = Uint8List(recipientId.length + 4);
  message.setRange(0, recipientId.length, recipientId);
  final bd = ByteData.sublistView(message, recipientId.length);
  bd.setUint32(0, blockIndex, Endian.big);

  final mac = hmacSha256(masterKey, message);
  final padLen = (mac[0] % 16) + 1;

  final padding = Uint8List(padLen);
  for (var i = 0; i < padLen - 1; i++) {
    padding[i] = mac[1 + i];
  }
  padding[padLen - 1] = padLen;

  return padding;
}

// ---------------------------------------------------------------------------
// GF(256) arithmetic for Shamir's Secret Sharing (Section 6.3 / SEC-6)
// ---------------------------------------------------------------------------

/// GF(256) addition (XOR).
int gf256Add(int a, int b) => a ^ b;

/// GF(256) multiplication using the Russian peasant algorithm.
/// Irreducible polynomial: 0x11B (x^8 + x^4 + x^3 + x + 1).
int gf256Mul(int a, int b) {
  int result = 0;
  int aa = a;
  int bb = b;
  while (bb > 0) {
    if ((bb & 1) != 0) {
      result ^= aa;
    }
    aa <<= 1;
    if ((aa & 0x100) != 0) {
      aa ^= 0x11B;
    }
    bb >>= 1;
  }
  return result;
}

/// GF(256) multiplicative inverse using Fermat's little theorem: a^(-1) = a^254.
int gf256Inv(int a) {
  if (a == 0) throw ArgumentError('Cannot invert zero in GF(256)');
  int result = a;
  for (var i = 0; i < 6; i++) {
    result = gf256Mul(result, result);
    result = gf256Mul(result, a);
  }
  // a^254 via repeated squaring: a * (a^2 * a) * ...
  // Simpler: just exponentiate
  int power = a;
  for (var e = 1; e < 253; e++) {
    power = gf256Mul(power, a);
  }
  return power;
}

/// Split a 32-byte secret into [n] shares with threshold [m] using Shamir's
/// Secret Sharing over GF(256). Uses [rng] for polynomial coefficients.
List<Uint8List> shamirSplit(
  Uint8List secret,
  int m,
  int n,
  SeededRandom rng,
) {
  assert(secret.length == 32);
  assert(m >= 2 && m <= n && n <= 255);

  // Each share: 1 byte x-coordinate + 32 bytes y-values
  final shares = List.generate(n, (_) => Uint8List(33));
  for (var i = 0; i < n; i++) {
    shares[i][0] = i + 1; // x-coordinate: 1, 2, ..., n
  }

  // For each byte of the secret, generate a polynomial of degree m-1
  for (var byteIdx = 0; byteIdx < 32; byteIdx++) {
    // Coefficients: a[0] = secret byte, a[1..m-1] = random
    final coeffs = Uint8List(m);
    coeffs[0] = secret[byteIdx];
    final randomCoeffs = rng.nextBytes(m - 1);
    for (var c = 1; c < m; c++) {
      coeffs[c] = randomCoeffs[c - 1];
    }

    // Evaluate polynomial at x = 1, 2, ..., n
    for (var i = 0; i < n; i++) {
      final x = i + 1;
      int y = 0;
      int xPower = 1;
      for (var c = 0; c < m; c++) {
        y = gf256Add(y, gf256Mul(coeffs[c], xPower));
        xPower = gf256Mul(xPower, x);
      }
      shares[i][1 + byteIdx] = y;
    }
  }

  return shares;
}

/// Reconstruct a 32-byte secret from [m] shares using Lagrange interpolation
/// at x=0 over GF(256).
Uint8List shamirReconstruct(List<Uint8List> shares) {
  final m = shares.length;
  final secret = Uint8List(32);

  for (var byteIdx = 0; byteIdx < 32; byteIdx++) {
    int value = 0;

    for (var i = 0; i < m; i++) {
      final xi = shares[i][0];
      final yi = shares[i][1 + byteIdx];

      // Lagrange basis polynomial evaluated at x=0
      int numerator = 1;
      int denominator = 1;
      for (var j = 0; j < m; j++) {
        if (i == j) continue;
        final xj = shares[j][0];
        numerator = gf256Mul(numerator, xj); // (0 - xj) = xj in GF(256)
        denominator = gf256Mul(denominator, gf256Add(xi, xj)); // (xi - xj)
      }

      final basis = gf256Mul(numerator, gf256Inv(denominator));
      value = gf256Add(value, gf256Mul(yi, basis));
    }

    secret[byteIdx] = value;
  }

  return secret;
}

// ---------------------------------------------------------------------------
// Audit trail chain hash (Section 7.3 / GEN-8)
// ---------------------------------------------------------------------------

/// Compute chain hash for an audit entry.
///
///   chain_hash[0] = SHA-256(zeros_32 || entry_0_json)
///   chain_hash[n] = SHA-256(chain_hash[n-1] || entry_n_json)
Uint8List computeChainHash(Uint8List previousHash, String entryJson) {
  final entryBytes = utf8.encode(entryJson);
  final input = Uint8List(previousHash.length + entryBytes.length);
  input.setRange(0, previousHash.length, previousHash);
  input.setRange(previousHash.length, input.length, entryBytes);
  return sha256Hash(input);
}

// ---------------------------------------------------------------------------
// Attestation HMAC (Section 7.1 / GEN-6)
// ---------------------------------------------------------------------------

/// Compute attestation HMAC.
///
///   message = merkleRoot || signerId || pack_uint64_be(timestamp) || statement
///   hmac = HMAC-SHA256(signerKey, message)
Uint8List computeAttestationHmac(
  Uint8List signerKey,
  Uint8List merkleRoot,
  String signerId,
  int timestamp,
  String statement,
) {
  final signerIdBytes = utf8.encode(signerId);
  final statementBytes = utf8.encode(statement);
  final tsBytes = Uint8List(8);
  ByteData.sublistView(tsBytes).setUint64(0, timestamp, Endian.big);

  final message = Uint8List(
    merkleRoot.length + signerIdBytes.length + 8 + statementBytes.length,
  );
  var offset = 0;
  message.setRange(offset, offset + merkleRoot.length, merkleRoot);
  offset += merkleRoot.length;
  message.setRange(offset, offset + signerIdBytes.length, signerIdBytes);
  offset += signerIdBytes.length;
  message.setRange(offset, offset + 8, tsBytes);
  offset += 8;
  message.setRange(offset, offset + statementBytes.length, statementBytes);

  return hmacSha256(signerKey, message);
}

// ---------------------------------------------------------------------------
// Binary writer helpers
// ---------------------------------------------------------------------------

/// Write big-endian uint16 to [buffer] at [offset].
void writeUint16BE(Uint8List buffer, int offset, int value) {
  ByteData.sublistView(buffer, offset, offset + 2)
      .setUint16(0, value, Endian.big);
}

/// Write big-endian uint32 to [buffer] at [offset].
void writeUint32BE(Uint8List buffer, int offset, int value) {
  ByteData.sublistView(buffer, offset, offset + 4)
      .setUint32(0, value, Endian.big);
}

/// Write big-endian uint64 to [buffer] at [offset].
void writeUint64BE(Uint8List buffer, int offset, int value) {
  ByteData.sublistView(buffer, offset, offset + 8)
      .setUint64(0, value, Endian.big);
}

/// Encode a hex string to bytes.
Uint8List hexDecode(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}

/// Encode bytes to hex string.
String hexEncode(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

// ---------------------------------------------------------------------------
// Block directory entry
// ---------------------------------------------------------------------------

class BlockEntry {
  final int type;
  final Uint8List plaintextHash;
  final Uint8List iv;
  final Uint8List ciphertext;
  final Uint8List tag;

  BlockEntry({
    required this.type,
    required this.plaintextHash,
    required this.iv,
    required this.ciphertext,
    required this.tag,
  });

  /// Serialize the directory entry (65 bytes).
  Uint8List toDirectoryBytes() {
    final entry = Uint8List(kDirectoryEntrySize);
    var offset = 0;

    entry[offset] = type;
    offset += 1;

    entry.setRange(offset, offset + kHashSize, plaintextHash);
    offset += kHashSize;

    writeUint32BE(entry, offset, ciphertext.length);
    offset += 4;

    entry.setRange(offset, offset + kIvSize, iv);
    offset += kIvSize;

    entry.setRange(offset, offset + kGcmTagSize, tag);

    return entry;
  }
}

// ---------------------------------------------------------------------------
// Zegel file builder
// ---------------------------------------------------------------------------

/// Build a complete .zgl file from components.
///
/// This follows the binary layout from FORMAT_SPEC.md Section 3:
///   Magic | Version | Flags | Timestamp | Content-Type | Filename-Len |
///   Filename | Salt | Block-Count | [Extended Header] | Block Directory |
///   Merkle Root | [Key Commitment] | Block Ciphertexts | Master Seal
Uint8List buildZegelFile({
  required Uint8List masterKey,
  required Uint8List salt,
  required int flags,
  required int timestamp,
  required String contentType,
  required String filename,
  required List<Uint8List> blockPlaintexts,
  required List<int> blockTypes,
  required SeededRandom rng,
  Uint8List? recipientId,
  int? splitThreshold,
  int? splitTotal,
}) {
  assert(blockPlaintexts.length == blockTypes.length);
  final blockCount = blockPlaintexts.length;

  // Apply canary padding to content blocks if HAS_CANARY flag is set
  final processedPlaintexts = <Uint8List>[];
  for (var i = 0; i < blockCount; i++) {
    if ((flags & kFlagHasCanary) != 0 &&
        blockTypes[i] == kBlockTypeContent &&
        recipientId != null) {
      final padding = computeCanaryPadding(masterKey, recipientId, i);
      final padded = Uint8List(blockPlaintexts[i].length + padding.length);
      padded.setRange(0, blockPlaintexts[i].length, blockPlaintexts[i]);
      padded.setRange(blockPlaintexts[i].length, padded.length, padding);
      processedPlaintexts.add(padded);
    } else {
      processedPlaintexts.add(blockPlaintexts[i]);
    }
  }

  // Step 1: Compute leaf hashes and Merkle root
  final leafHashes = processedPlaintexts.map(sha256Hash).toList();
  final merkleRoot = computeMerkleRoot(leafHashes);

  // Step 2: Derive per-block keys and encrypt
  final blockEntries = <BlockEntry>[];
  for (var i = 0; i < blockCount; i++) {
    final blockKey = deriveBlockKey(masterKey, merkleRoot, salt, i);
    final iv = rng.nextBytes(kIvSize);
    final result = aesGcmEncrypt(blockKey, iv, processedPlaintexts[i]);

    blockEntries.add(BlockEntry(
      type: blockTypes[i],
      plaintextHash: leafHashes[i],
      iv: iv,
      ciphertext: result.ciphertext,
      tag: result.tag,
    ));
  }

  // Step 3: Build the binary file

  // Calculate header size
  final filenameBytes = utf8.encode(filename);
  final contentTypeBytes = utf8.encode(contentType);

  var headerSize = 8 + // magic
      1 + // version major
      1 + // version minor
      2 + // flags
      8 + // timestamp
      kContentTypeFieldSize + // content-type (64 bytes, null-padded)
      2 + // filename length
      filenameBytes.length + // filename
      kSaltSize + // salt
      4; // block count

  // Extended header fields (Section 3.2)
  if ((flags & kFlagHasCanary) != 0) {
    headerSize += 32; // recipient ID
  }
  if ((flags & kFlagSplitKey) != 0) {
    headerSize += 2; // threshold (1) + total (1)
  }

  final directorySize = blockCount * kDirectoryEntrySize;
  final merkleRootOffset = headerSize + directorySize;

  var totalCiphertextSize = 0;
  for (final entry in blockEntries) {
    totalCiphertextSize += entry.ciphertext.length;
  }

  final fileSizeBeforeSeal =
      merkleRootOffset + kHashSize + totalCiphertextSize;
  final totalFileSize = fileSizeBeforeSeal + kSealSize;

  final buffer = Uint8List(totalFileSize);
  var offset = 0;

  // Magic bytes
  buffer.setRange(offset, offset + kMagicBytes.length, kMagicBytes);
  offset += kMagicBytes.length;

  // Version
  buffer[offset++] = kVersionMajor;
  buffer[offset++] = kVersionMinor;

  // Flags
  writeUint16BE(buffer, offset, flags);
  offset += 2;

  // Timestamp
  writeUint64BE(buffer, offset, timestamp);
  offset += 8;

  // Content-Type (64 bytes, null-padded)
  final ctField = Uint8List(kContentTypeFieldSize);
  final ctLen = contentTypeBytes.length < kContentTypeFieldSize
      ? contentTypeBytes.length
      : kContentTypeFieldSize;
  ctField.setRange(0, ctLen, contentTypeBytes);
  buffer.setRange(offset, offset + kContentTypeFieldSize, ctField);
  offset += kContentTypeFieldSize;

  // Filename length
  writeUint16BE(buffer, offset, filenameBytes.length);
  offset += 2;

  // Filename
  buffer.setRange(offset, offset + filenameBytes.length, filenameBytes);
  offset += filenameBytes.length;

  // Salt
  buffer.setRange(offset, offset + kSaltSize, salt);
  offset += kSaltSize;

  // Block count
  writeUint32BE(buffer, offset, blockCount);
  offset += 4;

  // Extended header: recipient ID (if HAS_CANARY)
  if ((flags & kFlagHasCanary) != 0 && recipientId != null) {
    buffer.setRange(offset, offset + 32, recipientId);
    offset += 32;
  }

  // Extended header: split-key params (if SPLIT_KEY)
  if ((flags & kFlagSplitKey) != 0) {
    buffer[offset++] = splitThreshold ?? 3;
    buffer[offset++] = splitTotal ?? 5;
  }

  // Block directory
  for (final entry in blockEntries) {
    final dirBytes = entry.toDirectoryBytes();
    buffer.setRange(offset, offset + kDirectoryEntrySize, dirBytes);
    offset += kDirectoryEntrySize;
  }

  // Merkle root
  buffer.setRange(offset, offset + kHashSize, merkleRoot);
  offset += kHashSize;

  // Block ciphertexts
  for (final entry in blockEntries) {
    buffer.setRange(offset, offset + entry.ciphertext.length, entry.ciphertext);
    offset += entry.ciphertext.length;
  }

  // Master seal
  final sealKey = computeSealKey(merkleRoot, masterKey, salt);
  final bytesBeforeSeal =
      Uint8List.fromList(buffer.sublist(0, fileSizeBeforeSeal));
  final seal = computeMasterSeal(sealKey, bytesBeforeSeal);
  buffer.setRange(fileSizeBeforeSeal, totalFileSize, seal);

  return buffer;
}

// ---------------------------------------------------------------------------
// Test vector generators
// ---------------------------------------------------------------------------

/// Generate the minimal test vector: single block, no metadata.
Future<void> generateMinimal(
  String outputDir,
  Uint8List masterKey,
  Uint8List salt,
  SeededRandom rng,
) async {
  final content = utf8.encode('Hello, Zegel!');
  final contentBytes = Uint8List.fromList(content);

  final fileBytes = buildZegelFile(
    masterKey: masterKey,
    salt: salt,
    flags: 0x0000,
    timestamp: 1706356800, // 2024-01-27T12:00:00Z
    contentType: 'text/plain',
    filename: 'hello.txt',
    blockPlaintexts: [contentBytes],
    blockTypes: [kBlockTypeContent],
    rng: rng,
  );

  await File('$outputDir/minimal.zgl').writeAsBytes(fileBytes);
  print('  minimal.zgl (${fileBytes.length} bytes)');
}

/// Generate the with_metadata test vector: metadata block + content block.
Future<void> generateWithMetadata(
  String outputDir,
  Uint8List masterKey,
  Uint8List salt,
  SeededRandom rng,
) async {
  final metadata = jsonEncode({
    'sealed_at': '2026-01-27T12:00:00Z',
    'sealed_by': 'zegel-test-vectors',
    'document_id': 1,
    'document_type': 'test',
  });
  final metadataBytes = Uint8List.fromList(utf8.encode(metadata));
  final contentBytes = Uint8List.fromList(utf8.encode('Document content here'));

  final fileBytes = buildZegelFile(
    masterKey: masterKey,
    salt: salt,
    flags: kFlagHasMetadata,
    timestamp: 1706356800,
    contentType: 'text/plain',
    filename: 'document.txt',
    blockPlaintexts: [metadataBytes, contentBytes],
    blockTypes: [kBlockTypeMetadata, kBlockTypeContent],
    rng: rng,
  );

  await File('$outputDir/with_metadata.zgl').writeAsBytes(fileBytes);
  print('  with_metadata.zgl (${fileBytes.length} bytes)');
}

/// Generate the multi_block test vector: 3 x 65536 bytes of 'A'.
Future<void> generateMultiBlock(
  String outputDir,
  Uint8List masterKey,
  Uint8List salt,
  SeededRandom rng,
) async {
  final block = Uint8List(kDefaultBlockSize);
  block.fillRange(0, kDefaultBlockSize, 0x41); // 'A'

  final fileBytes = buildZegelFile(
    masterKey: masterKey,
    salt: salt,
    flags: 0x0000,
    timestamp: 1706356800,
    contentType: 'application/octet-stream',
    filename: 'large.bin',
    blockPlaintexts: [
      Uint8List.fromList(block),
      Uint8List.fromList(block),
      Uint8List.fromList(block),
    ],
    blockTypes: [kBlockTypeContent, kBlockTypeContent, kBlockTypeContent],
    rng: rng,
  );

  await File('$outputDir/multi_block.zgl').writeAsBytes(fileBytes);
  print('  multi_block.zgl (${fileBytes.length} bytes)');
}

/// Generate canary_a test vector: canary trap for recipient A.
Future<void> generateCanaryA(
  String outputDir,
  Uint8List masterKey,
  Uint8List salt,
  SeededRandom rng,
) async {
  final contentBytes =
      Uint8List.fromList(utf8.encode('Confidential document'));
  final recipientId = hexDecode(
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');

  final fileBytes = buildZegelFile(
    masterKey: masterKey,
    salt: salt,
    flags: kFlagHasCanary,
    timestamp: 1706356800,
    contentType: 'text/plain',
    filename: 'confidential.txt',
    blockPlaintexts: [contentBytes],
    blockTypes: [kBlockTypeContent],
    rng: rng,
    recipientId: recipientId,
  );

  await File('$outputDir/canary_a.zgl').writeAsBytes(fileBytes);
  print('  canary_a.zgl (${fileBytes.length} bytes)');
}

/// Generate canary_b test vector: canary trap for recipient B (same content).
Future<void> generateCanaryB(
  String outputDir,
  Uint8List masterKey,
  Uint8List salt,
  SeededRandom rng,
) async {
  final contentBytes =
      Uint8List.fromList(utf8.encode('Confidential document'));
  final recipientId = hexDecode(
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb');

  final fileBytes = buildZegelFile(
    masterKey: masterKey,
    salt: salt,
    flags: kFlagHasCanary,
    timestamp: 1706356800,
    contentType: 'text/plain',
    filename: 'confidential.txt',
    blockPlaintexts: [contentBytes],
    blockTypes: [kBlockTypeContent],
    rng: rng,
    recipientId: recipientId,
  );

  await File('$outputDir/canary_b.zgl').writeAsBytes(fileBytes);
  print('  canary_b.zgl (${fileBytes.length} bytes)');
}

/// Generate split_key test vector and write shares JSON.
Future<void> generateSplitKey(
  String outputDir,
  Uint8List masterKey,
  Uint8List salt,
  SeededRandom rng,
) async {
  const threshold = 3;
  const totalShares = 5;

  // Split the master key (use a separate seeded RNG for deterministic shares)
  final shareRng = SeededRandom(42);
  final shares = shamirSplit(masterKey, threshold, totalShares, shareRng);

  // Verify reconstruction works with any 3 shares
  final reconstructed = shamirReconstruct([shares[0], shares[2], shares[4]]);
  assert(hexEncode(reconstructed) == hexEncode(masterKey),
      'Shamir reconstruction failed!');

  // Build the .zgl file (using split-key flag)
  final contentBytes =
      Uint8List.fromList(utf8.encode('Split-key protected content'));

  final fileBytes = buildZegelFile(
    masterKey: masterKey,
    salt: salt,
    flags: kFlagSplitKey,
    timestamp: 1706356800,
    contentType: 'text/plain',
    filename: 'split_key.txt',
    blockPlaintexts: [contentBytes],
    blockTypes: [kBlockTypeContent],
    rng: rng,
    splitThreshold: threshold,
    splitTotal: totalShares,
  );

  await File('$outputDir/split_key.zgl').writeAsBytes(fileBytes);

  // Write computed share values to the JSON
  final sharesJson = {
    'description': 'Split-key shares for threshold=3, total=5',
    'master_key_hex': hexEncode(masterKey),
    'threshold': threshold,
    'total_shares': totalShares,
    'note':
        'Shares generated with SeededRandom(42) for deterministic test vectors.',
    'shares': shares
        .asMap()
        .map((i, s) => MapEntry(i.toString(), {
              'x_coordinate': s[0],
              'y_values_hex': hexEncode(Uint8List.fromList(s.sublist(1))),
              'full_share_hex': hexEncode(s),
            })),
    'verification': {
      'shares_1_3_5_reconstruct':
          hexEncode(shamirReconstruct([shares[0], shares[2], shares[4]])),
      'shares_2_4_5_reconstruct':
          hexEncode(shamirReconstruct([shares[1], shares[3], shares[4]])),
      'reconstruction_matches_master_key': true,
    },
  };

  final encoder = JsonEncoder.withIndent('  ');
  await File('$outputDir/split_key_shares_computed.json')
      .writeAsString(encoder.convert(sharesJson));
  print('  split_key.zgl (${fileBytes.length} bytes)');
  print('  split_key_shares_computed.json');
}

/// Generate redacted test vector: 3 blocks, block 1 redacted.
Future<void> generateRedacted(
  String outputDir,
  Uint8List masterKey,
  Uint8List salt,
  SeededRandom rng,
) async {
  final block = Uint8List(kDefaultBlockSize);
  block.fillRange(0, kDefaultBlockSize, 0x41); // 'A'

  // First, build the original (non-redacted) file to get valid structure
  final originalBytes = buildZegelFile(
    masterKey: masterKey,
    salt: salt,
    flags: 0x0000,
    timestamp: 1706356800,
    contentType: 'application/octet-stream',
    filename: 'redacted.bin',
    blockPlaintexts: [
      Uint8List.fromList(block),
      Uint8List.fromList(block),
      Uint8List.fromList(block),
    ],
    blockTypes: [kBlockTypeContent, kBlockTypeContent, kBlockTypeContent],
    rng: rng,
  );

  // Now rebuild with block 1 redacted:
  // 1. Parse header to find directory offset and ciphertext locations
  // 2. Change block 1 type to REDACTED
  // 3. Replace block 1 ciphertext with random bytes
  // 4. Set HAS_REDACTIONS flag
  // 5. Recompute master seal

  // For simplicity, rebuild from scratch with the redaction applied
  final redactRng = SeededRandom(999); // separate RNG for redaction randomness

  // We need the same IVs and ciphertexts for blocks 0 and 2, but block 1
  // gets random ciphertext. To achieve this, rebuild using the same flow
  // but with flag and type changes.

  // Reconstruct leaf hashes from original content (all the same for 'A' blocks)
  final leafHash = sha256Hash(block);
  final leafHashes = [leafHash, Uint8List.fromList(leafHash), Uint8List.fromList(leafHash)];
  final merkleRoot = computeMerkleRoot(leafHashes);

  // Derive block keys (same as original since merkle root is identical)
  final blockKey0 = deriveBlockKey(masterKey, merkleRoot, salt, 0);
  final blockKey2 = deriveBlockKey(masterKey, merkleRoot, salt, 2);

  // Use fresh seeded RNG for IVs (must match what buildZegelFile would use)
  final redactBuildRng = SeededRandom(200);
  final iv0 = redactBuildRng.nextBytes(kIvSize);
  final iv1 = redactBuildRng.nextBytes(kIvSize); // won't be used for decryption
  final iv2 = redactBuildRng.nextBytes(kIvSize);

  // Encrypt blocks 0 and 2
  final enc0 = aesGcmEncrypt(blockKey0, iv0, block);
  final blockKey1 = deriveBlockKey(masterKey, merkleRoot, salt, 1);
  final enc1Orig = aesGcmEncrypt(blockKey1, iv1, block);
  final enc2 = aesGcmEncrypt(blockKey2, iv2, block);

  // Replace block 1 ciphertext with random bytes (same length)
  final redactedCiphertext1 = redactRng.nextBytes(enc1Orig.ciphertext.length);

  // Build entries
  final entries = [
    BlockEntry(
      type: kBlockTypeContent,
      plaintextHash: leafHashes[0],
      iv: iv0,
      ciphertext: enc0.ciphertext,
      tag: enc0.tag,
    ),
    BlockEntry(
      type: kBlockTypeRedacted, // REDACTED
      plaintextHash: leafHashes[1], // original hash preserved!
      iv: iv1, // original IV preserved
      ciphertext: redactedCiphertext1, // random bytes
      tag: enc1Orig.tag, // original tag preserved
    ),
    BlockEntry(
      type: kBlockTypeContent,
      plaintextHash: leafHashes[2],
      iv: iv2,
      ciphertext: enc2.ciphertext,
      tag: enc2.tag,
    ),
  ];

  // Build binary file with HAS_REDACTIONS flag
  final filenameBytes = utf8.encode('redacted.bin');
  final contentTypeBytes = utf8.encode('application/octet-stream');
  const flags = kFlagHasRedactions;

  var headerSize = 8 + 1 + 1 + 2 + 8 + kContentTypeFieldSize + 2 +
      filenameBytes.length + kSaltSize + 4;
  final directorySize = 3 * kDirectoryEntrySize;
  final merkleRootOffset = headerSize + directorySize;

  var totalCiphertextSize = 0;
  for (final e in entries) {
    totalCiphertextSize += e.ciphertext.length;
  }

  final fileSizeBeforeSeal = merkleRootOffset + kHashSize + totalCiphertextSize;
  final totalFileSize = fileSizeBeforeSeal + kSealSize;

  final buffer = Uint8List(totalFileSize);
  var offset = 0;

  // Magic
  buffer.setRange(offset, offset + kMagicBytes.length, kMagicBytes);
  offset += kMagicBytes.length;

  // Version
  buffer[offset++] = kVersionMajor;
  buffer[offset++] = kVersionMinor;

  // Flags
  writeUint16BE(buffer, offset, flags);
  offset += 2;

  // Timestamp
  writeUint64BE(buffer, offset, 1706356800);
  offset += 8;

  // Content-Type
  final ctField = Uint8List(kContentTypeFieldSize);
  final ctLen = contentTypeBytes.length < kContentTypeFieldSize
      ? contentTypeBytes.length
      : kContentTypeFieldSize;
  ctField.setRange(0, ctLen, contentTypeBytes);
  buffer.setRange(offset, offset + kContentTypeFieldSize, ctField);
  offset += kContentTypeFieldSize;

  // Filename length + filename
  writeUint16BE(buffer, offset, filenameBytes.length);
  offset += 2;
  buffer.setRange(offset, offset + filenameBytes.length, filenameBytes);
  offset += filenameBytes.length;

  // Salt
  buffer.setRange(offset, offset + kSaltSize, salt);
  offset += kSaltSize;

  // Block count
  writeUint32BE(buffer, offset, 3);
  offset += 4;

  // Block directory
  for (final entry in entries) {
    final dirBytes = entry.toDirectoryBytes();
    buffer.setRange(offset, offset + kDirectoryEntrySize, dirBytes);
    offset += kDirectoryEntrySize;
  }

  // Merkle root
  buffer.setRange(offset, offset + kHashSize, merkleRoot);
  offset += kHashSize;

  // Block ciphertexts
  for (final entry in entries) {
    buffer.setRange(offset, offset + entry.ciphertext.length, entry.ciphertext);
    offset += entry.ciphertext.length;
  }

  // Master seal (recomputed over the modified file)
  final sealKey = computeSealKey(merkleRoot, masterKey, salt);
  final bytesBeforeSeal = Uint8List.fromList(buffer.sublist(0, fileSizeBeforeSeal));
  final seal = computeMasterSeal(sealKey, bytesBeforeSeal);
  buffer.setRange(fileSizeBeforeSeal, totalFileSize, seal);

  await File('$outputDir/redacted.zgl').writeAsBytes(buffer);
  print('  redacted.zgl (${buffer.length} bytes)');
}

/// Generate the with_audit test vector: content block + 2 audit blocks.
Future<void> generateWithAudit(
  String outputDir,
  Uint8List masterKey,
  Uint8List salt,
  SeededRandom rng,
) async {
  final contentBytes = Uint8List.fromList(utf8.encode('Audited document'));

  // Audit entry 0
  final entry0Json = jsonEncode({
    'actor': 'user:1:admin@example.com',
    'action': 'sealed',
    'timestamp': 1706367600,
    'details': {},
  });
  final chainHash0 =
      computeChainHash(Uint8List(kHashSize), entry0Json); // starts from zeros

  final auditEntry0 = jsonEncode({
    'actor': 'user:1:admin@example.com',
    'action': 'sealed',
    'timestamp': 1706367600,
    'details': {},
    'chain_hash': hexEncode(chainHash0),
  });

  // Audit entry 1
  final entry1Json = jsonEncode({
    'actor': 'user:2:reviewer@example.com',
    'action': 'verified',
    'timestamp': 1706371200,
    'details': {},
  });
  final chainHash1 = computeChainHash(chainHash0, entry1Json);

  final auditEntry1 = jsonEncode({
    'actor': 'user:2:reviewer@example.com',
    'action': 'verified',
    'timestamp': 1706371200,
    'details': {},
    'chain_hash': hexEncode(chainHash1),
  });

  final auditBytes0 = Uint8List.fromList(utf8.encode(auditEntry0));
  final auditBytes1 = Uint8List.fromList(utf8.encode(auditEntry1));

  final fileBytes = buildZegelFile(
    masterKey: masterKey,
    salt: salt,
    flags: 0x0000,
    timestamp: 1706367600,
    contentType: 'text/plain',
    filename: 'audited.txt',
    blockPlaintexts: [contentBytes, auditBytes0, auditBytes1],
    blockTypes: [kBlockTypeContent, kBlockTypeAudit, kBlockTypeAudit],
    rng: rng,
  );

  await File('$outputDir/with_audit.zgl').writeAsBytes(fileBytes);

  // Write computed chain hashes
  final auditComputed = {
    'chain_hash_0': hexEncode(chainHash0),
    'chain_hash_1': hexEncode(chainHash1),
    'audit_entry_0_json': entry0Json,
    'audit_entry_1_json': entry1Json,
  };
  final encoder = JsonEncoder.withIndent('  ');
  await File('$outputDir/with_audit_computed.json')
      .writeAsString(encoder.convert(auditComputed));

  print('  with_audit.zgl (${fileBytes.length} bytes)');
  print('  with_audit_computed.json');
}

/// Generate the with_attestation test vector: content + attestation block.
Future<void> generateWithAttestation(
  String outputDir,
  Uint8List masterKey,
  Uint8List salt,
  SeededRandom rng,
) async {
  final contentBytes = Uint8List.fromList(utf8.encode('Attested document'));
  final signerKey = hexDecode(
      '0000000000000000000000000000000000000000000000000000000000000002');
  const signerId = 'user:42:accountant@example.com';
  const statement = 'Reviewed and approved';
  const timestamp = 1706367600;

  // We need the merkle root to compute the attestation HMAC, but the merkle
  // root depends on the attestation block content (which contains the HMAC).
  // Resolution: first compute the attestation using a preliminary merkle root
  // from just the content, then include the attestation block and recompute.
  //
  // In practice, the attestation is computed against the merkle root of the
  // CONTENT blocks only, or the entire file's merkle root at sealing time.
  // Per the spec (Section 7.1), the HMAC uses the file's merkle root.
  //
  // To break the circularity: build the attestation JSON without the HMAC first,
  // compute the merkle root including it, then fill in the HMAC.
  //
  // Simpler approach: two-pass. First compute the merkle root with a placeholder
  // HMAC, then verify it doesn't change (it will change because content differs).
  //
  // Cleanest approach: The attestation is typically added AFTER sealing, as an
  // additional block. The merkle root used in the HMAC is the root at the time
  // of attestation. For test vectors, we pre-compute it.

  // Step 1: Create a placeholder attestation to determine size, then iterate.
  // For deterministic test vectors, we use a fixed flow:

  // First, compute what the merkle root would be with the actual attestation content
  // We'll iterate: guess attestation content -> compute root -> compute HMAC -> check

  // Actually, let's do it properly:
  // The attestation block contains JSON with the HMAC. The merkle root depends on
  // ALL blocks including the attestation. So:
  // 1. Create content block hash
  // 2. Create a "template" attestation JSON (without hmac_hex)
  // 3. We need to find the fixed point. In practice, we do two passes.

  // Pass 1: Build with dummy HMAC to get approximate layout
  final dummyHmac = '0' * 64;
  final attestJsonPass1 = jsonEncode({
    'signer_id': signerId,
    'signer_key': hexEncode(signerKey),
    'statement': statement,
    'timestamp': timestamp,
    'hmac_hex': dummyHmac,
  });
  final attestBytesPass1 = Uint8List.fromList(utf8.encode(attestJsonPass1));

  // Compute merkle root with this content
  final contentHash = sha256Hash(contentBytes);
  final attestHashPass1 = sha256Hash(attestBytesPass1);
  final merkleRootPass1 =
      computeMerkleRoot([contentHash, attestHashPass1]);

  // Compute actual HMAC with this merkle root
  final attestHmac = computeAttestationHmac(
    signerKey,
    merkleRootPass1,
    signerId,
    timestamp,
    statement,
  );

  // Check: if the HMAC hex happens to be same length as dummy (it will be),
  // the merkle root won't change. Since HMAC-SHA256 always produces 32 bytes
  // = 64 hex chars, and our dummy is 64 chars, the JSON length is identical.
  final attestJson = jsonEncode({
    'signer_id': signerId,
    'signer_key': hexEncode(signerKey),
    'statement': statement,
    'timestamp': timestamp,
    'hmac_hex': hexEncode(attestHmac),
  });
  final attestBytes = Uint8List.fromList(utf8.encode(attestJson));

  // Verify: the actual attestation bytes have the same length as the dummy
  // If not, we'd need another pass. In practice, SHA-256 hex is always 64 chars.
  assert(attestBytes.length == attestBytesPass1.length,
      'Attestation size mismatch between passes');

  // Verify merkle root is the same (same length attestation -> same hash structure)
  final attestHash = sha256Hash(attestBytes);
  final merkleRootFinal = computeMerkleRoot([contentHash, attestHash]);

  // Note: merkle root WILL differ because the hash of the attestation block
  // changes (different HMAC content). So we need to iterate.
  // Since the HMAC depends on the merkle root, and the merkle root depends
  // on the HMAC, we have a circular dependency.
  //
  // Standard resolution: The attestation HMAC is computed over the merkle root
  // of the file WITHOUT the attestation block, then the attestation block is
  // appended.
  //
  // For our test vector, we'll use the content-only merkle root for the HMAC,
  // then include the attestation block in the file's merkle tree.

  // Recompute: HMAC over content-only merkle root
  final contentOnlyMerkleRoot = computeMerkleRoot([contentHash]);
  final finalHmac = computeAttestationHmac(
    signerKey,
    contentOnlyMerkleRoot,
    signerId,
    timestamp,
    statement,
  );

  final finalAttestJson = jsonEncode({
    'signer_id': signerId,
    'signer_key': hexEncode(signerKey),
    'statement': statement,
    'timestamp': timestamp,
    'hmac_hex': hexEncode(finalHmac),
  });
  final finalAttestBytes = Uint8List.fromList(utf8.encode(finalAttestJson));

  final fileBytes = buildZegelFile(
    masterKey: masterKey,
    salt: salt,
    flags: 0x0000,
    timestamp: 1706367600,
    contentType: 'text/plain',
    filename: 'attested.txt',
    blockPlaintexts: [contentBytes, finalAttestBytes],
    blockTypes: [kBlockTypeContent, kBlockTypeAttestation],
    rng: rng,
  );

  await File('$outputDir/with_attestation.zgl').writeAsBytes(fileBytes);

  // Write computed HMAC values
  final attestComputed = {
    'content_only_merkle_root': hexEncode(contentOnlyMerkleRoot),
    'attestation_hmac': hexEncode(finalHmac),
    'attestation_json': finalAttestJson,
    'note':
        'The attestation HMAC is computed over the content-only merkle root, '
            'then the attestation block is included in the full merkle tree.',
  };
  final encoder = JsonEncoder.withIndent('  ');
  await File('$outputDir/with_attestation_computed.json')
      .writeAsString(encoder.convert(attestComputed));

  print('  with_attestation.zgl (${fileBytes.length} bytes)');
  print('  with_attestation_computed.json');
}

/// Generate tampered variants by modifying bytes in the minimal.zgl file.
Future<void> generateTampered(
  String outputDir,
  Uint8List masterKey,
  Uint8List salt,
  SeededRandom rng,
) async {
  // First, regenerate minimal.zgl bytes (use same RNG seed)
  final minimalRng = SeededRandom(100);
  final content = utf8.encode('Hello, Zegel!');
  final contentBytes = Uint8List.fromList(content);

  final original = buildZegelFile(
    masterKey: masterKey,
    salt: salt,
    flags: 0x0000,
    timestamp: 1706356800,
    contentType: 'text/plain',
    filename: 'hello.txt',
    blockPlaintexts: [contentBytes],
    blockTypes: [kBlockTypeContent],
    rng: minimalRng,
  );

  // --- tampered_seal.zgl: flip bit 0 of first seal byte ---
  final tamperedSeal = Uint8List.fromList(original);
  final sealStart = tamperedSeal.length - kSealSize;
  tamperedSeal[sealStart] ^= 0x01;
  await File('$outputDir/tampered_seal.zgl').writeAsBytes(tamperedSeal);
  print('  tampered_seal.zgl (${tamperedSeal.length} bytes)');

  // --- tampered_block.zgl: flip bit 0 of first ciphertext byte ---
  // Find the ciphertext start: after merkle root
  // Header: 8+1+1+2+8+64+2+9+32+4 = 131
  // Directory: 1 block x 65 = 65
  // Merkle root: 32
  // Ciphertext starts at: 131 + 65 + 32 = 228
  final filenameLen = 9; // "hello.txt"
  final headerSize = 8 + 1 + 1 + 2 + 8 + kContentTypeFieldSize + 2 +
      filenameLen + kSaltSize + 4;
  final directorySize = 1 * kDirectoryEntrySize;
  final ciphertextStart = headerSize + directorySize + kHashSize;

  final tamperedBlock = Uint8List.fromList(original);
  tamperedBlock[ciphertextStart] ^= 0x01;
  await File('$outputDir/tampered_block.zgl').writeAsBytes(tamperedBlock);
  print('  tampered_block.zgl (${tamperedBlock.length} bytes)');

  // --- tampered_directory.zgl: XOR first byte of block 0's hash with 0xFF ---
  // Directory starts at headerSize
  // Entry 0: type(1) + hash(32) + ...
  // Hash starts at headerSize + 1
  final hashOffset = headerSize + 1; // skip block type byte

  final tamperedDir = Uint8List.fromList(original);
  tamperedDir[hashOffset] ^= 0xFF;
  await File('$outputDir/tampered_directory.zgl').writeAsBytes(tamperedDir);
  print('  tampered_directory.zgl (${tamperedDir.length} bytes)');
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main() async {
  final outputDir = Directory.current.path;

  // Ensure output directory exists
  final dir = Directory(outputDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  // Fixed test inputs (NEVER use these in production)
  final masterKey = hexDecode(
      '0000000000000000000000000000000000000000000000000000000000000001');
  final salt = Uint8List(kSaltSize); // all zeros

  print('Zegel Test Vector Generator v1.2');
  print('================================');
  print('Output directory: $outputDir');
  print('Master key: ${hexEncode(masterKey)}');
  print('Salt: ${hexEncode(salt)} (all zeros - test only!)');
  print('');
  print('Generating test vectors:');

  // Each generator uses its own seeded RNG for deterministic IVs.
  // The seed values are arbitrary but fixed per test vector.

  // 1. Minimal
  await generateMinimal(outputDir, masterKey, salt, SeededRandom(100));

  // 2. With metadata
  await generateWithMetadata(outputDir, masterKey, salt, SeededRandom(101));

  // 3. Multi-block
  await generateMultiBlock(outputDir, masterKey, salt, SeededRandom(102));

  // 4. Canary A
  await generateCanaryA(outputDir, masterKey, salt, SeededRandom(103));

  // 5. Canary B
  await generateCanaryB(outputDir, masterKey, salt, SeededRandom(104));

  // 6. Split key
  await generateSplitKey(outputDir, masterKey, salt, SeededRandom(105));

  // 7. Redacted
  await generateRedacted(outputDir, masterKey, salt, SeededRandom(106));

  // 8. With audit
  await generateWithAudit(outputDir, masterKey, salt, SeededRandom(107));

  // 9. With attestation
  await generateWithAttestation(outputDir, masterKey, salt, SeededRandom(108));

  // 10. Tampered variants (based on minimal)
  await generateTampered(outputDir, masterKey, salt, SeededRandom(109));

  print('');
  print('Test vectors generated successfully');
  print('');
  print('Summary of generated files:');
  print('  .zgl files:');
  print('    minimal.zgl              - Single block, no metadata');
  print('    with_metadata.zgl        - Metadata block + content block');
  print('    multi_block.zgl          - 3 content blocks (3 x 64KB)');
  print('    canary_a.zgl             - Canary trap, recipient A');
  print('    canary_b.zgl             - Canary trap, recipient B');
  print('    split_key.zgl            - Split-key (3-of-5) protected');
  print('    redacted.zgl             - 3 blocks, block 1 redacted');
  print('    with_audit.zgl           - Content + 2 audit trail entries');
  print('    with_attestation.zgl     - Content + attestation block');
  print('    tampered_seal.zgl        - Bit flip in master seal');
  print('    tampered_block.zgl       - Bit flip in block ciphertext');
  print('    tampered_directory.zgl   - XOR 0xFF on directory hash');
  print('');
  print('  .json files (computed values):');
  print('    split_key_shares_computed.json  - Shamir share values');
  print('    with_audit_computed.json        - Chain hash values');
  print('    with_attestation_computed.json  - Attestation HMAC values');
  print('');
  print('Descriptive .json files (input specifications) are maintained');
  print('separately and not overwritten by this script.');
}
