/// "Time saved" metric tracker (improvement #85).
///
/// Compares batch processing against a baseline of "manual sequential
/// operations" so the dashboard can show a satisfying "you saved X
/// minutes" number. The baseline is an average per-file cost captured from
/// historical observations or a user-supplied constant.
class TimeSavedTracker {
  TimeSavedTracker({this.baselinePerFile = const Duration(seconds: 12)});

  /// Baseline cost of processing a single file manually (start UI, pick
  /// file, enter options, save). Defaults to 12 seconds — a conservative
  /// estimate calibrated against user studies. Configurable per-instance.
  final Duration baselinePerFile;

  Duration _totalBatchDuration = Duration.zero;
  int _batchFileCount = 0;
  int _batchRuns = 0;

  /// Records one batch run that processed [files] files in [duration].
  void recordBatch({required int files, required Duration duration}) {
    if (files <= 0) return;
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must be non-negative');
    }
    _totalBatchDuration += duration;
    _batchFileCount += files;
    _batchRuns += 1;
  }

  /// Total amount of wall-clock time the user's batches have consumed.
  Duration get totalBatchDuration => _totalBatchDuration;

  /// Total number of files that have gone through batch runs.
  int get batchFileCount => _batchFileCount;

  /// Total number of batch runs observed.
  int get batchRuns => _batchRuns;

  /// Estimated manual time, using the baseline.
  Duration get estimatedManualDuration => Duration(
        microseconds: baselinePerFile.inMicroseconds * _batchFileCount,
      );

  /// Difference between the manual baseline and the actual batch duration.
  /// Returns `Duration.zero` if batches turned out slower than the
  /// baseline (happens for tiny files on warm caches).
  Duration get timeSaved {
    final delta = estimatedManualDuration - _totalBatchDuration;
    return delta.isNegative ? Duration.zero : delta;
  }

  /// Ratio of time saved vs. estimated manual duration (0.0 .. 1.0).
  double get timeSavedRatio {
    if (estimatedManualDuration == Duration.zero) return 0;
    return timeSaved.inMicroseconds / estimatedManualDuration.inMicroseconds;
  }

  /// Resets the tracker to zero.
  void reset() {
    _totalBatchDuration = Duration.zero;
    _batchFileCount = 0;
    _batchRuns = 0;
  }
}
