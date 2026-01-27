# SEC-4: Canary Trap / Recipient Fingerprinting

This guide explains how to use Zegel's canary trap feature to trace leaked copies of confidential documents back to their source.

For the specification, see [FORMAT_SPEC.md Section 6.1](../../FORMAT_SPEC.md#61-sec-4-canary-trap--recipient-fingerprinting).

---

## What Are Canary Traps?

A canary trap is an invisible, per-recipient fingerprint embedded in a sealed file. When you distribute the same document to multiple people, each person receives a version with unique, invisible padding in every content block. The content itself is identical, but the cryptographic fingerprint differs per recipient.

If one of those copies is later found in an unauthorized location (leaked), you can determine which recipient's copy was leaked by comparing the file's padding against the known recipients.

The term "canary trap" comes from intelligence tradecraft, where slightly different versions of a document are given to suspected leakers to identify the source.

---

## Use Case

You are distributing a confidential board report to five board members. You want to know who leaked it if a copy appears outside the organization.

1. Seal the document five times, once per board member, each with a unique recipient ID.
2. Distribute each copy to the corresponding board member.
3. If a copy surfaces publicly, run leak identification with all five recipient IDs.
4. The system identifies which board member's copy was leaked.

---

## How It Works Technically

When the `FLAG_HAS_CANARY` flag (bit 7, mask `0x0080`) is set, each content block has deterministic padding appended before encryption.

### Padding Generation

For each content block at index `i`:

```
mac     = HMAC-SHA256(master_key, recipient_id || pack_uint32_be(block_index))
pad_len = (mac[0] % 16) + 1                // 1 to 16 bytes
padding = mac[1 .. pad_len-1] || byte(pad_len)   // PKCS#7-style length marker
```

The padding is:
- **Deterministic:** same inputs always produce the same padding.
- **Unique per recipient:** different recipient IDs produce different HMAC outputs.
- **Unique per block:** the block index is included in the HMAC input.
- **Invisible:** the padding is stripped during extraction. The extracted content is identical regardless of recipient.

### Recipient ID

A 32-byte value stored in the extended header. It uniquely identifies the intended recipient of this particular copy.

### Leak Identification

Given a leaked file and a list of candidate recipient IDs:

1. For each candidate recipient ID, compute the expected padding for each content block.
2. Decrypt the leaked file's content blocks (requires the master key).
3. Compare the actual padding at the end of each block against the expected padding for each candidate.
4. The candidate whose expected padding matches the actual padding across all blocks is the leak source.

---

## How to Seal with Canary Fingerprinting

### CLI

```bash
# Generate a unique recipient ID for each person
# Recommended: derive from an authenticated user identifier
zegel seal report.pdf \
  -k master.key \
  -o report_alice.zgl \
  --canary-recipient "alice@example.com"

zegel seal report.pdf \
  -k master.key \
  -o report_bob.zgl \
  --canary-recipient "bob@example.com"
```

The `--canary-recipient` flag sets the `FLAG_HAS_CANARY` flag and stores the recipient ID in the extended header. The recipient string is hashed internally to produce the 32-byte recipient ID.

### GUI

1. Open the Zegel application and navigate to the Seal screen.
2. Select the source file.
3. Enter or load the master key.
4. Expand the "Advanced Options" section.
5. Enable "Canary Trap Fingerprinting."
6. Enter the recipient identifier (e.g., email address or employee ID).
7. Click "Seal."
8. Repeat for each recipient with a different identifier.

---

## How to Identify a Leaked Copy

### CLI

```bash
zegel identify-canary leaked_file.zgl \
  -k master.key \
  --candidates "alice@example.com,bob@example.com,carol@example.com"
```

The command outputs the matching recipient identifier, or reports that no candidate matches.

### GUI

1. Open the Zegel application and navigate to the Verify screen.
2. Load the leaked `.zgl` file.
3. Enter the master key.
4. Click "Identify Canary Recipient."
5. Enter the list of candidate recipient identifiers.
6. The application displays the matching recipient, or indicates no match.

---

## Limitations

### Requires a Candidate List

Canary identification is not open-ended. You must provide a list of candidate recipient IDs. If the leak source is not in the list (e.g., an unknown attacker obtained the file through a different channel), identification will fail.

### Does Not Prevent Copying

Canary traps are a tracing mechanism, not a prevention mechanism. A recipient can:
- Copy the `.zgl` file and share it (traceable).
- Extract the content and share the extracted file (not traceable -- the canary is in the Zegel container, not the content).
- Screenshot, print, or re-type the content (not traceable).

### Requires the Master Key

Leak identification requires the master key to decrypt blocks and compare padding. If the master key is not available, identification is not possible.

### Same Master Key Across Copies

All copies for different recipients must use the same master key. This is because the canary padding is derived from `HMAC-SHA256(master_key, ...)`. The Merkle roots will differ between copies (because the padding changes the block content), but the master key is shared.

---

## Best Practices for Recipient ID Generation

### Recommended: Derived from Authenticated Identifiers

Use an HMAC-based derivation from a company secret and an authenticated user identifier:

```
recipient_id = HMAC-SHA256(company_key, "zegel-recipient-v1:" || user_id)
```

This approach:
- Produces a 32-byte ID that fits the extended header.
- Is deterministic: the same user always gets the same ID.
- Is unforgeable: without the company key, an attacker cannot produce a valid recipient ID.
- Is tied to the authentication system: the `user_id` comes from the company's user database, not self-reported input.

### Not Recommended: Direct Use of Email Addresses

Using raw email addresses or names as recipient IDs is fragile:
- Email addresses can change.
- Users can self-report false addresses.
- Raw strings may exceed or underuse the 32-byte field.

Always derive the recipient ID from an authenticated source.

### Record Keeping

Maintain a secure, internal mapping of:
- Recipient ID (hex) to real identity (name, user ID)
- Which files were distributed to which recipients
- Timestamps of distribution

This mapping is essential for leak identification and may be needed for legal proceedings.

---

## Interaction with Other Features

### Canary + Split-Key

Canary traps and split-key (SEC-6) can be used together. The canary padding is applied using the reconstructed master key. The recipient ID is stored in the extended header as usual.

### Canary + Compression

When both `FLAG_COMPRESSED` and `FLAG_HAS_CANARY` are set, the processing order is:
1. Compress the block content (zlib).
2. Append canary padding.
3. Hash the result (for the Merkle tree).
4. Encrypt.

On extraction, the reverse order applies: decrypt, verify hash, strip canary padding, decompress.

### Canary + Redaction

Redacted blocks have their ciphertext replaced with random bytes. The canary padding in a redacted block is destroyed along with the content. Leak identification can still work using the remaining non-redacted blocks.

---

## Further Reading

- [FORMAT_SPEC.md Section 6.1](../../FORMAT_SPEC.md#61-sec-4-canary-trap--recipient-fingerprinting) -- Specification
- [Security Audit](../security_audit.md) -- Canary trap limitations and threat model
- [Split Key Guide](split_key.md) -- Multi-party key management
- [Redaction Guide](redaction.md) -- Partial content removal
