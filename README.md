# Zegel

**Tamper-proof container format -- modify one byte and the content self-destructs.**

[![Tests](https://github.com/JW-1980/zegel/actions/workflows/test.yml/badge.svg)](https://github.com/JW-1980/zegel/actions/workflows/test.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Format: v1.3](https://img.shields.io/badge/Format-v1.3-green.svg)](FORMAT_SPEC.md)

Zegel ("seal" in Dutch) wraps any file in a container where the content becomes **physically unreadable** if even a single byte is modified after creation. This is not a "check and warn" system -- the cryptographic math itself prevents decoding.

## How It Works

1. File content is split into blocks (default 64 KB)
2. Each block is hashed (SHA-256) to form a **Merkle tree**
3. Each block's encryption key is derived from: `HKDF(master_key, merkle_root || block_index)`
4. Blocks are encrypted with **AES-256-GCM** (authenticated encryption)
5. A **master seal** (HMAC-SHA512) covers the entire file

**Why it's tamper-proof:** Changing any byte changes a block's hash, which changes the Merkle root, which changes every block's derived key. AES-GCM then rejects decryption. The content isn't flagged -- it's destroyed.

## Quick Start

### Install CLI

```bash
# From source
cd cli && dart pub get
dart compile exe bin/zegel.dart -o zegel

# Or download a pre-built binary from GitHub Releases
```

### Basic Usage

```bash
# Generate a key
zegel keygen -o my.key

# Seal a file
zegel seal document.pdf --key-file my.key -o document.pdf.zgl

# Verify integrity
zegel verify document.pdf.zgl --key-file my.key

# Extract original
zegel extract document.pdf.zgl --key-file my.key -o document.pdf

# Inspect without a key
zegel inspect document.pdf.zgl
```

## Features

### Security Features

| ID | Feature | Description |
|----|---------|-------------|
| SEC-1 | Password-based key derivation | Argon2id with configurable time/memory cost |
| SEC-2 | Key commitment | Prevents invisible salamander attacks on AES-GCM |
| SEC-3 | Cryptographic expiration | Expiration date baked into key derivation |
| SEC-4 | Canary trap fingerprinting | Invisible per-recipient padding for leak tracing |
| SEC-5 | Partial redaction | Permanently destroy specific blocks while preserving Merkle tree |
| SEC-6 | Split-key M-of-N | Shamir's Secret Sharing for threshold decryption |
| SEC-7 | Regulatory hold | Block extraction until a compliance date (SEC 17a-4, GDPR holds) |
| SEC-8 | Classification levels | PUBLIC / INTERNAL / CONFIDENTIAL / SECRET / TOP_SECRET labelling |
| SEC-9 | Hierarchical split-key | Classification-based nested Shamir sharing |

### General Features

| ID | Feature | Description |
|----|---------|-------------|
| GEN-1 | Public metadata | Unencrypted metadata readable without key |
| GEN-2 | Block compression | zlib compression before encryption |
| GEN-3 | Streaming verification | Merkle inclusion proofs for per-block verification |
| GEN-4 | Multi-file container | Multiple files in one .zgl |
| GEN-5 | Provenance chain | Chain of custody event records |
| GEN-6 | Co-signatures | Multi-party attestation via HMAC |
| GEN-7 | Cross-file references | Verifiable links between .zgl files |
| GEN-8 | Audit trail | Hash-chained tamper-evident append-only log |
| GEN-9 | Selective disclosure | Per-block key tokens for partial content sharing |
| GEN-10 | Content versioning | SHA-256 chain hash linking file versions |
| GEN-11 | Trusted timestamps | RFC 3161 compatible timestamp proofs |
| GEN-12 | Anonymous mode | Seal files without identifying metadata |
| GEN-13 | Role-based attestation | Typed roles (owner, signer, witness, notary, auditor, reviewer) |
| GEN-14 | Excerpt proofs | Merkle inclusion proofs for specific blocks |
| GEN-15 | Batch operations | Efficient multi-file verification and sealing |
| GEN-16 | Manifests | Signed multi-file integrity documents |
| GEN-17 | Provenance verification | Signed, hash-chained custody events with chronological validation |
| GEN-18 | Token expiration | Time-limited selective disclosure tokens |

## Use Cases

### Real Estate Contracts
Seal house purchase contracts with multi-party attestation (buyer, seller, notary, bank). Each party signs with a role-based attestation. The notary creates a manifest of all related documents (contract, deed, inspection report, mortgage agreement). Split the master key 3-of-5 among the parties for shared custody.

### Financial Auditing
Seal financial statements with regulatory holds (SEC 17a-4 compliance). Auditors attach role-based attestations. Selective disclosure tokens allow sharing specific sections with regulators without exposing the full document. Batch verification checks all documents in an audit set.

### Medical Records
Seal patient records with classification levels (CONFIDENTIAL). Selective disclosure allows sharing relevant sections with specialists. Expiration dates enforce retention policies. Canary traps trace unauthorized disclosures.

### Legal Discovery
Seal evidence files with provenance chains tracking chain of custody. Partial redaction removes privileged content while preserving Merkle tree integrity for verification. Version chains link amended filings.

### Academic Credentials & Diplomas
Seal diplomas and certifications with institutional attestation (university as signer, registrar as notary). Excerpt proofs allow graduates to prove specific credentials without sharing the full transcript. Classification levels distinguish between public (degree title) and confidential (grades) information.

### Government Classified Documents
Hierarchical split-key distributes access based on classification levels. TOP_SECRET documents require higher thresholds. Declassification records track level reductions with authority and reason. Regulatory holds prevent premature release.

### Journalism & Source Protection
Anonymous mode seals documents without identifying metadata, protecting whistleblower sources. Canary traps identify which recipient leaked a document. Excerpt proofs allow publishers to prove they hold authentic documents without revealing them entirely.

### Software Distribution
Seal software release packages with provenance chains tracking the build pipeline. Manifests verify release integrity across multiple artifacts. Attestations from CI/CD systems, security reviewers, and release managers provide multi-party trust.

### Digital Art Provenance
Seal digital artworks with media metadata preservation. Provenance chains track ownership transfers. Version chains link original works to authorised derivatives. Cross-file references connect an artwork to its certificate of authenticity.

## CLI Reference

### Core Commands

```bash
# Seal a file into a tamper-proof .zgl container
zegel seal <input> -k <hex> -o <output.zgl> [options]
  Options:
    --compress                Enable zlib compression
    --password                Derive key from password via Argon2id
    --expires <YYYY-MM-DD>    Set cryptographic expiration date
    --metadata key=value      Add encrypted metadata (repeatable)
    --classification <level>  Set classification level
    --anonymous               Seal without identifying metadata
    --role <role>             Set creator role

# Verify file integrity
zegel verify <file.zgl> -k <hex>

# Extract original content from a verified .zgl file
zegel extract <file.zgl> -k <hex> -o <output>

# Inspect file header (no key required)
zegel inspect <file.zgl>
  Options:
    --json                    Output as JSON

# Generate a cryptographically secure 32-byte master key
zegel keygen [-o <keyfile>]
  Options:
    --format <hex|raw|base64> Output format (default: raw)
```

### Security Commands

```bash
# Permanently redact specific blocks
zegel redact <file.zgl> -k <hex> --blocks 1,3,5 -o <redacted.zgl>

# Split master key into M-of-N Shamir shares
zegel split-key -k <hex> --threshold 3 --shares 5 -o <share-dir/>

# Reconstruct master key from shares
zegel reconstruct <share1> <share2> <share3> -o <keyfile>

# Add a co-signature attestation
zegel attest <file.zgl> --signer-key <key> --statement "Approved"
  Options:
    --role <role>             Attestation role (owner/signer/witness/notary/auditor/reviewer)
    --signer-id <id>         Signer identifier
```

### Disclosure Commands

```bash
# Generate a selective disclosure token for specific blocks
zegel disclose <file.zgl> -k <hex> --blocks 0,2 -o <token.json>
  Options:
    --expires-in <duration>   Token expiration (e.g. "24h", "7d", "2w")

# Extract content using a disclosure token (no master key needed)
zegel extract-with-token <file.zgl> --token <token.json> -o <output>

# Generate a Merkle inclusion proof for a specific block
zegel excerpt-proof <file.zgl> -k <hex> --block <index> -o <proof.json>

# Verify an excerpt proof
zegel verify-excerpt <file.zgl> --proof <proof.json>
```

### Batch Commands

```bash
# Verify multiple .zgl files at once
zegel batch-verify <dir-or-files...> -k <hex>
  Options:
    --stop-on-failure         Stop after first failed file

# Seal multiple files from a directory
zegel batch-seal <dir> -k <hex> -o <output-dir/>

# Create a manifest from .zgl files
zegel manifest-create <files...> --signer-key <key> --signer-id <id> -o <manifest.json>

# Verify a manifest against files on disk
zegel manifest-verify <manifest.json> --signer-key <key>
```

### Classification Commands

```bash
# Set classification level on a .zgl file
zegel classify <file.zgl> --level <PUBLIC|INTERNAL|CONFIDENTIAL|SECRET|TOP_SECRET> --authority <name>
  Options:
    --caveats <list>          Handling caveats (e.g. "NOFORN,REL TO")

# Reduce classification level
zegel declassify <file.zgl> --level <new-level> --authority <name>
  Options:
    --reason <text>           Reason for declassification
```

### Versioning Commands

```bash
# Verify a sequence of .zgl files are linked via version chain
zegel version-chain-verify <file1.zgl> <file2.zgl> [file3.zgl ...]

# Verify provenance chain integrity in a .zgl file
zegel provenance-verify <file.zgl> --signer-key <key>
```

### Global Options

```bash
zegel --version              # Show version
zegel <command> --help       # Show help for a command
```

Key formats accepted by `-k` / `--key-file`:
- Hex string: `-k 0a1b2c3d...` (64 hex chars = 32 bytes)
- Key file: `--key-file path/to/keyfile` (raw 32 bytes, hex, or base64)

## Platform Support

| Platform | CLI | GUI |
|----------|-----|-----|
| Windows  | x64 | x64 |
| macOS    | x64 | x64 |
| Linux    | x64 | x64 |
| Android  | --  | APK |
| iOS      | --  | App |
| Web      | --  | Verification only |

## GUI Application

The Flutter GUI provides visual workflows for all Zegel operations:

- **Seal Screen** -- Drag-and-drop file sealing with classification, compression, and expiration options
- **Verify Screen** -- Visual verification with detailed integrity report
- **Contract Screen** -- Multi-party contract workflow with party management and role-based attestation
- **Credential Screen** -- Academic credential and diploma management
- **Batch Screen** -- Bulk file operations with progress tracking
- **Classification Screen** -- Set and manage document classification levels
- **Manifest Screen** -- Create and verify multi-file manifests
- **Excerpt Screen** -- Generate and verify Merkle inclusion proofs
- **Provenance Screen** -- View and verify chain of custody

## Project Structure

```
zegel/
  FORMAT_SPEC.md     # Binary format specification (source of truth)
  lib/               # Core Dart library
    lib/src/         # Source modules (20 files)
    test/            # Unit & integration tests (20+ files)
  cli/               # Command-line interface (22 commands)
  app/               # Flutter GUI (all platforms)
    lib/screens/     # 12 screens
    lib/widgets/     # 10 widgets
    lib/services/    # Application services
  test_vectors/      # Language-agnostic test files
  docs/              # Documentation
```

## Building from Source

### Prerequisites

- [Dart SDK](https://dart.dev/get-dart) >= 3.0.0
- [Flutter SDK](https://docs.flutter.dev/get-started/install) >= 3.10.0 (for GUI)

### Build

```bash
# Core library
cd lib && dart pub get && dart test

# CLI binary
cd cli && dart pub get && dart compile exe bin/zegel.dart -o zegel

# GUI (choose platform)
cd app && flutter pub get
flutter build windows    # or: macos, linux, apk, ios
```

## Documentation

- [Format Specification](FORMAT_SPEC.md) -- Complete binary format reference (v1.3)
- [Architecture](docs/architecture.md) -- How the format works with diagrams
- [Porting Guide](docs/porting_guide.md) -- Implement Zegel in other languages
- [Security Audit](docs/security_audit.md) -- Threat model and crypto rationale
- [FAQ](docs/faq.md) -- Common questions

### Feature Guides

- [Canary Traps](docs/features/canary_traps.md) -- Leak tracing
- [Split Key](docs/features/split_key.md) -- M-of-N threshold decryption
- [Redaction](docs/features/redaction.md) -- Partial content removal
- [Selective Disclosure](docs/features/selective_disclosure.md) -- Sharing specific blocks
- [Audit Trail](docs/features/audit_trail.md) -- Compliance logging

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, code style, and PR process.

## Security

See [SECURITY.md](SECURITY.md) for responsible disclosure of vulnerabilities.

## License

- **Code:** [Apache License 2.0](LICENSE)
- **Format Specification:** [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)
- **Test Vectors:** [CC0](https://creativecommons.org/publicdomain/zero/1.0/) (public domain)

---

*Zegel = "seal" in Dutch. Originated in the Boekhouder bookkeeping project for tamper-proof financial document storage.*
