import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('HelpRegistry', () {
    test('register and lookup round trip', () {
      final reg = HelpRegistry()
        ..register(
          const HelpEntry(
            topic: 'seal',
            title: 'Seal',
            summary: 'Wraps a file in a tamper-proof container.',
            body: 'Long description',
          ),
        );
      final entry = reg.lookup('seal');
      expect(entry, isNotNull);
      expect(entry!.title, 'Seal');
    });

    test('topicsWithPrefix filters alphabetically', () {
      final reg = HelpRegistry.defaults();
      final verbs = reg.topicsWithPrefix('s');
      expect(verbs, contains('seal'));
      expect(verbs, contains('split-key'));
    });

    test('search returns ranked results', () {
      final reg = HelpRegistry.defaults();
      final results = reg.search('Merkle');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.topic, 'merkle-root');
    });

    test('defaults include a baseline of topics', () {
      final reg = HelpRegistry.defaults();
      expect(reg.length, greaterThanOrEqualTo(4));
      expect(reg.lookup('seal'), isNotNull);
      expect(reg.lookup('verify'), isNotNull);
    });
  });
}
