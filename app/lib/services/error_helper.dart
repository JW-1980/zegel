/// Provides human-readable error messages with actionable suggestions.
///
/// Converts cryptic exception messages into clear, user-friendly text
/// with specific steps to resolve the problem.
///
/// Implements item 42 from SUGGESTED_IMPROVEMENTS.md:
/// "Provide detailed, human-readable error messages with suggested solutions."
class ErrorHelper {
  ErrorHelper._();

  /// Converts an error into a user-friendly message with a suggestion.
  static ErrorMessage humanize(Object error) {
    final msg = error.toString();

    // Master key errors.
    if (msg.contains('Master key must be exactly 32 bytes')) {
      return const ErrorMessage(
        title: 'Invalid Master Key',
        description: 'The master key must be exactly 32 bytes (256 bits).',
        suggestion:
            'Generate a new key using the Key Generation tool, or ensure '
            'your key file contains exactly 32 raw bytes or 64 hex characters.',
      );
    }

    // Tamper detection.
    if (msg.contains('Master seal verification failed') ||
        msg.contains('Tamper detected')) {
      return const ErrorMessage(
        title: 'File Integrity Compromised',
        description:
            'This file has been modified since it was sealed. The content '
            'is cryptographically irrecoverable.',
        suggestion:
            'Obtain a fresh copy of the file from the original source. '
            'If you suspect unauthorized modification, check the audit trail '
            'and contact the file owner.',
      );
    }

    // Wrong key.
    if (msg.contains('decryption failed') ||
        msg.contains('Merkle root mismatch')) {
      return const ErrorMessage(
        title: 'Wrong Master Key',
        description:
            'The provided key does not match the key used to seal this file.',
        suggestion:
            'Double-check that you are using the correct key file. '
            'If the key was split using Shamir shares, ensure you have '
            'the minimum threshold of shares to reconstruct it.',
      );
    }

    // Expired file.
    if (msg.contains('expired') || msg.contains('Expired')) {
      return const ErrorMessage(
        title: 'File Has Expired',
        description:
            'This file has passed its cryptographic expiration date. '
            'The content is permanently inaccessible by design.',
        suggestion:
            'Contact the file creator to issue a new sealed file with '
            'an updated expiration date, or request a non-expiring version.',
      );
    }

    // Regulatory hold.
    if (msg.contains('regulatory hold') || msg.contains('RegulatoryHold')) {
      return const ErrorMessage(
        title: 'Regulatory Hold Active',
        description:
            'This file is under a compliance hold and cannot be accessed '
            'until the hold period expires.',
        suggestion:
            'Check the file\'s public metadata to see when the hold expires. '
            'Contact your compliance officer if early access is needed.',
      );
    }

    // Format errors.
    if (msg.contains('Invalid magic bytes') ||
        msg.contains('FormatException')) {
      return const ErrorMessage(
        title: 'Not a Valid Zegel File',
        description:
            'This file does not appear to be a .zgl file, or it is severely '
            'corrupted.',
        suggestion:
            'Verify the file extension is .zgl and the file was created '
            'with Zegel software. If it was transferred over a network, '
            'try downloading it again (the transfer may have corrupted it).',
      );
    }

    // File too short.
    if (msg.contains('too short')) {
      return const ErrorMessage(
        title: 'File Is Truncated',
        description: 'The file appears to be incomplete or truncated.',
        suggestion:
            'The file may have been partially downloaded or the disk ran '
            'out of space during creation. Obtain a complete copy from '
            'the original source.',
      );
    }

    // Block count exceeded.
    if (msg.contains('Block count') && msg.contains('exceeds maximum')) {
      return const ErrorMessage(
        title: 'Suspicious File Rejected',
        description:
            'The file claims to contain an unreasonably large number of '
            'blocks, which may indicate a malicious file designed to '
            'exhaust system memory.',
        suggestion: 'Do not trust this file. Obtain it from a verified source.',
      );
    }

    // Argon2id parameter errors.
    if (msg.contains('Argon2id') ||
        msg.contains('time cost') ||
        msg.contains('memory cost')) {
      return const ErrorMessage(
        title: 'Weak Password Parameters',
        description:
            'The Argon2id password derivation parameters are below the '
            'minimum security thresholds recommended by OWASP.',
        suggestion:
            'Use time cost >= 2 and memory cost >= 19456 KiB (19 MiB). '
            'These minimums protect against GPU-based brute-force attacks.',
      );
    }

    // Shamir share errors.
    if (msg.contains('Duplicate x-coordinate')) {
      return const ErrorMessage(
        title: 'Duplicate Key Share',
        description: 'Two or more key shares have the same identifier.',
        suggestion:
            'Ensure each share file is unique. You may have accidentally '
            'loaded the same share twice.',
      );
    }

    if (msg.contains('Need at least') && msg.contains('shares')) {
      return const ErrorMessage(
        title: 'Not Enough Key Shares',
        description: 'You need more key shares to reconstruct the master key.',
        suggestion:
            'Collect additional shares from other key holders until you '
            'have at least the threshold number.',
      );
    }

    // Token expiration.
    if (msg.contains('token expired') || msg.contains('Token expired')) {
      return const ErrorMessage(
        title: 'Disclosure Token Expired',
        description:
            'The selective disclosure token has passed its expiration time.',
        suggestion:
            'Request a new disclosure token from the file owner. '
            'Tokens have a limited lifetime for security reasons.',
      );
    }

    // File not found.
    if (msg.contains('does not exist') || msg.contains('not found')) {
      return const ErrorMessage(
        title: 'File Not Found',
        description: 'The specified file could not be found on disk.',
        suggestion:
            'Verify the file path is correct and the file has not been '
            'moved, renamed, or deleted.',
      );
    }

    // Generic fallback.
    return ErrorMessage(
      title: 'Operation Failed',
      description: msg.length > 200 ? '${msg.substring(0, 200)}...' : msg,
      suggestion:
          'Try the operation again. If the problem persists, check the '
          'file integrity and key validity.',
    );
  }
}

/// A user-friendly error message with title, description, and suggestion.
class ErrorMessage {
  final String title;
  final String description;
  final String suggestion;

  const ErrorMessage({
    required this.title,
    required this.description,
    required this.suggestion,
  });
}
