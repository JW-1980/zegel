# Zegel FAQ

Frequently asked questions about the Zegel tamper-proof container format.

---

## General

### What is Zegel?

Zegel ("seal" in Dutch) is a tamper-proof container format. It wraps any file in a `.zgl` container where modifying a single byte after sealing makes the entire content physically unreadable. This is not a warning system -- the cryptographic math itself prevents decoding of tampered content.

The format is designed for document integrity, compliance, auditing, and secure distribution. It is specified in [FORMAT_SPEC.md](../FORMAT_SPEC.md) and is currently at version 1.2.

### How is this different from just hashing a file?

Traditional file hashing (e.g., computing a SHA-256 checksum) creates a "detect and warn" system. If the file is modified, the hash will not match, but the file content remains perfectly readable. A viewer application can display a warning, but a modified viewer can simply skip the check.

Zegel is fundamentally different: the file's integrity is woven into its encryption keys. The encryption key for each block is derived from a Merkle tree root hash that covers every block. If any byte changes, the root hash changes, which changes every encryption key, which causes AES-GCM authenticated decryption to reject. The content is not "flagged as modified" -- it is literally destroyed.

No viewer cooperation, policy enforcement, or external hash storage is needed. The math is self-enforcing.

### What file types can Zegel protect?

Any file of any type. Zegel is format-agnostic. It treats the source file as a sequence of bytes, splits it into blocks, and seals it. The original content type and filename are preserved in the header.

Common use cases include PDF documents, images, spreadsheets, database exports, legal contracts, medical records, and financial reports.

---

## Tampering and Integrity

### What happens if I modify a sealed `.zgl` file?

The content becomes permanently unreadable. Here is the chain of events:

1. You change one or more bytes in the `.zgl` file.
2. The block containing those bytes now has a different ciphertext.
3. During verification, the master seal (HMAC-SHA512 over the entire file) will not match. Verification stops with a "tampered" result.
4. Even if the seal check were bypassed, AES-256-GCM's authentication tag would reject decryption because the derived keys no longer match the ciphertext.
5. No content is returned. The file is cryptographically destroyed.

### Can I recover a tampered file?

No. That is the entire point of Zegel. There is no recovery mechanism, no backdoor, and no administrator override. If the file is tampered with, the content is gone.

If you need a backup, keep the original unsealed file or a separate copy of the `.zgl` file in a secure location.

### What if the file is corrupted accidentally (disk error, network glitch)?

Zegel treats accidental corruption identically to intentional tampering. The format cannot distinguish between the two. If even a single byte is flipped due to a hardware error, the file is unreadable.

This means Zegel files should be stored on reliable media and transferred using protocols with their own error correction. Consider keeping redundant copies.

### Does Zegel protect the header too?

Yes. The master seal (HMAC-SHA512) covers the entire file from the first byte (magic bytes) through the last ciphertext byte. Modifying any header field (flags, timestamp, content-type, filename, block directory, Merkle root) will cause the seal check to fail.

However, the header is not encrypted. An attacker can read (but not modify) the header without the master key.

---

## Encryption and Keys

### What encryption is used?

Each block is encrypted with **AES-256-GCM** (Advanced Encryption Standard with 256-bit keys in Galois/Counter Mode). This is authenticated encryption: it provides both confidentiality (content is secret) and integrity (tampering is detected by the GCM authentication tag).

Per-block encryption keys are derived using **HKDF** (HMAC-based Key Derivation Function, RFC 5869) with SHA-256. The inputs to HKDF are the master key, the Merkle root hash, the master salt, and the block index. This ensures each block has a unique key and all keys depend on the integrity of all blocks.

The entire file is sealed with **HMAC-SHA512**.

### Can I use a password instead of a key?

Yes. When the `PASSWORD_DERIVED` flag is set, the 32-byte master key is derived from a user-provided password using **Argon2id** (the winner of the Password Hashing Competition). Argon2id is resistant to both GPU attacks and side-channel attacks.

The Argon2id parameters (time cost and memory cost) are stored in the file header, so the reader can re-derive the same key from the same password.

Default parameters: 3 iterations, 64 MiB memory. For high-security applications, increase both values.

### What if I lose my master key?

The content is permanently inaccessible. There is no recovery mechanism, no master backdoor, and no way to reset the key. This is a deliberate design choice.

If you use password-based key derivation, forgetting the password has the same effect.

If you use split-key (M-of-N), losing too many shares (more than N-M) makes the key unrecoverable.

### How long is the master key?

The master key is always exactly 32 bytes (256 bits). It can be represented as 64 hexadecimal characters.

---

## Platform and Compatibility

### What platforms are supported?

The Zegel format is platform-independent. The reference implementation targets:

- **Desktop:** Windows, macOS, Linux (CLI and GUI applications)
- **Mobile:** Android, iOS (GUI application)

The format specification is open, so any platform with the required cryptographic primitives (AES-256-GCM, SHA-256, HMAC) can implement a reader or writer.

### Can I open a `.zgl` file created on Windows on my Mac?

Yes. The `.zgl` format uses big-endian byte order and platform-independent encoding throughout. A file created on any platform can be verified and extracted on any other platform.

### Is there a web-based viewer?

