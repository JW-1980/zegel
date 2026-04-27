# Zegel Cryptographic Security Research and Threat Model

This document outlines a security review of the Zegel tamper-proof container format, including its cryptographic primitives, structural security features, dependency analysis, and theoretical threat model. The analysis is based on the source code located in `lib/lib/src/`, primarily focusing on `merkle_tree.dart`, `key_derivation.dart`, `reader.dart`, and `crypto_glossary.dart`.

## 1. Dependency Analysis (OSV Scan)
A check against the Open Source Vulnerabilities (OSV) database was performed for the primary cryptographic libraries used by the Zegel Dart implementation:
- `crypto` (3.0.3): No known vulnerabilities found.
- `pointycastle` (3.7.3): No known vulnerabilities found.
- `archive` (3.4.10): No known vulnerabilities found.
- `pinenacl` (0.6.0): No known vulnerabilities found.

*Note: The absence of documented CVEs in OSV does not imply the libraries are flawless, but it indicates no widely publicized, unpatched exploits exist for the specific versions utilized.*

## 2. Cryptographic Architecture Review

The Zegel format employs a robust, layered cryptographic architecture designed for absolute immutability and tamper evidence.

### 2.1 Key Derivation (Argon2id and HKDF)
- **Password-Based Derivation**: When sealed with a password, Zegel uses **Argon2id** (via PointyCastle) to derive the 32-byte master key. The implementation strictly enforces minimum bounds (time cost >= 2, memory cost >= 19 MiB) aligning with OWASP recommendations to resist GPU/ASIC brute-force attacks.
- **Per-Block Key Derivation (HKDF-SHA256)**: The 32-byte master key is *never* used directly to encrypt data. Instead, it is combined with the Merkle root and a random 32-byte salt using HMAC-based Extract-and-Expand Key Derivation Function (HKDF). A unique 32-byte AES-256 key is generated for every block, bound to the block's index.
- **Deterministic Nonces**: Zegel derives AES-GCM nonces deterministically via HKDF-SHA256 using a distinct info domain string (`zegel-block-nonce-v1:<index>`). This prevents nonce reuse and mitigates kleptographic attacks where malicious RNGs might leak key material via nonces.

### 2.2 Merkle Tree Integrity
- **Structure**: Zegel constructs a binary hash tree (Merkle tree) over the plaintext hashes of every data block.
- **Domain Separation (RFC 6962)**: Crucially, `merkle_tree.dart` implements domain-separated hashing to thwart second-preimage attacks:
  - Leaves: `SHA-256(0x00 || block_hash)`
  - Internal Nodes: `SHA-256(0x01 || left || right)`
  This prevents an attacker from supplying internal node hashes as leaf nodes.
- **Binding**: Because the Merkle root is injected into the HKDF calculation for *every* block's encryption key, flipping a single byte in any block alters the Merkle root, which in turn radically changes the derived decryption key for *all* blocks. A tampered file becomes entirely undecryptable, rather than merely failing a post-decryption MAC check.

### 2.3 Authenticated Encryption (AES-256-GCM)
- Content blocks are encrypted using AES-256-GCM.
- GCM provides both confidentiality and authenticity (via a 16-byte authentication tag).
- **Key Commitment (SEC-2)**: To prevent "invisible salamander" attacks (where an attacker crafts a ciphertext that successfully decrypts to two different valid plaintexts under two different keys), Zegel computes a commitment hash over all derived block keys (`SHA-256(key_0 || ... || key_n)`).

### 2.4 Master Sealing (HMAC-SHA512)
- The entire file format is authenticated with a 64-byte trailing Master Seal.
- The seal is an HMAC-SHA512 digest computed over the file bytes using a seal key (`HMAC-SHA256(merkleRoot, masterKey || salt)`). This prevents tampering with the file structure (headers, block directory) before decryption even begins.

## 3. Threat Modeling & Theoretical Attack Vectors

While Zegel is highly hardened, we evaluate potential theoretical vectors:

### 3.1 Brute Force / Dictionary Attacks
- **Vector**: An attacker attempts to guess the password of a password-sealed file.
- **Mitigation**: Argon2id ensures high computational and memory cost for each guess. The security scales with the chosen time/memory parameters. If weak passwords are used alongside low Argon2id parameters, this remains the primary risk surface.

### 3.2 Second Preimage / Merkle Tree Splicing
- **Vector**: An attacker tries to replace a block in the file with another block that produces the same Merkle root.
- **Mitigation**: Obviated by the domain separation (0x00/0x01 prefixing) in the Merkle tree and the collision resistance of SHA-256.

### 3.3 Ciphertext Tampering / Bit Flipping
- **Vector**: Modifying the AES-GCM ciphertext bytes or the IV/Tag in the block directory.
- **Mitigation**: Fails at three levels:
  1. The AES-GCM authentication tag validation will fail.
  2. Modifying the block directory invalidates the trailing Master Seal (HMAC-SHA512).
  3. Modifying the block alters its hash, changing the Merkle Root, which scrambles all subsequent derived HKDF keys, rendering the entire file garbled.

### 3.4 Key Extraction via Memory
- **Vector**: If Zegel is running on a compromised host, an attacker could dump memory to extract the `masterKey` or plaintext blocks.
- **Mitigation**: The code utilizes `SecureMemory.wipe()` (as seen in guidelines and `key_derivation.dart` cleanup loops) to zeroize sensitive buffers immediately after use. However, running on fundamentally compromised hardware cannot prevent live memory extraction.

### 3.5 Rollback Attacks (Version Downgrade)
- **Vector**: An attacker replaces a newer, valid Zegel file with an older, valid Zegel file.
- **Mitigation**: The format supports a `versionChainHash` flag. If utilized, files form a hash chain, preventing stealthy rollbacks as long as the verification system tracks the head of the chain.

## 4. Conclusion
The Zegel Dart implementation demonstrates a rigorous application of modern cryptographic standards. The structural coupling of the Merkle root to the key derivation function is a particularly strong mechanism that enforces holistic file immutability, far exceeding standard symmetric encryption wrappers. No fundamental cryptographic flaws or dependency vulnerabilities were discovered during this review.
