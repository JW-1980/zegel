import 'classification.dart';

/// Aggregated classification statistics (improvement #82).
///
/// Given a stream of classification labels collected from files the user
/// has processed, produces a distribution suitable for powering a pie or
/// bar chart in the dashboard. The class intentionally consumes raw
/// labels rather than parsed [Classification] values so callers can feed
/// it anything (including unknown classifications), and the stats will
/// still be well-defined.
class ClassificationStats {
  ClassificationStats();

  final Map<String, int> _counts = <String, int>{};

  /// Records a single sighting of [level].
  void record(String level) {
    _counts[level] = (_counts[level] ?? 0) + 1;
  }

  /// Bulk record every label in [levels].
  void recordAll(Iterable<String> levels) {
    for (final level in levels) {
      record(level);
    }
  }

  /// Current count for [level].
  int countOf(String level) => _counts[level] ?? 0;

  /// Total number of recorded classifications.
  int get total => _counts.values.fold<int>(0, (a, b) => a + b);

  /// Unique classification levels seen so far.
  Iterable<String> get levels => _counts.keys;

  /// Returns the distribution as `{level: fraction}` where fractions
  /// sum to 1.0 (or 0 if nothing has been recorded).
  Map<String, double> distribution() {
    if (total == 0) return const <String, double>{};
    return <String, double>{
      for (final entry in _counts.entries)
        entry.key: entry.value / total,
    };
  }

  /// Returns a ranked list ordered by descending count. When the class
  /// can be mapped to a known [Classification.levels] position, the
  /// [slice.order] field reflects that natural ordering; otherwise the
  /// slices are ordered by count only.
  List<ClassificationSlice> ranked() {
    final entries = _counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return <ClassificationSlice>[
      for (final entry in entries)
        ClassificationSlice(
          level: entry.key,
          count: entry.value,
          fraction: total == 0 ? 0 : entry.value / total,
          order: _canonicalOrder(entry.key),
        ),
    ];
  }

  /// Returns the label with the highest count, or null if empty.
  String? topLevel() {
    if (_counts.isEmpty) return null;
    String? best;
    int bestCount = -1;
    for (final entry in _counts.entries) {
      if (entry.value > bestCount) {
        best = entry.key;
        bestCount = entry.value;
      }
    }
    return best;
  }

  /// Returns an unmodifiable snapshot of the underlying counts.
  Map<String, int> snapshot() => Map<String, int>.unmodifiable(_counts);

  /// Clears all counts.
  void reset() => _counts.clear();

  static int _canonicalOrder(String level) {
    final idx = Classification.levels.indexOf(level);
    return idx >= 0 ? idx : Classification.levels.length;
  }
}

class ClassificationSlice {
  const ClassificationSlice({
    required this.level,
    required this.count,
    required this.fraction,
    required this.order,
  });

  final String level;
  final int count;
  final double fraction;
  final int order;
}
