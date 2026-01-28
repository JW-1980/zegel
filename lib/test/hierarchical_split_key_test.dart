import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

/// Creates a 32-byte test master key (0x00...01).
Uint8List _testKey() {
  final key = Uint8List(32);
  key[31] = 0x01;
  return key;
}

void main() {
  group('HierarchicalSplitKey', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    group('split key with 2 levels', () {
      test('CONFIDENTIAL: 2/3, SECRET: 3/5', () {
        final levels = <HierarchicalLevel>[
          HierarchicalLevel(
            name: ZegelFormat.classificationConfidential,
            threshold: 2,
            totalShares: 3,
          ),
          HierarchicalLevel(
            name: ZegelFormat.classificationSecret,
            threshold: 3,
            totalShares: 5,
          ),
        ];

        final result = HierarchicalSplitKey.split(
          masterKey: masterKey,
          levels: levels,
        );

        expect(result, isNotNull);
        expect(result.levels.length, equals(2));

        // CONFIDENTIAL level: 3 shares
        final confLevel = result.levels[0];
        expect(confLevel.name, equals(ZegelFormat.classificationConfidential));
        expect(confLevel.shares.length, equals(3));
        expect(confLevel.threshold, equals(2));

        // SECRET level: 5 shares
        final secretLevel = result.levels[1];
        expect(secretLevel.name, equals(ZegelFormat.classificationSecret));
        expect(secretLevel.shares.length, equals(5));
        expect(secretLevel.threshold, equals(3));
      });
    });

    group('reconstruct at CONFIDENTIAL level', () {
      test('with sufficient shares', () {
        final levels = <HierarchicalLevel>[
          HierarchicalLevel(
            name: ZegelFormat.classificationConfidential,
            threshold: 2,
            totalShares: 3,
          ),
          HierarchicalLevel(
            name: ZegelFormat.classificationSecret,
            threshold: 3,
            totalShares: 5,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(
          masterKey: masterKey,
          levels: levels,
        );

        // Reconstruct at CONFIDENTIAL level using 2 of 3 shares
        final confShares = splitResult.levels[0].shares;
        final reconstructed = HierarchicalSplitKey.reconstruct(
          levelName: ZegelFormat.classificationConfidential,
          shares: [confShares[0], confShares[2]], // any 2 of 3
          threshold: 2,
        );

        // The reconstructed key should allow deriving the original master key
        // at the CONFIDENTIAL level
        expect(reconstructed, isNotNull);
        expect(reconstructed.length, equals(32),
            reason: 'Reconstructed key should be 32 bytes');
      });
    });

    group('reconstruct at SECRET level', () {
      test('with all level shares', () {
        final levels = <HierarchicalLevel>[
          HierarchicalLevel(
            name: ZegelFormat.classificationConfidential,
            threshold: 2,
            totalShares: 3,
          ),
          HierarchicalLevel(
            name: ZegelFormat.classificationSecret,
            threshold: 3,
            totalShares: 5,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(
          masterKey: masterKey,
          levels: levels,
        );

        // Reconstruct at SECRET level using 3 of 5 shares
        final secretShares = splitResult.levels[1].shares;
        final reconstructed = HierarchicalSplitKey.reconstruct(
          levelName: ZegelFormat.classificationSecret,
          shares: [secretShares[0], secretShares[2], secretShares[4]],
          threshold: 3,
        );

        expect(reconstructed, isNotNull);
        expect(reconstructed.length, equals(32));
      });
    });

    group('insufficient shares', () {
      test('fails reconstruction at any level', () {
        final levels = <HierarchicalLevel>[
          HierarchicalLevel(
            name: ZegelFormat.classificationConfidential,
            threshold: 2,
            totalShares: 3,
          ),
          HierarchicalLevel(
            name: ZegelFormat.classificationSecret,
            threshold: 3,
            totalShares: 5,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(
          masterKey: masterKey,
          levels: levels,
        );

        // CONFIDENTIAL needs 2, provide only 1
        expect(
          () => HierarchicalSplitKey.reconstruct(
            levelName: ZegelFormat.classificationConfidential,
            shares: [splitResult.levels[0].shares[0]],
            threshold: 2,
          ),
          throwsA(isA<ArgumentError>()),
          reason: 'Insufficient shares should throw ArgumentError',
        );

        // SECRET needs 3, provide only 2
        final secretShares = splitResult.levels[1].shares;
        expect(
          () => HierarchicalSplitKey.reconstruct(
            levelName: ZegelFormat.classificationSecret,
            shares: [secretShares[0], secretShares[1]],
            threshold: 3,
          ),
          throwsA(isA<ArgumentError>()),
          reason: 'Insufficient shares should throw ArgumentError',
        );
      });
    });

    group('share properties', () {
      test('each level shares are 33 bytes each', () {
        final levels = <HierarchicalLevel>[
          HierarchicalLevel(
            name: ZegelFormat.classificationConfidential,
            threshold: 2,
            totalShares: 3,
          ),
          HierarchicalLevel(
            name: ZegelFormat.classificationSecret,
            threshold: 3,
            totalShares: 5,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(
          masterKey: masterKey,
          levels: levels,
        );

        for (final level in splitResult.levels) {
          for (final share in level.shares) {
            expect(share.length, equals(33),
                reason:
                    'Each share should be 33 bytes (1 x-coord + 32 y-values)');
          }
        }
      });

      test('share x-coordinates are unique within each level', () {
        final levels = <HierarchicalLevel>[
          HierarchicalLevel(
            name: ZegelFormat.classificationConfidential,
            threshold: 2,
            totalShares: 5,
          ),
          HierarchicalLevel(
            name: ZegelFormat.classificationSecret,
            threshold: 3,
            totalShares: 5,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(
          masterKey: masterKey,
          levels: levels,
        );

        for (final level in splitResult.levels) {
          final xCoords = <int>{};
          for (final share in level.shares) {
            final x = share[0]; // First byte is the x-coordinate
            expect(xCoords.contains(x), isFalse,
                reason:
                    'x-coordinate $x should be unique within level ${level.name}');
            xCoords.add(x);
          }
        }
      });

      test('x-coordinates are non-zero', () {
        final levels = <HierarchicalLevel>[
          HierarchicalLevel(
            name: ZegelFormat.classificationConfidential,
            threshold: 2,
            totalShares: 3,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(
          masterKey: masterKey,
          levels: levels,
        );

        for (final share in splitResult.levels[0].shares) {
          expect(share[0], greaterThan(0),
              reason: 'x-coordinate must be > 0 (secret is at x=0)');
        }
      });
    });

    group('multi-level reconstruction consistency', () {
      test('different share combinations at same level reconstruct same key', () {
        final levels = <HierarchicalLevel>[
          HierarchicalLevel(
            name: ZegelFormat.classificationConfidential,
            threshold: 2,
            totalShares: 4,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(
          masterKey: masterKey,
          levels: levels,
        );

        final shares = splitResult.levels[0].shares;

        // Reconstruct using shares [0, 1]
        final key1 = HierarchicalSplitKey.reconstruct(
          levelName: ZegelFormat.classificationConfidential,
          shares: [shares[0], shares[1]],
          threshold: 2,
        );

        // Reconstruct using shares [2, 3]
        final key2 = HierarchicalSplitKey.reconstruct(
          levelName: ZegelFormat.classificationConfidential,
          shares: [shares[2], shares[3]],
          threshold: 2,
        );

        // Both should produce the same key
        expect(key1, equals(key2),
            reason:
                'Any valid share combination should reconstruct the same key');
      });

      test('single level with threshold=2, total=2', () {
        final levels = <HierarchicalLevel>[
          HierarchicalLevel(
            name: 'BASIC',
            threshold: 2,
            totalShares: 2,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(
          masterKey: masterKey,
          levels: levels,
        );

        final shares = splitResult.levels[0].shares;
        expect(shares.length, equals(2));

        final reconstructed = HierarchicalSplitKey.reconstruct(
          levelName: 'BASIC',
          shares: shares,
          threshold: 2,
        );

        expect(reconstructed.length, equals(32));
      });
    });

    group('edge cases', () {
      test('three levels', () {
        final levels = <HierarchicalLevel>[
          HierarchicalLevel(
            name: ZegelFormat.classificationInternal,
            threshold: 2,
            totalShares: 3,
          ),
          HierarchicalLevel(
            name: ZegelFormat.classificationConfidential,
            threshold: 3,
            totalShares: 5,
          ),
          HierarchicalLevel(
            name: ZegelFormat.classificationSecret,
            threshold: 4,
            totalShares: 7,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(
          masterKey: masterKey,
          levels: levels,
        );

        expect(splitResult.levels.length, equals(3));
        expect(splitResult.levels[0].shares.length, equals(3));
        expect(splitResult.levels[1].shares.length, equals(5));
        expect(splitResult.levels[2].shares.length, equals(7));
      });

      test('single level split', () {
        final levels = <HierarchicalLevel>[
          HierarchicalLevel(
            name: ZegelFormat.classificationConfidential,
            threshold: 3,
            totalShares: 5,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(
          masterKey: masterKey,
          levels: levels,
        );

        expect(splitResult.levels.length, equals(1));
        expect(splitResult.levels[0].shares.length, equals(5));
      });
    });
  });
}
