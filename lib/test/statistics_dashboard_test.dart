import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('StatisticsDashboard', () {
    test('empty sources yield defaults', () {
      final snapshot = StatisticsDashboard.build();
      expect(snapshot.totalFiles, 0);
      expect(snapshot.successRate, 1.0);
      expect(snapshot.timeSaved, Duration.zero);
    });

    test('combines analytics, history, and time-saved', () {
      final analytics = UsageAnalytics(enabled: true)
        ..recordFileSealed(1024)
        ..recordCommand('seal')
        ..recordCommand('verify')
        ..recordAlgorithm('Ed25519');
      final history = HistoryLog()
        ..record(operation: 'verify', success: true)
        ..record(operation: 'verify', success: false)
        ..record(operation: 'seal', success: true);
      final timeSaved = TimeSavedTracker(
        baselinePerFile: const Duration(seconds: 10),
      )..recordBatch(files: 5, duration: const Duration(seconds: 10));

      final snapshot = StatisticsDashboard.build(
        analytics: analytics,
        history: history,
        timeSaved: timeSaved,
      );
      expect(snapshot.totalFiles, 1);
      expect(snapshot.totalBytes, 1024);
      expect(snapshot.totalOperations, 3);
      expect(snapshot.totalFailures, 1);
      expect(snapshot.successRate, closeTo(2 / 3, 1e-9));
      expect(snapshot.timeSaved, const Duration(seconds: 40));
      expect(snapshot.topCommands.isNotEmpty, isTrue);
      expect(snapshot.topAlgorithms.first.key, 'Ed25519');
    });

    test('toJson returns well-formed data', () {
      final snapshot = StatisticsDashboard.build();
      final json = snapshot.toJson();
      expect(
        json.keys,
        containsAll(<String>[
          'total_files',
          'total_operations',
          'success_rate',
          'time_saved_seconds',
        ]),
      );
    });
  });
}
