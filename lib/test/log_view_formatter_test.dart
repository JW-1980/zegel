import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('LogViewFormatter', () {
    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------
    HistoryLog _buildLog() {
      final log = HistoryLog();
      final base = DateTime.utc(2024, 3, 15, 10, 0, 0);

      log.record(
        operation: 'seal',
        success: true,
        filename: 'report.pdf',
        message: 'Sealed successfully',
        duration: const Duration(milliseconds: 42),
        at: base,
      );
      log.record(
        operation: 'verify',
        success: false,
        filename: 'tampered.zgl',
        message: 'HMAC mismatch',
        duration: const Duration(milliseconds: 7),
        at: base.add(const Duration(seconds: 1)),
      );
      log.record(
        operation: 'extract',
        success: true,
        filename: 'clean.zgl',
        at: base.add(const Duration(seconds: 2)),
      );
      return log;
    }

    // -----------------------------------------------------------------------
    // format
    // -----------------------------------------------------------------------
    group('format', () {
      test('returns one FormattedLogLine per entry (default limit)', () {
        final log = _buildLog();
        final lines = LogViewFormatter.format(log);
        expect(lines.length, 3);
      });

      test('respects the limit parameter', () {
        final log = _buildLog();
        final lines = LogViewFormatter.format(log, limit: 2);
        expect(lines.length, 2);
      });

      test('newest entry appears first', () {
        final log = _buildLog();
        final lines = LogViewFormatter.format(log);
        // tail() returns newest-first, so the first line is the extract op.
        expect(lines.first.operation, 'extract');
      });

      test('assigns LogLevel.info for successful entries', () {
        final log = _buildLog();
        final lines = LogViewFormatter.format(log);
        final sealLine = lines.firstWhere((l) => l.operation == 'seal');
        expect(sealLine.level, LogLevel.info);
      });

      test('assigns LogLevel.error for failed entries', () {
        final log = _buildLog();
        final lines = LogViewFormatter.format(log);
        final verifyLine = lines.firstWhere((l) => l.operation == 'verify');
        expect(verifyLine.level, LogLevel.error);
      });

      test('each line has a non-null timestamp', () {
        final log = _buildLog();
        for (final line in LogViewFormatter.format(log)) {
          expect(line.timestamp, isNotNull);
        }
      });

      test('text contains the operation name', () {
        final log = _buildLog();
        final lines = LogViewFormatter.format(log);
        for (final line in lines) {
          expect(line.text, contains(line.operation));
        }
      });

      test('text contains OK for successful entries', () {
        final log = _buildLog();
        final lines = LogViewFormatter.format(log);
        final sealLine = lines.firstWhere((l) => l.operation == 'seal');
        expect(sealLine.text, contains('OK'));
      });

      test('text contains FAIL for failed entries', () {
        final log = _buildLog();
        final lines = LogViewFormatter.format(log);
        final verifyLine = lines.firstWhere((l) => l.operation == 'verify');
        expect(verifyLine.text, contains('FAIL'));
      });

      test('duration is included in text when includeDuration = true', () {
        final log = _buildLog();
        final lines = LogViewFormatter.format(log, includeDuration: true);
        final sealLine = lines.firstWhere((l) => l.operation == 'seal');
        expect(sealLine.text, contains('42ms'));
      });

      test('duration is omitted when includeDuration = false', () {
        final log = _buildLog();
        final lines = LogViewFormatter.format(log, includeDuration: false);
        final sealLine = lines.firstWhere((l) => l.operation == 'seal');
        expect(sealLine.text, isNot(contains('ms')));
      });

      test('returns empty list for an empty log', () {
        final log = HistoryLog();
        expect(LogViewFormatter.format(log), isEmpty);
      });
    });

    // -----------------------------------------------------------------------
    // formatEntry
    // -----------------------------------------------------------------------
    group('formatEntry', () {
      test('returns a non-empty string', () {
        final log = _buildLog();
        final entry = log.entries.first;
        final text = LogViewFormatter.formatEntry(entry);
        expect(text, isNotEmpty);
      });

      test('contains operation name', () {
        final log = _buildLog();
        final entry = log.entries.first; // seal
        expect(LogViewFormatter.formatEntry(entry), contains('seal'));
      });

      test('contains OK for success', () {
        final log = _buildLog();
        final seal = log.byOperation('seal').first;
        expect(LogViewFormatter.formatEntry(seal), contains('OK'));
      });

      test('contains FAIL for failure', () {
        final log = _buildLog();
        final verify = log.byOperation('verify').first;
        expect(LogViewFormatter.formatEntry(verify), contains('FAIL'));
      });

      test('contains filename when present', () {
        final log = _buildLog();
        final seal = log.byOperation('seal').first;
        expect(LogViewFormatter.formatEntry(seal), contains('report.pdf'));
      });

      test('contains message when present', () {
        final log = _buildLog();
        final verify = log.byOperation('verify').first;
        expect(LogViewFormatter.formatEntry(verify), contains('HMAC mismatch'));
      });

      test('contains duration in ms when includeDuration = true', () {
        final log = _buildLog();
        final seal = log.byOperation('seal').first;
        expect(
          LogViewFormatter.formatEntry(seal, includeDuration: true),
          contains('42ms'),
        );
      });

      test('omits duration when includeDuration = false', () {
        final log = _buildLog();
        final seal = log.byOperation('seal').first;
        expect(
          LogViewFormatter.formatEntry(seal, includeDuration: false),
          isNot(contains('ms')),
        );
      });

      test('handles entry with no filename or message gracefully', () {
        final log = _buildLog();
        final extract = log.byOperation('extract').first;
        // extract has filename but no message — should not throw.
        expect(() => LogViewFormatter.formatEntry(extract), returnsNormally);
      });
    });

    // -----------------------------------------------------------------------
    // dump
    // -----------------------------------------------------------------------
    group('dump', () {
      test('returns a non-empty string for a non-empty log', () {
        final log = _buildLog();
        expect(LogViewFormatter.dump(log), isNotEmpty);
      });

      test('contains one line per entry', () {
        final log = _buildLog();
        final lines = LogViewFormatter.dump(
          log,
        ).split('\n').where((l) => l.isNotEmpty).toList();
        expect(lines.length, 3);
      });

      test('each line contains the operation name', () {
        final log = _buildLog();
        final dumped = LogViewFormatter.dump(log);
        expect(dumped, contains('seal'));
        expect(dumped, contains('verify'));
        expect(dumped, contains('extract'));
      });

      test('each line contains OK or FAIL', () {
        final log = _buildLog();
        final lines = LogViewFormatter.dump(
          log,
        ).split('\n').where((l) => l.isNotEmpty).toList();
        for (final line in lines) {
          expect(line.contains('OK') || line.contains('FAIL'), isTrue);
        }
      });

      test('each line starts with an ISO-8601 timestamp', () {
        final log = _buildLog();
        final lines = LogViewFormatter.dump(
          log,
        ).split('\n').where((l) => l.isNotEmpty).toList();
        for (final line in lines) {
          expect(
            RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}').hasMatch(line),
            isTrue,
            reason: 'Line does not start with ISO-8601: $line',
          );
        }
      });

      test('returns empty string for an empty log', () {
        final log = HistoryLog();
        expect(LogViewFormatter.dump(log).trim(), isEmpty);
      });
    });

    // -----------------------------------------------------------------------
    // filterByLevel
    // -----------------------------------------------------------------------
    group('filterByLevel', () {
      test('LogLevel.info returns only successful entries', () {
        final log = _buildLog();
        final infos = LogViewFormatter.filterByLevel(log, level: LogLevel.info);
        expect(infos.every((e) => e.success), isTrue);
      });

      test('LogLevel.error returns only failed entries', () {
        final log = _buildLog();
        final errors = LogViewFormatter.filterByLevel(
          log,
          level: LogLevel.error,
        );
        expect(errors.every((e) => !e.success), isTrue);
      });

      test('info count + error count equals total entry count', () {
        final log = _buildLog();
        final infos = LogViewFormatter.filterByLevel(log, level: LogLevel.info);
        final errors = LogViewFormatter.filterByLevel(
          log,
          level: LogLevel.error,
        );
        expect(infos.length + errors.length, log.entries.length);
      });

      test('returns empty list when no entries match the level', () {
        final log = HistoryLog();
        log.record(operation: 'seal', success: true);
        // No failures, so error filter should be empty.
        final errors = LogViewFormatter.filterByLevel(
          log,
          level: LogLevel.error,
        );
        expect(errors, isEmpty);
      });

      test('filtered entries belong to the original log', () {
        final log = _buildLog();
        final infos = LogViewFormatter.filterByLevel(log, level: LogLevel.info);
        for (final entry in infos) {
          expect(log.entries, contains(entry));
        }
      });
    });

    // -----------------------------------------------------------------------
    // FormattedLogLine
    // -----------------------------------------------------------------------
    group('FormattedLogLine', () {
      test('stores all four fields', () {
        final line = FormattedLogLine(
          timestamp: DateTime.utc(2024, 1, 1),
          level: LogLevel.info,
          operation: 'seal',
          text: 'some text',
        );
        expect(line.timestamp, DateTime.utc(2024, 1, 1));
        expect(line.level, LogLevel.info);
        expect(line.operation, 'seal');
        expect(line.text, 'some text');
      });
    });

    // -----------------------------------------------------------------------
    // LogLevel enum
    // -----------------------------------------------------------------------
    group('LogLevel', () {
      test('info and error are distinct values', () {
        expect(LogLevel.info, isNot(LogLevel.error));
      });

      test('values list contains both levels', () {
        expect(LogLevel.values, containsAll([LogLevel.info, LogLevel.error]));
      });
    });
  });
}
