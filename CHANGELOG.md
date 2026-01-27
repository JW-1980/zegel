# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-01-27

### Added

#### Format Specification
- Zegel v1.2 binary format specification (FORMAT_SPEC.md)
- Magic bytes, versioned header, block directory, Merkle root, master seal
- 12 feature flags and 10 block types

#### Security Features
- SEC-1: Password-based key derivation via Argon2id with configurable cost
- SEC-2: Key commitment to prevent invisible salamander attacks on AES-GCM
- SEC-3: Cryptographic expiration baked into key derivation (day-granularity UTC)
- SEC-4: Canary trap fingerprinting for per-recipient leak tracing
- SEC-5: Partial redaction preserving Merkle tree integrity
- SEC-6: Split-key M-of-N via Shamir's Secret Sharing over GF(256)

#### General Features
- GEN-1: Public metadata readable without key, integrity-protected
- GEN-2: Block compression via zlib before encryption
- GEN-3: Streaming verification via Merkle inclusion proofs
- GEN-4: Multi-file container with sub-file headers
- GEN-5: Provenance chain for chain of custody events
- GEN-6: Co-signature attestation via HMAC without master key knowledge
- GEN-7: Cross-file references via Merkle root linking
- GEN-8: Tamper-evident audit trail with hash-chained entries
- GEN-9: Selective disclosure tokens for per-block key sharing
- GEN-10: Content versioning via SHA-256 chain hashes

#### Core Library (lib/)
- Dart package implementing all v1.2 format features
- ZegelWriter for creating .zgl files
- ZegelReader for verification and extraction
- MerkleTree with inclusion proof support
- KeyDerivation (HKDF RFC 5869)
- ShamirSecretSharing over GF(256)
- CanaryTrap padding and identification
- Attestation creation and verification
- AuditTrail with chain hash verification
- SelectiveDisclosure token generation
- ContentVersioning chain hashes
- Comprehensive test suite (11 test files)

#### CLI Application (cli/)
- `zegel seal` - Seal files with optional metadata, compression, expiration
- `zegel verify` - Verify file integrity
- `zegel extract` - Extract original content
- `zegel inspect` - View header without key
- `zegel keygen` - Generate cryptographic keys
- `zegel redact` - Permanently redact blocks
- `zegel split-key` - Split key into M-of-N shares
- `zegel reconstruct` - Reconstruct key from shares
- `zegel attest` - Add co-signature attestation
- `zegel disclose` - Generate selective disclosure tokens
- `zegel extract-with-token` - Extract using disclosure token

#### GUI Application (app/)
- Flutter application for Windows, macOS, Linux, Android, iOS
- Home screen with drag-and-drop file zone
- Seal, Verify, Extract screens
- Settings with key management via OS keychain/keystore
- Split-key, Redaction, Selective Disclosure screens
- Audit trail timeline and attestation badges
- English and Dutch translations

#### Infrastructure
- GitHub Actions CI/CD (test, build, release)
- Tests on Linux, Windows, macOS
- CLI builds for all desktop platforms
- GUI builds for all platforms including Android and iOS
- Language-agnostic test vectors with JSON specifications
- Documentation: architecture, porting guide, security audit, FAQ, feature guides
