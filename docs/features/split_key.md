# SEC-6: Split-Key M-of-N (Shamir's Secret Sharing)

This guide explains how to use Zegel's split-key feature to distribute trust across multiple parties, requiring a threshold number of parties to agree before a sealed file can be opened.

For the specification, see [FORMAT_SPEC.md Section 6.3](../../FORMAT_SPEC.md#63-sec-6-split-key-m-of-n-shamirs-secret-sharing).

---

## What Is Shamir's Secret Sharing?

Shamir's Secret Sharing (SSS) is a cryptographic technique that splits a secret (in this case, the 32-byte Zegel master key) into N shares, of which any M shares are sufficient to reconstruct the original secret. Fewer than M shares reveal absolutely no information about the secret.

This is not computational security -- it is **information-theoretic security**. Even with unlimited computing power, M-1 shares give an attacker zero knowledge about the key.

The technique was published by Adi Shamir in 1979 and is based on polynomial interpolation over a finite field.

---

## Use Case

Split-key is useful in any scenario where no single person should have unilateral access to sensitive content:

- **Business continuity:** 2-of-3 split among CEO, CFO, and legal counsel. If one person is unavailable, the other two can still access the document.
- **Board approval:** 3-of-5 split among board members. A majority must agree to open the file.
- **Dual control:** 2-of-2 split between two officers. Both must be present to access the content.
- **Escrow:** 1-of-3 split (any single party can open). This is a backup/escrow scenario, not a security scenario.
- **Disaster recovery:** 3-of-7 split across geographically distributed offices.

---

## How It Works

### Mathematical Foundation

Shamir's Secret Sharing uses polynomial evaluation over GF(256), the Galois Field with 256 elements.

For each byte of the 32-byte master key:

1. **Construct a random polynomial** of degree M-1:
   ```
   f(x) = secret_byte + a1*x + a2*x^2 + ... + a_{M-1}*x^{M-1}
   ```
   where `a1, a2, ..., a_{M-1}` are random coefficients.

2. **Evaluate at N points** to produce N shares:
   ```
   share_1 = (1, f(1))
   share_2 = (2, f(2))
   ...
   share_N = (N, f(N))
   ```

3. The secret is `f(0)`, which equals `secret_byte`.

### Reconstruction

Given M shares, the master key is reconstructed using **Lagrange interpolation** at x=0 over GF(256):

```
f(0) = sum over i of (y_i * product over j!=i of (x_j / (x_j - x_i)))
```

All arithmetic (addition, multiplication, division) is performed in GF(256).

### GF(256) Arithmetic

- **Addition:** XOR (`a + b = a XOR b`)
- **Multiplication:** Russian peasant algorithm with reduction by the irreducible polynomial `x^8 + x^4 + x^3 + x + 1` (0x11B)
- **Inverse:** Fermat's little theorem: `a^(-1) = a^254` in GF(256)

### Share Format

Each share is exactly **33 bytes**:
- 1 byte: x-coordinate (1 to 255)
- 32 bytes: y-values (one per byte of the master key)

The x-coordinate identifies the share. The y-values are the secret material.

---

## How to Split a Key

### CLI

```bash
# Generate a master key
zegel keygen -o master.key

# Seal a file with the master key
zegel seal document.pdf -k master.key -o document.zgl

# Split the key into 5 shares with threshold 3
zegel split-key -k master.key --threshold 3 --shares 5 -o shares/

# This creates:
#   shares/share_1.key  (33 bytes)
#   shares/share_2.key  (33 bytes)
#   shares/share_3.key  (33 bytes)
#   shares/share_4.key  (33 bytes)
#   shares/share_5.key  (33 bytes)
```

Alternatively, seal and split in one step:

```bash
zegel seal document.pdf \
  -k master.key \
  -o document.zgl \
  --split-key --threshold 3 --shares 5 \
  --shares-output shares/
```

This sets the `FLAG_SPLIT_KEY` flag and records M=3, N=5 in the extended header.

### GUI

1. Open the Zegel application and navigate to the Seal screen.
2. Select the source file and enter the master key.
3. Expand "Advanced Options."
4. Enable "Split Key (M-of-N)."
5. Set the threshold (M) and total shares (N).
6. Click "Seal."
7. The application produces the `.zgl` file and N share files.
8. Distribute the share files to the designated parties.

---

## How to Reconstruct

### CLI

```bash
# Reconstruct from any 3 of the 5 shares
zegel reconstruct shares/share_1.key shares/share_3.key shares/share_5.key -o recovered.key

# Verify and extract using the reconstructed key
zegel extract document.zgl -k recovered.key -o document.pdf
```

### GUI

1. Open the Zegel application and navigate to the Verify or Extract screen.
2. Load the `.zgl` file.
3. The application detects the `FLAG_SPLIT_KEY` flag and prompts for shares.
4. Load M share files (the application shows how many are needed based on the threshold).
5. The key is reconstructed in memory.
6. Verification and extraction proceed normally.

---

## Security Properties

### Information-Theoretic Security

Any set of fewer than M shares reveals **zero information** about the master key. This is mathematically provable and does not depend on computational assumptions. Even a quantum computer with unlimited power cannot extract the key from M-1 shares.

### No Single Point of Failure

No single party holds the complete key. Even if one share is compromised, the attacker gains nothing (assuming M > 1).

### Threshold Flexibility

The M-of-N scheme is flexible:
- **2-of-3:** Tolerates loss of 1 share. Requires agreement of 2 parties.
- **3-of-5:** Tolerates loss of 2 shares. Requires agreement of 3 parties.
- **1-of-N:** Any single share suffices (backup/escrow, not access control).
- **N-of-N:** All shares required (maximum security, minimum availability).

### What Reconstruction Cannot Do

- It cannot identify which shares were used. All valid M-subsets produce the same key.
- It does not authenticate shareholders. Any party with a valid share can participate.
- It does not enforce who should participate. Access policy is external to the cryptographic mechanism.

---

## Share Distribution Best Practices

### Distribute Via Separate Channels

Never send all shares through the same channel. Use a different secure channel for each share:
- In-person handoff (most secure)
- Separate encrypted email threads
- Different secure messaging platforms
- Physical media (USB drives) delivered separately

### Never Store Shares Together

The entire purpose of splitting is to distribute trust. Storing all shares in the same system, backup, or location defeats this purpose completely.

### Record Share Assignments

Maintain a secure record of:
- Which share index (x-coordinate, 1 through N) was given to which party
- When each share was distributed
- Through which channel
- Contact information for each shareholder

This record should itself be protected, as it identifies the key holders.

### Physical Security

For high-security scenarios, consider:
- Printing shares as QR codes on paper, stored in separate safes
- Engraving shares on metal plates for fire resistance
- Using tamper-evident envelopes
- Requiring notarized receipt of each share

### Share Rotation

To rotate shares without re-sealing the file:
1. Reconstruct the master key from M existing shares.
2. Generate a new set of N' shares (possibly with different M', N' values).
3. Distribute the new shares.
4. Securely destroy all old shares.

Note: the `.zgl` file itself is unchanged. Only the shares change.

---

## Example Scenarios

### 2-of-3: Business Continuity

```
Parties: CEO, CFO, Legal Counsel
Threshold: 2 (any two can open)
Total shares: 3

Use case: financial audit documents that must be accessible
even if one executive is unavailable. Two of the three
executives can always access the documents.
```

### 3-of-5: Board Approval

```
Parties: 5 Board Members
Threshold: 3 (majority required)
Total shares: 5

Use case: acquisition documents or strategic plans that
require board majority approval before access. A simple
majority (3 of 5) must agree to open the file.
```

### 2-of-2: Dual Control

```
Parties: Compliance Officer, Department Head
Threshold: 2 (both required)
Total shares: 2

Use case: highly sensitive HR documents that require
both parties to be present for access. Neither can act
unilaterally.
```

### 3-of-7: Geographic Distribution

```
Parties: 7 regional offices
Threshold: 3 (any 3 offices)
Total shares: 7

Use case: disaster recovery key for an organization
with offices across multiple countries. Even if 4
offices are simultaneously unreachable, the remaining
3 can still recover the data.
```

---

## Interaction with Other Features

### Split-Key + Canary Traps

These features can be combined. The canary padding is applied using the reconstructed master key. The recipient ID is stored in the extended header.

### Split-Key + Password Derivation

The `FLAG_SPLIT_KEY` and `FLAG_PASSWORD_DERIVED` flags are mutually exclusive in practice. If the master key is password-derived, split the password-derived key (not the password). The `.zgl` file stores split-key parameters in the extended header.

### Split-Key + Selective Disclosure

Selective disclosure tokens are generated using the master key. If the key is split, reconstruct it first, then generate disclosure tokens.

---

## Further Reading

- [FORMAT_SPEC.md Section 6.3](../../FORMAT_SPEC.md#63-sec-6-split-key-m-of-n-shamirs-secret-sharing) -- Specification
- [Security Audit](../security_audit.md) -- Split-key security model
- [Canary Traps Guide](canary_traps.md) -- Leak tracing
- [Selective Disclosure Guide](selective_disclosure.md) -- Partial sharing
