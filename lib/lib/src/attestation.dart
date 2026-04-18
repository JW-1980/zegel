import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'format.dart';

/// Co-signature / multi-party attestation (GEN-6, v1.2+).
///
/// Attestation blocks allow third parties to cryptographically attest to a
/// file's integrity by signing a message that includes the Merkle root, the
/// signer's identity, a timestamp, and a free-text statement.
///
/// v1.3 adds **role-based attestations**, where each signer specifies their
/// organisational role (owner, signer, witness, notary, auditor, reviewer).
/// This enables policy enforcement (e.g. "must have at least one notary and
/// one auditor attestation").
///
/// The attestation uses HMAC-SHA256 with the signer's key, so verification
/// requires the same key. For public verifiability, consider distributing the
/// signer key hash or using a PKI-based scheme on top.
class Attestation {
  Attestation._();

  /// Valid attestation roles (v1.3).
  static const List<String> validRoles = <String>[
    ZegelFormat.roleOwner,
    ZegelFormat.roleSigner,
    ZegelFormat.roleWitness,
    ZegelFormat.roleNotary,
    ZegelFormat.roleAuditor,
    ZegelFormat.roleReviewer,
  ];

  /// Creates an attestation for the given [merkleRoot].
  ///
  /// The [signerId] is a human-readable identifier such as
  /// `"user:42:accountant@example.com"`.
  ///
  /// The [signerKey] is a 32-byte secret key belonging to the signer. The
  /// recommended derivation is:
  /// `HMAC-SHA256(company_key, "zegel-signer-v1:" + signer_id)`.
  ///
  /// The [statement] is free-text such as `"Reviewed and approved"`.
  ///
  /// If [timestamp] is null, the current UTC time is used.
  ///
  /// Returns a JSON-serialisable map containing the attestation fields and
  /// the hex-encoded HMAC.
  static Map<String, dynamic> createAttestation(
    Uint8List merkleRoot,
    String signerId,
    Uint8List signerKey,
    String statement, {
    DateTime? timestamp,
  }) {
    final DateTime ts = timestamp ?? DateTime.now().toUtc();
    final int epochSeconds = ts.millisecondsSinceEpoch ~/ 1000;

    // message = merkleRoot || signerIdBytes || pack_uint64_be(timestamp) || statementBytes
    final Uint8List signerIdBytes = Uint8List.fromList(utf8.encode(signerId));
    final Uint8List statementBytes = Uint8List.fromList(utf8.encode(statement));

    final int messageLen =
        merkleRoot.length + signerIdBytes.length + 8 + statementBytes.length;
    final Uint8List message = Uint8List(messageLen);
    int offset = 0;

    message.setRange(offset, offset + merkleRoot.length, merkleRoot);
    offset += merkleRoot.length;

    message.setRange(offset, offset + signerIdBytes.length, signerIdBytes);
    offset += signerIdBytes.length;

    final ByteData bd = ByteData(8);
    bd.setUint64(0, epochSeconds, Endian.big);
    message.setRange(offset, offset + 8, bd.buffer.asUint8List());
    offset += 8;

    message.setRange(offset, offset + statementBytes.length, statementBytes);

    // hmac = HMAC-SHA256(signerKey, message)
    final hmac = Hmac(sha256, signerKey);
    final Uint8List hmacBytes = Uint8List.fromList(hmac.convert(message).bytes);

    return <String, dynamic>{
      'signer_id': signerId,
      'statement': statement,
      'timestamp': epochSeconds,
      'hmac_hex': _bytesToHex(hmacBytes),
    };
  }

  /// Verifies an attestation against a [merkleRoot] and [signerKey].
  ///
  /// Recomputes the HMAC from the attestation fields and compares it with
  /// the stored `hmac_hex` value using constant-time comparison.
  ///
  /// Returns `true` if the attestation is valid.
  static bool verifyAttestation(
    Map<String, dynamic> attestation,
    Uint8List merkleRoot,
    Uint8List signerKey,
  ) {
    final String signerId = attestation['signer_id'] as String;
    final String statement = attestation['statement'] as String;
    final int epochSeconds = attestation['timestamp'] as int;
    final String storedHmacHex = attestation['hmac_hex'] as String;

    // Rebuild the message.
    final Uint8List signerIdBytes = Uint8List.fromList(utf8.encode(signerId));
    final Uint8List statementBytes = Uint8List.fromList(utf8.encode(statement));

    final int messageLen =
        merkleRoot.length + signerIdBytes.length + 8 + statementBytes.length;
    final Uint8List message = Uint8List(messageLen);
    int offset = 0;

    message.setRange(offset, offset + merkleRoot.length, merkleRoot);
    offset += merkleRoot.length;

    message.setRange(offset, offset + signerIdBytes.length, signerIdBytes);
    offset += signerIdBytes.length;

    final ByteData bd = ByteData(8);
    bd.setUint64(0, epochSeconds, Endian.big);
    message.setRange(offset, offset + 8, bd.buffer.asUint8List());
    offset += 8;

    message.setRange(offset, offset + statementBytes.length, statementBytes);

    // Compute HMAC.
    final hmac = Hmac(sha256, signerKey);
    final Uint8List computedHmac = Uint8List.fromList(
      hmac.convert(message).bytes,
    );
    final String computedHex = _bytesToHex(computedHmac);

    return _constantTimeEquals(storedHmacHex, computedHex);
  }

