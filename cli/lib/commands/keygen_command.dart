import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:args/command_runner.dart';

import 'common.dart';

/// Generates a cryptographically secure 32-byte master key.
///
/// Usage:
///   zegel keygen [-o <key-file>]
///
/// Outputs the key as a 64-character hex string to stdout,
/// or writes it to a file if -o is specified.
class KeygenCommand extends Command<int> {
  @override
  final String name = 'keygen';

  @override
  final String description =
      'Generate a cryptographically secure 32-byte master key.';

  @override
  final String invocation = 'zegel keygen [options]';

  KeygenCommand() {
    addOutputOption(
      argParser,
      help: 'Write key to a file instead of stdout.',
    );

    argParser.addFlag(
      'raw',
      help: 'Write raw bytes instead of hex string (only with -o).',
      defaultsTo: false,
    );

    argParser.addFlag(
      'quiet',
      abbr: 'q',
      help: 'Suppress security warnings.',
      defaultsTo: false,
    );
  }

  @override
  Future<int> run() async {
    // Generate 32 bytes of cryptographically secure random data.
    final random = Random.secure();
    final key = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      key[i] = random.nextInt(256);
    }
    final keyHex = hexEncode(key);

    final outputPath = argResults!['output'] as String?;
    final rawOutput = argResults!['raw'] as bool;
    final quiet = argResults!['quiet'] as bool;

    if (outputPath != null) {
      // Write key to file.
      final outputFile = File(outputPath);

      if (outputFile.existsSync()) {
        exitError(
          'Output file already exists: $outputPath. '
          'Refusing to overwrite key file.',
        );
      }

      if (rawOutput) {
        outputFile.writeAsBytesSync(key);
      } else {
        outputFile.writeAsStringSync('$keyHex\n');
      }

      // Set restrictive permissions on Unix systems.
      try {
        Process.runSync('chmod', ['600', outputPath]);
      } catch (_) {
        // chmod may not be available on all platforms (e.g., Windows).
      }

      if (!quiet) {
        stderr.writeln(Ansi.success('Key generated successfully.'));
        stderr.writeln();
        stderr.writeln('  File:   $outputPath');
        stderr.writeln('  Format: ${rawOutput ? 'raw (32 bytes)' : 'hex (64 characters)'}');
        stderr.writeln('  Perms:  0600 (owner read/write only)');
        stderr.writeln();
        _printSecurityWarning();
      }
    } else {
      // Output key to stdout.
      stdout.writeln(keyHex);

      if (!quiet) {
        stderr.writeln();
        _printSecurityWarning();
      }
    }

    return 0;
  }

  /// Prints a security warning about key handling.
  void _printSecurityWarning() {
    stderr.writeln(Ansi.warning('Security Warning:'));
    stderr.writeln(
      '  This key provides full access to any file sealed with it.',
    );
    stderr.writeln('  - Store it securely (password manager, hardware token).');
    stderr.writeln('  - Never commit key files to version control.');
    stderr.writeln('  - Never transmit keys over insecure channels.');
    stderr.writeln(
      '  - Consider split-key (M-of-N) for high-value documents:',
    );
    stderr.writeln(
      '      zegel split-key -k <key> --threshold 3 --shares 5',
    );
  }
}
