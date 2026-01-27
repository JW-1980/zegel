import 'dart:io';

import 'package:args/command_runner.dart';

import 'package:zegel_cli/commands/seal_command.dart';
import 'package:zegel_cli/commands/verify_command.dart';
import 'package:zegel_cli/commands/extract_command.dart';
import 'package:zegel_cli/commands/inspect_command.dart';
import 'package:zegel_cli/commands/keygen_command.dart';
import 'package:zegel_cli/commands/redact_command.dart';
import 'package:zegel_cli/commands/split_key_command.dart';
import 'package:zegel_cli/commands/attest_command.dart';
import 'package:zegel_cli/commands/disclose_command.dart';

/// Zegel CLI - tamper-proof container format tool.
///
/// Provides commands for sealing, verifying, extracting, and managing
/// files in the Zegel (.zgl) format.
void main(List<String> arguments) async {
  final runner = CommandRunner<int>(
    'zegel',
    'Zegel - tamper-proof container format (v1.2)\n'
        '\n'
        'Seal any file so that modifying a single byte makes\n'
        'the entire content physically unreadable.',
  );

  // Core commands.
  runner.addCommand(SealCommand());
  runner.addCommand(VerifyCommand());
  runner.addCommand(ExtractCommand());
  runner.addCommand(InspectCommand());
  runner.addCommand(KeygenCommand());

  // Advanced commands.
  runner.addCommand(RedactCommand());
  runner.addCommand(SplitKeyCommand());
  runner.addCommand(ReconstructCommand());
  runner.addCommand(AttestCommand());
  runner.addCommand(DiscloseCommand());
  runner.addCommand(ExtractWithTokenCommand());

  try {
    final exitCode = await runner.run(arguments) ?? 0;
    exit(exitCode);
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln();
    stderr.writeln(e.usage);
    exit(64); // EX_USAGE from sysexits.h
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    exit(1);
  } on FileSystemException catch (e) {
    stderr.writeln('Error: ${e.message}');
    if (e.path != null) {
      stderr.writeln('  Path: ${e.path}');
    }
    exit(1);
  } catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }
}
