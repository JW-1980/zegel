# Claude Code Configuration - Zegel

## Project Overview
Zegel is an open-source tamper-proof file format (v1.2). Extension: .zgl. MIME: application/x-zgl.
Files sealed in Zegel format become physically unreadable if modified.

## Architecture
- **lib/** - Dart package: core Zegel format library (reader, writer, Merkle tree, key derivation, Shamir SSS, canary traps, attestation, audit trail, selective disclosure)
- **cli/** - Dart CLI application using the lib/ package
- **app/** - Flutter GUI application for all platforms (Windows, macOS, Linux, Android, iOS)
- **test_vectors/** - Language-agnostic test files for cross-implementation verification

## Key Rules

1. **FORMAT_SPEC.md is the source of truth.** Never deviate from the spec. If you think the spec is wrong, update the spec first, then update code.
2. **Cross-platform compatibility is non-negotiable.** A .zgl file created on any platform must be verifiable on every other platform. Byte order, encoding, padding must match exactly.
3. **Test vectors are sacred.** Every implementation must pass the test vectors. After ANY change, run `dart test` in lib/, cli/, and app/.
4. **Security is the whole point.** Never:
   - Log or print master keys, derived keys, or plaintext content to stdout/stderr in production
   - Use Math.random() or similar weak RNG (always use cryptographically secure random)
   - Skip constant-time comparison for hashes/HMACs
   - Reuse IVs/nonces
   - Store split-key shares together
   - Log canary recipient IDs in production
5. **The format name is "Zegel", the extension is ".zgl", the MIME is "application/x-zgl".**

## Feature Flags (v1.2)

| Flag | Mask | Description |
|------|------|-------------|
| HAS_METADATA | 0x0001 | Encrypted metadata block |
| COMPRESSED | 0x0002 | zlib-compressed blocks |
| PASSWORD_DERIVED | 0x0004 | Argon2id key derivation |
| HAS_KEY_COMMITMENT | 0x0008 | Key commitment value |
| HAS_EXPIRATION | 0x0010 | Cryptographic expiration |
| HAS_PUBLIC_METADATA | 0x0020 | Unencrypted metadata |
| MULTI_FILE | 0x0040 | Multi-file container |
| HAS_CANARY | 0x0080 | Canary trap fingerprinting |
| HAS_REDACTIONS | 0x0100 | Partially redacted blocks |
| SPLIT_KEY | 0x0200 | Shamir's Secret Sharing |
| SELECTIVE_DISCLOSURE | 0x0400 | Selective disclosure index |
| VERSIONED | 0x0800 | Version chain hash |

## Block Types (v1.2)

| Value | Name | Description |
|-------|------|-------------|
| 0x01 | CONTENT | File content chunk |
| 0x02 | METADATA | Encrypted JSON metadata |
| 0x03 | PUBLIC_METADATA | Unencrypted metadata |
| 0x04 | FILE_HEADER | Multi-file sub-file header |
| 0x05 | PROVENANCE | Chain of custody event |
| 0x06 | REDACTED | Permanently redacted block |
| 0x07 | ATTESTATION | Co-signature attestation |
| 0x08 | REFERENCE | Cross-file reference |
| 0x09 | AUDIT | Audit trail entry |
| 0x0A | DISCLOSURE_INDEX | Selective disclosure index |

## Implementation Priority

Build in this order:
1. lib/ (core Dart library) - with 100% test coverage
2. test_vectors/ - generated from lib/, verified against PHP reference
3. cli/ - thin wrapper around lib/
4. app/ - Flutter GUI for all platforms

## CLI Interface

```
zegel seal <input-file> -k <key-file-or-hex> -o <output.zgl> [--metadata key=value...] [--compress] [--password] [--expires YYYY-MM-DD]
zegel verify <file.zgl> -k <key-file-or-hex>
zegel extract <file.zgl> -k <key-file-or-hex> -o <output-file>
zegel inspect <file.zgl>
zegel keygen [-o <key-file>]
zegel redact <file.zgl> -k <key-file-or-hex> --blocks 1,3,5 -o <redacted.zgl>
zegel split-key -k <key-file-or-hex> --threshold 3 --shares 5 -o <share-dir/>
zegel reconstruct <share1> <share2> <share3> -o <key-file>
zegel attest <file.zgl> --signer-key <key> --statement "Reviewed and approved"
zegel disclose <file.zgl> -k <key-file-or-hex> --blocks 0,2 -o <token.json>
zegel extract-with-token <file.zgl> --token <token.json> -o <output-file>
```

Key formats accepted:
- Hex string: `--key 0a1b2c3d...` (64 hex chars = 32 bytes)
- Key file: `--key-file path/to/keyfile` (raw 32 bytes or base64)
- Interactive prompt: if no key flag, ask securely

## Testing Requirements

- lib/: Unit tests for every public method. Property-based tests for roundtrip (create -> verify -> extract). Tamper detection tests (flip bits at every position). Split-key reconstruction tests with various M/N combinations. Canary identification tests. Redaction integrity tests. Audit trail chain hash tests.
- cli/: Integration tests for every command.
- app/: Widget tests for key screens. Integration test for seal -> verify flow.
- cross-platform: Generate .zgl files in Dart, verify against PHP reference output.

## CI/CD

GitHub Actions workflows:
- `test.yml` - Run all tests on push/PR
- `build.yml` - Build all platform binaries on release tags
- `release.yml` - Create GitHub release with binaries and checksums
