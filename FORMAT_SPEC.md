# Zegel File Format Specification v1.4

**Extension:** `.zgl`
**MIME type:** `application/x-zgl`
**Magic bytes:** `ZEGEL\x00\x01\x00` (8 bytes)
**Endianness:** Big-endian (network byte order) throughout
**Status:** Draft - seeking IANA registration for `application/x-zgl`

---

## 1. Purpose

Zegel ("seal" in Dutch) is a tamper-proof container format. It wraps any file and makes the content **physically unreadable** if even a single byte is modified after creation. This is not a "check and warn" system - the cryptographic math itself prevents decoding.

### Design Goals

1. **Self-enforcing integrity** - No viewer logic or policy required. The math makes tampered content undecryptable.
2. **Language-agnostic** - Any language with AES-256-GCM, SHA-256, and HMAC-SHA512 can implement a reader/writer.
3. **Streaming-friendly** - Content is split into blocks for memory-efficient processing.
4. **Auditable** - Embedded metadata, timestamps, Merkle proofs, audit trails, and attestations enable forensic analysis.
5. **Partial access** - Selective disclosure tokens allow sharing specific blocks without exposing the master key.
6. **Multi-party trust** - Split-key (M-of-N) and co-signature attestation distribute trust across multiple parties.

### How It Works (Summary)

1. Content is split into blocks (default 64 KB each).
2. Each block's plaintext is hashed (SHA-256) to produce a **leaf hash**.
3. All leaf hashes form a **Merkle tree**. The **root hash** uniquely represents every block.
4. Each block's **encryption key** is derived from: `HKDF(master_key, merkle_root || block_index)`.
5. Blocks are encrypted with **AES-256-GCM** (authenticated encryption).
6. A **master seal** (HMAC-SHA512) covers the entire file.

**Why this is tamper-proof:** Changing any byte in any block changes that block's leaf hash, which changes the Merkle root, which changes EVERY block's derived encryption key. AES-256-GCM's built-in authentication tag then rejects decryption. The content is not "flagged as modified" - it is literally destroyed.

---

## 2. Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-27 | Initial specification: core sealing, Merkle tree, HKDF key derivation, AES-256-GCM |
| 1.1 | 2026-01-27 | SEC-1 Argon2id password derivation, SEC-2 key commitment, SEC-3 expiration, GEN-1 public metadata, GEN-2 compression, GEN-3 streaming verification, GEN-4 multi-file container, GEN-5 provenance chain |
| 1.2 | 2026-01-27 | SEC-4 canary traps, SEC-5 partial redaction, SEC-6 split-key M-of-N, GEN-6 co-signatures, GEN-7 cross-file references, GEN-8 audit trail, GEN-9 selective disclosure, GEN-10 content versioning |
| 1.3 | 2026-01-28 | SEC-7 regulatory hold, SEC-8 classification levels, SEC-9 hierarchical split-key, GEN-11 trusted timestamps (RFC 3161), GEN-12 anonymous mode, GEN-13 role-based attestation, GEN-14 excerpt proofs (Merkle inclusion), GEN-15 batch operations, GEN-16 manifests, GEN-17 provenance verification, GEN-18 token expiration |
| 1.4 | 2026-04-07 | **SECURITY**: SEC-10 Merkle tree domain separation (RFC 6962), SEC-11 mandatory key commitment with passwords, SEC-12 AAD binding in AES-GCM, SEC-13 Shamir share validation, SEC-14 Argon2id minimum parameters (OWASP), SEC-15 token expiration enforcement. **FEATURES**: GEN-19 streaming seal mode, GEN-20 burn-after-read, GEN-21 time-locked release, GEN-22 Ed25519 creator identity/signatures, GEN-23 device attestation, GEN-24 supply chain verification, GEN-25 structured blocks (SBOM, royalty, measurement, privilege log) |

---

## 3. Binary Layout

```
Offset  Size     Field
------  -------  --------------------------------
0       8        Magic bytes: ZEGEL\x00\x01\x00
8       1        Version major (uint8)
9       1        Version minor (uint8)
10      2        Flags (uint16, big-endian)
12      8        Created timestamp (uint64, big-endian, Unix epoch seconds)
20      64       Content-Type (UTF-8, null-padded to 64 bytes)
84      2        Filename length (uint16, big-endian, max 255)
86      var      Filename (UTF-8, length from previous field)
86+N    32       Master salt (random, 32 bytes)
118+N   4        Block count (uint32, big-endian)
                 --- Extended Header (flag-dependent, v1.1+) ---
                 See Section 3.2 for flag-dependent fields
                 --- Block Directory (repeats `block_count` times) ---
                 For each block:
var     1          Block type (uint8)
var     32         Plaintext hash (SHA-256, raw 32 bytes)
var     4          Ciphertext length (uint32, big-endian)
var     12         IV/Nonce (random, 12 bytes)
var     16         GCM authentication tag (16 bytes)
                 --- End Block Directory ---
var     32       Merkle root hash (SHA-256, raw 32 bytes)
                 --- Key Commitment (if FLAG_HAS_KEY_COMMITMENT) ---
var     32         Key commitment hash (SHA-256)
                 --- Encrypted Block Data (repeats `block_count` times) ---
                 For each block:
var     var        Ciphertext (length from directory entry)
                 --- End Encrypted Block Data ---
var     64       Master seal (HMAC-SHA512, raw 64 bytes)
```

