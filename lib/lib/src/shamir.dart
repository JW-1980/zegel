import 'dart:math';
import 'dart:typed_data';

/// Shamir's Secret Sharing over GF(256).
///
/// Splits a 32-byte secret (the master key) into N shares such that any M
/// shares (the threshold) can reconstruct the original secret, but fewer than
/// M shares reveal no information about it.
///
/// Arithmetic is performed in GF(2^8) with the irreducible polynomial
/// x^8 + x^4 + x^3 + x + 1 (0x11B), which is the same field used by AES.
class ShamirSecretSharing {
  ShamirSecretSharing._();

  /// AES irreducible polynomial for GF(256): x^8 + x^4 + x^3 + x + 1.
  static const int _irreducible = 0x11B;

  // ---------------------------------------------------------------------------
  // GF(256) arithmetic
  // ---------------------------------------------------------------------------

  /// Addition in GF(256) is XOR.
  static int gfAdd(int a, int b) => a ^ b;

  /// Subtraction in GF(256) is also XOR (same as addition).
  static int gfSub(int a, int b) => a ^ b;

  /// Multiplication in GF(256) using the Russian peasant algorithm.
  ///
  /// Performs carry-less multiplication with modular reduction by [_irreducible].
  static int gfMultiply(int a, int b) {
    int result = 0;
    int aa = a;
    int bb = b;
    while (bb > 0) {
      if (bb & 1 != 0) {
        result ^= aa;
      }
      aa <<= 1;
      if (aa & 0x100 != 0) {
        aa ^= _irreducible;
      }
      bb >>= 1;
    }
    return result & 0xFF;
  }

  /// Multiplicative inverse in GF(256) using Fermat's little theorem.
  ///
  /// In GF(2^8), a^(2^8 - 1) = 1 for all a != 0, so a^(-1) = a^254.
  ///
  /// Throws [ArgumentError] if [a] is 0 (zero has no multiplicative inverse).
  static int gfInverse(int a) {
    if (a == 0) {
      throw ArgumentError('Zero has no multiplicative inverse in GF(256)');
    }
    // a^(-1) = a^254 = a^(2+4+8+16+32+64+128)
    // Compute by repeated squaring.
    int result = a;
    for (int i = 0; i < 6; i++) {
      result = gfMultiply(result, result); // square
      result = gfMultiply(result, a); // multiply by a
    }
    result = gfMultiply(result, result); // final square (total exponent = 254)
    return result;
  }

  // ---------------------------------------------------------------------------
  // Secret splitting
  // ---------------------------------------------------------------------------

  /// Splits a [secret] into [totalShares] shares with a reconstruction
  /// [threshold].
  ///
  /// [secret] must be exactly 32 bytes.
  /// [threshold] must be >= 2 and <= [totalShares].
  /// [totalShares] must be <= 255 (x-coordinates 1..255).
  ///
  /// Returns a list of [totalShares] shares, each exactly 33 bytes:
  /// 1 byte x-coordinate (1..N) followed by 32 bytes of y-values.
  static List<Uint8List> split(
    Uint8List secret,
    int threshold,
    int totalShares,
  ) {
    if (secret.length != 32) {
      throw ArgumentError('Secret must be exactly 32 bytes');
    }
    if (threshold < 2 || threshold > totalShares) {
      throw ArgumentError(
        'Threshold must be >= 2 and <= totalShares '
        '(got threshold=$threshold, totalShares=$totalShares)',
      );
    }
    if (totalShares > 255) {
      throw ArgumentError('Total shares must be <= 255');
    }

    final random = Random.secure();

    // Initialize shares: shares[i] = [x-coordinate, y0, y1, ..., y31]
    final List<Uint8List> shares = List<Uint8List>.generate(totalShares, (i) {
      final share = Uint8List(33);
      share[0] = i + 1; // x-coordinate: 1..N
      return share;
    });

    // For each byte position of the secret
    for (int byteIdx = 0; byteIdx < 32; byteIdx++) {
      // Build a random polynomial of degree (threshold - 1).
      // coefficients[0] = secret byte (the constant term).
      final List<int> coefficients = List<int>.filled(threshold, 0);
      coefficients[0] = secret[byteIdx];
      for (int c = 1; c < threshold; c++) {
        coefficients[c] = random.nextInt(256);
      }

      // Evaluate the polynomial at x = 1..totalShares.
      for (int shareIdx = 0; shareIdx < totalShares; shareIdx++) {
        final int x = shareIdx + 1;
        shares[shareIdx][1 + byteIdx] = _evaluatePolynomial(coefficients, x);
      }
    }

    return shares;
  }

