import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pinenacl/ed25519.dart' as pinenacl;

import 'identity.dart';
import 'writer.dart';
import 'reader.dart';

/// Creative proof-of-origination system for the Zegel format.
///
/// Seals creative works (music, images, video, documents) into a tamper-proof
/// .zgl container with embedded creator identity, optional identity document
/// scans, and an Ed25519 signature binding the content hash to the creator.
///
/// The sealed container proves:
/// 1. **What** was created (content hash in Merkle tree)
/// 2. **Who** created it (Ed25519-signed creator identity)
/// 3. **When** it was created (cryptographic timestamp)
/// 4. **Provenance** of the creator (optional ID document scans)
///
/// The content remains playable/viewable after extraction: images render,
/// audio plays, video streams — the original bytes are preserved bit-perfect.

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Type of creative work being sealed.
enum CreativeWorkType {
  music,
  image,
  video,
  photo,
  document,
  software,
  design,
  animation,
  poem,
  screenplay,
  other,
}

/// Type of identity document attached as proof.
enum IdDocumentType {
  passport,
  identityCard,
  driverLicense,
  residencePermit,
  other,
}

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// Full creator identity for embedding in a creative proof container.
class CreatorIdentity {
  const CreatorIdentity({
    required this.firstName,
    required this.familyName,
    this.middleName,
    this.dateOfBirth,
    this.address,
    this.zipCode,
    this.city,
    this.stateProvince,
    this.country,
    this.companyName,
    this.companyRegistrationNumber,
    this.email,
    this.phone,
    this.website,
    this.professionalTitle,
    this.socialMediaHandles,
  });

  factory CreatorIdentity.fromJson(Map<String, dynamic> json) {
    return CreatorIdentity(
      firstName: json['first_name'] as String,
      familyName: json['family_name'] as String,
      middleName: json['middle_name'] as String?,
      dateOfBirth: json['date_of_birth'] as String?,
      address: json['address'] as String?,
      zipCode: json['zip_code'] as String?,
      city: json['city'] as String?,
      stateProvince: json['state_province'] as String?,
      country: json['country'] as String?,
      companyName: json['company_name'] as String?,
      companyRegistrationNumber:
          json['company_registration_number'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      website: json['website'] as String?,
      professionalTitle: json['professional_title'] as String?,
      socialMediaHandles: json['social_media_handles'] != null
          ? Map<String, String>.from(
              json['social_media_handles'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  final String firstName;
  final String familyName;
  final String? middleName;
  final String? dateOfBirth;
  final String? address;
  final String? zipCode;
  final String? city;
  final String? stateProvince;
  final String? country;
  final String? companyName;
  final String? companyRegistrationNumber;
  final String? email;
  final String? phone;
  final String? website;
  final String? professionalTitle;
  final Map<String, String>? socialMediaHandles;

  String get displayName {
    final parts = <String>[];
    parts.add(firstName);
    if (middleName != null) parts.add(middleName!);
    parts.add(familyName);
    return parts.join(' ');
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'first_name': firstName,
      'family_name': familyName,
      if (middleName != null) 'middle_name': middleName,
      if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
      if (address != null) 'address': address,
      if (zipCode != null) 'zip_code': zipCode,
      if (city != null) 'city': city,
      if (stateProvince != null) 'state_province': stateProvince,
      if (country != null) 'country': country,
      if (companyName != null) 'company_name': companyName,
      if (companyRegistrationNumber != null)
        'company_registration_number': companyRegistrationNumber,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (website != null) 'website': website,
      if (professionalTitle != null) 'professional_title': professionalTitle,
      if (socialMediaHandles != null)
        'social_media_handles': socialMediaHandles,
    };
  }

  /// Returns a SHA-256 fingerprint of the identity for quick comparison.
  String get fingerprint {
    final canonical = jsonEncode(toJson());
    return sha256.convert(utf8.encode(canonical)).toString().substring(0, 16);
  }
}

/// An identity document scan attached as proof of the creator's identity.
class IdDocument {
  const IdDocument({
    required this.type,
    required this.scanBytes,
    required this.scanMimeType,
    this.documentNumber,
    this.issuingCountry,
    this.expiryDate,
    this.holderName,
  });

  factory IdDocument.fromJson(Map<String, dynamic> json) {
    return IdDocument(
      type: IdDocumentType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => IdDocumentType.other,
      ),
      scanBytes: base64Decode(json['scan_b64'] as String),
      scanMimeType: json['scan_mime_type'] as String,
      documentNumber: json['document_number'] as String?,
      issuingCountry: json['issuing_country'] as String?,
      expiryDate: json['expiry_date'] as String?,
      holderName: json['holder_name'] as String?,
    );
  }

  final IdDocumentType type;
  final Uint8List scanBytes;
  final String scanMimeType;
  final String? documentNumber;
  final String? issuingCountry;
  final String? expiryDate;
  final String? holderName;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type.name,
      'scan_b64': base64Encode(scanBytes),
      'scan_mime_type': scanMimeType,
      if (documentNumber != null) 'document_number': documentNumber,
      if (issuingCountry != null) 'issuing_country': issuingCountry,
      if (expiryDate != null) 'expiry_date': expiryDate,
      if (holderName != null) 'holder_name': holderName,
    };
  }

  Map<String, dynamic> toPublicJson() {
    return <String, dynamic>{
      'type': type.name,
      'scan_mime_type': scanMimeType,
      'scan_size_bytes': scanBytes.length,
      'scan_hash': sha256.convert(scanBytes).toString(),
      if (issuingCountry != null) 'issuing_country': issuingCountry,
      if (holderName != null) 'holder_name': holderName,
    };
  }
}

/// Options for creating a creative proof container.
class CreativeProofOptions {
  const CreativeProofOptions({
    required this.workType,
    this.workTitle,
    this.workDescription,
    this.tags,
    this.compress = false,
    this.includeIdentityInPublicMetadata = true,
    this.salt,
  });