### 3.1 Header Fields

| Field | Type | Bytes | Description |
|-------|------|-------|-------------|
| Magic | bytes | 8 | `ZEGEL\x00\x01\x00` - identifies this as a .zgl file |
| Version major | uint8 | 1 | Format major version (currently 1) |
| Version minor | uint8 | 1 | Format minor version (currently 2) |
| Flags | uint16 BE | 2 | Bitfield (see Section 4) |
| Timestamp | uint64 BE | 8 | Unix epoch seconds when file was created |
| Content-Type | UTF-8 | 64 | MIME type of original content, null-padded |
| Filename length | uint16 BE | 2 | Length of filename in bytes (max 255) |
| Filename | UTF-8 | variable | Original filename |
| Master salt | bytes | 32 | Cryptographically random salt |
| Block count | uint32 BE | 4 | Total number of blocks (metadata + content + special) |

### 3.2 Extended Header (v1.1+)

The extended header immediately follows the block count field. Fields are present or absent based on the flags bitmask, and MUST appear in the order listed below:

| Condition | Field | Type | Bytes | Description |
|-----------|-------|------|-------|-------------|
| `FLAG_PASSWORD_DERIVED` | Argon2 time cost | uint32 BE | 4 | Argon2id iterations |
| `FLAG_PASSWORD_DERIVED` | Argon2 memory cost | uint32 BE | 4 | Argon2id memory in KiB |
| `FLAG_HAS_EXPIRATION` | Expiration timestamp | uint64 BE | 8 | Unix epoch after which readers should refuse extraction |
| `FLAG_HAS_CANARY` | Recipient ID | bytes | 32 | Unique recipient identifier for canary trap |
| `FLAG_SPLIT_KEY` | Threshold (M) | uint8 | 1 | Minimum shares required to reconstruct |
| `FLAG_SPLIT_KEY` | Total shares (N) | uint8 | 1 | Total number of shares generated |
| `FLAG_VERSIONED` | Version chain hash | bytes | 32 | SHA-256 linking to previous version |
| `FLAG_HAS_PUBLIC_METADATA` | Public metadata length | uint32 BE | 4 | Length of following JSON |
| `FLAG_HAS_PUBLIC_METADATA` | Public metadata | UTF-8 | variable | Unencrypted JSON, integrity-protected by Merkle tree |

### 3.3 Block Directory Entry

Each block has a 65-byte directory entry:

| Field | Type | Bytes | Description |
|-------|------|-------|-------------|
| Block type | uint8 | 1 | See Section 3.4 |
| Plaintext hash | bytes | 32 | SHA-256 of the unencrypted block data |
| Ciphertext length | uint32 BE | 4 | Length of encrypted data in bytes |
| IV/Nonce | bytes | 12 | Random nonce for AES-GCM |
| Auth tag | bytes | 16 | AES-GCM authentication tag |

### 3.4 Block Types

| Value | Name | Since | Description |
|-------|------|-------|-------------|
| `0x01` | CONTENT | v1.0 | A chunk of the original file content |
| `0x02` | METADATA | v1.0 | JSON-encoded key-value metadata (encrypted) |
| `0x03` | PUBLIC_METADATA | v1.1 | Unencrypted metadata (integrity-protected only) |
| `0x04` | FILE_HEADER | v1.1 | Multi-file: sub-file header with name, type, block range |
| `0x05` | PROVENANCE | v1.1 | Chain of custody event record |
| `0x06` | REDACTED | v1.2 | Permanently redacted block (original hash preserved for Merkle tree) |
| `0x07` | ATTESTATION | v1.2 | Co-signature attestation from a third party |
| `0x08` | REFERENCE | v1.2 | Cross-file reference (Merkle root of another .zgl file) |
| `0x09` | AUDIT | v1.2 | Tamper-evident audit trail entry |
| `0x0A` | DISCLOSURE_INDEX | v1.2 | Index of blocks available for selective disclosure |
| `0x0B` | TIMESTAMP | v1.3 | Trusted timestamp token (RFC 3161 compatible) |
| `0x0C` | EXCERPT | v1.3 | Merkle inclusion proof for excerpt verification |
| `0x0D` | MANIFEST_ENTRY | v1.3 | Reference to an external file in a manifest |

If the `FLAG_HAS_METADATA` flag is set, the **first block** is always a metadata block. Subsequent blocks follow in the order they were added.

### 3.5 Merkle Root

32 bytes immediately after the block directory. This is the root of a binary SHA-256 Merkle tree built from all block plaintext hashes.

### 3.6 Key Commitment (v1.1+)

If `FLAG_HAS_KEY_COMMITMENT` is set, 32 bytes follow the Merkle root. This is SHA-256 of all derived block keys concatenated: `SHA-256(key_0 || key_1 || ... || key_n)`. Prevents invisible salamander attacks where AES-GCM decrypts different content under different keys.

### 3.7 Master Seal

The last 64 bytes of the file. HMAC-SHA512 computed over everything preceding it (magic through last ciphertext byte).

---

## 4. Flags

