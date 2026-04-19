import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Signing workflow envelope (v1.4) - DocuSign-style document routing.
///
/// An envelope groups one or more documents (sealed .zgl files) with a
/// workflow definition specifying who must sign, in what order, and with
/// what authentication. This provides DocuSign feature parity for
/// document signing workflows.
///
/// ## Envelope Lifecycle
///
/// 1. **Draft** - Envelope created, recipients and fields defined
/// 2. **Sent** - Envelope dispatched to first recipient(s)
/// 3. **In Progress** - Partial signatures collected
/// 4. **Completed** - All required signatures collected
/// 5. **Declined** - A recipient refused to sign
/// 6. **Voided** - Sender cancelled before completion
/// 7. **Expired** - Envelope passed its expiration date
///
/// ## Routing Modes
///
/// - **Sequential** - Recipients sign in a defined order (each waits for prior)
/// - **Parallel** - All recipients can sign simultaneously
/// - **Mixed** - Routing steps where each step can have multiple parallel signers

// =============================================================================
// Enums
// =============================================================================

/// Envelope status in the signing lifecycle.
enum EnvelopeStatus {
  /// Envelope is being edited and has not been sent.
  draft,

  /// Envelope has been sent to recipients but no signatures collected yet.
  sent,

  /// Some but not all required signatures have been collected.
  inProgress,

  /// All required signatures have been collected. Envelope is complete.
  completed,

  /// A recipient refused to sign. Envelope cannot be completed.
  declined,

  /// Sender cancelled the envelope before completion.
  voided,

  /// Envelope passed its expiration date without completion.
  expired,
}

/// Routing mode for recipient signing order.
enum RoutingMode {
  /// Recipients sign in the order they appear in the list.
  /// Each recipient waits for all prior recipients to complete.
  sequential,

  /// All recipients can sign in parallel, in any order.
  parallel,

  /// Mixed mode: steps are sequential, but each step has parallel signers.
  mixed,
}

/// Role of a recipient in the signing workflow.
enum RecipientRole {
  /// Must sign the document.
  signer,

  /// Must approve but not sign (e.g., manager approval).
  approver,

  /// Receives a copy when completed (carbon copy).
  cc,

  /// Certified delivery - receives a copy with delivery receipt.
  certifiedDelivery,

  /// In-person signer - signs on the sender's device.
  inPerson,

  /// Witness to the signing event.
  witness,

  /// Notary for notarized documents.
  notary,
}

/// Authentication method required before signing.
enum AuthenticationMethod {
  /// No additional authentication - link is sufficient.
  none,

  /// Access code (shared out-of-band).
  accessCode,

  /// SMS one-time code.
  sms,

  /// Phone call with spoken code.
  phoneCall,

  /// Knowledge-based authentication (personal questions).
  kba,

  /// Government ID verification (e.g., passport, driver license).
  idVerification,

  /// Digital certificate / PKI (e.g., smart card).
  digitalCertificate,
}

/// Type of signature field to be filled by a recipient.
enum FieldType {
  /// Handwritten signature (wet signature).
  signature,

  /// Initial (abbreviated signature).
  initial,

  /// Date stamp (usually today's date).
  date,

  /// Free text input.
  text,

  /// Checkbox (true/false).
  checkbox,

  /// Radio button selection.
  radio,

  /// Dropdown selection.
  dropdown,

  /// Name of the signer (auto-filled).
  name,

  /// Email of the signer (auto-filled).
  email,

  /// Company of the signer (auto-filled).
  company,

  /// Title / job position (auto-filled).
  title,
}

// =============================================================================
// SignatureField - A field to be filled by a recipient
// =============================================================================

/// A field on a document that a recipient must fill.
class SignatureField {

