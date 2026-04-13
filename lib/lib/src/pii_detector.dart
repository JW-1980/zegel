/// PII auto-detection and redaction suggestions (improvement #71).
///
/// Scans UTF-8 text for common patterns of personally-identifiable
/// information (SSN, credit card numbers, email addresses, phone numbers,
/// IBANs) and returns the spans that matched so the GUI can offer
/// redaction suggestions to the user.
///
/// This is deliberately a best-effort, regex-based detector — it will have
/// false positives. It is designed as a helper for redaction workflows,
/// not as a compliance tool.
class PiiDetector {
  PiiDetector._();

  static final RegExp _ssnUs = RegExp(r'\b(?!000|666|9\d\d)\d{3}[- ]?\d{2}[- ]?\d{4}\b');
  static final RegExp _email = RegExp(
    r'[\w.+\-]+@[\w\-]+(?:\.[\w\-]+)+',
    caseSensitive: false,
  );
  static final RegExp _phoneIntl = RegExp(
    r'(?:\+?\d{1,3}[ -]?)?(?:\(\d{2,4}\)[ -]?)?\d{3}[ -]?\d{3,4}[ -]?\d{3,4}',
  );
  static final RegExp _creditCard = RegExp(r'\b(?:\d[ -]?){13,19}\b');
  static final RegExp _iban = RegExp(
    r'\b[A-Z]{2}\d{2}[A-Z0-9]{10,30}\b',
  );
  static final RegExp _ipv4 = RegExp(
    r'\b(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\b',
  );

  /// Runs every detector against [text]. Results are returned in the order
  /// they appear in the input.
  static List<PiiMatch> scan(String text) {
    final matches = <PiiMatch>[];

    void collect(RegExp re, PiiCategory category, bool Function(String)? extra) {
      for (final m in re.allMatches(text)) {
        final value = m.group(0) ?? '';
        if (extra != null && !extra(value)) continue;
        matches.add(PiiMatch(
          category: category,
          value: value,
          start: m.start,
          end: m.end,
        ));
      }
    }

    collect(_email, PiiCategory.email, null);
    collect(_ssnUs, PiiCategory.ssn, null);
    collect(_iban, PiiCategory.iban, null);
    collect(_creditCard, PiiCategory.creditCard, _looksLikeCreditCard);
    collect(_phoneIntl, PiiCategory.phone, _looksLikePhone);
    collect(_ipv4, PiiCategory.ipv4, null);

    matches.sort((a, b) => a.start.compareTo(b.start));
    // Remove exact duplicate spans (different detectors can match the same
    // substring, e.g. phone numbers vs. IPv4-looking runs).
    final deduped = <PiiMatch>[];
    for (final m in matches) {
      if (deduped.isEmpty ||
          deduped.last.start != m.start ||
          deduped.last.end != m.end) {
        deduped.add(m);
      }
    }
    return deduped;
  }

  /// Returns true if [text] contains at least one PII match.
  static bool containsPii(String text) => scan(text).isNotEmpty;

  /// Produces a redacted copy of [text] where every match is replaced with
  /// [replacement] (default: `█` characters of the same length).
  static String redact(String text, {String? replacement}) {
    final matches = scan(text);
    if (matches.isEmpty) return text;
    final buf = StringBuffer();
    var cursor = 0;
    for (final m in matches) {
      buf.write(text.substring(cursor, m.start));
      if (replacement != null) {
        buf.write(replacement);
      } else {
        buf.write('█' * (m.end - m.start));
      }
      cursor = m.end;
    }
    if (cursor < text.length) buf.write(text.substring(cursor));
    return buf.toString();
  }

  static bool _looksLikeCreditCard(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 13 || digits.length > 19) return false;
    // Luhn check
    var sum = 0;
    var shouldDouble = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var d = int.parse(digits[i]);
      if (shouldDouble) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
      shouldDouble = !shouldDouble;
    }
    return sum % 10 == 0;
  }

  static bool _looksLikePhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    // Allow 7–15 digits per E.164 guidance.
    return digits.length >= 7 && digits.length <= 15;
  }
}

enum PiiCategory {
  ssn,
  email,
  phone,
  creditCard,
  iban,
  ipv4,
}

class PiiMatch {
  const PiiMatch({
    required this.category,
    required this.value,
    required this.start,
    required this.end,
  });

  final PiiCategory category;
  final String value;
  final int start;
  final int end;
}
