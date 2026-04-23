import 'dart:convert';
import 'dart:io';

/// Auto-rotation reminders for long-lived master keys (improvement #28).
///
/// Tracks the creation time (and optional last-rotation time) of named keys
/// and classifies them as OK / DUE / OVERDUE relative to a configurable
/// rotation window. Intended for operational hygiene: a GUI or CLI wrapper
/// calls [summarize] to show which keys should be rotated, without the
/// library ever holding the secret material itself.
class KeyRotationReminder {
  KeyRotationReminder({
    this.rotationWindow = const Duration(days: 90),
    Map<String, KeyRotationRecord>? initial,
  }) : _records = Map<String, KeyRotationRecord>.of(
         initial ?? const <String, KeyRotationRecord>{},
       );

  /// Default rotation window (90 days).
  static const Duration defaultRotationWindow = Duration(days: 90);

  final Duration rotationWindow;

  /// key name -> record. Kept in memory; persist with [encode]/[decodeJson].
  final Map<String, KeyRotationRecord> _records;

  /// Registers a key as created at [createdAt] (defaults to now).
  void registerKey(String name, {DateTime? createdAt}) {
    final ts = (createdAt ?? DateTime.now().toUtc()).toUtc();
    _records[name] = KeyRotationRecord(
      name: name,
      createdAt: ts,
      lastRotatedAt: ts,
    );
  }

  /// Marks [name] as rotated at [rotatedAt] (defaults to now).
  void markRotated(String name, {DateTime? rotatedAt}) {
    final existing = _records[name];
    final ts = (rotatedAt ?? DateTime.now().toUtc()).toUtc();
    _records[name] = KeyRotationRecord(
      name: name,
      createdAt: existing?.createdAt ?? ts,
      lastRotatedAt: ts,
    );
  }

  /// Removes a key from tracking.
  void forget(String name) => _records.remove(name);

  /// Returns the current status (OK/DUE/OVERDUE) for a single key.
  RotationStatus statusOf(String name, {DateTime? now}) {
    final record = _records[name];
    if (record == null) return RotationStatus.unknown;
    final cutoff = (now ?? DateTime.now().toUtc()).toUtc();
    final age = cutoff.difference(record.lastRotatedAt);
    if (age >= rotationWindow * 1.2) return RotationStatus.overdue;
    if (age >= rotationWindow) return RotationStatus.due;
    return RotationStatus.ok;
  }

  /// Returns a per-key summary, useful for dashboards.
  List<KeyRotationSummary> summarize({DateTime? now}) {
    final cutoff = (now ?? DateTime.now().toUtc()).toUtc();
    return _records.values
        .map(
          (r) => KeyRotationSummary(
            record: r,
            ageAtEvaluation: cutoff.difference(r.lastRotatedAt),
            status: statusOf(r.name, now: cutoff),
          ),
        )
        .toList()
      ..sort((a, b) => b.ageAtEvaluation.compareTo(a.ageAtEvaluation));
  }

  Iterable<KeyRotationRecord> get records => _records.values;

  /// Serializes the tracker to JSON.
  String encode() => jsonEncode({
    'rotation_window_days': rotationWindow.inDays,
    'records': _records.values.map((r) => r.toJson()).toList(),
  });

  /// Decodes a tracker previously serialized by [encode].
  static KeyRotationReminder decodeJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final window = Duration(
      days: (m['rotation_window_days'] as num?)?.toInt() ?? 90,
    );
    final records = <String, KeyRotationRecord>{};
    for (final entry in (m['records'] as List<dynamic>? ?? const <dynamic>[])) {
      final record = KeyRotationRecord.fromJson(entry as Map<String, dynamic>);
      records[record.name] = record;
    }
    return KeyRotationReminder(rotationWindow: window, initial: records);
  }

  /// Convenience: load a tracker from a file. Returns an empty tracker if
  /// the file does not yet exist.
  static KeyRotationReminder loadFile(
    String path, {
    Duration rotationWindow = defaultRotationWindow,
  }) {
    final file = File(path);
    if (!file.existsSync()) {
      return KeyRotationReminder(rotationWindow: rotationWindow);
    }
    return decodeJson(file.readAsStringSync());
  }

  /// Convenience: save to a file.
  void saveFile(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encode());
  }
}

class KeyRotationRecord {
  const KeyRotationRecord({
    required this.name,
    required this.createdAt,
    required this.lastRotatedAt,
  });

  static KeyRotationRecord fromJson(Map<String, dynamic> json) =>
      KeyRotationRecord(
        name: json['name'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        lastRotatedAt: DateTime.parse(
          json['last_rotated_at'] as String,
        ).toUtc(),
      );

  final String name;
  final DateTime createdAt;
  final DateTime lastRotatedAt;

  Map<String, dynamic> toJson() => {
    'name': name,
    'created_at': createdAt.toUtc().toIso8601String(),
    'last_rotated_at': lastRotatedAt.toUtc().toIso8601String(),
  };
}

enum RotationStatus { unknown, ok, due, overdue }

class KeyRotationSummary {
  const KeyRotationSummary({
    required this.record,
    required this.ageAtEvaluation,
    required this.status,
  });

  final KeyRotationRecord record;
  final Duration ageAtEvaluation;
  final RotationStatus status;
}
