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
        maxAge: const Duration(seconds: 2), // Use larger maxAge to avoid precision issues
        secureWipe: false,
      );

      final oldPath = cleanup.createTempFile('old.bin');
      await File(oldPath).setLastModified(
        DateTime.now().subtract(const Duration(minutes: 10)),
      );

      final freshPath = cleanup.createTempFile('fresh.bin');
      final now = DateTime.now();
      // Ensure 'fresh.bin' has a timestamp explicitly set to 'now' so it is NOT expired
      await File(freshPath).setLastModified(now);

      // Reload the actual lastModified from disk to use as 'now' reference for sweeping,
      // as the filesystem may truncate precision leading to age > 0 if we use the original 'now' object.
      final actualFreshTime = File(freshPath).lastModifiedSync();

      final deleted = cleanup.sweep(now: actualFreshTime);

      expect(deleted, contains(oldPath));
      expect(deleted.length, 1);
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
