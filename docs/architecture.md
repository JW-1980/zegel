# Zegel Architecture Overview

This document describes the internal architecture of the Zegel tamper-proof container format (v1.2). For the complete binary specification, see [FORMAT_SPEC.md](../FORMAT_SPEC.md).

---

## High-Level Pipeline

The following diagram shows how a file is transformed into a sealed `.zgl` container:

```
                         Zegel Sealing Pipeline
                         ======================

 +----------------+     +------------------+     +------------------+
 |                |     |                  |     |                  |
 |  Source File   +---->+  Block Splitting +---->+  SHA-256 Hashing |
 |  (any format)  |     |  (64 KB chunks)  |     |  (per block)     |
 |                |     |                  |     |                  |
 +----------------+     +------------------+     +--------+---------+
                                                          |
                                           leaf hashes    |
                                                          v
 +----------------+     +------------------+     +------------------+
 |                |     |                  |     |                  |
 |  AES-256-GCM   |<----+ HKDF Key Deriv. |<----+   Merkle Tree    |
 |  Encryption    |     |  (per block)     |     |   Construction   |
 |  (per block)   |     |                  |     |                  |
 +--------+-------+     +--------+---------+     +------------------+
          |                      ^
          |                      |
          |              master_key + merkle_root
          v
 +------------------+
 |                  |
 |  Binary Container|
 |  (.zgl file)     |
 |                  |
 +------------------+
```

### Pipeline Steps

1. **Block Splitting** -- The source file is divided into fixed-size blocks (default 64 KB). The last block may be smaller. If metadata is present, it occupies block index 0 as a JSON-encoded block.

2. **SHA-256 Hashing** -- Each block's plaintext content is hashed with SHA-256, producing a 32-byte leaf hash. These hashes are stored in the block directory and form the leaves of the Merkle tree.