  /// Creates an attestation with a role designation (v1.3).
  ///
  /// Roles define the signer's organisational function:
  /// - `owner` -- the file originator
  /// - `signer` -- a general signer
  /// - `witness` -- observed the sealing or verification
  /// - `notary` -- provides independent notarisation
  /// - `auditor` -- reviewed for compliance
  /// - `reviewer` -- inspected the content
  ///
  /// The role is included in the HMAC computation so it cannot be changed
  /// after signing.
  ///
  /// [merkleRoot] is the 32-byte Merkle root of the file.
  /// [signerId] identifies the signer.
  /// [signerKey] is the 32-byte signing key.
  /// [statement] is the attestation statement.
  /// [role] is one of [validRoles].
  /// [timestamp] is the attestation time. If null, current UTC time is used.
  ///
  /// Returns a JSON-serialisable map containing the attestation with role.
  ///
  /// Throws [ArgumentError] if [role] is not a valid role.
  static Map<String, dynamic> createRoleAttestation(
    Uint8List merkleRoot,
    String signerId,
    Uint8List signerKey,
    String statement,
    String role, {
    DateTime? timestamp,
  }) {
    if (!validRoles.contains(role)) {
      throw ArgumentError(
        'Invalid role "$role". Valid roles: ${validRoles.join(", ")}',
      );
    }

    final DateTime ts = timestamp ?? DateTime.now().toUtc();
    final int epochSeconds = ts.millisecondsSinceEpoch ~/ 1000;

    // message = merkleRoot || signerIdBytes || pack_uint64_be(timestamp) ||
    //           roleBytes || statementBytes
    final Uint8List signerIdBytes = Uint8List.fromList(utf8.encode(signerId));
    final Uint8List roleBytes = Uint8List.fromList(utf8.encode(role));
    final Uint8List statementBytes = Uint8List.fromList(utf8.encode(statement));

    final int messageLen =
        merkleRoot.length +
        signerIdBytes.length +
        8 +
        roleBytes.length +
        statementBytes.length;
    final Uint8List message = Uint8List(messageLen);
    int offset = 0;

    message.setRange(offset, offset + merkleRoot.length, merkleRoot);
    offset += merkleRoot.length;

    message.setRange(offset, offset + signerIdBytes.length, signerIdBytes);
    offset += signerIdBytes.length;

    final ByteData bd = ByteData(8);
    bd.setUint64(0, epochSeconds, Endian.big);
    message.setRange(offset, offset + 8, bd.buffer.asUint8List());
    offset += 8;

    message.setRange(offset, offset + roleBytes.length, roleBytes);
    offset += roleBytes.length;

    message.setRange(offset, offset + statementBytes.length, statementBytes);

    // hmac = HMAC-SHA256(signerKey, message)
    final hmac = Hmac(sha256, signerKey);
    final Uint8List hmacBytes = Uint8List.fromList(hmac.convert(message).bytes);

    return <String, dynamic>{
      'signer_id': signerId,
      'role': role,
      'statement': statement,
      'timestamp': epochSeconds,
      'hmac_hex': _bytesToHex(hmacBytes),
    };
  }

