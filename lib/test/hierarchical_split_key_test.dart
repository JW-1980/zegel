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
        final levels = <ShareLevel>[
          ShareLevel(
            classification: ZegelFormat.classificationConfidential,
            threshold: 2,
            totalShares: 3,
          ),
          ShareLevel(
            classification: ZegelFormat.classificationSecret,
            threshold: 3,
            totalShares: 5,
          ),
        ];

        final result = HierarchicalSplitKey.split(masterKey, levels);

        expect(result, isNotNull);
        expect(result.sharesByLevel.length, equals(2));

        // CONFIDENTIAL level: 3 shares
        final confShares =
            result.sharesByLevel[ZegelFormat.classificationConfidential]!;
        expect(confShares.length, equals(3));

        // SECRET level: 5 shares
        final secretShares =
            result.sharesByLevel[ZegelFormat.classificationSecret]!;
        expect(secretShares.length, equals(5));
      });
    });

    group('reconstruct with all levels', () {
      test('with sufficient shares for both levels', () {
        final levels = <ShareLevel>[
          ShareLevel(
            classification: ZegelFormat.classificationConfidential,
            threshold: 2,
            totalShares: 3,
          ),
          ShareLevel(
            classification: ZegelFormat.classificationSecret,
            threshold: 3,
            totalShares: 5,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(masterKey, levels);

        // Provide sufficient shares for both levels
        final confShares =
            splitResult.sharesByLevel[ZegelFormat.classificationConfidential]!;
        final secretShares =
            splitResult.sharesByLevel[ZegelFormat.classificationSecret]!;

        final providedShares = <LevelShares>[
          LevelShares(
            classification: ZegelFormat.classificationConfidential,
            shares: [confShares[0], confShares[2]], // any 2 of 3
          ),
          LevelShares(
            classification: ZegelFormat.classificationSecret,
            shares: [
              secretShares[0],
              secretShares[2],
              secretShares[4],
            ], // any 3 of 5
          ),
        ];

        final reconstructed = HierarchicalSplitKey.reconstruct(
          providedShares,
          levels,
        );

        expect(reconstructed, isNotNull);
        expect(
          reconstructed.length,
          equals(32),
          reason: 'Reconstructed key should be 32 bytes',
        );
        expect(
          reconstructed,
          equals(masterKey),
          reason: 'Reconstructed key should match original master key',
        );
      });
    });

    group('insufficient shares', () {
      test('fails reconstruction when a level has too few shares', () {
        final levels = <ShareLevel>[
          ShareLevel(
            classification: ZegelFormat.classificationConfidential,
            threshold: 2,
            totalShares: 3,
          ),
          ShareLevel(
            classification: ZegelFormat.classificationSecret,
            threshold: 3,
            totalShares: 5,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(masterKey, levels);

        final confShares =
            splitResult.sharesByLevel[ZegelFormat.classificationConfidential]!;
        final secretShares =
            splitResult.sharesByLevel[ZegelFormat.classificationSecret]!;

        // CONFIDENTIAL needs 2, provide only 1
        expect(
          () => HierarchicalSplitKey.reconstruct(<LevelShares>[
            LevelShares(
              classification: ZegelFormat.classificationConfidential,
              shares: [confShares[0]], // only 1 of required 2
            ),
            LevelShares(
              classification: ZegelFormat.classificationSecret,
              shares: [secretShares[0], secretShares[1], secretShares[2]],
            ),
          ], levels),
          throwsA(isA<ArgumentError>()),
          reason: 'Insufficient shares should throw ArgumentError',
        );

        // SECRET needs 3, provide only 2
        expect(
          () => HierarchicalSplitKey.reconstruct(<LevelShares>[
            LevelShares(
              classification: ZegelFormat.classificationConfidential,
              shares: [confShares[0], confShares[1]],
            ),
            LevelShares(
              classification: ZegelFormat.classificationSecret,
              shares: [
                secretShares[0],
                secretShares[1],
              ], // only 2 of required 3
            ),
          ], levels),
          throwsA(isA<ArgumentError>()),
          reason: 'Insufficient shares should throw ArgumentError',
        );
      });
    });

    group('share properties', () {
      test('each level shares are 33 bytes each', () {
        final levels = <ShareLevel>[
          ShareLevel(
            classification: ZegelFormat.classificationConfidential,
            threshold: 2,
            totalShares: 3,
          ),
          ShareLevel(
            classification: ZegelFormat.classificationSecret,
            threshold: 3,
            totalShares: 5,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(masterKey, levels);

        for (final entry in splitResult.sharesByLevel.entries) {
          for (final share in entry.value) {
            expect(
              share.length,
              equals(33),
              reason: 'Each share should be 33 bytes (1 x-coord + 32 y-values)',
            );
          }
        }
      });

      test('share x-coordinates are unique within each level', () {
        final levels = <ShareLevel>[
          ShareLevel(
            classification: ZegelFormat.classificationConfidential,
            threshold: 2,
            totalShares: 5,
          ),
          ShareLevel(
            classification: ZegelFormat.classificationSecret,
            threshold: 3,
            totalShares: 5,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(masterKey, levels);

        for (final entry in splitResult.sharesByLevel.entries) {
          final xCoords = <int>{};
          for (final share in entry.value) {
            final x = share[0]; // First byte is the x-coordinate
            expect(
              xCoords.contains(x),
              isFalse,
              reason:
                  'x-coordinate $x should be unique within level ${entry.key}',
            );
            xCoords.add(x);
          }
        }
      });

      test('x-coordinates are non-zero', () {
        final levels = <ShareLevel>[
          ShareLevel(
            classification: ZegelFormat.classificationConfidential,
            threshold: 2,
            totalShares: 3,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(masterKey, levels);

        final shares =
            splitResult.sharesByLevel[ZegelFormat.classificationConfidential]!;
        for (final share in shares) {
          expect(
            share[0],
            greaterThan(0),
            reason: 'x-coordinate must be > 0 (secret is at x=0)',
          );
        }
      });
    });

    group('multi-level reconstruction consistency', () {
      test(
        'different share combinations at same level reconstruct same key',
        () {
          final levels = <ShareLevel>[
            ShareLevel(
              classification: ZegelFormat.classificationConfidential,
              threshold: 2,
              totalShares: 4,
            ),
          ];

          final splitResult = HierarchicalSplitKey.split(masterKey, levels);

          final shares = splitResult
              .sharesByLevel[ZegelFormat.classificationConfidential]!;

          // Reconstruct using shares [0, 1]
          final key1 = HierarchicalSplitKey.reconstruct(<LevelShares>[
            LevelShares(
              classification: ZegelFormat.classificationConfidential,
              shares: [shares[0], shares[1]],
            ),
          ], levels);

          // Reconstruct using shares [2, 3]
          final key2 = HierarchicalSplitKey.reconstruct(<LevelShares>[
            LevelShares(
              classification: ZegelFormat.classificationConfidential,
              shares: [shares[2], shares[3]],
            ),
          ], levels);

          // Both should produce the same key
          expect(
            key1,
            equals(key2),
            reason:
                'Any valid share combination should reconstruct the same key',
          );
        },
      );

      test('single level with threshold=2, total=2', () {
        final levels = <ShareLevel>[
          ShareLevel(classification: 'BASIC', threshold: 2, totalShares: 2),
        ];

        final splitResult = HierarchicalSplitKey.split(masterKey, levels);

        final shares = splitResult.sharesByLevel['BASIC']!;
        expect(shares.length, equals(2));

        final reconstructed = HierarchicalSplitKey.reconstruct(<LevelShares>[
          LevelShares(classification: 'BASIC', shares: shares),
        ], levels);

        expect(reconstructed.length, equals(32));
        expect(
          reconstructed,
          equals(masterKey),
          reason: 'Reconstructed key should match original master key',
        );
      });
    });

    group('edge cases', () {
      test('three levels', () {
        final levels = <ShareLevel>[
          ShareLevel(
            classification: ZegelFormat.classificationInternal,
            threshold: 2,
            totalShares: 3,
          ),
          ShareLevel(
            classification: ZegelFormat.classificationConfidential,
            threshold: 3,
            totalShares: 5,
          ),
          ShareLevel(
            classification: ZegelFormat.classificationSecret,
            threshold: 4,
            totalShares: 7,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(masterKey, levels);

        expect(splitResult.sharesByLevel.length, equals(3));
        expect(
          splitResult.sharesByLevel[ZegelFormat.classificationInternal]!.length,
          equals(3),
        );
        expect(
          splitResult
              .sharesByLevel[ZegelFormat.classificationConfidential]!
              .length,
          equals(5),
        );
        expect(
          splitResult.sharesByLevel[ZegelFormat.classificationSecret]!.length,
          equals(7),
        );
      });

      test('single level split', () {
        final levels = <ShareLevel>[
          ShareLevel(
            classification: ZegelFormat.classificationConfidential,
            threshold: 3,
            totalShares: 5,
          ),
        ];

        final splitResult = HierarchicalSplitKey.split(masterKey, levels);

        expect(splitResult.sharesByLevel.length, equals(1));
        expect(
          splitResult
              .sharesByLevel[ZegelFormat.classificationConfidential]!
              .length,
          equals(5),
        );
      });
    });
  });
}
