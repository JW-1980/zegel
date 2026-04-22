import 'dart:convert';
import 'dart:typed_data';

import 'envelope.dart';

/// Reusable envelope templates (v1.4) - DocuSign-style document templates.
///
/// Templates capture the structure of a recurring signing workflow: recipient
/// roles, field positions, authentication requirements, and default messages.
/// When you need to send the same document to different people (e.g., a
/// standard NDA, employment contract, or purchase order), you instantiate a
/// template rather than rebuilding the workflow each time.
///
/// ## Template vs. Envelope
///
/// - A **template** defines ROLES (e.g., "buyer", "seller") with placeholder
///   field positions.
/// - An **envelope** is an instance of a template filled with actual
///   recipient data.
///
/// Templates are serialized as JSON and can be stored as .zgl files for
/// integrity protection.

// =============================================================================
// TemplateRole - A role placeholder in a template
// =============================================================================

/// A role placeholder in a template.
///
/// When instantiating the template, each role is mapped to a concrete
/// [EnvelopeRecipient] by providing a name, email, and authentication details.
class TemplateRole {

  /// Deserializes from JSON.
  factory TemplateRole.fromJson(Map<String, dynamic> json) {
    return TemplateRole(
      roleId: json['role_id'] as String,
      roleName: json['role_name'] as String,
      recipientRole: RecipientRole.values.firstWhere(
        (r) => r.name == json['recipient_role'],
      ),
      routingOrder: json['routing_order'] as int? ?? 1,
      defaultAuthentication: AuthenticationMethod.values.firstWhere(
        (a) => a.name == (json['default_authentication'] ?? 'none'),
      ),
      defaultNote: json['default_note'] as String?,
      description: json['description'] as String?,
    );
  }
  /// Creates a [TemplateRole].
  const TemplateRole({
    required this.roleId,
    required this.roleName,
    required this.recipientRole,
    this.routingOrder = 1,
    this.defaultAuthentication = AuthenticationMethod.none,
    this.defaultNote,
    this.description,
  });

  /// Internal identifier for the role (used to match fields to roles).
  final String roleId;

  /// Human-readable role name (e.g., "Buyer", "Seller", "Witness").
  final String roleName;

  /// The recipient role type (signer, approver, witness, etc.).
  final RecipientRole recipientRole;

  /// Routing order for sequential signing.
  final int routingOrder;

  /// Default authentication method for this role.
  final AuthenticationMethod defaultAuthentication;

  /// Default personal note for recipients in this role.
  final String? defaultNote;

  /// Description of what this role is for.
  final String? description;

  /// Serializes to JSON.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'role_id': roleId,
      'role_name': roleName,
      'recipient_role': recipientRole.name,
      'routing_order': routingOrder,
      'default_authentication': defaultAuthentication.name,
    };
    if (defaultNote != null) json['default_note'] = defaultNote;
    if (description != null) json['description'] = description;
    return json;
  }
}

// =============================================================================
// TemplateField - A field placeholder in a template
// =============================================================================

/// A field placeholder in a template.
///
/// Template fields use [roleId] instead of a concrete recipient ID.
/// When the template is instantiated, fields are remapped to the actual
/// recipients for each role.
class TemplateField {

  /// Deserializes from JSON.
  factory TemplateField.fromJson(Map<String, dynamic> json) {
    return TemplateField(
      id: json['id'] as String,
      type: FieldType.values.firstWhere((t) => t.name == json['type']),
      roleId: json['role_id'] as String,
      page: json['page'] as int,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num?)?.toDouble() ?? 120,
      height: (json['height'] as num?)?.toDouble() ?? 40,
      required: json['required'] as bool? ?? true,
      label: json['label'] as String?,
      defaultValue: json['default_value'] as String?,
      options:
          (json['options'] as List<dynamic>?)?.map((o) => o as String).toList(),
    );
  }
  /// Creates a [TemplateField].
  const TemplateField({
    required this.id,
    required this.type,
    required this.roleId,
    required this.page,
    required this.x,
    required this.y,
    this.width = 120,
    this.height = 40,
    this.required = true,
    this.label,
    this.defaultValue,
    this.options,
  });

  /// Unique identifier within the template.
  final String id;

  /// Type of field.
  final FieldType type;

  /// The role this field belongs to (maps to [TemplateRole.roleId]).
  final String roleId;

  /// Zero-based page number.
  final int page;

  /// X coordinate in points.
  final double x;

  /// Y coordinate in points.
  final double y;

  /// Field width.
  final double width;

  /// Field height.
  final double height;

  /// Whether the field is required.
  final bool required;

  /// Optional label.
  final String? label;

  /// Default value.
  final String? defaultValue;

  /// Options for dropdown/radio.
  final List<String>? options;

  /// Serializes to JSON.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'id': id,
      'type': type.name,
      'role_id': roleId,
      'page': page,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'required': required,
    };
    if (label != null) json['label'] = label;
    if (defaultValue != null) json['default_value'] = defaultValue;
    if (options != null) json['options'] = options;
    return json;
  }
}