  /// Verifies a role attestation against a [merkleRoot] and [signerKey].
  ///
  /// Similar to [verifyAttestation] but includes the `role` field in the
  /// HMAC computation.
  ///
  /// Returns `true` if the attestation is valid.
  static bool verifyRoleAttestation(
    Map<String, dynamic> attestation,
    Uint8List merkleRoot,
    Uint8List signerKey,
  ) {
    final String signerId = attestation['signer_id'] as String;
    final String role = attestation['role'] as String;
    final String statement = attestation['statement'] as String;
    final int epochSeconds = attestation['timestamp'] as int;
    final String storedHmacHex = attestation['hmac_hex'] as String;

    // Rebuild the message.
    final Uint8List signerIdBytes = Uint8List.fromList(utf8.encode(signerId));
    final Uint8List roleBytes = Uint8List.fromList(utf8.encode(role));
    final Uint8List statementBytes = Uint8List.fromList(utf8.encode(statement));

    final int messageLen =
        merkleRoot.length +
        signerIdBytes.length +
        8 +
        roleBytes.length +
        statementBytes.length;
    final Uint8List message = Uint8List(messageLen);
    int offset = 0;

    message.setRange(offset, offset + merkleRoot.length, merkleRoot);
    offset += merkleRoot.length;

    message.setRange(offset, offset + signerIdBytes.length, signerIdBytes);
    offset += signerIdBytes.length;

    final ByteData bd = ByteData(8);
    bd.setUint64(0, epochSeconds, Endian.big);
    message.setRange(offset, offset + 8, bd.buffer.asUint8List());
    offset += 8;

    message.setRange(offset, offset + roleBytes.length, roleBytes);
    offset += roleBytes.length;

    message.setRange(offset, offset + statementBytes.length, statementBytes);

    // Compute HMAC.
    final hmac = Hmac(sha256, signerKey);
    final Uint8List computedHmac = Uint8List.fromList(
      hmac.convert(message).bytes,
    );
    final String computedHex = _bytesToHex(computedHmac);

    return _constantTimeEquals(storedHmacHex, computedHex);
  }

  /// Checks if all required roles have been attested.
  ///
  /// Verifies each attestation's HMAC signature and checks that every role
  /// in [requiredRoles] has at least one valid attestation.
  ///
  /// [attestations] is the list of attestation maps (each with a `role` field).
  /// [requiredRoles] is the list of roles that must be present.
  /// [merkleRoot] is the 32-byte Merkle root of the file.
  /// [signerKeys] maps signer IDs to their 32-byte keys.
  ///
  /// Returns an [AttestationPolicyResult] with detailed status.
  static AttestationPolicyResult checkPolicy(
    List<Map<String, dynamic>> attestations,
    List<String> requiredRoles,
    Uint8List merkleRoot,
    Map<String, Uint8List> signerKeys,
  ) {
    final Map<String, bool> rolesFulfilled = <String, bool>{};
    for (final String role in requiredRoles) {
      rolesFulfilled[role] = false;
    }

    final List<String> validSigners = <String>[];
    final List<String> invalidSigners = <String>[];

    for (final Map<String, dynamic> attestation in attestations) {
      final String signerId = attestation['signer_id'] as String;
      final String? role = attestation['role'] as String?;

      // Verify the attestation signature.
      bool isValid = false;
      if (signerKeys.containsKey(signerId)) {
        if (role != null && attestation.containsKey('role')) {
          isValid = verifyRoleAttestation(
            attestation,
            merkleRoot,
            signerKeys[signerId]!,
          );
        } else {
          isValid = verifyAttestation(
            attestation,
            merkleRoot,
            signerKeys[signerId]!,
          );
        }
      }

      if (isValid) {
        validSigners.add(signerId);
        if (role != null && rolesFulfilled.containsKey(role)) {
          rolesFulfilled[role] = true;
        }
      } else {
        invalidSigners.add(signerId);
      }
    }

    final List<String> missingRoles = rolesFulfilled.entries
        .where((MapEntry<String, bool> e) => !e.value)
        .map((MapEntry<String, bool> e) => e.key)
        .toList();

    return AttestationPolicyResult(
      allRolesFulfilled: missingRoles.isEmpty,
      missingRoles: missingRoles,
      validSigners: validSigners,
      invalidSigners: invalidSigners,
    );
  }

  /// Converts bytes to lowercase hex string.
  static String _bytesToHex(Uint8List bytes) {
    final StringBuffer buf = StringBuffer();
    for (final byte in bytes) {
      buf.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  /// Constant-time string comparison.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// Result of an attestation policy check.
///
/// Indicates whether all required roles have been fulfilled by valid
/// attestations, and lists any missing roles or invalid signers.
class AttestationPolicyResult {
  /// Creates an [AttestationPolicyResult].
  AttestationPolicyResult({
    required this.allRolesFulfilled,
    required this.missingRoles,
    required this.validSigners,
    required this.invalidSigners,
  });

  /// Whether every required role has at least one valid attestation.
  final bool allRolesFulfilled;

  /// Roles that were required but have no valid attestation.
  final List<String> missingRoles;

  /// Signer IDs whose attestations passed HMAC verification.
  final List<String> validSigners;

  /// Signer IDs whose attestations failed HMAC verification.
  final List<String> invalidSigners;
}
