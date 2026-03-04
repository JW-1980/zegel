import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// `zegel classify` - Set classification level on a .zgl file.
class ClassifyCommand extends Command<int> {
  ClassifyCommand() {
    argParser.addOption('file', abbr: 'f',
      help: 'Path to the .zgl file.',
      valueHelp: 'path');
    argParser.addOption('level', abbr: 'l',
      help: 'Classification level (PUBLIC, INTERNAL, CONFIDENTIAL, SECRET, TOP_SECRET).',
      valueHelp: 'level');
    argParser.addOption('authority',
      help: 'Authority setting the classification.',
      valueHelp: 'name');
    argParser.addMultiOption('caveats',
      help: 'Handling caveats (e.g. NOFORN, REL_TO).',
      valueHelp: 'caveat');
    addOutputOption(argParser, help: 'Output file path for classified metadata.');
  }

  @override
  String get name => 'classify';

  @override
  String get description =>
      'Set or update the classification level on a .zgl file.\n'
      '\n'
      'Adds or updates the classification metadata for a sealed file.\n'
      'The classification is stored as structured metadata that can be\n'
      'queried and enforced by access control systems.\n'
      '\n'
      'Valid classification levels (ascending sensitivity):\n'
      '  PUBLIC, INTERNAL, CONFIDENTIAL, SECRET, TOP_SECRET\n'
      '\n'
      'Caveats can be added to restrict handling further (e.g.,\n'
      '"NOFORN", "REL_TO").\n'
      '\n'
      'Exit codes:\n'
      '  0  Classification set successfully\n'
      '  1  Error\n'
      '\n'
      'Examples:\n'
      '  zegel classify -f doc.zgl -l CONFIDENTIAL --authority "Security Officer"\n'
      '  zegel classify -f doc.zgl -l SECRET --authority "CISO" --caveats NOFORN\n'
      '  zegel classify -f doc.zgl -l TOP_SECRET --authority "Director" --caveats NOFORN --caveats "REL_TO PROJ-X"';

  @override
  Future<int> run() async {
    final filePath = argResults!['file'] as String?;
    final level = argResults!['level'] as String?;
    final authority = argResults!['authority'] as String?;
    if (filePath == null || level == null || authority == null) {
      throw UsageException('--file, --level, and --authority are required.', usage);
    }

    final normalized = validateClassificationLevel(level);
    final caveats = argResults!['caveats'] as List<String>;

    final metadata = Classification.createClassificationMetadata(
      level: normalized,
      authority: authority,
      caveat: caveats.isNotEmpty ? caveats.join(', ') : null,
    );

    final outputPath = argResults!['output'] as String? ?? '$filePath.classification.json';
    File(outputPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(metadata),
    );

    stdout.writeln('Classification set: ${Ansi.warning(normalized)}');
    stdout.writeln('  Authority: $authority');
    if (caveats.isNotEmpty) {
      stdout.writeln('  Caveats: ${caveats.join(", ")}');
    }
    stdout.writeln('  Output: $outputPath');
    return 0;
  }
}

/// `zegel declassify` - Lower classification level.
class DeclassifyCommand extends Command<int> {
  DeclassifyCommand() {
    argParser.addOption('file', abbr: 'f',
      help: 'Path to the classification JSON.',
      valueHelp: 'path');
    argParser.addOption('current-level',
      help: 'Current classification level.',
      valueHelp: 'level');
    argParser.addOption('new-level',
      help: 'New (lower) classification level.',
      valueHelp: 'level');
    argParser.addOption('authority',
      help: 'Authority approving declassification.',
      valueHelp: 'name');
    argParser.addOption('reason',
      help: 'Reason for declassification.');
    addOutputOption(argParser);
  }

  @override
  String get name => 'declassify';

  @override
  String get description =>
      'Reduce the classification level of a sealed file.\n'
      '\n'
      'Creates a formal declassification record lowering the classification\n'
      'level. The new level must be strictly lower than the current level.\n'
      'A reason can be provided for audit trail purposes.\n'
      '\n'
      'Exit codes:\n'
      '  0  Declassification record created\n'
      '  1  Error (invalid level, new level not lower, etc.)\n'
      '\n'
      'Examples:\n'
      '  zegel declassify --current-level SECRET --new-level INTERNAL --authority "Director" -o declass.json\n'
      '  zegel declassify --current-level CONFIDENTIAL --new-level PUBLIC --authority "Records Mgr" --reason "Retention period expired" -o declass.json';

  @override
  Future<int> run() async {
    final currentLevel = argResults!['current-level'] as String?;
    final newLevel = argResults!['new-level'] as String?;
    final authority = argResults!['authority'] as String?;
    if (currentLevel == null || newLevel == null || authority == null) {
      throw UsageException(
        '--current-level, --new-level, and --authority are required.', usage);
    }

    final normalizedCurrent = validateClassificationLevel(currentLevel);
    final normalizedNew = validateClassificationLevel(newLevel);
    final reason = argResults!['reason'] as String?;

    // Validate that the new level is less restrictive.
    if (Classification.compare(normalizedNew, normalizedCurrent) >= 0) {
      exitError(
        'New level "$normalizedNew" must be less restrictive than '
        'current level "$normalizedCurrent".',
      );
    }

    final record = <String, dynamic>{
      'action': 'declassify',
      'previous_level': normalizedCurrent,
      'new_level': normalizedNew,
      'authority': authority,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      if (reason != null) 'reason': reason,
    };

    final outputPath = argResults!['output'] as String? ?? 'declassification.json';
    File(outputPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(record),
    );

    stdout.writeln('Declassification: $normalizedCurrent -> ${Ansi.success(normalizedNew)}');
    stdout.writeln('  Authority: $authority');
    if (reason != null) stdout.writeln('  Reason: $reason');
    stdout.writeln('  Output: $outputPath');
    return 0;
  }
}
