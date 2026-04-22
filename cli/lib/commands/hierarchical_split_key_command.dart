import 'dart:convert';
import 'dart:io' hide BytesBuilder;
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Parent command for hierarchical split-key operations.
///
/// Usage:
///   zegel hierarchical-split &lt;subcommand&gt; [options]
///
/// Subcommands:
///   split        Split a key into hierarchical share groups
///   reconstruct  Reconstruct a key from hierarchical shares
class HierarchicalSplitCommand extends Command<int> {
  @override
  final String name = 'hierarchical-split';

  @override
  String get description => 'Hierarchical split-key operations.\n'
      '\n'
      'Implements nested Shamir\'s Secret Sharing where different\n'
      'classification levels require different numbers of key shares.\n'
      'Higher-level access requires shares from all lower levels plus\n'
      'additional shares for the higher level.\n'
      '\n'
      'Subcommands:\n'
      '  split        Split a master key into hierarchical share groups\n'
      '  reconstruct  Reconstruct a master key from hierarchical shares\n'
      '\n'
      'Examples:\n'
      '  zegel hierarchical-split split -k <key> --levels "CONFIDENTIAL:2:3,SECRET:2:3" -o shares/\n'
      '  zegel hierarchical-split reconstruct shares/ -o recovered.key';

  HierarchicalSplitCommand() {
    addSubcommand(HierarchicalSplitSplitCommand());
    addSubcommand(HierarchicalSplitReconstructCommand());
  }

  @override
  Future<int> run() async {
    // Show help if no subcommand specified.
    printUsage();
    return 0;
  }
}

/// Splits a master key into hierarchical share groups.
class HierarchicalSplitSplitCommand extends Command<int> {
  @override
  final String name = 'split';

  @override
  String get description =>
      'Split a master key into hierarchical share groups.\n'
      '\n'
      'The master key is decomposed into intermediate keys using XOR chaining,\n'
      'and each intermediate key is split using Shamir\'s Secret Sharing with\n'
      'the threshold and share count specified for each level.\n'
      '\n'
      'Levels are specified as "LEVEL_NAME:THRESHOLD:TOTAL" separated by commas.\n'
      'Order matters: list from lowest to highest classification.\n'
      '\n'
      'Exit codes:\n'
      '  0  Split successfully\n'
      '  1  Error\n'
      '\n'
      'Examples:\n'
      '  zegel hierarchical-split split -k <key> --levels "CONFIDENTIAL:2:3,SECRET:2:3" -o shares/\n'
      '  zegel hierarchical-split split --key-file master.key --levels "CEO:1:1,VP:2:3,Manager:2:4" -o shares/';

  @override
  final String invocation = 'zegel hierarchical-split split [options]';

  HierarchicalSplitSplitCommand() {
    addKeyOptions(argParser);
    addOutputOption(argParser, help: 'Output directory for share files.');

    argParser.addOption(
      'levels',
      abbr: 'l',
      help: 'Level specifications as "NAME:THRESHOLD:TOTAL,...".\n'
          'Example: "CONFIDENTIAL:2:3,SECRET:2:3,TOP_SECRET:3:5"\n'
          'Order from lowest to highest classification.',
      valueHelp: 'specs',
      mandatory: true,
    );
  }

