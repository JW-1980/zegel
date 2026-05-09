import 'history_log.dart';
import 'time_saved.dart';
import 'usage_analytics.dart';

/// Statistics dashboard aggregator (improvement #81).
///
/// Pulls the various telemetry sources together into a single snapshot
/// that the GUI "Statistics" tab can render without having to reach
/// into each of the underlying services.
class StatisticsDashboard {
  StatisticsDashboard._();

  /// Builds a snapshot from the supplied data sources. Each source is
  /// optional — missing data is omitted from the snapshot.
  static StatisticsSnapshot build({
    UsageAnalytics? analytics,
    HistoryLog? history,
    TimeSavedTracker? timeSaved,
  }) {
    int totalFiles = 0;
    int totalBytes = 0;
    int totalOperations = 0;
    int totalFailures = 0;

    if (analytics != null) {
      totalFiles = analytics.totalFilesSealed;
      totalBytes = analytics.totalBytesSealed;
    }
    if (history != null) {
      totalOperations = history.entries.length;
      totalFailures = history.entries.where((e) => !e.success).length;
    }

    final double successRate = totalOperations == 0
        ? 1.0
        : (totalOperations - totalFailures) / totalOperations;

    return StatisticsSnapshot(
      totalFiles: totalFiles,
      totalBytes: totalBytes,
      totalOperations: totalOperations,
      totalFailures: totalFailures,
      successRate: successRate,
      timeSaved: timeSaved?.timeSaved ?? Duration.zero,
      topCommands:
          analytics?.topCommands(limit: 5) ?? const <MapEntry<String, int>>[],
      topAlgorithms:
          analytics?.topAlgorithms(limit: 5) ?? const <MapEntry<String, int>>[],
    );
  }
}

class StatisticsSnapshot {
  const StatisticsSnapshot({
    required this.totalFiles,
    required this.totalBytes,
    required this.totalOperations,
    required this.totalFailures,
    required this.successRate,
    required this.timeSaved,
    required this.topCommands,
    required this.topAlgorithms,
  });

  /// Total files sealed across the tracker's lifetime.
  final int totalFiles;

  /// Total bytes sealed across the tracker's lifetime.
  final int totalBytes;

  /// Total operations recorded (of any type).
  final int totalOperations;

  /// Operations that ended in failure.
  final int totalFailures;

  /// Success rate in `[0.0, 1.0]`.
  final double successRate;

  /// Wall-clock time saved by batching vs. manual work.
  final Duration timeSaved;

  /// Most-used CLI commands, ranked.
  final List<MapEntry<String, int>> topCommands;

  /// Most-used crypto algorithms, ranked.
  final List<MapEntry<String, int>> topAlgorithms;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'total_files': totalFiles,
        'total_bytes': totalBytes,
        'total_operations': totalOperations,
        'total_failures': totalFailures,
        'success_rate': successRate,
        'time_saved_seconds': timeSaved.inSeconds,
        'top_commands': <Map<String, dynamic>>[
          for (final entry in topCommands)
            <String, dynamic>{'name': entry.key, 'count': entry.value},
        ],
        'top_algorithms': <Map<String, dynamic>>[
          for (final entry in topAlgorithms)
            <String, dynamic>{'name': entry.key, 'count': entry.value},
        ],
      };
}