  /// Deserializes from JSON.
  factory SignatureField.fromJson(Map<String, dynamic> json) {
    return SignatureField(
      id: json['id'] as String,
      type: FieldType.values.firstWhere((t) => t.name == json['type']),
      recipientId: json['recipient_id'] as String,
      page: json['page'] as int,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num?)?.toDouble() ?? 120,
      height: (json['height'] as num?)?.toDouble() ?? 40,
      required: json['required'] as bool? ?? true,
      label: json['label'] as String?,
      defaultValue: json['default_value'] as String?,
      value: json['value'] as String?,
      options:
          (json['options'] as List<dynamic>?)?.map((o) => o as String).toList(),
    );
  }
  /// Creates a [SignatureField].
  const SignatureField({
    required this.id,
    required this.type,
    required this.recipientId,
    required this.page,
    required this.x,
    required this.y,
    this.width = 120,
    this.height = 40,
    this.required = true,
    this.label,
    this.defaultValue,
    this.value,
    this.options,
  });

  /// Unique identifier within the envelope.
  final String id;

  /// Type of field.
  final FieldType type;

  /// ID of the recipient who must fill this field.
  final String recipientId;

  /// Zero-based page number within the document.
  final int page;

  /// X coordinate in points (1/72 inch).
  final double x;

  /// Y coordinate in points (1/72 inch).
  final double y;

  /// Field width in points.
  final double width;

  /// Field height in points.
  final double height;

  /// Whether the field is required for signing completion.
  final bool required;

  /// Optional label displayed next to the field.
  final String? label;

  /// Default value (for pre-filled fields).
  final String? defaultValue;

  /// Current value (filled when recipient signs).
  final String? value;

  /// Options for dropdown/radio fields.
  final List<String>? options;

  /// Serializes to JSON.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'id': id,
      'type': type.name,
      'recipient_id': recipientId,
      'page': page,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'required': required,
    };
    if (label != null) json['label'] = label;
    if (defaultValue != null) json['default_value'] = defaultValue;
    if (value != null) json['value'] = value;
    if (options != null) json['options'] = options;
    return json;
  }
}

// =============================================================================
// EnvelopeRecipient - A party in the signing workflow
// =============================================================================

/// A recipient in an envelope signing workflow.
class EnvelopeRecipient {

  /// Deserializes from JSON.
  factory EnvelopeRecipient.fromJson(Map<String, dynamic> json) {
    return EnvelopeRecipient(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
      role: RecipientRole.values.firstWhere((r) => r.name == json['role']),
      routingOrder: json['routing_order'] as int? ?? 1,
      authentication: AuthenticationMethod.values
          .firstWhere((a) => a.name == (json['authentication'] ?? 'none')),
      accessCode: json['access_code'] as String?,
      phoneNumber: json['phone_number'] as String?,
      company: json['company'] as String?,
      title: json['title'] as String?,
      note: json['note'] as String?,
      status: RecipientStatus.values
          .firstWhere((s) => s.name == (json['status'] ?? 'created')),
      signedAt: json['signed_at'] as int?,
      declinedAt: json['declined_at'] as int?,
      declineReason: json['decline_reason'] as String?,
      ipAddress: json['ip_address'] as String?,
      signatureHash: json['signature_hash'] as String?,
    );
  }
  /// Creates an [EnvelopeRecipient].
  const EnvelopeRecipient({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.routingOrder = 1,
    this.authentication = AuthenticationMethod.none,
    this.accessCode,
    this.phoneNumber,
    this.company,
    this.title,
    this.note,
    this.status = RecipientStatus.created,
    this.signedAt,
    this.declinedAt,
    this.declineReason,
    this.ipAddress,
    this.signatureHash,
  });

  /// Unique identifier within the envelope.
  final String id;

  /// Display name.
  final String name;

  /// Email address.
  final String email;

  /// Role in the signing workflow.
  final RecipientRole role;

  /// Routing order (for sequential routing). Lower numbers sign first.
  final int routingOrder;

  /// Required authentication method before signing.
  final AuthenticationMethod authentication;

  /// Access code (for accessCode authentication).
  final String? accessCode;

  /// Phone number (for SMS/phone authentication).
  final String? phoneNumber;

  /// Company name.
  final String? company;

  /// Job title.
  final String? title;

  /// Personal note from sender to this recipient.
  final String? note;

  /// Current status in the workflow.
  final RecipientStatus status;

  /// Timestamp when recipient completed signing.
  final int? signedAt;