| Bit | Mask | Name | Since | Description |
|-----|------|------|-------|-------------|
| 0 | `0x0001` | HAS_METADATA | v1.0 | First block is an encrypted JSON metadata block |
| 1 | `0x0002` | COMPRESSED | v1.1 | Content blocks are zlib-compressed before encryption |
| 2 | `0x0004` | PASSWORD_DERIVED | v1.1 | Master key is derived from password via Argon2id |
| 3 | `0x0008` | HAS_KEY_COMMITMENT | v1.1 | Key commitment hash is present after Merkle root |
| 4 | `0x0010` | HAS_EXPIRATION | v1.1 | File has a cryptographic expiration timestamp |
| 5 | `0x0020` | HAS_PUBLIC_METADATA | v1.1 | Unencrypted metadata block is present |
| 6 | `0x0040` | MULTI_FILE | v1.1 | Container holds multiple files |
| 7 | `0x0080` | HAS_CANARY | v1.2 | Canary trap fingerprinting is enabled |
| 8 | `0x0100` | HAS_REDACTIONS | v1.2 | One or more blocks have been permanently redacted |
| 9 | `0x0200` | SPLIT_KEY | v1.2 | Master key was split using Shamir's Secret Sharing |
| 10 | `0x0400` | SELECTIVE_DISCLOSURE | v1.2 | Selective disclosure index block is present |
| 11 | `0x0800` | VERSIONED | v1.2 | File is linked to a previous version via chain hash |
| 12 | `0x1000` | REGULATORY_HOLD | v1.3 | File is under regulatory hold (extraction blocked until hold date) |
| 13 | `0x2000` | HAS_TIMESTAMP | v1.3 | File contains a trusted timestamp block (RFC 3161) |
| 14 | `0x4000` | ANONYMOUS | v1.3 | File was sealed in anonymous mode (no identifying metadata) |
| 15 | `0x8000` | HAS_CLASSIFICATION | v1.3 | File has a classification level in public metadata |

---

## 5. Cryptographic Operations

### 5.1 Key Derivation (HKDF)

The format requires a 32-byte **master key** as input. How this key is obtained is implementation-specific (e.g., password-based derivation, hardware token, application secret).

**Per-block key derivation** uses HKDF (RFC 5869) with SHA-256:

```
ikm  = master_key || merkle_root      (64 bytes)
salt = master_salt                     (32 bytes from header)
info = "zegel-block-key-v1:" || block_index_as_string
prk  = HMAC-SHA256(salt, ikm)         (extract step)
key  = HKDF-Expand(prk, info, 32)     (expand step, 32 byte output)
```

**HKDF-Expand** (RFC 5869 Section 2.3):
```
T(1) = HMAC-SHA256(prk, info || 0x01)
T(2) = HMAC-SHA256(prk, T(1) || info || 0x02)
...
OKM  = first L bytes of T(1) || T(2) || ...
```

Since we need 32 bytes and HMAC-SHA256 produces 32 bytes, only `T(1)` is needed.

### 5.2 Password-Based Key Derivation (SEC-1, v1.1)

When `FLAG_PASSWORD_DERIVED` is set, the master key is derived from a user password:

```
master_key = Argon2id(password, salt, ops_limit, mem_limit, output_length=32)
```

Parameters are stored in the extended header. Defaults: `ops_limit = 3`, `mem_limit = 65536 KiB (64 MiB)`.

**v1.4 minimum parameters (SEC-14):** Writers MUST enforce:
- `ops_limit >= 2` (time cost)
- `mem_limit >= 19456 KiB` (19 MiB memory cost)

These minimums follow OWASP 2024 Password Storage Cheat Sheet recommendations.

The Argon2id variant is mandatory (not Argon2i or Argon2d). This provides resistance against both side-channel and GPU attacks.

**v1.4 mandatory key commitment (SEC-11):** When `FLAG_PASSWORD_DERIVED` is set,
`FLAG_HAS_KEY_COMMITMENT` MUST also be set. This defends against partitioning
oracle attacks where an attacker uses the lack of key commitment to partition
the password space and recover the password more efficiently.

### 5.3 Key Derivation with Expiration (SEC-3, v1.1)

When `FLAG_HAS_EXPIRATION` is set, the HKDF info string includes the expiration date:

```
info = "zegel-block-key-v1:" || block_index || ":exp=" || YYYY-MM-DD
```

The date is UTC day-granularity. Readers MUST check the current time against the expiration timestamp. If expired, readers MUST refuse to derive keys (making extraction impossible). The expiration date is baked into the key derivation, so even if a reader ignores the check, it would need the exact expiration date to derive correct keys.

### 5.4 Block Encryption (v1.4: AAD Binding)

Each block is encrypted with AES-256-GCM. Starting with v1.4, **Associated
Authenticated Data (AAD)** is used to cryptographically bind each ciphertext to
its block type, position, and file identity. This prevents block-swapping and
cross-file replay attacks.

```
plaintext  = block content (bytes)
key        = derived block key (32 bytes)
iv         = random 12 bytes (unique per block)
aad        = block_type (1 byte) || block_index (uint32 BE) || master_salt (32 bytes)
tag_length = 16 bytes

ciphertext, tag = AES-256-GCM-Encrypt(key, iv, plaintext, aad, tag_length)
```

The AAD is **37 bytes**: 1 byte block type + 4 bytes block index (big-endian) +
32 bytes master salt from the file header. This ensures that:
- A ciphertext cannot be moved to a different block position (block_index check)
- A ciphertext cannot be used in a different file (salt check)
- A ciphertext's block type cannot be changed (block_type check)

### 5.5 Block Compression (GEN-2, v1.1)

When `FLAG_COMPRESSED` is set, each content block is compressed with zlib (level 6) before encryption:

