import 'history_log.dart';

/// Log viewer formatting helpers (improvement #99).
///
/// Turns a [HistoryLog] into strings a GUI or CLI can display without
/// every call site having to reimplement timestamp and color logic.
/// Returns plain text plus "level" hints the UI can map to its own
/// styling.
class LogViewFormatter {
  LogViewFormatter._();

  /// Returns formatted lines for the log, newest first, limited to
  /// [limit] entries.
  static List<FormattedLogLine> format(
    HistoryLog log, {
    int limit = 100,
    bool includeDuration = true,
  }) {
    final entries = log.tail(limit: limit);
    return entries.map((entry) {
      return FormattedLogLine(
        timestamp: entry.at,
        level: entry.success ? LogLevel.info : LogLevel.error,
        operation: entry.operation,
        text: _buildText(entry, includeDuration: includeDuration),
      );
    }).toList();
  }

  /// Produces a compact single-line text representation for a single
  /// entry. Useful for shipping one line to stdout or a progress bar.
  static String formatEntry(HistoryEntry entry, {bool includeDuration = true}) {
    return _buildText(entry, includeDuration: includeDuration);
  }

  /// Emits a plain-text log dump that could be saved to disk. Newest
  /// entries at the bottom to match common logging conventions.
  static String dump(HistoryLog log) {
    final buf = StringBuffer();
    for (final entry in log.entries) {
      buf.writeln(
        '${entry.at.toUtc().toIso8601String()} '
                '[${entry.operation}] '
                '${entry.success ? "OK" : "FAIL"} '
                '${entry.filename ?? ""} '
                '${entry.message ?? ""}'
            .trim(),
      );
    }
    return buf.toString();
  }

  /// Filters a log using a simple `level` hint so the UI can offer a
  /// "show only failures" toggle.
  static List<HistoryEntry> filterByLevel(
    HistoryLog log, {
    required LogLevel level,
  }) {
    switch (level) {
      case LogLevel.info:
        return log.byStatus(success: true);
      case LogLevel.error:
        return log.byStatus(success: false);
    }
  }

  static String _buildText(
    HistoryEntry entry, {
    required bool includeDuration,
  }) {
    final parts = <String>[
      entry.at
          .toUtc()
          .toIso8601String()
          .replaceFirst('T', ' ')
          .substring(0, 19),
      '[${entry.operation}]',
      entry.success ? 'OK' : 'FAIL',
    ];
    if (entry.filename != null) parts.add(entry.filename!);
    if (entry.message != null) parts.add('- ${entry.message}');
    if (includeDuration && entry.duration != null) {
      parts.add('(${entry.duration!.inMilliseconds}ms)');
    }
    return parts.join(' ');
  }
}

class FormattedLogLine {
  const FormattedLogLine({
    required this.timestamp,
    required this.level,
    required this.operation,
    required this.text,
  });

  final DateTime timestamp;
  final LogLevel level;
  final String operation;
  final String text;
}

enum LogLevel { info, error }
