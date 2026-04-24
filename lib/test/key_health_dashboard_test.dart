import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('KeyHealthDashboard', () {
    test('empty tracker reports perfect health', () {
      final reminder = KeyRotationReminder();
      final snap = KeyHealthDashboard.from(reminder);
      expect(snap.total, 0);
      expect(snap.healthScore, 1.0);
      expect(snap.mostUrgent, isNull);
    });

    test('mix of statuses produces a weighted health score', () {
      final now = DateTime.utc(2026, 4, 12);
      final reminder =
          KeyRotationReminder(rotationWindow: const Duration(days: 30))
            ..registerKey(
              'fresh',
              createdAt: now.subtract(const Duration(days: 1)),
            )
            ..registerKey(
              'due',
              createdAt: now.subtract(const Duration(days: 31)),
            )
            ..registerKey(
              'overdue',
              createdAt: now.subtract(const Duration(days: 60)),
            );

      final snap = KeyHealthDashboard.from(reminder, now: now);
      expect(snap.total, 3);
      expect(snap.ok, 1);
      expect(snap.due, 1);
      expect(snap.overdue, 1);
      // Score: (1*1 + 1*0.5 + 1*0) / 3 = 0.5
      expect(snap.healthScore, closeTo(0.5, 1e-9));
      expect(snap.mostUrgent?.record.name, 'overdue');
    });

    test('isHealthy is false whenever anything is due or overdue', () {
      final now = DateTime.utc(2026, 4, 12);
      final reminder =
          KeyRotationReminder(rotationWindow: const Duration(days: 7))
            ..registerKey(
              'stale',
              createdAt: now.subtract(const Duration(days: 30)),
            );
      final snap = KeyHealthDashboard.from(reminder, now: now);
      expect(snap.isHealthy, isFalse);
    });
  });
}
