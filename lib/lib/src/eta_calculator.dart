/// Estimated time-remaining calculator (improvement #6).
///
/// Fed periodic `(processed, total, timestamp)` samples by a progress
/// indicator, returns an estimate of the remaining duration based on a
/// rolling exponential moving average of throughput. Unlike a naive
/// `(total - processed) * elapsed / processed`, the EMA keeps the ETA
/// stable when batch performance fluctuates.
class EtaCalculator {
  EtaCalculator({
    required this.total,
    this.alpha = 0.3,
    DateTime? startedAt,
  })  : _startedAt = startedAt ?? DateTime.now().toUtc(),
        _lastSample = null,
        _emaPerItem = null {
    if (total < 0) {
      throw ArgumentError.value(total, 'total', 'must be non-negative');
    }
    if (alpha <= 0 || alpha > 1) {
      throw ArgumentError.value(alpha, 'alpha', 'must be in (0, 1]');
    }
  }

  /// Total number of items to process.
  final int total;

  /// Smoothing factor for the per-item EMA in `(0, 1]`. Higher values
  /// weight recent samples more heavily.
  final double alpha;

  final DateTime _startedAt;
  _Sample? _lastSample;
  double? _emaPerItem;

  /// Duration since the calculator was created.
  Duration elapsed({DateTime? now}) =>
      (now ?? DateTime.now().toUtc()).toUtc().difference(_startedAt);

  /// Records a progress snapshot at [processed] items.
  void update(int processed, {DateTime? at}) {
    if (processed < 0) {
      throw ArgumentError.value(processed, 'processed', 'must be non-negative');
    }
    final now = (at ?? DateTime.now().toUtc()).toUtc();
    final sample = _Sample(processed: processed, at: now);
    final prev = _lastSample;
    if (prev != null) {
      final items = processed - prev.processed;
      final elapsedMicros = now.difference(prev.at).inMicroseconds;
      if (items > 0 && elapsedMicros > 0) {
        final perItem = elapsedMicros / items;
        if (_emaPerItem == null) {
          _emaPerItem = perItem;
        } else {
          _emaPerItem = alpha * perItem + (1 - alpha) * _emaPerItem!;
        }
      }
    }
    _lastSample = sample;
  }

  /// Current items-per-second throughput based on the EMA, or `null`
  /// if not enough samples have been recorded.
  double? get itemsPerSecond {
    final perItem = _emaPerItem;
    if (perItem == null || perItem <= 0) return null;
    return 1e6 / perItem;
  }

  /// Estimated remaining duration. Returns `null` until at least two
  /// samples have been recorded.
  Duration? remaining({DateTime? now}) {
    final sample = _lastSample;
    final perItem = _emaPerItem;
    if (sample == null || perItem == null) return null;
    final remainingItems = total - sample.processed;
    if (remainingItems <= 0) return Duration.zero;
    final remainingMicros = (remainingItems * perItem).round();
    return Duration(microseconds: remainingMicros);
  }

  /// Current progress ratio in `[0.0, 1.0]`.
  double get progress {
    if (total == 0) return 1;
    final sample = _lastSample;
    if (sample == null) return 0;
    return (sample.processed / total).clamp(0, 1);
  }
}

class _Sample {
  const _Sample({required this.processed, required this.at});

  final int processed;
  final DateTime at;
}
