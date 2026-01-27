# Zegel Open-Source Repository - Handoff Document

**From:** Claude (Boekhouder project, session: tamper-detection-file-format)
**To:** Claude (new `zegel` repository)
**Date:** 2026-01-27
**Format Version:** 1.2

---

## What This Is

You are taking over development of the **Zegel file format** - a tamper-proof container format. Your job is to build an open-source repository containing:

1. The format specification (provided: `FORMAT_SPEC.md`)
2. Cross-platform applications for Windows, macOS, Linux (CLI + GUI), Android, iOS
3. Library packages for multiple languages

The format already has a **working reference implementation in PHP** inside the Boekhouder project. You are building the public-facing, language-agnostic version.

---

## What Zegel Does (The Core Idea)

Zegel wraps any file in a container where **modifying a single byte makes the entire content physically unreadable**. Not "shows a warning" - the decryption keys are mathematically derived from the file's integrity, so tampering destroys the keys.

The mechanism:
1. File content is split into blocks
2. Each block is hashed (SHA-256) -> leaf hashes
3. Leaf hashes form a Merkle tree -> root hash
4. Each block's AES-256-GCM encryption key = `HKDF(master_key, merkle_root || block_index)`
5. Change 1 byte -> leaf hash changes -> root changes -> ALL keys change -> AES-GCM rejects decryption

Read `FORMAT_SPEC.md` for the complete binary specification.

---

## Feature Overview (v1.2)

### Core (v1.0)
- Merkle-rooted authenticated encryption
- AES-256-GCM per-block encryption
- HKDF key derivation (RFC 5869)
- HMAC-SHA512 master seal
- Encrypted metadata blocks
- Binary format with magic bytes, versioning, block directory

### Security Features (v1.1-v1.2)
| ID | Feature | Description |
|----|---------|-------------|
| SEC-1 | Password-based key derivation | Argon2id with configurable time/memory cost |
| SEC-2 | Key commitment | Prevents invisible salamander attacks on AES-GCM |
| SEC-3 | Cryptographic expiration | Expiration date baked into key derivation (day-granularity UTC) |
| SEC-4 | Canary trap fingerprinting | Invisible per-recipient padding for leak tracing |
| SEC-5 | Partial redaction | Permanently destroy specific blocks while preserving Merkle tree integrity |
| SEC-6 | Split-key M-of-N | Shamir's Secret Sharing over GF(256) for threshold decryption |

### General Features (v1.1-v1.2)
| ID | Feature | Description |
|----|---------|-------------|
| GEN-1 | Public metadata | Unencrypted metadata readable without key, integrity-protected |
| GEN-2 | Block compression | zlib compression before encryption |
| GEN-3 | Streaming verification | Merkle inclusion proofs for per-block verification |
| GEN-4 | Multi-file container | Multiple files in one .zgl with sub-file headers |
| GEN-5 | Provenance chain | Chain of custody event records |
| GEN-6 | Co-signatures | Multi-party attestation via HMAC without master key knowledge |
| GEN-7 | Cross-file references | Verifiable links between .zgl files via Merkle root |
| GEN-8 | Audit trail | Hash-chained tamper-evident append-only log |
| GEN-9 | Selective disclosure | Per-block key tokens for partial content sharing |
| GEN-10 | Content versioning | SHA-256 chain hash linking file versions |

---

## Repository Structure To Build

