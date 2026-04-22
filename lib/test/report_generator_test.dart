import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('ReportGenerator', () {
    test('batchVerifyReport summarises verify entries', () {
      final log = HistoryLog();
      log.record(
        operation: 'verify',
        success: true,
        filename: 'a.zgl',
        duration: const Duration(milliseconds: 100),
      );
      log.record(
        operation: 'verify',
        success: false,
        filename: 'b.zgl',
        message: 'Merkle mismatch',
        duration: const Duration(milliseconds: 150),
      );
      log.record(operation: 'seal', success: true);

      final report = ReportGenerator.batchVerifyReport(log);
      expect(report, contains('Files processed | 2'));
      expect(report, contains('Successes | 1'));
      expect(report, contains('Failures | 1'));
      expect(report, contains('`b.zgl` — Merkle mismatch'));
    });

    test('usageReport includes overview and top commands', () {
      final analytics = UsageAnalytics(enabled: true)
        ..recordCommand('seal')
        ..recordCommand('seal')
        ..recordCommand('verify')
        ..recordAlgorithm('AES-256-GCM')
        ..recordFileSealed(2048);
      final report = ReportGenerator.usageReport(analytics);
      expect(report, contains('Usage Report'));
      expect(report, contains('Total files sealed | 1'));
      expect(report, contains('`seal` — 2 invocations'));
      expect(report, contains('AES-256-GCM'));
    });
  });
}
