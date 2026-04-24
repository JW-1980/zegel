import 'dart:math' as math;

/// Password strength estimation (improvements #55 and #59).
///
/// Calculates a rough entropy estimate, produces human-readable strength
/// labels, and emits actionable feedback the UI can show next to a
/// password input. Also provides the [isWeakForSealing] helper used to
/// warn users before they seal files with an obviously weak password.
class PasswordStrength {
  PasswordStrength._();

  /// Minimum entropy (in bits) required to "safely" seal a file. The value
  /// is deliberately conservative: Argon2id stretches the password, but
  /// pathologically short passwords still fall out of brute-force range
  /// quickly.
  static const double sealingEntropyFloor = 50.0;

  /// Common top-of-list passwords. Not an exhaustive list — just enough
  /// to catch the most obvious cases offline.
  static const Set<String> commonPasswords = <String>{
    '123456',
    '123456789',
    'password',
    'password1',
    'qwerty',
    '111111',
    'iloveyou',
    'abc123',
    'admin',
    'letmein',
    'monkey',
    'dragon',
    'sunshine',
    'princess',
    'welcome',
    'football',
    'baseball',
    'shadow',
    'master',
    'ashley',
  };

  /// Returns an estimate of the password strength.
  static PasswordStrengthResult evaluate(String password) {
    if (password.isEmpty) {
      return const PasswordStrengthResult(
        entropyBits: 0,
        score: 0,
        label: PasswordStrengthLabel.veryWeak,
        feedback: <String>['Password cannot be empty.'],
      );
    }

    final feedback = <String>[];
    final normalized = password.toLowerCase();

    var charset = 0;
    if (password.contains(RegExp(r'[a-z]'))) charset += 26;
    if (password.contains(RegExp(r'[A-Z]'))) charset += 26;
    if (password.contains(RegExp(r'[0-9]'))) charset += 10;
    if (password.contains(RegExp(r'[!@#\$%^&*()_+\-=\[\]{};:"\\|,.<>/?`~]'))) {
      charset += 32;
    }
    if (charset == 0) charset = 1;

    // Base entropy: log2(charset^length) = length * log2(charset)
    var entropy = password.length * (math.log(charset) / math.log(2));

    // Penalties
    if (commonPasswords.contains(normalized)) {
      entropy -= 30;
      feedback.add('This password is in common breach lists.');
    }

    if (RegExp(r'^(.)\1+$').hasMatch(password)) {
      entropy -= 20;
      feedback.add('Avoid repeating a single character.');
    }

    if (RegExp(r'^(abc|xyz|qwe|123|098)').hasMatch(normalized)) {
      entropy -= 10;
      feedback.add('Avoid keyboard sequences.');
    }

    if (password.length < 8) {
      feedback.add('Use at least 8 characters.');
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      feedback.add('Add an uppercase letter.');
    }
    if (!password.contains(RegExp(r'[a-z]'))) {
      feedback.add('Add a lowercase letter.');
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      feedback.add('Add a digit.');
    }
    if (!password.contains(RegExp(r'[^A-Za-z0-9]'))) {
      feedback.add('Add a symbol.');
    }

    if (entropy < 0) entropy = 0;

    final label = _label(entropy);
    final score = _score(entropy);

    return PasswordStrengthResult(
      entropyBits: entropy,
      score: score,
      label: label,
      feedback: List<String>.unmodifiable(feedback),
    );
  }

  /// Whether the password should trigger a "weak password" warning when
  /// used as the seed for sealing.
  static bool isWeakForSealing(String password) {
    return evaluate(password).entropyBits < sealingEntropyFloor;
  }

  static PasswordStrengthLabel _label(double entropy) {
    if (entropy < 28) return PasswordStrengthLabel.veryWeak;
    if (entropy < 36) return PasswordStrengthLabel.weak;
    if (entropy < 60) return PasswordStrengthLabel.reasonable;
    if (entropy < 128) return PasswordStrengthLabel.strong;
    return PasswordStrengthLabel.veryStrong;
  }

  static int _score(double entropy) {
    // 0..4 integer score for bar meters.
    if (entropy < 28) return 0;
    if (entropy < 36) return 1;
    if (entropy < 60) return 2;
    if (entropy < 128) return 3;
    return 4;
  }
}

enum PasswordStrengthLabel { veryWeak, weak, reasonable, strong, veryStrong }

class PasswordStrengthResult {
  const PasswordStrengthResult({
    required this.entropyBits,
    required this.score,
    required this.label,
    required this.feedback,
  });

  /// Estimated entropy of the password in bits.
  final double entropyBits;

  /// Integer score 0..4, matching zxcvbn conventions for meter widgets.
  final int score;

  /// Human-readable label for display.
  final PasswordStrengthLabel label;

  /// List of suggestions to shown in the UI.
  final List<String> feedback;
}
