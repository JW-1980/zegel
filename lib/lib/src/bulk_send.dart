import 'dart:convert';
import 'dart:typed_data';

import 'envelope.dart';
import 'template.dart';

/// Bulk send (v1.4) - DocuSign-style mass document distribution.
///
/// Bulk send allows a sender to distribute a single document to many
/// recipients at once, each receiving their own independent envelope.
/// Useful for scenarios like:
/// - Annual employee policy acknowledgments
/// - Mass contract renewals
/// - Large-scale NDAs for vendor onboarding
/// - Bulk consent collection (e.g. GDPR)
///
/// ## Flow
///
/// 1. Sender creates a template with one signer role
/// 2. Sender uploads a recipient list (CSV or programmatic)
/// 3. A [BulkSendJob] is created with one envelope per recipient
/// 4. Each envelope is independently tracked and audited
/// 5. The job reports aggregate statistics (sent, signed, declined, etc.)

// =============================================================================
// BulkRecipient - A single entry in a bulk send list
// =============================================================================

/// A single recipient in a bulk send list.
class BulkRecipient {

  /// Deserializes from JSON.
  factory BulkRecipient.fromJson(Map<String, dynamic> json) {
    return BulkRecipient(
      name: json['name'] as String,
      email: json['email'] as String,
      customFields: (json['custom_fields'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as String),
          ) ??
          <String, String>{},
      accessCode: json['access_code'] as String?,
      phoneNumber: json['phone_number'] as String?,
      company: json['company'] as String?,
      title: json['title'] as String?,
    );
  }
  /// Creates a [BulkRecipient].
  const BulkRecipient({
    required this.name,
    required this.email,
    this.customFields = const <String, String>{},
    this.accessCode,
    this.phoneNumber,
    this.company,
    this.title,
  });

  /// Recipient name.
  final String name;

  /// Recipient email address.
  final String email;

  /// Optional custom fields to merge into the envelope (e.g., "employee_id").
  final Map<String, String> customFields;

  /// Access code for authentication.
  final String? accessCode;

  /// Phone number for SMS authentication.
  final String? phoneNumber;

  /// Company name.
  final String? company;

  /// Job title.
  final String? title;

  /// Parses a recipient list from CSV bytes.
  ///
  /// Expected columns (first row is header): `name,email[,company,title,phone,access_code,<custom fields>...]`
  ///
  /// Returns a list of parsed [BulkRecipient]s.
  static List<BulkRecipient> parseCsv(Uint8List csvBytes) {
    final csv = utf8.decode(csvBytes);
    final lines = csv.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return <BulkRecipient>[];

    final header = lines[0].split(',').map((h) => h.trim()).toList();
    final nameIdx = header.indexOf('name');
    final emailIdx = header.indexOf('email');

    if (nameIdx < 0 || emailIdx < 0) {
      throw FormatException(
        'CSV must have "name" and "email" columns (got: ${header.join(", ")})',
      );
    }

    final companyIdx = header.indexOf('company');
    final titleIdx = header.indexOf('title');
    final phoneIdx = header.indexOf('phone');
    final accessCodeIdx = header.indexOf('access_code');

    // Custom fields are any columns not in the standard list.
    final standardFields = <String>{
      'name',
      'email',
      'company',
      'title',
      'phone',
      'access_code',
    };
    final customFieldIndices = <int, String>{};
    for (var i = 0; i < header.length; i++) {
      if (!standardFields.contains(header[i])) {
        customFieldIndices[i] = header[i];
      }
    }

    final recipients = <BulkRecipient>[];
    for (var i = 1; i < lines.length; i++) {
      final fields = _parseCsvLine(lines[i]);
      if (fields.length <= emailIdx) continue;

      final customFields = <String, String>{};
      for (final entry in customFieldIndices.entries) {
        if (fields.length > entry.key) {
          customFields[entry.value] = fields[entry.key];
        }
      }

      recipients.add(
        BulkRecipient(
          name: fields[nameIdx],
          email: fields[emailIdx],
          company: companyIdx >= 0 && fields.length > companyIdx
              ? (fields[companyIdx].isEmpty ? null : fields[companyIdx])
              : null,
          title: titleIdx >= 0 && fields.length > titleIdx
              ? (fields[titleIdx].isEmpty ? null : fields[titleIdx])
              : null,
          phoneNumber: phoneIdx >= 0 && fields.length > phoneIdx
              ? (fields[phoneIdx].isEmpty ? null : fields[phoneIdx])
              : null,
          accessCode: accessCodeIdx >= 0 && fields.length > accessCodeIdx
              ? (fields[accessCodeIdx].isEmpty ? null : fields[accessCodeIdx])
              : null,
          customFields: customFields,
        ),
      );
    }

    return recipients;
  }

  /// Parses a single CSV line, handling quoted fields with embedded commas.
  static List<String> _parseCsvLine(String line) {
    final fields = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        fields.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    fields.add(buf.toString());
    return fields;
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'name': name,
      'email': email,
    };
    if (customFields.isNotEmpty) json['custom_fields'] = customFields;
    if (accessCode != null) json['access_code'] = accessCode;
    if (phoneNumber != null) json['phone_number'] = phoneNumber;
    if (company != null) json['company'] = company;
    if (title != null) json['title'] = title;
    return json;
  }
}

// =============================================================================
// BulkSendJob - A collection of envelopes generated from a bulk list
// =============================================================================

/// Status of a bulk send job.
enum BulkSendStatus {
  /// Job is being prepared, no envelopes sent yet.
  draft,

