import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('PiiDetector', () {
    test('detects email addresses', () {
      final matches = PiiDetector.scan('Contact alice@example.com for info.');
      expect(matches.length, 1);
      expect(matches.first.category, PiiCategory.email);
      expect(matches.first.value, 'alice@example.com');
    });

    test('detects US SSN', () {
      final matches = PiiDetector.scan('SSN: 123-45-6789 is sensitive.');
      expect(matches.any((m) => m.category == PiiCategory.ssn), isTrue);
    });

    test('detects Luhn-valid credit card numbers', () {
      // Standard Visa test number 4111111111111111 passes the Luhn check.
      final matches = PiiDetector.scan('Card: 4111111111111111');
      expect(matches.any((m) => m.category == PiiCategory.creditCard), isTrue);
    });

    test('rejects non-Luhn credit card numbers', () {
      final matches = PiiDetector.scan('Card: 1234567890123456');
      expect(matches.any((m) => m.category == PiiCategory.creditCard), isFalse);
    });

    test('detects IPv4 addresses', () {
      final matches = PiiDetector.scan('Client 192.168.1.100 connected.');
      expect(matches.any((m) => m.category == PiiCategory.ipv4), isTrue);
    });

    test('containsPii is true when any match is found', () {
      expect(PiiDetector.containsPii('no secrets here'), isFalse);
      expect(PiiDetector.containsPii('email me at bob@example.org'), isTrue);
    });

    test('redact replaces matched spans', () {
      const input = 'Contact bob@example.org now.';
      final redacted = PiiDetector.redact(input, replacement: '[email]');
      expect(redacted, 'Contact [email] now.');
    });

    test('redact with default replacement keeps length', () {
      const input = 'email bob@example.org.';
      final redacted = PiiDetector.redact(input);
      expect(redacted.length, input.length);
      expect(redacted, isNot(contains('bob@example.org')));
    });
  });
}
