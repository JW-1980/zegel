import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

class _Event extends RetainableEvent {
  _Event(this.timestamp, this.category);

  @override
  final DateTime timestamp;
  @override
  final String category;
}

void main() {
  group('RetentionPolicy', () {
    final now = DateTime.utc(2026, 4, 12);

    test('default retention applies when no rule is set', () {
      final policy =
          RetentionPolicy(defaultRetention: const Duration(days: 30));
      final kept = _Event(now.subtract(const Duration(days: 10)), 'verify');
      final expired = _Event(now.subtract(const Duration(days: 60)), 'verify');
      expect(policy.isExpired(kept, now: now), isFalse);
      expect(policy.isExpired(expired, now: now), isTrue);
    });

    test('per-category rules override the default', () {
      final policy =
          RetentionPolicy(defaultRetention: const Duration(days: 30));
      policy.setRule('audit', const Duration(days: 365));
      final old = _Event(now.subtract(const Duration(days: 100)), 'audit');
      expect(policy.isExpired(old, now: now), isFalse);

      final stale = _Event(now.subtract(const Duration(days: 100)), 'verify');
      expect(policy.isExpired(stale, now: now), isTrue);
    });

    test('removeRule reverts to default', () {
      final policy =
          RetentionPolicy(defaultRetention: const Duration(days: 30));
      policy.setRule('audit', const Duration(days: 1));
      policy.removeRule('audit');
      final e = _Event(now.subtract(const Duration(days: 10)), 'audit');
      expect(policy.isExpired(e, now: now), isFalse);
    });

    test('apply returns only kept events', () {
      final policy =
          RetentionPolicy(defaultRetention: const Duration(days: 30));
      final events = [
        _Event(now.subtract(const Duration(days: 10)), 'verify'),
        _Event(now.subtract(const Duration(days: 60)), 'verify'),
      ];
      final kept = policy.apply(events, now: now);
      expect(kept.length, 1);
      expect(kept.first.timestamp, now.subtract(const Duration(days: 10)));
    });

    test('partition returns kept and expired lists', () {
      final policy = RetentionPolicy(defaultRetention: const Duration(days: 7));
      final events = [
        _Event(now.subtract(const Duration(days: 1)), 'verify'),
        _Event(now.subtract(const Duration(days: 14)), 'verify'),
        _Event(now.subtract(const Duration(days: 3)), 'seal'),
      ];
      final r = policy.partition(events, now: now);
      expect(r.kept.length, 2);
      expect(r.expired.length, 1);
    });

    test('encode/decodeJson round trip', () {
      final policy = RetentionPolicy(
        defaultRetention: const Duration(days: 5),
      )..setRule('audit', const Duration(days: 100));
      final restored = RetentionPolicy.decodeJson(policy.encode());
      expect(restored.defaultRetention.inDays, 5);
      expect(restored.retentionFor('audit').inDays, 100);
    });
  });
}
