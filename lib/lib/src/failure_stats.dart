import 'dart:convert';
import 'dart:io';

/// Categorized verification-failure tracker (improvement #35).
///
/// Aggregates verification failures into a small, well-known set of
/// buckets so support teams can quickly spot the most common user errors
/// without needing to inspect individual logs.
class FailureStats {
  FailureStats({this.maxSamples = 50}) : _counts = {}, _samples = [];

  final Map<FailureCategory, int> _counts;
  final List<FailureSample> _samples;
  final int maxSamples;

  /// Records a failure. If [category] is null, the stats use
  /// [FailureCategory.other] and record the message verbatim for review.
  void record(String message, {FailureCategory? category, DateTime? at}) {
    final bucket = category ?? classify(message);
    _counts[bucket] = (_counts[bucket] ?? 0) + 1;
    _samples.add(
      FailureSample(
        category: bucket,
        message: message,
        at: (at ?? DateTime.now().toUtc()).toUtc(),
      ),
    );
    while (_samples.length > maxSamples) {
      _samples.removeAt(0);
    }
  }

  /// Heuristic that maps a raw failure message to a category.
  static FailureCategory classify(String message) {
    final m = message.toLowerCase();
    if (m.contains('magic') ||
        m.contains('header') ||
        m.contains('not a zegel')) {
      return FailureCategory.badMagic;
    }
    if (m.contains('merkle')) return FailureCategory.merkleMismatch;
    if (m.contains('gcm') ||
        m.contains('auth tag') ||
        m.contains('mac') ||
        m.contains('hmac')) {
      return FailureCategory.authTagFailure;
    }
    if (m.contains('expired') || m.contains('expiration')) {
      return FailureCategory.expired;
    }
    if (m.contains('wrong key') ||
        m.contains('invalid key') ||
        m.contains('key mismatch')) {
      return FailureCategory.wrongKey;
    }
    if (m.contains('corrupt') || m.contains('truncated')) {
      return FailureCategory.corruptFile;
    }
    if (m.contains('version') && m.contains('unsupported')) {
      return FailureCategory.unsupportedVersion;
    }
    return FailureCategory.other;
  }

  /// Counts per category.
  Map<FailureCategory, int> get counts =>
      Map<FailureCategory, int>.unmodifiable(_counts);

  /// Most recent failure samples (oldest first, newest last).
  List<FailureSample> get samples => List<FailureSample>.unmodifiable(_samples);

  /// Total number of recorded failures.
  int get totalFailures => _counts.values.fold<int>(0, (a, b) => a + b);

  /// Returns the most frequent failure category, or null if none recorded.
  FailureCategory? topCategory() {
    if (_counts.isEmpty) return null;
    final sorted = _counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  Map<String, dynamic> toJson() => {
    'counts': {for (final e in _counts.entries) e.key.name: e.value},
    'samples': _samples.map((s) => s.toJson()).toList(),
    'max_samples': maxSamples,
  };

  String encode() => jsonEncode(toJson());

  static FailureStats decodeJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final stats = FailureStats(
      maxSamples: (m['max_samples'] as num?)?.toInt() ?? 50,
    );
    final countsMap =
        (m['counts'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    countsMap.forEach((k, v) {
      final cat = FailureCategory.values.firstWhere(
        (c) => c.name == k,
        orElse: () => FailureCategory.other,
      );
      stats._counts[cat] = (v as num).toInt();
    });
    final samples = (m['samples'] as List<dynamic>?) ?? const <dynamic>[];
    for (final s in samples) {
      stats._samples.add(FailureSample.fromJson(s as Map<String, dynamic>));
    }
    return stats;
  }

  void saveFile(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encode());
  }

  static FailureStats loadFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return FailureStats();
    return decodeJson(file.readAsStringSync());
  }
}

enum FailureCategory {
  badMagic,
  merkleMismatch,
  authTagFailure,
  wrongKey,
  expired,
  corruptFile,
  unsupportedVersion,
  other,
}

class FailureSample {
  const FailureSample({
    required this.category,
    required this.message,
    required this.at,
  });

  static FailureSample fromJson(Map<String, dynamic> json) => FailureSample(
    category: FailureCategory.values.firstWhere(
      (c) => c.name == json['category'],
      orElse: () => FailureCategory.other,
    ),
    message: json['message'] as String,
    at: DateTime.parse(json['at'] as String).toUtc(),
  );

  final FailureCategory category;
  final String message;
  final DateTime at;

  Map<String, dynamic> toJson() => {
    'category': category.name,
    'message': message,
    'at': at.toUtc().toIso8601String(),
  };
}
