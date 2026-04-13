import 'dart:io';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('WatchFolder', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('zegel_watch_test_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('initial scan discovers existing files', () {
      File('${tmp.path}/a.txt').writeAsStringSync('hello');
      final watcher = WatchFolder(directory: tmp.path);
      final initial = watcher.pollOnce();
      expect(initial.length, 1);
      expect(initial.first.path, contains('a.txt'));
    });

    test('subsequent polls only report new files', () {
      File('${tmp.path}/a.txt').writeAsStringSync('hello');
      final watcher = WatchFolder(directory: tmp.path);
      watcher.pollOnce();
      // Second poll on the same contents yields nothing.
      expect(watcher.pollOnce(), isEmpty);

      File('${tmp.path}/b.txt').writeAsStringSync('world');
      final second = watcher.pollOnce();
      expect(second.length, 1);
      expect(second.first.path, contains('b.txt'));
    });

    test('skipZegel ignores .zgl files when enabled', () {
      File('${tmp.path}/sealed.zgl').writeAsStringSync('binary');
      final watcher = WatchFolder(directory: tmp.path);
      expect(watcher.pollOnce(), isEmpty);
    });

    test('includeExtensions restricts discovered files', () {
      File('${tmp.path}/a.pdf').writeAsStringSync('x');
      File('${tmp.path}/b.txt').writeAsStringSync('y');
      final watcher = WatchFolder(
        directory: tmp.path,
        includeExtensions: {'pdf'},
      );
      final initial = watcher.pollOnce();
      expect(initial.length, 1);
      expect(initial.first.path, endsWith('a.pdf'));
    });
  });
}