```
compressed = zlib_compress(plaintext)
aad        = block_type || block_index (uint32 BE) || master_salt
ciphertext, tag = AES-256-GCM-Encrypt(key, iv, compressed, aad, tag_length)
```

The plaintext hash in the directory is computed from the **compressed** data (before encryption). On decryption, decompress after decrypting.

### 5.6 Merkle Tree Construction (v1.4: Domain-Separated per RFC 6962)

Domain separation prevents second preimage attacks where internal nodes could
be confused with leaf nodes. This follows the Certificate Transparency standard
(RFC 6962, Section 2.1).

1. Compute **domain-separated** leaf hash for each block:
   `leaf[i] = SHA-256(0x00 || SHA-256(plaintext[i]))`
   The `0x00` byte prefix identifies this as a leaf node.
2. Build tree bottom-up:
   - If layer has odd number of nodes, duplicate the last node
   - Parent node: `SHA-256(0x01 || left_child || right_child)`
     The `0x01` byte prefix identifies this as an internal node.
3. Root is the single node at the top level

**Single leaf special case:** If there is only one block, the Merkle root
equals the domain-separated leaf hash: `SHA-256(0x00 || SHA-256(plaintext[0]))`.

### 5.7 Master Seal

```
seal_key = HMAC-SHA256(merkle_root, master_key || master_salt)
seal     = HMAC-SHA512(seal_key, file_bytes_before_seal)
```

The seal covers ALL bytes from offset 0 through the end of the last encrypted block (everything except the seal itself).

---

## 6. Security Features (v1.2)

### 6.1 SEC-4: Canary Trap / Recipient Fingerprinting

When `FLAG_HAS_CANARY` is set, each content block has invisible, deterministic padding appended before encryption. This padding is unique per recipient, enabling leak tracing.

**Padding generation:**
```
mac = HMAC-SHA256(master_key, recipient_id || pack_uint32_be(block_index))
pad_len = (mac[0] % 16) + 1      // 1-16 bytes
padding = mac[1..pad_len-1] || byte(pad_len)   // PKCS#7-style length marker
```

**Leak identification:** Given a leaked file and a list of candidate recipient IDs, compute expected padding for each candidate at each block. Match against actual padding to identify the source.

**Recipient ID:** A 32-byte value stored in the extended header. Recommended derivation: `HMAC-SHA256(company_key, "zegel-recipient-v1:" || user_id)` for unforgeable IDs tied to authenticated users.

### 6.2 SEC-5: Partial Redaction

When `FLAG_HAS_REDACTIONS` is set, one or more blocks have been permanently redacted. A redacted block:

- Has block type `0x06` (REDACTED)
- Retains its original plaintext hash in the directory (preserving Merkle tree integrity)
- Has its ciphertext replaced with cryptographically random bytes
- Is indecryptable - the original content is permanently destroyed

**Redaction process:**
1. Verify the original file is intact (full verification)
2. For each block to redact:
   - Replace ciphertext with `random_bytes(ciphertext_length)`
   - Change block type to `0x06`
   - Keep the original plaintext hash, IV, and auth tag in the directory
3. Recompute the master seal over the modified file

**Verification of redacted files:** The Merkle tree remains valid because original leaf hashes are preserved. Redacted blocks are skipped during decryption. Non-redacted blocks decrypt normally.

### 6.3 SEC-6: Split-Key M-of-N (Shamir's Secret Sharing)

When `FLAG_SPLIT_KEY` is set, the master key was split into N shares using Shamir's Secret Sharing over GF(256). Any M shares can reconstruct the key; fewer than M shares reveal no information.

**Key splitting:**
```
For each byte b of the 32-byte master key:
  1. Generate random polynomial of degree M-1: f(x) = b + a1*x + a2*x^2 + ... + a_{M-1}*x^{M-1}
  2. Evaluate at x = 1, 2, ..., N to produce N shares
  3. Each share = 1-byte x-coordinate || 32-byte y-values
```

**Key reconstruction:** Lagrange interpolation at x=0 over GF(256) for each byte position.

**GF(256) arithmetic:** Uses irreducible polynomial `x^8 + x^4 + x^3 + x + 1` (0x11B). Addition is XOR. Multiplication uses the Russian peasant algorithm with modular reduction. Inverse uses Fermat's little theorem: `a^(-1) = a^254`.

**Share format:** Each share is exactly 33 bytes: 1-byte x-coordinate (1-255) + 32 bytes of y-values.

The extended header stores M (threshold) and N (total shares) as uint8 values.

### 6.4 Canary + Split-Key Interaction

Canary traps and split-key can be used together. The canary padding is applied using the reconstructed master key. The recipient ID is still stored in the extended header.

---

## 7. General Features (v1.2)

### 7.1 GEN-6: Co-Signatures / Multi-Party Attestation

Attestation blocks (type `0x07`) allow third parties to cryptographically attest to a file's integrity without knowing the master key.

**Attestation creation:**
```
message = merkle_root || signer_id || pack_uint64_be(timestamp) || statement
hmac = HMAC-SHA256(signer_key, message)
```

**Attestation block content (JSON):**
```json
{
  "signer_id": "user:42:accountant@example.com",
  "signer_key": "<hex-encoded 32-byte key>",
  "statement": "Reviewed and approved",
  "timestamp": 1706367600,
  "hmac_hex": "<hex-encoded 32-byte HMAC>"
}
```

