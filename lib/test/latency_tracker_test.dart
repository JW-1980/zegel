import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('LatencyTracker', () {
    test('records and summarizes percentiles correctly', () {
      final t = LatencyTracker('tsa.example.org');
      for (var i = 1; i <= 100; i++) {
        t.record(i);
      }
      expect(t.count, 100);
      expect(t.minMs, 1);
      expect(t.maxMs, 100);
      expect(t.averageMs, closeTo(50.5, 0.01));
      expect(t.percentileMs(50), 50);
      expect(t.percentileMs(95), 95);
      expect(t.percentileMs(99), 99);
    });

    test('empty tracker returns null summary fields', () {
      final t = LatencyTracker('endpoint');
      expect(t.minMs, isNull);
      expect(t.maxMs, isNull);
      expect(t.averageMs, isNull);
      expect(t.percentileMs(50), isNull);
    });

    test('enforces maxSamples (rolling window)', () {
      final t = LatencyTracker('endpoint', maxSamples: 5);
      for (var i = 0; i < 10; i++) {
        t.record(i);
      }
      expect(t.count, 5);
      expect(t.minMs, 5);
      expect(t.maxMs, 9);
    });

    test('rejects negative latencies and invalid percentiles', () {
      final t = LatencyTracker('endpoint');
      expect(() => t.record(-1), throwsArgumentError);
      t.record(10);
      expect(() => t.percentileMs(-1), throwsArgumentError);
      expect(() => t.percentileMs(101), throwsArgumentError);
    });

    test('encode/decodeJson round trip', () {
      final t = LatencyTracker('endpoint', maxSamples: 3);
      t.record(100);
      t.record(200);
      final restored = LatencyTracker.decodeJson(t.encode());
      expect(restored.endpoint, 'endpoint');
      expect(restored.count, 2);
      expect(restored.maxMs, 200);
    });
  });
}
