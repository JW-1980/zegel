/// Operation time baselines (improvement #89).
///
/// Establishes a historical average for each named operation (verify,
/// seal, extract, attest) so that anomalous runs can be highlighted.
/// The class maintains a rolling window of recent samples and exposes
/// helpers for computing the mean, standard deviation, and z-score of
/// a new observation.
class OperationBaseline {
  OperationBaseline({this.windowSize = 100});

  /// Maximum number of samples retained per operation.
  final int windowSize;

  final Map<String, List<double>> _samples = <String, List<double>>{};

  /// Records a single observation for [operation]. Durations are stored
  /// as floating-point milliseconds for precision and to keep the stats
  /// math simple.
  void record(String operation, Duration duration) {
    final list = _samples.putIfAbsent(operation, () => <double>[]);
    list.add(duration.inMicroseconds / 1000.0);
    while (list.length > windowSize) {
      list.removeAt(0);
    }
  }

  /// Number of samples currently retained for [operation].
  int sampleCount(String operation) => _samples[operation]?.length ?? 0;

  /// Returns the arithmetic mean of the samples in milliseconds, or
  /// `null` if no samples exist for [operation].
  double? meanMs(String operation) {
    final list = _samples[operation];
    if (list == null || list.isEmpty) return null;
    return list.reduce((a, b) => a + b) / list.length;
  }

  /// Returns the sample standard deviation in milliseconds, or `null`
  /// if fewer than 2 samples are present.
  double? stddevMs(String operation) {
    final list = _samples[operation];
    if (list == null || list.length < 2) return null;
    final mean = meanMs(operation)!;
    var sumSquares = 0.0;
    for (final v in list) {
      final delta = v - mean;
      sumSquares += delta * delta;
    }
    final variance = sumSquares / (list.length - 1);
    return _sqrt(variance);
  }

  /// Returns the z-score `(observation - mean) / stddev` in units of
  /// standard deviations. Useful for flagging outliers — e.g. a z-score
  /// above 3 indicates the new observation is far slower than typical.
  /// Returns `null` if there is not enough history.
  double? zScore(String operation, Duration observation) {
    final mean = meanMs(operation);
    final stddev = stddevMs(operation);
    if (mean == null || stddev == null || stddev == 0) return null;
    final ms = observation.inMicroseconds / 1000.0;
    return (ms - mean) / stddev;
  }

  /// Returns a [BaselineComparison] for the new observation. Callers
  /// typically use [BaselineComparison.isOutlier] and
  /// [BaselineComparison.zScore] to drive user warnings.
  BaselineComparison compare(String operation, Duration observation) {
    final mean = meanMs(operation);
    if (mean == null) {
      return BaselineComparison(
        operation: operation,
        observationMs: observation.inMicroseconds / 1000.0,
        meanMs: null,
        zScore: null,
      );
    }
    return BaselineComparison(
      operation: operation,
      observationMs: observation.inMicroseconds / 1000.0,
      meanMs: mean,
      zScore: zScore(operation, observation),
    );
  }

  /// Clears all samples.
  void reset() => _samples.clear();

  static double _sqrt(double value) {
    // A tiny Newton-Raphson implementation: avoids importing dart:math
    // solely for a single call. Falls back to 0 for negatives (which
    // can't happen with variance anyway).
    if (value < 0) return 0;
    if (value == 0) return 0;
    var x = value;
    var prev = 0.0;
    while ((x - prev).abs() > 1e-9) {
      prev = x;
      x = (x + value / x) / 2;
    }
    return x;
  }
}

class BaselineComparison {
  const BaselineComparison({
    required this.operation,
    required this.observationMs,
    required this.meanMs,
    required this.zScore,
  });

  final String operation;
  final double observationMs;
  final double? meanMs;
  final double? zScore;

  /// True when there is enough history AND the new sample is more
  /// than 3 standard deviations away from the mean.
  bool get isOutlier {
    final z = zScore;
    return z != null && z.abs() >= 3.0;
  }
}
