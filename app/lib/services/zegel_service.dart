import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:zegel/zegel.dart' as zegel;

/// Result status from a verification operation.
enum ZegelStatus {
  valid,
  tampered,
  expired,
}

/// Result of a verification operation.
class VerifyResult {
  final ZegelStatus status;
  final String message;
  final Uint8List? content;
  final Map<String, dynamic>? metadata;
  final String? originalFilename;
  final String? contentType;
  final Map<String, dynamic>? publicMetadata;
  final List<Map<String, dynamic>>? attestations;
  final List<Map<String, dynamic>>? auditTrail;
  final List<int>? redactedBlocks;

  const VerifyResult({
    required this.status,
    required this.message,
    this.content,
    this.metadata,
    this.originalFilename,
    this.contentType,
    this.publicMetadata,
    this.attestations,
    this.auditTrail,
    this.redactedBlocks,
  });
}

/// Inspection result (no key required).
class InspectResult {
  final String version;
  final int flags;
  final int timestamp;
  final String? contentType;
  final String? filename;
  final int blockCount;
  final Map<String, dynamic>? publicMetadata;
  final int? expirationTimestamp;
  final Map<String, int>? splitKeyParams;

  const InspectResult({
    required this.version,
    required this.flags,
    required this.timestamp,
    this.contentType,
    this.filename,
    required this.blockCount,
    this.publicMetadata,
    this.expirationTimestamp,
    this.splitKeyParams,
  });

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
    if (flags & 0x1000 != 0) names.add('REGULATORY_HOLD');
    if (flags & 0x2000 != 0) names.add('HAS_TIMESTAMP');
    if (flags & 0x4000 != 0) names.add('ANONYMOUS');
    if (flags & 0x8000 != 0) names.add('HAS_CLASSIFICATION');
    return names;
  }
}

/// High-level service wrapping the zegel lib/ package for GUI operations.
///
/// All file operations are asynchronous to keep the UI responsive during
/// cryptographic operations. Each method delegates to the real package:zegel
/// library for all crypto work.
class ZegelService {
  final _reader = const zegel.ZegelReader();

  // ======================================================================
  // Core operations
  // ======================================================================

  /// Seals a file with the given key and options.
  Future<Uint8List> seal(
    String filePath,
    Uint8List masterKey, {
    String? contentType,
    String? filename,
    bool compress = false,
    bool enableKeyCommitment = false,
    bool enableSelectiveDisclosure = false,
    DateTime? expiration,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? publicMetadata,
    Uint8List? recipientId,
    int? splitKeyThreshold,
    int? splitKeyTotal,
    Uint8List? versionChainHash,
    String? classification,
    String? classificationAuthority,
    int? regulatoryHoldUntil,
    bool anonymous = false,
    int blockSize = zegel.ZegelFormat.defaultBlockSize,
  }) async {
    final file = File(filePath);
    final content = await file.readAsBytes();

    final options = zegel.ZegelOptions(
      contentType: contentType ?? _guessContentType(filePath),
      filename: filename ?? file.uri.pathSegments.last,
      compress: compress,
      enableKeyCommitment: enableKeyCommitment,
      enableSelectiveDisclosure: enableSelectiveDisclosure,
      expiration: expiration,
      metadata: metadata,
      publicMetadata: publicMetadata,
      recipientId: recipientId,
      splitKeyThreshold: splitKeyThreshold,
      splitKeyTotal: splitKeyTotal,
      versionChainHash: versionChainHash,
      classification: classification,
      classificationAuthority: classificationAuthority,
      regulatoryHoldUntil: regulatoryHoldUntil,
      anonymous: anonymous,
      blockSize: blockSize,
    );

    final writer = zegel.ZegelWriter(masterKey, options);
    return writer.seal(Uint8List.fromList(content));
  }