  final CreativeWorkType workType;
  final String? workTitle;
  final String? workDescription;
  final List<String>? tags;
  final bool compress;
  final bool includeIdentityInPublicMetadata;
  final Uint8List? salt;
}

/// Result of verifying a creative proof container.
class CreativeProofResult {
  const CreativeProofResult({
    required this.valid,
    required this.signatureValid,
    this.content,
    this.contentType,
    this.originalFilename,
    this.creator,
    this.idDocuments,
    this.workType,
    this.workTitle,
    this.workDescription,
    this.tags,
    this.creatorPublicKeyHex,
    this.createdAt,
    this.contentHashHex,
    this.signatureHex,
  });

  final bool valid;
  final bool signatureValid;
  final Uint8List? content;
  final String? contentType;
  final String? originalFilename;
  final CreatorIdentity? creator;
  final List<IdDocument>? idDocuments;
  final CreativeWorkType? workType;
  final String? workTitle;
  final String? workDescription;
  final List<String>? tags;
  final String? creatorPublicKeyHex;
  final DateTime? createdAt;
  final String? contentHashHex;
  final String? signatureHex;
}

/// Public inspection of a creative proof (no key required).
class CreativeProofInspection {
  const CreativeProofInspection({
    required this.isCreativeProof,
    this.workType,
    this.workTitle,
    this.creatorName,
    this.creatorFingerprint,
    this.creatorPublicKeyHex,
    this.contentHashHex,
    this.signatureHex,
    this.createdAt,
    this.contentType,
    this.originalFilename,
    this.idDocumentSummaries,
    this.tags,
  });

  final bool isCreativeProof;
  final String? workType;
  final String? workTitle;
  final String? creatorName;
  final String? creatorFingerprint;
  final String? creatorPublicKeyHex;
  final String? contentHashHex;
  final String? signatureHex;
  final DateTime? createdAt;
  final String? contentType;
  final String? originalFilename;
  final List<Map<String, dynamic>>? idDocumentSummaries;
  final List<String>? tags;
}

// ---------------------------------------------------------------------------
// Core implementation
// ---------------------------------------------------------------------------

/// Creative proof engine: seal, verify, inspect, and extract creative works.
class CreativeProof {
  CreativeProof._();

  static const String _proofMarker = 'zegel_creative_proof';
  static const int _proofVersion = 1;

  /// Generates a fresh Ed25519 keypair for creator signing.
  static ZegelKeyPair generateCreatorKeypair() {
    return ZegelIdentity.generateKeyPair();
  }

