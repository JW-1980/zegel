import 'history_log.dart';
import 'usage_analytics.dart';

/// Text/Markdown summary report generator (improvement #24).
///
/// The original feature request calls for PDF summary reports after batch
/// verification, but PDF generation brings a heavy dependency into the
/// core library. Instead we emit well-structured Markdown — any downstream
/// tool (pandoc, a Flutter widget, a web page) can turn that into a PDF.
///
/// The generator accepts any combination of a [HistoryLog] and a
/// [UsageAnalytics] collector and produces a single string.
class ReportGenerator {
  ReportGenerator._();

  /// Builds a markdown-formatted batch verification summary from [log].
  /// Only entries where `operation == 'verify'` are considered.
  static String batchVerifyReport(
    HistoryLog log, {
    DateTime? from,
    DateTime? to,
    String title = 'Batch Verification Report',
  }) {
    final filtered = _filterVerifyEntries(log, from: from, to: to);
    final totalFiles = filtered.length;
    final successes = filtered.where((e) => e.success).length;
    final failures = totalFiles - successes;
    final durations = filtered
        .where((e) => e.duration != null)
        .map((e) => e.duration!.inMilliseconds)
        .toList();
    final averageMs = durations.isEmpty
        ? 0.0
        : durations.reduce((a, b) => a + b) / durations.length;

    final sb = StringBuffer()
      ..writeln('# $title')
      ..writeln()
      ..writeln('Generated: ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln()
      ..writeln('## Summary')
      ..writeln()
      ..writeln('| Metric | Value |')
      ..writeln('|--------|-------|')
      ..writeln('| Files processed | $totalFiles |')
      ..writeln('| Successes | $successes |')
      ..writeln('| Failures | $failures |')
      ..writeln(
        '| Success rate | ${totalFiles == 0 ? "0.00" : (successes / totalFiles * 100).toStringAsFixed(2)}% |',
      )
      ..writeln('| Avg duration | ${averageMs.toStringAsFixed(2)} ms |')
      ..writeln();

    if (failures > 0) {
      sb
        ..writeln('## Failures')
        ..writeln();
      for (final entry in filtered.where((e) => !e.success)) {
        sb.writeln(
          '- `${entry.filename ?? "(unknown)"}` — ${entry.message ?? "error"}',
        );
      }
      sb.writeln();
    }

    return sb.toString();
  }

  /// Builds a markdown-formatted usage report from [analytics].
  static String usageReport(
    UsageAnalytics analytics, {
    String title = 'Usage Report',
  }) {
    final sb = StringBuffer()
      ..writeln('# $title')
      ..writeln()
      ..writeln('Generated: ${DateTime.now().toUtc().toIso8601String()}')
      ..writeln()
      ..writeln('## Overview')
      ..writeln()
      ..writeln('| Metric | Value |')
      ..writeln('|--------|-------|')
      ..writeln('| Total files sealed | ${analytics.totalFilesSealed} |')
      ..writeln('| Total bytes sealed | ${analytics.totalBytesSealed} |')
      ..writeln(
        '| Average file size | ${analytics.averageFileSizeBytes.toStringAsFixed(2)} B |',
      )
      ..writeln();

    if (analytics.commandCounts.isNotEmpty) {
      sb
        ..writeln('## Top commands')
        ..writeln();
      for (final entry in analytics.topCommands()) {
        sb.writeln('- `${entry.key}` — ${entry.value} invocations');
      }
      sb.writeln();
    }

    if (analytics.algorithmCounts.isNotEmpty) {
      sb
        ..writeln('## Algorithm usage')
        ..writeln();
      for (final entry in analytics.topAlgorithms()) {
        sb.writeln('- `${entry.key}` — ${entry.value} uses');
      }
      sb.writeln();
    }

    return sb.toString();
  }

  static List<HistoryEntry> _filterVerifyEntries(
    HistoryLog log, {
    DateTime? from,
    DateTime? to,
  }) {
    final verify = log.byOperation('verify');
    if (from == null && to == null) return verify;
    final fromUtc = from?.toUtc();
    final toUtc = to?.toUtc();
    return verify.where((entry) {
      if (fromUtc != null && entry.at.isBefore(fromUtc)) return false;
      if (toUtc != null && entry.at.isAfter(toUtc)) return false;
      return true;
    }).toList();
  }
}
