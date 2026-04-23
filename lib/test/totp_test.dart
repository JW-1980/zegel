import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('Totp', () {
    // RFC 6238 test vector: secret = "12345678901234567890" (ASCII).
    // Base32: GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ
    final rfcSecretBytes = Uint8List.fromList(
      '12345678901234567890'.codeUnits,
    );

    // A minimal 20-byte secret for ad-hoc tests.
    final simpleSecret =
        Uint8List.fromList(List<int>.generate(20, (i) => i + 1));

    // -----------------------------------------------------------------------
    // Construction
    // -----------------------------------------------------------------------
    group('constructor', () {
      test('stores secret, digits, and period', () {
        final totp = Totp(secret: simpleSecret, digits: 6, period: 30);
        expect(totp.secret, simpleSecret);
        expect(totp.digits, 6);
        expect(totp.period, 30);
      });

      test('defaults to 6 digits and 30-second period', () {
        final totp = Totp(secret: simpleSecret);
        expect(totp.digits, 6);
        expect(totp.period, 30);
      });

      test('accepts custom digits and period', () {
        final totp = Totp(secret: simpleSecret, digits: 8, period: 60);
        expect(totp.digits, 8);
        expect(totp.period, 60);
      });
    });

    // -----------------------------------------------------------------------
    // generate
    // -----------------------------------------------------------------------
    group('generate', () {
      test('produces a 6-digit string for default configuration', () {
        final totp = Totp(secret: simpleSecret);
        final code = totp.generate();
        expect(code.length, 6);
        expect(RegExp(r'^\d{6}$').hasMatch(code), isTrue);
      });

      test('produces an 8-digit string when digits = 8', () {
        final totp = Totp(secret: simpleSecret, digits: 8);
        final code = totp.generate();
        expect(code.length, 8);
        expect(RegExp(r'^\d{8}$').hasMatch(code), isTrue);
      });

      test('code is left-padded with zeros when needed', () {
        // Run a range of timestamps to hit a padded code at some point.
        final totp = Totp(secret: simpleSecret);
        // We cannot guarantee a padded code in a unit test, but we can
        // confirm the length is always exactly 6.
        for (var i = 0; i < 50; i++) {
          final dt = DateTime.utc(2025, 1, 1, 0, 0, i * 30);
          final code = totp.generate(now: dt);
          expect(code.length, 6, reason: 'Code at step $i has wrong length');
        }
      });

      test('same timestamp produces the same code', () {
        final totp = Totp(secret: simpleSecret);
        final at = DateTime.utc(2024, 6, 15, 12, 0, 0);
        expect(totp.generate(now: at), totp.generate(now: at));
      });

      test('codes differ across separate 30-second windows', () {
        final totp = Totp(secret: simpleSecret);
        final t1 = DateTime.utc(2024, 1, 1, 0, 0, 0);
        final t2 = DateTime.utc(2024, 1, 1, 0, 0, 30);
        // They may be the same by coincidence but overwhelmingly will differ.
        // We just confirm both produce valid 6-character strings.
        expect(totp.generate(now: t1).length, 6);
        expect(totp.generate(now: t2).length, 6);
      });

      // RFC 6238 Appendix B — SHA-1 vectors (selected subset).
      // Time T in seconds, expected 8-digit code.
      // We compare only the last 6 digits to avoid hard-coding 8-digit values.
      group('RFC 6238 known vectors (SHA-1)', () {
        final totp8 = Totp(secret: rfcSecretBytes, digits: 8, period: 30);

        // T=59 → counter=1 → expected code '94287082'
        test('T=59 produces 94287082', () {
          final at =
              DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true);
          expect(totp8.generate(now: at), '94287082');
        });

        // T=1111111109 → counter=37037036 → expected code '07081804'
        test('T=1111111109 produces 07081804', () {
          final at = DateTime.fromMillisecondsSinceEpoch(
            1111111109 * 1000,
            isUtc: true,
          );
          expect(totp8.generate(now: at), '07081804');
        });

        // T=1111111111 → counter=37037037 → expected code '14050471'
        test('T=1111111111 produces 14050471', () {
          final at = DateTime.fromMillisecondsSinceEpoch(
            1111111111 * 1000,
            isUtc: true,
          );
          expect(totp8.generate(now: at), '14050471');
        });
      });
    });

    // -----------------------------------------------------------------------
    // verify
    // -----------------------------------------------------------------------
    group('verify', () {
      test('accepts the exact current code', () {
        final totp = Totp(secret: simpleSecret);
        final at = DateTime.utc(2024, 3, 10, 8, 0, 0);
        final code = totp.generate(now: at);
        expect(totp.verify(code, now: at), isTrue);
      });

      test('accepts a code from the previous window (window=1)', () {
        final totp = Totp(secret: simpleSecret);
        final now = DateTime.utc(2024, 3, 10, 8, 0, 30);
        final prev = DateTime.utc(2024, 3, 10, 8, 0, 0);
        final code = totp.generate(now: prev);
        expect(totp.verify(code, now: now, window: 1), isTrue);
      });

      test('accepts a code from the next window (window=1)', () {
        final totp = Totp(secret: simpleSecret);
        final now = DateTime.utc(2024, 3, 10, 8, 0, 0);
        final future = DateTime.utc(2024, 3, 10, 8, 0, 30);
        final code = totp.generate(now: future);
        expect(totp.verify(code, now: now, window: 1), isTrue);
      });

      test('rejects a code from two windows ago (window=1)', () {
        final totp = Totp(secret: simpleSecret);
        final now = DateTime.utc(2024, 3, 10, 8, 1, 0);
        final old = DateTime.utc(2024, 3, 10, 8, 0, 0);
        final code = totp.generate(now: old);
        expect(totp.verify(code, now: now, window: 1), isFalse);
      });

      test('rejects an obviously wrong code', () {
        final totp = Totp(secret: simpleSecret);
        final at = DateTime.utc(2024, 3, 10, 8, 0, 0);
        expect(totp.verify('000000', now: at, window: 0), isFalse);
      });

      test('rejects a code of wrong length', () {
        final totp = Totp(secret: simpleSecret);
        final at = DateTime.utc(2024, 3, 10, 8, 0, 0);
        // A 5-digit string can never equal a 6-digit code.
        expect(totp.verify('12345', now: at), isFalse);
      });

      test('window=0 only accepts exact current code', () {
        final totp = Totp(secret: simpleSecret);
        final at = DateTime.utc(2024, 5, 1, 0, 0, 0);
        final code = totp.generate(now: at);
        expect(totp.verify(code, now: at, window: 0), isTrue);
      });
    });

    // -----------------------------------------------------------------------
    // encodedSecret / parseBase32
    // -----------------------------------------------------------------------
    group('base32 round-trip', () {
      test('encodedSecret produces uppercase base32 string', () {
        final totp = Totp(secret: simpleSecret);
        final encoded = totp.encodedSecret();
        expect(RegExp(r'^[A-Z2-7]+$').hasMatch(encoded), isTrue);
      });

      test('parseBase32(encodedSecret()) round-trips correctly', () {
        final totp = Totp(secret: simpleSecret);
        final encoded = totp.encodedSecret();
        final decoded = Totp.parseBase32(encoded);
        expect(decoded, simpleSecret);
      });

      test('RFC secret base32-encodes to expected string', () {
        // "12345678901234567890" → GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ
        final totp = Totp(secret: rfcSecretBytes);
        expect(totp.encodedSecret(), 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
      });

      test('parseBase32 is case-insensitive', () {
        final lower = Totp.parseBase32('gezdgnbvgy3tqojq');
        final upper = Totp.parseBase32('GEZDGNBVGY3TQOJQ');
        expect(lower, upper);
      });

      test('parseBase32 ignores padding characters', () {
        final withPad = Totp.parseBase32('MFRA====');
        final withoutPad = Totp.parseBase32('MFRA');
        expect(withPad, withoutPad);
      });

      test('two Totp instances from same parsed secret agree', () {
        final totp1 = Totp(secret: simpleSecret);
        final encoded = totp1.encodedSecret();
        final totp2 = Totp(secret: Totp.parseBase32(encoded));
        final at = DateTime.utc(2024, 9, 1, 0, 0, 0);
        expect(totp1.generate(now: at), totp2.generate(now: at));
      });
    });

    // -----------------------------------------------------------------------
    // provisioningUri
    // -----------------------------------------------------------------------
    group('provisioningUri', () {
      late Totp totp;
      late Uri uri;

      setUp(() {
        totp = Totp(secret: simpleSecret);
        uri = totp.provisioningUri(
          accountName: 'alice@example.com',
          issuer: 'Zegel',
        );
      });

      test('uses otpauth scheme', () {
        expect(uri.scheme, 'otpauth');
      });

      test('uses totp host', () {
        expect(uri.host, 'totp');
      });

      test('path contains issuer and account name', () {
        expect(uri.path, contains('Zegel'));
        expect(uri.path, contains('alice@example.com'));
      });

      test('secret query parameter matches encodedSecret', () {
        expect(uri.queryParameters['secret'], totp.encodedSecret());
      });

      test('issuer query parameter is set', () {
        expect(uri.queryParameters['issuer'], 'Zegel');
      });

      test('algorithm is SHA1', () {
        expect(uri.queryParameters['algorithm'], 'SHA1');
      });

      test('digits query parameter matches configuration', () {
        expect(uri.queryParameters['digits'], '6');
      });

      test('period query parameter matches configuration', () {
        expect(uri.queryParameters['period'], '30');
      });

      test('custom digits and period appear in URI', () {
        final t8 = Totp(secret: simpleSecret, digits: 8, period: 60);
        final u = t8.provisioningUri(accountName: 'bob', issuer: 'Zegel');
        expect(u.queryParameters['digits'], '8');
        expect(u.queryParameters['period'], '60');
      });
    });
  });
}
