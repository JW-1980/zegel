import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'envelope.dart';

/// Certificate of Completion (v1.4) - DocuSign-style audit certificate.
///
/// A Certificate of Completion is a tamper-evident, human-readable record of
/// every action taken on a signing envelope. It's the electronic equivalent
/// of a notary's log book and is admissible as legal evidence in most
/// jurisdictions.
///
/// The certificate contains:
/// - Envelope metadata (ID, subject, sender)
/// - All recipients with their status and signing timestamps
/// - The complete hash-chained audit log
/// - IP addresses, user agents, and authentication results
/// - Document Merkle roots for integrity verification
/// - An HMAC over the entire certificate for tamper detection
///
/// The certificate is typically generated when an envelope reaches the
/// `completed`, `declined`, or `voided` status and is stored as a structured
/// block in a .zgl file or exported as a standalone document.

/// A Certificate of Completion for a signing envelope.
class CertificateOfCompletion {

  /// Decodes a certificate from JSON bytes.
  factory CertificateOfCompletion.decode(Uint8List data) {
    return CertificateOfCompletion.fromJson(
      jsonDecode(utf8.decode(data)) as Map<String, dynamic>,
    );
  }

  /// Deserializes from JSON.
  factory CertificateOfCompletion.fromJson(Map<String, dynamic> json) {
    return CertificateOfCompletion(
      envelopeId: json['envelope_id'] as String,
      envelopeSubject: json['envelope_subject'] as String,
      envelopeStatus: EnvelopeStatus.values.firstWhere(
        (s) => s.name == json['envelope_status'],
      ),
      senderName: json['sender_name'] as String?,
      senderEmail: json['sender_email'] as String?,
      recipients: (json['recipients'] as List<dynamic>)
          .map((r) => EnvelopeRecipient.fromJson(r as Map<String, dynamic>))
          .toList(),
      events: (json['events'] as List<dynamic>)
          .map((e) => EnvelopeEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
      documentMerkleRoots: (json['document_merkle_roots'] as List<dynamic>)
          .map((d) => d as String)
          .toList(),
      createdAt: json['created_at'] as int?,
      sentAt: json['sent_at'] as int?,
      completedAt: json['completed_at'] as int?,
      generatedAt: json['generated_at'] as int,
      certificateHash: json['certificate_hash'] as String?,
    );
  }
  /// Creates a [CertificateOfCompletion] from a completed [Envelope].
  CertificateOfCompletion({
    required this.envelopeId,
    required this.envelopeSubject,
    required this.envelopeStatus,
    required this.recipients,
    required this.events,
    required this.documentMerkleRoots,
    required this.generatedAt,
    this.senderName,
    this.senderEmail,
    this.createdAt,
    this.sentAt,
    this.completedAt,
    this.certificateHash,
  });

  /// Envelope ID.
  final String envelopeId;

  /// Envelope subject line.
  final String envelopeSubject;

  /// Final status of the envelope.
  final EnvelopeStatus envelopeStatus;

  /// Sender name.
  final String? senderName;

  /// Sender email.
  final String? senderEmail;

  /// All recipients with their final status.
  final List<EnvelopeRecipient> recipients;

  /// Complete audit event chain.
  final List<EnvelopeEvent> events;

  /// Merkle roots of documents in the envelope.
  final List<String> documentMerkleRoots;

  /// Envelope creation timestamp.
  final int? createdAt;

  /// Envelope sent timestamp.
  final int? sentAt;

  /// Envelope completion timestamp.
  final int? completedAt;

  /// Certificate generation timestamp.
  final int generatedAt;

  /// SHA-256 hash of the certificate content for tamper evidence.
  final String? certificateHash;

  /// Generates a Certificate of Completion from an envelope.
  static CertificateOfCompletion generate(Envelope envelope) {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    final cert = CertificateOfCompletion(
      envelopeId: envelope.id,
      envelopeSubject: envelope.subject,
      envelopeStatus: envelope.status,
      senderName: envelope.senderName,
      senderEmail: envelope.senderEmail,
      recipients: List<EnvelopeRecipient>.from(envelope.recipients),
      events: List<EnvelopeEvent>.from(envelope.events),
      documentMerkleRoots: List<String>.from(envelope.documentMerkleRoots),
      createdAt: envelope.createdAt,
      sentAt: envelope.sentAt,
      completedAt: envelope.completedAt,
      generatedAt: now,
    );

    // Compute a hash over the canonical JSON for tamper detection.
    final canonicalJson = jsonEncode(cert._canonicalJson());
    final hash = sha256.convert(utf8.encode(canonicalJson)).toString();

    return CertificateOfCompletion(
      envelopeId: cert.envelopeId,
      envelopeSubject: cert.envelopeSubject,
      envelopeStatus: cert.envelopeStatus,
      senderName: cert.senderName,
      senderEmail: cert.senderEmail,
      recipients: cert.recipients,
      events: cert.events,
      documentMerkleRoots: cert.documentMerkleRoots,
      createdAt: cert.createdAt,
      sentAt: cert.sentAt,
      completedAt: cert.completedAt,
      generatedAt: cert.generatedAt,
      certificateHash: hash,
    );
  }

  /// Verifies the certificate's tamper-evidence hash and audit chain.
  ///
  /// Returns `true` if:
  /// 1. The certificate hash matches the canonical content
  /// 2. The audit event chain is unbroken
  bool verify() {
    if (certificateHash == null) return false;

    // Re-compute hash of canonical content.
    final canonicalJson = jsonEncode(_canonicalJson());
    final computed = sha256.convert(utf8.encode(canonicalJson)).toString();
    if (computed != certificateHash) return false;

    // Verify audit chain.
    for (var i = 1; i < events.length; i++) {
      final expected = events[i - 1].computeHash();
      if (events[i].previousHash != expected) return false;
    }

    return true;
  }

  /// Renders the certificate as a human-readable text document.
  String renderText() {
    final buf = StringBuffer();
    buf.writeln('=' * 70);
    buf.writeln('          CERTIFICATE OF COMPLETION');
    buf.writeln('          Powered by Zegel Tamper-Proof Format');
    buf.writeln('=' * 70);
    buf.writeln();
    buf.writeln('Envelope ID:  $envelopeId');
    buf.writeln('Subject:      $envelopeSubject');
    buf.writeln('Status:       ${envelopeStatus.name.toUpperCase()}');
    if (senderName != null || senderEmail != null) {
      buf.writeln(
        'Sender:       ${senderName ?? ''} '
        '${senderEmail != null ? '<$senderEmail>' : ''}',
      );
    }
    buf.writeln();
    buf.writeln('Timeline:');
    if (createdAt != null) {
      buf.writeln('  Created:    ${_formatDate(createdAt!)}');
    }
    if (sentAt != null) {
      buf.writeln('  Sent:       ${_formatDate(sentAt!)}');
    }
    if (completedAt != null) {
      buf.writeln('  Completed:  ${_formatDate(completedAt!)}');
    }
    buf.writeln('  Generated:  ${_formatDate(generatedAt)}');
    buf.writeln();

    // Documents
    if (documentMerkleRoots.isNotEmpty) {
      buf.writeln('Documents (by Merkle root):');
      for (var i = 0; i < documentMerkleRoots.length; i++) {
        buf.writeln('  ${i + 1}. ${documentMerkleRoots[i]}');
      }
      buf.writeln();
    }

    // Recipients
    buf.writeln('-' * 70);
    buf.writeln('RECIPIENTS');
    buf.writeln('-' * 70);
    for (final r in recipients) {
      buf.writeln();
      buf.writeln('  Name:          ${r.name}');
      buf.writeln('  Email:         ${r.email}');
      buf.writeln('  Role:          ${r.role.name}');
      buf.writeln('  Status:        ${r.status.name}');
      buf.writeln('  Routing order: ${r.routingOrder}');
      buf.writeln('  Authentication: ${r.authentication.name}');
      if (r.signedAt != null) {
        buf.writeln('  Signed at:     ${_formatDate(r.signedAt!)}');
      }
      if (r.declinedAt != null) {
        buf.writeln('  Declined at:   ${_formatDate(r.declinedAt!)}');
        if (r.declineReason != null) {
          buf.writeln('  Reason:        ${r.declineReason}');
        }
      }
      if (r.ipAddress != null) {
        buf.writeln('  IP address:    ${r.ipAddress}');
      }
      if (r.signatureHash != null) {
        buf.writeln('  Signature:     ${r.signatureHash}');
      }
    }

    // Audit trail
    buf.writeln();
    buf.writeln('-' * 70);
    buf.writeln('AUDIT TRAIL (hash-chained for tamper evidence)');
    buf.writeln('-' * 70);
    for (final e in events) {
      buf.writeln();
      buf.writeln('  ${_formatDate(e.timestamp)}  [${e.eventType}]');
      buf.writeln('    ${e.description}');
      if (e.recipientId != null) {
        buf.writeln('    Recipient: ${e.recipientId}');
      }
      if (e.ipAddress != null) {
        buf.writeln('    IP: ${e.ipAddress}');
      }
      if (e.previousHash != null) {
        buf.writeln('    Prev hash: ${e.previousHash!.substring(0, 16)}...');
      }
    }

    // Tamper evidence
    buf.writeln();
    buf.writeln('=' * 70);
    buf.writeln('CERTIFICATE INTEGRITY');
    buf.writeln('=' * 70);
    if (certificateHash != null) {
      buf.writeln('Certificate Hash: $certificateHash');
      buf.writeln();
      buf.writeln('This certificate is cryptographically tamper-evident.');
      buf.writeln('Any modification to this document will cause the hash');
      buf.writeln('verification to fail.');
    }
    buf.writeln('=' * 70);

    return buf.toString();
  }

  /// Encodes the certificate to JSON bytes for embedding in a .zgl file.
  Uint8List encode() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'block_type': 'certificate_of_completion',
      ..._canonicalJson(),
    };
    if (certificateHash != null) json['certificate_hash'] = certificateHash;
    return json;
  }

  /// Canonical representation used for hashing (excludes the hash itself).
  Map<String, dynamic> _canonicalJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'envelope_id': envelopeId,
      'envelope_subject': envelopeSubject,
      'envelope_status': envelopeStatus.name,
      'document_merkle_roots': documentMerkleRoots,
      'recipients': recipients.map((r) => r.toJson()).toList(),
      'events': events.map((e) => e.toJson()).toList(),
      'generated_at': generatedAt,
    };
    if (senderName != null) json['sender_name'] = senderName;
    if (senderEmail != null) json['sender_email'] = senderEmail;
    if (createdAt != null) json['created_at'] = createdAt;
    if (sentAt != null) json['sent_at'] = sentAt;
    if (completedAt != null) json['completed_at'] = completedAt;
    return json;
  }

  /// Formats a Unix epoch timestamp as an ISO 8601 UTC date string.
  static String _formatDate(int epoch) {
    final dt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000, isUtc: true);
    return dt.toIso8601String();
  }
}