**Signer key derivation:** Recommended: `HMAC-SHA256(company_key, "zegel-signer-v1:" || signer_id)` for keys derived from a shared company secret.

### 7.2 GEN-7: Cross-File References

Reference blocks (type `0x08`) link a .zgl file to other .zgl files, creating a verifiable reference graph.

**Reference block content (JSON):**
```json
{
  "merkle_root_hex": "<64-char hex>",
  "filename": "related-document.zgl",
  "relationship": "supersedes|references|derived_from|attached_to",
  "metadata": {}
}
```

### 7.3 GEN-8: Tamper-Evident Audit Trail

Audit blocks (type `0x09`) form a hash-chained append-only log within the file.

**Audit entry:**
```json
{
  "actor": "user:42:admin@example.com",
  "action": "sealed|verified|redacted|attested|disclosed",
  "timestamp": 1706367600,
  "details": {},
  "chain_hash": "<64-char hex>"
}
```

**Chain hash computation:**
```
chain_hash[0] = SHA-256(zeros_32_bytes || entry_0_json)
chain_hash[n] = SHA-256(chain_hash[n-1] || entry_n_json)
```

Verifiers MUST recompute chain hashes and reject the audit trail if any hash does not match.

### 7.4 GEN-9: Selective Disclosure

When `FLAG_SELECTIVE_DISCLOSURE` is set, a disclosure index block (type `0x0A`) is present. This enables generating tokens that allow third parties to decrypt specific blocks without the master key.

**Disclosure token (JSON):**
```json
{
  "version": 1,
  "merkle_root": "<64-char hex>",
  "block_keys": {
    "0": "<64-char hex key for block 0>",
    "3": "<64-char hex key for block 3>"
  },
  "created_at": 1706367600
}
```

Each block key is the per-block derived key (see Section 5.1). The token holder can decrypt only the listed blocks. They cannot derive keys for other blocks because they don't have the master key.

**Token generation:** Only the master key holder can generate tokens. The token is distributed out-of-band (not embedded in the file).

### 7.5 GEN-10: Content Versioning

When `FLAG_VERSIONED` is set, the extended header contains a 32-byte version chain hash linking this file to its predecessor:

```
version_chain_hash = SHA-256(previous_merkle_root || previous_master_seal)
```

This allows verification that a file is a legitimate successor of another without needing the predecessor's master key.

---

## 7a. Security Features (v1.3)

### 7a.1 SEC-7: Regulatory Hold

When `FLAG_REGULATORY_HOLD` (0x1000) is set, the file cannot be extracted until the hold date has passed. The hold expiration is stored in public metadata as `regulatory_hold_until` (Unix epoch seconds). Readers MUST check the current time against this value and throw `ZegelRegulatoryHoldException` if the hold is still active.

Use cases: SEC 17a-4 compliance, GDPR litigation holds, evidence preservation orders.

### 7a.2 SEC-8: Classification Levels

When `FLAG_HAS_CLASSIFICATION` (0x8000) is set, the public metadata contains a `classification` field with one of the following levels (ordered from lowest to highest):

| Level | Description |
|-------|-------------|
| `PUBLIC` | No restrictions |
| `INTERNAL` | Organisation-internal only |
| `CONFIDENTIAL` | Restricted distribution |
| `SECRET` | Need-to-know basis |
| `TOP_SECRET` | Highest restriction |

Classification metadata also includes `authority` (who set the level), `classified_at` (timestamp), and optional `caveats` (handling instructions like "NOFORN", "REL TO").

**Declassification:** A declassification record lowers the classification level and records the authority and reason. The new level must be strictly lower than the current level.

### 7a.3 SEC-9: Hierarchical Split-Key

Extends Shamir's Secret Sharing (SEC-6) with classification-based access levels. For each classification level, a level-specific sub-key is derived:

```
level_key = HMAC-SHA256(master_key, "zegel-level:" || level_name)
```

Each level key is then split using standard Shamir SSS with level-appropriate threshold/total values. Higher-level shares cannot reconstruct lower-level keys and vice versa.

## 7b. General Features (v1.3)

### 7b.1 GEN-11: Trusted Timestamps (RFC 3161)

When `FLAG_HAS_TIMESTAMP` (0x2000) is set, a timestamp block (type `0x0B`) contains a signed timestamp proving when the file was sealed.

**Timestamp request:**
```
message_imprint = SHA-256(merkle_root || master_seal)
```

**Local timestamp token:** When no external TSA is available, a local token is created:
```
message = merkle_root || master_seal || pack_uint64_be(epoch_seconds)
signature = HMAC-SHA256(signer_key, message)
```

This helps prevent clock manipulation attacks on expiration features.

### 7b.2 GEN-12: Anonymous Mode

When `FLAG_ANONYMOUS` (0x4000) is set, the file was sealed without identifying metadata. The filename is set to a random identifier, and no user-attributable metadata is included. Use cases: whistleblower protection, anonymous voting.

### 7b.3 GEN-13: Role-Based Attestation

Extends co-signatures (GEN-6) with predefined roles. The role field is included in the HMAC computation:

```
message = merkle_root || signer_id || pack_uint64_be(timestamp) || statement || role
hmac = HMAC-SHA256(signer_key, message)
```

Standard roles: `owner`, `signer`, `witness`, `notary`, `auditor`, `reviewer`.

**Policy checking:** A required roles policy can be defined (e.g., requires both a `signer` and a `notary`). The `checkPolicy` method verifies all required roles are present in the attestation set.

