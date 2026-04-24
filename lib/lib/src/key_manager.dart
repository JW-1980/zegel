import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'secure_memory.dart';

/// Centralized CRUD manager for user keys (improvement #91).
///
/// A lightweight on-disk registry that tracks named keys, their
/// fingerprints, creation timestamps, and optional expiration. The
/// manager deliberately never stores raw key bytes — callers feed raw
/// bytes only at create time, and the manager keeps a SHA-256
/// fingerprint plus any metadata the user wants for their own UI.
///
/// This keeps the core library agnostic to secret storage: a GUI might
/// put the actual keys in a system keychain, while a CLI might store
/// them in a file. The manager only coordinates the metadata.
class KeyManager {
  KeyManager._(this._entries);

  factory KeyManager.empty() => KeyManager._(<String, KeyEntry>{});

  /// Loads a manager from a JSON file. Returns an empty manager when
  /// the file does not yet exist.
  factory KeyManager.load(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) return KeyManager.empty();
    final raw = file.readAsStringSync();
    if (raw.trim().isEmpty) return KeyManager.empty();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final entries = <String, KeyEntry>{};
    for (final entry in (json['keys'] as List<dynamic>? ?? const <dynamic>[])) {
      final e = KeyEntry.fromJson(entry as Map<String, dynamic>);
      entries[e.id] = e;
    }
    return KeyManager._(entries);
  }

  final Map<String, KeyEntry> _entries;

  /// Creates a new entry from raw [keyBytes]. The bytes are fingerprinted
  /// and wiped from the caller's buffer, so the manager never retains
  /// them. [keyBytes] must be exactly 32 bytes.
  KeyEntry create({
    required String name,
    required Uint8List keyBytes,
    DateTime? createdAt,
    DateTime? expiresAt,
    String? description,
  }) {
    if (keyBytes.length != 32) {
      throw ArgumentError.value(
        keyBytes.length,
        'keyBytes.length',
        'must be exactly 32',
      );
    }
    final fingerprint = sha256.convert(keyBytes).toString();
    SecureMemory.wipe(keyBytes);
    final id = _nextId();
    final entry = KeyEntry(
      id: id,
      name: name,
      fingerprint: fingerprint,
      createdAt: (createdAt ?? DateTime.now().toUtc()).toUtc(),
      expiresAt: expiresAt?.toUtc(),
      description: description,
    );
    _entries[id] = entry;
    return entry;
  }

  /// Reads an entry by id.
  KeyEntry? read(String id) => _entries[id];

  /// Looks up an entry by its fingerprint.
  KeyEntry? findByFingerprint(String fingerprint) {
    for (final entry in _entries.values) {
      if (entry.fingerprint == fingerprint) return entry;
    }
    return null;
  }

  /// Updates the mutable fields of an existing entry. Returns the new
  /// entry, or null if the id was not found.
  KeyEntry? update(
    String id, {
    String? name,
    DateTime? expiresAt,
    String? description,
  }) {
    final existing = _entries[id];
    if (existing == null) return null;
    final updated = existing.copyWith(
      name: name,
      expiresAt: expiresAt,
      description: description,
    );
    _entries[id] = updated;
    return updated;
  }

  /// Deletes the entry with [id]. Returns true if one existed.
  bool delete(String id) => _entries.remove(id) != null;

  /// Lists every entry, optionally filtering out the expired ones.
  List<KeyEntry> list({bool includeExpired = true, DateTime? now}) {
    final cutoff = (now ?? DateTime.now().toUtc()).toUtc();
    final out = _entries.values.toList();
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (includeExpired) return out;
    return out.where((e) {
      final expires = e.expiresAt;
      return expires == null || expires.isAfter(cutoff);
    }).toList();
  }

  /// Serializes the manager to JSON.
  String encode() => jsonEncode(<String, dynamic>{
        'keys': _entries.values.map((e) => e.toJson()).toList(),
      });

  /// Writes the serialized state to disk.
  ///
  /// The write is atomic (temp file + rename) and, on POSIX platforms, the
  /// destination is chmod'd to `0600` so the fingerprint registry cannot be
  /// enumerated by other local users.
  void save(String filePath) {
    final file = File(filePath);
    file.parent.createSync(recursive: true);

    final tmp = File('$filePath.tmp');
    final raf = tmp.openSync(mode: FileMode.write);
    try {
      raf.writeStringSync(encode());
      raf.flushSync();
    } finally {
      raf.closeSync();
    }
    tmp.renameSync(filePath);

    if (!Platform.isWindows) {
      try {
        Process.runSync('chmod', <String>['600', filePath]);
      } catch (_) {
        // Best effort.
      }
    }
  }

  String _nextId() {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    return 'key_${now.toRadixString(36)}';
  }
}

class KeyEntry {
  const KeyEntry({
    required this.id,
    required this.name,
    required this.fingerprint,
    required this.createdAt,
    this.expiresAt,
    this.description,
  });

  static KeyEntry fromJson(Map<String, dynamic> json) => KeyEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        fingerprint: json['fingerprint'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        expiresAt: json['expires_at'] == null
            ? null
            : DateTime.parse(json['expires_at'] as String).toUtc(),
        description: json['description'] as String?,
      );

  final String id;
  final String name;
  final String fingerprint;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final String? description;

  KeyEntry copyWith({String? name, DateTime? expiresAt, String? description}) {
    return KeyEntry(
      id: id,
      name: name ?? this.name,
      fingerprint: fingerprint,
      createdAt: createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'fingerprint': fingerprint,
        'created_at': createdAt.toUtc().toIso8601String(),
        if (expiresAt != null)
          'expires_at': expiresAt!.toUtc().toIso8601String(),
        if (description != null) 'description': description,
      };
}
