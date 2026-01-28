import 'dart:typed_data';

/// Constants and exception classes for the Zegel binary format specification.
///
/// All multi-byte integers in the Zegel format are big-endian (network byte
/// order). This class defines every constant referenced by the binary layout
/// described in FORMAT_SPEC.md.
class ZegelFormat {
  ZegelFormat._();

  // ---------------------------------------------------------------------------
  // Magic bytes and version
  // ---------------------------------------------------------------------------

  /// File signature: ASCII "ZEGEL" followed by \x00\x01\x00.
  static final Uint8List magic = Uint8List.fromList([
    0x5A, 0x45, 0x47, 0x45, 0x4C, // Z E G E L
    0x00, 0x01, 0x00,
  ]);

  /// Format major version.
  static const int versionMajor = 1;

  /// Format minor version.
  static const int versionMinor = 2;

  // ---------------------------------------------------------------------------
  // Block size
  // ---------------------------------------------------------------------------

  /// Default block size in bytes (64 KiB).
  static const int defaultBlockSize = 65536;

  // ---------------------------------------------------------------------------
  // Flag bitmask constants (uint16)
  // ---------------------------------------------------------------------------

  /// First block is an encrypted JSON metadata block.
  static const int flagHasMetadata = 0x0001;

  /// Content blocks are zlib-compressed before encryption.
  static const int flagCompressed = 0x0002;

  /// Master key was derived from a password via Argon2id.
  static const int flagPasswordDerived = 0x0004;

  /// Key commitment hash is present after the Merkle root.
  static const int flagHasKeyCommitment = 0x0008;

  /// File has a cryptographic expiration timestamp.
  static const int flagHasExpiration = 0x0010;

  /// Unencrypted metadata block is present in the extended header.
  static const int flagHasPublicMetadata = 0x0020;

  /// Container holds multiple files.
  static const int flagMultiFile = 0x0040;

  /// Canary trap fingerprinting is enabled.
  static const int flagHasCanary = 0x0080;

  /// One or more blocks have been permanently redacted.
  static const int flagHasRedactions = 0x0100;

  /// Master key was split using Shamir's Secret Sharing.
  static const int flagSplitKey = 0x0200;

  /// Selective disclosure index block is present.
  static const int flagSelectiveDisclosure = 0x0400;

  /// File is linked to a previous version via chain hash.
  static const int flagVersioned = 0x0800;

  // v1.3 flags

  /// File is under regulatory hold and cannot be extracted until the hold expires.
  static const int flagRegulatoryHold = 0x1000;

  /// File contains a trusted timestamp block (RFC 3161).
  static const int flagHasTimestamp = 0x2000;

  /// File was sealed in anonymous mode (no identifying metadata).
  static const int flagAnonymous = 0x4000;

  /// File has a classification level in public metadata.
  static const int flagHasClassification = 0x8000;

  // ---------------------------------------------------------------------------
  // Block type constants (uint8)
  // ---------------------------------------------------------------------------

  /// A chunk of the original file content.
  static const int blockContent = 0x01;

  /// JSON-encoded key-value metadata (encrypted).
  static const int blockMetadata = 0x02;

  /// Unencrypted metadata (integrity-protected only).
  static const int blockPublicMetadata = 0x03;

  /// Multi-file: sub-file header with name, type, block range.
  static const int blockFileHeader = 0x04;

  /// Chain of custody event record.
  static const int blockProvenance = 0x05;

  /// Permanently redacted block (original hash preserved).
  static const int blockRedacted = 0x06;

  /// Co-signature attestation from a third party.
  static const int blockAttestation = 0x07;

  /// Cross-file reference (Merkle root of another .zgl file).
  static const int blockReference = 0x08;

  /// Tamper-evident audit trail entry.
  static const int blockAudit = 0x09;

  /// Index of blocks available for selective disclosure.
  static const int blockDisclosureIndex = 0x0A;

  // v1.3 block types

  /// Trusted timestamp block (RFC 3161 token).
  static const int blockTimestamp = 0x0B;

  /// Excerpt proof block.
  static const int blockExcerpt = 0x0C;

  /// Manifest entry referencing an external file.
  static const int blockManifestEntry = 0x0D;

  // ---------------------------------------------------------------------------
  // Classification levels (v1.3)
  // ---------------------------------------------------------------------------