3. **Merkle Tree Construction** -- Leaf hashes are assembled into a binary SHA-256 Merkle tree. If a layer has an odd number of nodes, the last node is duplicated. The root hash uniquely represents every block in the file. See [FORMAT_SPEC.md Section 5.6](../FORMAT_SPEC.md#56-merkle-tree-construction).

4. **HKDF Key Derivation** -- Each block receives a unique encryption key derived via HKDF (RFC 5869) from the master key, Merkle root, master salt, and block index. See the Key Derivation Flow section below.

5. **AES-256-GCM Encryption** -- Each block is encrypted with its derived key using AES-256-GCM authenticated encryption. A random 12-byte IV is generated per block. No additional authenticated data (AAD) is used. The 16-byte GCM authentication tag is stored in the block directory.

6. **Binary Container Assembly** -- All components are assembled into the `.zgl` binary format: header, extended header, block directory, Merkle root, key commitment (optional), ciphertext blocks, and master seal.

---

## Why Tampering Destroys Content

This is the core security property of Zegel. The chain of dependencies makes any modification self-destructive:

```
  Tamper with 1 byte in any block
            |
            v
  Leaf hash changes (SHA-256)
            |
            v
  Merkle root changes
            |
            v
  ALL per-block keys change (HKDF depends on root)
            |
            v
  AES-256-GCM authentication tags no longer match
            |
            v
  Decryption is REJECTED for every block
            |
            v
  Content is physically unreadable
```

This is not a "detect and warn" system. The encryption keys are mathematically derived from the file's integrity. If the integrity changes, the keys change, and AES-GCM's built-in authentication rejects decryption. No policy enforcement or viewer cooperation is needed -- the math prevents it.

**Contrast with traditional hashing:** A traditional approach computes a hash and stores it separately. A viewer can check the hash and display a warning, but the content remains readable. In Zegel, the hash (Merkle root) is woven into the key derivation, so the content itself becomes inaccessible.

---

## Binary Layout

The `.zgl` file has the following structure:

```
 Offset    Size      Section
 --------  --------  ------------------------------------------
 0         8         Magic Bytes: ZEGEL\x00\x01\x00
 8         1         Version Major (uint8)
 9         1         Version Minor (uint8)
 10        2         Flags (uint16, big-endian)
 12        8         Created Timestamp (uint64 BE, Unix epoch)
 20        64        Content-Type (UTF-8, null-padded)
 84        2         Filename Length (uint16 BE)
 86        var       Filename (UTF-8)
 86+N      32        Master Salt (32 random bytes)
 118+N     4         Block Count (uint32 BE)
           --------  ------------------------------------------
                     EXTENDED HEADER (flag-dependent, v1.1+)
                       Argon2 params     (if PASSWORD_DERIVED)
                       Expiration        (if HAS_EXPIRATION)
                       Recipient ID      (if HAS_CANARY)
                       Split-key M, N    (if SPLIT_KEY)
                       Version chain hash(if VERSIONED)
                       Public metadata   (if HAS_PUBLIC_METADATA)
           --------  ------------------------------------------
                     BLOCK DIRECTORY (65 bytes per block)
                       For each block:
                       +--  1B  Block Type (uint8)
                       +-- 32B  Plaintext Hash (SHA-256)
                       +--  4B  Ciphertext Length (uint32 BE)
                       +-- 12B  IV / Nonce (random)
                       +-- 16B  GCM Authentication Tag
           --------  ------------------------------------------
           32        MERKLE ROOT (SHA-256)
           --------  ------------------------------------------
           32        KEY COMMITMENT (if FLAG_HAS_KEY_COMMITMENT)
                       SHA-256(key_0 || key_1 || ... || key_n)
           --------  ------------------------------------------
                     CIPHERTEXT BLOCKS
                       For each block:
                       +-- var  Encrypted data (length from dir)
           --------  ------------------------------------------
           64        MASTER SEAL (HMAC-SHA512)
                       Covers bytes [0 .. end of last ciphertext]
 --------  --------  ------------------------------------------
```

### Header (Fixed + Variable)

The header provides file identification, versioning, and basic metadata. The Content-Type field is always exactly 64 bytes, null-padded on the right. The filename is variable-length with a 2-byte length prefix (maximum 255 bytes).

### Extended Header (v1.1+)

Flag-dependent fields appear in a fixed order after the block count. Only fields whose corresponding flags are set are present. See [FORMAT_SPEC.md Section 3.2](../FORMAT_SPEC.md#32-extended-header-v11).

### Block Directory

Each block has a 65-byte directory entry containing its type, plaintext hash, ciphertext length, IV, and GCM tag. The directory is read before any ciphertext, enabling streaming verification and random-access decryption.

### Merkle Root and Key Commitment

The 32-byte Merkle root follows the block directory. If the `FLAG_HAS_KEY_COMMITMENT` flag is set, a 32-byte key commitment hash follows. This commitment is `SHA-256(key_0 || key_1 || ... || key_n)` and prevents invisible salamander attacks on AES-GCM.

### Ciphertext Blocks

Encrypted block data appears in order, with lengths specified by the block directory.

### Master Seal

The final 64 bytes are an HMAC-SHA512 seal computed over all preceding bytes. This provides a single integrity check over the entire file.

---

## Key Derivation Flow

Per-block encryption keys are derived using HKDF (RFC 5869) with SHA-256. This ensures that each block has a unique key and that all keys depend on the Merkle root.

```
  master_key (32 bytes)     merkle_root (32 bytes)
        |                         |
        +----------+--------------+
                   |
                   v
         IKM = master_key || merkle_root  (64 bytes)
                   |
                   +---- salt = master_salt (32 bytes from header)
                   |
                   v
         PRK = HMAC-SHA256(salt, IKM)     [HKDF-Extract]
                   |
                   |     info = "zegel-block-key-v1:" + index
                   |                |
                   v                v
         block_key = HMAC-SHA256(PRK, info || 0x01)  [HKDF-Expand]
                   |
                   v
         32-byte AES-256-GCM key for block[index]
```

**Important details:**
- In HKDF-Extract, the salt is the HMAC key and the IKM is the HMAC message. This follows RFC 5869 but can be confusing because HMAC(key, message) has the salt as key.
- The `info` string uses the decimal string representation of the block index (e.g., `"zegel-block-key-v1:0"`, `"zegel-block-key-v1:12"`).
- Since the output length (32 bytes) equals the hash length (SHA-256 = 32 bytes), only one HKDF-Expand iteration (`T(1)`) is needed.
- When `FLAG_HAS_EXPIRATION` is set, the info string includes the expiration date: `"zegel-block-key-v1:0:exp=2026-12-31"`.

See [FORMAT_SPEC.md Section 5.1](../FORMAT_SPEC.md#51-key-derivation-hkdf).

---

## Master Seal Flow

The master seal provides a single integrity check over the entire file. It is the last 64 bytes of the `.zgl` file.

```
  merkle_root (32 bytes)    master_key (32 bytes)    master_salt (32 bytes)
       |                         |                        |
       |                         +----------+-------------+
       |                                    |
       |                                    v
       |                    message = master_key || master_salt  (64 bytes)
       |                                    |
       +------ HMAC key ---+               |
                            |               |
                            v               v
              seal_key = HMAC-SHA256(merkle_root, master_key || master_salt)
                            |
                            |     file_bytes = bytes[0 .. last ciphertext byte]
                            |                |
                            v                v
              master_seal = HMAC-SHA512(seal_key, file_bytes)
                            |
                            v
              64-byte seal (appended as final bytes of .zgl file)
```

**Important details:**
- The seal key derivation uses `merkle_root` as the HMAC key and `master_key || master_salt` as the message. This is a specific ordering that must be matched exactly.
- The seal itself uses HMAC-SHA512 (not SHA256), producing a 64-byte output.
- The seal covers all bytes from offset 0 through the end of the last encrypted block -- everything except the seal itself.

See [FORMAT_SPEC.md Section 5.7](../FORMAT_SPEC.md#57-master-seal).

---

## Block Types Overview

| Value  | Name               | Since | Description                                                |
|--------|--------------------|-------|------------------------------------------------------------|
| `0x01` | CONTENT            | v1.0  | A chunk of the original file content                       |
| `0x02` | METADATA           | v1.0  | Encrypted JSON key-value metadata                          |
| `0x03` | PUBLIC_METADATA    | v1.1  | Unencrypted metadata (integrity-protected by Merkle tree)  |
| `0x04` | FILE_HEADER        | v1.1  | Multi-file container: sub-file header with name and range  |
| `0x05` | PROVENANCE         | v1.1  | Chain of custody event record                              |
| `0x06` | REDACTED           | v1.2  | Permanently redacted block (original hash preserved)       |
| `0x07` | ATTESTATION        | v1.2  | Co-signature attestation from a third party                |
| `0x08` | REFERENCE          | v1.2  | Cross-file reference via Merkle root of another .zgl file  |
| `0x09` | AUDIT              | v1.2  | Tamper-evident audit trail entry                           |
| `0x0A` | DISCLOSURE_INDEX   | v1.2  | Index of blocks available for selective disclosure         |

When the `FLAG_HAS_METADATA` flag is set, the first block (index 0) is always a METADATA block. All other block types follow in the order they were added.

See [FORMAT_SPEC.md Section 3.4](../FORMAT_SPEC.md#34-block-types).

---

## Flag System

Zegel uses a 16-bit flags field (big-endian) at offset 10 in the header. Flags control which optional features are active and which extended header fields are present.

| Bit | Mask     | Name                  | Since | Purpose                                       |
|-----|----------|-----------------------|-------|-----------------------------------------------|
| 0   | `0x0001` | HAS_METADATA          | v1.0  | Encrypted metadata block present (index 0)    |
| 1   | `0x0002` | COMPRESSED            | v1.1  | Content blocks are zlib-compressed            |
| 2   | `0x0004` | PASSWORD_DERIVED      | v1.1  | Master key derived via Argon2id               |
| 3   | `0x0008` | HAS_KEY_COMMITMENT    | v1.1  | Key commitment hash follows Merkle root       |
| 4   | `0x0010` | HAS_EXPIRATION        | v1.1  | Cryptographic expiration date                 |
| 5   | `0x0020` | HAS_PUBLIC_METADATA   | v1.1  | Unencrypted metadata in extended header       |
| 6   | `0x0040` | MULTI_FILE            | v1.1  | Container holds multiple sub-files            |
| 7   | `0x0080` | HAS_CANARY            | v1.2  | Canary trap fingerprinting enabled            |
| 8   | `0x0100` | HAS_REDACTIONS        | v1.2  | One or more blocks permanently redacted       |
| 9   | `0x0200` | SPLIT_KEY             | v1.2  | Master key was split via Shamir SSS           |
| 10  | `0x0400` | SELECTIVE_DISCLOSURE  | v1.2  | Selective disclosure index block present      |
| 11  | `0x0800` | VERSIONED             | v1.2  | Version chain hash links to predecessor       |
| 12-15 | --     | RESERVED              | --    | Must be zero                                  |

### Flag Interactions

- `PASSWORD_DERIVED` adds Argon2id parameters to the extended header.
- `HAS_EXPIRATION` adds the expiration timestamp to the extended header and modifies the HKDF info string.
- `HAS_CANARY` adds the recipient ID to the extended header and appends fingerprint padding to content blocks before encryption.
- `SPLIT_KEY` adds the threshold (M) and total shares (N) to the extended header.
- `HAS_KEY_COMMITMENT` adds a 32-byte key commitment hash after the Merkle root in the binary layout.
- `HAS_PUBLIC_METADATA` adds a length-prefixed JSON field to the extended header.
- `VERSIONED` adds a 32-byte version chain hash to the extended header.

Extended header fields always appear in the fixed order listed in [FORMAT_SPEC.md Section 3.2](../FORMAT_SPEC.md#32-extended-header-v11), regardless of which flags are set. Only fields whose flags are active are present; absent fields occupy zero bytes.

---

## Verification Pipeline

Reading and verifying a `.zgl` file reverses the sealing pipeline and performs integrity checks at multiple levels:

```
  .zgl File
      |
      v
  1. Validate magic bytes (ZEGEL\x00\x01\x00)
      |
      v
  2. Parse header + extended header + block directory
      |
      v
  3. Read stored Merkle root (+ key commitment if present)
      |
      v
  4. Derive/obtain master key
      |   (direct, Argon2id from password, or Shamir reconstruction)
      |
      v
  5. Verify master seal: HMAC-SHA512 over all preceding bytes
      |   FAIL -> TAMPERED (stop)
      |
      v
  6. Rebuild Merkle tree from directory hashes, compare with stored root
      |   FAIL -> TAMPERED (stop)
      |
      v
  7. Verify key commitment if present
      |   FAIL -> TAMPERED (stop)
      |
      v
  8. For each block:
      |   a. Derive per-block key via HKDF
      |   b. Decrypt with AES-256-GCM (key, IV, tag)
      |      FAIL -> TAMPERED (stop)
      |   c. Hash decrypted plaintext, compare with directory hash
      |      FAIL -> TAMPERED (stop)
      |   d. Decompress if COMPRESSED flag set
      |   e. Strip canary padding if HAS_CANARY flag set
      |
      v
  9. Reassemble content blocks -> original file
```

See [FORMAT_SPEC.md Section 11](../FORMAT_SPEC.md#11-verification-algorithm) for the complete verification algorithm.

---

## Component Interaction Diagram

```
  +------------------------------------------------------------------+
  |                        .zgl Binary File                          |
  |                                                                  |
  |  +----------+  +----------+  +---------+  +-------+  +--------+ |
  |  |  Header  |  | Extended |  |  Block  |  |Merkle |  |  Key   | |
  |  |          |  |  Header  |  |Directory|  | Root  |  |Commit. | |
  |  +----+-----+  +----+-----+  +----+----+  +---+---+  +---+----+ |
  |       |              |             |           |           |      |
  |       |  flags       |  types,     |  32 bytes |  32 bytes |     |
  |       |  control     |  hashes,    |  integrity|  multi-key|     |
  |       |  which       |  lengths,   |  anchor   |  binding  |     |
  |       |  sections    |  IVs, tags  |           |           |     |
  |       |  exist       |             |           |           |     |
  |  +----+-----+--------+----+--------+---+-------+-----------+     |
  |  |          Ciphertext Blocks          |    Master Seal     |    |
  |  |  block_0 | block_1 | ... | block_n  |    (HMAC-SHA512)   |    |
  |  +-----------------------------------------+----------------+    |
  +------------------------------------------------------------------+

  External Inputs:
  +-------------+     +----------------+     +-----------------+
  | Master Key  |     | Password       |     | M-of-N Shares   |
  | (32 bytes)  | OR  | (Argon2id)     | OR  | (Shamir SSS)    |
  +------+------+     +-------+--------+     +--------+--------+
         |                    |                        |
         +--------------------+------------------------+
                              |
                              v
                     Key Derivation (HKDF)
                              |
                              v
                     Per-Block AES-256-GCM Keys
```

---

## Further Reading

- [FORMAT_SPEC.md](../FORMAT_SPEC.md) -- Complete binary format specification
- [Porting Guide](porting_guide.md) -- How to implement Zegel in another language
- [Security Audit](security_audit.md) -- Security considerations and threat model
- [FAQ](faq.md) -- Frequently asked questions
- [Canary Traps](features/canary_traps.md) -- SEC-4 leak tracing
- [Split Key](features/split_key.md) -- SEC-6 multi-party key management
- [Redaction](features/redaction.md) -- SEC-5 partial content removal
- [Selective Disclosure](features/selective_disclosure.md) -- GEN-9 partial sharing
- [Audit Trail](features/audit_trail.md) -- GEN-8 compliance logging
