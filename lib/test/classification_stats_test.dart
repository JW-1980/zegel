import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('ClassificationStats', () {
    test('records and counts labels', () {
      final stats = ClassificationStats()
        ..record('PUBLIC')
        ..record('INTERNAL')
        ..record('INTERNAL')
        ..record('SECRET');
      expect(stats.countOf('INTERNAL'), 2);
      expect(stats.countOf('SECRET'), 1);
      expect(stats.total, 4);
    });

    test('distribution sums to 1.0', () {
      final stats = ClassificationStats()
        ..recordAll(<String>['PUBLIC', 'PUBLIC', 'INTERNAL', 'SECRET']);
      final dist = stats.distribution();
      var sum = 0.0;
      for (final v in dist.values) {
        sum += v;
      }
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('ranked returns slices in descending count order', () {
      final stats = ClassificationStats()
        ..recordAll(<String>['PUBLIC', 'INTERNAL', 'INTERNAL', 'INTERNAL']);
      final ranked = stats.ranked();
      expect(ranked.first.level, 'INTERNAL');
      expect(ranked.first.count, 3);
      expect(ranked.last.level, 'PUBLIC');
    });

    test('topLevel reflects the most-used label', () {
      final stats = ClassificationStats()
        ..recordAll(<String>['TOP_SECRET', 'TOP_SECRET', 'CONFIDENTIAL']);
      expect(stats.topLevel(), 'TOP_SECRET');
    });

    test('empty stats return null top and empty distribution', () {
      final stats = ClassificationStats();
      expect(stats.topLevel(), isNull);
      expect(stats.distribution(), isEmpty);
    });
  });
}
