import 'history_log.dart';

/// CSV report exporter (improvement #84).
///
/// Produces monthly usage-metrics exports as CSV strings that can be saved
/// to a file, emailed, or uploaded to a spreadsheet. Handles quoting,
/// escaping, and newline normalization.
class CsvReport {
  CsvReport._();

  /// Escapes a cell value for inclusion in a CSV row: fields that contain
  /// commas, quotes, or newlines are wrapped in double quotes with inner
  /// double quotes doubled.
  static String escape(Object? cell) {
    final value = cell?.toString() ?? '';
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      final escaped = value.replaceAll('"', '""');
      return '"$escaped"';
    }
    return value;
  }

  /// Builds a CSV document from a [header] row and a list of value rows.
  static String buildCsv(List<String> header, List<List<Object?>> rows) {
    final sb = StringBuffer();
    sb.writeln(header.map(escape).join(','));
    for (final row in rows) {
      sb.writeln(row.map(escape).join(','));
    }
    return sb.toString();
  }

  /// Produces a report of [HistoryLog] entries aggregated by day.
  static String dailySummary(HistoryLog log) {
    final byDay = <String, _DayBucket>{};
    for (final entry in log.entries) {
      final date = entry.at.toIso8601String().substring(0, 10);
      final bucket = byDay.putIfAbsent(date, _DayBucket.new);
      bucket.total += 1;
      if (entry.success) {
        bucket.successes += 1;
      } else {
        bucket.failures += 1;
      }
      if (entry.duration != null) {
        bucket.totalDurationMs += entry.duration!.inMilliseconds;
        bucket.timed += 1;
      }
    }
    final sortedDays = byDay.keys.toList()..sort();
    return buildCsv(
      ['date', 'total', 'successes', 'failures', 'avg_duration_ms'],
      [
        for (final day in sortedDays)
          [
            day,
            byDay[day]!.total,
            byDay[day]!.successes,
            byDay[day]!.failures,
            byDay[day]!.averageDurationMs.toStringAsFixed(2),
          ],
      ],
    );
  }

  /// Produces a report of entries aggregated by operation name.
  static String operationSummary(HistoryLog log) {
    final byOp = <String, _DayBucket>{};
    for (final entry in log.entries) {
      final bucket = byOp.putIfAbsent(entry.operation, _DayBucket.new);
      bucket.total += 1;
      if (entry.success) {
        bucket.successes += 1;
      } else {
        bucket.failures += 1;
      }
    }
    final ops = byOp.keys.toList()..sort();
    return buildCsv(
      ['operation', 'total', 'successes', 'failures', 'success_rate'],
      [
        for (final op in ops)
          [
            op,
            byOp[op]!.total,
            byOp[op]!.successes,
            byOp[op]!.failures,
            byOp[op]!.total == 0
                ? '0.00'
                : (byOp[op]!.successes / byOp[op]!.total).toStringAsFixed(2),
          ],
      ],
    );
  }
}

class _DayBucket {
  int total = 0;
  int successes = 0;
  int failures = 0;
  int totalDurationMs = 0;
  int timed = 0;

  double get averageDurationMs => timed == 0 ? 0 : totalDurationMs / timed;
}
