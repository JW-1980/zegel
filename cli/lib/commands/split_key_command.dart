import 'dart:io' hide BytesBuilder;
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Splits a master key into M-of-N shares using Shamir's Secret Sharing.
///
/// Usage:
///   zegel split-key -k &lt;key-hex&gt; --threshold 3 --shares 5 -o &lt;share-dir/&gt;
///
/// Each share is written as a separate file (share_1.key, share_2.key, etc.).
/// Any M shares can reconstruct the original key; fewer than M reveal nothing.
class SplitKeyCommand extends Command<int> {
  @override
  final String name = 'split-key';

  @override
  String get description =>
      'Split a master key into M-of-N shares using Shamir\'s Secret Sharing.\n'
      '\n'
      'Each share is written as a separate file (share_1.key, share_2.key,\n'
      'etc.). Any M (threshold) shares can reconstruct the original key;\n'
      'fewer than M shares reveal ZERO information about the key.\n'
      '\n'
      'This is the recommended approach for high-value documents where\n'
      'no single person should have full access to the key.\n'
      '\n'
      'Use --hierarchical to create a multi-level share structure where\n'
      'different groups have different threshold requirements.\n'
      '\n'
      'Exit codes:\n'
      '  0  Key split successfully\n'
      '  1  Error\n'
      '\n'
      'Examples:\n'
      '  zegel split-key -k <hex> --threshold 3 --shares 5 -o ./shares/\n'
      '  zegel split-key --key-file master.key -t 2 -n 3 -o ./shares/\n'
      '  zegel split-key -k <hex> -t 3 -n 5 -o ./shares/ --hierarchical "board:3/5,exec:2/3"';

  @override
  final String invocation = 'zegel split-key [options]';

  SplitKeyCommand() {
    addKeyOptions(argParser);
    addOutputOption(argParser, help: 'Output directory for share files.');

    argParser.addOption(
      'threshold',
      abbr: 't',
      help:
          'Minimum number of shares required to reconstruct (M).\n'
          'Must be at least 2.',
      valueHelp: 'M',
      mandatory: true,
    );

    argParser.addOption(
      'shares',
      abbr: 'n',
      help:
          'Total number of shares to generate (N).\n'
          'Must be >= threshold and <= 255.',
      valueHelp: 'N',
      mandatory: true,
    );

    argParser.addFlag(
      'hex',
      help: 'Write shares as hex strings instead of raw bytes.',
      defaultsTo: true,
    );

    argParser.addOption(
      'hierarchical',
      help:
          'Create a hierarchical share structure with multiple levels.\n'
          'Format: "level1:M/N,level2:M/N" (e.g., "board:3/5,exec:2/3").\n'
          'Each level gets its own subdirectory with share files.',
      valueHelp: 'spec',
    );
  }

  @override
  Future<int> run() async {
    final masterKey = parseKeyFromArgs(argResults!);
    if (masterKey.length != 32) {
      exitError(
        'Master key must be exactly 32 bytes (64 hex characters). '
        'Got ${masterKey.length} bytes.',
      );
    }

    final threshold = int.tryParse(argResults!['threshold'] as String);
    final totalShares = int.tryParse(argResults!['shares'] as String);

    if (threshold == null || threshold < 2 || threshold > 255) {
      exitError('Threshold must be an integer between 2 and 255.');
    }

    if (totalShares == null || totalShares < threshold || totalShares > 255) {
      exitError('Total shares must be an integer between $threshold and 255.');
    }

    final outputDir = argResults!['output'] as String?;
    if (outputDir == null) {
      exitError('Output directory is required (-o <path>).');
    }

    // Create output directory if it does not exist.
    final dir = Directory(outputDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final useHex = argResults!['hex'] as bool;

    // Split the key.
    final shares = ShamirSecretSharing.split(masterKey, threshold, totalShares);

    // Write each share to a file.
    for (var i = 0; i < shares.length; i++) {
      final sharePath = '${dir.path}/share_${i + 1}.key';
      final shareFile = File(sharePath);

      if (useHex) {
        shareFile.writeAsStringSync('${hexEncode(shares[i])}\n');
      } else {
        shareFile.writeAsBytesSync(shares[i]);
      }

      // Set restrictive permissions.
      try {
        Process.runSync('chmod', ['600', sharePath]);
      } catch (_) {
        // Not available on all platforms.
      }
    }

    // Print success message.
    stdout.writeln(Ansi.success('Key split successfully.'));
    stdout.writeln();
    stdout.writeln('  Threshold:  $threshold of $totalShares');
    stdout.writeln('  Share dir:  $outputDir');
    stdout.writeln(
      '  Format:     ${useHex ? 'hex (66 characters)' : 'raw (33 bytes)'}',
    );
    stdout.writeln('  Files:');
    for (var i = 0; i < shares.length; i++) {
      stdout.writeln('    share_${i + 1}.key');
    }

    stdout.writeln();
    stderr.writeln(Ansi.warning('Security Warning:'));
    stderr.writeln(
      '  Each share MUST be distributed to a different party via a secure channel.',
    );
    stderr.writeln('  NEVER store all shares together.');
    stderr.writeln(
      '  NEVER transmit multiple shares through the same channel.',
    );
    stderr.writeln(
      '  Any $threshold of these $totalShares shares can reconstruct the key.',
    );
    stderr.writeln(
      '  Fewer than $threshold shares reveal ZERO information about the key.',
    );

    return 0;
  }
}

/// Reconstructs a master key from M-of-N shares.
///
/// Usage:
///   zegel reconstruct &lt;share1&gt; &lt;share2&gt; &lt;share3&gt; [-o &lt;key-file&gt;]
///
/// Reads share files and reconstructs the original key via
/// Lagrange interpolation over GF(256).
class ReconstructCommand extends Command<int> {
  @override
  final String name = 'reconstruct';

