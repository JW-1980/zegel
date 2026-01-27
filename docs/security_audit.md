# Zegel Security Considerations

This document describes the security model, cryptographic rationale, known limitations, and implementation guidelines for the Zegel tamper-proof container format (v1.2).

This is not a formal third-party audit. It is a first-party analysis intended to guide implementers, security reviewers, and users in understanding what Zegel protects against and where its boundaries lie.

---

## Threat Model

### What Zegel Protects Against

| Threat | Protection Mechanism |
|--------|---------------------|
| **Unauthorized modification** of sealed content | Merkle-rooted key derivation: any change invalidates all encryption keys; AES-GCM rejects decryption |
| **Partial tampering** of individual blocks | Per-block hashing in the Merkle tree; each block's key depends on the global root |
| **Silent content substitution** (invisible salamander attack) | Key commitment hash binds all derived keys to a single commitment value (SEC-2) |
| **Brute-force password attacks** | Argon2id with configurable time and memory cost (SEC-1) |
| **Post-expiration access** | Expiration date baked into HKDF info string; keys cannot be derived without knowing the exact date (SEC-3) |
| **Leak source identification** | Canary trap fingerprinting with per-recipient HMAC-based padding (SEC-4) |
| **Excessive disclosure** | Partial redaction permanently destroys selected blocks (SEC-5); selective disclosure limits access to specific blocks (GEN-9) |
| **Single point of failure for key custody** | Shamir's Secret Sharing splits the master key into M-of-N shares (SEC-6) |
| **Repudiation of review/approval** | Co-signature attestation with HMAC (GEN-6) |
| **Audit trail tampering** | Hash-chained append-only log with SHA-256 linking (GEN-8) |

### What Zegel Does NOT Protect Against

| Threat | Why Not |
|--------|---------|
| **Key compromise** | If the master key (or M shares) is exposed, all content is accessible. Zegel is symmetric-key only. |
| **Authorized user misuse** | A user with the master key can decrypt, copy, and redistribute content. Zegel does not implement DRM. |
| **Side-channel attacks on the implementation** | The format spec does not mandate specific side-channel countermeasures beyond constant-time comparison. Implementations must add their own. |
| **Traffic analysis / metadata leakage** | The header (file size, content-type, filename, timestamp, flags) is readable without the key. An observer can determine that a Zegel file exists, its approximate size, and when it was created. |
| **Coercion / rubber-hose attacks** | Zegel has no deniable encryption mode. If the key is known, the file creator is provable. |
| **Quantum computing (full break)** | AES-256 retains 128-bit security under Grover's algorithm. SHA-256 retains 128-bit collision resistance. This is adequate for the foreseeable future but not infinite. |
| **Denial of service** | A malicious file with an extremely large block count could consume excessive memory or processing time. Implementations should impose limits. |

---

## Cryptographic Algorithm Choices and Rationale

### AES-256-GCM (Per-Block Encryption)

**Choice:** AES-256 in Galois/Counter Mode with 128-bit authentication tags.

