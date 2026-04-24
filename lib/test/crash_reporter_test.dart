import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('CrashReporter', () {
    test('disabled reporter is a no-op', () {
      final reporter = CrashReporter(enabled: false);
      final result = reporter.report(Exception('boom'), StackTrace.current);
      expect(result, isNull);
      expect(reporter.reports, isEmpty);
    });

    test('enabled reporter records a scrubbed report', () {
      final reporter = CrashReporter(
        enabled: true,
        anonymizer: Anonymizer.fromHex('0102030405060708'),
      );
      final report = reporter.report(
        Exception('problem at alice@example.org'),
        StackTrace.fromString(
          '#0 main (file:///home/alice/workspace/foo.dart:10:1)',
        ),
        context: 'seal foo.pdf',
      );
      expect(report, isNotNull);
      expect(reporter.reports, hasLength(1));
      expect(report!.message, contains('problem at'));
      // Email should have been replaced.
      expect(report.stackTrace, isNot(contains('alice@example.org')));
    });

    test('runGuarded reports and rethrows', () {
      final reporter = CrashReporter(enabled: true);
      expect(
        () => reporter.runGuarded<int>(() {
          throw StateError('oops');
        }),
        throwsStateError,
      );
      expect(reporter.reports.length, 1);
    });

    test('encode/decode round trip', () {
      final reporter = CrashReporter(enabled: true)
        ..report(Exception('x'), StackTrace.fromString('frame'));
      final restored = CrashReporter.decodeJson(reporter.encode());
      expect(restored.enabled, isTrue);
      expect(restored.reports.length, 1);
    });
  });
}
