import 'dart:convert';
import 'dart:io';

/// Persistent user preferences store (improvement #17).
///
/// A minimal, dependency-free key/value store backed by a single JSON file.
/// Suitable for the Dart library and CLI — the Flutter app can layer
/// SharedPreferences on top of the same abstraction if desired.
///
/// All values are serialized as JSON, so the permitted value types are the
/// ones supported by `jsonEncode`: `String`, `num`, `bool`, `null`, `List`,
/// and `Map<String, dynamic>`.
///
/// ## Usage
///
/// ```dart
/// final prefs = ZegelPreferences.load('/tmp/prefs.json');
/// prefs.setString('default_classification', 'CONFIDENTIAL');
/// prefs.setInt('block_size', 65536);
/// prefs.save();
/// ```
class ZegelPreferences {
  ZegelPreferences._(this.path, this._values);

  /// Creates an empty, in-memory preferences instance.
  factory ZegelPreferences.empty() => ZegelPreferences._(null, {});

  /// Loads preferences from a JSON file. If the file does not exist,
  /// returns an empty instance that will write to [filePath] on [save].
  factory ZegelPreferences.load(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      return ZegelPreferences._(filePath, {});
    }
    final raw = file.readAsStringSync();
    if (raw.trim().isEmpty) {
      return ZegelPreferences._(filePath, {});
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
          'Preferences file must contain a JSON object');
    }
    return ZegelPreferences._(filePath, Map<String, dynamic>.from(decoded));
  }

  /// The backing file on disk. `null` means in-memory only.
  final String? path;

  final Map<String, dynamic> _values;

  /// Returns true if a value is stored for [key].
  bool contains(String key) => _values.containsKey(key);

  /// Returns all keys currently stored.
  Iterable<String> get keys => _values.keys;

  /// Deletes a stored value.
  void remove(String key) => _values.remove(key);

  /// Clears all stored values.
  void clear() => _values.clear();

  // --- Typed accessors -------------------------------------------------------

  String? getString(String key, {String? defaultValue}) {
    final v = _values[key];
    if (v is String) return v;
    return defaultValue;
  }

  void setString(String key, String value) => _values[key] = value;

  int? getInt(String key, {int? defaultValue}) {
    final v = _values[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return defaultValue;
  }

  void setInt(String key, int value) => _values[key] = value;

  double? getDouble(String key, {double? defaultValue}) {
    final v = _values[key];
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return defaultValue;
  }

  void setDouble(String key, double value) => _values[key] = value;

  bool? getBool(String key, {bool? defaultValue}) {
    final v = _values[key];
    if (v is bool) return v;
    return defaultValue;
  }

  void setBool(String key, bool value) => _values[key] = value;

  List<dynamic>? getList(String key) {
    final v = _values[key];
    if (v is List<dynamic>) return List<dynamic>.from(v);
    return null;
  }

  void setList(String key, List<dynamic> value) => _values[key] = value;

  Map<String, dynamic>? getMap(String key) {
    final v = _values[key];
    if (v is Map<String, dynamic>) return Map<String, dynamic>.from(v);
    return null;
  }

  void setMap(String key, Map<String, dynamic> value) => _values[key] = value;

  // --- Serialization ---------------------------------------------------------

  /// Encodes all preferences as a JSON string.
  String encode() => jsonEncode(_values);

  /// Persists the current state to the backing file. If no file path was
  /// provided, this throws a [StateError].
  ///
  /// The write is performed atomically: contents are first written to a
  /// sibling temp file, fsynced, and then renamed over the destination so a
  /// crash mid-write cannot corrupt the existing file. On POSIX systems the
  /// file is also chmod'd to `0600` so user preferences (which may include
  /// key fingerprints or classification defaults) cannot be read by other
  /// local users.
  void save() {
    final target = path;
    if (target == null) {
      throw StateError('Cannot save an in-memory ZegelPreferences instance');
    }
    final file = File(target);
    file.parent.createSync(recursive: true);

    final tmp = File('$target.tmp');
    final raf = tmp.openSync(mode: FileMode.write);
    try {
      raf.writeStringSync(encode());
      raf.flushSync();
    } finally {
      raf.closeSync();
    }
    // Rename is atomic on POSIX and Windows.
    tmp.renameSync(target);

    // Restrict permissions on POSIX. No-op on Windows.
    if (!Platform.isWindows) {
      try {
        Process.runSync('chmod', <String>['600', target]);
      } catch (_) {
        // Best effort: ignore if chmod is unavailable.
      }
    }
  }

  /// Returns an unmodifiable snapshot of the raw underlying map.
  Map<String, dynamic> snapshot() => Map<String, dynamic>.unmodifiable(_values);
}
