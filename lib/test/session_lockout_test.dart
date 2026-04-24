import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('SessionLockout', () {
    test('initially unlocked and records activity time', () {
      final s = SessionLockout(
        timeout: const Duration(minutes: 5),
        nowOverride: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      expect(s.isLocked, isFalse);
      expect(s.lastActivity, DateTime.utc(2026, 1, 1, 12, 0, 0));
    });

    test('isIdleAt returns true once timeout has passed', () {
      final s = SessionLockout(
        timeout: const Duration(minutes: 5),
        nowOverride: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      expect(s.isIdleAt(DateTime.utc(2026, 1, 1, 12, 4, 0)), isFalse);
      expect(s.isIdleAt(DateTime.utc(2026, 1, 1, 12, 10, 0)), isTrue);
    });

    test('recordActivity resets the last activity time', () {
      final s = SessionLockout(
        timeout: const Duration(minutes: 5),
        nowOverride: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      s.recordActivity(at: DateTime.utc(2026, 1, 1, 12, 30, 0));
      expect(s.isIdleAt(DateTime.utc(2026, 1, 1, 12, 31, 0)), isFalse);
    });

    test('lock and unlock emit events', () async {
      final s = SessionLockout(
        timeout: const Duration(minutes: 5),
        nowOverride: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      final received = <SessionLockoutEventType>[];
      s.events.listen((event) => received.add(event.type));
      s.lock();
      expect(s.isLocked, isTrue);
      s.unlock();
      expect(s.isLocked, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(received, [
        SessionLockoutEventType.locked,
        SessionLockoutEventType.unlocked,
      ]);
      await s.close();
    });

    test('recordActivity is ignored while locked', () {
      final s = SessionLockout()..lock();
      final before = s.lastActivity;
      s.recordActivity(at: DateTime.utc(2099, 1, 1));
      expect(s.lastActivity, before);
    });
  });
}
