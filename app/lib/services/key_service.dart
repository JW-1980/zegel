import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for managing cryptographic keys using platform-native secure storage.
///
/// Uses flutter_secure_storage which maps to:
/// - Android: Android Keystore
/// - iOS/macOS: Keychain Services
/// - Windows: Windows Credential Manager
/// - Linux: libsecret (GNOME Keyring / KDE Wallet)
class KeyService {
  static const String _keyPrefix = 'zegel_key_';
  static const String _keyListKey = 'zegel_key_list';

  final FlutterSecureStorage _storage;

  KeyService()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        );

  /// Saves a key with the given name.
  ///
  /// [name] is a human-readable label for the key.
  /// [hexKey] is the 64-character hex-encoded 32-byte key.
  Future<void> saveKey(String name, String hexKey) async {
    await _storage.write(key: _keyPrefix + name, value: hexKey);
    final names = await listKeys();
    if (!names.contains(name)) {
      names.add(name);
      await _storage.write(
          key: _keyListKey, // ignore: deprecated_member_use
          // ignore: deprecated_member_use
          // ignore: deprecated_member_use
          value: names.join(','));
    }
  }

  /// Retrieves a key by name.
  ///
  /// Returns the 64-character hex string, or null if not found.
  Future<String?> getKey(String name) async {
    return _storage.read(key: _keyPrefix + name);
  }

  /// Returns a list of all saved key names.
  Future<List<String>> listKeys() async {
    final raw = await _storage.read(key: _keyListKey);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    return raw.split(',').where((s) => s.isNotEmpty).toList();
  }

  /// Deletes a key by name.
  Future<void> deleteKey(String name) async {
    await _storage.delete(key: _keyPrefix + name);
    final names = await listKeys();
    names.remove(name);
    await _storage.write(
        key: _keyListKey, // ignore: deprecated_member_use
        // ignore: deprecated_member_use
        // ignore: deprecated_member_use
        value: names.join(','));
  }

  /// Renames a key from [oldName] to [newName].
  Future<void> renameKey(String oldName, String newName) async {
    final hexKey = await getKey(oldName);
    if (hexKey != null) {
      await deleteKey(oldName);
      await saveKey(newName, hexKey);
    }
  }

  /// Generates a new random 32-byte key and returns it as a 64-character hex string.
  String generateKey([int lengthBits = 256]) {
    final random = Random.secure();
    final int numBytes = lengthBits ~/ 8;
    final bytes = List<int>.generate(numBytes, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Validates that a string is a valid 64-character hex key.
  bool isValidHexKey(String key) {
    if (key.length != 64) return false;
    return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key);
  }

  /// Converts a hex key string to bytes.
  List<int> hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  /// Converts bytes to a hex string.
  String bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
