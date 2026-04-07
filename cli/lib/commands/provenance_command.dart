import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// `zegel provenance-verify` - Verify provenance chain of a file.
class ProvenanceVerifyCommand extends Command<int> {
  ProvenanceVerifyCommand() {
    argParser.addOption('provenance', abbr: 'p',
      help: 'Path to provenance chain JSON file.',
      valueHelp: 'path');
    addKeyOptions(argParser);
  }

  @override
  String get name => 'provenance-verify';

  @override
  String get description =>
      'Verify the provenance (chain of custody) events for a sealed file.\n'
      '\n'
      'Reads a provenance chain JSON file and verifies:\n'
      '  - Chronological ordering of events\n'
      '  - Chain hash integrity (each event references the previous)\n'
      '  - Event signatures using the provided key\n'
      '\n'
      'PROVENANCE events record lifecycle actions like creation,\n'
      'transfer, attestation, redaction, and other custody changes.\n'
      '\n'
      'Exit codes:\n'
      '  0  Provenance chain verified successfully\n'
      '  1  Error (chain broken, signature invalid, etc.)\n'
      '\n'
      'Examples:\n'
      '  zegel provenance-verify -p provenance.json -k <hex-key>\n'
      '  zegel provenance-verify -p chain.json --key-file audit.key';

  @override
  Future<int> run() async {
    final provPath = argResults!['provenance'] as String?;
    if (provPath == null) {
      throw UsageException('--provenance is required.', usage);
    }

    final key = parseKeyFromArgs(argResults!);
    final provFile = File(provPath);
    if (!provFile.existsSync()) {
      stderr.writeln("${Ansi.error('Error:')} Provenance file not found: $provPath");
      return 1;
    }

    final events = (jsonDecode(provFile.readAsStringSync()) as List<dynamic>)
        .cast<Map<String, dynamic>>();

    stdout.writeln('Verifying provenance chain (${events.length} events)...');
    stdout.writeln();

    final result = ProvenanceVerification.verifyChain(events, key);
    final valid = result['valid'] as bool;
    final errors = result['errors'] as List<dynamic>;

    // Display events
    for (int i = 0; i < events.length; i++) {
      final e = events[i];
      final ts = DateTime.fromMillisecondsSinceEpoch(
        (e['timestamp'] as int) * 1000, isUtc: true,
      );
      stdout.writeln('  ${i + 1}. ${e["action"]} by ${e["actor"]} at ${formatTimestamp(ts)}');
    }

    stdout.writeln();
    if (valid) {
      stdout.writeln(Ansi.success('✓ Provenance chain is valid'));
    } else {
      stdout.writeln(Ansi.error('✗ Provenance chain verification failed:'));
      for (final err in errors) {
        stdout.writeln('    - $err');
      }
    }
    return valid ? 0 : 1;
  }
}
