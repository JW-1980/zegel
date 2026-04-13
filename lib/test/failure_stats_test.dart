import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('FailureStats', () {
    test('classify maps common messages to their buckets', () {
      expect(
        FailureStats.classify('Merkle root mismatch'),
        FailureCategory.merkleMismatch,
      );
      expect(
        FailureStats.classify('GCM auth tag failure in block 3'),
        FailureCategory.authTagFailure,
      );
      expect(
        FailureStats.classify('file expired'),
        FailureCategory.expired,
      );
      expect(
        FailureStats.classify('File is corrupt or truncated'),
        FailureCategory.corruptFile,
      );
      expect(
        FailureStats.classify('Not a Zegel file: bad magic'),
        FailureCategory.badMagic,
      );
      expect(
        FailureStats.classify('completely unknown problem'),
        FailureCategory.other,
      );
    });

    test('record increments counts and stores samples', () {
      final stats = FailureStats(maxSamples: 3);
      stats.record('bad magic');
      stats.record('Merkle root mismatch');
      stats.record('GCM auth tag failure');
      stats.record('file expired');

      expect(stats.totalFailures, 4);
      expect(stats.samples.length, 3);
      // First sample ("bad magic") should have been dropped.
      expect(
        stats.samples.first.category,
        FailureCategory.merkleMismatch,
      );
    });

    test('topCategory returns the most frequent bucket', () {
      final stats = FailureStats();
      stats.record('Merkle mismatch');
      stats.record('Merkle mismatch');
      stats.record('file expired');
      expect(stats.topCategory(), FailureCategory.merkleMismatch);
    });

    test('encode/decode round trip', () {
      final stats = FailureStats();
      stats.record('bad magic');
      stats.record('Merkle root mismatch');
      final restored = FailureStats.decodeJson(stats.encode());
      expect(restored.totalFailures, 2);
      expect(
        restored.counts[FailureCategory.merkleMismatch],
        1,
      );
    });
  });
}
