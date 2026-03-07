import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';
import 'package:zegel/zegel.dart' as zegel_core;
import 'package:zegel/zegel.dart' as zegel;

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

  const SealOptions({
    this.compress = false,
    this.expirationDate,
    this.recipientId,
    this.splitKeyThreshold,
    this.splitKeyTotal,
    this.enableSelectiveDisclosure = false,
    this.metadata,
    this.blockSize = 65536,
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
/// responsive during cryptographic operations.
class ZegelService {
  /// Seals a file with the given key and options.
  ///
  /// Returns the sealed bytes as a Uint8List.
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

||||||| original
    final file = File(filePath);
    final content = await file.readAsBytes();
    final filename = filePath.split(Platform.pathSeparator).last;

    // Delegate to the zegel library.
    // The actual implementation calls into package:zegel.
    // For now, this is a placeholder that returns empty bytes
    // until the core library is fully integrated.
    throw UnimplementedError(
      'Seal operation requires the zegel core library. '
      'Ensure package:zegel is properly linked in pubspec.yaml.',
    );
  }

  /// Verifies a .zgl file with the given key.
  ///
  /// Returns a ZegelResult indicating the status.
  Future<ZegelResult> verify(String filePath, String hexKey) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return const ZegelResult(
        status: ZegelStatus.tampered,
        message: 'File does not exist',
      );
    }

    try {
      final bytes = await file.readAsBytes();

      // Convert hex key to bytes
      final keyBytes = _hexToBytes(hexKey);

      // We pass the hex string directly or the raw bytes. It's better to pass the data needed for Isolate
      // The heavy crypto verification is in a separate isolate to avoid blocking the UI
      final Map<String, dynamic> resultData = await Isolate.run(() {
        const reader = zegel_core.ZegelReader();
        try {
          final coreResult = reader.verify(bytes, keyBytes);
          final inspection = reader.inspect(bytes);

          return {
            'valid': coreResult.valid,
            'message': 'Verification successful',
            'status': 'valid',
            'metadata': coreResult.metadata ?? coreResult.publicMetadata,
            'originalFilename': coreResult.filename ?? inspection.filename,
            'contentType': coreResult.contentType ?? inspection.contentType,
            'blockCount': inspection.blockCount,
            'createdAt': inspection.timestamp,
            'expiresAt': inspection.expirationTimestamp,
            'flags': inspection.flags,
            // Attestations and audit trails are complex structures, simplified here
            // but normally they would be mapped fully
          };
        } on zegel_core.ZegelTamperedException catch (e) {
          return {
            'valid': false,
            'message': e.toString(),
            'status': 'tampered',
          };
        } on zegel_core.ZegelExpiredException catch (e) {
          return {
            'valid': false,
            'message': e.toString(),
            'status': 'expired',
          };
        } catch (e) {
          return {
            'valid': false,
            'message': 'Error verifying file: $e',
            'status': 'tampered',
          };
        }
      });

      ZegelStatus status;
      if (resultData['status'] == 'valid') {
        status = ZegelStatus.valid;
      } else if (resultData['status'] == 'expired') {
        status = ZegelStatus.expired;
      } else {
        status = ZegelStatus.tampered;
      }

      DateTime? createdAt;
      if (resultData['createdAt'] != null) {
        createdAt = DateTime.fromMillisecondsSinceEpoch(
            resultData['createdAt'] as int,
            isUtc: true);
      }

      DateTime? expiresAt;
      if (resultData['expiresAt'] != null) {
        expiresAt = DateTime.fromMillisecondsSinceEpoch(
            resultData['expiresAt'] as int,
            isUtc: true);
      }

      return ZegelResult(
        status: status,
        message: resultData['message'] as String,
        metadata: resultData['metadata'] as Map<String, dynamic>?,
        originalFilename: resultData['originalFilename'] as String?,
        contentType: resultData['contentType'] as String?,
        blockCount: resultData['blockCount'] as int?,
        createdAt: createdAt,
        expiresAt: expiresAt,
        flags: resultData['flags'] as int?,
      );
    } catch (e) {
      return ZegelResult(
        status: ZegelStatus.tampered,
        message: 'Error verifying file: $e',
      );
    }
  }

  Uint8List _hexToBytes(String hexStr) {
    final result = Uint8List(hexStr.length ~/ 2);
    for (int i = 0; i < result.length; i++) {
      result[i] = int.parse(hexStr.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
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
      return false;
    }

    try {
      final fileBytes = await file.readAsBytes();
      final keyBytes = _hexToBytes(hexKey);

      final reader = const zegel.ZegelReader();
      final result = reader.verify(fileBytes, keyBytes);

      if (result.valid && result.content != null) {
        final outFile = File(outputPath);
        await outFile.writeAsBytes(result.content!);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Inspects a .zgl file without requiring the master key.
  ///
  /// Reads the header and public information only.
  Future<ZegelInspection> inspect(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }

    // Delegate to the zegel library.
    try {
      final bytes = await file.readAsBytes();
      const zegelReader = zegel.ZegelReader();
      final inspection = zegelReader.inspect(bytes);

      final versionParts = inspection.version.split('.');
      final versionMajor =
          versionParts.isNotEmpty ? int.tryParse(versionParts[0]) ?? 1 : 1;
      final versionMinor =
          versionParts.length > 1 ? int.tryParse(versionParts[1]) ?? 2 : 2;

      return ZegelInspection(
        versionMajor: versionMajor,
        versionMinor: versionMinor,
        flags: inspection.flags,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            inspection.timestamp * 1000,
            isUtc: true),
        contentType: inspection.contentType ?? 'application/octet-stream',
        originalFilename: inspection.filename ?? 'unknown',
        blockCount: inspection.blockCount,
        expiresAt: inspection.expirationTimestamp != null
            ? DateTime.fromMillisecondsSinceEpoch(
                inspection.expirationTimestamp! * 1000,
                isUtc: true)
            : null,
        publicMetadata: inspection.publicMetadata,
        hasMetadata: inspection.flags & zegel.ZegelFormat.flagHasMetadata != 0,
        isCompressed: inspection.flags & zegel.ZegelFormat.flagCompressed != 0,
        hasExpiration:
            inspection.flags & zegel.ZegelFormat.flagHasExpiration != 0,
        hasCanary: inspection.flags & zegel.ZegelFormat.flagHasCanary != 0,
        hasRedactions:
            inspection.flags & zegel.ZegelFormat.flagHasRedactions != 0,
        isSplitKey: inspection.flags & zegel.ZegelFormat.flagSplitKey != 0,
        hasSelectiveDisclosure:
            inspection.flags & zegel.ZegelFormat.flagSelectiveDisclosure != 0,
        isVersioned: inspection.flags & zegel.ZegelFormat.flagVersioned != 0,
        splitKeyThreshold: inspection.splitKeyParams?['threshold'],
        splitKeyTotal: inspection.splitKeyParams?['total'],
      );
    } catch (e) {
      throw FormatException('Failed to inspect file: $e');
    }
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
    final masterKey = _hexToBytes(hexKey);
    return Redaction.redactBlocks(fileBytes, masterKey, blockIndices);
  }

  /// Splits a key into N shares with threshold M using Shamir's Secret Sharing.
  ///
  /// Returns a list of hex-encoded shares.
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

    // Delegate to the zegel library.
    throw UnimplementedError(
      'Split key operation requires the zegel core library. '
      'Ensure package:zegel is properly linked in pubspec.yaml.',
    );
  }

  /// Reconstructs a key from the given shares.
  ///
  /// Returns the reconstructed hex key.
  Future<String> reconstructKey(List<String> shares) async {
    if (shares.isEmpty) {
      throw ArgumentError('At least one share is required.');
    }

    try {
      final List<Uint8List> shareBytesList = [];
      for (final shareHex in shares) {
        final hexStr = shareHex.trim();
        if (hexStr.length % 2 != 0) {
          throw FormatException('Invalid hex string length: ${hexStr.length}');
        }
        final bytes = Uint8List(hexStr.length ~/ 2);
        for (int i = 0; i < bytes.length; i++) {
          final byteStr = hexStr.substring(i * 2, i * 2 + 2);
          bytes[i] = int.parse(byteStr, radix: 16);
        }
        shareBytesList.add(bytes);
      }

      final threshold = shareBytesList.length;
      final secret = zegel.ShamirSecretSharing.reconstruct(shareBytesList, threshold);

      final buffer = StringBuffer();
      for (final byte in secret) {
        buffer.write(byte.toRadixString(16).padLeft(2, '0'));
      }
      return buffer.toString();
    } catch (e) {
      throw ArgumentError('Failed to reconstruct key: $e');
    }
  }

  /// Creates an attestation (co-signature) for a .zgl file.
  ///
  /// Returns the updated file bytes with the attestation block appended.
  Future<Uint8List> createAttestation(
    String filePath,
    String signerKeyHex,
    String signerId,
    String statement,
  ) async {
    // Delegate to the zegel library.
    throw UnimplementedError(
      'Attestation operation requires the zegel core library. '
      'Ensure package:zegel is properly linked in pubspec.yaml.',
    );
  }

  /// Generates a selective disclosure token for the specified blocks.
  ///
  /// Returns a DisclosureToken that can be shared with third parties.
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

    _RawZegelHeader rawHeader;
    try {
      rawHeader = _RawZegelHeader.parse(fileBytes);
    } on FormatException catch (e) {
      throw FormatException('Invalid .zgl file: ${e.message}');
    }

    for (final index in blockIndices) {
      if (index < 0 || index >= rawHeader.blockCount) {
        throw ArgumentError(
          'Block index $index is out of range. '
          'File has ${rawHeader.blockCount} blocks.',
        );
      }
      if (rawHeader.blockDirectory[index].type == ZegelFormat.blockRedacted) {
        throw ArgumentError(
          'Block $index is redacted and cannot be disclosed.',
        );
      }
    }

    String? expirationDateStr;
    if (rawHeader.expirationTimestamp != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(
        rawHeader.expirationTimestamp! * 1000,
        isUtc: true,
      );
      expirationDateStr =
          '${dt.year.toString().padLeft(4, '0')}-'
          '${dt.month.toString().padLeft(2, '0')}-'
          '${dt.day.toString().padLeft(2, '0')}';
    }

    final int length = hexKey.length ~/ 2;
    final Uint8List masterKeyBytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      masterKeyBytes[i] = int.parse(hexKey.substring(i * 2, i * 2 + 2), radix: 16);
    }

    final tokenMap = SelectiveDisclosure.generateToken(
      masterKeyBytes,
      rawHeader.merkleRoot,
      rawHeader.salt,
      blockIndices,
      expirationDate: expirationDateStr,
    );

    return DisclosureToken.fromJson(tokenMap);
  }

  /// Extracts specific blocks using a disclosure token (no master key required).
  ///
  /// Returns the extracted content bytes.
  Future<Uint8List> extractWithToken(
    String filePath,
    DisclosureToken token,
    String outputPath,
  ) async {
    // Delegate to the zegel library.
    throw UnimplementedError(
      'Token extraction requires the zegel core library. '
      'Ensure package:zegel is properly linked in pubspec.yaml.',
    );
  }

  /// Lists all blocks in a .zgl file with their type and metadata.
  ///
  /// Useful for redaction and disclosure UIs.
  Future<List<ZegelBlockInfo>> listBlocks(
    String filePath,
    String hexKey,
  ) async {
    // Delegate to the zegel library.
    throw UnimplementedError(
      'Block listing requires the zegel core library. '
      'Ensure package:zegel is properly linked in pubspec.yaml.',
    );
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

  /// Converts a hex string to a Uint8List.
  Uint8List _hexToBytes(String hexStr) {
    final length = hexStr.length;
    if (length % 2 != 0) {
      throw const FormatException('Invalid hex string');
    }
    final result = Uint8List(length ~/ 2);
    for (var i = 0; i < length; i += 2) {
      result[i ~/ 2] = int.parse(hexStr.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  // ===============================================================  // Batch operations
  // ===============================================================
  /// Verifies multiple .zgl files in batch.
  ///
  /// Returns a list of [ZegelResult] for each file.
  Future<List<ZegelResult>> batchVerify(
    List<String> filePaths,
    String hexKey,
  ) async {
    final results = <ZegelResult>[];
    for (final path in filePaths) {
      try {
        final result = await verify(path, hexKey);
        results.add(result);
      } catch (e) {
        results.add(ZegelResult(
          status: ZegelStatus.tampered,
          message: 'Error: $e',
        ));
      }
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
    final results = <Uint8List>[];
    for (final path in filePaths) {
      final sealed = await seal(path, hexKey, options);
      results.add(sealed);
    }
    return results;
  }

  // ===============================================================  // Manifest operations
  // ===============================================================
  /// Creates a signed manifest of multiple files.
  ///
  /// Returns the manifest as JSON bytes.
  Future<Uint8List> createManifest(
    List<String> filePaths,
    String signerKeyHex,
    String signerId,
  ) async {
    // Delegate to the zegel library.
    throw UnimplementedError(
      'Create manifest operation requires the zegel core library. '
      'Ensure package:zegel is properly linked in pubspec.yaml.',
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
    // Delegate to the zegel library.
    throw UnimplementedError(
      'Verify manifest operation requires the zegel core library. '
      'Ensure package:zegel is properly linked in pubspec.yaml.',
    );
  }

  // ===============================================================  // Classification operations
  // ===============================================================
  /// Sets or changes the classification level of a .zgl file.
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

    final metadata = Classification.createClassificationMetadata(
      level: level,
      authority: authority,
      caveat: caveat,
    );

    final outputPath = '$filePath.classification.json';
    await File(outputPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(metadata),
    );
  }

  /// Declassifies a .zgl file to a lower classification level.
  /// Optionally redacts specified blocks during declassification.
  Future<void> declassify(
    String filePath,
    String newLevel,
    String authority, {
    List<int>? redactBlocks,
  }) async {
    // Delegate to the zegel library.
    throw UnimplementedError(
      'Declassify operation requires the zegel core library. '
      'Ensure package:zegel is properly linked in pubspec.yaml.',
    );
  }

  // ===============================================================  // Excerpt proof operations
  // ===============================================================
  /// Generates a cryptographic excerpt proof for specific blocks.
  ///
  /// Returns the proof as JSON bytes.
  Future<Uint8List> generateExcerptProof(
    String filePath,
    String hexKey,
    List<int> blockIndices,
  ) async {
    // Delegate to the zegel library.
    throw UnimplementedError(
      'Generate excerpt proof operation requires the zegel core library. '
      'Ensure package:zegel is properly linked in pubspec.yaml.',
    );
  }

  /// Verifies an excerpt proof against a .zgl file.
  ///
  /// No master key is required for verification.
  /// Returns true if the proof is valid.
  Future<bool> verifyExcerptProof(
    String filePath,
    String proofPath,
  ) async {
    // Delegate to the zegel library.
    throw UnimplementedError(
      'Verify excerpt proof operation requires the zegel core library. '
      'Ensure package:zegel is properly linked in pubspec.yaml.',
    );
  }

  // ===============================================================  // Provenance operations
  // ===============================================================
  /// Reads and verifies the provenance chain from a .zgl file.
  ///
  /// Returns a list of provenance events with signature verification status.
  Future<List<ProvenanceEvent>> verifyProvenance(
    String filePath,
    String hexKey,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }

    final bytes = await file.readAsBytes();
    final keyBytes = _hexToBytes(hexKey);

    final result = const ZegelReader().verify(bytes, keyBytes);
    if (result.provenance == null || result.provenance!.isEmpty) {
      return [];
    }

    final chainResult = ProvenanceVerification.verifyChain(result.provenance!, keyBytes);
    final isValid = chainResult['valid'] == true;

    return result.provenance!.map((entry) {
      final timestamp = entry['timestamp'] as int;
      return ProvenanceEvent(
        actor: entry['actor'] as String,
        action: entry['action'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp * 1000, isUtc: true),
        isSignatureVerified: isValid,
      );
    }).toList();
  }

  // ===============================================================  // Version chain operations
  // ===============================================================
  /// Verifies the version chain hash of a sequence of .zgl files.
  ///
  /// Returns true if the version chain is intact and unbroken.
  Future<bool> verifyVersionChain(List<String> filePaths) async {
    final fileBytesList = <Uint8List>[];
    for (final path in filePaths) {
      final file = File(path);
      if (!await file.exists()) {
        throw FileSystemException('File does not exist', path);
      }
      fileBytesList.add(await file.readAsBytes());
    }
    return ContentVersioning.verifyVersionChain(fileBytesList);

  }

  // ===============================================================  // Credential operations
  // ===============================================================
  /// Issues a credential by sealing a document with attestation metadata.
  ///
  /// Returns the sealed credential bytes.
  Future<Uint8List> issueCredential(
    String filePath,
    String hexKey, {
    required String institutionName,
    required String institutionId,
    required String credentialType,
    required String recipientName,
    required String recipientId,
  }) async {
    // Delegate to the zegel library.
    throw UnimplementedError(
      'Issue credential operation requires the zegel core library. '
      'Ensure package:zegel is properly linked in pubspec.yaml.',
    );
  }

  /// Verifies a credential .zgl file using public attestation data.
  ///
  /// No master key required for attestation verification.
  Future<CredentialInfo> verifyCredential(String filePath) async {
    // Delegate to the zegel library.
    throw UnimplementedError(
      'Verify credential operation requires the zegel core library. '
      'Ensure package:zegel is properly linked in pubspec.yaml.',
    );
  }

  Uint8List _hexToBytes(String hex) {
    final int length = hex.length ~/ 2;
    final Uint8List bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}


// =============================================================================
// Internal Header Parsers
// =============================================================================

/// A raw block directory entry parsed directly from a .zgl file.
class _RawBlockEntry {
  const _RawBlockEntry({
    required this.type,
    required this.plaintextHash,
    required this.ciphertextLength,
    required this.iv,
    required this.tag,
  });

  final int type;
  final Uint8List plaintextHash;
  final int ciphertextLength;
  final Uint8List iv;
  final Uint8List tag;
}

/// Lightweight parsed header from raw .zgl bytes.
class _RawZegelHeader {
  _RawZegelHeader._();

  late final int versionMajor;
  late final int versionMinor;
  late final int flags;
  late final int timestamp;
  late final String contentType;
  late final String filename;
  late final Uint8List salt;
  late final int blockCount;
  late final Uint8List merkleRoot;
  late final List<_RawBlockEntry> blockDirectory;
  late final int dataStart;

  // Extended header fields (nullable).
  int? argon2TimeCost;
  int? argon2MemoryCost;
  int? expirationTimestamp;
  Uint8List? recipientId;
  int? splitKeyThreshold;
  int? splitKeyTotal;
  Uint8List? versionChainHash;
  Map<String, dynamic>? publicMetadata;
  Uint8List? keyCommitment;

  /// Parses a .zgl file's raw bytes and returns a [_RawZegelHeader].
  ///
  /// Throws [FormatException] if the binary structure is invalid.
  static _RawZegelHeader parse(Uint8List fileBytes) {
    final h = _RawZegelHeader._();
    final bd = ByteData.sublistView(fileBytes);

    if (fileBytes.length < 86) {
      throw const FormatException('File too short for Zegel header.');
    }

    h.versionMajor = fileBytes[8];
    h.versionMinor = fileBytes[9];
    h.flags = bd.getUint16(10, Endian.big);
    h.timestamp = bd.getUint64(12, Endian.big);

    // Content-Type (64 bytes, null-padded).
    final ctRaw = Uint8List.sublistView(fileBytes, 20, 84);
    int ctEnd = ctRaw.indexOf(0);
    if (ctEnd < 0) ctEnd = ctRaw.length;
    h.contentType = utf8.decode(ctRaw.sublist(0, ctEnd));

    // Filename.
    final filenameLen = bd.getUint16(84, Endian.big);
    h.filename = utf8.decode(fileBytes.sublist(86, 86 + filenameLen));

    // Salt.
    final saltOffset = 86 + filenameLen;
    h.salt = Uint8List.fromList(
      fileBytes.sublist(saltOffset, saltOffset + ZegelFormat.saltSize),
    );

    // Block count.
    final blockCountOffset = saltOffset + ZegelFormat.saltSize;
    h.blockCount = bd.getUint32(blockCountOffset, Endian.big);

    // Extended header.
    int cursor = blockCountOffset + 4;

    if (h.flags & ZegelFormat.flagPasswordDerived != 0) {
      h.argon2TimeCost = bd.getUint32(cursor, Endian.big);
      cursor += 4;
      h.argon2MemoryCost = bd.getUint32(cursor, Endian.big);
      cursor += 4;
    }

    if (h.flags & ZegelFormat.flagHasExpiration != 0) {
      h.expirationTimestamp = bd.getUint64(cursor, Endian.big);
      cursor += 8;
    }

    if (h.flags & ZegelFormat.flagHasCanary != 0) {
      h.recipientId = Uint8List.fromList(
        fileBytes.sublist(cursor, cursor + 32),
      );
      cursor += 32;
    }

    if (h.flags & ZegelFormat.flagSplitKey != 0) {
      h.splitKeyThreshold = fileBytes[cursor];
      cursor += 1;
      h.splitKeyTotal = fileBytes[cursor];
      cursor += 1;
    }

    if (h.flags & ZegelFormat.flagVersioned != 0) {
      h.versionChainHash = Uint8List.fromList(
        fileBytes.sublist(cursor, cursor + 32),
      );
      cursor += 32;
    }

    if (h.flags & ZegelFormat.flagHasPublicMetadata != 0) {
      final pubMetaLen = bd.getUint32(cursor, Endian.big);
      cursor += 4;
      final pubMetaJson = utf8.decode(
        fileBytes.sublist(cursor, cursor + pubMetaLen),
      );
      h.publicMetadata = jsonDecode(pubMetaJson) as Map<String, dynamic>;
      cursor += pubMetaLen;
    }

    // Block directory.
    final directory = <_RawBlockEntry>[];
    for (int i = 0; i < h.blockCount; i++) {
      final eo = cursor;
      directory.add(_RawBlockEntry(
        type: fileBytes[eo],
        plaintextHash: Uint8List.fromList(fileBytes.sublist(eo + 1, eo + 33)),
        ciphertextLength: bd.getUint32(eo + 33, Endian.big),
        iv: Uint8List.fromList(fileBytes.sublist(eo + 37, eo + 49)),
        tag: Uint8List.fromList(fileBytes.sublist(eo + 49, eo + 65)),
      ));
      cursor += ZegelFormat.blockDirectoryEntrySize;
    }
    h.blockDirectory = directory;

    // Merkle root.
    h.merkleRoot = Uint8List.fromList(
      fileBytes.sublist(cursor, cursor + ZegelFormat.hashSize),
    );
    cursor += ZegelFormat.hashSize;

    // Key commitment (optional).
    if (h.flags & ZegelFormat.flagHasKeyCommitment != 0) {
      h.keyCommitment = Uint8List.fromList(
        fileBytes.sublist(cursor, cursor + ZegelFormat.hashSize),
      );
      cursor += ZegelFormat.hashSize;
    }

    h.dataStart = cursor;
    return h;
  }
}
