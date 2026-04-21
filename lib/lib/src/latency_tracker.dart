import 'dart:convert';

/// Network latency metrics for timestamping (improvement #38).
///
/// Records observation samples of round-trip time (in milliseconds) to
/// network services such as a trusted timestamp authority. Exposes
/// count/min/max/average/p50/p95/p99 percentiles over all samples,
/// plus a rolling window of the most recent observations.
class LatencyTracker {
  LatencyTracker(this.endpoint, {this.maxSamples = 200}) : _samples = [];

  /// Name of the measured endpoint (e.g. `tsa.example.org`).
  final String endpoint;

  /// Maximum number of samples to keep in the rolling buffer.
  final int maxSamples;

  final List<LatencySample> _samples;

  /// Records one round-trip observation in milliseconds.
  void record(int latencyMs, {DateTime? at}) {
    if (latencyMs < 0) {
      throw ArgumentError.value(latencyMs, 'latencyMs', 'must be non-negative');
    }
    _samples.add(LatencySample(
      latencyMs: latencyMs,
      at: (at ?? DateTime.now().toUtc()).toUtc(),
    ));
    while (_samples.length > maxSamples) {
      _samples.removeAt(0);
    }
  }

  /// Number of samples currently in the buffer.
  int get count => _samples.length;

  int? get minMs {
    if (_samples.isEmpty) return null;
    return _samples.map((s) => s.latencyMs).reduce((a, b) => a < b ? a : b);
  }

  int? get maxMs {
    if (_samples.isEmpty) return null;
    return _samples.map((s) => s.latencyMs).reduce((a, b) => a > b ? a : b);
  }

  double? get averageMs {
    if (_samples.isEmpty) return null;
    final sum = _samples.fold<int>(0, (a, b) => a + b.latencyMs);
    return sum / _samples.length;
  }

  /// Calculates the given percentile (0–100) over all samples using the
  /// nearest-rank method.
  int? percentileMs(double percentile) {
    if (_samples.isEmpty) return null;
    if (percentile < 0 || percentile > 100) {
      throw ArgumentError.value(
          percentile, 'percentile', 'must be in [0, 100]');
    }
    final sorted = _samples.map((s) => s.latencyMs).toList()..sort();
    final rank = (percentile / 100 * sorted.length).ceil();
    final idx = rank == 0 ? 0 : rank - 1;
    return sorted[idx.clamp(0, sorted.length - 1)];
  }

  /// Resets the tracker.
  void reset() => _samples.clear();

  Map<String, dynamic> summary() => {
        'endpoint': endpoint,
        'count': count,
        'min_ms': minMs,
        'max_ms': maxMs,
        'average_ms': averageMs,
        'p50_ms': percentileMs(50),
        'p95_ms': percentileMs(95),
        'p99_ms': percentileMs(99),
      };

  String encode() => jsonEncode({
        'endpoint': endpoint,
        'max_samples': maxSamples,
        'samples': _samples.map((s) => s.toJson()).toList(),
      });

  static LatencyTracker decodeJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final tracker = LatencyTracker(
      m['endpoint'] as String,
      maxSamples: (m['max_samples'] as num?)?.toInt() ?? 200,
    );
    for (final entry in (m['samples'] as List<dynamic>? ?? const <dynamic>[])) {
      tracker._samples
          .add(LatencySample.fromJson(entry as Map<String, dynamic>));
    }
    return tracker;
  }
}

class LatencySample {
  const LatencySample({required this.latencyMs, required this.at});

  static LatencySample fromJson(Map<String, dynamic> json) => LatencySample(
        latencyMs: (json['latency_ms'] as num).toInt(),
        at: DateTime.parse(json['at'] as String).toUtc(),
      );

  final int latencyMs;
  final DateTime at;

  Map<String, dynamic> toJson() => {
        'latency_ms': latencyMs,
        'at': at.toUtc().toIso8601String(),
      };
}
