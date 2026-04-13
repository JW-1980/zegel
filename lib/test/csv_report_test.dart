import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('CsvReport', () {
    test('escape handles plain values and special characters', () {
      expect(CsvReport.escape('plain'), 'plain');
      expect(CsvReport.escape('with,comma'), '"with,comma"');
      expect(CsvReport.escape('with "quote"'), '"with ""quote"""');
      expect(CsvReport.escape(42), '42');
      expect(CsvReport.escape(null), '');
    });

    test('buildCsv produces header + rows', () {
      final csv = CsvReport.buildCsv(
        ['name', 'count'],
        [
          ['seal', 2],
          ['verify', 5],
        ],
      );
      expect(csv.split('\n').first, 'name,count');
      expect(csv, contains('seal,2'));
      expect(csv, contains('verify,5'));
    });

    test('dailySummary aggregates by date', () {
      final log = HistoryLog();
      log.record(
        operation: 'verify',
        success: true,
        at: DateTime.utc(2026, 4, 10),
        duration: const Duration(milliseconds: 100),
      );
      log.record(
        operation: 'verify',
        success: false,
        at: DateTime.utc(2026, 4, 10),
        duration: const Duration(milliseconds: 200),
      );
      log.record(
        operation: 'seal',
        success: true,
        at: DateTime.utc(2026, 4, 11),
      );
      final csv = CsvReport.dailySummary(log);
      expect(csv, contains('2026-04-10,2,1,1'));
      expect(csv, contains('2026-04-11,1,1,0'));
    });

    test('operationSummary aggregates by operation with success rates', () {
      final log = HistoryLog();
      log.record(operation: 'verify', success: true);
      log.record(operation: 'verify', success: true);
      log.record(operation: 'verify', success: false);
      final csv = CsvReport.operationSummary(log);
      expect(csv, contains('verify,3,2,1,0.67'));
    });
  });
}
