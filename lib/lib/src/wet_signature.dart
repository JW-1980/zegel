import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Wet (handwritten) signature support for the Zegel format (v1.4).
///
/// Allows capturing handwritten signatures from touchscreens or mouse input,
/// along with signer metadata (name, city, date). The signature is stored
/// as a PNG image inside a dedicated block, and the signer metadata is stored
/// as JSON.
///
/// This is a GUI/web feature -- the CLI cannot capture signatures, but can
/// verify and display them.
///
/// ## Signing Flow
///
/// 1. User draws signature on a canvas (touch, mouse, or stylus)
/// 2. Canvas is exported as PNG bytes
/// 3. Signer enters their name, woonplaats (city), and confirms the date
/// 4. A [WetSignature] is created with the image, metadata, and HMAC
/// 5. The signature is encoded and embedded as a block in the .zgl file
///
/// ## Multi-Party Signing
///
/// The `requiredSignatures` field specifies how many people must sign.
/// The file is only considered fully signed when the number of signature
/// blocks equals or exceeds `requiredSignatures`.

/// Block type for wet signature image + metadata.
/// Uses the existing ATTESTATION block type (0x07) with a special subtype.
const String wetSignatureSubtype = 'wet_signature';

/// A single wet (handwritten) signature with signer metadata.
class WetSignature {
  /// Creates a [WetSignature].
  const WetSignature({
    required this.signatureImage,
    required this.signerName,
    required this.signerCity,
    required this.signedAt,
    this.signerId,
    this.signerRole,
    this.imageFormat = 'png',
  });

  /// The handwritten signature as image bytes (PNG format by default).
  final Uint8List signatureImage;

  /// Full name of the signer.
  final String signerName;

  /// City of residence (woonplaats) of the signer.
  final String signerCity;

  /// Timestamp when the signature was captured (Unix epoch seconds).
  final int signedAt;

  /// Optional unique identifier for the signer (e.g., national ID hash).
  final String? signerId;

  /// Optional role of the signer (e.g., `buyer`, `seller`, `witness`, `notary`).
  final String? signerRole;

  /// Image format: `png` (default) or `svg`.
  final String imageFormat;

  /// Encodes this wet signature to bytes for embedding in a Zegel container.
  ///
  /// The encoded format is JSON with the signature image base64-encoded.
  Uint8List encode() {
    final Map<String, dynamic> json = <String, dynamic>{
      'subtype': wetSignatureSubtype,
      'signer_name': signerName,
      'signer_city': signerCity,
      'signed_at': signedAt,
      'image_format': imageFormat,
      'signature_image_b64': base64Encode(signatureImage),
    };
    if (signerId != null) json['signer_id'] = signerId;
    if (signerRole != null) json['signer_role'] = signerRole;
    return Uint8List.fromList(utf8.encode(jsonEncode(json)));
  }

  /// Decodes a wet signature from block bytes.
  factory WetSignature.decode(Uint8List data) {
    final Map<String, dynamic> json =
        jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    return WetSignature(
      signatureImage: base64Decode(json['signature_image_b64'] as String),
      signerName: json['signer_name'] as String,
      signerCity: json['signer_city'] as String,
      signedAt: json['signed_at'] as int,
      signerId: json['signer_id'] as String?,
      signerRole: json['signer_role'] as String?,
      imageFormat: json['image_format'] as String? ?? 'png',
    );
  }
}

/// Configuration for multi-party wet signature requirements.
class WetSignatureConfig {
  /// Creates a [WetSignatureConfig].
  const WetSignatureConfig({
    required this.requiredSignatures,
    this.roles,
  });

  /// Number of signatures required for the document to be considered
  /// fully signed. Must be >= 1.
  final int requiredSignatures;

  /// Optional list of required roles. When non-null, at least one signature
  /// from each role is required. Example: `['buyer', 'seller', 'witness']`.
  final List<String>? roles;

  /// Encodes to JSON.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'required_signatures': requiredSignatures,
    };
    if (roles != null) json['roles'] = roles;
    return json;
  }

  /// Decodes from JSON.
  factory WetSignatureConfig.fromJson(Map<String, dynamic> json) {
    return WetSignatureConfig(
      requiredSignatures: json['required_signatures'] as int,
      roles: (json['roles'] as List<dynamic>?)
          ?.map((r) => r as String)
          .toList(),
    );
  }
}

/// Utility methods for wet signature management.
class WetSignatureUtils {
  WetSignatureUtils._();

  /// Checks whether a file has the required number of wet signatures.
  ///
  /// [signatures] is the list of wet signatures found in the file.
  /// [config] is the signing configuration from the public metadata.
  ///
  /// Returns `true` if all signing requirements are met.
  static bool isFullySigned(
    List<WetSignature> signatures,
    WetSignatureConfig config,
  ) {
    if (signatures.length < config.requiredSignatures) {
      return false;
    }

    // Check role requirements if specified.
    if (config.roles != null) {
      for (final String requiredRole in config.roles!) {
        final bool hasRole = signatures.any(
          (s) => s.signerRole == requiredRole,
        );
        if (!hasRole) return false;
      }
    }

    return true;
  }

  /// Computes an HMAC over the signature image and metadata.
  ///
  /// This binds the wet signature to the signer's identity and timestamp,
  /// preventing signature image reuse across different documents.
  ///
  /// [signature] is the wet signature.
  /// [masterKey] is the 32-byte master key of the file.
  ///
  /// Returns a 32-byte HMAC-SHA256 digest.
  static Uint8List computeSignatureHmac(
    WetSignature signature,
    Uint8List masterKey,
  ) {
    final message = Uint8List.fromList(utf8.encode(
      '${signature.signerName}:${signature.signerCity}:${signature.signedAt}',
    ));
    final combined = Uint8List(
      signature.signatureImage.length + message.length,
    );
    combined.setRange(0, signature.signatureImage.length, signature.signatureImage);
    combined.setRange(signature.signatureImage.length, combined.length, message);

    final hmac = Hmac(sha256, masterKey);
    return Uint8List.fromList(hmac.convert(combined).bytes);
  }

  /// Verifies that a wet signature's HMAC matches.
  static bool verifySignatureHmac(
    WetSignature signature,
    Uint8List masterKey,
    Uint8List expectedHmac,
  ) {
    final computed = computeSignatureHmac(signature, masterKey);
    if (computed.length != expectedHmac.length) return false;
    int diff = 0;
    for (int i = 0; i < computed.length; i++) {
      diff |= computed[i] ^ expectedHmac[i];
    }
    return diff == 0;
  }
}
