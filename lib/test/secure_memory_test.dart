import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('SecureMemory', () {
    test('wipe replaces the buffer contents with zeros', () {
      final buf = Uint8List.fromList(List.generate(32, (i) => i));
      SecureMemory.wipe(buf);
      expect(buf.every((b) => b == 0), isTrue);
    });

    test('wipe on empty buffer is a no-op', () {
      final buf = Uint8List(0);
      SecureMemory.wipe(buf);
      expect(buf.length, 0);
    });

    test('takeAndWipe returns a copy and zeros the source', () {
      final source = Uint8List.fromList([1, 2, 3, 4]);
      final copy = SecureMemory.takeAndWipe(source);
      expect(copy, [1, 2, 3, 4]);
      expect(source.every((b) => b == 0), isTrue);
      // Ensure copy is independent.
      copy[0] = 9;
      expect(source[0], 0);
    });

    test('constantTimeEquals handles equal and unequal buffers', () {
      expect(
        SecureMemory.constantTimeEquals([1, 2, 3], [1, 2, 3]),
        isTrue,
      );
      expect(
        SecureMemory.constantTimeEquals([1, 2, 3], [1, 2, 4]),
        isFalse,
      );
      expect(
        SecureMemory.constantTimeEquals([1, 2], [1, 2, 3]),
        isFalse,
      );
    });

    test('randomBytes returns correct length and rejects negatives', () {
      final r = SecureMemory.randomBytes(16);
      expect(r.length, 16);
      expect(() => SecureMemory.randomBytes(-1), throwsArgumentError);
    });
  });
}