  /// Envelopes are being dispatched.
  dispatching,

  /// All envelopes have been sent, awaiting signatures.
  inProgress,

  /// All envelopes reached a final state (completed, declined, or expired).
  complete,

  /// Job was cancelled by the sender.
  cancelled,
}

/// A bulk send job containing many envelopes generated from one template.
class BulkSendJob {

  /// Decodes from JSON bytes.
  factory BulkSendJob.decode(Uint8List data) {
    return BulkSendJob.fromJson(
      jsonDecode(utf8.decode(data)) as Map<String, dynamic>,
    );
  }

  /// Deserializes from JSON.
  factory BulkSendJob.fromJson(Map<String, dynamic> json) {
    return BulkSendJob(
      id: json['id'] as String,
      templateId: json['template_id'] as String,
      recipients: (json['recipients'] as List<dynamic>)
          .map((r) => BulkRecipient.fromJson(r as Map<String, dynamic>))
          .toList(),
      envelopeIds: (json['envelope_ids'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      status: BulkSendStatus.values
          .firstWhere((s) => s.name == (json['status'] ?? 'draft')),
      createdAt: json['created_at'] as int?,
      dispatchedAt: json['dispatched_at'] as int?,
      completedAt: json['completed_at'] as int?,
      senderName: json['sender_name'] as String?,
      senderEmail: json['sender_email'] as String?,
      name: json['name'] as String?,
    );
  }
  /// Creates a [BulkSendJob].
  BulkSendJob({
    required this.id,
    required this.templateId,
    required this.recipients,
    required this.envelopeIds,
    this.status = BulkSendStatus.draft,
    this.createdAt,
    this.dispatchedAt,
    this.completedAt,
    this.senderName,
    this.senderEmail,
    this.name,
  });

  /// Unique job identifier.
  final String id;

  /// ID of the template used for this bulk send.
  final String templateId;

  /// List of bulk recipients.
  final List<BulkRecipient> recipients;

  /// Generated envelope IDs (one per recipient).
  final List<String> envelopeIds;

  /// Current job status.
  BulkSendStatus status;

  /// Job creation timestamp.
  final int? createdAt;

  /// Timestamp when envelopes were dispatched.
  int? dispatchedAt;

  /// Timestamp when all envelopes reached final state.
  int? completedAt;

  /// Name of the sender.
  final String? senderName;

  /// Email of the sender.
  final String? senderEmail;

  /// Human-readable name for the job.
  final String? name;

  /// Creates envelopes from a template for each recipient in the list.
  ///
  /// [template] must have exactly one signer role (the recipient).
  /// [signerRoleId] identifies which template role is the signer.
  static BulkSendJob fromTemplate({
    required String jobId,
    required EnvelopeTemplate template,
    required String signerRoleId,
    required List<BulkRecipient> recipients,
    required List<String> documentMerkleRoots,
    String? senderName,
    String? senderEmail,
    String? name,
  }) {
    // Validate signer role exists.
    if (!template.roles.any((r) => r.roleId == signerRoleId)) {
      throw ArgumentError(
        'Template does not contain role "$signerRoleId"',
      );
    }

    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final envelopeIds = <String>[];

    // Generate envelope IDs (envelopes themselves are created on dispatch).
    for (var i = 0; i < recipients.length; i++) {
      envelopeIds.add('$jobId-env-${i.toString().padLeft(6, '0')}');
    }

    return BulkSendJob(
      id: jobId,
      templateId: template.id,
      recipients: List<BulkRecipient>.from(recipients),
      envelopeIds: envelopeIds,
      createdAt: now,
      senderName: senderName,
      senderEmail: senderEmail,
      name: name,
    );
  }

  /// Creates the actual envelopes for this bulk send job.
  ///
  /// Returns a list of [Envelope] objects, one per recipient. Each envelope
  /// is a fresh instance of the template with the recipient's data filled in.
  List<Envelope> createEnvelopes({
    required EnvelopeTemplate template,
    required String signerRoleId,
    required List<String> documentMerkleRoots,
  }) {
    final envelopes = <Envelope>[];

    for (var i = 0; i < recipients.length; i++) {
      final recipient = recipients[i];
      final envelopeId = envelopeIds[i];

      final roleMapping = <String, TemplateRoleMapping>{
        signerRoleId: TemplateRoleMapping(
          name: recipient.name,
          email: recipient.email,
          company: recipient.company,
          title: recipient.title,
          phoneNumber: recipient.phoneNumber,
          accessCode: recipient.accessCode,
        ),
      };

      envelopes.add(
        template.instantiate(
          envelopeId: envelopeId,
          roleMapping: roleMapping,
          documentMerkleRoots: documentMerkleRoots,
          senderName: senderName,
          senderEmail: senderEmail,
        ),
      );
    }

    return envelopes;
  }

  /// Encodes to JSON bytes.
  Uint8List encode() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'block_type': 'bulk_send_job',
      'id': id,
      'template_id': templateId,
      'recipients': recipients.map((r) => r.toJson()).toList(),
      'envelope_ids': envelopeIds,
      'status': status.name,
    };
    if (createdAt != null) json['created_at'] = createdAt;
    if (dispatchedAt != null) json['dispatched_at'] = dispatchedAt;
    if (completedAt != null) json['completed_at'] = completedAt;
    if (senderName != null) json['sender_name'] = senderName;
    if (senderEmail != null) json['sender_email'] = senderEmail;
    if (name != null) json['name'] = name;
    return json;
  }
}
