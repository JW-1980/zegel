/// Reusable form-field validator (improvements #8 and #97).
///
/// A pipeline of small, composable [ValidatorRule]s that produce either
/// `null` (meaning "valid") or a human-readable error message. The
/// pipeline short-circuits on the first failure. The rules here are
/// purely string-based so the class can live in the core library and
/// be exercised in unit tests without any UI framework.
class FieldValidator {

  /// Shortcut for "all common text-field rules with defaults".
  factory FieldValidator.text({
    bool required = false,
    int? minLength,
    int? maxLength,
    RegExp? pattern,
    String? patternMessage,
  }) {
    return FieldValidator(<ValidatorRule>[
      if (required) const RequiredRule(),
      if (minLength != null) MinLengthRule(minLength),
      if (maxLength != null) MaxLengthRule(maxLength),
      if (pattern != null)
        PatternRule(pattern, message: patternMessage ?? 'Invalid format'),
    ]);
  }
  const FieldValidator(this.rules);

  final List<ValidatorRule> rules;

  /// Returns the first error message produced by any rule, or `null`
  /// when every rule passes.
  String? validate(String? value) {
    for (final rule in rules) {
      final error = rule.check(value);
      if (error != null) return error;
    }
    return null;
  }
}

abstract class ValidatorRule {
  const ValidatorRule();

  String? check(String? value);
}

class RequiredRule extends ValidatorRule {
  const RequiredRule({this.message = 'This field is required'});

  final String message;

  @override
  String? check(String? value) {
    if (value == null || value.isEmpty) return message;
    return null;
  }
}

class MinLengthRule extends ValidatorRule {
  const MinLengthRule(this.length, {String? message})
      : _customMessage = message;

  final int length;
  final String? _customMessage;

  @override
  String? check(String? value) {
    if (value == null || value.length < length) {
      return _customMessage ?? 'Must be at least $length characters';
    }
    return null;
  }
}

class MaxLengthRule extends ValidatorRule {
  const MaxLengthRule(this.length, {String? message})
      : _customMessage = message;

  final int length;
  final String? _customMessage;

  @override
  String? check(String? value) {
    if (value != null && value.length > length) {
      return _customMessage ?? 'Must be at most $length characters';
    }
    return null;
  }
}

class PatternRule extends ValidatorRule {
  const PatternRule(this.pattern, {this.message = 'Invalid format'});

  final RegExp pattern;
  final String message;

  @override
  String? check(String? value) {
    if (value == null) return null;
    if (!pattern.hasMatch(value)) return message;
    return null;
  }
}

class HexKeyRule extends ValidatorRule {
  const HexKeyRule({this.bytes = 32, this.message});

  /// Expected key length in bytes (length*2 hex chars).
  final int bytes;
  final String? message;

  @override
  String? check(String? value) {
    if (value == null) return null;
    final expectedChars = bytes * 2;
    if (value.length != expectedChars) {
      return message ?? 'Key must be $expectedChars hex characters';
    }
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
      return message ?? 'Key must contain only hex digits';
    }
    return null;
  }
}

class EmailRule extends ValidatorRule {
  const EmailRule({this.message = 'Enter a valid email address'});

  final String message;

  @override
  String? check(String? value) {
    if (value == null || value.isEmpty) return null;
    final re = RegExp(r'^[\w.+\-]+@[\w\-]+(?:\.[\w\-]+)+$');
    if (!re.hasMatch(value)) return message;
    return null;
  }
}