  /// Verifies a .zgl file with the given key.
  Future<VerifyResult> verify(String filePath, Uint8List masterKey) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return const VerifyResult(
        status: ZegelStatus.tampered,
        message: 'File does not exist',
      );
    }

    final fileBytes = Uint8List.fromList(await file.readAsBytes());

    try {
      final result = _reader.verify(fileBytes, masterKey);
      return VerifyResult(
        status: ZegelStatus.valid,
        message: 'File is intact and verified',
        content: result.content,
        metadata: result.metadata,
        originalFilename: result.filename,
        contentType: result.contentType,
        publicMetadata: result.publicMetadata,
        attestations: result.attestations,
        auditTrail: result.auditTrail,
        redactedBlocks: result.redactedBlocks,
      );
    } on zegel.ZegelTamperedException catch (e) {
      return VerifyResult(
        status: ZegelStatus.tampered,
        message: e.message,
      );
    } on zegel.ZegelExpiredException catch (e) {
      return VerifyResult(
        status: ZegelStatus.expired,
        message: e.message,
      );
    } on zegel.ZegelRegulatoryHoldException catch (e) {
      return VerifyResult(
        status: ZegelStatus.tampered,
        message: 'Regulatory hold: ${e.message}',
      );
    } on zegel.ZegelFormatException catch (e) {
      return VerifyResult(
        status: ZegelStatus.tampered,
        message: 'Format error: ${e.message}',
      );
    }
  }

  /// Extracts content from a verified .zgl file and writes to outputPath.
  Future<bool> extract(
    String filePath,
    Uint8List masterKey,
    String outputPath,
  ) async {
    final fileBytes = Uint8List.fromList(await File(filePath).readAsBytes());
    final result = _reader.verify(fileBytes, masterKey);

    if (result.valid && result.content != null) {
      await File(outputPath).writeAsBytes(result.content!);
      return true;
    }
    return false;
  }

  /// Inspects a .zgl file header without requiring the master key.
  Future<InspectResult> inspect(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }

    final fileBytes = Uint8List.fromList(await file.readAsBytes());
    final inspection = _reader.inspect(fileBytes);

    return InspectResult(
      version: inspection.version,
      flags: inspection.flags,
      timestamp: inspection.timestamp,
      contentType: inspection.contentType,
      filename: inspection.filename,
      blockCount: inspection.blockCount,
      publicMetadata: inspection.publicMetadata,
      expirationTimestamp: inspection.expirationTimestamp,
      splitKeyParams: inspection.splitKeyParams,
    );
  }

  // ======================================================================
  // Redaction
  // ======================================================================

  /// Redacts specified blocks permanently.
  Future<Uint8List> redact(
    String filePath,
    Uint8List masterKey,
    List<int> blockIndices,
  ) async {
    final fileBytes = Uint8List.fromList(await File(filePath).readAsBytes());
    return zegel.Redaction.redactBlocks(fileBytes, masterKey, blockIndices);
  }

  // ======================================================================
  // Split-key (Shamir)
  // ======================================================================

  /// Splits a key into N shares with threshold M.
  List<Uint8List> splitKey(
    Uint8List masterKey,
    int threshold,
    int totalShares,
  ) {
    return zegel.ShamirSecretSharing.split(masterKey, threshold, totalShares);
  }

  /// Reconstructs a key from shares.
  Uint8List reconstructKey(List<Uint8List> shares, int threshold) {
    return zegel.ShamirSecretSharing.reconstruct(shares, threshold);
  }

  // ======================================================================
  // Attestation
  // ======================================================================

  /// Creates an HMAC attestation on a .zgl file.
  Future<Uint8List> createAttestation(
    String filePath,
    Uint8List signerKey,
    String signerId,
    String statement, {
    String role = 'signer',
  }) async {
    final fileBytes = Uint8List.fromList(await File(filePath).readAsBytes());
    return zegel.Attestation.addAttestation(
      fileBytes,
      signerKey,
      signerId,
      statement,
    );
  }

  // ======================================================================
  // Selective disclosure
  // ======================================================================

  /// Generates a selective disclosure token.
  Future<Map<String, dynamic>> generateDisclosureToken(
    String filePath,
    Uint8List masterKey,
    List<int> blockIndices, {
    int? expiresAt,
  }) async {
    final fileBytes = Uint8List.fromList(await File(filePath).readAsBytes());
    final inspection = _reader.inspect(fileBytes);

    // Parse salt and Merkle root from the file.
    final bd = ByteData.sublistView(fileBytes);
    final fnLen = bd.getUint16(84, Endian.big);
    final saltOffset = 86 + fnLen;
    final salt = Uint8List.sublistView(fileBytes, saltOffset, saltOffset + 32);

    final blockCountOffset = saltOffset + 32;
    final blockCount = bd.getUint32(blockCountOffset, Endian.big);

    // Parse extended header size.
    int extSize = 0;
    final flags = inspection.flags;
    if (flags & zegel.ZegelFormat.flagPasswordDerived != 0) extSize += 8;
    if (flags & zegel.ZegelFormat.flagHasExpiration != 0) extSize += 8;
    if (flags & zegel.ZegelFormat.flagHasCanary != 0) extSize += 32;
    if (flags & zegel.ZegelFormat.flagSplitKey != 0) extSize += 2;
    if (flags & zegel.ZegelFormat.flagVersioned != 0) extSize += 32;
    if (flags & zegel.ZegelFormat.flagHasPublicMetadata != 0) {
      final pmOffset = blockCountOffset + 4 + extSize;
      final pmLen = bd.getUint32(pmOffset, Endian.big);
      extSize += 4 + pmLen;
    }

    final dirStart = blockCountOffset + 4 + extSize;
    final merkleRootOffset = dirStart + blockCount * 65;
    final merkleRoot = Uint8List.sublistView(
      fileBytes,
      merkleRootOffset,
      merkleRootOffset + 32,
    );

    return zegel.SelectiveDisclosure.generateToken(
      masterKey,
      merkleRoot,
      salt,
      blockIndices,
      expiresAt: expiresAt,
    );
  }

  /// Extracts content using a disclosure token (no master key).
  Future<VerifyResult> extractWithToken(
    String filePath,
    Map<String, dynamic> token,
  ) async {
    final fileBytes = Uint8List.fromList(await File(filePath).readAsBytes());

    try {
      final result = _reader.extractWithToken(fileBytes, token);
      return VerifyResult(
        status: ZegelStatus.valid,
        message: 'Token extraction successful',
        content: result.content,
        metadata: result.metadata,
        originalFilename: result.filename,
        contentType: result.contentType,
      );
    } on zegel.ZegelExpiredException catch (e) {
      return VerifyResult(
        status: ZegelStatus.expired,
        message: 'Token expired: ${e.message}',
      );
    } on zegel.ZegelTamperedException catch (e) {
      return VerifyResult(
        status: ZegelStatus.tampered,
        message: 'Tamper detected: ${e.message}',
      );
    }
  }

  // ======================================================================
  // Version chain
  // ======================================================================

  /// Verifies the version chain hash of a sequence of .zgl files.
  Future<bool> verifyVersionChain(List<String> filePaths) async {
    final fileBytesList = <Uint8List>[];
    for (final path in filePaths) {
      fileBytesList.add(Uint8List.fromList(await File(path).readAsBytes()));
    }
    return zegel.ContentVersioning.verifyVersionChain(fileBytesList);
  }

  // ======================================================================
  // Batch operations
  // ======================================================================

  /// Verifies multiple .zgl files in batch.
  Future<List<VerifyResult>> batchVerify(
    List<String> filePaths,
    Uint8List masterKey,
  ) async {
    return Future.wait(
      filePaths.map((path) => verify(path, masterKey)),
    );
  }

  // ======================================================================
  // Identity (v1.4)
  // ======================================================================

  /// Generates an Ed25519 signing keypair.
  Map<String, Uint8List> generateSigningKeyPair() {
    return zegel.ZegelIdentity.generateKeyPair();
  }

  /// Signs a .zgl file with an Ed25519 private key.
  Future<Map<String, dynamic>> signFile(
    String filePath,
    Uint8List privateKey,
  ) async {
    final fileBytes = Uint8List.fromList(await File(filePath).readAsBytes());
    return zegel.ZegelIdentity.sign(fileBytes, privateKey);
  }

  /// Verifies an Ed25519 signature on a .zgl file.
  Future<bool> verifySignature(
    String filePath,
    Map<String, dynamic> signatureData,
  ) async {
    final fileBytes = Uint8List.fromList(await File(filePath).readAsBytes());
    return zegel.ZegelIdentity.verifySignature(fileBytes, signatureData);
  }

  // ======================================================================
  // Supply chain (v1.4)
  // ======================================================================

  /// Audits the entropy/randomness of a sealed .zgl file.
  Future<bool> auditEntropy(String filePath) async {
    final fileBytes = Uint8List.fromList(await File(filePath).readAsBytes());
    return zegel.SupplyChainVerifier.auditEntropy(fileBytes);
  }

  // ======================================================================
  // Envelope (v1.4 - DocuSign parity)
  // ======================================================================

  /// Creates an envelope and encodes it to bytes.
  Uint8List createEnvelope(zegel.Envelope envelope) {
    return envelope.encode();
  }

  /// Decodes an envelope from bytes.
  zegel.Envelope decodeEnvelope(Uint8List data) {
    return zegel.Envelope.decode(data);
  }

  /// Generates a Certificate of Completion for an envelope.
  zegel.CertificateOfCompletion generateCertificate(
    zegel.Envelope envelope,
  ) {
    return zegel.CertificateOfCompletion.generate(envelope);
  }

  // ======================================================================
  // Wet signature (v1.4)
  // ======================================================================

  /// Encodes a wet signature to bytes for embedding.
  Uint8List encodeWetSignature(zegel.WetSignature signature) {
    return signature.encode();
  }

  /// Decodes a wet signature from bytes.
  zegel.WetSignature decodeWetSignature(Uint8List data) {
    return zegel.WetSignature.decode(data);
  }

  /// Computes the HMAC for a wet signature (binds it to the file).
  Uint8List computeSignatureHmac(
    zegel.WetSignature signature,
    Uint8List masterKey,
  ) {
    return zegel.WetSignatureUtils.computeSignatureHmac(signature, masterKey);
  }

  // ======================================================================
  // Key generation
  // ======================================================================

  /// Generates a cryptographically secure 32-byte master key.
  Uint8List generateMasterKey() {
    final rng = Random.secure();
    final key = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      key[i] = rng.nextInt(256);
    }
    return key;
  }

  // ======================================================================
  // Helpers
  // ======================================================================

  /// Returns a human-readable name for a block type value.
  String blockTypeName(int blockType) {
    switch (blockType) {
      case 0x01: return 'CONTENT';
      case 0x02: return 'METADATA';
      case 0x03: return 'PUBLIC_METADATA';
      case 0x04: return 'FILE_HEADER';
      case 0x05: return 'PROVENANCE';
      case 0x06: return 'REDACTED';
      case 0x07: return 'ATTESTATION';
      case 0x08: return 'REFERENCE';
      case 0x09: return 'AUDIT';
      case 0x0A: return 'DISCLOSURE_INDEX';
      case 0x0B: return 'TIMESTAMP';
      case 0x0C: return 'EXCERPT';
      case 0x0D: return 'MANIFEST_ENTRY';
      case 0x0E: return 'SIGNATURE';
      case 0x0F: return 'DEVICE_ATTESTATION';
      case 0x10: return 'SBOM';
      case 0x11: return 'ROYALTY';
      case 0x12: return 'MEASUREMENT';
      case 0x13: return 'PRIVILEGE_LOG';
      case 0x14: return 'BUILD_ATTESTATION';
      default: return 'UNKNOWN (0x${blockType.toRadixString(16).padLeft(2, '0')})';
    }
  }

  /// Converts a hex string to bytes.
  static Uint8List hexToBytes(String hex) {
    final length = hex.length ~/ 2;
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Converts bytes to hex string.
  static String bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Guesses the content type from the file extension.
  String _guessContentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    const types = <String, String>{
      'txt': 'text/plain',
      'html': 'text/html',
      'htm': 'text/html',
      'css': 'text/css',
      'js': 'application/javascript',
      'json': 'application/json',
      'xml': 'application/xml',
      'csv': 'text/csv',
      'md': 'text/markdown',
      'pdf': 'application/pdf',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'svg': 'image/svg+xml',
      'mp3': 'audio/mpeg',
      'mp4': 'video/mp4',
      'zip': 'application/zip',
      'gz': 'application/gzip',
      'tar': 'application/x-tar',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'dart': 'text/x-dart',
    };
    return types[ext] ?? 'application/octet-stream';
  }
}
