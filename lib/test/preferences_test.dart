import 'dart:io';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('ZegelPreferences', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('zegel_prefs_test_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('empty instance reports no keys', () {
      final prefs = ZegelPreferences.empty();
      expect(prefs.keys, isEmpty);
      expect(prefs.contains('x'), isFalse);
    });

    test('typed accessors round trip', () {
      final prefs = ZegelPreferences.empty();
      prefs.setString('s', 'hello');
      prefs.setInt('i', 42);
      prefs.setDouble('d', 3.14);
      prefs.setBool('b', true);
      prefs.setList('l', [1, 2, 3]);
      prefs.setMap('m', {'a': 1});

      expect(prefs.getString('s'), 'hello');
      expect(prefs.getInt('i'), 42);
      expect(prefs.getDouble('d'), 3.14);
      expect(prefs.getBool('b'), true);
      expect(prefs.getList('l'), [1, 2, 3]);
      expect(prefs.getMap('m'), {'a': 1});
    });

    test('defaults are returned for missing keys', () {
      final prefs = ZegelPreferences.empty();
      expect(prefs.getString('missing', defaultValue: 'fallback'), 'fallback');
      expect(prefs.getInt('missing', defaultValue: 7), 7);
      expect(prefs.getBool('missing', defaultValue: false), false);
    });

    test('save() writes to disk and load() reads it back', () {
      final path = '${tmp.path}/prefs.json';
      final prefs = ZegelPreferences.load(path);
      prefs.setString('lang', 'nl');
      prefs.setInt('block_size', 65536);
      prefs.save();

      final reloaded = ZegelPreferences.load(path);
      expect(reloaded.getString('lang'), 'nl');
      expect(reloaded.getInt('block_size'), 65536);
    });

    test('in-memory save() throws', () {
      final prefs = ZegelPreferences.empty();
      expect(() => prefs.save(), throwsStateError);
    });

    test('remove and clear work', () {
      final prefs = ZegelPreferences.empty();
      prefs.setString('a', '1');
      prefs.setString('b', '2');
      prefs.remove('a');
      expect(prefs.contains('a'), isFalse);
      expect(prefs.contains('b'), isTrue);
      prefs.clear();
      expect(prefs.keys, isEmpty);
    });
  });
}
