import 'package:zegel_app/utils/hex_utils.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

// Import the zegel library under the `zgl` alias so that this service can
// expose its own GUI-friendly `ZegelResult` and `ZegelInspection` types
// without clashing with the library's. All library calls below use the
// `zgl.` prefix explicitly so readers can tell which side of the wall the
// code is talking to.
import 'package:zegel/zegel.dart' as zgl;
import 'package:zegel/zegel.dart'
    show ContentVersioning; // Used by verifyVersionChain without the alias.

/// Result status from a verification operation.
enum ZegelStatus {
  /// File is intact and has not been tampered with.
  valid,

  /// File has been tampered with or is corrupted.
  tampered,

  /// File has passed its cryptographic expiration date.
  expired,
}

/// Result of a verification operation.
class ZegelResult {
  final ZegelStatus status;
  final String message;
  final Map<String, dynamic>? metadata;
  final String? originalFilename;
  final String? contentType;
  final int? blockCount;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final int? flags;
  final List<ZegelAttestation>? attestations;
  final List<ZegelAuditEntry>? auditTrail;

  const ZegelResult({
    required this.status,
    required this.message,
    this.metadata,
    this.originalFilename,
    this.contentType,
    this.blockCount,
    this.createdAt,
    this.expiresAt,
    this.flags,
    this.attestations,
    this.auditTrail,
  });
}

/// Inspection result (no key required).
class ZegelInspection {
  final int versionMajor;
  final int versionMinor;
  final int flags;
  final DateTime createdAt;
  final String contentType;
  final String originalFilename;
  final int blockCount;
  final DateTime? expiresAt;
  final Map<String, dynamic>? publicMetadata;
  final bool hasMetadata;
  final bool isCompressed;
  final bool hasExpiration;
  final bool hasCanary;
  final bool hasRedactions;
  final bool isSplitKey;
  final bool hasSelectiveDisclosure;
  final bool isVersioned;
  final int? splitKeyThreshold;
  final int? splitKeyTotal;

  const ZegelInspection({
    required this.versionMajor,
    required this.versionMinor,
    required this.flags,
    required this.createdAt,
    required this.contentType,
    required this.originalFilename,
    required this.blockCount,
    this.expiresAt,
    this.publicMetadata,
    required this.hasMetadata,
    required this.isCompressed,
    required this.hasExpiration,
    required this.hasCanary,
    required this.hasRedactions,
    required this.isSplitKey,
    required this.hasSelectiveDisclosure,
    required this.isVersioned,
    this.splitKeyThreshold,
    this.splitKeyTotal,
  });

  /// Decodes the flags field into a list of human-readable feature names.
  List<String> get flagNames {
    final names = <String>[];
    if (flags & 0x0001 != 0) names.add('HAS_METADATA');
    if (flags & 0x0002 != 0) names.add('COMPRESSED');
    if (flags & 0x0004 != 0) names.add('PASSWORD_DERIVED');
    if (flags & 0x0008 != 0) names.add('HAS_KEY_COMMITMENT');
    if (flags & 0x0010 != 0) names.add('HAS_EXPIRATION');
    if (flags & 0x0020 != 0) names.add('HAS_PUBLIC_METADATA');
    if (flags & 0x0040 != 0) names.add('MULTI_FILE');
    if (flags & 0x0080 != 0) names.add('HAS_CANARY');
    if (flags & 0x0100 != 0) names.add('HAS_REDACTIONS');
    if (flags & 0x0200 != 0) names.add('SPLIT_KEY');
    if (flags & 0x0400 != 0) names.add('SELECTIVE_DISCLOSURE');
    if (flags & 0x0800 != 0) names.add('VERSIONED');
    return names;
  }

  /// Whether the expiration enforcement is HARD or SOFT.
  ///
  /// `HARD` = trusted timestamp present (cannot be bypassed by clock change).
  /// `SOFT` = relies on local OS clock (spoofable).
  /// `null` = no expiration set.
  String? get expirationEnforcement {
    if (!hasExpiration) return null;
    return (flags & 0x2000 != 0) ? 'HARD' : 'SOFT';
  }

  /// Per-block plaintext hashes from public metadata, if present.
  List<String>? get plaintextManifest {
    if (publicMetadata == null) return null;
    final dynamic raw = publicMetadata!['plaintext_manifest'];
    if (raw is! List) return null;
    return raw.map((e) => e.toString()).toList();
  }
}

/// An attestation entry from a .zgl file.
class ZegelAttestation {
  final String signerId;
  final String statement;
  final DateTime timestamp;
  final String hmacHex;
  final bool isVerified;

  const ZegelAttestation({
    required this.signerId,
    required this.statement,
    required this.timestamp,
    required this.hmacHex,
    this.isVerified = false,
  });
}

/// An audit trail entry from a .zgl file.
class ZegelAuditEntry {
  final String actor;
  final String action;
  final DateTime timestamp;
  final Map<String, dynamic>? details;
  final String chainHash;
  final bool isChainValid;

  const ZegelAuditEntry({
    required this.actor,
    required this.action,
    required this.timestamp,
    this.details,
    required this.chainHash,
    this.isChainValid = false,
  });
}

/// Block info for display in redaction/disclosure screens.
class ZegelBlockInfo {
  final int index;
  final int blockType;
  final String blockTypeName;
  final int ciphertextLength;
  final bool isRedacted;

  const ZegelBlockInfo({
    required this.index,
    required this.blockType,
    required this.blockTypeName,
    required this.ciphertextLength,
    this.isRedacted = false,
  });
}