  /// Reconstructs the original 32-byte secret from [shares] using Lagrange
  /// interpolation at x = 0.
  ///
  /// [threshold] shares are required. Providing fewer than [threshold] shares
  /// will produce an incorrect (random-looking) result.
  ///
  /// Each share must be exactly 33 bytes: 1-byte x-coordinate + 32 y-values.
  ///
  /// Throws [ArgumentError] if:
  /// - Fewer than [threshold] shares are provided.
  /// - Any share has an invalid length (not 33 bytes).
  /// - Any share has a zero x-coordinate.
  /// - Duplicate x-coordinates are found among the shares.
  static Uint8List reconstruct(List<Uint8List> shares, int threshold) {
    if (shares.length < threshold) {
      throw ArgumentError(
        'Need at least $threshold shares, got ${shares.length}',
      );
    }

    // Validate share lengths.
    for (int i = 0; i < shares.length; i++) {
      if (shares[i].length != 33) {
        throw ArgumentError(
          'Share $i has invalid length ${shares[i].length} (expected 33)',
        );
      }
    }

    // Use exactly threshold shares.
    final List<Uint8List> usedShares = shares.sublist(0, threshold);

    // Extract x-coordinates.
    final List<int> xCoords = usedShares.map((s) => s[0]).toList();

    // Validate x-coordinates: no zeros, no duplicates.
    final Set<int> seen = <int>{};
    for (int i = 0; i < xCoords.length; i++) {
      if (xCoords[i] == 0) {
        throw ArgumentError('Share $i has invalid x-coordinate 0');
      }
      if (!seen.add(xCoords[i])) {
        throw ArgumentError('Duplicate x-coordinate ${xCoords[i]} in shares');
      }
    }

    final Uint8List secret = Uint8List(32);

    for (int byteIdx = 0; byteIdx < 32; byteIdx++) {
      // y-values for this byte position.
      final List<int> yValues = usedShares.map((s) => s[1 + byteIdx]).toList();

      // Lagrange interpolation at x = 0.
      int result = 0;
      for (int i = 0; i < threshold; i++) {
        int numerator = 1;
        int denominator = 1;
        for (int j = 0; j < threshold; j++) {
          if (i == j) continue;
          // numerator *= (0 - xCoords[j]) = xCoords[j] in GF(256) since -a = a
          numerator = gfMultiply(numerator, xCoords[j]);
          // denominator *= (xCoords[i] - xCoords[j]) = xCoords[i] ^ xCoords[j]
          denominator = gfMultiply(denominator, gfSub(xCoords[i], xCoords[j]));
        }
        // Lagrange basis polynomial value at x=0:
        // L_i(0) = numerator / denominator
        final int basis = gfMultiply(numerator, gfInverse(denominator));
        result = gfAdd(result, gfMultiply(yValues[i], basis));
      }
      secret[byteIdx] = result;
    }

    return secret;
  }

  /// Evaluates a polynomial over GF(256) at the given [x] value.
  ///
  /// Uses Horner's method: f(x) = c[n-1]*x^(n-1) + ... + c[1]*x + c[0]
  ///                              = (...((c[n-1]*x + c[n-2])*x + c[n-3])*x ...)*x + c[0]
  static int _evaluatePolynomial(List<int> coefficients, int x) {
    int result = 0;
    // Horner's method, starting from the highest degree.
    for (int i = coefficients.length - 1; i >= 0; i--) {
      result = gfAdd(gfMultiply(result, x), coefficients[i]);
    }
    return result;
  }
}