  /// Seals a creative work into a tamper-proof .zgl container.
  ///
  /// [content] is the raw creative asset bytes (MP3, PNG, MP4, PDF, etc.).
  /// [contentType] is the MIME type (e.g. "audio/mpeg", "image/png").
  /// [filename] is the original filename.
  /// [masterKey] is the 32-byte encryption key.
  /// [creatorSigningKey] is the 32-byte Ed25519 private key seed.
  /// [creator] is the creator's identity information.
  /// [options] configures the proof container.
  /// [idDocuments] is an optional list of identity document scans.
  static Uint8List seal({
    required Uint8List content,
    required String contentType,
    required String filename,
    required Uint8List masterKey,
    required Uint8List creatorSigningKey,
    required CreatorIdentity creator,
    required CreativeProofOptions options,
    List<IdDocument>? idDocuments,
  }) {
    if (masterKey.length != 32) {
      throw ArgumentError('Master key must be exactly 32 bytes');
    }
    if (creatorSigningKey.length != 32) {
      throw ArgumentError('Creator signing key must be exactly 32 bytes');
    }

    final int createdAtEpoch =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    final String contentHashHex = sha256.convert(content).toString();

    // Derive creator public key from signing key.
    final signingKey = pinenacl.SigningKey.fromSeed(creatorSigningKey);
    final Uint8List creatorPublicKey =
        Uint8List.fromList(signingKey.verifyKey.asTypedList);
    final String creatorPublicKeyHex = _bytesToHex(creatorPublicKey);

    // Build the signed proof manifest.
    final Map<String, dynamic> proofManifest = <String, dynamic>{
      'proof_marker': _proofMarker,
      'proof_version': _proofVersion,
      'work_type': options.workType.name,
      if (options.workTitle != null) 'work_title': options.workTitle,
      if (options.workDescription != null)
        'work_description': options.workDescription,
      if (options.tags != null && options.tags!.isNotEmpty) 'tags': options.tags,
      'content_hash_sha256': contentHashHex,
      'content_size_bytes': content.length,
      'content_type': contentType,
      'original_filename': filename,
      'created_at_epoch': createdAtEpoch,
      'creator': creator.toJson(),
      'creator_public_key_hex': creatorPublicKeyHex,
      'creator_fingerprint': creator.fingerprint,
    };

    // Compute Ed25519 signature over: SHA256(contentHash || publicKey || epoch).
    final Uint8List signatureMessage = _buildSignatureMessage(
      contentHashHex,
      creatorPublicKeyHex,
      createdAtEpoch,
    );
    final Uint8List signatureDigest =
        Uint8List.fromList(sha256.convert(signatureMessage).bytes);
    final signedMsg = signingKey.sign(signatureDigest);
    final Uint8List signature =
        Uint8List.fromList(signedMsg.signature.asTypedList);
    proofManifest['creator_signature_hex'] = _bytesToHex(signature);

    // Add ID documents to encrypted metadata (private).
    if (idDocuments != null && idDocuments.isNotEmpty) {
      proofManifest['id_documents'] =
          idDocuments.map((d) => d.toJson()).toList();
    }

    // Build public metadata (readable without key).
    final Map<String, dynamic> publicMetadata = <String, dynamic>{
      'proof_marker': _proofMarker,
      'proof_version': _proofVersion,
      'work_type': options.workType.name,
      if (options.workTitle != null) 'work_title': options.workTitle,
      'content_hash_sha256': contentHashHex,
      'content_size_bytes': content.length,
      'created_at_epoch': createdAtEpoch,
      'creator_public_key_hex': creatorPublicKeyHex,
      'creator_signature_hex': _bytesToHex(signature),
    };

    if (options.includeIdentityInPublicMetadata) {
      publicMetadata['creator_name'] = creator.displayName;
      publicMetadata['creator_fingerprint'] = creator.fingerprint;
      if (creator.companyName != null) {
        publicMetadata['creator_company'] = creator.companyName;
      }
      if (creator.city != null) {
        publicMetadata['creator_city'] = creator.city;
      }
      if (creator.country != null) {
        publicMetadata['creator_country'] = creator.country;
      }
    }

    if (options.tags != null && options.tags!.isNotEmpty) {
      publicMetadata['tags'] = options.tags;
    }

    if (idDocuments != null && idDocuments.isNotEmpty) {
      publicMetadata['id_documents_summary'] =
          idDocuments.map((d) => d.toPublicJson()).toList();
    }

    // Seal using the standard Zegel writer.
    final zegelOptions = ZegelOptions(
      contentType: contentType,
      filename: filename,
      metadata: proofManifest,
      publicMetadata: publicMetadata,
      compress: options.compress,
      enableKeyCommitment: true,
      salt: options.salt,
    );

    final writer = ZegelWriter(masterKey, zegelOptions);
    return writer.seal(content);
  }

