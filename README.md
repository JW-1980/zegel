# Zegel

**Tamper-proof container format -- modify one byte and the content self-destructs.**

[![Tests](https://github.com/JW-1980/zegel/actions/workflows/test.yml/badge.svg)](https://github.com/JW-1980/zegel/actions/workflows/test.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Format: v1.2](https://img.shields.io/badge/Format-v1.2-green.svg)](FORMAT_SPEC.md)

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

### Seal a File

```bash
# Generate a key
zegel keygen -o my.key

# Seal a file
zegel seal document.pdf -k my.key -o document.pdf.zgl

# Verify integrity
zegel verify document.pdf.zgl -k my.key

# Extract original
zegel extract document.pdf.zgl -k my.key -o document.pdf
```

### Inspect Without a Key

```bash
zegel inspect document.pdf.zgl
# Shows: version, flags, content-type, filename, block count, timestamps
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

## Platform Support

| Platform | CLI | GUI |
|----------|-----|-----|
| Windows  | x64 | x64 |
| macOS    | x64 | x64 |
| Linux    | x64 | x64 |
| Android  | --  | APK |
| iOS      | --  | App |
| Web      | --  | Verification only |

## Project Structure

```
zegel/
  FORMAT_SPEC.md     # Binary format specification (source of truth)
  lib/               # Core Dart library
  cli/               # Command-line interface
  app/               # Flutter GUI (all platforms)
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

- [Format Specification](FORMAT_SPEC.md) -- Complete binary format reference
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
