import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('IsolatePool', () {
    test('runs tasks up to maxWorkers in parallel', () async {
      final pool = IsolatePool(maxWorkers: 2);
      var peakActive = 0;
      int activeAtMoment = 0;

      Future<int> task(int id) async {
        activeAtMoment++;
        if (activeAtMoment > peakActive) peakActive = activeAtMoment;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        activeAtMoment--;
        return id * 2;
      }

      final results = await Future.wait(<Future<int>>[
        pool.run(() => task(1)),
        pool.run(() => task(2)),
        pool.run(() => task(3)),
        pool.run(() => task(4)),
      ]);

      expect(results, [2, 4, 6, 8]);
      expect(peakActive, lessThanOrEqualTo(2));
      await pool.close();
    });

    test('errors propagate to the caller', () async {
      final pool = IsolatePool(maxWorkers: 1);
      await expectLater(
        pool.run<int>(() async {
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );
      await pool.close();
    });

    test('runAll preserves order', () async {
      final pool = IsolatePool(maxWorkers: 3);
      final results = await pool.runAll<int>(<Future<int> Function()>[
        () async => 1,
        () async => 2,
        () async => 3,
      ]);
      expect(results, [1, 2, 3]);
      await pool.close();
    });

    test('rejects submissions after close', () async {
      final pool = IsolatePool(maxWorkers: 1);
      await pool.close();
      expect(
        () => pool.run<int>(() async => 1),
        throwsStateError,
      );
    });

    test('rejects invalid maxWorkers', () {
      expect(() => IsolatePool(maxWorkers: 0), throwsArgumentError);
    });
  });
}