  /// Public classification level -- no restrictions.
  static const String classificationPublic = 'PUBLIC';

  /// Internal classification level -- organisation-internal only.
  static const String classificationInternal = 'INTERNAL';

  /// Confidential classification level -- restricted distribution.
  static const String classificationConfidential = 'CONFIDENTIAL';

  /// Secret classification level -- need-to-know basis.
  static const String classificationSecret = 'SECRET';

  /// Top Secret classification level -- highest restriction.
  static const String classificationTopSecret = 'TOP_SECRET';

  // ---------------------------------------------------------------------------
  // Attestation roles (v1.3)
  // ---------------------------------------------------------------------------

  /// The file owner / originator.
  static const String roleOwner = 'owner';

  /// A signer who cryptographically signed the attestation.
  static const String roleSigner = 'signer';

  /// A witness who observed the sealing or verification.
  static const String roleWitness = 'witness';

  /// A notary who provides independent verification.
  static const String roleNotary = 'notary';

  /// An auditor who reviewed the file for compliance.
  static const String roleAuditor = 'auditor';

  /// A reviewer who inspected the file content.
  static const String roleReviewer = 'reviewer';

  // ---------------------------------------------------------------------------
  // Field sizes in bytes
  // ---------------------------------------------------------------------------

  /// Size of the Content-Type header field (null-padded UTF-8).
  static const int contentTypeSize = 64;

  /// Maximum filename length in bytes.
  static const int maxFilenameLength = 255;

  /// Master salt size in bytes.
  static const int saltSize = 32;

  /// SHA-256 hash output size in bytes.
  static const int hashSize = 32;

  /// AES-GCM IV/nonce size in bytes.
  static const int ivSize = 12;

  /// AES-GCM authentication tag size in bytes.
  static const int tagSize = 16;

  /// Master seal (HMAC-SHA512) size in bytes.
  static const int sealSize = 64;

  /// Block directory entry size: type(1) + hash(32) + len(4) + iv(12) + tag(16).
  static const int blockDirectoryEntrySize = 65;

  // ---------------------------------------------------------------------------
  // Key derivation
  // ---------------------------------------------------------------------------

  /// HKDF info prefix for per-block key derivation.
  static const String hkdfInfoPrefix = 'zegel-block-key-v1:';
}

// =============================================================================
// Exception hierarchy
// =============================================================================

/// Base exception for all Zegel-related errors.
class ZegelException implements Exception {
  /// Creates a [ZegelException] with the given [message].
  const ZegelException(this.message);

  /// Human-readable description of the error.
  final String message;

  @override
  String toString() => 'ZegelException: $message';
}

/// Thrown when the binary format is invalid or cannot be parsed.
///
/// This covers structural issues such as bad magic bytes, truncated headers,
/// unsupported versions, or malformed block directories.
class ZegelFormatException extends ZegelException {
  /// Creates a [ZegelFormatException] with the given [message].
  const ZegelFormatException(super.message);

  @override
  String toString() => 'ZegelFormatException: $message';
}

/// Thrown when cryptographic verification detects tampering.
///
/// This indicates that the file content, Merkle tree, key commitment, or
/// master seal does not match expectations. The content is irrecoverable.
class ZegelTamperedException extends ZegelException {
  /// Creates a [ZegelTamperedException] with the given [message].
  const ZegelTamperedException(super.message);

  @override
  String toString() => 'ZegelTamperedException: $message';
}

/// Thrown when a file's cryptographic expiration has passed.
///
/// Once expired, per-block keys cannot be derived because the expiration date
/// is baked into the HKDF info string. Extraction is impossible.
class ZegelExpiredException extends ZegelException {
  /// Creates a [ZegelExpiredException] with the given [message].
  const ZegelExpiredException(super.message);

  @override
  String toString() => 'ZegelExpiredException: $message';
}

/// Thrown when a file is under regulatory hold and cannot be extracted.
///
/// A regulatory hold prevents any extraction or modification of the sealed
/// content until the hold date has passed. This is used for compliance with
/// data retention regulations (e.g. SEC 17a-4, GDPR litigation holds).
class ZegelRegulatoryHoldException extends ZegelException {
  /// Creates a [ZegelRegulatoryHoldException] with the given [message].
  const ZegelRegulatoryHoldException(super.message);

  @override
  String toString() => 'ZegelRegulatoryHoldException: $message';
}
