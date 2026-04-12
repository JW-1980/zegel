import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('PrefetchQueue', () {
    test('prefetch caches loader result', () async {
      var calls = 0;
      final queue = PrefetchQueue<String, int>(
        loader: (key) async {
          calls++;
          return key.length;
        },
      );
      await queue.prefetch('alpha');
      final value = await queue.fetch('alpha');
      expect(value, 5);
      expect(calls, 1);
    });

    test('fetch resolves immediately when the entry is hot', () async {
      final queue = PrefetchQueue<String, String>(
        loader: (key) async => 'resolved-$key',
      );
      await queue.prefetch('k');
      final result = await queue.fetch('k');
      expect(result, 'resolved-k');
    });

    test('invalidate drops cached entries', () async {
      var calls = 0;
      final queue = PrefetchQueue<String, int>(
        loader: (key) async {
          calls++;
          return calls;
        },
      );
      await queue.prefetch('alpha');
      queue.invalidate('alpha');
      await queue.fetch('alpha');
      expect(calls, 2);
    });

    test('isHot respects ttl', () async {
      final queue = PrefetchQueue<String, int>(
        loader: (_) async => 0,
        ttl: const Duration(milliseconds: 50),
      );
      await queue.prefetch('k');
      expect(queue.isHot('k'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(queue.isHot('k'), isFalse);
    });

    test('maxEntries caps the cache size', () async {
      final queue = PrefetchQueue<int, int>(
        loader: (key) async => key * 2,
        maxEntries: 2,
      );
      await queue.prefetch(1);
      await queue.prefetch(2);
      await queue.prefetch(3);
      expect(queue.length, 2);
    });
  });
}
