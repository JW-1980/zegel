import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('KeyRotationReminder', () {
    test('new keys are OK until the rotation window elapses', () {
      final rem = KeyRotationReminder(rotationWindow: const Duration(days: 30));
      final created = DateTime.utc(2026, 1, 1);
      rem.registerKey('master', createdAt: created);

      expect(rem.statusOf('master', now: created), RotationStatus.ok);
      expect(
        rem.statusOf('master', now: created.add(const Duration(days: 29))),
        RotationStatus.ok,
      );
      expect(
        rem.statusOf('master', now: created.add(const Duration(days: 31))),
        RotationStatus.due,
      );
      expect(
        rem.statusOf('master', now: created.add(const Duration(days: 60))),
        RotationStatus.overdue,
      );
    });

    test('markRotated resets the age', () {
      final rem = KeyRotationReminder(rotationWindow: const Duration(days: 10));
      final created = DateTime.utc(2026, 1, 1);
      rem.registerKey('k', createdAt: created);
      rem.markRotated('k', rotatedAt: created.add(const Duration(days: 20)));
      expect(
        rem.statusOf('k', now: created.add(const Duration(days: 21))),
        RotationStatus.ok,
      );
    });

    test('unknown keys return RotationStatus.unknown', () {
      final rem = KeyRotationReminder();
      expect(rem.statusOf('absent'), RotationStatus.unknown);
    });

    test('summarize sorts by age descending', () {
      final rem = KeyRotationReminder(rotationWindow: const Duration(days: 10));
      rem.registerKey('old', createdAt: DateTime.utc(2025, 1, 1));
      rem.registerKey('young', createdAt: DateTime.utc(2026, 4, 1));

      final summaries = rem.summarize(now: DateTime.utc(2026, 4, 12));
      expect(summaries.first.record.name, 'old');
      expect(summaries.last.record.name, 'young');
    });

    test('encode/decodeJson preserves records and window', () {
      final rem = KeyRotationReminder(rotationWindow: const Duration(days: 45));
      rem.registerKey('k', createdAt: DateTime.utc(2026, 1, 1));
      final encoded = rem.encode();
      final restored = KeyRotationReminder.decodeJson(encoded);
      expect(restored.rotationWindow.inDays, 45);
      expect(restored.records.map((r) => r.name), contains('k'));
    });
  });
}