  /// Verifies a creative proof container and extracts its contents.
  ///
  /// Returns a [CreativeProofResult] with the verification status, extracted
  /// content, creator identity, and signature validation.
  static CreativeProofResult verify(
    Uint8List fileBytes,
    Uint8List masterKey,
  ) {
    final reader = const ZegelReader();
    final zegelResult = reader.verify(fileBytes, masterKey);

    if (!zegelResult.valid) {
      return const CreativeProofResult(valid: false, signatureValid: false);
    }

    final metadata = zegelResult.metadata;
    if (metadata == null ||
        metadata['proof_marker'] != _proofMarker) {
      return CreativeProofResult(
        valid: zegelResult.valid,
        signatureValid: false,
        content: zegelResult.content,
        contentType: zegelResult.contentType,
        originalFilename: zegelResult.filename,
      );
    }

    final creator = CreatorIdentity.fromJson(
      metadata['creator'] as Map<String, dynamic>,
    );

    List<IdDocument>? idDocuments;
    if (metadata['id_documents'] != null) {
      idDocuments = (metadata['id_documents'] as List<dynamic>)
          .map((d) => IdDocument.fromJson(d as Map<String, dynamic>))
          .toList();
    }

    final String contentHashHex = metadata['content_hash_sha256'] as String;
    final String creatorPubKeyHex =
        metadata['creator_public_key_hex'] as String;
    final int createdAtEpoch = metadata['created_at_epoch'] as int;
    final String signatureHex = metadata['creator_signature_hex'] as String;

    // Verify content hash matches.
    final String actualContentHash =
        sha256.convert(zegelResult.content!).toString();
    final bool contentHashValid = actualContentHash == contentHashHex;

    // Verify Ed25519 signature.
    bool signatureValid = false;
    if (contentHashValid) {
      signatureValid = _verifySignature(
        contentHashHex: contentHashHex,
        creatorPublicKeyHex: creatorPubKeyHex,
        createdAtEpoch: createdAtEpoch,
        signatureHex: signatureHex,
      );
    }

    final workTypeName = metadata['work_type'] as String?;
    final workType = workTypeName != null
        ? CreativeWorkType.values.firstWhere(
            (t) => t.name == workTypeName,
            orElse: () => CreativeWorkType.other,
          )
        : null;

    List<String>? tags;
    if (metadata['tags'] != null) {
      tags = (metadata['tags'] as List<dynamic>)
          .map((t) => t as String)
          .toList();
    }

    return CreativeProofResult(
      valid: zegelResult.valid && contentHashValid,
      signatureValid: signatureValid,
      content: zegelResult.content,
      contentType: zegelResult.contentType,
      originalFilename: zegelResult.filename,
      creator: creator,
      idDocuments: idDocuments,
      workType: workType,
      workTitle: metadata['work_title'] as String?,
      workDescription: metadata['work_description'] as String?,
      tags: tags,
      creatorPublicKeyHex: creatorPubKeyHex,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        createdAtEpoch * 1000,
        isUtc: true,
      ),
      contentHashHex: contentHashHex,
      signatureHex: signatureHex,
    );
  }

  /// Inspects a creative proof container without the master key.
  ///
  /// Reads public metadata to determine if the file is a creative proof,
  /// who the creator is, and verifies the Ed25519 signature against
  /// the publicly available content hash and creator public key.
  static CreativeProofInspection inspect(Uint8List fileBytes) {
    final reader = const ZegelReader();
    final inspection = reader.inspect(fileBytes);

    final pubMeta = inspection.publicMetadata;
    if (pubMeta == null || pubMeta['proof_marker'] != _proofMarker) {
      return const CreativeProofInspection(isCreativeProof: false);
    }

    final int? createdAtEpoch = pubMeta['created_at_epoch'] as int?;

    List<Map<String, dynamic>>? idDocSummaries;
    if (pubMeta['id_documents_summary'] != null) {
      idDocSummaries = (pubMeta['id_documents_summary'] as List<dynamic>)
          .map((d) => Map<String, dynamic>.from(d as Map<String, dynamic>))
          .toList();
    }

    List<String>? tags;
    if (pubMeta['tags'] != null) {
      tags = (pubMeta['tags'] as List<dynamic>)
          .map((t) => t as String)
          .toList();
    }

    return CreativeProofInspection(
      isCreativeProof: true,
      workType: pubMeta['work_type'] as String?,
      workTitle: pubMeta['work_title'] as String?,
      creatorName: pubMeta['creator_name'] as String?,
      creatorFingerprint: pubMeta['creator_fingerprint'] as String?,
      creatorPublicKeyHex: pubMeta['creator_public_key_hex'] as String?,
      contentHashHex: pubMeta['content_hash_sha256'] as String?,
      signatureHex: pubMeta['creator_signature_hex'] as String?,
      createdAt: createdAtEpoch != null
          ? DateTime.fromMillisecondsSinceEpoch(
              createdAtEpoch * 1000,
              isUtc: true,
            )
          : null,
      contentType: inspection.contentType,
      originalFilename: inspection.filename,
      idDocumentSummaries: idDocSummaries,
      tags: tags,
    );
  }

