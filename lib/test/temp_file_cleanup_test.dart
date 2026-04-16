import 'dart:io';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('TempFileCleanup', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('zegel_tmp_cleanup_test_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('createTempFile tracks the newly created file', () {
      final cleanup = TempFileCleanup(directory: tmp.path, secureWipe: false);
      final path = cleanup.createTempFile('plaintext.bin');
      expect(File(path).existsSync(), isTrue);
      expect(cleanup.trackedCount, 1);
    });

    test('sweep deletes expired tracked files only', () async {
      final cleanup = TempFileCleanup(
        directory: tmp.path,
        maxAge: const Duration(minutes: 5),
        secureWipe: false,
      );
      final oldPath = cleanup.createTempFile('old.bin');
      await File(oldPath).setLastModified(
        DateTime.now().subtract(const Duration(minutes: 10)),
      );
      final freshPath = cleanup.createTempFile('fresh.bin');
      // Explicitly set the last modified time of the new file to NOW
      // to ensure no filesystem lag causes it to look old
      await File(freshPath).setLastModified(DateTime.now());

      final deleted = cleanup.sweep();
      expect(deleted, [oldPath]);
      expect(cleanup.trackedCount, 1);
      expect(File(oldPath).existsSync(), isFalse);
    });

    test('clearAll removes every tracked file', () {
      final cleanup = TempFileCleanup(directory: tmp.path, secureWipe: false);
      final a = cleanup.createTempFile('a.bin');
      final b = cleanup.createTempFile('b.bin');
      final count = cleanup.clearAll();
      expect(count, 2);
      expect(File(a).existsSync(), isFalse);
      expect(File(b).existsSync(), isFalse);
      expect(cleanup.trackedCount, 0);
    });

    test('secure wipe overwrites bytes before delete', () {
      final cleanup = TempFileCleanup(directory: tmp.path);
      final path = cleanup.createTempFile('secrets.bin');
      File(path).writeAsBytesSync(List.filled(256, 0xAB));
      final sizeBefore = File(path).lengthSync();
      expect(sizeBefore, 256);
      cleanup.clearAll();
      expect(File(path).existsSync(), isFalse);
    });
  });
}