### 7b.4 GEN-14: Excerpt Proofs (Merkle Inclusion)

Excerpt blocks (type `0x0C`) contain Merkle inclusion proofs that allow proving a specific block belongs to a sealed file without revealing the full file.

**Proof generation:**
```
Given leaf hashes [h0, h1, ..., hn] and target block index i:
1. Compute sibling hashes along the path from leaf i to the root
2. Package as: { block_index, block_hash, merkle_root, proof: [sibling_hashes], total_leaves }
```

**Proof verification:** Recompute the root from the block hash and proof path. Compare with the expected Merkle root from the file header.

### 7b.5 GEN-15: Batch Operations

Provides efficient processing of multiple .zgl files:

- **Batch verify:** Verify multiple files against the same master key, with optional stop-on-first-failure.
- **Batch seal:** Seal multiple content entries into individual .zgl files with shared options.

### 7b.6 GEN-16: Manifests

A manifest is a signed JSON document listing multiple .zgl files with their Merkle roots, enabling batch integrity verification of document sets (e.g., all files in a real estate closing).

**Manifest structure:**
```json
{
  "version": 1,
  "signer_id": "notary@example.com",
  "created_at": 1706367600,
  "files": [
    { "filename": "contract.zgl", "merkle_root": "<hex>" },
    { "filename": "deed.zgl", "merkle_root": "<hex>" }
  ],
  "signature": "<HMAC-SHA256 hex>"
}
```

### 7b.7 GEN-17: Provenance Verification

Extends provenance chains (GEN-5) with signed, hash-chained events and chronological verification:

```
event_hash[0] = SHA-256(event_0_json)
event_hash[n] = SHA-256(event_n_json)  // includes previous_event link
```

Each event is HMAC-signed and linked to a specific file via its Merkle root. Verification checks chronological order, chain hash integrity, and signature validity.

### 7b.8 GEN-18: Token Expiration

Extends selective disclosure tokens (GEN-9) with an `expires_at` field (Unix epoch seconds). Readers MUST check whether the token has expired before allowing extraction. This prevents indefinite access from a single token issuance.

## 7c. Security Features (v1.4)

### 7c.1 SEC-10: Merkle Tree Domain Separation

See Section 5.6. Leaf hashes are prefixed with `0x00` and internal node hashes with `0x01` per RFC 6962. This prevents second preimage attacks.

### 7c.2 SEC-11: Mandatory Key Commitment with Passwords

When `FLAG_PASSWORD_DERIVED` is set, `FLAG_HAS_KEY_COMMITMENT` MUST also be set. Defends against partitioning oracle attacks.

### 7c.3 SEC-12: AAD Binding in AES-GCM

See Section 5.4. Each block's ciphertext is bound to `block_type || block_index || master_salt` via GCM's Associated Authenticated Data.

### 7c.4 SEC-13: Shamir Share Validation

Implementations MUST validate share integrity before reconstruction:
- Reject shares with x-coordinate = 0
- Reject duplicate x-coordinates among shares
- Reject shares with invalid length (!= 33 bytes)

### 7c.5 SEC-14: Argon2id Minimum Parameters

See Section 5.2. Writers MUST enforce `time_cost >= 2` and `memory_cost >= 19456 KiB` per OWASP 2024 guidelines.

### 7c.6 SEC-15: Token Expiration Enforcement

Readers MUST check the `expires_at` field in disclosure tokens before any block decryption. Expired tokens MUST be rejected.

## 7d. General Features (v1.4)

### 7d.1 GEN-19: Streaming Seal Mode

Allows append-only block sealing for real-time use cases (black boxes, IoT logging). Blocks are encrypted as they arrive; the Merkle tree and master seal are computed on finalization.

### 7d.2 GEN-20: Burn After Read

Embeds a tamper-evident read counter in public metadata. After N reads, the content is considered destroyed. The counter is protected by HMAC.

**Limitation:** Requires trust in the reader software. The file format itself cannot enforce read limits -- this is a policy mechanism.

### 7d.3 GEN-21: Time-Locked Release

Uses iterated hashing (SHA-256) to create a time-lock puzzle. The actual encryption key is derived from `SHA-256^N(puzzle_seed)` where N is calibrated to the desired time duration. Sequential computation is required -- no parallelization shortcut.

### 7d.4 GEN-22: Creator Identity (Ed25519 Signatures)

New block type `0x0E` (SIGNATURE): Contains an Ed25519 signature over `SHA-256(merkle_root || master_seal || timestamp)`, binding the file to a verified identity.

### 7d.5 GEN-23: Device Attestation

New block type `0x0F` (DEVICE_ATTESTATION): Contains signed device properties (OS, platform, hostname hash) bound to the sealing operation.

### 7d.6 GEN-24: Supply Chain Verification

New block type `0x14` (BUILD_ATTESTATION): Contains Ed25519-signed build provenance (version, commit hash, build timestamp, builder identity, reproducible build hash). Used to verify the integrity of the Zegel tool itself.

### 7d.7 GEN-25: Structured Block Types

| Type | Name | Purpose |
|------|------|---------|
| 0x10 | SBOM | Software Bill of Materials |
| 0x11 | ROYALTY | Payment split ratios |
| 0x12 | MEASUREMENT | Sensor/IoT data with calibration |
| 0x13 | PRIVILEGE_LOG | Legal basis for redactions |

All structured blocks are JSON-serialized and encrypted as regular blocks.