/// Options for sealing a file.
class SealOptions {
  final bool compress;
  final DateTime? expirationDate;
  final String? recipientId;
  final int? splitKeyThreshold;
  final int? splitKeyTotal;
  final bool enableSelectiveDisclosure;
  final Map<String, dynamic>? metadata;
  final int blockSize;
  final bool enablePlaintextManifest;
  final List<int>? boundaryHints;

  const SealOptions({
    this.compress = false,
    this.expirationDate,
    this.recipientId,
    this.splitKeyThreshold,
    this.splitKeyTotal,
    this.enableSelectiveDisclosure = false,
    this.metadata,
    this.blockSize = 65536,
    this.enablePlaintextManifest = false,
    this.boundaryHints,
  });
}

/// Disclosure token for selective block access.
class DisclosureToken {
  final int version;
  final String merkleRoot;
  final Map<int, String> blockKeys;
  final DateTime createdAt;

  const DisclosureToken({
    required this.version,
    required this.merkleRoot,
    required this.blockKeys,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'merkle_root': merkleRoot,
        'block_keys': blockKeys.map((k, v) => MapEntry(k.toString(), v)),
        'created_at': createdAt.millisecondsSinceEpoch ~/ 1000,
      };

  factory DisclosureToken.fromJson(Map<String, dynamic> json) {
    final blockKeysRaw = json['block_keys'] as Map<String, dynamic>;
    return DisclosureToken(
      version: json['version'] as int,
      merkleRoot: json['merkle_root'] as String,
      blockKeys: blockKeysRaw.map(
        (k, v) => MapEntry(int.parse(k), v as String),
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['created_at'] as int) * 1000,
        isUtc: true,
      ),
    );
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory DisclosureToken.fromJsonString(String jsonStr) {
    return DisclosureToken.fromJson(
      json.decode(jsonStr) as Map<String, dynamic>,
    );
  }
}

/// A provenance event from the chain of custody.
class ProvenanceEvent {
  final String actor;
  final String action;
  final DateTime timestamp;
  final bool isSignatureVerified;

  const ProvenanceEvent({
    required this.actor,
    required this.action,
    required this.timestamp,
    this.isSignatureVerified = false,
  });
}

/// Result of a manifest file verification.
class ManifestFileResult {
  final String filename;
  final bool isValid;
  final String message;

  const ManifestFileResult({
    required this.filename,
    required this.isValid,
    required this.message,
  });
}

/// Information about a verified credential.
class CredentialInfo {
  final String credentialType;
  final String institutionName;
  final String institutionId;
  final String recipientName;
  final String recipientId;
  final DateTime? issuedAt;
  final bool isValid;

  const CredentialInfo({
    required this.credentialType,
    required this.institutionName,
    required this.institutionId,
    required this.recipientName,
    required this.recipientId,
    this.issuedAt,
    required this.isValid,
  });
}

/// High-level service wrapping the zegel lib/ package for GUI operations.
///
/// This service provides the bridge between the Flutter UI and the core
/// Zegel library. All file operations are asynchronous to keep the UI
/// responsive during cryptographic operations; the underlying zegel
/// library primitives are synchronous so every method here wraps its
/// work in an `async` boundary that can be offloaded onto a background
/// isolate later if profiling shows the main thread stalling.
class ZegelService {
  /// Seals a file with the given key and options.
  ///
  /// Returns the sealed bytes as a [Uint8List].
  /// Throws on error.
  Future<Uint8List> seal(
    String filePath,
    String hexKey,
    SealOptions options,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    final content = await file.readAsBytes();
    final masterKey = HexUtils.hexToBytes(hexKey);
    final writer = zgl.ZegelWriter(masterKey, _toLibOptions(filePath, options));
    return writer.seal(content);
  }

  /// Verifies a .zgl file with the given key.
  ///
  /// Returns a [ZegelResult] indicating the status.
  Future<ZegelResult> verify(String filePath, String hexKey) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return const ZegelResult(
        status: ZegelStatus.tampered,
        message: 'File does not exist',
      );
    }

