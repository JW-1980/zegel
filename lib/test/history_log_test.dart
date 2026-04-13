import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('HistoryLog', () {
    test('record appends entries and tail returns newest first', () {
      final log = HistoryLog();
      log.record(
        operation: 'verify',
        success: true,
        filename: 'a.zgl',
        duration: const Duration(milliseconds: 50),
      );
      log.record(
        operation: 'seal',
        success: false,
        filename: 'b.txt',
        message: 'disk full',
      );
      expect(log.entries.length, 2);
      final tail = log.tail(limit: 1);
      expect(tail.length, 1);
      expect(tail.first.operation, 'seal');
    });

    test('byOperation and byStatus filter correctly', () {
      final log = HistoryLog();
      log.record(operation: 'verify', success: true);
      log.record(operation: 'verify', success: false);
      log.record(operation: 'seal', success: true);

      expect(log.byOperation('verify').length, 2);
      expect(log.byStatus(success: true).length, 2);
    });

    test('inRange filters by timestamp', () {
      final log = HistoryLog();
      log.record(
        operation: 'verify',
        success: true,
        at: DateTime.utc(2026, 1, 1),
      );
      log.record(
        operation: 'verify',
        success: true,
        at: DateTime.utc(2026, 6, 1),
      );
      final selected = log.inRange(
        DateTime.utc(2026, 5, 1),
        DateTime.utc(2026, 7, 1),
      );
      expect(selected.length, 1);
    });

    test('prune removes expired entries using a retention policy', () {
      final log = HistoryLog();
      log.record(
        operation: 'verify',
        success: true,
        at: DateTime.utc(2025, 1, 1),
      );
      log.record(
        operation: 'verify',
        success: true,
        at: DateTime.utc(2026, 4, 1),
      );
      final policy = RetentionPolicy(
        defaultRetention: const Duration(days: 30),
      );
      final dropped = log.prune(policy, now: DateTime.utc(2026, 4, 12));
      expect(dropped, 1);
      expect(log.entries.length, 1);
    });

    test('encode/decode round trip', () {
      final log = HistoryLog();
      log.record(operation: 'verify', success: true, filename: 'x.zgl');
      log.record(operation: 'seal', success: false, message: 'boom');
      final restored = HistoryLog.decode(log.encode());
      expect(restored.entries.length, 2);
    });
  });
}
