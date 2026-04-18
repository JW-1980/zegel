import 'dart:io';
import 'dart:convert';

/// Service for managing a local contact book of frequent signers.
///
/// Stores contacts as a JSON file in the user's home directory.
/// Used by the envelope screen and attestation screen to quickly
/// select recipients without re-typing their details.
///
/// Implements item 97 from SUGGESTED_IMPROVEMENTS.md:
/// "Add a Contact Book for managing frequent signers' IDs."
class ContactService {
  static const _fileName = '.zegel_contacts.json';

  /// Returns the path to the contacts file.
  String get _filePath {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return '$home/$_fileName';
  }

  /// Loads all contacts from disk.
  Future<List<SignerContact>> loadContacts() async {
    final file = File(_filePath);
    if (!await file.exists()) {
      return <SignerContact>[];
    }

    try {
      final json = jsonDecode(await file.readAsString());
      final list = json['contacts'] as List<dynamic>;
      return list
          .map((c) => SignerContact.fromJson(c as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (_) {
      return <SignerContact>[];
    }
  }

  /// Saves the contact list to disk.
  Future<void> saveContacts(List<SignerContact> contacts) async {
    final json = {
      'version': 1,
      'contacts': contacts.map((c) => c.toJson()).toList(),
    };
    await File(
      _filePath,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }

  /// Adds a new contact. Returns the updated list.
  Future<List<SignerContact>> addContact(SignerContact contact) async {
    final contacts = await loadContacts();
    contacts.add(contact);
    await saveContacts(contacts);
    return contacts;
  }

  /// Removes a contact by email. Returns the updated list.
  Future<List<SignerContact>> removeContact(String email) async {
    final contacts = await loadContacts();
    contacts.removeWhere((c) => c.email == email);
    await saveContacts(contacts);
    return contacts;
  }

  /// Updates an existing contact (matched by email).
  Future<List<SignerContact>> updateContact(SignerContact updated) async {
    final contacts = await loadContacts();
    final index = contacts.indexWhere((c) => c.email == updated.email);
    if (index >= 0) {
      contacts[index] = updated;
    } else {
      contacts.add(updated);
    }
    await saveContacts(contacts);
    return contacts;
  }

  /// Searches contacts by name or email.
  Future<List<SignerContact>> search(String query) async {
    final contacts = await loadContacts();
    final q = query.toLowerCase();
    return contacts.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.email.toLowerCase().contains(q) ||
          (c.company?.toLowerCase().contains(q) ?? false);
    }).toList();
  }
}

/// A signer contact entry.
class SignerContact {
  final String name;
  final String email;
  final String? company;
  final String? title;
  final String? phone;
  final String? role;
  final String? notes;
  final int? addedAt;

  const SignerContact({
    required this.name,
    required this.email,
    this.company,
    this.title,
    this.phone,
    this.role,
    this.notes,
    this.addedAt,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'name': name, 'email': email};
    if (company != null) json['company'] = company;
    if (title != null) json['title'] = title;
    if (phone != null) json['phone'] = phone;
    if (role != null) json['role'] = role;
    if (notes != null) json['notes'] = notes;
    if (addedAt != null) json['added_at'] = addedAt;
    return json;
  }

  factory SignerContact.fromJson(Map<String, dynamic> json) {
    return SignerContact(
      name: json['name'] as String,
      email: json['email'] as String,
      company: json['company'] as String?,
      title: json['title'] as String?,
      phone: json['phone'] as String?,
      role: json['role'] as String?,
      notes: json['notes'] as String?,
      addedAt: json['added_at'] as int?,
    );
  }
}