A browser-based verifier is technically possible using the Web Crypto API. However, key management in browsers is inherently less secure than native applications. The recommended approach is to use the native desktop or mobile application.

---

## Advanced Features

### Can I share specific parts of a sealed file?

Yes. **Selective disclosure** (GEN-9) allows you to generate a token that grants access to specific blocks without revealing the master key. The token contains per-block derived keys for only the selected blocks.

For example, if a document has 10 content blocks, you can generate a token for blocks 3 and 7. The token holder can decrypt only those blocks. They cannot derive keys for the other blocks because they do not have the master key.

See [Selective Disclosure Guide](features/selective_disclosure.md).

### Can multiple people need to agree to open a file?

Yes. **Split-key** (SEC-6) uses Shamir's Secret Sharing to split the master key into N shares, of which any M are required to reconstruct the key. For example, with a 3-of-5 split, any 3 of the 5 shareholders can reconstruct the key, but 2 or fewer shares reveal absolutely no information about the key.

This is useful for scenarios like:
- 2-of-3 for business continuity (CEO, CFO, legal counsel)
- 3-of-5 for board approval
- 2-of-2 for dual control (both parties must agree)

See [Split Key Guide](features/split_key.md).

### How do I trace a leaked copy?

**Canary trap fingerprinting** (SEC-4) embeds invisible, recipient-specific padding in each content block. When distributing a confidential document to multiple people, seal a separate copy for each recipient with their unique recipient ID.

If a copy is leaked, provide the leaked file and the list of candidate recipients. The system computes the expected padding for each candidate and matches it against the leaked file to identify the source.

See [Canary Traps Guide](features/canary_traps.md).

### Can I permanently remove parts of a sealed file?

Yes. **Partial redaction** (SEC-5) permanently destroys selected blocks while preserving the Merkle tree integrity of the remaining file. The original plaintext hash of each redacted block is kept in the directory (so the Merkle root remains valid), but the ciphertext is replaced with random bytes.

Redaction is irreversible. The original content of redacted blocks cannot be recovered.

See [Redaction Guide](features/redaction.md).

### How does the audit trail work?

The **audit trail** (GEN-8) is a hash-chained append-only log embedded within the `.zgl` file. Each entry records an action (sealed, verified, redacted, attested, disclosed), the actor, a timestamp, and a chain hash computed as `SHA-256(previous_chain_hash || entry_json)`.

Verifiers recompute the chain hashes and reject the audit trail if any hash is inconsistent. This makes the log tamper-evident: entries cannot be modified, reordered, or deleted without breaking the chain.

See [Audit Trail Guide](features/audit_trail.md).

---

## Limits and Sizing

### What is the maximum file size?

The theoretical maximum is determined by the block count (uint32, max ~4.29 billion blocks) and per-block ciphertext size (uint32, max ~4.29 GB per block). With the default 64 KB block size, the theoretical limit is approximately 256 TB.

In practice, file size is limited by available memory and processing time. Implementations should impose practical limits (the recommended default is 100 MB, configurable upward).

### How much overhead does sealing add?

For a single-block file (under 64 KB), the overhead is approximately:

| Component | Size |
|-----------|------|
| Header (fixed + variable) | ~122 bytes + filename length |
| Block directory (1 block) | 65 bytes |
| Merkle root | 32 bytes |
| Master seal | 64 bytes |
| GCM overhead per block | ~0 bytes (GCM ciphertext is same length as plaintext; tag is in the directory) |
| **Total overhead** | **~283 bytes + filename length** |

For multi-block files, add 65 bytes per additional block (directory entry). The percentage overhead decreases as file size increases.

### What is the default block size?

65,536 bytes (64 KB). This is configurable by implementations. Smaller blocks increase the Merkle tree granularity (useful for selective disclosure and redaction) but increase overhead. Larger blocks reduce overhead but make partial operations less granular.

---

## Licensing and Community

### Is this open source?

Yes. Zegel is dual-licensed:

- **Code** (implementations): Apache License 2.0
- **Specification** (FORMAT_SPEC.md): Creative Commons Attribution 4.0 International (CC BY 4.0)
- **Test vectors**: CC0 (public domain)

Anyone can implement the format, build commercial products, and distribute them freely under these licenses.

### Can I implement Zegel in my own language?

Absolutely. The format is designed to be language-agnostic. See the [Porting Guide](porting_guide.md) for step-by-step instructions, common pitfalls, and language-specific recommendations.

### How do I report a security vulnerability?

Please follow the responsible disclosure process described in [SECURITY.md](../SECURITY.md). Do not file public issues for security vulnerabilities.

### How can I contribute?

See [CONTRIBUTING.md](../CONTRIBUTING.md) for contribution guidelines. Contributions welcome in areas including:

- New language implementations
- Test vector expansion
- Documentation improvements
- GUI/UX improvements
- Security review

---

## Further Reading

- [FORMAT_SPEC.md](../FORMAT_SPEC.md) -- Complete binary format specification
- [Architecture Overview](architecture.md) -- How the format works (with diagrams)
- [Porting Guide](porting_guide.md) -- Implementing in another language
- [Security Audit](security_audit.md) -- Security considerations and threat model
