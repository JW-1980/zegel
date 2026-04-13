import 'dart:io';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('KeyBackupPlanner', () {
    late Directory tmp;
    late Directory destDir;
    late File key1;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('zegel_backup_test_');
      destDir = Directory('${tmp.path}/backups');
      key1 = File('${tmp.path}/key1.txt');
      key1.writeAsStringSync('secret-material-1');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('backupNow copies files and records manifest', () {
      final planner = KeyBackupPlanner(
        sourcePaths: [key1.path],
        destinationDirectory: destDir.path,
        retainSnapshots: 3,
      );
      final result = planner.backupNow(now: DateTime.utc(2026, 4, 12));
      expect(result.skipped, isFalse);
      expect(Directory(result.snapshotDirectory).existsSync(), isTrue);
      expect(result.manifest.containsKey('key1.txt'), isTrue);
      expect(result.manifest['key1.txt']!.length, 64);
    });

    test('backupNow skips when source is unchanged', () {
      final planner = KeyBackupPlanner(
        sourcePaths: [key1.path],
        destinationDirectory: destDir.path,
      );
      planner.backupNow(now: DateTime.utc(2026, 4, 12));
      final second = planner.backupNow(now: DateTime.utc(2026, 4, 13));
      expect(second.skipped, isTrue);
    });

    test('backupNow writes a fresh snapshot when source changes', () {
      final planner = KeyBackupPlanner(
        sourcePaths: [key1.path],
        destinationDirectory: destDir.path,
      );
      planner.backupNow(now: DateTime.utc(2026, 4, 12));
      key1.writeAsStringSync('changed-material');
      final second = planner.backupNow(now: DateTime.utc(2026, 4, 13));
      expect(second.skipped, isFalse);
      expect(planner.listSnapshots().length, 2);
    });

    test('retainSnapshots prunes the oldest backups', () {
      final planner = KeyBackupPlanner(
        sourcePaths: [key1.path],
        destinationDirectory: destDir.path,
        retainSnapshots: 2,
      );
      key1.writeAsStringSync('a');
      planner.backupNow(now: DateTime.utc(2026, 1, 1));
      key1.writeAsStringSync('b');
      planner.backupNow(now: DateTime.utc(2026, 1, 2));
      key1.writeAsStringSync('c');
      planner.backupNow(now: DateTime.utc(2026, 1, 3));
      expect(planner.listSnapshots().length, 2);
    });

    test('throws when source file is missing', () {
      final planner = KeyBackupPlanner(
        sourcePaths: ['${tmp.path}/nonexistent.key'],
        destinationDirectory: destDir.path,
      );
      expect(() => planner.backupNow(), throwsA(isA<FileSystemException>()));
    });
  });
}