  @override
  Future<int> run() async {
    // Parse master key.
    final masterKey = parseKeyFromArgs(argResults!);
    if (masterKey.length != 32) {
      exitError(
        'Master key must be exactly 32 bytes (64 hex characters). '
        'Got ${masterKey.length} bytes.',
      );
    }

    final outputDir = argResults!['output'] as String?;
    if (outputDir == null || outputDir.isEmpty) {
      exitError('Output directory is required.');
    }

    final levelsStr = argResults!['levels'] as String;
    final levels = _parseLevels(levelsStr);

    if (levels.isEmpty) {
      exitError('At least one level must be specified.');
    }

    // Create output directory if it doesn't exist.
    final dir = Directory(outputDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Split the key.
    final hierarchicalShares = HierarchicalSplitKey.split(masterKey, levels);

    // Write share files.
    int totalShares = 0;
    for (final levelName in hierarchicalShares.sharesByLevel.keys) {
      final shares = hierarchicalShares.sharesByLevel[levelName]!;
      final levelDir = Directory('$outputDir/$levelName');
      if (!levelDir.existsSync()) {
        levelDir.createSync(recursive: true);
      }

      for (int i = 0; i < shares.length; i++) {
        final shareFile = File('${levelDir.path}/share_${i + 1}.key');
        shareFile.writeAsBytesSync(shares[i]);
        totalShares++;
      }
    }

    // Write manifest for reconstruction.
    final manifest = <String, dynamic>{
      'version': 1,
      'type': 'hierarchical_split_key',
      'levels': levels
          .map(
            (l) => {
              'name': l.classification,
              'threshold': l.threshold,
              'total': l.totalShares,
            },
          )
          .toList(),
      'created': DateTime.now().toUtc().toIso8601String(),
    };
    final manifestFile = File('$outputDir/manifest.json');
    manifestFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(manifest),
    );

    // Print success message.
    stdout.writeln(Ansi.success('Hierarchical key split successfully.'));
    stdout.writeln();
    stdout.writeln('  Output:  $outputDir');
    stdout.writeln('  Levels:  ${levels.length}');
    stdout.writeln('  Shares:  $totalShares total');
    stdout.writeln();
    stdout.writeln(Ansi.header('Share Structure:'));
    for (final level in levels) {
      final shares = hierarchicalShares.sharesByLevel[level.classification]!;
      stdout.writeln(
        '  ${level.classification}: ${level.threshold}-of-${level.totalShares} '
        '(${shares.length} shares)',
      );
    }
    stdout.writeln();
    stdout.writeln(
      'To reconstruct the full key, you need shares from ALL levels:',
    );
    for (final level in levels) {
      stdout.writeln(
        '  - ${level.threshold} shares from ${level.classification}',
      );
    }

    SecureMemory.wipe(masterKey);
    return 0;
  }

  List<ShareLevel> _parseLevels(String levelsStr) {
    final levels = <ShareLevel>[];
    final parts = levelsStr.split(',');

    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;

      final components = trimmed.split(':');
      if (components.length != 3) {
        exitError(
          'Invalid level format: "$trimmed". '
          'Expected "NAME:THRESHOLD:TOTAL".',
        );
      }

      final name = components[0].trim().toUpperCase();
      final threshold = int.tryParse(components[1].trim());
      final total = int.tryParse(components[2].trim());

      if (threshold == null || total == null) {
        exitError(
          'Invalid level format: "$trimmed". '
          'Threshold and total must be integers.',
        );
      }

      if (threshold < 1) {
        exitError('Threshold must be at least 1 for level "$name".');
      }

      if (total < threshold) {
        exitError(
          'Total shares ($total) must be >= threshold ($threshold) '
          'for level "$name".',
        );
      }

      levels.add(
        ShareLevel(
          classification: name,
          threshold: threshold,
          totalShares: total,
        ),
      );
    }

    return levels;
  }
}

/// Reconstructs a master key from hierarchical shares.
class HierarchicalSplitReconstructCommand extends Command<int> {
  @override
  final String name = 'reconstruct';

  @override
  String get description =>
      'Reconstruct a master key from hierarchical shares.\n'
      '\n'
      'Reads shares from a directory structure created by "hierarchical-split split"\n'
      'and reconstructs the original master key. You must provide at least the\n'
      'threshold number of shares for each level.\n'
      '\n'
      'The directory should contain:\n'
      '  - manifest.json (level configuration)\n'
      '  - LEVEL_NAME/ subdirectories with share_N.key files\n'
      '\n'
      'Exit codes:\n'
      '  0  Reconstructed successfully\n'
      '  1  Error or insufficient shares\n'
      '\n'
      'Examples:\n'
      '  zegel hierarchical-split reconstruct shares/ -o recovered.key\n'
      '  zegel hierarchical-split reconstruct shares/ --levels "CONFIDENTIAL,SECRET" -o recovered.key';

  @override
  final String invocation =
      'zegel hierarchical-split reconstruct <shares-dir> [options]';

