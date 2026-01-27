# Zegel Porting Guide

This document explains how to implement a Zegel reader and/or writer in any programming language. The format is designed to be language-agnostic: any language with the required cryptographic primitives can produce and consume `.zgl` files that are byte-for-byte interoperable.

For the authoritative binary specification, see [FORMAT_SPEC.md](../FORMAT_SPEC.md).

---

## Required Cryptographic Primitives

Your language or library must provide:

| Primitive | Purpose | Notes |
|-----------|---------|-------|
| **AES-256-GCM** | Per-block authenticated encryption | 32-byte key, 12-byte IV, 16-byte tag, no AAD |
| **SHA-256** | Block hashing, Merkle tree, key commitment | Raw 32-byte output |
| **HMAC-SHA256** | HKDF extract/expand, seal key, canary padding, attestation | Standard RFC 2104 |
| **HMAC-SHA512** | Master seal | 64-byte output |
| **CSPRNG** | Salt, IV, and random byte generation | Cryptographically secure random number generator |

### Optional Primitives

| Primitive | Purpose | Required For |
|-----------|---------|--------------|
| **Argon2id** | Password-based key derivation | `FLAG_PASSWORD_DERIVED` (SEC-1) |
| **zlib** | Block compression | `FLAG_COMPRESSED` (GEN-2) |

If you only need a reader/verifier and do not need to support password-derived keys or compressed files, you can skip these.

---

## Writer Implementation Guide

Follow these steps in order to create a valid `.zgl` file.

### Step 1: Prepare Inputs

Gather the following:
- Source file content (bytes)
- Master key (32 bytes from CSPRNG, or derived from password via Argon2id)
- Content-Type string (MIME type, e.g., `"application/pdf"`)
- Original filename (UTF-8, max 255 bytes)
- Optional: metadata (JSON object), feature flags and associated parameters

### Step 2: Generate Random Values

- Master salt: 32 bytes from CSPRNG
- One IV per block: 12 bytes each from CSPRNG

### Step 3: Split Content into Blocks

Split the source content into chunks of 65,536 bytes (64 KB). The last chunk may be smaller. If metadata is present, it becomes block index 0 (JSON-encoded, UTF-8).

### Step 4: Apply Pre-Encryption Transforms

