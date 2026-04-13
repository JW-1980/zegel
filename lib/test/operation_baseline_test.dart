import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('OperationBaseline', () {
    test('mean and stddev reflect recorded samples', () {
      final baseline = OperationBaseline();
      for (var i = 0; i < 10; i++) {
        baseline.record('verify', Duration(milliseconds: 100 + i));
      }
      final mean = baseline.meanMs('verify');
      expect(mean, isNotNull);
      expect(mean!, closeTo(104.5, 0.1));
      expect(baseline.stddevMs('verify'), isNotNull);
    });

    test('unknown operation returns null metrics', () {
      final baseline = OperationBaseline();
      expect(baseline.meanMs('nope'), isNull);
      expect(baseline.stddevMs('nope'), isNull);
    });

    test('z-score classifies outliers', () {
      final baseline = OperationBaseline();
      for (var i = 0; i < 30; i++) {
        baseline.record('seal', const Duration(milliseconds: 100));
      }
      // Introduce variance so stddev > 0.
      for (var i = 0; i < 5; i++) {
        baseline.record('seal', const Duration(milliseconds: 105));
      }
      final comparison = baseline.compare(
        'seal',
        const Duration(milliseconds: 100),
      );
      expect(comparison.meanMs, isNotNull);
      expect(comparison.isOutlier, isFalse);
    });

    test('window size caps the stored samples', () {
      final baseline = OperationBaseline(windowSize: 5);
      for (var i = 0; i < 10; i++) {
        baseline.record('verify', Duration(milliseconds: i));
      }
      expect(baseline.sampleCount('verify'), 5);
    });
  });
}