  HierarchicalSplitReconstructCommand() {
    addOutputOption(argParser, help: 'Output path for the reconstructed key.');

    argParser.addOption(
      'levels',
      abbr: 'l',
      help: 'Comma-separated level names to use (in order).\n'
          'If not specified, uses manifest.json.',
      valueHelp: 'level1,level2,...',
    );
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('No shares directory specified.', usage);
    }

    final sharesDir = argResults!.rest.first;
    final dir = Directory(sharesDir);

    if (!dir.existsSync()) {
      exitError('Shares directory not found: $sharesDir');
    }

    final outputPath = argResults!['output'] as String?;
    if (outputPath == null || outputPath.isEmpty) {
      exitError('Output path is required.');
    }

    // Read manifest.
    final manifestFile = File('$sharesDir/manifest.json');
    if (!manifestFile.existsSync()) {
      exitError('manifest.json not found in $sharesDir');
    }

    final manifestJson = jsonDecode(manifestFile.readAsStringSync());
    if (manifestJson['type'] != 'hierarchical_split_key') {
      exitError('Invalid manifest type. Expected "hierarchical_split_key".');
    }

    // Parse levels from manifest.
    final manifestLevels = (manifestJson['levels'] as List)
        .map(
          (l) => ShareLevel(
            classification: l['name'] as String,
            threshold: l['threshold'] as int,
            totalShares: l['total'] as int,
          ),
        )
        .toList();

    // Optionally filter to specific levels.
    List<ShareLevel> levels = manifestLevels;
    final levelsFilter = argResults!['levels'] as String?;
    if (levelsFilter != null && levelsFilter.isNotEmpty) {
      final filterNames =
          levelsFilter.split(',').map((s) => s.trim().toUpperCase()).toList();
      levels = manifestLevels
          .where((l) => filterNames.contains(l.classification))
          .toList();

      // Preserve order from manifest.
      levels.sort((a, b) {
        final aIdx = manifestLevels.indexWhere(
          (m) => m.classification == a.classification,
        );
        final bIdx = manifestLevels.indexWhere(
          (m) => m.classification == b.classification,
        );
        return aIdx.compareTo(bIdx);
      });
    }

    if (levels.isEmpty) {
      exitError('No valid levels found.');
    }

    // Read shares for each level.
    final providedShares = <LevelShares>[];
    for (final level in levels) {
      final levelDir = Directory('$sharesDir/${level.classification}');
      if (!levelDir.existsSync()) {
        exitError('Level directory not found: ${levelDir.path}');
      }

      final shareFiles = levelDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.key'))
          .toList();

      if (shareFiles.length < level.threshold) {
        exitError(
          'Level "${level.classification}" requires ${level.threshold} shares, '
          'but only ${shareFiles.length} found.',
        );
      }

      // Read up to threshold shares.
      final shares = <Uint8List>[];
      for (int i = 0; i < level.threshold && i < shareFiles.length; i++) {
        shares.add(Uint8List.fromList(shareFiles[i].readAsBytesSync()));
      }

      providedShares.add(
        LevelShares(classification: level.classification, shares: shares),
      );
    }

    // Reconstruct the master key.
    Uint8List masterKey;
    try {
      masterKey = HierarchicalSplitKey.reconstruct(providedShares, levels);
    } on ArgumentError catch (e) {
      exitError('Reconstruction failed: ${e.message}');
    }

    // Write output file.
    final outputFile = File(outputPath);
    outputFile.writeAsBytesSync(masterKey);

    // Print success message.
    stdout.writeln(Ansi.success('Key reconstructed successfully.'));
    stdout.writeln();
    stdout.writeln('  Output:  $outputPath');
    stdout.writeln('  Levels:  ${levels.length}');
    stdout.writeln('  Key:     ${hexEncode(masterKey)}');
    stdout.writeln();
    stdout.writeln(Ansi.header('Levels used:'));
    for (final level in levels) {
      stdout.writeln('  ${level.classification}: ${level.threshold} shares');
    }

    SecureMemory.wipe(masterKey);
    return 0;
  }
}