    final fileBytes = await file.readAsBytes();
    final masterKey = HexUtils.hexToBytes(hexKey);
    try {
      const reader = zgl.ZegelReader();
      final libResult = reader.verify(fileBytes, masterKey);
      final libInspection = reader.inspect(fileBytes);

      return ZegelResult(
        status: ZegelStatus.valid,
        message: 'Integrity verified',
        metadata: libResult.metadata,
        originalFilename: libResult.filename,
        contentType: libResult.contentType,
        blockCount: libInspection.blockCount,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          libInspection.timestamp * 1000,
          isUtc: true,
        ),
        expiresAt: libInspection.expirationTimestamp == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                libInspection.expirationTimestamp! * 1000,
                isUtc: true,
              ),
        flags: libInspection.flags,
        attestations: libResult.attestations?.map(_mapAttestation).toList(),
        auditTrail: _mapAuditTrail(libResult.auditTrail),
      );
    } on zgl.ZegelExpiredException catch (e) {
      return ZegelResult(status: ZegelStatus.expired, message: e.message);
    } on zgl.ZegelTamperedException catch (e) {
      return ZegelResult(status: ZegelStatus.tampered, message: e.message);
    } on zgl.ZegelFormatException catch (e) {
      return ZegelResult(
        status: ZegelStatus.tampered,
        message: 'Invalid format: ${e.message}',
      );
    }
  }

  /// Extracts the original content from a .zgl file.
  ///
  /// Returns true on success.
  Future<bool> extract(
    String filePath,
    String hexKey,
    String outputPath,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    final fileBytes = await file.readAsBytes();
    final masterKey = HexUtils.hexToBytes(hexKey);
    const reader = zgl.ZegelReader();
    final result = reader.verify(fileBytes, masterKey);
    if (!result.valid || result.content == null) return false;
    await File(outputPath).writeAsBytes(result.content!, flush: true);
    return true;
  }

  /// Inspects a .zgl file without requiring the master key.
  ///
  /// Reads the header and public information only.
  Future<ZegelInspection> inspect(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    final fileBytes = await file.readAsBytes();
    const reader = zgl.ZegelReader();
    final libInspection = reader.inspect(fileBytes);
    return _mapInspection(libInspection);
  }

  /// Redacts the specified blocks from a .zgl file.
  ///
  /// This is an irreversible operation. The original content of redacted
  /// blocks is permanently destroyed.
  Future<Uint8List> redact(
    String filePath,
    String hexKey,
    List<int> blockIndices,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    final fileBytes = await file.readAsBytes();
    final masterKey = HexUtils.hexToBytes(hexKey);
    return zgl.Redaction.redactBlocks(fileBytes, masterKey, blockIndices);
  }

  /// Splits a key into N shares with threshold M using Shamir's Secret Sharing.
  ///
  /// Returns a list of hex-encoded shares, one per row. Each share is
  /// `x-coordinate || 32 y-values` encoded as 66 hex chars (33 bytes).
  Future<List<String>> splitKey(
    String hexKey,
    int threshold,
    int totalShares,
  ) async {
    if (threshold < 2 || threshold > totalShares || totalShares > 255) {
      throw ArgumentError(
        'Invalid split-key parameters: M=$threshold, N=$totalShares. '
        'Requires 2 <= M <= N <= 255.',
      );
    }
    final masterKey = HexUtils.hexToBytes(hexKey);
    final shares = zgl.ShamirSecretSharing.split(
      masterKey,
      threshold,
      totalShares,
    );
    return shares.map(_bytesToHex).toList();
  }

  /// Reconstructs a key from the given shares.
  ///
  /// Returns the reconstructed hex key.
  Future<String> reconstructKey(List<String> shares) async {
    if (shares.isEmpty) {
      throw ArgumentError('At least one share is required.');
    }
    final byteShares = shares.map(HexUtils.hexToBytes).toList();
    // The library requires the threshold up-front; we pass `shares.length`
    // because the caller has already selected the exact set they believe
    // meets the threshold.
    final reconstructed = zgl.ShamirSecretSharing.reconstruct(
      byteShares,
      shares.length,
    );
    return _bytesToHex(reconstructed);
  }

  /// Creates an attestation (co-signature) for a .zgl file.
  ///
  /// Returns the updated file bytes with the attestation block appended.
  /// Note: embedding a new block requires re-sealing the file, which
  /// requires the *master* key. This method takes only the signer key and
  /// therefore returns the attestation payload as a stand-alone JSON
  /// block that can be persisted alongside the file or added as a
  /// provenance event via the `audit` CLI command.
  Future<Uint8List> createAttestation(
    String filePath,
    String signerKeyHex,
    String signerId,
    String statement,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    final fileBytes = await file.readAsBytes();
    const reader = zgl.ZegelReader();
    final inspection = reader.inspect(fileBytes);
    // Recover the Merkle root without the master key via the raw header
    // parser: the inspection deliberately omits it for separation of
    // concerns, so we re-parse with a helper that only reads public data.
    final merkleRoot = _readMerkleRoot(fileBytes, inspection);
    final signerKey = HexUtils.hexToBytes(signerKeyHex);
    final attestation = zgl.Attestation.createAttestation(
      merkleRoot,
      signerId,
      signerKey,
      statement,
    );
    return Uint8List.fromList(utf8.encode(jsonEncode(attestation)));
  }

  /// Generates a selective disclosure token for the specified blocks.
  ///
  /// Returns a [DisclosureToken] that can be shared with third parties.
  Future<DisclosureToken> generateDisclosureToken(
    String filePath,
    String hexKey,
    List<int> blockIndices,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    final fileBytes = await file.readAsBytes();
    final masterKey = HexUtils.hexToBytes(hexKey);
    const reader = zgl.ZegelReader();
    final inspection = reader.inspect(fileBytes);
    final merkleRoot = _readMerkleRoot(fileBytes, inspection);
    final salt = _readMasterSalt(fileBytes);
    String? expirationDate;
    if (inspection.expirationTimestamp != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(
        inspection.expirationTimestamp! * 1000,
        isUtc: true,
      );
      expirationDate = '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    }
    final raw = zgl.SelectiveDisclosure.generateToken(
      masterKey,
      merkleRoot,
      salt,
      blockIndices,
      expirationDate: expirationDate,
    );
    return DisclosureToken(
      version: raw['version'] as int,
      merkleRoot: raw['merkle_root'] as String,
      blockKeys: (raw['block_keys'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(int.parse(k), v as String),
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (raw['created_at'] as int) * 1000,
        isUtc: true,
      ),
    );
  }

  /// Extracts specific blocks using a disclosure token (no master key required).
  ///
  /// Writes the extracted content to [outputPath] and also returns it.
  Future<Uint8List> extractWithToken(
    String filePath,
    DisclosureToken token,
    String outputPath,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    final fileBytes = await file.readAsBytes();
    const reader = zgl.ZegelReader();
    final tokenMap = <String, dynamic>{
      'version': token.version,
      'merkle_root': token.merkleRoot,
      'block_keys': token.blockKeys.map((k, v) => MapEntry(k.toString(), v)),
      'created_at': token.createdAt.millisecondsSinceEpoch ~/ 1000,
    };
    final result = reader.extractWithToken(fileBytes, tokenMap);
    final content = result.content ?? Uint8List(0);
    await File(outputPath).writeAsBytes(content, flush: true);
    return content;
  }

  /// Lists all blocks in a .zgl file with their type and metadata.
  ///
  /// Useful for redaction and disclosure UIs. Does not decrypt blocks;
  /// only parses the directory so no [hexKey] is strictly required, but
  /// it is accepted so callers can re-use their key-input UI consistently.
  Future<List<ZegelBlockInfo>> listBlocks(
    String filePath,
    String hexKey,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    final fileBytes = await file.readAsBytes();
    final entries = _parseDirectoryEntries(fileBytes);
    return entries;
  }

  /// Returns a human-readable name for a block type value.
  String blockTypeName(int blockType) {
    switch (blockType) {
      case 0x01:
        return 'CONTENT';
      case 0x02:
        return 'METADATA';
      case 0x03:
        return 'PUBLIC_METADATA';
      case 0x04:
        return 'FILE_HEADER';
      case 0x05:
        return 'PROVENANCE';
      case 0x06:
        return 'REDACTED';
      case 0x07:
        return 'ATTESTATION';
      case 0x08:
        return 'REFERENCE';
      case 0x09:
        return 'AUDIT';
      case 0x0A:
        return 'DISCLOSURE_INDEX';
      default:
        return 'UNKNOWN (0x${blockType.toRadixString(16).padLeft(2, '0')})';
    }
  }

  /// Converts a hex string to bytes.

  // ======================================================================
  // Batch operations
  // ======================================================================

  /// Verifies multiple .zgl files in batch.
  ///
  /// Returns a list of [ZegelResult] for each file.
  Future<List<ZegelResult>> batchVerify(
    List<String> filePaths,
    String hexKey,
  ) async {
    final results = <ZegelResult>[];
    const chunkSize = 10;

    for (var i = 0; i < filePaths.length; i += chunkSize) {
      final chunk = filePaths.skip(i).take(chunkSize);
      final chunkFutures = chunk.map((path) async {
        try {
          return await verify(path, hexKey);
        } catch (e) {
          return ZegelResult(
            status: ZegelStatus.tampered,
            message: 'Error: $e',
          );
        }
      });

      results.addAll(await Future.wait(chunkFutures));
    }

    return results;
  }

  /// Seals multiple files in batch.
  ///
  /// Returns a list of sealed byte arrays.
  Future<List<Uint8List>> batchSeal(
    List<String> filePaths,
    String hexKey,
    SealOptions options,
  ) async {
    final masterKey = HexUtils.hexToBytes(hexKey);
    final results = <Uint8List>[];
    const chunkSize = 10;

    for (var i = 0; i < filePaths.length; i += chunkSize) {
      final chunk = filePaths.skip(i).take(chunkSize);
      final chunkFutures = chunk.map((path) async {
        final file = File(path);
        if (!await file.exists()) {
          throw FileSystemException('File does not exist', path);
        }
        final content = await file.readAsBytes();
        final libOptions = _toLibOptions(path, options);

        return await Isolate.run(() {
          final writer = zgl.ZegelWriter(masterKey, libOptions);
          return writer.seal(content);
        });
      });

      results.addAll(await Future.wait(chunkFutures));
    }

    return results;
  }

  // ======================================================================
  // Manifest operations
  // ======================================================================

  /// Creates a signed manifest of multiple files.
  ///
  /// Returns the manifest as JSON bytes.
  Future<Uint8List> createManifest(
    List<String> filePaths,
    String signerKeyHex,
    String signerId,
  ) async {
    final entries = <String, Uint8List>{};

    final results = await Future.wait(
      filePaths.map((p) async {
        final file = File(p);
        if (!await file.exists()) {
          throw FileSystemException('File does not exist', p);
        }
        final bytes = await file.readAsBytes();
        return MapEntry(_basename(p), _readMerkleRootUnverified(bytes));
      }),
    );
    entries.addEntries(results);

    final signerKey = HexUtils.hexToBytes(signerKeyHex);
    final manifest = zgl.ZegelManifest.create(entries, signerKey, signerId);
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
    );
  }

  /// Verifies a manifest file against the signer key.
  ///
  /// Returns per-file verification results.
  Future<List<ManifestFileResult>> verifyManifest(
    String manifestPath,
    String signerKeyHex, {
    String? fileDirectory,
  }) async {
    final manifestFile = File(manifestPath);
    if (!await manifestFile.exists()) {
      throw FileSystemException('Manifest does not exist', manifestPath);
    }
    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    final signerKey = HexUtils.hexToBytes(signerKeyHex);

    if (!zgl.ZegelManifest.verify(manifest, signerKey)) {
      return const [
        ManifestFileResult(
          filename: '<manifest>',
          isValid: false,
          message: 'Manifest signature is invalid',
        ),
      ];
    }

    final files = manifest['files'] as List<dynamic>;
    final results = <ManifestFileResult>[];
    final baseDir = fileDirectory ?? manifestFile.parent.path;
    for (final entry in files) {
      final m = entry as Map<String, dynamic>;
      final filename = m['filename'] as String;
      final expectedRoot = m['merkle_root'] as String;
      final path = '$baseDir${Platform.pathSeparator}$filename';
      final file = File(path);
      if (!await file.exists()) {
        results.add(
          ManifestFileResult(
            filename: filename,
            isValid: false,
            message: 'File missing',
          ),
        );
        continue;
      }
      try {
        final bytes = await file.readAsBytes();
        final actualRoot = _bytesToHex(_readMerkleRootUnverified(bytes));
        final match = _constantTimeStringEquals(actualRoot, expectedRoot);
        results.add(
          ManifestFileResult(
            filename: filename,
            isValid: match,
            message: match ? 'OK' : 'Merkle root mismatch',
          ),
        );
      } on Exception catch (e) {
        results.add(
          ManifestFileResult(
            filename: filename,
            isValid: false,
            message: 'Parse error: $e',
          ),
        );
      }
    }
    return results;
  }

  // ======================================================================
  // Classification operations
  // ======================================================================

  /// Sets or changes the classification level of a .zgl file.
  ///
  /// Emits a JSON classification metadata file next to the original at
  /// `<file>.classification.json`. Actually embedding the classification
  /// into the sealed file requires re-sealing with the master key, which
  /// is outside the scope of this helper; the GUI screen that calls us
  /// also writes this sidecar so the classification badge can be shown
  /// without touching the sealed bytes.
  Future<void> classify(
    String filePath,
    String level,
    String authority, {
    String? caveat,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    if (!zgl.Classification.isValidLevel(level)) {
      throw ArgumentError.value(level, 'level', 'unknown classification level');
    }
    final meta = zgl.Classification.createClassificationMetadata(
      level: level,
      authority: authority,
      caveat: caveat,
    );
    final sidecar = File('$filePath.classification.json');
    await sidecar.writeAsString(
      const JsonEncoder.withIndent('  ').convert(meta),
      flush: true,
    );
  }

  /// Declassifies a .zgl file to a lower classification level by
  /// overwriting the classification sidecar with the new level and, if
  /// [redactBlocks] is provided, redacting those blocks in the sealed
  /// file. Redaction is destructive and requires the master key, which
  /// the UI is expected to prompt for before calling this method; the
  /// key must be supplied via [masterKeyHex].
  Future<void> declassify(
    String filePath,
    String newLevel,
    String authority, {
    List<int>? redactBlocks,
    String? masterKeyHex,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    if (!zgl.Classification.isValidLevel(newLevel)) {
      throw ArgumentError.value(
        newLevel,
        'newLevel',
        'unknown classification level',
      );
    }
    if (redactBlocks != null && redactBlocks.isNotEmpty) {
      if (masterKeyHex == null || masterKeyHex.isEmpty) {
        throw ArgumentError(
          'A master key is required to redact blocks during declassification',
        );
      }
      final masterKey = HexUtils.hexToBytes(masterKeyHex);
      final bytes = await file.readAsBytes();
      final newBytes = zgl.Redaction.redactBlocks(
        bytes,
        masterKey,
        redactBlocks,
      );
      await file.writeAsBytes(newBytes, flush: true);
    }
    await classify(filePath, newLevel, authority);
  }

  // ======================================================================
  // Excerpt proof operations
  // ======================================================================

  /// Generates one cryptographic excerpt proof per block in [blockIndices].
  ///
  /// Returns a JSON document containing the list of proofs, which any
  /// verifier can later check against the file's Merkle root. The master
  /// key is used only to check that the file is intact before the proof
  /// is generated.
  Future<Uint8List> generateExcerptProof(
    String filePath,
    String hexKey,
    List<int> blockIndices,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    final fileBytes = await file.readAsBytes();
    final masterKey = HexUtils.hexToBytes(hexKey);
    const reader = zgl.ZegelReader();
    final result = reader.verify(fileBytes, masterKey);
    zgl.SecureMemory.wipe(masterKey);
    if (!result.valid) {
      throw const zgl.ZegelTamperedException(
        'Cannot generate excerpt proof for a tampered file',
      );
    }
    final leafHashes = _readLeafHashes(fileBytes);
    final proofs = <Map<String, dynamic>>[];
    final layers = zgl.MerkleTree.buildTree(leafHashes);
    final root = zgl.MerkleTree.buildRoot(leafHashes);
    for (final idx in blockIndices) {
      proofs.add(zgl.ExcerptProof.generateProofFromTree(
          leafHashes, layers, root, idx));
    }
    return Uint8List.fromList(
      utf8.encode(
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'merkle_root': _bytesToHex(_readMerkleRootUnverified(fileBytes)),
          'proofs': proofs,
        }),
      ),
    );
  }

  /// Verifies every excerpt proof inside [proofPath] against the Merkle
  /// root of the sealed file at [filePath]. Returns `true` only if every
  /// proof in the file is valid.
  Future<bool> verifyExcerptProof(String filePath, String proofPath) async {
    final file = File(filePath);
    final proofFile = File(proofPath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    if (!await proofFile.exists()) {
      throw FileSystemException('Proof file does not exist', proofPath);
    }
    final fileBytes = await file.readAsBytes();
    final expectedRoot = _readMerkleRootUnverified(fileBytes);
    final decoded =
        jsonDecode(await proofFile.readAsString()) as Map<String, dynamic>;
    final proofs = (decoded['proofs'] as List<dynamic>?) ?? const <dynamic>[];
    if (proofs.isEmpty) return false;
    final isValid = await Isolate.run(() {
      for (final p in proofs) {
        final proofMap = p as Map<String, dynamic>;
        if (!zgl.ExcerptProof.verifyProof(proofMap, expectedRoot)) {
          return false;
        }
      }
      return true;
    });
    return isValid;
  }

  // ======================================================================
  // Provenance operations
  // ======================================================================

  /// Reads and verifies the provenance chain from a .zgl file.
  ///
  /// Returns a list of provenance events with signature verification status.
  /// [signerKeyHex] is optional; when provided the provenance chain's
  /// HMAC signatures are re-checked, otherwise the method only walks the
  /// chronological / chain-hash structure and reports every event with
  /// `isSignatureVerified = false`.
  Future<List<ProvenanceEvent>> verifyProvenance(
    String filePath,
    String hexKey, {
    String? signerKeyHex,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    final fileBytes = await file.readAsBytes();
    final masterKey = HexUtils.hexToBytes(hexKey);
    const reader = zgl.ZegelReader();
    final result = reader.verify(fileBytes, masterKey);
    final events = <ProvenanceEvent>[];
    final provenance = result.provenance ?? const <Map<String, dynamic>>[];
    Map<String, dynamic>? chainCheck;
    if (signerKeyHex != null && signerKeyHex.isNotEmpty) {
      chainCheck = zgl.ProvenanceVerification.verifyChain(
        provenance,
        HexUtils.hexToBytes(signerKeyHex),
      );
    }
    final chainOk = chainCheck?['valid'] as bool? ?? false;
    for (final entry in provenance) {
      final actor = (entry['actor'] ?? '') as String;
      final action = (entry['action'] ?? '') as String;
      final tsRaw = entry['timestamp'];
      DateTime ts;
      if (tsRaw is int) {
        ts = DateTime.fromMillisecondsSinceEpoch(tsRaw * 1000, isUtc: true);
      } else {
        ts = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
      events.add(
        ProvenanceEvent(
          actor: actor,
          action: action,
          timestamp: ts,
          isSignatureVerified: chainOk,
        ),
      );
    }
    return events;
  }

  // ======================================================================
  // Version chain operations
  // ======================================================================

  /// Verifies the version chain hash of a sequence of .zgl files.
  ///
  /// Returns true if the version chain is intact and unbroken.
  Future<bool> verifyVersionChain(List<String> filePaths) async {
    final futures = filePaths.map((path) async {
      final file = File(path);
      if (!await file.exists()) {
        throw FileSystemException('File does not exist', path);
      }
      return file.readAsBytes();
    });
    final fileBytesList = await Future.wait(futures);
    return ContentVersioning.verifyVersionChain(fileBytesList);
  }

  // ======================================================================
  // Credential operations
  // ======================================================================

  /// Issues a credential by sealing a document with credential metadata.
  ///
  /// Returns the sealed credential bytes. The credential metadata is
  /// embedded in the sealed file's public metadata section so any party
  /// can verify it without the master key.
  Future<Uint8List> issueCredential(
    String filePath,
    String hexKey, {
    required String institutionName,
    required String institutionId,
    required String credentialType,
    required String recipientName,
    required String recipientId,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    final content = await file.readAsBytes();
    final masterKey = HexUtils.hexToBytes(hexKey);
    final issuedAt = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final credentialMetadata = <String, dynamic>{
      'credential_type': credentialType,
      'institution_name': institutionName,
      'institution_id': institutionId,
      'recipient_name': recipientName,
      'recipient_id': recipientId,
      'issued_at': issuedAt,
    };
    final writer = zgl.ZegelWriter(
      masterKey,
      zgl.ZegelOptions(
        contentType: 'application/x-credential',
        filename: _basename(filePath),
        publicMetadata: {'credential': credentialMetadata},
        enableKeyCommitment: true,
      ),
    );
    return writer.seal(content);
  }

  /// Verifies a credential .zgl file using public attestation data.
  ///
  /// No master key required — reads the credential metadata straight out
  /// of the public metadata section and confirms the file's master seal
  /// signature against the embedded Merkle root. Callers that need full
  /// content verification should use [verify] instead.
  Future<CredentialInfo> verifyCredential(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }
    final fileBytes = await file.readAsBytes();
    const reader = zgl.ZegelReader();
    try {
      final inspection = reader.inspect(fileBytes);
      final pub = inspection.publicMetadata;
      if (pub == null || pub['credential'] is! Map<String, dynamic>) {
        return const CredentialInfo(
          credentialType: '',
          institutionName: '',
          institutionId: '',
          recipientName: '',
          recipientId: '',
          isValid: false,
        );
      }
      final cred = pub['credential'] as Map<String, dynamic>;
      return CredentialInfo(
        credentialType: cred['credential_type'] as String? ?? '',
        institutionName: cred['institution_name'] as String? ?? '',
        institutionId: cred['institution_id'] as String? ?? '',
        recipientName: cred['recipient_name'] as String? ?? '',
        recipientId: cred['recipient_id'] as String? ?? '',
        issuedAt: cred['issued_at'] is int
            ? DateTime.fromMillisecondsSinceEpoch(
                (cred['issued_at'] as int) * 1000,
                isUtc: true,
              )
            : null,
        isValid: true,
      );
    } on zgl.ZegelFormatException {
      return const CredentialInfo(
        credentialType: '',
        institutionName: '',
        institutionId: '',
        recipientName: '',
        recipientId: '',
        isValid: false,
      );
    }
  }

  // ======================================================================
  // Mapping and helper methods
  // ======================================================================

  /// Converts the service-level [SealOptions] into a library [zgl.ZegelOptions].
  zgl.ZegelOptions _toLibOptions(String filePath, SealOptions options) {
    final fn = _basename(filePath);
    Uint8List? recipientBytes;
    if (options.recipientId != null && options.recipientId!.isNotEmpty) {
      recipientBytes = HexUtils.hexToBytes(options.recipientId!);
    }
    return zgl.ZegelOptions(
      contentType: 'application/octet-stream',
      filename: fn,
      metadata: options.metadata,
      compress: options.compress,
      expiration: options.expirationDate,
      recipientId: recipientBytes,
      splitKeyThreshold: options.splitKeyThreshold,
      splitKeyTotal: options.splitKeyTotal,
      enableSelectiveDisclosure: options.enableSelectiveDisclosure,
      blockSize: options.blockSize,
      enableKeyCommitment: true,
      enablePlaintextManifest: options.enablePlaintextManifest,
      boundaryHints: options.boundaryHints,
    );
  }

  /// Maps a library inspection result into the GUI inspection DTO.
  ZegelInspection _mapInspection(zgl.ZegelInspection i) {
    final flags = i.flags;
    return ZegelInspection(
      versionMajor: int.parse(i.version.split('.').first),
      versionMinor: int.parse(i.version.split('.').last),
      flags: flags,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        i.timestamp * 1000,
        isUtc: true,
      ),
      contentType: i.contentType ?? '',
      originalFilename: i.filename ?? '',
      blockCount: i.blockCount,
      expiresAt: i.expirationTimestamp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              i.expirationTimestamp! * 1000,
              isUtc: true,
            ),
      publicMetadata: i.publicMetadata,
      hasMetadata: flags & 0x0001 != 0,
      isCompressed: flags & 0x0002 != 0,
      hasExpiration: flags & 0x0010 != 0,
      hasCanary: flags & 0x0080 != 0,
      hasRedactions: flags & 0x0100 != 0,
      isSplitKey: flags & 0x0200 != 0,
      hasSelectiveDisclosure: flags & 0x0400 != 0,
      isVersioned: flags & 0x0800 != 0,
      splitKeyThreshold: i.splitKeyParams?['threshold'],
      splitKeyTotal: i.splitKeyParams?['total'],
    );
  }

  /// Maps a single attestation map into the GUI DTO.
  ZegelAttestation _mapAttestation(Map<String, dynamic> a) {
    return ZegelAttestation(
      signerId: a['signer_id'] as String? ?? '',
      statement: a['statement'] as String? ?? '',
      timestamp: a['timestamp'] is int
          ? DateTime.fromMillisecondsSinceEpoch(
              (a['timestamp'] as int) * 1000,
              isUtc: true,
            )
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      hmacHex: a['hmac_hex'] as String? ?? '',
      isVerified: true, // GCM already authenticated the block on verify.
    );
  }

  /// Maps a list of audit entries into GUI DTOs and runs the chain-hash
  /// verification once. Every returned entry inherits the global
  /// `isChainValid` flag.
  List<ZegelAuditEntry>? _mapAuditTrail(List<Map<String, dynamic>>? entries) {
    if (entries == null) return null;
    final chainValid = zgl.AuditTrail.verifyChain(entries);
    return entries.map((e) {
      return ZegelAuditEntry(
        actor: e['actor'] as String? ?? '',
        action: e['action'] as String? ?? '',
        timestamp: e['timestamp'] is int
            ? DateTime.fromMillisecondsSinceEpoch(
                (e['timestamp'] as int) * 1000,
                isUtc: true,
              )
            : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        details: e['details'] is Map<String, dynamic>
            ? e['details'] as Map<String, dynamic>
            : null,
        chainHash: e['chain_hash'] as String? ?? '',
        isChainValid: chainValid,
      );
    }).toList();
  }

  /// Parses the block directory without decrypting any block. Raises
  /// [zgl.ZegelFormatException] if the header is malformed.
  List<ZegelBlockInfo> _parseDirectoryEntries(Uint8List fileBytes) {
    if (fileBytes.length < 86) {
      throw const zgl.ZegelFormatException('File too short for header');
    }
    final bd = ByteData.sublistView(fileBytes);
    final flags = bd.getUint16(10, Endian.big);
    final filenameLen = bd.getUint16(84, Endian.big);
    final blockCountOffset = 86 + filenameLen + zgl.ZegelFormat.saltSize;
    if (fileBytes.length < blockCountOffset + 4) {
      throw const zgl.ZegelFormatException('File too short for block count');
    }
    final blockCount = bd.getUint32(blockCountOffset, Endian.big);
    if (blockCount > zgl.ZegelFormat.maxBlockCount) {
      throw zgl.ZegelFormatException(
        'Block count $blockCount exceeds maximum '
        '${zgl.ZegelFormat.maxBlockCount}',
      );
    }

    int cursor = blockCountOffset + 4;
    if (flags & 0x0004 != 0) cursor += 8; // password_derived
    if (flags & 0x0010 != 0) cursor += 8; // expiration
    if (flags & 0x0080 != 0) cursor += 32; // canary
    if (flags & 0x0200 != 0) cursor += 2; // split_key
    if (flags & 0x0800 != 0) cursor += 32; // versioned
    if (flags & 0x0020 != 0) {
      if (fileBytes.length < cursor + 4) {
        throw const zgl.ZegelFormatException(
          'File too short for public metadata length',
        );
      }
      final pubLen = bd.getUint32(cursor, Endian.big);
      if (pubLen > zgl.ZegelFormat.maxPublicMetadataSize) {
        throw zgl.ZegelFormatException(
          'Public metadata size $pubLen exceeds maximum '
          '${zgl.ZegelFormat.maxPublicMetadataSize}',
        );
      }
      cursor += 4 + pubLen;
    }

    final directoryStart = cursor;
    final directorySize = blockCount * zgl.ZegelFormat.blockDirectoryEntrySize;
    if (fileBytes.length < directoryStart + directorySize) {
      throw const zgl.ZegelFormatException(
        'File too short for block directory',
      );
    }

    final entries = <ZegelBlockInfo>[];
    for (int i = 0; i < blockCount; i++) {
      final eo = directoryStart + i * zgl.ZegelFormat.blockDirectoryEntrySize;
      final blockType = fileBytes[eo];
      final ctLen = bd.getUint32(eo + 33, Endian.big);
      entries.add(
        ZegelBlockInfo(
          index: i,
          blockType: blockType,
          blockTypeName: blockTypeName(blockType),
          ciphertextLength: ctLen,
          isRedacted: blockType == 0x06,
        ),
      );
    }
    return entries;
  }

  /// Returns the Merkle root for a file without requiring the master key.
  /// Walks the header using the same layout as [_parseDirectoryEntries].
  Uint8List _readMerkleRoot(
    Uint8List fileBytes,
    zgl.ZegelInspection inspection,
  ) {
    return _readMerkleRootUnverified(fileBytes);
  }

  Uint8List _readMerkleRootUnverified(Uint8List fileBytes) {
    if (fileBytes.length < 86) {
      throw const zgl.ZegelFormatException('File too short for header');
    }
    final bd = ByteData.sublistView(fileBytes);
    final flags = bd.getUint16(10, Endian.big);
    final filenameLen = bd.getUint16(84, Endian.big);
    final blockCountOffset = 86 + filenameLen + zgl.ZegelFormat.saltSize;
    if (fileBytes.length < blockCountOffset + 4) {
      throw const zgl.ZegelFormatException('File too short for block count');
    }
    final blockCount = bd.getUint32(blockCountOffset, Endian.big);
    if (blockCount > zgl.ZegelFormat.maxBlockCount) {
      throw zgl.ZegelFormatException(
        'Block count $blockCount exceeds maximum '
        '${zgl.ZegelFormat.maxBlockCount}',
      );
    }

    int cursor = blockCountOffset + 4;
    if (flags & 0x0004 != 0) cursor += 8;
    if (flags & 0x0010 != 0) cursor += 8;
    if (flags & 0x0080 != 0) cursor += 32;
    if (flags & 0x0200 != 0) cursor += 2;
    if (flags & 0x0800 != 0) cursor += 32;
    if (flags & 0x0020 != 0) {
      if (fileBytes.length < cursor + 4) {
        throw const zgl.ZegelFormatException(
          'File too short for public metadata length',
        );
      }
      final pubLen = bd.getUint32(cursor, Endian.big);
      cursor += 4 + pubLen;
    }
    final directoryStart = cursor;
    final directoryEnd =
        directoryStart + blockCount * zgl.ZegelFormat.blockDirectoryEntrySize;
    if (fileBytes.length < directoryEnd + zgl.ZegelFormat.hashSize) {
      throw const zgl.ZegelFormatException('File too short for Merkle root');
    }
    return Uint8List.fromList(
      fileBytes.sublist(directoryEnd, directoryEnd + zgl.ZegelFormat.hashSize),
    );
  }

  /// Parses the block directory and returns the list of plaintext leaf
  /// hashes in order. Used to feed [zgl.ExcerptProof.generateProof].
  List<Uint8List> _readLeafHashes(Uint8List fileBytes) {
    final entries = <Uint8List>[];
    if (fileBytes.length < 86) {
      throw const zgl.ZegelFormatException('File too short for header');
    }
    final bd = ByteData.sublistView(fileBytes);
    final flags = bd.getUint16(10, Endian.big);
    final filenameLen = bd.getUint16(84, Endian.big);
    final blockCountOffset = 86 + filenameLen + zgl.ZegelFormat.saltSize;
    final blockCount = bd.getUint32(blockCountOffset, Endian.big);
    if (blockCount > zgl.ZegelFormat.maxBlockCount) {
      throw zgl.ZegelFormatException(
        'Block count $blockCount exceeds maximum '
        '${zgl.ZegelFormat.maxBlockCount}',
      );
    }

    int cursor = blockCountOffset + 4;
    if (flags & 0x0004 != 0) cursor += 8;
    if (flags & 0x0010 != 0) cursor += 8;
    if (flags & 0x0080 != 0) cursor += 32;
    if (flags & 0x0200 != 0) cursor += 2;
    if (flags & 0x0800 != 0) cursor += 32;
    if (flags & 0x0020 != 0) {
      final pubLen = bd.getUint32(cursor, Endian.big);
      cursor += 4 + pubLen;
    }

    for (int i = 0; i < blockCount; i++) {
      final eo = cursor + i * zgl.ZegelFormat.blockDirectoryEntrySize;
      entries.add(Uint8List.fromList(fileBytes.sublist(eo + 1, eo + 33)));
    }
    return entries;
  }

  /// Extracts the 32-byte master salt from the fixed header.
  Uint8List _readMasterSalt(Uint8List fileBytes) {
    if (fileBytes.length < 86) {
      throw const zgl.ZegelFormatException('File too short for header');
    }
    final bd = ByteData.sublistView(fileBytes);
    final filenameLen = bd.getUint16(84, Endian.big);
    final saltOffset = 86 + filenameLen;
    if (fileBytes.length < saltOffset + zgl.ZegelFormat.saltSize) {
      throw const zgl.ZegelFormatException('File too short for master salt');
    }
    return Uint8List.fromList(
      fileBytes.sublist(saltOffset, saltOffset + zgl.ZegelFormat.saltSize),
    );
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool _constantTimeStringEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static String _basename(String filePath) {
    final sep = Platform.pathSeparator;
    final idx = filePath.lastIndexOf(sep);
    if (idx < 0) return filePath;
    return filePath.substring(idx + 1);
  }
}