**Rationale:**
- AES-256 provides 256-bit key strength (128-bit post-quantum via Grover's algorithm).
- GCM provides authenticated encryption: both confidentiality and integrity in a single operation.
- GCM is widely available in hardware (AES-NI) and software across all major platforms.
- The 128-bit tag length is the maximum for GCM, providing the strongest authentication guarantee.

**Why not ChaCha20-Poly1305?** AES-GCM is more widely supported in hardware and regulatory contexts. ChaCha20-Poly1305 could be added as an alternative cipher in a future version.

**Why not AES-CBC + HMAC?** GCM provides both encryption and authentication in a single pass, reducing implementation complexity and the risk of combining primitives incorrectly (encrypt-then-MAC ordering bugs).

### SHA-256 (Block Hashing, Merkle Tree)

**Choice:** SHA-256 for all hash operations except the master seal.

**Rationale:**
- 256-bit output provides 128-bit collision resistance (adequate for Merkle tree security).
- Universal availability across all platforms and languages.
- Well-analyzed with no known practical attacks.
- 32-byte output aligns naturally with AES-256 key size.

**Why not SHA-3?** SHA-256 is more widely deployed, faster on most hardware, and provides equivalent security for 256-bit output. SHA-3 could be considered for future versions if SHA-256 weaknesses are discovered.

### HMAC-SHA512 (Master Seal)

**Choice:** HMAC-SHA512 for the master seal that covers the entire file.

**Rationale:**
- 512-bit output provides a stronger integrity guarantee for the file-level seal.
- Distinguishes the file seal from internal HMAC-SHA256 operations, reducing the risk of confusion.
- HMAC construction is provably secure under standard assumptions about the underlying hash function.

### HKDF (Key Derivation)

**Choice:** HKDF (RFC 5869) with SHA-256 for per-block key derivation.

**Rationale:**
- HKDF is the standard key derivation function recommended by NIST and IETF.
- The extract-then-expand paradigm cleanly separates the mixing of key material (extract) from the derivation of multiple keys (expand).
- Using the Merkle root in the IKM ensures that all derived keys depend on the integrity of all blocks.
- The info string includes the block index, ensuring each block gets a unique key.

### Argon2id (Password-Based Key Derivation)

**Choice:** Argon2id (hybrid variant) for password-to-key derivation.

**Rationale:**
- Argon2id combines Argon2i (side-channel resistant) and Argon2d (GPU-resistant) to provide protection against both attack vectors.
- Winner of the Password Hashing Competition (2015).
- Configurable time and memory cost allows tuning for the target hardware.
- Mandatory use of the id variant prevents downgrade to weaker Argon2i or Argon2d.

**Default parameters:** `ops_limit = 3` (3 iterations), `mem_limit = 65536 KiB` (64 MiB). These should be increased for high-security applications.

---

## Key Management Recommendations

### Master Key Generation

- Generate 32 bytes from a CSPRNG (e.g., `/dev/urandom`, `crypto.getRandomValues()`, `SecureRandom`).
- Never use a predictable seed, timestamp, or low-entropy source.
- Never reuse a master key across different `.zgl` files unless intentionally linking them.

### Master Key Storage

- Store master keys in platform-specific secure storage:
  - **macOS/iOS:** Keychain Services
  - **Android:** Android Keystore
  - **Windows:** Windows Credential Manager / DPAPI
  - **Linux:** libsecret (GNOME Keyring / KDE Wallet)
- Never store master keys in plaintext files, environment variables, or version control.
- Consider encrypting master keys at rest with a user-held password (using Argon2id).

### Password-Derived Keys

- Enforce minimum password length (12+ characters recommended).
- Use Argon2id with the highest time and memory cost the target hardware can tolerate.
- Display the Argon2id parameters to the user during sealing so they can be recorded.
- Consider warning users that forgetting the password means permanent data loss.

### Split-Key (M-of-N) Key Management

- Distribute shares via separate secure channels (e.g., in-person handoff, separate encrypted emails).
- Never store all shares in the same location or system.
- Record which share index (x-coordinate) was given to which party.
- Consider 2-of-3 as a minimum for business continuity (tolerates loss of one share).
- Consider 3-of-5 or higher for high-security scenarios.

### Key Rotation

- Zegel files are sealed once. To "rotate" a key, create a new `.zgl` file with a new master key and the same content.
- Use the version chain hash (`FLAG_VERSIONED`) to link the new file to the old one.
- Securely destroy the old file and old key after verification of the new file.

---

## Known Limitations

### 1. Symmetric-Key Only

Zegel v1.x uses only symmetric cryptography. There are no public-key signatures, no certificates, and no key exchange protocols. Authentication of the file creator relies on the secrecy of the master key.

**Implication:** If two parties share a master key, either one could have created the file. Non-repudiation requires out-of-band evidence (e.g., attestation blocks with party-specific signer keys).

**Future:** Public-key signatures are planned for v2.0.

### 2. File Size Metadata Is Not Hidden

The file header is unencrypted. An observer can determine:
- That a file is in Zegel format (magic bytes)
- The approximate original file size (block count and ciphertext lengths)
- The content type and filename
- The creation timestamp
- Which features are enabled (flags)

**Implication:** Zegel does not provide steganographic properties. The existence and approximate nature of the sealed content is visible. To hide the existence of a Zegel file, wrap it in another encryption layer.

### 3. No Deniability

If the master key is known, the file creator is provable. There is no deniable encryption mode where a decoy message could be produced with a different key.

**Implication:** Under compulsion, a key holder cannot plausibly deny the file's contents. This is by design for compliance and audit use cases, but may be undesirable in other contexts.

### 4. Quantum Computing Considerations

| Algorithm | Classical Security | Post-Quantum Security (Grover/BHT) |
|-----------|-------------------|-------------------------------------|
| AES-256   | 256-bit           | 128-bit (Grover's algorithm)        |
| SHA-256   | 128-bit collision | 85-bit collision (BHT algorithm)    |
| HMAC-SHA256 | 256-bit         | 128-bit (Grover's algorithm)        |
| HMAC-SHA512 | 512-bit         | 256-bit (Grover's algorithm)        |

AES-256 with 128-bit post-quantum security is considered adequate by NIST for the foreseeable future. If quantum computers capable of running Grover's algorithm at scale become available, a future Zegel version could adopt post-quantum algorithms (e.g., CRYSTALS-Kyber for key encapsulation).

### 5. No Forward Secrecy

If the master key is compromised at any point in the future, all past files sealed with that key become readable. There is no ephemeral key exchange to provide forward secrecy.

**Mitigation:** Use unique master keys per file. Use split-key (M-of-N) to distribute trust.

---

## Side-Channel Considerations

### Timing Attacks

All hash and HMAC comparisons during verification MUST use constant-time comparison functions. This includes:
- Master seal comparison
- Merkle root comparison
- Key commitment comparison
- Per-block hash comparison
- Attestation HMAC comparison
- Audit trail chain hash comparison

**Recommended functions:**
- Python: `hmac.compare_digest()`
- Go: `crypto/subtle.ConstantTimeCompare()`
- Rust: `subtle::ConstantTimeEq`
- Java: `MessageDigest.isEqual()`
- C#: `CryptographicOperations.FixedTimeEquals()`
- Node.js: `crypto.timingSafeEqual()`

### Memory Security

- Derived keys, master keys, and decrypted plaintext should be zeroed from memory as soon as they are no longer needed.
- Use language-specific secure memory utilities:
  - Rust: `zeroize` crate
  - C#: `SecureString`, `CryptographicOperations.ZeroMemory()`
  - Java: `Arrays.fill(keyBytes, (byte) 0)` (note: not guaranteed by GC)
  - Python: limited options; use `ctypes` to overwrite buffers

### Cache Attacks

AES implementations should use hardware AES-NI instructions where available to avoid table-lookup-based timing leaks. Most modern cryptographic libraries handle this automatically, but verify that your chosen library uses constant-time AES.

### Power Analysis

For embedded or mobile implementations, consider using libraries that implement countermeasures against differential power analysis (DPA). This is primarily a concern for hardware tokens or constrained devices.

---

## Implementation Security Checklist

Use this checklist when implementing or reviewing a Zegel implementation:

### Cryptographic Correctness

- [ ] AES-256-GCM with 128-bit (16-byte) tags, no AAD
- [ ] SHA-256 for block hashing and Merkle tree
- [ ] HMAC-SHA256 for HKDF, seal key, canary padding, attestation
- [ ] HMAC-SHA512 for master seal (64-byte output)
- [ ] HKDF-Extract: `HMAC(key=salt, msg=IKM)` -- salt is the HMAC key
- [ ] HKDF-Expand: `HMAC(key=PRK, msg=info || 0x01)` -- single iteration for 32-byte output
- [ ] Merkle tree: duplicate last node for odd layers, single leaf = root
- [ ] Master seal key: `HMAC(key=merkle_root, msg=master_key || salt)`
- [ ] GF(256) arithmetic with irreducible polynomial 0x11B
- [ ] Shamir interpolation at x=0 using Fermat's little theorem for inverse

### Randomness

- [ ] Master salt: 32 bytes from CSPRNG
- [ ] Per-block IV: 12 bytes from CSPRNG, unique per block
- [ ] Redaction replacement: random bytes from CSPRNG
- [ ] Never use a non-cryptographic RNG (e.g., `Math.random()`, `rand()`)

### Constant-Time Operations

- [ ] Master seal comparison
- [ ] Merkle root comparison
- [ ] Key commitment comparison
- [ ] Per-block plaintext hash comparison
- [ ] Attestation HMAC comparison
- [ ] Audit chain hash comparison
- [ ] All other security-sensitive comparisons

### IV / Nonce Uniqueness

- [ ] Each block has a unique 12-byte IV
- [ ] IVs are generated from a CSPRNG (not sequential, not derived)
- [ ] Never reuse an IV with the same key (catastrophic for GCM security)
- [ ] Note: because each block has a unique key (derived from index), IV collision across blocks is not a concern. However, each IV should still be random for defense in depth.

### Memory and Data Handling

- [ ] Master key zeroed from memory after use
- [ ] Derived keys zeroed after block decryption
- [ ] Plaintext zeroed if only verification (not extraction) is requested
- [ ] No logging of master keys, derived keys, or plaintext in production
- [ ] No logging of recipient IDs or canary parameters in production
- [ ] No logging of split-key share values in production

### Error Handling

- [ ] External error messages are generic ("file integrity verification failed")
- [ ] Internal error messages may be detailed for debugging
- [ ] Verification failures do not reveal which specific check failed to untrusted parties
- [ ] Partial decryption results are not returned on verification failure

### Input Validation

- [ ] Magic bytes validated before any parsing
- [ ] Block count validated against available file size
- [ ] Ciphertext lengths validated against remaining file data
- [ ] Filename length validated (max 255 bytes)
- [ ] Flags validated (reserved bits must be zero)
- [ ] Split-key threshold M >= 2 and M <= N and N <= 255
- [ ] Extended header field sizes validated before reading

---

## Split-Key Security Model

Shamir's Secret Sharing over GF(256) provides information-theoretic security:

- Any set of M or more shares can reconstruct the master key.
- Any set of fewer than M shares reveals **zero information** about the master key. This is not computational security -- it is mathematically provable.

### Assumptions

- Shares are distributed via secure channels.
- Shareholders do not collude (or at least, fewer than M collude).
- The CSPRNG used to generate polynomial coefficients is truly random.

### Limitations

- If exactly M shareholders collude, they can reconstruct the key without the knowledge or consent of the remaining N-M shareholders.
- The format does not enforce access control policies. It only provides the cryptographic mechanism.
- Share indices (x-coordinates) are not secret. Only the y-values are secret.

---

## Canary Trap Limitations

The canary trap system (SEC-4) provides leak tracing, not leak prevention.

### What It Can Do

- Given a leaked `.zgl` file and a list of candidate recipients, identify which recipient's copy was leaked.
- The identification is deterministic and unforgeable (based on HMAC with the master key).

### What It Cannot Do

- **Prevent copying:** A recipient can copy the file, extract the content, and redistribute it without the canary.
- **Identify unknown recipients:** The system requires a candidate list. If the leaker is not on the list, identification fails.
- **Survive format stripping:** If the content is extracted and redistributed in a different format (e.g., screenshot, re-typed), the canary is lost.
- **Work without the master key:** Canary identification requires the master key to compute expected padding.

### Best Practices

- Use authenticated, unforgeable recipient IDs: `HMAC-SHA256(company_key, "zegel-recipient-v1:" || user_id)`.
- Do not use self-reported identifiers (email addresses) directly.
- Maintain a secure mapping of recipient IDs to real identities.
- Combine canary traps with access controls, logging, and legal deterrents.

---

## Reporting Security Vulnerabilities

If you discover a security vulnerability in the Zegel format or any implementation, please follow the responsible disclosure process described in [SECURITY.md](../SECURITY.md).

Do not file public issues for security vulnerabilities.

---

## Further Reading

- [FORMAT_SPEC.md](../FORMAT_SPEC.md) -- Complete binary format specification
- [Architecture Overview](architecture.md) -- How the format works
- [Porting Guide](porting_guide.md) -- Implementation guidance
- [FAQ](faq.md) -- Common questions
- [RFC 5869](https://tools.ietf.org/html/rfc5869) -- HKDF specification
- [RFC 5116](https://tools.ietf.org/html/rfc5116) -- AEAD (AES-GCM) interface
- [NIST SP 800-38D](https://csrc.nist.gov/publications/detail/sp/800-38d/final) -- GCM specification