```
zegel/
  FORMAT_SPEC.md                    # Copy from Boekhouder (provided)
  LICENSE                           # Apache-2.0 (code), CC BY 4.0 (spec)
  README.md                         # Project overview, badges, installation
  CLAUDE.md                         # This file (adapted for the new repo)
  CONTRIBUTING.md                   # Contribution guidelines
  SECURITY.md                       # Responsible disclosure process

  # Dart/Flutter shared library (core logic)
  lib/
    lib/zegel.dart                  # Package entry point
    lib/src/
      format.dart                   # Constants, matching ZegelFormat.php
      merkle_tree.dart              # Merkle tree implementation
      writer.dart                   # Creates .zgl files
      reader.dart                   # Reads/verifies .zgl files
      key_derivation.dart           # HKDF implementation
      canary.dart                   # SEC-4: Canary trap padding
      shamir.dart                   # SEC-6: Shamir's Secret Sharing / GF(256)
      redaction.dart                # SEC-5: Partial redaction
      attestation.dart              # GEN-6: Co-signature attestation
      disclosure.dart               # GEN-9: Selective disclosure tokens
      audit.dart                    # GEN-8: Audit trail with chain hashes
      versioning.dart               # GEN-10: Version chain hashes
    test/
      format_test.dart
      merkle_tree_test.dart
      writer_test.dart
      reader_test.dart
      roundtrip_test.dart           # Create -> verify -> extract
      tamper_test.dart              # Flip bits and verify detection
      canary_test.dart              # SEC-4: Fingerprint round-trip
      shamir_test.dart              # SEC-6: Split/reconstruct key
      redaction_test.dart           # SEC-5: Redact and verify
      disclosure_test.dart          # GEN-9: Token generation and extraction
      audit_test.dart               # GEN-8: Chain hash verification
      cross_platform_test.dart      # Verify PHP-generated files
    pubspec.yaml                    # Dart package

  # CLI application (Dart)
  cli/
    bin/
      zegel.dart                    # Entry point
    lib/
      commands/
        seal_command.dart           # zegel seal <file> --key <key> --output <file.zgl>
        verify_command.dart         # zegel verify <file.zgl> --key <key>
        extract_command.dart        # zegel extract <file.zgl> --key <key> --output <file>
        inspect_command.dart        # zegel inspect <file.zgl> (header only, no key)
        keygen_command.dart         # zegel keygen (generate 32-byte key)
        redact_command.dart         # zegel redact <file.zgl> --blocks 1,3,5
        split_key_command.dart      # zegel split-key --threshold 3 --shares 5
        attest_command.dart         # zegel attest <file.zgl> --statement "..."
        disclose_command.dart       # zegel disclose <file.zgl> --blocks 0,2
    pubspec.yaml

  # GUI application (Flutter - all platforms)
  app/
    lib/
      main.dart
      screens/
        home_screen.dart            # Drag & drop zone, file list
        seal_screen.dart            # Select file -> seal -> save .zgl
        verify_screen.dart          # Select .zgl -> show result
        extract_screen.dart         # Select .zgl -> extract original
        settings_screen.dart        # Key management, preferences
        split_key_screen.dart       # SEC-6: M-of-N key management
        redact_screen.dart          # SEC-5: Select blocks to redact
        disclose_screen.dart        # GEN-9: Generate disclosure tokens
      widgets/
        drop_zone.dart              # File drag & drop widget
        status_badge.dart           # Valid/Tampered/Unknown badge
        file_info_card.dart         # Show file metadata
        key_input.dart              # Secure key entry/paste/file
        audit_trail_view.dart       # GEN-8: Audit trail timeline
        attestation_badge.dart      # GEN-6: Co-signature badges
      services/
        file_service.dart           # File picking, saving
        key_service.dart            # Key storage (keychain/keystore)
        zegel_service.dart          # Wraps the lib/ package
      l10n/                         # Translations
        app_en.arb
        app_nl.arb
    pubspec.yaml

    # Platform-specific
    android/                        # Standard Flutter Android project
    ios/                            # Standard Flutter iOS project
    macos/                          # Standard Flutter macOS project
    windows/                        # Standard Flutter Windows project
    linux/                          # Standard Flutter Linux project
    web/                            # Optional: Flutter web (for browser verification)

  # Test vectors (language-agnostic)
  test_vectors/
    minimal.zgl                     # Smallest valid file
    minimal.json                    # Expected values for minimal.zgl
    with_metadata.zgl               # File with metadata block
    with_metadata.json
    multi_block.zgl                 # File larger than 1 block
    multi_block.json
    canary_a.zgl                    # SEC-4: Canary for recipient A
    canary_b.zgl                    # SEC-4: Same content, different recipient
    split_key.zgl                   # SEC-6: File sealed with split key
    split_key_shares.json           # SEC-6: All shares for the split key
    redacted.zgl                    # SEC-5: File with redacted blocks
    with_audit.zgl                  # GEN-8: File with audit trail
    with_attestation.zgl            # GEN-6: File with co-signatures
    tampered_seal.zgl               # Modified master seal (should fail)
    tampered_block.zgl              # Modified block data (should fail)
    tampered_directory.zgl          # Modified directory (should fail)
    generate_vectors.dart           # Script to regenerate vectors

  # Documentation
  docs/
    architecture.md                 # How the format works (visual diagrams)
    porting_guide.md                # How to implement in other languages
    security_audit.md               # Security considerations
    faq.md                          # Common questions
    features/
      canary_traps.md               # SEC-4: Leak tracing guide
      split_key.md                  # SEC-6: Multi-party key management
      redaction.md                  # SEC-5: Partial redaction workflow
      selective_disclosure.md       # GEN-9: Sharing specific content
      audit_trail.md                # GEN-8: Compliance audit logging
```

---

## CLAUDE.md For The New Repository

Below is the content that should be placed as `CLAUDE.md` in the new repository:

```markdown
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

## GUI Features

### Home Screen
- Drag & drop zone (accepts any file for sealing, or .zgl for verification)
- Recent files list
- Auto-detect: if dropped file is .zgl, go to verify; otherwise go to seal

### Seal Screen
- File preview (name, size, type)
- Key entry (paste hex, load file, or generate new)
- Optional metadata fields
- Advanced options: compression, expiration, recipient fingerprinting, split-key
- "Seal" button -> produces .zgl file
- Save dialog

### Verify Screen
- Load .zgl file
- Key entry
- Big visual indicator: green checkmark (intact) or red X (tampered)
- Show metadata if valid
- Show audit trail timeline
- Show co-signature attestations with validity badges
- "Extract original" button

### Settings Screen
- Saved keys (stored in OS keychain/keystore)
- Default block size
- Language (Dutch, English)

## Platform Build Targets

| Platform | Build Command | Output |
|----------|---------------|--------|
| Android | `flutter build apk` | APK file |
| iOS | `flutter build ios` | .app bundle |
| macOS | `flutter build macos` | .app bundle |
| Windows | `flutter build windows` | .exe + DLLs |
| Linux | `flutter build linux` | Binary |
| CLI | `dart compile exe cli/bin/zegel.dart` | Native binary |

## Translations

Support at minimum:
- English (en) - primary
- Dutch (nl) - origin language

Use Flutter's l10n system with .arb files. ALL user-visible strings must use translations.

## Testing Requirements

- lib/: Unit tests for every public method. Property-based tests for roundtrip (create -> verify -> extract). Tamper detection tests (flip bits at every position). Split-key reconstruction tests with various M/N combinations. Canary identification tests. Redaction integrity tests. Audit trail chain hash tests.
- cli/: Integration tests for every command.
- app/: Widget tests for key screens. Integration test for seal -> verify flow.
- cross-platform: Generate .zgl files in Dart, verify against PHP reference output. Generate in PHP, verify in Dart.

## CI/CD

GitHub Actions workflows:
- `test.yml` - Run all tests on push/PR
- `build.yml` - Build all platform binaries on release tags
- `release.yml` - Create GitHub release with binaries and checksums

## Security Policy

- SECURITY.md with responsible disclosure instructions
- No binary releases without reproducible builds
- All dependencies audited (`dart pub audit`)
```

---

## Critical Implementation Details

### Byte-for-Byte Compatibility With PHP

The PHP reference implementation is in the Boekhouder project:
- `app/Services/TamperProof/ZegelFormat.php` - Constants, key derivation, GF(256) arithmetic, canary traps, attestation, audit trail, disclosure tokens
- `app/Services/TamperProof/MerkleTree.php` - Merkle tree
- `app/Services/TamperProof/ZegelWriter.php` - Writer (all v1.2 features)
- `app/Services/TamperProof/ZegelReader.php` - Reader (all v1.2 features)
- `app/Services/TamperProof/ZegelOptions.php` - Feature option configuration
- `app/Services/TamperProof/ZegelService.php` - High-level application API

Key implementation details that MUST match:

1. **Pack format for uint16:** Big-endian (`pack('n', ...)` in PHP = `ByteData.setUint16(offset, value, Endian.big)` in Dart)
2. **Pack format for uint32:** Big-endian (`pack('N', ...)` in PHP)
3. **Pack format for uint64:** Big-endian (`pack('J', ...)` in PHP)
4. **Content-Type padding:** Right-padded with `\x00` bytes to exactly 64 bytes, truncated if longer
5. **Filename max length:** 255 bytes (UTF-8 encoded)
6. **Merkle tree odd-node handling:** Duplicate the last node (hash it with itself)
7. **Single-leaf tree:** Root = leaf hash (no hashing with itself)
8. **HKDF info string:** `"zegel-block-key-v1:" + block_index_as_decimal_string` (e.g., `"zegel-block-key-v1:0"`, `"zegel-block-key-v1:1"`)
9. **HKDF extract:** `PRK = HMAC-SHA256(salt, IKM)` where IKM = masterKey || merkleRoot
10. **HKDF expand:** `T(1) = HMAC-SHA256(PRK, info || 0x01)` - since output length = hash length, only one iteration
11. **Master seal key:** `HMAC-SHA256(merkle_root, master_key || salt)` (note: root is the HMAC key, master_key||salt is the message)
12. **Master seal:** `HMAC-SHA512(seal_key, all_file_bytes_except_last_64)`
13. **AES-GCM tag length:** 16 bytes
14. **AES-GCM AAD:** Empty string (no additional authenticated data)
15. **Block splitting:** `str_split(content, 65536)` equivalent - last block may be smaller
16. **Metadata block ordering:** If present, metadata is ALWAYS block index 0, content blocks follow
17. **Metadata encoding:** JSON with `JSON_UNESCAPED_UNICODE` (preserve Unicode, don't escape to `\uXXXX`)
18. **Canary padding:** `HMAC-SHA256(master_key, recipient_id || pack_uint32_be(block_index))` -> first byte mod 16 + 1 = pad_len -> pad = mac[1..pad_len-1] || byte(pad_len)
19. **GF(256) polynomial:** 0x11B (`x^8 + x^4 + x^3 + x + 1`)
20. **Shamir share format:** 33 bytes = 1-byte x-coordinate (1-255) + 32 bytes y-values
21. **Lagrange interpolation:** At x=0 over GF(256), using Fermat's little theorem for multiplicative inverse
22. **Attestation HMAC:** `HMAC-SHA256(signer_key, merkle_root || signer_id || pack_uint64_be(timestamp) || statement)`
23. **Audit chain hash:** `SHA-256(previous_chain_hash || entry_json)`, initial = 32 zero bytes
24. **Version chain hash:** `SHA-256(previous_merkle_root || previous_master_seal)`
25. **Extended header field order:** Argon2 params, expiration, recipient ID, split-key params, version chain hash, public metadata

### Dart Crypto Libraries

Use `package:cryptography` or `package:pointycastle` for:
- AES-256-GCM encryption/decryption
- SHA-256 hashing
- HMAC-SHA256, HMAC-SHA512
- Secure random number generation

For Argon2id, use `package:argon2_ffi` or `package:sodium_libs`.

Alternatively, for native performance on mobile, consider `dart:io` + FFI bindings to platform crypto (CommonCrypto on Apple, BoringSSL on Android).

### Flutter Platform Specifics

**File Associations:**
- Register `.zgl` files with the app on all platforms
- Android: intent filter in `AndroidManifest.xml` for `application/x-zgl`
- iOS: `CFBundleDocumentTypes` in `Info.plist`
- macOS: `CFBundleDocumentTypes` + `UTImportedTypeDeclarations`
- Windows: Registry entries for `.zgl` extension
- Linux: `.desktop` file with MimeType entry, `shared-mime-info` XML

**Key Storage:**
- Android: Android Keystore
- iOS/macOS: Keychain Services
- Windows: Windows Credential Manager
- Linux: libsecret (GNOME Keyring / KDE Wallet)

**File Picking:**
- Use `package:file_picker` for cross-platform file selection
- On desktop, also support drag & drop via `package:desktop_drop`

---

## What NOT To Do

1. **Don't change the binary format** without updating FORMAT_SPEC.md version number and maintaining backwards compatibility for reading old versions.
2. **Don't add public-key signatures** to v1.x. That's v2.0 scope. The current format is symmetric-key only (with HMAC-based attestation).
3. **Don't build a web app** as the primary target. The web crypto API is fine for verification but key management in browsers is inherently weak.
4. **Don't over-engineer the GUI.** It should be simple: seal, verify, extract, with advanced features accessible but not overwhelming.
5. **Don't store split-key shares together.** The entire point is that shares are distributed to different parties.
6. **Don't log recipient IDs, master keys, or share values** in production. These are security-sensitive.

---

## Licensing

- **Code:** Apache License 2.0 (provides patent grant, enterprise-friendly)
- **Specification (FORMAT_SPEC.md):** Creative Commons Attribution 4.0 International (CC BY 4.0)
- **Test vectors:** CC0 (public domain, no restrictions)

---

## Open Source Checklist

Before the first public release:

- [ ] LICENSE file (Apache-2.0)
- [ ] README.md with badges, screenshots, installation instructions
- [ ] CONTRIBUTING.md
- [ ] SECURITY.md with responsible disclosure process
- [ ] CODE_OF_CONDUCT.md
- [ ] GitHub issue templates (bug report, feature request)
- [ ] GitHub Actions CI (test + build)
- [ ] Test vectors generated and verified against PHP (all features)
- [ ] At least one platform binary tested end-to-end
- [ ] All user-visible strings in l10n (no hardcoded text)
- [ ] `dart pub publish --dry-run` succeeds for lib/ package
- [ ] CHANGELOG.md
- [ ] Split-key M-of-N tested with multiple M/N combinations
- [ ] Canary trap tested with multiple recipients
- [ ] Redaction tested: redact -> verify -> extract works
- [ ] Selective disclosure tested: token -> extract specific blocks
- [ ] Audit trail chain hash verification tested

---

## Questions For The Human

When you start working, ask the user:
1. What should the GitHub organization/username be? (e.g., `zegel-format/zegel`)
2. Should the Dart package be published to pub.dev? If so, under what name? (`zegel`?)
3. Do they want a project logo/icon designed?
4. What's the initial set of supported languages beyond English and Dutch?
5. Should the web build be included in v1.0 or deferred?
