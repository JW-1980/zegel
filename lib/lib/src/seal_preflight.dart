import 'dart:convert';
import 'dart:typed_data';

import 'pii_detector.dart';
import 'password_strength.dart';

/// Pre-flight check run before sealing a file (improvement #73).
///
/// Collects the warnings the GUI should surface to the user *before* a
/// file is converted into its tamper-proof form. Once the file is sealed,
/// the original may be deleted — so this is the last chance to catch
/// mistakes like "you forgot to redact the SSN in paragraph 2".
///
/// The preflight checks currently include:
/// - PII scan of the raw bytes when they decode as UTF-8 text
///   (SSNs, credit cards, emails, phone numbers, IBANs, IPv4)
/// - Weak-password warning when a password-derived key is being used
/// - Empty-file warning
/// - Oversize warning when a file exceeds [oversizeBytes]
class SealPreflight {
  SealPreflight._();

  /// Default "oversize" threshold (256 MiB). Sealing still works above
  /// this, but the GUI should offer a warning and a compression option.
  static const int oversizeBytes = 256 * 1024 * 1024;

  /// Analyses [bytes] and optional [password] and returns a
  /// [PreflightResult] with the list of warnings to display.
  static PreflightResult analyse(
    Uint8List bytes, {
    String? password,
    int oversizeThreshold = oversizeBytes,
  }) {
    final warnings = <PreflightWarning>[];

    if (bytes.isEmpty) {
      warnings.add(
        const PreflightWarning(
          severity: PreflightSeverity.error,
          code: 'empty_file',
          message: 'The file is empty; sealing would produce an empty payload.',
        ),
      );
    }

    if (bytes.length > oversizeThreshold) {
      warnings.add(
        PreflightWarning(
          severity: PreflightSeverity.info,
          code: 'oversize_file',
          message:
              'File is ${_humanSize(bytes.length)}; consider enabling compression.',
        ),
      );
    }

    final piiMatches = _scanForPii(bytes);
    if (piiMatches.isNotEmpty) {
      warnings.add(
        PreflightWarning(
          severity: PreflightSeverity.warning,
          code: 'pii_detected',
          message:
              'Found ${piiMatches.length} potential PII match(es). Consider redaction.',
          details: {
            'categories':
                piiMatches.map((m) => m.category.name).toSet().toList(),
            'count': piiMatches.length,
          },
        ),
      );
    }

    if (password != null) {
      final strength = PasswordStrength.evaluate(password);
      if (PasswordStrength.isWeakForSealing(password)) {
        warnings.add(
          PreflightWarning(
            severity: PreflightSeverity.warning,
            code: 'weak_password',
            message:
                'Password strength is ${strength.label.name} (${strength.entropyBits.toStringAsFixed(1)} bits).',
            details: {
              'entropy_bits': strength.entropyBits,
              'score': strength.score,
              'feedback': strength.feedback,
            },
          ),
        );
      }
    }

    return PreflightResult(warnings: warnings);
  }

  static List<PiiMatch> _scanForPii(Uint8List bytes) {
    // Only scan if the bytes look like UTF-8 text. We treat any decoding
    // error as "not text" and return no matches.
    try {
      final text = utf8.decode(bytes, allowMalformed: false);
      return PiiDetector.scan(text);
    } catch (_) {
      return const <PiiMatch>[];
    }
  }

  static String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class PreflightResult {
  const PreflightResult({required this.warnings});

  final List<PreflightWarning> warnings;

  bool get hasErrors =>
      warnings.any((w) => w.severity == PreflightSeverity.error);
  bool get hasWarnings =>
      warnings.any((w) => w.severity == PreflightSeverity.warning);
  bool get safeToProceed => !hasErrors;
}

class PreflightWarning {
  const PreflightWarning({
    required this.severity,
    required this.code,
    required this.message,
    this.details = const <String, dynamic>{},
  });

  final PreflightSeverity severity;
  final String code;
  final String message;
  final Map<String, dynamic> details;
}

enum PreflightSeverity { info, warning, error }