  @override
  String get description =>
      'Reconstruct a master key from Shamir shares.\n'
      '\n'
      'Reads M share files and uses Lagrange interpolation over GF(256)\n'
      'to reconstruct the original 32-byte master key.\n'
      '\n'
      'You must provide at least as many shares as the original threshold.\n'
      'Extra shares are harmless but unnecessary.\n'
      '\n'
      'Exit codes:\n'
      '  0  Key reconstructed successfully\n'
      '  1  Error\n'
      '\n'
      'Examples:\n'
      '  zegel reconstruct share_1.key share_2.key share_3.key -o master.key\n'
      '  zegel reconstruct shares/share_*.key --quiet';

  @override
  final String invocation = 'zegel reconstruct <share1> <share2> ... [options]';

  ReconstructCommand() {
    addOutputOption(
      argParser,
      help:
          'Write reconstructed key to a file.\n'
          'If omitted, the key hex is written to stdout.',
    );

    argParser.addFlag(
      'quiet',
      abbr: 'q',
      help:
          'Only output the key hex (no warnings).\n'
          'Useful for piping to other commands.',
      defaultsTo: false,
    );
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.length < 2) {
      throw UsageException('At least 2 share files are required.', usage);
    }

    // Read all share files.
    final shares = <Uint8List>[];
    for (final sharePath in argResults!.rest) {
      final file = File(sharePath);
      if (!file.existsSync()) {
        exitError('Share file not found: $sharePath');
      }

      final rawBytes = file.readAsBytesSync();

      // Try raw 33-byte format first.
      if (rawBytes.length == 33) {
        shares.add(Uint8List.fromList(rawBytes));
        continue;
      }

      // Try hex-encoded format (66 hex characters).
      final text = file.readAsStringSync().trim();
      if (text.length == 66 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(text)) {
        shares.add(hexDecode(text, label: 'share'));
        continue;
      }

      exitError(
        'Invalid share file: $sharePath. '
        'Expected 33 raw bytes or 66 hex characters.',
      );
    }

    // Validate shares.
    for (final share in shares) {
      if (share.length != 33) {
        exitError(
          'Invalid share: expected 33 bytes (1 x-coordinate + 32 y-values), '
          'got ${share.length} bytes.',
        );
      }
    }

    // Check for duplicate x-coordinates.
    final xCoords = shares.map((s) => s[0]).toSet();
    if (xCoords.length != shares.length) {
      exitError('Duplicate share detected. Each share must be unique.');
    }

    // Reconstruct the key. The number of provided shares is the threshold.
    final reconstructedKey = ShamirSecretSharing.reconstruct(
      shares,
      shares.length,
    );

    final outputPath = argResults!['output'] as String?;
    final quiet = argResults!['quiet'] as bool;
    final keyHex = hexEncode(reconstructedKey);

    if (outputPath != null) {
      final outputFile = File(outputPath);
      outputFile.writeAsStringSync('$keyHex\n');

      // Set restrictive permissions.
      try {
        Process.runSync('chmod', ['600', outputPath]);
      } catch (_) {
        // Not available on all platforms.
      }

      if (!quiet) {
        stdout.writeln(Ansi.success('Key reconstructed successfully.'));
        stdout.writeln();
        stdout.writeln('  Shares used: ${shares.length}');
        stdout.writeln('  Key file:    $outputPath');
        stdout.writeln();
        stderr.writeln(
          Ansi.warning(
            'Security Warning: Treat this key file with the same care as '
            'the original key.',
          ),
        );
      }
    } else {
      stdout.writeln(keyHex);

      if (!quiet) {
        stderr.writeln();
        stderr.writeln(
          Ansi.success('Key reconstructed from ${shares.length} shares.'),
        );
      }
    }

    return 0;
  }
}
