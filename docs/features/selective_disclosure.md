# GEN-9: Selective Disclosure

This guide explains how to use Zegel's selective disclosure feature to share specific blocks of a sealed file with third parties without revealing the master key or the content of other blocks.

For the specification, see [FORMAT_SPEC.md Section 7.4](../../FORMAT_SPEC.md#74-gen-9-selective-disclosure).

---

## What Is Selective Disclosure?

Selective disclosure allows the holder of a Zegel master key to generate a **disclosure token** that grants access to specific blocks of a sealed file. The token contains per-block derived keys for only the selected blocks. The token recipient can decrypt those blocks but cannot access any other blocks or derive any other keys.

This is different from redaction:
- **Redaction** removes content permanently. The redacted file is distributed, and everyone sees the same thing.
- **Selective disclosure** keeps the file intact. Different tokens can grant access to different subsets of blocks. The file is shared as-is, and different recipients can see different parts.

---

## Use Case

Selective disclosure is useful when different parties need access to different parts of the same sealed document:

- **Auditors** receive a token for the financial summary blocks (e.g., blocks 0-5) but not the personal data blocks.
- **Legal counsel** receives a token for the contract terms blocks but not the proprietary technology details.
- **Regulators** receive a token for compliance-relevant sections only.
- **Researchers** receive a token for the anonymized data sections but not the identifying information.

In all cases, the sealed file is identical. Only the token differs.

---

## How Tokens Work

### Token Structure

A disclosure token is a JSON document containing per-block derived keys for the disclosed blocks:

```json
{
  "version": 1,
  "merkle_root": "a1b2c3d4...64 hex chars...",
  "block_keys": {
    "0": "e5f6a7b8...64 hex chars...",
    "3": "c9d0e1f2...64 hex chars..."
  },
  "created_at": 1706367600
}
```

| Field | Description |
|-------|-------------|
| `version` | Token format version (currently 1) |
| `merkle_root` | Hex-encoded Merkle root of the target file. Used to verify the token matches the file. |
| `block_keys` | Map of block index (as string) to hex-encoded 32-byte per-block key. |
| `created_at` | Unix timestamp of token creation. |

### Per-Block Keys

Each key in the `block_keys` map is the same key that the writer computed via HKDF for that block. The token simply exposes specific per-block keys without exposing the master key.

```
master_key + merkle_root --[HKDF]--> block_key[i]
```

The token recipient receives `block_key[i]` directly. They can use it with the block's IV and ciphertext to decrypt, but they cannot reverse-engineer the master key from individual block keys (HKDF is a one-way function).

### What the Token Holder Can Do

- Decrypt the blocks listed in the token.
- Verify the Merkle root matches the file.
- Confirm the block plaintext hashes match after decryption.

### What the Token Holder Cannot Do

- Decrypt blocks not listed in the token.
- Derive the master key from the block keys.
- Generate tokens for other blocks.
- Modify the file (the master seal requires the master key to recompute).

---

## How to Generate Tokens

### CLI

```bash
# Generate a disclosure token for blocks 0 and 2
zegel disclose document.zgl \
  -k master.key \
  --blocks 0,2 \
  -o token_auditor.json
```

The `--blocks` flag takes a comma-separated list of zero-indexed block numbers. The output is a JSON file containing the token.

To see available blocks:

```bash
zegel inspect document.zgl

# Output:
# Block 0: METADATA (encrypted, 342 bytes)
# Block 1: CONTENT (encrypted, 65536 bytes)
# Block 2: CONTENT (encrypted, 65536 bytes)
# Block 3: CONTENT (encrypted, 28190 bytes)
```

### GUI

1. Open the Zegel application and navigate to the Disclose screen.
2. Load the `.zgl` file and enter the master key.
3. The application displays a list of blocks with their types and sizes.
4. Select the blocks to include in the disclosure token.
5. Click "Generate Token."
6. Save the token file.

---

## How to Extract with a Token

### CLI

```bash
# Extract using a disclosure token instead of the master key
zegel extract-with-token document.zgl \
  --token token_auditor.json \
  -o extracted/
```

The command extracts only the blocks listed in the token. Other blocks are reported as inaccessible.

### GUI

1. Open the Zegel application and navigate to the Extract screen.
2. Load the `.zgl` file.
3. Instead of entering a master key, select "Use Disclosure Token."
4. Load the token file.
5. The application displays which blocks are accessible and which are not.
6. Click "Extract Accessible Blocks."
7. Save the output.

---

## Security Properties

### Token Granularity

Tokens operate at the block level. If you need finer granularity (e.g., specific paragraphs within a block), consider using smaller block sizes when sealing the file.

### Token Independence

Multiple tokens can be generated for the same file with different block sets. Each token is independent and works without knowledge of other tokens.

### Token Permanence

A disclosure token grants permanent access to the specified blocks. There is no built-in expiration or revocation mechanism for tokens. Treat tokens with the same care as encryption keys.

If the file has the `FLAG_HAS_EXPIRATION` flag set, the per-block keys in the token include the expiration date in their derivation. After the file's expiration date, the block keys in the token will not match -- effectively expiring the token along with the file.

### No Key Escalation

The token holder cannot escalate access. Per-block keys are derived via HKDF, which is a one-way function. Knowing `block_key[3]` does not help compute `block_key[4]` or the master key.

### Merkle Root Binding

The token includes the Merkle root of the target file. Before using a token, verify that the file's Merkle root matches the token's. This prevents using a token intended for one file on a different file that happens to share the same master key.

---

## Token Distribution Best Practices

### Secure Transmission

Disclosure tokens contain encryption keys. Distribute them via secure channels:
- Encrypted email (PGP/S/MIME)
- Secure messaging (Signal, etc.)
- In-person handoff
- Secure file transfer (SFTP, encrypted archive)

### Access Logging

Record which tokens were generated, for which blocks, for which recipients, and when. Use the audit trail feature (GEN-8) to embed this information in the `.zgl` file itself.

### Minimal Disclosure

Generate tokens containing only the blocks the recipient needs. Do not include unnecessary blocks. This follows the principle of least privilege.

### Separate File and Token

Distribute the `.zgl` file and the disclosure token through separate channels when possible. An attacker who intercepts only the file or only the token gains nothing.

### Token Naming

Use descriptive filenames for tokens to avoid confusion:
```
document_token_auditor_blocks_0_2.json
document_token_legal_blocks_0_5.json
```

---

## Interaction with Other Features

### Selective Disclosure + Redaction

If blocks have been redacted, their ciphertext is random data. A disclosure token for a redacted block is useless -- the key will decrypt random bytes, not meaningful content. Generate tokens only for non-redacted blocks.

The token holder can detect redacted blocks by checking the block type in the directory (type `0x06`).

### Selective Disclosure + Canary Traps

If the file has canary fingerprinting, disclosed content blocks will include the canary padding. The token holder will see the padding as part of the decrypted content (since they do not have the master key, they cannot compute the expected padding to strip it). To avoid this, the token generator can strip canary padding and include it in the token metadata, or advise the token holder about the trailing padding bytes.

### Selective Disclosure + Metadata

The metadata block (index 0, if present) is an encrypted JSON block like any other. It can be included in a disclosure token, allowing the token holder to read the file's metadata without the master key.

### Selective Disclosure + Split-Key

To generate a disclosure token, the master key must be available. If the key is split (SEC-6), reconstruct it from M shares first, then generate the token. The token itself is not split -- it is a single JSON document.

### Selective Disclosure + Compression

If the file uses compression (`FLAG_COMPRESSED`), the token holder must decompress content blocks after decryption, just like a regular reader. The compression flag is visible in the header (no key required).

---

## Disclosure Index Block

When the `FLAG_SELECTIVE_DISCLOSURE` flag (bit 10, mask `0x0400`) is set, the file contains a disclosure index block (type `0x0A`). This block is encrypted and lists which blocks are intended for selective disclosure.

The disclosure index is informational -- it does not restrict token generation. The master key holder can generate tokens for any block regardless of the index. The index serves as a guide for applications to present meaningful options to the user.

---

## Further Reading

- [FORMAT_SPEC.md Section 7.4](../../FORMAT_SPEC.md#74-gen-9-selective-disclosure) -- Specification
- [Security Audit](../security_audit.md) -- Security considerations
- [Redaction Guide](redaction.md) -- Permanent content removal
- [Audit Trail Guide](audit_trail.md) -- Logging disclosure actions
- [Split Key Guide](split_key.md) -- Multi-party key management
