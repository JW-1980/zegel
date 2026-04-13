import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('PasswordStrength', () {
    test('empty password is reported as very weak', () {
      final r = PasswordStrength.evaluate('');
      expect(r.label, PasswordStrengthLabel.veryWeak);
      expect(r.score, 0);
      expect(r.entropyBits, 0);
    });

    test('known breach passwords land at the bottom', () {
      final r = PasswordStrength.evaluate('password');
      expect(r.label, PasswordStrengthLabel.veryWeak);
      expect(r.feedback, isNotEmpty);
    });

    test('a strong mixed password scores high', () {
      final r = PasswordStrength.evaluate('Correct-Horse-Battery-Staple!1');
      expect(r.entropyBits, greaterThan(80));
      expect(
        r.label,
        anyOf(
          PasswordStrengthLabel.strong,
          PasswordStrengthLabel.veryStrong,
        ),
      );
      expect(r.score, greaterThanOrEqualTo(3));
    });

    test('isWeakForSealing flags short passwords', () {
      expect(PasswordStrength.isWeakForSealing('short'), isTrue);
      expect(
        PasswordStrength.isWeakForSealing('Xh%9q2Rn4!bT2#vE7gJk'),
        isFalse,
      );
    });

    test('feedback mentions character-class deficits', () {
      final r = PasswordStrength.evaluate('abcdefgh');
      expect(r.feedback.any((s) => s.contains('uppercase')), isTrue);
      expect(r.feedback.any((s) => s.contains('digit')), isTrue);
      expect(r.feedback.any((s) => s.contains('symbol')), isTrue);
    });
  });
}
