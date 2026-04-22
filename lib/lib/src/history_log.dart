import 'dart:convert';
import 'dart:io';

import 'retention_policy.dart';

/// Timestamped history log for verification operations (improvement #83).
///
/// A lightweight append-only log that records every verify/seal/extract
/// operation with the user-facing outcome (success/failure). It is stored
/// as newline-delimited JSON so it can be tail-read, grep-filtered, and
/// streamed over stdin/stdout without a parser.
///
/// The log integrates with [RetentionPolicy] via [prune] so periodic
/// cleanups can cap the file size without losing cryptographic history.
class HistoryLog {
  final List<HistoryEntry> _entries = [];

  /// Records a single operation. Returns the entry that was appended.
  HistoryEntry record({
    required String operation,
    required bool success,
    String? filename,
    String? message,
    Duration? duration,
    Map<String, dynamic>? details,
    DateTime? at,
  }) {
    final entry = HistoryEntry(
      operation: operation,
      success: success,
      filename: filename,
      message: message,
      duration: duration,
      details: details ?? const <String, dynamic>{},
      at: (at ?? DateTime.now().toUtc()).toUtc(),
    );
    _entries.add(entry);
    return entry;
  }

  /// Returns all entries, oldest first.
  List<HistoryEntry> get entries => List<HistoryEntry>.unmodifiable(_entries);

  /// Returns the last [limit] entries, newest first.
  List<HistoryEntry> tail({int limit = 20}) {
    final start = (_entries.length - limit).clamp(0, _entries.length);
    return _entries.sublist(start).reversed.toList();
  }

  /// Filters entries by operation name.
  List<HistoryEntry> byOperation(String operation) =>
      _entries.where((e) => e.operation == operation).toList();

  /// Filters entries by success status.
  List<HistoryEntry> byStatus({required bool success}) =>
      _entries.where((e) => e.success == success).toList();

  /// Returns filtered entries falling inside `[from, to]` inclusive.
  List<HistoryEntry> inRange(DateTime from, DateTime to) {
    final f = from.toUtc();
    final t = to.toUtc();
    return _entries
        .where((e) => !e.at.isBefore(f) && !e.at.isAfter(t))
        .toList();
  }

  /// Removes all entries that the [policy] marks expired. Returns the
  /// number of entries pruned.
  int prune(RetentionPolicy policy, {DateTime? now}) {
    final before = _entries.length;
    final kept = policy.apply(_entries, now: now);
    _entries
      ..clear()
      ..addAll(kept);
    return before - _entries.length;
  }

  /// Serializes the log as newline-delimited JSON.
  String encode() => _entries.map((e) => jsonEncode(e.toJson())).join('\n');

  /// Loads a previously saved log from a newline-delimited JSON string.
  static HistoryLog decode(String raw) {
    final log = HistoryLog();
    for (final line in raw.split('\n')) {
      if (line.trim().isEmpty) continue;
      log._entries.add(
        HistoryEntry.fromJson(jsonDecode(line) as Map<String, dynamic>),
      );
    }
    return log;
  }

  void saveFile(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encode());
  }

  static HistoryLog loadFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return HistoryLog();
    return decode(file.readAsStringSync());
  }
}

class HistoryEntry extends RetainableEvent {
  HistoryEntry({
    required this.operation,
    required this.success,
    this.filename,
    this.message,
    this.duration,
    required this.details,
    required this.at,
  });

  static HistoryEntry fromJson(Map<String, dynamic> json) => HistoryEntry(
    operation: json['operation'] as String,
    success: json['success'] as bool,
    filename: json['filename'] as String?,
    message: json['message'] as String?,
    duration: json['duration_ms'] == null
        ? null
        : Duration(milliseconds: (json['duration_ms'] as num).toInt()),
    details: json['details'] == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(json['details'] as Map<String, dynamic>),
    at: DateTime.parse(json['at'] as String).toUtc(),
  );

  final String operation;
  final bool success;
  final String? filename;
  final String? message;
  final Duration? duration;
  final Map<String, dynamic> details;
  final DateTime at;

  @override
  DateTime get timestamp => at;

  @override
  String get category => operation;

  Map<String, dynamic> toJson() => {
    'operation': operation,
    'success': success,
    if (filename != null) 'filename': filename,
    if (message != null) 'message': message,
    if (duration != null) 'duration_ms': duration!.inMilliseconds,
    'details': details,
    'at': at.toUtc().toIso8601String(),
  };
}
