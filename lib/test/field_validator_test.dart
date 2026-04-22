import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('FieldValidator', () {
    group('RequiredRule', () {
      const rule = RequiredRule();

      test('returns error for null', () {
        expect(rule.check(null), isNotNull);
      });

      test('returns error for empty string', () {
        expect(rule.check(''), isNotNull);
      });

      test('returns null for non-empty string', () {
        expect(rule.check('a'), isNull);
      });

      test('default message is human-readable', () {
        expect(rule.check(''), contains('required'));
      });

      test('accepts custom message', () {
        const custom = RequiredRule(message: 'Do not leave blank');
        expect(custom.check(''), 'Do not leave blank');
      });

      test('passes for whitespace-only (not empty)', () {
        // RequiredRule only checks isEmpty; trimming is the caller's job.
        expect(rule.check('   '), isNull);
      });
    });

    group('MinLengthRule', () {
      const rule = MinLengthRule(5);

      test('returns error for null', () {
        expect(rule.check(null), isNotNull);
      });

      test('returns error when value is shorter than limit', () {
        expect(rule.check('abc'), isNotNull);
      });

      test('returns error when value is exactly one short', () {
        expect(rule.check('abcd'), isNotNull);
      });

      test('returns null when value meets the minimum', () {
        expect(rule.check('abcde'), isNull);
      });

      test('returns null when value exceeds the minimum', () {
        expect(rule.check('abcdefgh'), isNull);
      });

      test('default message mentions the length', () {
        expect(rule.check('ab'), contains('5'));
      });

      test('accepts custom message', () {
        const custom = MinLengthRule(3, message: 'Too short!');
        expect(custom.check('ab'), 'Too short!');
      });
    });

    group('MaxLengthRule', () {
      const rule = MaxLengthRule(10);

      test('returns null for null value', () {
        expect(rule.check(null), isNull);
      });

      test('returns null when value is exactly at the limit', () {
        expect(rule.check('1234567890'), isNull);
      });

      test('returns null when value is shorter than the limit', () {
        expect(rule.check('abc'), isNull);
      });

      test('returns error when value exceeds the limit', () {
        expect(rule.check('12345678901'), isNotNull);
      });

      test('default message mentions the length', () {
        expect(rule.check('x' * 11), contains('10'));
      });

      test('accepts custom message', () {
        const custom = MaxLengthRule(5, message: 'Way too long');
        expect(custom.check('toolongvalue'), 'Way too long');
      });
    });

    group('PatternRule', () {
      final rule = PatternRule(RegExp(r'^\d+$'), message: 'Digits only');

      test('returns null for null value', () {
        expect(rule.check(null), isNull);
      });

      test('returns null when pattern matches', () {
        expect(rule.check('12345'), isNull);
      });

      test('returns error when pattern does not match', () {
        expect(rule.check('123abc'), 'Digits only');
      });

      test('returns error for empty string when pattern requires content', () {
        expect(rule.check(''), 'Digits only');
      });

      test('uses default message when none supplied', () {
        final r = PatternRule(RegExp(r'^[a-z]+$'));
        expect(r.check('ABC'), isNotNull);
        expect(r.message, 'Invalid format');
      });
    });

    group('HexKeyRule', () {
      const rule = HexKeyRule(); // default 32 bytes => 64 hex chars

      final validKey = 'a' * 64;

      test('returns null for null value', () {
        expect(rule.check(null), isNull);
      });

      test('returns null for valid 64-char hex key', () {
        expect(rule.check(validKey), isNull);
      });

      test('returns null for uppercase hex', () {
        expect(rule.check('A' * 64), isNull);
      });

      test('returns null for mixed-case hex', () {
        final mixed = ('aAbBcCdDeEfF01234567' * 4).substring(0, 64);
        expect(rule.check(mixed), isNull);
      });

      test('returns error when too short', () {
        expect(rule.check('a' * 63), isNotNull);
      });

      test('returns error when too long', () {
        expect(rule.check('a' * 65), isNotNull);
      });

      test('returns error when non-hex chars present', () {
        final bad = 'g${'a' * 63}';
        expect(rule.check(bad), isNotNull);
      });

      test('error message mentions expected char count', () {
        expect(rule.check('a' * 10), contains('64'));
      });

      test('custom bytes parameter adjusts expected length', () {
        const rule16 = HexKeyRule(bytes: 16); // 32 hex chars
        expect(rule16.check('a' * 32), isNull);
        expect(rule16.check('a' * 64), isNotNull);
      });

      test('accepts custom message', () {
        const custom = HexKeyRule(message: 'Bad key!');
        expect(custom.check('z'), 'Bad key!');
      });
    });

    group('EmailRule', () {
      const rule = EmailRule();

      test('returns null for null value', () {
        expect(rule.check(null), isNull);
      });

      test('returns null for empty string (field is not required)', () {
        expect(rule.check(''), isNull);
      });

      test('returns null for valid simple email', () {
        expect(rule.check('user@example.com'), isNull);
      });

      test('returns null for email with subdomains', () {
        expect(rule.check('user@mail.example.co.uk'), isNull);
      });

      test('returns null for email with plus tag', () {
        expect(rule.check('user+tag@example.com'), isNull);
      });

      test('returns null for email with dots in local part', () {
        expect(rule.check('first.last@example.com'), isNull);
      });

      test('returns error for missing at-sign', () {
        expect(rule.check('userexample.com'), isNotNull);
      });

      test('returns error for missing domain', () {
        expect(rule.check('user@'), isNotNull);
      });

      test('returns error for missing TLD', () {
        expect(rule.check('user@example'), isNotNull);
      });

      test('returns error for double at-sign', () {
        expect(rule.check('user@@example.com'), isNotNull);
      });

      test('uses expected default message', () {
        expect(rule.check('notanemail'), contains('email'));
      });

      test('accepts custom message', () {
        const custom = EmailRule(message: 'Invalid address');
        expect(custom.check('bad'), 'Invalid address');
      });
    });

    group('FieldValidator.validate pipeline', () {
      test('returns null when no rules are configured', () {
        const v = FieldValidator(<ValidatorRule>[]);
        expect(v.validate('anything'), isNull);
      });

      test('returns null when all rules pass', () {
        const v = FieldValidator(<ValidatorRule>[
          RequiredRule(),
          MinLengthRule(3),
          MaxLengthRule(10),
        ]);
        expect(v.validate('hello'), isNull);
      });

      test('returns first error and stops (short-circuit)', () {
        // RequiredRule should fire first; MinLengthRule is never reached.
        const v = FieldValidator(<ValidatorRule>[
          RequiredRule(),
          MinLengthRule(100),
        ]);
        final error = v.validate('');
        expect(error, isNotNull);
        expect(error, contains('required'));
      });

      test('second rule fires when first passes', () {
        const v = FieldValidator(<ValidatorRule>[
          RequiredRule(),
          MaxLengthRule(3),
        ]);
        final error = v.validate('toolong');
        expect(error, isNotNull);
        expect(error, contains('3'));
      });
    });

    group('FieldValidator.text factory', () {
      test('no options — allows anything', () {
        final v = FieldValidator.text();
        expect(v.validate(null), isNull);
        expect(v.validate(''), isNull);
        expect(v.validate('hello world'), isNull);
      });

      test('required:true fails on null', () {
        final v = FieldValidator.text(required: true);
        expect(v.validate(null), isNotNull);
        expect(v.validate(''), isNotNull);
        expect(v.validate('x'), isNull);
      });

      test('minLength enforced', () {
        final v = FieldValidator.text(minLength: 4);
        expect(v.validate('abc'), isNotNull);
        expect(v.validate('abcd'), isNull);
      });

      test('maxLength enforced', () {
        final v = FieldValidator.text(maxLength: 5);
        expect(v.validate('abcdef'), isNotNull);
        expect(v.validate('abcde'), isNull);
      });

      test('pattern enforced with custom message', () {
        final v = FieldValidator.text(
          pattern: RegExp(r'^\d+$'),
          patternMessage: 'Numbers only',
        );
        expect(v.validate('abc'), 'Numbers only');
        expect(v.validate('123'), isNull);
      });

      test('pattern uses default message when patternMessage is null', () {
        final v = FieldValidator.text(pattern: RegExp(r'^\d+$'));
        expect(v.validate('abc'), 'Invalid format');
      });

      test('combined required + minLength + maxLength + pattern', () {
        final v = FieldValidator.text(
          required: true,
          minLength: 3,
          maxLength: 8,
          pattern: RegExp(r'^[a-z]+$'),
        );
        expect(v.validate(null), isNotNull); // required fails
        expect(v.validate('ab'), isNotNull); // minLength fails
        expect(v.validate('toolongvalue'), isNotNull); // maxLength fails
        expect(v.validate('ABC'), isNotNull); // pattern fails
        expect(v.validate('hello'), isNull); // all pass
      });
    });
  });
}