---

## 8. Metadata Block Format

### 8.1 Encrypted Metadata (v1.0)

When `FLAG_HAS_METADATA` is set, the first block (type `0x02`) contains a JSON object. After decryption, the plaintext is UTF-8 encoded JSON.

Standard metadata keys (all optional):

| Key | Type | Description |
|-----|------|-------------|
| `sealed_at` | ISO 8601 string | When the file was sealed |
| `sealed_by` | string | Application or user that created the seal |
| `document_id` | integer | Source document identifier |
| `document_type` | string | Type classification |
| `company_id` | integer | Organizational identifier |
| `original_hash` | string | Pre-existing hash of original content |

Applications may add custom keys freely. Unknown keys should be preserved, not discarded.

### 8.2 Public Metadata (GEN-1, v1.1)

When `FLAG_HAS_PUBLIC_METADATA` is set, the extended header contains a JSON object that is readable without the master key. This metadata is integrity-protected by the Merkle tree (included as a block hash) but not encrypted.

Use cases: file creation date, document classification, file size hints - anything that should be inspectable without decryption.

---

## 9. Multi-File Container (GEN-4, v1.1)

When `FLAG_MULTI_FILE` is set, the container holds multiple files. Each sub-file is preceded by a file header block (type `0x04`) containing:

```json
{
  "filename": "report.pdf",
  "content_type": "application/pdf",
  "block_count": 5,
  "original_size": 327680
}
```

The file header block is followed by the sub-file's content blocks.

---

## 10. Provenance Chain (GEN-5, v1.1)

Provenance blocks (type `0x05`) record the chain of custody:

```json
{
  "actor": "user:42:admin@example.com",
  "action": "created|transferred|received|verified",
  "timestamp": 1706367600,
  "signature": "<optional HMAC>"
}
```

---

## 11. Verification Algorithm

To verify and extract a .zgl file:

```
 1. Read and validate magic bytes
 2. Parse header (version, flags, timestamp, content-type, filename, salt, block count)
 3. Parse extended header based on flags (argon2 params, expiration, recipient ID,
    split-key params, version chain hash, public metadata)
 4. Parse block directory (for each block: type, hash, ciphertext_len, iv, tag)
 5. Read stored Merkle root (32 bytes)
 6. Read key commitment if FLAG_HAS_KEY_COMMITMENT (32 bytes)
 7. Derive master key:
    - If FLAG_PASSWORD_DERIVED: derive from password via Argon2id
    - If FLAG_SPLIT_KEY: reconstruct from M shares
    - Otherwise: use provided 32-byte master key
 8. If FLAG_HAS_EXPIRATION: check current time < expiration timestamp
    -> If expired: EXPIRED (stop)
 9. Compute master seal over bytes [0, file_length - 64)
10. Compare computed seal with stored seal (last 64 bytes)
    -> If mismatch: TAMPERED (stop)
11. Rebuild Merkle tree from directory hashes
12. Compare computed root with stored root
    -> If mismatch: TAMPERED (stop)
13. If FLAG_HAS_KEY_COMMITMENT: derive all block keys, compute commitment,
    compare with stored commitment
    -> If mismatch: TAMPERED (stop)
14. For each block:
    a. If block type is REDACTED (0x06): skip decryption, record as redacted
    b. Derive block key (with expiration suffix if applicable)
    c. If FLAG_HAS_CANARY: note that content blocks have canary padding
    d. Decrypt ciphertext with AES-256-GCM using derived key, stored IV, stored tag
       -> If decryption fails: TAMPERED (stop)
    e. If FLAG_COMPRESSED and block is CONTENT: decompress
    f. Hash decrypted plaintext with SHA-256
    g. Compare with stored hash from directory
       -> If mismatch: TAMPERED (stop)
    h. If FLAG_HAS_CANARY and block is CONTENT: strip canary padding
    i. Route by block type:
       - CONTENT (0x01): collect as file content
       - METADATA (0x02): parse as JSON metadata
       - PROVENANCE (0x05): collect provenance event
       - ATTESTATION (0x07): collect attestation
       - REFERENCE (0x08): collect cross-file reference
       - AUDIT (0x09): collect audit entry, verify chain hash
       - DISCLOSURE_INDEX (0x0A): collect disclosure index
15. Concatenate content blocks in order -> original file content
16. Return: VALID + content + metadata + provenance + attestations + audit trail + references
```

---

## 12. Implementation Notes

### 12.1 Block Size

The default block size is 65,536 bytes (64 KB). Implementations SHOULD allow this to be configured. Very small files (< block size) result in a single content block.

The `str_split()` (PHP) / chunking operation divides the content. If content length is not an exact multiple of block size, the last block is smaller.

### 12.2 Security Considerations

- **Master key**: Must be 32 bytes of cryptographically strong randomness or derived from a strong source
- **Salt**: Must be 32 bytes from a CSPRNG, unique per file
- **IV/Nonce**: Must be 12 bytes from a CSPRNG, unique per block. Never reuse an IV with the same key.
- **Timing attacks**: Use constant-time comparison for all hash/HMAC checks
- **Side channels**: Treat master key, derived keys, and plaintext as sensitive; clear from memory when done
- **Split-key shares**: Each share MUST be distributed via a secure channel. Shares MUST NOT be stored together.
- **Canary IDs**: Recipient IDs SHOULD be derived from authenticated identifiers (database user IDs), not self-reported values (emails).
- **Selective disclosure tokens**: Tokens grant permanent access to the specified blocks. Distribute tokens with the same care as keys.
- **Redaction**: Redaction is irreversible. The original ciphertext is replaced with random bytes. Only the file owner should have redaction authority.

