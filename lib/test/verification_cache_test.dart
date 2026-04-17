import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('VerificationCache', () {
    test('miss returns null, put/lookup round trip returns the entry', () {
      final cache = VerificationCache();
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      expect(cache.lookup(bytes), isNull);

      cache.put(fileBytes: bytes, valid: true, metadata: {'contentType': 'text/plain'});
      final entry = cache.lookup(bytes);
      expect(entry, isNotNull);
      expect(entry!.valid, isTrue);
      expect(entry.metadata['contentType'], 'text/plain');
    });

    test('LRU eviction drops the oldest entry when full', () {
      final cache = VerificationCache(maxEntries: 2);
      final a = Uint8List.fromList([1]);
      final b = Uint8List.fromList([2]);
      final c = Uint8List.fromList([3]);

      cache.put(fileBytes: a, valid: true);
      cache.put(fileBytes: b, valid: true);
      // Promote b by reading.
      cache.lookup(b);
      cache.put(fileBytes: c, valid: true);

      expect(cache.lookup(a), isNull); // evicted
      expect(cache.lookup(b), isNotNull);
      expect(cache.lookup(c), isNotNull);
    });

    test('ttl expiry causes lookups to return null', () {
      final cache = VerificationCache(ttl: const Duration(minutes: 5));
      final a = Uint8List.fromList([1]);
      cache.put(
        fileBytes: a,
        valid: true,
        cachedAt: DateTime.utc(2026, 1, 1, 12, 0, 0),
      );
      expect(
        cache.lookup(a, now: DateTime.utc(2026, 1, 1, 12, 3, 0)),
        isNotNull,
      );
      expect(
        cache.lookup(a, now: DateTime.utc(2026, 1, 1, 12, 10, 0)),
        isNull,
      );
    });

    test('invalidate removes the entry', () {
      final cache = VerificationCache();
      final a = Uint8List.fromList([1]);
      cache.put(fileBytes: a, valid: true);
      expect(cache.invalidate(a), isTrue);
      expect(cache.lookup(a), isNull);
      expect(cache.invalidate(a), isFalse);
    });

    test('encode/decodeJson round trip', () {
      final cache = VerificationCache(maxEntries: 8);
      cache.put(fileBytes: Uint8List.fromList([1, 2]), valid: true);
      cache.put(fileBytes: Uint8List.fromList([3, 4]), valid: false, failureReason: 'Merkle');
      final restored = VerificationCache.decodeJson(cache.encode());
      expect(restored.length, 2);
    });
  });
}