  /// Timestamp when recipient declined.
  final int? declinedAt;

  /// Reason for declining (if declined).
  final String? declineReason;

  /// IP address from which the recipient signed.
  final String? ipAddress;

  /// Hex hash of the signature (if signed).
  final String? signatureHash;

  /// Serializes to JSON.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'id': id,
      'name': name,
      'email': email,
      'role': role.name,
      'routing_order': routingOrder,
      'authentication': authentication.name,
      'status': status.name,
    };
    if (accessCode != null) json['access_code'] = accessCode;
    if (phoneNumber != null) json['phone_number'] = phoneNumber;
    if (company != null) json['company'] = company;
    if (title != null) json['title'] = title;
    if (note != null) json['note'] = note;
    if (signedAt != null) json['signed_at'] = signedAt;
    if (declinedAt != null) json['declined_at'] = declinedAt;
    if (declineReason != null) json['decline_reason'] = declineReason;
    if (ipAddress != null) json['ip_address'] = ipAddress;
    if (signatureHash != null) json['signature_hash'] = signatureHash;
    return json;
  }
}

/// Status of a single recipient in the signing workflow.
enum RecipientStatus {
  /// Recipient has been added but envelope not yet sent.
  created,

  /// Envelope has been sent to this recipient (awaiting their action).
  sent,

  /// Recipient has opened the envelope.
  delivered,

  /// Recipient has signed all their required fields.
  signed,

  /// Recipient has completed (signed + acknowledged).
  completed,

  /// Recipient declined to sign.
  declined,

  /// Authentication failed (wrong code, ID verification failed).
  authenticationFailed,
}

// =============================================================================
// EnvelopeEvent - An audit log entry
// =============================================================================

/// A single event in the envelope audit log.
class EnvelopeEvent {

  /// Deserializes from JSON.
  factory EnvelopeEvent.fromJson(Map<String, dynamic> json) {
    return EnvelopeEvent(
      timestamp: json['timestamp'] as int,
      eventType: json['event_type'] as String,
      description: json['description'] as String,
      recipientId: json['recipient_id'] as String?,
      ipAddress: json['ip_address'] as String?,
      userAgent: json['user_agent'] as String?,
      previousHash: json['previous_hash'] as String?,
    );
  }
  /// Creates an [EnvelopeEvent].
  const EnvelopeEvent({
    required this.timestamp,
    required this.eventType,
    required this.description,
    this.recipientId,
    this.ipAddress,
    this.userAgent,
    this.previousHash,
  });

  /// Unix epoch seconds of the event.
  final int timestamp;

  /// Type of event (e.g., "envelope_sent", "recipient_signed", "envelope_completed").
  final String eventType;

  /// Human-readable description.
  final String description;

  /// ID of the recipient involved (if applicable).
  final String? recipientId;

  /// IP address from which the action was taken.
  final String? ipAddress;

  /// User agent string.
  final String? userAgent;

  /// Hash of the previous event in the chain (for tamper-evident audit trail).
  final String? previousHash;

  /// Computes the hash of this event for chain-linking.
  String computeHash() {
    final canonical = <String, dynamic>{
      'timestamp': timestamp,
      'event_type': eventType,
      'description': description,
      if (recipientId != null) 'recipient_id': recipientId,
      if (ipAddress != null) 'ip_address': ipAddress,
      if (userAgent != null) 'user_agent': userAgent,
      if (previousHash != null) 'previous_hash': previousHash,
    };
    final bytes = utf8.encode(jsonEncode(canonical));
    return sha256.convert(bytes).toString();
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'timestamp': timestamp,
      'event_type': eventType,
      'description': description,
    };
    if (recipientId != null) json['recipient_id'] = recipientId;
    if (ipAddress != null) json['ip_address'] = ipAddress;
    if (userAgent != null) json['user_agent'] = userAgent;
    if (previousHash != null) json['previous_hash'] = previousHash;
    return json;
  }
}

// =============================================================================
// Envelope - The main workflow container
// =============================================================================