### 12.3 Maximum Sizes

| Field | Maximum |
|-------|---------|
| Filename | 255 bytes |
| Content-Type | 64 bytes |
| Block count | 4,294,967,295 (uint32 max) |
| Ciphertext per block | 4,294,967,295 bytes (uint32 max) |
| Total file size | Limited by block count x max block ciphertext |
| Split-key shares | 255 |
| Split-key threshold | 2-255 |

Implementations SHOULD impose practical limits (e.g., 100 MB default).

### 12.4 Error Messages

When verification fails, implementations SHOULD NOT reveal which specific check failed to an untrusted party. Internally, detailed error messages are useful for debugging. Externally, a generic "file integrity verification failed" is appropriate.

### 12.5 Backward Compatibility

- v1.0 readers that encounter unknown flags SHOULD reject the file with an "unsupported version" error.
- v1.2 readers MUST handle v1.0 and v1.1 files (no extended header, fewer block types, fewer flags).
- When reading older versions, treat missing flags as unset and missing extended header fields as absent.

---

## 13. Test Vectors

### 13.1 Minimal File

```
Master key (hex): 0000000000000000000000000000000000000000000000000000000000000001
Content: "Hello, Zegel!" (UTF-8, 13 bytes)
Content-Type: "text/plain"
Filename: "hello.txt"
Salt: (all zeros for test reproducibility - NEVER in production)

Expected behavior:
- 1 content block (13 bytes < 64KB)
- No metadata block
- Flags: 0x0000
- Block count: 1
- Merkle root = SHA-256 of the single block's plaintext hash
```

### 13.2 Tamper Detection

```
1. Create a valid .zgl file with known content
2. Flip one bit in the encrypted block data
3. Attempt verification -> MUST fail
4. Flip one bit in the Merkle root -> MUST fail
5. Flip one bit in the master seal -> MUST fail
6. Flip one bit in the block directory hash -> MUST fail
7. Truncate file by 1 byte -> MUST fail
```

### 13.3 Split-Key Round-Trip

```
1. Create a .zgl file with threshold=3, total=5
2. Reconstruct key from shares 1, 3, 5 -> MUST succeed
3. Reconstruct key from shares 1, 2 (< threshold) -> MUST produce wrong key
4. Verify file with reconstructed key -> MUST succeed
```

### 13.4 Canary Trap

```
1. Seal the same content for recipient A and recipient B
2. Files MUST have identical Merkle roots (content is the same)
3. Files MUST have different ciphertexts (canary padding differs)
4. Given a leaked copy, identifyCanaryRecipient() MUST return the correct recipient
```

### 13.5 Redaction

```
1. Create a .zgl file with 3 content blocks
2. Redact block 1
3. Verify the redacted file -> MUST succeed (Merkle root unchanged)
4. Extract -> block 0 and 2 return content, block 1 is marked as redacted
5. Flip a bit in the redacted file's non-redacted block -> MUST fail verification
```

### 13.6 Selective Disclosure

```
1. Create a .zgl file with metadata (block 0) and 3 content blocks (blocks 1-3)
2. Generate a disclosure token for blocks [0, 2]
3. Extract using token -> block 0 (metadata) and block 2 (content) are returned
4. Blocks 1 and 3 are inaccessible without master key
```

---

## 14. File Extension Registration

The `.zgl` extension is chosen for brevity and uniqueness. The format name "Zegel" (Dutch: seal) reflects its origin in Dutch bookkeeping compliance.

Planned registrations:
- **IANA MIME type:** `application/x-zgl` (experimental), targeting `application/vnd.zegel`
- **File extension:** `.zgl`
- **UTI (Apple):** `com.zegel.zgl`
- **Windows registry:** `HKCR\.zgl`
- **freedesktop.org:** shared-mime-info entry for Linux

---

## 15. License

This specification is released under the Creative Commons Attribution 4.0 International License (CC BY 4.0). Implementations may be licensed under any terms. The recommended license for implementations is Apache License 2.0.

---

## 16. Reference Implementation

The reference implementation in PHP (Laravel) is available at:
- `app/Services/TamperProof/ZegelFormat.php` - Constants, key derivation, GF(256) arithmetic, canary traps, attestation, audit trail, disclosure tokens
- `app/Services/TamperProof/MerkleTree.php` - Merkle tree
- `app/Services/TamperProof/ZegelWriter.php` - File creation (all v1.2 features)
- `app/Services/TamperProof/ZegelReader.php` - File verification and extraction (all v1.2 features)
- `app/Services/TamperProof/ZegelOptions.php` - Feature option configuration
- `app/Services/TamperProof/ZegelService.php` - High-level application API

A cross-platform implementation in Dart/Flutter is available in the `zegel` open-source repository:
- `lib/lib/src/` - Core library (format, reader, writer, Merkle tree, key derivation, Shamir SSS, canary traps, attestation, audit trail, selective disclosure, batch, manifest, classification, excerpt, timestamp, provenance verification, hierarchical split-key, media metadata)
- `cli/bin/zegel.dart` - CLI application with 22 commands
- `app/` - Flutter GUI for Windows, macOS, Linux, Android, iOS
