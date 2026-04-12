import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('EtaCalculator', () {
    test('requires two samples before ETA is available', () {
      final eta = EtaCalculator(
        total: 100,
        startedAt: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      eta.update(10, at: DateTime.utc(2026, 1, 1, 12, 0, 0));
      expect(eta.remaining(), isNull);
    });

    test('remaining shrinks as progress increases', () {
      final eta = EtaCalculator(
        total: 100,
        startedAt: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      eta.update(10, at: DateTime.utc(2026, 1, 1, 12, 0, 1));
      eta.update(20, at: DateTime.utc(2026, 1, 1, 12, 0, 2));
      final r1 = eta.remaining();
      expect(r1, isNotNull);
      eta.update(60, at: DateTime.utc(2026, 1, 1, 12, 0, 3));
      final r2 = eta.remaining();
      expect(r2!.inMicroseconds, lessThan(r1!.inMicroseconds));
    });

    test('progress reflects processed/total ratio', () {
      final eta = EtaCalculator(total: 100);
      eta.update(40);
      expect(eta.progress, 0.4);
    });

    test('itemsPerSecond is available after second sample', () {
      final eta = EtaCalculator(
        total: 100,
        startedAt: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      eta.update(0, at: DateTime.utc(2026, 1, 1, 12, 0, 0));
      eta.update(10, at: DateTime.utc(2026, 1, 1, 12, 0, 1));
      expect(eta.itemsPerSecond, isNotNull);
      expect(eta.itemsPerSecond!, closeTo(10.0, 0.1));
    });

    test('rejects invalid arguments', () {
      expect(() => EtaCalculator(total: -1), throwsArgumentError);
      expect(() => EtaCalculator(total: 10, alpha: 0), throwsArgumentError);
    });
  });
}
