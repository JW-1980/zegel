import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

/// Creates a 32-byte test master key (0x00...01).
Uint8List _testKey() {
  final key = Uint8List(32);
  key[31] = 0x01;
  return key;
}

/// Creates a 32-byte key with all bytes set to a value.
Uint8List _filledKey(int value) {
  return Uint8List.fromList(List.filled(32, value));
}

void main() {
  group('Shamir Secret Sharing', () {
    group('GF(256) arithmetic', () {
      test('multiply: 0 * x = 0 for any x', () {
        for (var x = 0; x < 256; x++) {
          expect(ShamirSecretSharing.gfMultiply(0, x), equals(0),
              reason: '0 * $x should equal 0');
        }
      });

      test('multiply: x * 0 = 0 for any x', () {
        for (var x = 0; x < 256; x++) {
          expect(ShamirSecretSharing.gfMultiply(x, 0), equals(0),
              reason: '$x * 0 should equal 0');
        }
      });

      test('multiply: 1 * x = x for any x', () {
        for (var x = 0; x < 256; x++) {
          expect(ShamirSecretSharing.gfMultiply(1, x), equals(x),
              reason: '1 * $x should equal $x');
        }
      });

      test('multiply: x * 1 = x for any x', () {
        for (var x = 0; x < 256; x++) {
          expect(ShamirSecretSharing.gfMultiply(x, 1), equals(x),
              reason: '$x * 1 should equal $x');
        }
      });

      test('multiply: result is always in range [0, 255]', () {
        for (var a = 0; a < 256; a += 17) {
          for (var b = 0; b < 256; b += 13) {
            final result = ShamirSecretSharing.gfMultiply(a, b);
            expect(result, greaterThanOrEqualTo(0));
            expect(result, lessThanOrEqualTo(255));
          }
        }
      });

      test('multiply: commutative (a * b = b * a)', () {
        for (var a = 0; a < 256; a += 7) {
          for (var b = 0; b < 256; b += 11) {
            expect(
              ShamirSecretSharing.gfMultiply(a, b),
              equals(ShamirSecretSharing.gfMultiply(b, a)),
              reason: '$a * $b should equal $b * $a',
            );
          }
        }
      });

      test('inverse: a * inverse(a) = 1 for all non-zero a', () {
        for (var a = 1; a < 256; a++) {
          final inv = ShamirSecretSharing.gfInverse(a);
          final product = ShamirSecretSharing.gfMultiply(a, inv);
          expect(product, equals(1),
              reason: '$a * inverse($a) = $a * $inv = $product, expected 1');
        }
      });

      test('inverse: inverse of 1 is 1', () {
        expect(ShamirSecretSharing.gfInverse(1), equals(1));
      });

      test('inverse: inverse(inverse(a)) = a for all non-zero a', () {
        for (var a = 1; a < 256; a++) {
          final inv = ShamirSecretSharing.gfInverse(a);
          final invInv = ShamirSecretSharing.gfInverse(inv);
          expect(invInv, equals(a),
              reason: 'inverse(inverse($a)) should equal $a');
        }
      });

      test('inverse: result is always in range [1, 255]', () {
        for (var a = 1; a < 256; a++) {
          final inv = ShamirSecretSharing.gfInverse(a);
          expect(inv, greaterThanOrEqualTo(1));
          expect(inv, lessThanOrEqualTo(255));
        }
      });
    });

    group('split and reconstruct', () {
      test('split 32-byte key with threshold=2, total=3', () {
        final key = _testKey();
        final shares = ShamirSecretSharing.split(key, 2, 3);

        expect(shares.length, equals(3));
        for (final share in shares) {
          expect(share.length, equals(33),
              reason:
                  'Each share should be 33 bytes (1 x-coord + 32 y-values)');
        }
      });

      test('reconstruct with any 2 of 3 shares -> correct key', () {
        final key = _testKey();
        final shares = ShamirSecretSharing.split(key, 2, 3);

        // Try all combinations of 2 shares
        final combinations = [
          [shares[0], shares[1]],
          [shares[0], shares[2]],
          [shares[1], shares[2]],
        ];

        for (var i = 0; i < combinations.length; i++) {
          final reconstructed =
              ShamirSecretSharing.reconstruct(combinations[i], 2);
          expect(reconstructed, equals(key),
              reason: 'Combination $i should reconstruct correctly');
        }
      });

      test('reconstruct with all 3 shares -> correct key', () {
        final key = _testKey();
        final shares = ShamirSecretSharing.split(key, 2, 3);

        final reconstructed = ShamirSecretSharing.reconstruct(shares, 2);
        expect(reconstructed, equals(key));
      });

      test('reconstruct with only 1 share (< threshold) -> wrong key', () {
        final key = _testKey();
        final shares = ShamirSecretSharing.split(key, 2, 3);

        // Reconstructing with fewer shares than threshold should yield wrong key
        // (technically, you need to pass threshold to reconstruct, but passing
        // 1 share with threshold 1 would be a degenerate case)
        // The spec says: "fewer than M shares reveal no information"
        // This means using 1 share to guess the key should not work.
        // We test by passing insufficient shares to Lagrange interpolation.
        final reconstructed = ShamirSecretSharing.reconstruct([shares[0]], 1);
        // With threshold=1 (trivial case), the secret = share value at that point,
        // which is NOT the original key (key is at x=0, share is at x=1+)
        // Actually with M=1, the polynomial is f(x) = secret (constant),
        // so f(1) = secret. If we split with M=2 but try to reconstruct
        // with M=1 using one share, we do Lagrange interp at x=0 with
        // a single point, which just gives f(xi) = yi at x=0, which is wrong
        // because the actual polynomial is degree 1.
        expect(reconstructed, isNot(equals(key)),
            reason:
                'Reconstructing with fewer shares than threshold should produce wrong key');
      });

      test('split with threshold=3, total=5 -> reconstruct with shares 1,3,5',
          () {
        final key = _testKey();
        final shares = ShamirSecretSharing.split(key, 3, 5);

        expect(shares.length, equals(5));

        // Use shares at indices 0, 2, 4 (x-coordinates 1, 3, 5)
        final selectedShares = [shares[0], shares[2], shares[4]];
        final reconstructed =
            ShamirSecretSharing.reconstruct(selectedShares, 3);
        expect(reconstructed, equals(key));
      });

      test('split with threshold=5, total=5 (all shares required)', () {
        final key = _testKey();
        final shares = ShamirSecretSharing.split(key, 5, 5);

        expect(shares.length, equals(5));

        // All 5 shares needed
        final reconstructed = ShamirSecretSharing.reconstruct(shares, 5);
        expect(reconstructed, equals(key));

        // 4 of 5 should fail
        final partial = shares.sublist(0, 4);
        final wrongResult = ShamirSecretSharing.reconstruct(partial, 4);
        // With threshold=5, using 4 shares with threshold=4 gives wrong result
        // because the polynomial is degree 4, not 3
        expect(wrongResult, isNot(equals(key)));
      });
    });

    group('share format', () {
      test('each share is exactly 33 bytes', () {
        final key = _testKey();
        final shares = ShamirSecretSharing.split(key, 3, 5);

        for (var i = 0; i < shares.length; i++) {
          expect(shares[i].length, equals(33),
              reason: 'Share $i should be 33 bytes');
        }
      });

      test('x-coordinates are unique values 1..N', () {
        final key = _testKey();
        final shares = ShamirSecretSharing.split(key, 3, 5);

        final xCoords = shares.map((s) => s[0]).toSet();
        expect(xCoords.length, equals(5),
            reason: 'All x-coordinates should be unique');

        for (var i = 0; i < 5; i++) {
          expect(shares[i][0], equals(i + 1),
              reason: 'Share $i x-coordinate should be ${i + 1}');
        }
      });

      test('x-coordinates are non-zero', () {
        final key = _testKey();
        final shares = ShamirSecretSharing.split(key, 2, 3);

        for (final share in shares) {
          expect(share[0], isNot(equals(0)),
              reason: 'x-coordinate must not be 0 (that is the secret)');
        }
      });
    });

    group('various M/N combinations', () {
      test('M=2, N=2', () {
        final key = _filledKey(0xAB);
        final shares = ShamirSecretSharing.split(key, 2, 2);
        final reconstructed = ShamirSecretSharing.reconstruct(shares, 2);
        expect(reconstructed, equals(key));
      });

      test('M=2, N=10', () {
        final key = _filledKey(0xCD);
        final shares = ShamirSecretSharing.split(key, 2, 10);

        // Any 2 of 10 should work
        for (var i = 0; i < 10; i++) {
          for (var j = i + 1; j < 10; j++) {
            final reconstructed =
                ShamirSecretSharing.reconstruct([shares[i], shares[j]], 2);
            expect(reconstructed, equals(key),
                reason: 'Shares $i and $j should reconstruct key');
          }
        }
      });

      test('M=3, N=7', () {
        final key = _filledKey(0xEF);
        final shares = ShamirSecretSharing.split(key, 3, 7);

        // Pick 3 non-adjacent shares
        final reconstructed = ShamirSecretSharing.reconstruct(
            [shares[0], shares[3], shares[6]], 3);
        expect(reconstructed, equals(key));
      });

      test('M=N=1 (degenerate case) throws because threshold must be >= 2', () {
        final key = _filledKey(0x42);
        expect(
          () => ShamirSecretSharing.split(key, 1, 1),
          throwsA(isA<ArgumentError>()),
          reason: 'Threshold must be >= 2 for Shamir SSS',
        );
      });
    });

    group('round-trip with various keys', () {
      test('key with all zeros', () {
        final key = Uint8List(32);
        final shares = ShamirSecretSharing.split(key, 2, 3);
        final reconstructed =
            ShamirSecretSharing.reconstruct([shares[0], shares[1]], 2);
        expect(reconstructed, equals(key));
      });

      test('key with all 0xFF', () {
        final key = _filledKey(0xFF);
        final shares = ShamirSecretSharing.split(key, 2, 3);
        final reconstructed =
            ShamirSecretSharing.reconstruct([shares[0], shares[2]], 2);
        expect(reconstructed, equals(key));
      });

      test('key with sequential bytes', () {
        final key = Uint8List.fromList(List.generate(32, (i) => i));
        final shares = ShamirSecretSharing.split(key, 3, 5);
        final reconstructed = ShamirSecretSharing.reconstruct(
            [shares[1], shares[2], shares[4]], 3);
        expect(reconstructed, equals(key));
      });

      test('key with alternating bytes', () {
        final key = Uint8List.fromList(
            List.generate(32, (i) => i.isEven ? 0xAA : 0x55));
        final shares = ShamirSecretSharing.split(key, 2, 4);
        final reconstructed =
            ShamirSecretSharing.reconstruct([shares[1], shares[3]], 2);
        expect(reconstructed, equals(key));
      });
    });

    group('edge cases', () {
      test('threshold must be <= total', () {
        final key = _testKey();
        expect(
          () => ShamirSecretSharing.split(key, 4, 3),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('total must be >= 1', () {
        final key = _testKey();
        expect(
          () => ShamirSecretSharing.split(key, 1, 0),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('secret must be 32 bytes', () {
        final shortSecret = Uint8List(16);
        expect(
          () => ShamirSecretSharing.split(shortSecret, 2, 3),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('shares are different from each other', () {
        final key = _testKey();
        final shares = ShamirSecretSharing.split(key, 2, 5);

        // All shares should be different (y-values differ)
        for (var i = 0; i < shares.length; i++) {
          for (var j = i + 1; j < shares.length; j++) {
            expect(shares[i], isNot(equals(shares[j])),
                reason: 'Shares $i and $j should differ');
          }
        }
      });

      test('large N: threshold=3, total=20', () {
        final key = _testKey();
        final shares = ShamirSecretSharing.split(key, 3, 20);
        expect(shares.length, equals(20));

        final reconstructed = ShamirSecretSharing.reconstruct(
            [shares[5], shares[10], shares[15]], 3);
        expect(reconstructed, equals(key));
      });
    });

    group('determinism', () {
      test('split is NOT deterministic (uses random coefficients)', () {
        final key = _testKey();
        final shares1 = ShamirSecretSharing.split(key, 2, 3);
        final shares2 = ShamirSecretSharing.split(key, 2, 3);

        // It is theoretically possible but astronomically unlikely
        // for two random polynomials to produce the same shares
        // We check by comparing the y-values
        final yValues1 = shares1.map((s) => s.sublist(1)).toList();
        final yValues2 = shares2.map((s) => s.sublist(1)).toList();
        var diffFound = false;
        for (var i = 0; i < 3; i++) {
          for (var j = 0; j < 32; j++) {
            if (yValues1[i][j] != yValues2[i][j]) {
              diffFound = true;
              break;
            }
          }
          if (diffFound) break;
        }
        expect(diffFound, isTrue,
            reason: 'Two independent splits should produce different shares');
      });

      test('reconstruction is deterministic', () {
        final key = _testKey();
        final shares = ShamirSecretSharing.split(key, 2, 3);

        final result1 =
            ShamirSecretSharing.reconstruct([shares[0], shares[1]], 2);
        final result2 =
            ShamirSecretSharing.reconstruct([shares[0], shares[1]], 2);

        expect(result1, equals(result2));
        expect(result1, equals(key));
      });
    });
  });
}
