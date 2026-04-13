import 'dart:convert';
import 'dart:io';

/// Contact book for frequent signers and collaborators (improvement #93).
///
/// Stores metadata about people you repeatedly co-sign or send envelopes
/// to: their display name, email, public key fingerprint, organization,
/// and optional notes. Entries can be marked as "trusted" to signal they
/// were verified in person / via a secondary channel.
///
/// This is an operational convenience feature, not a cryptographic trust
/// store: trust decisions still live inside the envelope / attestation
/// verification flow.
class ContactBook {
  ContactBook() : _byId = {};

  final Map<String, Contact> _byId;

  /// Adds or replaces [contact] and returns it.
  Contact upsert(Contact contact) {
    _byId[contact.id] = contact;
    return contact;
  }

  /// Looks up a contact by id.
  Contact? get(String id) => _byId[id];

  /// Removes the contact with [id]. Returns `true` if one existed.
  bool remove(String id) => _byId.remove(id) != null;

  /// Marks a contact as trusted. Throws [StateError] if the contact is
  /// missing.
  Contact markTrusted(String id, {bool trusted = true}) {
    final existing = _byId[id];
    if (existing == null) {
      throw StateError('No contact with id "$id"');
    }
    final updated = existing.copyWith(trusted: trusted);
    _byId[id] = updated;
    return updated;
  }

  /// Returns all contacts, sorted by display name (case-insensitive).
  List<Contact> list() {
    final all = _byId.values.toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ));
    return all;
  }

  /// Returns only trusted contacts.
  List<Contact> trusted() => list().where((c) => c.trusted).toList();

  /// Substring search over display name, email and organization.
  List<Contact> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return list();
    return list().where((c) {
      return c.displayName.toLowerCase().contains(q) ||
          (c.email?.toLowerCase().contains(q) ?? false) ||
          (c.organization?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  int get length => _byId.length;

  Map<String, dynamic> toJson() => {
        'contacts': _byId.values.map((c) => c.toJson()).toList(),
      };

  String encode() => jsonEncode(toJson());

  static ContactBook decodeJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final book = ContactBook();
    for (final entry in (m['contacts'] as List<dynamic>? ?? const <dynamic>[])) {
      final contact = Contact.fromJson(entry as Map<String, dynamic>);
      book._byId[contact.id] = contact;
    }
    return book;
  }

  void saveFile(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encode());
  }

  static ContactBook loadFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return ContactBook();
    return decodeJson(file.readAsStringSync());
  }
}

class Contact {
  const Contact({
    required this.id,
    required this.displayName,
    required this.addedAt,
    this.email,
    this.organization,
    this.publicKeyFingerprint,
    this.trusted = false,
    this.notes,
  });

  static Contact fromJson(Map<String, dynamic> json) => Contact(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        addedAt: DateTime.parse(json['added_at'] as String).toUtc(),
        email: json['email'] as String?,
        organization: json['organization'] as String?,
        publicKeyFingerprint: json['public_key_fingerprint'] as String?,
        trusted: json['trusted'] as bool? ?? false,
        notes: json['notes'] as String?,
      );

  final String id;
  final String displayName;
  final String? email;
  final String? organization;
  final String? publicKeyFingerprint;
  final bool trusted;
  final String? notes;
  final DateTime addedAt;

  Contact copyWith({
    String? displayName,
    String? email,
    String? organization,
    String? publicKeyFingerprint,
    bool? trusted,
    String? notes,
  }) {
    return Contact(
      id: id,
      displayName: displayName ?? this.displayName,
      addedAt: addedAt,
      email: email ?? this.email,
      organization: organization ?? this.organization,
      publicKeyFingerprint: publicKeyFingerprint ?? this.publicKeyFingerprint,
      trusted: trusted ?? this.trusted,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        if (email != null) 'email': email,
        if (organization != null) 'organization': organization,
        if (publicKeyFingerprint != null)
          'public_key_fingerprint': publicKeyFingerprint,
        'trusted': trusted,
        if (notes != null) 'notes': notes,
        'added_at': addedAt.toUtc().toIso8601String(),
      };
}