  /// Verifies the Ed25519 creator signature from public metadata alone.
  ///
  /// Useful for third-party verification without the master key — the
  /// content hash, public key, and signature are all in public metadata.
  static bool verifyPublicSignature(Uint8List fileBytes) {
    final insp = inspect(fileBytes);
    if (!insp.isCreativeProof) return false;
    if (insp.contentHashHex == null ||
        insp.creatorPublicKeyHex == null ||
        insp.signatureHex == null ||
        insp.createdAt == null) {
      return false;
    }

    return _verifySignature(
      contentHashHex: insp.contentHashHex!,
      creatorPublicKeyHex: insp.creatorPublicKeyHex!,
      createdAtEpoch: insp.createdAt!.millisecondsSinceEpoch ~/ 1000,
      signatureHex: insp.signatureHex!,
    );
  }

  /// Guesses the MIME type from a filename extension.
  static String guessMimeType(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    const mimeMap = <String, String>{
      'mp3': 'audio/mpeg',
      'wav': 'audio/wav',
      'flac': 'audio/flac',
      'aac': 'audio/aac',
      'ogg': 'audio/ogg',
      'm4a': 'audio/mp4',
      'wma': 'audio/x-ms-wma',
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'bmp': 'image/bmp',
      'webp': 'image/webp',
      'svg': 'image/svg+xml',
      'tiff': 'image/tiff',
      'tif': 'image/tiff',
      'ico': 'image/x-icon',
      'heic': 'image/heic',
      'mp4': 'video/mp4',
      'avi': 'video/x-msvideo',
      'mov': 'video/quicktime',
      'mkv': 'video/x-matroska',
      'webm': 'video/webm',
      'wmv': 'video/x-ms-wmv',
      'flv': 'video/x-flv',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'txt': 'text/plain',
      'rtf': 'application/rtf',
      'html': 'text/html',
      'htm': 'text/html',
      'xml': 'application/xml',
      'json': 'application/json',
      'zip': 'application/zip',
      'psd': 'image/vnd.adobe.photoshop',
      'ai': 'application/postscript',
      'eps': 'application/postscript',
    };
    return mimeMap[ext] ?? 'application/octet-stream';
  }

  /// Determines work type from MIME type.
  static CreativeWorkType guessWorkType(String mimeType) {
    if (mimeType.startsWith('audio/')) return CreativeWorkType.music;
    if (mimeType.startsWith('image/')) {
      if (mimeType == 'image/vnd.adobe.photoshop' ||
          mimeType == 'image/svg+xml') {
        return CreativeWorkType.design;
      }
      return CreativeWorkType.image;
    }
    if (mimeType.startsWith('video/')) return CreativeWorkType.video;
    if (mimeType.startsWith('text/')) return CreativeWorkType.document;
    if (mimeType == 'application/pdf') return CreativeWorkType.document;
    return CreativeWorkType.other;
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  static Uint8List _buildSignatureMessage(
    String contentHashHex,
    String creatorPublicKeyHex,
    int createdAtEpoch,
  ) {
    final parts = '$contentHashHex:$creatorPublicKeyHex:$createdAtEpoch';
    return Uint8List.fromList(utf8.encode(parts));
  }

  static bool _verifySignature({
    required String contentHashHex,
    required String creatorPublicKeyHex,
    required int createdAtEpoch,
    required String signatureHex,
  }) {
    try {
      final Uint8List publicKey = _hexToBytes(creatorPublicKeyHex);
      final Uint8List signature = _hexToBytes(signatureHex);

      if (publicKey.length != 32 || signature.length != 64) return false;

      final Uint8List message = _buildSignatureMessage(
        contentHashHex,
        creatorPublicKeyHex,
        createdAtEpoch,
      );
      final Uint8List digest =
          Uint8List.fromList(sha256.convert(message).bytes);

      final verifyKey = pinenacl.VerifyKey(publicKey);
      return verifyKey.verify(
        signature: pinenacl.Signature(signature),
        message: digest,
      );
    } on Exception {
      return false;
    }
  }

  static String _bytesToHex(Uint8List bytes) {
    final buf = StringBuffer();
    for (final byte in bytes) {
      buf.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  static Uint8List _hexToBytes(String hex) {
    final length = hex.length ~/ 2;
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
