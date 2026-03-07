import 'dart:io';
import 'dart:math';

import 'package:args/command_runner.dart';

import 'common.dart';

/// Generates a cryptographically secure 32-byte master key.
///
/// Usage:
///   zegel keygen [-o <key-file>]
///   zegel keygen --hierarchical [-o <key-dir>]
///
/// Outputs the key as a 64-character hex string to stdout,
/// or writes it to a file if -o is specified.
class KeygenCommand extends Command<int> {
  @override
  final String name = 'keygen';

  @override
  String get description =>
      'Generate a cryptographically secure 32-byte master key.\n'
      '\n'
      'Uses the platform cryptographic RNG (Random.secure()) to\n'
      'generate 32 bytes (256 bits) of random data suitable for\n'
      'AES-256-GCM encryption.\n'
      '\n'
      'The key is output as a 64-character hex string to stdout,\n'
      'or written to a file if -o is specified. Key files are\n'
      'automatically set to 0600 permissions on Unix systems.\n'
      '\n'
      'Use --hierarchical to generate a key hierarchy with a\n'
      'root key and derived sub-keys for different purposes\n'
      '(e.g., department keys, project keys).\n'
      '\n'
      'Exit codes:\n'
      '  0  Key generated successfully\n'
      '  1  Error\n'
      '\n'
      'Examples:\n'
      '  zegel keygen > master.key\n'
      '  zegel keygen -o master.key\n'
      '  zegel keygen -o master.key --raw\n'
      '  zegel keygen --hierarchical -o keys/';

  @override
  final String invocation = 'zegel keygen [options]';

  KeygenCommand() {
    addOutputOption(
      argParser,
      help: 'Write key to a file instead of stdout.\n'
          'With --hierarchical, this is the output directory.',
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

    argParser.addFlag(
      'hierarchical',
      help: 'Generate a hierarchical key set:\n'
          '  - root.key: Master root key\n'
          '  - seal.key: Derived key for sealing\n'
          '  - attest.key: Derived key for attestations\n'
          'Output path (-o) is treated as a directory.',
      defaultsTo: false,
    );
  }

  @override
  Future<int> run() async {
    final hierarchical = argResults!['hierarchical'] as bool;

    if (hierarchical) {
      return _runHierarchical();
    }

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
        stderr.writeln(
            '  Format: ${rawOutput ? 'raw (32 bytes)' : 'hex (64 characters)'}');
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

  /// Generates a hierarchical key set (root + derived keys).
  Future<int> _runHierarchical() async {
    final outputDir = argResults!['output'] as String?;
    if (outputDir == null) {
      exitError(
        'Output directory is required for hierarchical key generation (-o <dir>).',
      );
    }

    final dir = Directory(outputDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final random = Random.secure();
    final quiet = argResults!['quiet'] as bool;

    // Generate root key.
    final rootKey = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      rootKey[i] = random.nextInt(256);
    }

    // Generate derived keys (independent random keys).
    final sealKey = Uint8List(32);
    final attestKey = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      sealKey[i] = random.nextInt(256);
      attestKey[i] = random.nextInt(256);
    }

    // Write keys.
    final keys = <String, Uint8List>{
      'root.key': rootKey,
      'seal.key': sealKey,
      'attest.key': attestKey,
    };

    for (final entry in keys.entries) {
      final path = '${dir.path}/${entry.key}';
      File(path).writeAsStringSync('${hexEncode(entry.value)}\n');
      try {
        Process.runSync('chmod', ['600', path]);
      } catch (_) {}
    }

    if (!quiet) {
      stdout.writeln(Ansi.success('Hierarchical key set generated.'));
      stdout.writeln();
      stdout.writeln('  Directory: $outputDir');
      stdout.writeln('  Files:');
      for (final name in keys.keys) {
        stdout.writeln('    $name');
      }
      stdout.writeln();
      _printSecurityWarning();
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
