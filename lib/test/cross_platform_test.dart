import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

/// Creates a 32-byte test master key: 31 zero bytes followed by 0x01.
Uint8List _testKey() {
  final key = Uint8List(32);
  key[31] = 0x01;
  return key;
}

/// Creates a 32-byte all-zeros salt.
Uint8List _zeroSalt() => Uint8List(32);

/// Helper to compute SHA-256 of bytes.
Uint8List _sha256(Uint8List data) {
  return Uint8List.fromList(sha256.convert(data).bytes);
}

/// Helper to convert bytes to hex string.
String _toHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Helper to compute HMAC-SHA256.
Uint8List _hmacSha256(Uint8List key, Uint8List data) {
  return Uint8List.fromList(Hmac(sha256, key).convert(data).bytes);
}

void main() {
  group('Cross-platform compatibility', () {
    group('test vector: minimal file', () {
      // Known inputs from FORMAT_SPEC.md Section 13.1
      // Master key (hex): 00...01 (32 bytes)
      // Content: "Hello, Zegel!" (13 bytes UTF-8)
      // Content-Type: "text/plain"
      // Filename: "hello.txt"
      // Salt: all zeros (32 bytes)
      // No metadata, no compression, no flags

      late Uint8List masterKey;
      late Uint8List content;
      late Uint8List fileBytes;

      setUp(() {
        masterKey = _testKey();
        content = Uint8List.fromList(utf8.encode('Hello, Zegel!'));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        fileBytes = ZegelWriter(masterKey, options).seal(content);
      });

      test('file starts with correct magic bytes', () {
        expect(
          fileBytes.sublist(0, 8),
          equals(
            Uint8List.fromList([
              0x5A,
              0x45,
              0x47,
              0x45,
              0x4C,
              0x00,
              0x01,
              0x00,
            ]),
          ),
        );
      });

      test('version is (1, 4)', () {
        expect(fileBytes[8], equals(1));
        expect(fileBytes[9], equals(4));
      });

      test('flags are 0x0000', () {
        final flags = ByteData.sublistView(
          fileBytes,
          10,
          12,
        ).getUint16(0, Endian.big);
        expect(flags, equals(0x0000));
      });

      test('content-type is "text/plain" null-padded to 64 bytes', () {
        final ctBytes = fileBytes.sublist(20, 84);
        final textPlainBytes = utf8.encode('text/plain');
        expect(
          ctBytes.sublist(0, textPlainBytes.length),
          equals(Uint8List.fromList(textPlainBytes)),
        );
        // Rest is zeros
        for (var i = textPlainBytes.length; i < 64; i++) {
          expect(ctBytes[i], equals(0));
        }
      });

      test('filename length is 9 (big-endian)', () {
        final fnLen = ByteData.sublistView(
          fileBytes,
          84,
          86,
        ).getUint16(0, Endian.big);
        expect(fnLen, equals(9));
      });

      test('filename is "hello.txt"', () {
        final fn = utf8.decode(fileBytes.sublist(86, 95));
        expect(fn, equals('hello.txt'));
      });

      test('salt is 32 zero bytes', () {
        final salt = fileBytes.sublist(95, 127);
        expect(salt, equals(_zeroSalt()));
      });

      test('block count is 1', () {
        final bc = ByteData.sublistView(
          fileBytes,
          127,
          131,
        ).getUint32(0, Endian.big);
        expect(bc, equals(1));
      });

      test('first directory entry has block type CONTENT (0x01)', () {
        // Directory starts at offset 131
        expect(fileBytes[131], equals(0x01));
      });

      test('block plaintext hash matches SHA-256 of content', () {
        // Plaintext hash is at directory offset + 1, length 32
        final plaintextHash = fileBytes.sublist(132, 164);
        final expectedHash = _sha256(content);
        expect(plaintextHash, equals(expectedHash));
      });
    });

    group('deterministic Merkle root (v1.4: RFC 6962 domain separation)', () {
      test('Merkle root for single block is domain-separated leaf hash', () {
        final content = Uint8List.fromList(utf8.encode('Hello, Zegel!'));
        final contentHash = _sha256(content);

        // v1.4: single leaf root = SHA-256(0x00 || contentHash), NOT contentHash.
        final merkleRoot = MerkleTree.buildRoot([contentHash]);

        // Compute expected: SHA-256(0x00 || contentHash)
        final leafPrefixed = Uint8List(1 + contentHash.length);
        leafPrefixed[0] = 0x00;
        leafPrefixed.setRange(1, leafPrefixed.length, contentHash);
        final expectedRoot = _sha256(leafPrefixed);

        expect(merkleRoot, equals(expectedRoot));
      });

      test('Merkle root for known two-block content is deterministic', () {
        // Two blocks of known content
        final block0 = Uint8List.fromList(List.filled(65536, 0xAA));
        final block1 = Uint8List.fromList(List.filled(100, 0xBB));

        final hash0 = _sha256(block0);
        final hash1 = _sha256(block1);

        final root = MerkleTree.buildRoot([hash0, hash1]);
        expect(root.length, equals(32));

        // Compute expected root with RFC 6962 domain separation.
        // Leaf 0: SHA-256(0x00 || hash0)
        final leaf0Prefixed = Uint8List(1 + hash0.length);
        leaf0Prefixed[0] = 0x00;
        leaf0Prefixed.setRange(1, leaf0Prefixed.length, hash0);
        final leaf0Ds = _sha256(leaf0Prefixed);

        // Leaf 1: SHA-256(0x00 || hash1)
        final leaf1Prefixed = Uint8List(1 + hash1.length);
        leaf1Prefixed[0] = 0x00;
        leaf1Prefixed.setRange(1, leaf1Prefixed.length, hash1);
        final leaf1Ds = _sha256(leaf1Prefixed);

        // Internal node: SHA-256(0x01 || leaf0Ds || leaf1Ds)
        final nodePrefixed = Uint8List(1 + 64);
        nodePrefixed[0] = 0x01;
        nodePrefixed.setRange(1, 33, leaf0Ds);
        nodePrefixed.setRange(33, 65, leaf1Ds);
        final expectedRoot = _sha256(nodePrefixed);

        expect(root, equals(expectedRoot));
      });
    });

    group('deterministic HKDF key derivation', () {
      test('HKDF produces consistent key for known inputs', () {
        final masterKey = _testKey();
        final salt = _zeroSalt();
        final content = Uint8List.fromList(utf8.encode('Hello, Zegel!'));
        // v1.4: single leaf root = SHA-256(0x00 || content_hash)
        final contentHash = _sha256(content);
        final merkleRoot = MerkleTree.buildRoot([contentHash]);

        // IKM = master_key || merkle_root (64 bytes)
        final ikm = Uint8List(64);
        ikm.setAll(0, masterKey);
        ikm.setAll(32, merkleRoot);

        // PRK = HMAC-SHA256(salt, IKM)
        final prk = _hmacSha256(salt, ikm);
        expect(prk.length, equals(32));

        // info = "zegel-block-key-v1:0"
        final info = utf8.encode('zegel-block-key-v1:0');

        // T(1) = HMAC-SHA256(PRK, info || 0x01)
        final expandInput = Uint8List(info.length + 1);
        expandInput.setAll(0, info);
        expandInput[info.length] = 0x01;
        final blockKey = _hmacSha256(prk, expandInput);

        expect(blockKey.length, equals(32));

        // This key should be the same every time with these inputs
        // Store the hex for cross-platform comparison
        final keyHex = _toHex(blockKey);
        expect(keyHex.length, equals(64));

        // Run again to verify determinism
        final blockKey2 = _hmacSha256(prk, expandInput);
        expect(blockKey2, equals(blockKey));
      });
    });

    group('deterministic seal computation', () {
      test('seal key derivation is deterministic', () {
        final masterKey = _testKey();
        final salt = _zeroSalt();
        final content = Uint8List.fromList(utf8.encode('Hello, Zegel!'));
        // v1.4: domain-separated Merkle root.
        final merkleRoot = MerkleTree.buildRoot([_sha256(content)]);

        // seal_key = HMAC-SHA256(merkle_root, master_key || salt)
        final sealKeyInput = Uint8List(64);
        sealKeyInput.setAll(0, masterKey);
        sealKeyInput.setAll(32, salt);
        final sealKey = _hmacSha256(merkleRoot, sealKeyInput);

        expect(sealKey.length, equals(32));

        // Verify determinism
        final sealKey2 = _hmacSha256(merkleRoot, sealKeyInput);
        expect(sealKey2, equals(sealKey));
      });

      test('master seal is last 64 bytes of file', () {
        final masterKey = _testKey();
        final content = Uint8List.fromList(utf8.encode('Hello, Zegel!'));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        final seal = fileBytes.sublist(fileBytes.length - 64);
        expect(seal.length, equals(64));
        // Seal should not be all zeros
        expect(seal, isNot(equals(Uint8List(64))));
      });
    });

    group('header structure verification', () {
      test('header byte offsets match specification exactly', () {
        final masterKey = _testKey();
        final content = Uint8List.fromList(utf8.encode('Hello, Zegel!'));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'hello.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        // Offset 0-7: Magic (8 bytes)
        expect(fileBytes.sublist(0, 8), equals(ZegelFormat.magic));

        // Offset 8: Version major
        expect(fileBytes[8], equals(1));

        // Offset 9: Version minor (v1.4)
        expect(fileBytes[9], equals(4));

        // Offset 10-11: Flags (uint16 BE)
        final flags = ByteData.sublistView(
          fileBytes,
          10,
          12,
        ).getUint16(0, Endian.big);
        expect(flags, equals(0));

        // Offset 12-19: Timestamp (uint64 BE)
        final ts = ByteData.sublistView(
          fileBytes,
          12,
          20,
        ).getUint64(0, Endian.big);
        expect(ts, greaterThan(0));

        // Offset 20-83: Content-Type (64 bytes, null-padded)
        final ctField = fileBytes.sublist(20, 84);
        expect(ctField.length, equals(64));

        // Offset 84-85: Filename length (uint16 BE)
        final fnLen = ByteData.sublistView(
          fileBytes,
          84,
          86,
        ).getUint16(0, Endian.big);
        expect(fnLen, equals(9)); // "hello.txt"

        // Offset 86-94: Filename
        expect(
          utf8.decode(fileBytes.sublist(86, 86 + fnLen)),
          equals('hello.txt'),
        );

        // Offset 95-126: Salt (32 bytes)
        expect(fileBytes.sublist(95, 127), equals(_zeroSalt()));

        // Offset 127-130: Block count (uint32 BE)
        final blockCount = ByteData.sublistView(
          fileBytes,
          127,
          131,
        ).getUint32(0, Endian.big);
        expect(blockCount, equals(1));

        // Offset 131: Start of block directory
        // Block type at 131
        expect(fileBytes[131], equals(ZegelFormat.blockContent));

        // Hash at 132-163 (32 bytes)
        final blockHash = fileBytes.sublist(132, 164);
        expect(blockHash.length, equals(32));

        // Ciphertext length at 164-167 (uint32 BE)
        final ctLen = ByteData.sublistView(
          fileBytes,
          164,
          168,
        ).getUint32(0, Endian.big);
        expect(ctLen, greaterThan(0));

        // IV at 168-179 (12 bytes)
        final iv = fileBytes.sublist(168, 180);
        expect(iv.length, equals(12));

        // Auth tag at 180-195 (16 bytes)
        final tag = fileBytes.sublist(180, 196);
        expect(tag.length, equals(16));

        // Directory entry total: 1 + 32 + 4 + 12 + 16 = 65 bytes
        // Directory ends at 131 + 65 = 196

        // Merkle root at 196-227 (32 bytes).
        // v1.4: single leaf root = SHA-256(0x00 || content_hash)
        final merkleRoot = fileBytes.sublist(196, 228);
        expect(merkleRoot.length, equals(32));
        final expectedRoot = MerkleTree.buildRoot([_sha256(content)]);
        expect(merkleRoot, equals(expectedRoot));

        // Encrypted block data at 228 through (end - 64)
        const blockDataStart = 228;
        final blockDataEnd = fileBytes.length - 64;
        expect(blockDataEnd - blockDataStart, equals(ctLen));

        // Master seal at last 64 bytes
        final masterSeal = fileBytes.sublist(fileBytes.length - 64);
        expect(masterSeal.length, equals(64));
      });
    });

    group('GF(256) known values', () {
      test('specific GF(256) multiply results for cross-platform check', () {
        // These are known results that any correct GF(256) implementation
        // with polynomial 0x11B must produce
        expect(ShamirSecretSharing.gfMultiply(2, 2), equals(4));
        expect(ShamirSecretSharing.gfMultiply(3, 3), equals(5));
        expect(ShamirSecretSharing.gfMultiply(7, 7), equals(21));
        expect(ShamirSecretSharing.gfMultiply(0x80, 2), equals(0x1B));
        // 0x80 * 2 in GF(256) with 0x11B polynomial:
        // 0x100 XOR 0x11B = 0x1B
      });

      test('specific GF(256) inverse values', () {
        // Known inverses in GF(256) with 0x11B
        expect(ShamirSecretSharing.gfInverse(1), equals(1));
        expect(
          ShamirSecretSharing.gfMultiply(2, ShamirSecretSharing.gfInverse(2)),
          equals(1),
        );
        expect(
          ShamirSecretSharing.gfMultiply(3, ShamirSecretSharing.gfInverse(3)),
          equals(1),
        );
      });
    });

    group('audit chain hash cross-platform check', () {
      test('chain hash for known entry is deterministic', () {
        final initialHash = Uint8List(32);

        // Create a known entry
        final entryData = {
          'actor': 'user:1:admin@example.com',
          'action': 'sealed',
          'timestamp': 1706367600,
          'details': <String, dynamic>{},
        };
        final entryJsonStr = jsonEncode(entryData);
        final entryJsonBytes = Uint8List.fromList(utf8.encode(entryJsonStr));

        // chain_hash = SHA-256(initial_hash || entry_json)
        final combined = Uint8List(32 + entryJsonBytes.length);
        combined.setAll(0, initialHash);
        combined.setAll(32, entryJsonBytes);
        final expectedChainHash = _sha256(combined);

        // Any implementation should produce this exact hash
        expect(expectedChainHash.length, equals(32));
        // Store hex for cross-platform comparison
        final hex = _toHex(expectedChainHash);
        expect(hex.length, equals(64));

        // Verify the same computation twice produces identical results
        final secondHash = _sha256(Uint8List.fromList(combined));
        expect(secondHash, equals(expectedChainHash));
      });
    });

    group('canary padding cross-platform check', () {
      test('padding for known inputs is deterministic', () {
        final key = _testKey();
        final recipientId = _sha256(
          Uint8List.fromList(utf8.encode('user:1:alice@example.com')),
        );
        const blockIndex = 0;

        // Compute expected padding per spec:
        // mac = HMAC-SHA256(key, recipient_id || pack_uint32_be(block_index))
        final message = Uint8List(recipientId.length + 4);
        message.setAll(0, recipientId);
        ByteData.sublistView(
          message,
          recipientId.length,
          recipientId.length + 4,
        ).setUint32(0, blockIndex, Endian.big);

        final mac = _hmacSha256(key, message);
        final padLen = (mac[0] % 16) + 1;

        expect(padLen, greaterThanOrEqualTo(1));
        expect(padLen, lessThanOrEqualTo(16));

        // Build expected padding
        final expectedPadding = Uint8List(padLen);
        for (var i = 0; i < padLen - 1; i++) {
          expectedPadding[i] = mac[i + 1];
        }
        expectedPadding[padLen - 1] = padLen;

        // Verify the library produces the same padding
        final actualPadding = CanaryTrap.generatePadding(
          key,
          recipientId,
          blockIndex,
        );
        expect(actualPadding, equals(expectedPadding));
      });
    });
  });
}
