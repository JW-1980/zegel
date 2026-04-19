import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('MmapReader', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('mmap_reader_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------
    File _writeFile(String name, List<int> bytes) {
      final file = File('${tempDir.path}${Platform.pathSeparator}$name');
      file.writeAsBytesSync(bytes);
      return file;
    }

    // -----------------------------------------------------------------------
    // open
    // -----------------------------------------------------------------------
    group('open', () {
      test('opens an existing file and exposes its length', () {
        final file = _writeFile('sample.zgl', List<int>.generate(64, (i) => i));
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);
        expect(reader.length, 64);
      });

      test('exposes the absolute path', () {
        final file = _writeFile('path_test.bin', [1, 2, 3]);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);
        expect(reader.path, file.path);
      });

      test('throws FileSystemException for a non-existent file', () {
        expect(
          () => MmapReader.open('${tempDir.path}/does_not_exist.zgl'),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('opens an empty file with length 0', () {
        final file = _writeFile('empty.bin', []);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);
        expect(reader.length, 0);
      });
    });

    // -----------------------------------------------------------------------
    // read
    // -----------------------------------------------------------------------
    group('read', () {
      test('reads bytes at offset 0', () {
        final data = List<int>.generate(16, (i) => i * 2);
        final file = _writeFile('read_test.bin', data);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);

        final result = reader.read(0, 8);
        expect(result, Uint8List.fromList(data.sublist(0, 8)));
      });

      test('reads bytes at a non-zero offset', () {
        final data = List<int>.generate(32, (i) => i);
        final file = _writeFile('offset_test.bin', data);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);

        final result = reader.read(10, 5);
        expect(result, Uint8List.fromList(data.sublist(10, 15)));
      });

      test('reads the last byte of the file', () {
        final data = [0xAA, 0xBB, 0xCC, 0xDD];
        final file = _writeFile('last_byte.bin', data);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);

        final result = reader.read(3, 1);
        expect(result, [0xDD]);
      });

      test('returns a fresh Uint8List (not a shared view)', () {
        final data = List<int>.generate(10, (i) => i);
        final file = _writeFile('fresh.bin', data);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);

        final r1 = reader.read(0, 5);
        final r2 = reader.read(0, 5);
        // They should be equal in content but distinct objects.
        expect(r1, r2);
        expect(identical(r1, r2), isFalse);
      });

      test('throws RangeError when reading past end of file', () {
        final file = _writeFile('small.bin', [1, 2, 3]);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);

        expect(() => reader.read(0, 4), throwsA(isA<RangeError>()));
      });

      test('throws ArgumentError for negative offset', () {
        final file = _writeFile('neg_offset.bin', [1, 2, 3, 4]);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);

        expect(() => reader.read(-1, 2), throwsA(isA<ArgumentError>()));
      });

      test('throws ArgumentError for negative count', () {
        final file = _writeFile('neg_count.bin', [1, 2, 3, 4]);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);

        expect(() => reader.read(0, -1), throwsA(isA<ArgumentError>()));
      });

      test('reading zero bytes returns an empty Uint8List', () {
        final file = _writeFile('zero.bin', [5, 6, 7]);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);

        final result = reader.read(1, 0);
        expect(result.isEmpty, isTrue);
      });
    });

    // -----------------------------------------------------------------------
    // readHeader
    // -----------------------------------------------------------------------
    group('readHeader', () {
      test('returns the first N bytes of the file', () {
        final data = List<int>.generate(128, (i) => i % 256);
        final file = _writeFile('header_test.bin', data);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);

        final header = reader.readHeader(4);
        expect(header, Uint8List.fromList(data.sublist(0, 4)));
      });

      test('is equivalent to read(0, count)', () {
        final data = List<int>.generate(20, (i) => i + 100);
        final file = _writeFile('header_eq.bin', data);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);

        expect(reader.readHeader(8), reader.read(0, 8));
      });
    });

    // -----------------------------------------------------------------------
    // readBlocks
    // -----------------------------------------------------------------------
    group('readBlocks', () {
      test('yields all bytes when file is smaller than blockSize', () {
        final data = List<int>.generate(100, (i) => i);
        final file = _writeFile('small_blocks.bin', data);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);

        final chunks = reader.readBlocks(blockSize: 65536).toList();
        expect(chunks.length, 1);
        expect(chunks.first, Uint8List.fromList(data));
      });

      test('yields multiple chunks when file exceeds blockSize', () {
        final data = List<int>.generate(100, (i) => i);
        final file = _writeFile('multi_blocks.bin', data);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);

        final chunks = reader.readBlocks(blockSize: 30).toList();
        // 100 bytes / 30 = 3 full chunks + 1 partial (10 bytes)
        expect(chunks.length, 4);
        expect(chunks[0].length, 30);
        expect(chunks[1].length, 30);
        expect(chunks[2].length, 30);
        expect(chunks[3].length, 10);
      });

      test('concatenating all chunks equals the full file', () {
        final data = List<int>.generate(256, (i) => i);
        final file = _writeFile('concat_blocks.bin', data);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);

        final all = <int>[];
        for (final chunk in reader.readBlocks(blockSize: 50)) {
          all.addAll(chunk);
        }
        expect(all, data);
      });

      test('throws ArgumentError for blockSize <= 0', () {
        final file = _writeFile('bad_block.bin', [1, 2, 3]);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);

        expect(
          () => reader.readBlocks(blockSize: 0).toList(),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('yields no chunks for an empty file', () {
        final file = _writeFile('empty_blocks.bin', []);
        final reader = MmapReader.open(file.path);
        addTearDown(reader.close);

        final chunks = reader.readBlocks().toList();
        expect(chunks.isEmpty, isTrue);
      });
    });

    // -----------------------------------------------------------------------
    // close / StateError after close
    // -----------------------------------------------------------------------
    group('close', () {
      test('close is idempotent (calling twice does not throw)', () {
        final file = _writeFile('close_twice.bin', [1, 2, 3]);
        final reader = MmapReader.open(file.path);
        reader.close();
        expect(() => reader.close(), returnsNormally);
      });

      test('read throws StateError after close', () {
        final file = _writeFile('closed_read.bin', [1, 2, 3]);
        final reader = MmapReader.open(file.path);
        reader.close();
        expect(() => reader.read(0, 1), throwsA(isA<StateError>()));
      });

      test('readBlocks throws StateError after close', () {
        final file = _writeFile('closed_blocks.bin', [1, 2, 3]);
        final reader = MmapReader.open(file.path);
        reader.close();
        expect(
          () => reader.readBlocks().toList(),
          throwsA(isA<StateError>()),
        );
      });

      test('readHeader throws StateError after close', () {
        final file = _writeFile('closed_header.bin', [1, 2, 3]);
        final reader = MmapReader.open(file.path);
        reader.close();
        expect(() => reader.readHeader(1), throwsA(isA<StateError>()));
      });
    });
  });
}
