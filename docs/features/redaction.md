# SEC-5: Partial Redaction

This guide explains how to use Zegel's partial redaction feature to permanently remove selected blocks from a sealed file while preserving the integrity and verifiability of the remaining content.

For the specification, see [FORMAT_SPEC.md Section 6.2](../../FORMAT_SPEC.md#62-sec-5-partial-redaction).

---

## What Is Partial Redaction?

Partial redaction permanently destroys the content of selected blocks within a sealed `.zgl` file, while keeping the rest of the file intact and verifiable.

After redaction:
- The redacted blocks' ciphertext is replaced with cryptographically random bytes.
- The original plaintext hashes are preserved in the block directory.
- The Merkle tree remains valid (because the original leaf hashes are unchanged).
- Non-redacted blocks decrypt normally.
- The master seal is recomputed over the modified file.
- The `FLAG_HAS_REDACTIONS` flag (bit 8, mask `0x0100`) is set.
- Redacted blocks have block type `0x06` (REDACTED).

Redaction is **irreversible**. The original content of redacted blocks cannot be recovered from the redacted file.

---

## Use Case

Partial redaction is designed for scenarios where you need to share a sealed document but must remove certain sections:

- **FOIA (Freedom of Information Act) requests:** Release government documents with classified or personal information redacted, while proving the remaining content is unmodified.
- **Legal discovery:** Produce documents for litigation with privileged or irrelevant sections removed, while the court can verify the remaining sections are authentic.
- **Privacy compliance (GDPR, CCPA):** Remove personally identifiable information from a sealed record while maintaining an audit trail of what was redacted and when.
- **Selective release:** Share a multi-section report with certain sections removed for different audiences.

The key advantage over simply editing a document is that the Zegel Merkle tree proves the non-redacted content has not been altered since the original sealing.

---

## How It Works

### Redaction Process

```
 Original .zgl File
 +--------+--------+--------+--------+--------+
 |Block 0 |Block 1 |Block 2 |Block 3 |Block 4 |
 | META   |CONTENT |CONTENT |CONTENT |CONTENT |
 +--------+--------+--------+--------+--------+

           Redact blocks 1 and 3
                   |
                   v

 Redacted .zgl File
 +--------+--------+--------+--------+--------+
 |Block 0 |Block 1 |Block 2 |Block 3 |Block 4 |
 | META   |REDACTED|CONTENT |REDACTED|CONTENT |
 +--------+--------+--------+--------+--------+
```

The redaction process, step by step:

1. **Verify the original file** is intact (full verification with the master key).
2. For each block to redact:
   a. Replace the ciphertext with `random_bytes(ciphertext_length)` from a CSPRNG.
   b. Change the block type in the directory to `0x06` (REDACTED).
   c. **Keep** the original plaintext hash, IV, and auth tag in the directory. These are no longer usable for decryption, but the plaintext hash is essential for Merkle tree integrity.
3. Set the `FLAG_HAS_REDACTIONS` flag in the header.
4. Recompute the master seal over the modified file.

### Why the Merkle Tree Still Works

The Merkle tree is built from the plaintext hashes stored in the block directory. During redaction, these hashes are preserved even though the ciphertext is replaced. Therefore:

- The Merkle root computed from the directory hashes matches the stored Merkle root.
- The stored Merkle root is the same as the original file's Merkle root.
- A verifier can confirm that the non-redacted blocks are identical to the original file's blocks.

### What Changes in the File

| Component | Original | After Redaction |
|-----------|----------|-----------------|
| Header flags | `0x____` | `0x____ \| 0x0100` (HAS_REDACTIONS set) |
| Block type (redacted blocks) | `0x01` (CONTENT) | `0x06` (REDACTED) |
| Plaintext hash (redacted blocks) | SHA-256 of original | **Unchanged** |
| Ciphertext (redacted blocks) | Encrypted content | **Random bytes** |
| IV, auth tag (redacted blocks) | Original values | **Unchanged** (but no longer functional) |
| Merkle root | Original | **Unchanged** |
| Master seal | Original HMAC | **Recomputed** (file bytes changed) |

---

## How to Redact

### CLI

```bash
# Redact blocks 1 and 3 from a sealed file
zegel redact document.zgl \
  -k master.key \
  --blocks 1,3 \
  -o document_redacted.zgl
```

The `--blocks` flag takes a comma-separated list of zero-indexed block numbers to redact. The original file is not modified; a new file is created.

To see which blocks exist and their types:

```bash
zegel inspect document.zgl
```

This displays the block directory without requiring the master key, showing block indices, types, and sizes.

### GUI

1. Open the Zegel application and navigate to the Redact screen.
2. Load the `.zgl` file and enter the master key.
3. The application displays a list of blocks with their types, sizes, and (for content blocks) a preview of the decrypted content.
4. Select the blocks to redact using checkboxes.
5. Click "Redact Selected Blocks."
6. Confirm the irreversibility warning.
7. Save the redacted file.

---

## Verification of Redacted Files

A redacted `.zgl` file can be verified like any other Zegel file, with the following behavior:

1. The master seal is verified against the modified file bytes. This confirms the file has not been tampered with since redaction.
2. The Merkle root is rebuilt from the block directory hashes. Since original hashes are preserved, the root matches.
3. Non-redacted blocks are decrypted and verified normally.
4. Redacted blocks (type `0x06`) are skipped during decryption. They are reported as redacted.

```bash
zegel verify document_redacted.zgl -k master.key

# Output:
# Status: VALID
# Blocks: 5 total, 2 redacted
# Block 0: METADATA (intact)
# Block 1: REDACTED
# Block 2: CONTENT (intact)
# Block 3: REDACTED
# Block 4: CONTENT (intact)
```

### Proving Non-Modification

The fact that the Merkle root is unchanged between the original and redacted files proves that:
- The non-redacted blocks have the exact same content as the original.
- No blocks were added, removed, or reordered.
- The only change is the replacement of selected blocks' ciphertext with random data.

A third party with access to both the original and redacted Merkle roots can confirm they are identical.

---

## Irreversibility Warning

Redaction is a **one-way operation**. Once a block is redacted:

- The ciphertext is replaced with random bytes. The original encrypted data is gone.
- The encryption key for the redacted block still exists (it can be derived from the master key), but there is nothing meaningful to decrypt.
- The original plaintext cannot be recovered from the redacted file.
- There is no "undo" operation.

To preserve the original content, keep a separate, unredacted copy of the `.zgl` file in a secure location before performing redaction.

---

## Best Practices

### Pre-Redaction Verification

Always verify the original file before redacting. Redacting a tampered file produces a file that appears valid but contains corrupted data in the non-redacted blocks.

### Document What Was Redacted

Use the audit trail feature (GEN-8) to record:
- Which blocks were redacted
- Who performed the redaction
- When the redaction occurred
- The legal or policy basis for the redaction

### Preserve the Original

Keep the unredacted `.zgl` file in a secure, access-controlled location. The redacted version is for distribution; the original is for internal records or future legal proceedings where full disclosure may be required.

### Block Granularity

Since redaction operates at the block level (default 64 KB), consider the block size when sealing files intended for later redaction. Smaller blocks (e.g., 4 KB or 16 KB) provide finer granularity for redaction but increase overhead.

For documents where specific paragraphs or pages may need redaction, consider:
- Using smaller block sizes during sealing.
- Structuring multi-section documents so that each section starts at a block boundary.
- Using multi-file containers where each section is a separate sub-file.

### Chained Redaction

Multiple rounds of redaction can be applied to the same file. Each round:
- Sets the `FLAG_HAS_REDACTIONS` flag (already set after the first round).
- Changes additional blocks to type `0x06`.
- Recomputes the master seal.

Previously redacted blocks cannot be "re-redacted" (they are already destroyed), but they are harmlessly skipped.

---

## Interaction with Other Features

### Redaction + Canary Traps

When redacting a file with canary fingerprinting, the canary padding in redacted blocks is destroyed along with the content. Leak identification can still work using the non-redacted blocks, as long as enough blocks remain to produce a reliable match.

### Redaction + Selective Disclosure

Selective disclosure tokens for redacted blocks are useless (the ciphertext is random data). Tokens for non-redacted blocks continue to work normally. If you intend to use selective disclosure after redaction, generate tokens only for non-redacted blocks.

### Redaction + Audit Trail

Redaction should be recorded in the audit trail. The audit entry for a redaction action includes the list of redacted block indices and the actor who performed the redaction.

### Redaction + Multi-File Containers

In a multi-file container (`FLAG_MULTI_FILE`), you can redact blocks belonging to specific sub-files while leaving others intact. Be careful not to redact file header blocks (type `0x04`) unless you intend to remove the entire sub-file's metadata.

---

## Further Reading

- [FORMAT_SPEC.md Section 6.2](../../FORMAT_SPEC.md#62-sec-5-partial-redaction) -- Specification
- [Security Audit](../security_audit.md) -- Security considerations
- [Audit Trail Guide](audit_trail.md) -- Logging redaction actions
- [Selective Disclosure Guide](selective_disclosure.md) -- Sharing specific blocks
- [Canary Traps Guide](canary_traps.md) -- Leak tracing interaction