// =============================================================================
// EnvelopeTemplate - The main template
// =============================================================================

/// A reusable envelope template.
class EnvelopeTemplate {

  /// Decodes a template from JSON bytes.
  factory EnvelopeTemplate.decode(Uint8List data) {
    return EnvelopeTemplate.fromJson(
      jsonDecode(utf8.decode(data)) as Map<String, dynamic>,
    );
  }

  /// Deserializes from JSON.
  factory EnvelopeTemplate.fromJson(Map<String, dynamic> json) {
    return EnvelopeTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      subject: json['subject'] as String,
      message: json['message'] as String?,
      routingMode: RoutingMode.values.firstWhere(
        (r) => r.name == (json['routing_mode'] ?? 'sequential'),
      ),
      roles: (json['roles'] as List<dynamic>)
          .map((r) => TemplateRole.fromJson(r as Map<String, dynamic>))
          .toList(),
      fields: (json['fields'] as List<dynamic>)
          .map((f) => TemplateField.fromJson(f as Map<String, dynamic>))
          .toList(),
      createdAt: json['created_at'] as int?,
      updatedAt: json['updated_at'] as int?,
      author: json['author'] as String?,
      tags:
          (json['tags'] as List<dynamic>?)?.map((t) => t as String).toList() ??
              <String>[],
      expirationDays: json['expiration_days'] as int?,
      remindersEnabled: json['reminders_enabled'] as bool? ?? false,
      reminderIntervalDays: json['reminder_interval_days'] as int? ?? 3,
      reminderMaxCount: json['reminder_max_count'] as int? ?? 3,
    );
  }
  /// Creates a new [EnvelopeTemplate].
  const EnvelopeTemplate({
    required this.id,
    required this.name,
    required this.subject,
    required this.roles,
    required this.fields,
    this.description,
    this.message,
    this.routingMode = RoutingMode.sequential,
    this.createdAt,
    this.updatedAt,
    this.author,
    this.tags = const <String>[],
    this.expirationDays,
    this.remindersEnabled = false,
    this.reminderIntervalDays = 3,
    this.reminderMaxCount = 3,
  });

  /// Unique template identifier.
  final String id;

  /// Template name.
  final String name;

  /// Template description.
  final String? description;

  /// Default envelope subject.
  final String subject;

  /// Default envelope message.
  final String? message;

  /// Routing mode.
  final RoutingMode routingMode;

  /// List of roles that must be filled when instantiating.
  final List<TemplateRole> roles;

  /// List of field placeholders.
  final List<TemplateField> fields;

  /// Creation timestamp.
  final int? createdAt;

  /// Last update timestamp.
  final int? updatedAt;

  /// Template author.
  final String? author;

  /// Tags for organizing templates.
  final List<String> tags;

  /// Default number of days before expiration (null = no expiration).
  final int? expirationDays;

  /// Whether reminders are enabled by default.
  final bool remindersEnabled;

  /// Default reminder interval.
  final int reminderIntervalDays;

  /// Default reminder count.
  final int reminderMaxCount;

  /// Instantiates this template into a concrete [Envelope].
  ///
  /// [roleMapping] maps each role ID to a concrete recipient (with name,
  /// email, and optional overrides).
  ///
  /// Throws [ArgumentError] if any role in the template is not mapped.
  Envelope instantiate({
    required String envelopeId,
    required Map<String, TemplateRoleMapping> roleMapping,
    required List<String> documentMerkleRoots,
    String? subject,
    String? message,
    String? senderName,
    String? senderEmail,
  }) {
    // Validate all roles are mapped.
    for (final role in roles) {
      if (!roleMapping.containsKey(role.roleId)) {
        throw ArgumentError(
          'Role "${role.roleId}" (${role.roleName}) is not mapped',
        );
      }
    }

    // Create recipients from mapped roles.
    final recipients = <EnvelopeRecipient>[];
    final roleIdToRecipientId = <String, String>{};

    for (final role in roles) {
      final mapping = roleMapping[role.roleId]!;
      final recipientId = mapping.recipientId ?? 'rcpt-${role.roleId}';
      roleIdToRecipientId[role.roleId] = recipientId;

      recipients.add(
        EnvelopeRecipient(
          id: recipientId,
          name: mapping.name,
          email: mapping.email,
          role: role.recipientRole,
          routingOrder: role.routingOrder,
          authentication: mapping.authentication ?? role.defaultAuthentication,
          accessCode: mapping.accessCode,
          phoneNumber: mapping.phoneNumber,
          company: mapping.company,
          title: mapping.title,
          note: mapping.note ?? role.defaultNote,
        ),
      );
    }

    // Remap field role IDs to actual recipient IDs.
    final envelopeFields = fields.map((tf) {
      final recipientId = roleIdToRecipientId[tf.roleId]!;
      return SignatureField(
        id: tf.id,
        type: tf.type,
        recipientId: recipientId,
        page: tf.page,
        x: tf.x,
        y: tf.y,
        width: tf.width,
        height: tf.height,
        required: tf.required,
        label: tf.label,
        defaultValue: tf.defaultValue,
        options: tf.options,
      );
    }).toList();

    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final expiresAt =
        expirationDays != null ? now + (expirationDays! * 24 * 3600) : null;

    return Envelope(
      id: envelopeId,
      subject: subject ?? this.subject,
      message: message ?? this.message,
      routingMode: routingMode,
      documentMerkleRoots: documentMerkleRoots,
      recipients: recipients,
      fields: envelopeFields,
      createdAt: now,
      expiresAt: expiresAt,
      senderName: senderName,
      senderEmail: senderEmail,
      remindersEnabled: remindersEnabled,
      reminderIntervalDays: reminderIntervalDays,
      reminderMaxCount: reminderMaxCount,
    );
  }

  /// Encodes this template to JSON bytes.
  Uint8List encode() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = <String, dynamic>{
      'block_type': 'envelope_template',
      'id': id,
      'name': name,
      'subject': subject,
      'routing_mode': routingMode.name,
      'roles': roles.map((r) => r.toJson()).toList(),
      'fields': fields.map((f) => f.toJson()).toList(),
      'tags': tags,
      'reminders_enabled': remindersEnabled,
      'reminder_interval_days': reminderIntervalDays,
      'reminder_max_count': reminderMaxCount,
    };
    if (description != null) json['description'] = description;
    if (message != null) json['message'] = message;
    if (createdAt != null) json['created_at'] = createdAt;
    if (updatedAt != null) json['updated_at'] = updatedAt;
    if (author != null) json['author'] = author;
    if (expirationDays != null) json['expiration_days'] = expirationDays;
    return json;
  }
}

// =============================================================================
// TemplateRoleMapping - Concrete data to fill a template role
// =============================================================================

/// Concrete recipient data used when instantiating a template role.
class TemplateRoleMapping {
  /// Creates a [TemplateRoleMapping].
  const TemplateRoleMapping({
    required this.name,
    required this.email,
    this.recipientId,
    this.authentication,
    this.accessCode,
    this.phoneNumber,
    this.company,
    this.title,
    this.note,
  });

  /// Concrete recipient ID (auto-generated if null).
  final String? recipientId;

  /// Name of the actual recipient.
  final String name;

  /// Email of the actual recipient.
  final String email;

  /// Override authentication method (uses role default if null).
  final AuthenticationMethod? authentication;

  /// Access code (if using access code authentication).
  final String? accessCode;

  /// Phone number (if using SMS/phone authentication).
  final String? phoneNumber;

  /// Company name.
  final String? company;

  /// Job title.
  final String? title;

  /// Override personal note.
  final String? note;
}