/// A signing workflow envelope containing documents, recipients, and routing.
///
/// An envelope is encoded as a block inside a .zgl file or as a separate
/// sidecar file. It references one or more documents by their Merkle root
/// and defines the signing workflow.
class Envelope {

  /// Decodes an envelope from JSON bytes.
  factory Envelope.decode(Uint8List data) {
    return Envelope.fromJson(
      jsonDecode(utf8.decode(data)) as Map<String, dynamic>,
    );
  }

  /// Deserializes from JSON.
  factory Envelope.fromJson(Map<String, dynamic> json) {
    return Envelope(
      id: json['id'] as String,
      subject: json['subject'] as String,
      message: json['message'] as String?,
      routingMode: RoutingMode.values
          .firstWhere((r) => r.name == (json['routing_mode'] ?? 'sequential')),
      status: EnvelopeStatus.values
          .firstWhere((s) => s.name == (json['status'] ?? 'draft')),
      documentMerkleRoots: (json['document_merkle_roots'] as List<dynamic>?)
              ?.map((d) => d as String)
              .toList() ??
          <String>[],
      recipients: (json['recipients'] as List<dynamic>)
          .map((r) => EnvelopeRecipient.fromJson(r as Map<String, dynamic>))
          .toList(),
      fields: (json['fields'] as List<dynamic>?)
              ?.map((f) => SignatureField.fromJson(f as Map<String, dynamic>))
              .toList() ??
          <SignatureField>[],
      events: (json['events'] as List<dynamic>?)
              ?.map((e) => EnvelopeEvent.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <EnvelopeEvent>[],
      createdAt: json['created_at'] as int?,
      sentAt: json['sent_at'] as int?,
      completedAt: json['completed_at'] as int?,
      expiresAt: json['expires_at'] as int?,
      senderName: json['sender_name'] as String?,
      senderEmail: json['sender_email'] as String?,
      remindersEnabled: json['reminders_enabled'] as bool? ?? false,
      reminderIntervalDays: json['reminder_interval_days'] as int? ?? 3,
      reminderMaxCount: json['reminder_max_count'] as int? ?? 3,
    );
  }
  /// Creates a new [Envelope].
  Envelope({
    required this.id,
    required this.subject,
    required this.recipients,
    this.message,
    this.routingMode = RoutingMode.sequential,
    this.status = EnvelopeStatus.draft,
    List<String>? documentMerkleRoots,
    List<SignatureField>? fields,
    List<EnvelopeEvent>? events,
    this.createdAt,
    this.sentAt,
    this.completedAt,
    this.expiresAt,
    this.senderName,
    this.senderEmail,
    this.remindersEnabled = false,
    this.reminderIntervalDays = 3,
    this.reminderMaxCount = 3,
  })  : documentMerkleRoots = documentMerkleRoots ?? <String>[],
        fields = fields ?? <SignatureField>[],
        events = events ?? <EnvelopeEvent>[];

  /// Unique identifier for the envelope.
  final String id;

  /// Subject line (like an email subject).
  final String subject;

  /// Optional message body from sender to recipients.
  final String? message;

  /// Routing mode for recipient signing order.
  final RoutingMode routingMode;

  /// Current envelope status.
  EnvelopeStatus status;

  /// Merkle roots of documents included in this envelope.
  final List<String> documentMerkleRoots;

  /// List of recipients in the signing workflow.
  final List<EnvelopeRecipient> recipients;

  /// Signature fields to be filled by recipients.
  final List<SignatureField> fields;

  /// Audit log of all events.
  final List<EnvelopeEvent> events;

  /// Creation timestamp.
  final int? createdAt;

  /// Send timestamp.
  int? sentAt;

  /// Completion timestamp.
  int? completedAt;

  /// Expiration timestamp (envelope expires if not completed).
  final int? expiresAt;

  /// Name of the sender.
  final String? senderName;

  /// Email of the sender.
  final String? senderEmail;

  /// Whether reminders should be sent to pending recipients.
  final bool remindersEnabled;

  /// Days between reminder emails.
  final int reminderIntervalDays;

  /// Maximum number of reminders to send.
  final int reminderMaxCount;

  /// Returns the current recipient(s) who should be acting, based on routing.
  ///
  /// For sequential routing, returns the first recipient who hasn't completed.
  /// For parallel routing, returns all recipients who haven't completed.
  /// For mixed routing, returns all recipients at the lowest incomplete step.
  List<EnvelopeRecipient> currentRecipients() {
    if (routingMode == RoutingMode.parallel) {
      return recipients
          .where((r) =>
              r.status != RecipientStatus.signed &&
              r.status != RecipientStatus.completed &&
              r.status != RecipientStatus.declined)
          .toList();
    }

    // Sequential or mixed: group by routing order, return lowest incomplete.
    final sorted = List<EnvelopeRecipient>.from(recipients)
      ..sort((a, b) => a.routingOrder.compareTo(b.routingOrder));

    for (final recipient in sorted) {
      if (recipient.status != RecipientStatus.signed &&
          recipient.status != RecipientStatus.completed &&
          recipient.status != RecipientStatus.declined) {
        // Return all recipients at this routing order (for mixed mode).
        return recipients
            .where((r) =>
                r.routingOrder == recipient.routingOrder &&
                r.status != RecipientStatus.signed &&
                r.status != RecipientStatus.completed &&
                r.status != RecipientStatus.declined)
            .toList();
      }
    }

    return <EnvelopeRecipient>[];
  }

  /// Appends a new event to the audit log with chain-hashing.
  void appendEvent(EnvelopeEvent event) {
    final withChain = EnvelopeEvent(
      timestamp: event.timestamp,
      eventType: event.eventType,
      description: event.description,
      recipientId: event.recipientId,
      ipAddress: event.ipAddress,
      userAgent: event.userAgent,
      previousHash: events.isEmpty ? null : events.last.computeHash(),
    );
    events.add(withChain);
  }

  /// Verifies the audit trail's chain integrity.
  ///
  /// Returns `true` if every event's `previousHash` matches the actual hash
  /// of the preceding event. Uses a constant-time string comparison so that
  /// a would-be forger cannot learn how many leading bytes of their guessed
  /// `previousHash` happen to match.
  bool verifyAuditChain() {
    for (var i = 1; i < events.length; i++) {
      final expected = events[i - 1].computeHash();
      final actual = events[i].previousHash ?? '';
      if (!_constantTimeEqualsString(actual, expected)) return false;
    }
    return true;
  }

  static bool _constantTimeEqualsString(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Checks if all required recipients have signed.
  bool isFullySigned() {
    for (final r in recipients) {
      if (r.role == RecipientRole.cc ||
          r.role == RecipientRole.certifiedDelivery) {
        continue; // CC recipients don't sign.
      }
      if (r.status != RecipientStatus.signed &&
          r.status != RecipientStatus.completed) {
        return false;
      }
    }
    return true;
  }

  /// Checks if the envelope is past its expiration date.
  bool isExpired() {
    if (expiresAt == null) return false;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    return now > expiresAt!;
  }

  /// Encodes this envelope to JSON bytes for embedding in a .zgl file.
  Uint8List encode() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'block_type': 'envelope',
      'id': id,
      'subject': subject,
      'routing_mode': routingMode.name,
      'status': status.name,
      'document_merkle_roots': documentMerkleRoots,
      'recipients': recipients.map((r) => r.toJson()).toList(),
      'fields': fields.map((f) => f.toJson()).toList(),
      'events': events.map((e) => e.toJson()).toList(),
      'reminders_enabled': remindersEnabled,
      'reminder_interval_days': reminderIntervalDays,
      'reminder_max_count': reminderMaxCount,
    };
    if (message != null) json['message'] = message;
    if (createdAt != null) json['created_at'] = createdAt;
    if (sentAt != null) json['sent_at'] = sentAt;
    if (completedAt != null) json['completed_at'] = completedAt;
    if (expiresAt != null) json['expires_at'] = expiresAt;
    if (senderName != null) json['sender_name'] = senderName;
    if (senderEmail != null) json['sender_email'] = senderEmail;
    return json;
  }
}
