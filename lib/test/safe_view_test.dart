import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('SafeView', () {
    test('obscures middle of a long value', () {
      const key = '0123456789abcdef0123456789abcdef';
      final obscured = SafeView.obscure(key);
      expect(obscured.substring(0, 4), '0123');
      expect(obscured.endsWith('cdef'), isTrue);
      expect(obscured.contains('•'), isTrue);
    });

    test('fully masks a short value', () {
      final obscured = SafeView.obscure('abc');
      expect(obscured, '•••');
    });

    test('obscureFully hides everything', () {
      final out = SafeView.obscureFully('secret');
      expect(out, '••••••');
    });

    test('regions describe head/middle/tail spans', () {
      final regions = SafeView.regions('abcdefghijk');
      expect(regions.length, 3);
      expect(regions.first.visible, isTrue);
      expect(regions.first.start, 0);
      expect(regions.first.end, 4);
      expect(regions[1].visible, isFalse);
      expect(regions.last.visible, isTrue);
    });

    test('rejects negative visible counts', () {
      expect(
        () => SafeView.obscure('abc', visibleHead: -1),
        throwsArgumentError,
      );
    });
  });
}
