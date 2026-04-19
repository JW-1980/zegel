import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('TimeSavedTracker', () {
    test('positive savings when batch beats baseline', () {
      final tracker = TimeSavedTracker(
        baselinePerFile: const Duration(seconds: 10),
      );
      tracker.recordBatch(files: 10, duration: const Duration(seconds: 20));
      // baseline = 100s, actual = 20s, saved = 80s
      expect(tracker.estimatedManualDuration, const Duration(seconds: 100));
      expect(tracker.timeSaved, const Duration(seconds: 80));
      expect(tracker.timeSavedRatio, closeTo(0.8, 0.001));
    });

    test('zero savings when batch is slower than baseline', () {
      final tracker = TimeSavedTracker(
        baselinePerFile: const Duration(seconds: 1),
      );
      tracker.recordBatch(files: 10, duration: const Duration(seconds: 100));
      expect(tracker.timeSaved, Duration.zero);
    });

    test('multiple batches accumulate', () {
      final tracker = TimeSavedTracker(
        baselinePerFile: const Duration(seconds: 10),
      );
      tracker.recordBatch(files: 5, duration: const Duration(seconds: 5));
      tracker.recordBatch(files: 5, duration: const Duration(seconds: 5));
      expect(tracker.batchFileCount, 10);
      expect(tracker.batchRuns, 2);
      expect(tracker.totalBatchDuration, const Duration(seconds: 10));
    });

    test('rejects negative durations and ignores zero-file batches', () {
      final tracker = TimeSavedTracker();
      expect(
        () => tracker.recordBatch(
          files: 1,
          duration: const Duration(seconds: -1),
        ),
        throwsArgumentError,
      );
      tracker.recordBatch(files: 0, duration: const Duration(seconds: 5));
      expect(tracker.batchRuns, 0);
    });

    test('reset zeroes all counters', () {
      final tracker = TimeSavedTracker();
      tracker.recordBatch(files: 1, duration: const Duration(seconds: 1));
      tracker.reset();
      expect(tracker.batchFileCount, 0);
      expect(tracker.batchRuns, 0);
      expect(tracker.totalBatchDuration, Duration.zero);
    });
  });
}
