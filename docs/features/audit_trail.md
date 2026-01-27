# GEN-8: Tamper-Evident Audit Trail

This guide explains how to use Zegel's audit trail feature to maintain a hash-chained, tamper-evident log of actions performed on a sealed file.

For the specification, see [FORMAT_SPEC.md Section 7.3](../../FORMAT_SPEC.md#73-gen-8-tamper-evident-audit-trail).

---

## What Is the Audit Trail?

The audit trail is an append-only, hash-chained log embedded within a `.zgl` file as audit blocks (type `0x09`). Each entry records an action, the actor who performed it, a timestamp, optional details, and a chain hash that cryptographically links it to the previous entry.

The chain hash ensures that audit entries cannot be modified, reordered, deleted, or inserted without detection. This provides tamper-evidence for the log itself, on top of the tamper-proof protection Zegel provides for the file content.

---

## Use Case

The audit trail is designed for scenarios requiring a verifiable record of actions:

- **Regulatory compliance:** Demonstrate to auditors that a document has been handled according to policy. The audit trail shows who sealed, verified, redacted, or attested the file, and when.
- **Forensic analysis:** Investigate the chain of custody for a document. The audit trail provides a chronological record of every significant action.
- **Chain of custody:** Prove that a document passed through specific hands in a specific order, with each handoff recorded and cryptographically linked.
- **Legal proceedings:** Provide evidence that a document was reviewed and approved by specific parties at specific times.
- **Internal controls:** Track who accessed, redacted, or shared parts of a sealed document.

---

## How Chain Hashes Work

Each audit entry contains a `chain_hash` field computed as follows:

```
chain_hash[0] = SHA-256(zeros_32_bytes || entry_0_json)
chain_hash[n] = SHA-256(chain_hash[n-1] || entry_n_json)
```

Where:
- `zeros_32_bytes` is a 32-byte buffer of all zeros (the initial "previous" hash).
- `entry_n_json` is the UTF-8 JSON encoding of the entry (without the `chain_hash` field).
- `||` denotes byte concatenation.

This forms a hash chain:

```
  32 zero bytes     entry_0 JSON
       |                 |
       +--------+--------+
                |
                v
  chain_hash[0] = SHA-256(zeros || entry_0)
       |
       |            entry_1 JSON
       |                 |
       +--------+--------+
                |
                v
  chain_hash[1] = SHA-256(chain_hash[0] || entry_1)
       |
       |            entry_2 JSON
       |                 |
       +--------+--------+
                |
                v
  chain_hash[2] = SHA-256(chain_hash[1] || entry_2)
       |
       ...
```

### Why This Provides Tamper-Evidence

- **Modification:** Changing any field in entry N changes its JSON, which changes `chain_hash[N]`, which changes `chain_hash[N+1]`, and so on. All subsequent hashes become invalid.
- **Deletion:** Removing entry N breaks the chain: `chain_hash[N+1]` was computed from `chain_hash[N]`, which no longer exists.
- **Insertion:** Inserting a new entry between N and N+1 changes the chain hash for the inserted entry, which invalidates `chain_hash[N+1]` and all subsequent entries.
- **Reordering:** Swapping entries N and M changes the inputs to their chain hashes, invalidating both and all subsequent entries.

---

## Audit Entry Format

Each audit block (type `0x09`) contains a JSON object with the following fields:

```json
{
  "actor": "user:42:admin@example.com",
  "action": "sealed",
  "timestamp": 1706367600,
  "details": {
    "content_type": "application/pdf",
    "block_count": 5,
    "features": ["metadata", "compression"]
  },
  "chain_hash": "a1b2c3d4e5f6...64 hex characters..."
}
```

| Field | Type | Description |
|-------|------|-------------|
| `actor` | string | Identifier of the person or system that performed the action. Recommended format: `"user:ID:email"` or `"system:service_name"`. |
| `action` | string | One of the supported action types (see below). |
| `timestamp` | integer | Unix epoch seconds when the action was performed. |
| `details` | object | Action-specific metadata (optional). |
| `chain_hash` | string | 64-character hex-encoded SHA-256 hash linking to the previous entry. |

---

## Supported Actions

| Action | Description | Typical Details |
|--------|-------------|-----------------|
| `sealed` | File was initially sealed | Content type, block count, features enabled |
| `verified` | File was verified (integrity check passed) | Verifier identity, result |
| `redacted` | One or more blocks were redacted | List of redacted block indices |
| `attested` | A co-signature attestation was added | Signer ID, statement |
| `disclosed` | A selective disclosure token was generated | Block indices included in the token, recipient |

Implementations may define additional action types for application-specific events. Unknown action types should be preserved (not discarded) during processing.

---

## Verification of Chain Integrity

To verify the audit trail:

1. Collect all audit blocks from the file, in order of appearance.
2. For the first entry: compute `SHA-256(zeros_32_bytes || entry_0_json_without_chain_hash)` and compare with the stored `chain_hash`.
3. For each subsequent entry: compute `SHA-256(previous_chain_hash || entry_n_json_without_chain_hash)` and compare with the stored `chain_hash`.
4. If any hash does not match, the audit trail has been tampered with.

### Computing Entry JSON Without Chain Hash

When computing the chain hash for verification, the `chain_hash` field itself is excluded from the JSON used as input to SHA-256. The remaining fields (`actor`, `action`, `timestamp`, `details`) are serialized to JSON in a canonical order.

### CLI

```bash
zegel verify document.zgl -k master.key --verify-audit

# Output:
# Audit trail: 4 entries, chain VALID
# Entry 0: sealed by user:42:admin@example.com at 2026-01-15T10:00:00Z
# Entry 1: verified by user:7:auditor@example.com at 2026-01-16T14:30:00Z
# Entry 2: attested by user:12:cfo@example.com at 2026-01-17T09:15:00Z
# Entry 3: redacted by user:42:admin@example.com at 2026-01-20T11:00:00Z
```

### GUI

1. Open the Zegel application and navigate to the Verify screen.
2. Load the `.zgl` file and enter the master key.
3. After verification, scroll to the "Audit Trail" section.
4. The application displays a timeline of all audit entries with validity indicators.
5. Each entry shows the actor, action, timestamp, and details.
6. A green indicator means the chain hash is valid; a red indicator means tampering was detected.

---

## Integration with Attestations

Audit trail entries and co-signature attestations (GEN-6) serve complementary purposes:

- **Attestations** are cryptographic statements by third parties about the file's integrity. They are verified using the signer's key and prove that a specific person reviewed the file.
- **Audit entries** are chronological records of actions. They record that an attestation was added, when, and by whom.

A typical workflow:

1. File is sealed. Audit entry: `{"action": "sealed", ...}`.
2. Reviewer verifies the file. Audit entry: `{"action": "verified", ...}`.
3. Reviewer adds an attestation block. Audit entry: `{"action": "attested", "details": {"signer_id": "...", "statement": "Reviewed and approved"}}`.
4. The attestation block (type `0x07`) contains the cryptographic HMAC.
5. The audit entry records that the attestation was added.

Both the attestation and the audit entry are encrypted blocks within the `.zgl` file. The Merkle tree covers both, and the master seal covers the entire file.

---

## Best Practices for Audit Logging

### Record Every Significant Action

Add audit entries for:
- Initial sealing
- Every verification (even routine checks)
- Every redaction
- Every attestation
- Every selective disclosure token generation
- Any failed verification attempt (with details about what failed)

### Use Authenticated Actor Identifiers

The `actor` field should use authenticated identifiers tied to your authentication system:
```
"user:42:admin@example.com"    // Database user ID + email
"system:backup-service"        // Automated system identifier
"api:client-id-xyz"            // API client identifier
```

Do not use self-reported or unverified identifiers.

### Include Relevant Details

The `details` object should contain enough information to reconstruct what happened:

```json
{
  "action": "redacted",
  "details": {
    "blocks_redacted": [1, 3, 5],
    "reason": "FOIA exemption 6 - personal privacy",
    "authorization": "legal-review-2026-0142"
  }
}
```

### Preserve Audit Trails During Operations

When performing operations that modify the file (redaction, adding attestations), the existing audit trail entries must be preserved. New entries are appended, never inserted or prepended.

### Timestamp Accuracy

Use accurate, synchronized timestamps (NTP). For legal and compliance purposes, the accuracy of timestamps may be relevant. Consider including the timezone or using UTC exclusively.

### Audit Trail Limits

The number of audit entries is limited by the block count (uint32). In practice, thousands of entries are feasible. For files that undergo frequent operations over many years, consider archiving old audit entries to a separate record.

---

## Chain Hash Computation Example

Given the following two entries:

**Entry 0 (JSON without chain_hash):**
```json
{"actor":"user:1:alice@example.com","action":"sealed","timestamp":1706367600,"details":{}}
```

**Chain hash computation:**
```
chain_hash[0] = SHA-256(
  00000000000000000000000000000000  (32 zero bytes, hex)
  ||
  {"actor":"user:1:alice@example.com","action":"sealed","timestamp":1706367600,"details":{}}
)
```

**Entry 1 (JSON without chain_hash):**
```json
{"actor":"user:2:bob@example.com","action":"verified","timestamp":1706454000,"details":{}}
```

**Chain hash computation:**
```
chain_hash[1] = SHA-256(
  chain_hash[0]  (32 bytes from above)
  ||
  {"actor":"user:2:bob@example.com","action":"verified","timestamp":1706454000,"details":{}}
)
```

---

## Interaction with Other Features

### Audit Trail + Redaction

Redaction should always be accompanied by an audit entry recording the redacted blocks and the reason. The audit entry is itself a block in the file and will be included in the post-redaction master seal.

### Audit Trail + Attestation

Attestation should be accompanied by an audit entry. The audit entry records that the attestation was added, while the attestation block contains the cryptographic proof.

### Audit Trail + Selective Disclosure

When generating a disclosure token, add an audit entry recording which blocks were disclosed and to whom. The token itself is distributed out-of-band, but the audit trail records that the disclosure occurred.

### Audit Trail + Split-Key

Audit entries are encrypted blocks. Reading the audit trail requires the master key (or a disclosure token that includes the audit blocks). If the key is split, reconstruct it first.

### Audit Trail + Content Versioning

When creating a new version of a file (`FLAG_VERSIONED`), the new file starts with a fresh audit trail. Consider adding an entry that references the previous version:

```json
{
  "action": "sealed",
  "details": {
    "previous_version": "a1b2c3d4...merkle root of previous version...",
    "change_summary": "Updated financial figures for Q4"
  }
}
```

---

## Further Reading

- [FORMAT_SPEC.md Section 7.3](../../FORMAT_SPEC.md#73-gen-8-tamper-evident-audit-trail) -- Specification
- [FORMAT_SPEC.md Section 7.1](../../FORMAT_SPEC.md#71-gen-6-co-signatures--multi-party-attestation) -- Co-signatures specification
- [Security Audit](../security_audit.md) -- Security considerations
- [Redaction Guide](redaction.md) -- Recording redaction actions
- [Selective Disclosure Guide](selective_disclosure.md) -- Recording disclosure actions
