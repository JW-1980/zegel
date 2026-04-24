import 'dart:io';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('SecureDelete', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('zegel_shred_test_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('shredFile deletes the target and returns the byte count', () {
      final file = File('${tmp.path}/secret.bin');
      file.writeAsBytesSync(List<int>.filled(256, 0xAB));
      final bytes = SecureDelete.shredFile(file);
      expect(bytes, 256);
      expect(file.existsSync(), isFalse);
    });

    test('shredFile handles empty files', () {
      final file = File('${tmp.path}/empty.bin')..createSync();
      final bytes = SecureDelete.shredFile(file);
      expect(bytes, 0);
      expect(file.existsSync(), isFalse);
    });

    test('shredFile rejects passes < 1', () {
      final file = File('${tmp.path}/x.bin')..writeAsBytesSync(<int>[1, 2, 3]);
      expect(
        () => SecureDelete.shredFile(file, passes: 0),
        throwsArgumentError,
      );
    });

    test('shredFile throws for missing files', () {
      expect(
        () => SecureDelete.shredFile(File('${tmp.path}/nope.bin')),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('shredAll deletes every existing file in the iterable', () {
      final a = File('${tmp.path}/a.bin')..writeAsBytesSync(<int>[1, 2]);
      final b = File('${tmp.path}/b.bin')..writeAsBytesSync(<int>[3, 4, 5]);
      final total = SecureDelete.shredAll(<String>[a.path, b.path]);
      expect(total, 5);
      expect(a.existsSync(), isFalse);
      expect(b.existsSync(), isFalse);
    });

    test('shredDirectory recursively shreds a tree', () {
      final dir = Directory('${tmp.path}/tree')..createSync();
      File('${dir.path}/a.bin').writeAsBytesSync(<int>[1]);
      Directory('${dir.path}/sub').createSync();
      File('${dir.path}/sub/b.bin').writeAsBytesSync(<int>[2, 3]);
      final total = SecureDelete.shredDirectory(dir);
      expect(total, 3);
      expect(dir.existsSync(), isFalse);
    });
  });
}