For each content block, in order:
1. If `FLAG_COMPRESSED`: compress with zlib (level 6)
2. If `FLAG_HAS_CANARY`: compute and append canary padding (see [FORMAT_SPEC.md Section 6.1](../FORMAT_SPEC.md#61-sec-4-canary-trap--recipient-fingerprinting))

### Step 5: Hash Each Block

Compute `SHA-256(block_plaintext)` for each block (after compression and canary padding, before encryption). Store as the leaf hash in the block directory.

### Step 6: Build the Merkle Tree

1. Start with the list of leaf hashes from Step 5.
2. If there is a single leaf, the root equals that leaf hash (no self-hashing).
3. Otherwise, build the tree bottom-up:
   - If the current layer has an odd number of nodes, duplicate the last node.
   - Compute each parent: `SHA-256(left_child || right_child)` (concatenate raw 32-byte hashes).
   - Repeat until one node remains.

### Step 7: Derive Per-Block Keys (HKDF)

For each block at index `i`:

```
IKM  = master_key || merkle_root          (64 bytes)
salt = master_salt                         (32 bytes)
PRK  = HMAC-SHA256(salt, IKM)             (HKDF-Extract)
info = "zegel-block-key-v1:" + str(i)     (ASCII string)
key  = HMAC-SHA256(PRK, info || 0x01)     (HKDF-Expand, one iteration)
```

If `FLAG_HAS_EXPIRATION` is set, append `:exp=YYYY-MM-DD` to the info string.

### Step 8: Encrypt Each Block

For each block:
```
ciphertext, tag = AES-256-GCM-Encrypt(
    key       = block_key,
    iv        = block_iv (12 bytes, random),
    plaintext = block_data,
    aad       = empty,
    tag_len   = 16
)
```

### Step 9: Compute Key Commitment (Optional)

If `FLAG_HAS_KEY_COMMITMENT` is set:
```
commitment = SHA-256(key_0 || key_1 || ... || key_n)
```

### Step 10: Assemble the Binary File

Write the following sections in order:

1. **Magic bytes:** `ZEGEL\x00\x01\x00` (8 bytes)
2. **Version:** major (uint8), minor (uint8)
3. **Flags:** uint16 big-endian
4. **Timestamp:** uint64 big-endian (Unix epoch seconds)
5. **Content-Type:** UTF-8 string, null-padded to exactly 64 bytes
6. **Filename length:** uint16 big-endian
7. **Filename:** UTF-8 bytes
8. **Master salt:** 32 bytes
9. **Block count:** uint32 big-endian
10. **Extended header:** flag-dependent fields in the order specified by [FORMAT_SPEC.md Section 3.2](../FORMAT_SPEC.md#32-extended-header-v11)
11. **Block directory:** for each block, write type (1B) + hash (32B) + ciphertext length (4B) + IV (12B) + tag (16B)
12. **Merkle root:** 32 bytes
13. **Key commitment:** 32 bytes (if `FLAG_HAS_KEY_COMMITMENT`)
14. **Ciphertext blocks:** concatenated, in order
15. **Master seal:** 64 bytes (see Step 11)

### Step 11: Compute and Append the Master Seal

```
seal_key    = HMAC-SHA256(merkle_root, master_key || master_salt)
master_seal = HMAC-SHA512(seal_key, all_bytes_written_so_far)
```

Append the 64-byte seal as the final bytes of the file.

---

## Reader / Verifier Implementation Guide

### Step 1: Read and Validate Magic Bytes

Read the first 8 bytes. They must be exactly `ZEGEL\x00\x01\x00`. If not, reject the file as not a valid `.zgl` file.

### Step 2: Parse the Header

Read:
- Version major (uint8 at offset 8)
- Version minor (uint8 at offset 9)
- Flags (uint16 big-endian at offset 10)
- Created timestamp (uint64 big-endian at offset 12)
- Content-Type (64 bytes at offset 20, strip trailing null bytes)
- Filename length (uint16 big-endian at offset 84)
- Filename (variable bytes starting at offset 86)
- Master salt (32 bytes)
- Block count (uint32 big-endian)

### Step 3: Parse the Extended Header

Based on the flags, read the extended header fields in order. Only fields whose flags are set will be present. See [FORMAT_SPEC.md Section 3.2](../FORMAT_SPEC.md#32-extended-header-v11) for the exact order.

### Step 4: Parse the Block Directory

For each of the `block_count` blocks, read:
- Block type (uint8, 1 byte)
- Plaintext hash (32 bytes)
- Ciphertext length (uint32 big-endian, 4 bytes)
- IV/Nonce (12 bytes)
- GCM authentication tag (16 bytes)

Total: 65 bytes per block.

### Step 5: Read the Merkle Root and Key Commitment

- Read 32 bytes for the Merkle root.
- If `FLAG_HAS_KEY_COMMITMENT` is set, read 32 more bytes for the key commitment.

### Step 6: Obtain the Master Key

- If `FLAG_PASSWORD_DERIVED`: derive from password using Argon2id with stored parameters.
- If `FLAG_SPLIT_KEY`: reconstruct from M shares using Lagrange interpolation over GF(256).
- Otherwise: use the provided 32-byte master key directly.

### Step 7: Check Expiration

If `FLAG_HAS_EXPIRATION` is set, compare the current time against the expiration timestamp. If expired, refuse to proceed.

### Step 8: Verify the Master Seal

```
seal_key    = HMAC-SHA256(merkle_root, master_key || master_salt)
expected    = HMAC-SHA512(seal_key, file_bytes[0 .. file_length - 64))
actual      = file_bytes[file_length - 64 .. file_length)
```

Compare `expected` and `actual` using constant-time comparison. If they differ, the file has been tampered with. Stop.

### Step 9: Verify the Merkle Tree

Rebuild the Merkle tree from the block directory plaintext hashes (Step 4). Compare the computed root with the stored Merkle root. If they differ, the file has been tampered with. Stop.

### Step 10: Verify Key Commitment (If Present)

Derive all per-block keys. Compute `SHA-256(key_0 || key_1 || ... || key_n)`. Compare with the stored key commitment. If they differ, stop.

### Step 11: Decrypt and Verify Each Block

For each block:
1. If block type is REDACTED (`0x06`): skip decryption, record as redacted.
2. Derive the block key via HKDF (same as writer Step 7).
3. Decrypt: `plaintext = AES-256-GCM-Decrypt(key, iv, ciphertext, tag, aad=empty)`. If decryption fails (tag mismatch), the file has been tampered with. Stop.
4. If `FLAG_COMPRESSED` and block is CONTENT: decompress with zlib.
5. Compute `SHA-256(decrypted_plaintext)` and compare with the directory hash. If they differ, stop.
6. If `FLAG_HAS_CANARY` and block is CONTENT: strip the canary padding from the end.
7. Route by block type (CONTENT, METADATA, ATTESTATION, AUDIT, etc.).

### Step 12: Reassemble Output

Concatenate all CONTENT blocks in order to produce the original file content.

---

## Common Pitfalls

These are the most frequent sources of interoperability failures when porting Zegel to a new language. Each one has caused real bugs in implementations.

### 1. Big-Endian Byte Order Everywhere

All multi-byte integers in the `.zgl` format are big-endian (network byte order). This includes:
- Flags (uint16)
- Timestamp (uint64)
- Filename length (uint16)
- Block count (uint32)
- Ciphertext length (uint32)
- Argon2 parameters (uint32)
- Expiration timestamp (uint64)

Most modern CPUs are little-endian. You must explicitly convert. Do not assume your platform's native byte order is correct.

### 2. Content-Type Null-Padding to Exactly 64 Bytes

The Content-Type field is always exactly 64 bytes. If the MIME type string is shorter, pad with `\x00` bytes on the right. If the string is longer than 64 bytes, truncate. When reading, strip trailing `\x00` bytes to recover the original string.

### 3. HKDF Info String Format

The info string for per-block key derivation is:
```
"zegel-block-key-v1:" + decimal_string_of_block_index
```

Examples: `"zegel-block-key-v1:0"`, `"zegel-block-key-v1:1"`, `"zegel-block-key-v1:42"`.

This is an ASCII string, not a binary encoding. The block index is the decimal representation, not a fixed-width or zero-padded number. Do not use binary encoding of the index.

### 4. HKDF Extract: Salt Is the HMAC Key

In HKDF-Extract (RFC 5869), the computation is:
```
PRK = HMAC-SHA256(salt, IKM)
```

The salt is the HMAC **key** and the IKM is the HMAC **message**. Many developers accidentally reverse this. Verify against the test vectors.

### 5. Master Seal Key: Merkle Root Is the HMAC Key

The seal key derivation is:
```
seal_key = HMAC-SHA256(merkle_root, master_key || master_salt)
```

The Merkle root is the HMAC key. The concatenation of master key and salt is the message. This is another case where the parameter order matters and is easily reversed.

### 6. Merkle Tree Odd-Node Handling: Duplicate Last

When a tree layer has an odd number of nodes, duplicate the **last** node. Do not skip it, do not hash it with zeros, and do not leave it unpaired.

```
Layer: [A, B, C]
Becomes: [A, B, C, C]
Parents: [SHA-256(A || B), SHA-256(C || C)]
```

### 7. Single Leaf Equals Root

When there is only one block, the Merkle root equals that block's leaf hash directly. Do not hash the leaf with itself.

```
1 block:  root = leaf_hash
2 blocks: root = SHA-256(leaf_0 || leaf_1)
```

### 8. GCM Tag Is 16 Bytes, No AAD

AES-256-GCM must use a 16-byte (128-bit) authentication tag. No additional authenticated data (AAD) is used -- pass an empty byte array, not null. Some libraries distinguish between empty AAD and no AAD.

### 9. Metadata Block Is Always Index 0

When the `FLAG_HAS_METADATA` flag is set, the first block in the block directory (index 0) is always the encrypted JSON metadata block. Content blocks start at index 1.

### 10. JSON Metadata with Unescaped Unicode

Metadata JSON must be encoded with unescaped Unicode (equivalent to PHP's `JSON_UNESCAPED_UNICODE`). Non-ASCII characters appear literally in the UTF-8 string, not as `\uXXXX` escape sequences. Ensure your JSON encoder supports this behavior.

---

## Language-Specific Recommendations

### Python

**Libraries:**
- `cryptography` (pyca/cryptography): AES-GCM, HMAC, SHA-256, HKDF
- `hashlib`: SHA-256, SHA-512 (standard library)
- `hmac`: HMAC (standard library)
- `argon2-cffi`: Argon2id
- `secrets` or `os.urandom()`: CSPRNG

**Notes:**
- Use `struct.pack('>H', ...)` for big-endian uint16, `'>I'` for uint32, `'>Q'` for uint64.
- Python's `json.dumps(obj, ensure_ascii=False)` produces unescaped Unicode.
- Use `hmac.compare_digest()` for constant-time comparison.
- Beware: `cryptography` library's AES-GCM API may concatenate tag with ciphertext. Separate them explicitly.

### Go

**Libraries:**
- `crypto/aes`, `crypto/cipher` (standard library): AES-GCM
- `crypto/sha256`, `crypto/sha512` (standard library): SHA-256, SHA-512
- `crypto/hmac` (standard library): HMAC
- `golang.org/x/crypto/hkdf`: HKDF
- `golang.org/x/crypto/argon2`: Argon2id
- `crypto/rand`: CSPRNG

**Notes:**
- Use `binary.BigEndian.PutUint16()` and friends for byte order.
- Go's `crypto/cipher` GCM `Seal()` appends the tag to the ciphertext. Use `Overhead()` to know the tag length and separate them.
- Use `crypto/subtle.ConstantTimeCompare()` for constant-time comparison.
- Use `json.Marshal()` for metadata; Go's default encoder handles Unicode correctly.

### Rust

**Libraries:**
- `aes-gcm` crate: AES-256-GCM
- `sha2` crate: SHA-256
- `hmac` crate: HMAC
- `hkdf` crate: HKDF
- `argon2` crate: Argon2id
- `rand` crate with `OsRng`: CSPRNG
- `flate2` crate: zlib

**Notes:**
- Use `u16::to_be_bytes()`, `u32::to_be_bytes()`, `u64::to_be_bytes()` for big-endian encoding.
- Use the `subtle` crate for constant-time comparison (`ConstantTimeEq` trait).
- Ensure `serde_json` is configured to not escape Unicode (default behavior is correct).
- Rust's ownership model helps with zeroing secrets: use `zeroize` crate for sensitive data.

### Java

**Libraries:**
- `javax.crypto.Cipher` with `AES/GCM/NoPadding`: AES-GCM
- `java.security.MessageDigest`: SHA-256
- `javax.crypto.Mac`: HMAC-SHA256, HMAC-SHA512
- `javax.crypto.spec.GCMParameterSpec`: GCM parameters
- `java.security.SecureRandom`: CSPRNG
- Bouncy Castle or de.mkammerer's argon2-jvm: Argon2id

**Notes:**
- Use `java.nio.ByteBuffer` with `ByteOrder.BIG_ENDIAN` for byte order. Java is big-endian by default for `DataOutputStream`.
- For GCM: `GCMParameterSpec(128, iv)` for 16-byte (128-bit) tag.
- Java's GCM implementation appends the tag to the ciphertext. Split the last 16 bytes as the tag.
- Use `MessageDigest.isEqual()` for constant-time comparison.
- For JSON: use Jackson with `ObjectMapper` -- default Unicode handling is correct.

### C# (.NET)

**Libraries:**
- `System.Security.Cryptography.AesGcm`: AES-GCM (.NET 3.0+)
- `System.Security.Cryptography.SHA256`: SHA-256
- `System.Security.Cryptography.HMACSHA256`: HMAC-SHA256
- `System.Security.Cryptography.HMACSHA512`: HMAC-SHA512
- `System.Security.Cryptography.RandomNumberGenerator`: CSPRNG
- Konscious.Security.Cryptography or Isopoh.Cryptography.Argon2: Argon2id

**Notes:**
- Use `BinaryPrimitives.WriteUInt16BigEndian()` and related methods for byte order.
- .NET's `AesGcm` class takes tag as a separate parameter -- matches the Zegel format directly.
- Use `CryptographicOperations.FixedTimeEquals()` for constant-time comparison.
- `System.Text.Json` with `JsonSerializerOptions { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping }` for unescaped Unicode.

### JavaScript (Node.js / Browser)

**Libraries (Node.js):**
- `crypto` module (built-in): AES-GCM, SHA-256, HMAC, CSPRNG
- `argon2` npm package: Argon2id
- `pako` npm package: zlib

**Libraries (Browser):**
- `SubtleCrypto` (Web Crypto API): AES-GCM, SHA-256, HMAC
- `crypto.getRandomValues()`: CSPRNG
- `argon2-browser` or `hash-wasm`: Argon2id

**Notes:**
- Use `DataView` with `setUint16(offset, value, false)` for big-endian (the `false` parameter means big-endian).
- Node.js `crypto.createCipheriv('aes-256-gcm', key, iv)` requires calling `cipher.getAuthTag()` separately.
- Use `crypto.timingSafeEqual()` (Node.js) for constant-time comparison. No built-in equivalent in browsers -- implement manually or use a library.
- `JSON.stringify()` does not escape non-ASCII Unicode by default -- this is the correct behavior.
- Browser `SubtleCrypto` is async. Plan your API accordingly.

---

## Test Vector Verification Procedure

After implementing a reader, verify against the provided test vectors in the `test_vectors/` directory:

1. **Load each `.zgl` test file** and its corresponding `.json` file containing expected values.

2. **Parse the header** and compare:
   - Magic bytes, version, flags, timestamp, content-type, filename, salt, block count

3. **Parse the block directory** and compare:
   - Block types, plaintext hashes (hex), ciphertext lengths, IVs (hex), tags (hex)

4. **Verify the Merkle root** matches the expected value.

5. **Derive per-block keys** using the provided master key and verify they match expected key values.

6. **Decrypt each block** and verify plaintext matches expected content.

7. **Verify the master seal** matches the expected value.

8. **Test tamper detection** using the `tampered_*.zgl` files -- these must fail verification.

If all test vectors pass, your implementation is interoperable with the reference implementation. If any vector fails, compare intermediate values (PRK, block keys, leaf hashes, Merkle layers) to isolate the divergence.

---

## Recommended Library Choices Summary

| Language   | AES-GCM                        | SHA-256            | HMAC                 | Argon2id              | CSPRNG               |
|------------|--------------------------------|--------------------|----------------------|-----------------------|----------------------|
| Python     | `cryptography`                 | `hashlib`          | `hmac`               | `argon2-cffi`         | `secrets`            |
| Go         | `crypto/aes` + `crypto/cipher` | `crypto/sha256`    | `crypto/hmac`        | `x/crypto/argon2`     | `crypto/rand`        |
| Rust       | `aes-gcm`                      | `sha2`             | `hmac`               | `argon2`              | `rand` (`OsRng`)     |
| Java       | `javax.crypto.Cipher`          | `MessageDigest`    | `javax.crypto.Mac`   | `argon2-jvm`          | `SecureRandom`       |
| C#         | `AesGcm`                       | `SHA256`           | `HMACSHA256/512`     | `Konscious.Argon2`    | `RandomNumberGenerator` |
| JavaScript | `crypto` / `SubtleCrypto`      | `crypto` / `SubtleCrypto` | `crypto` / `SubtleCrypto` | `argon2` / `hash-wasm` | `crypto.randomBytes` |
| Dart       | `pointycastle` / `cryptography`| `crypto`           | `crypto`             | FFI bindings          | `dart:math` (secure) |

---

## Further Reading

- [FORMAT_SPEC.md](../FORMAT_SPEC.md) -- Complete binary format specification
- [Architecture Overview](architecture.md) -- Diagrams and data flow
- [Security Audit](security_audit.md) -- Security considerations
- [FAQ](faq.md) -- Common questions
