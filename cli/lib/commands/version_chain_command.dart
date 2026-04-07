import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// `zegel version-chain-verify` - Verify a chain of versioned .zgl files.
class VersionChainVerifyCommand extends Command<int> {
  VersionChainVerifyCommand() {
    argParser.addMultiOption('files',
      help: 'Ordered list of .zgl files in the version chain (oldest first).',
      valueHelp: 'path');
  }

  @override
  String get name => 'version-chain-verify';

  @override
  String get description =>
      'Verify that a sequence of .zgl files form a valid version chain.\n'
      '\n'
      'Checks that each file (except the first) contains a version\n'
      'chain hash that matches the Merkle root and master seal of\n'
      'the previous file. This proves the files were created in\n'
      'sequence and each version acknowledges the previous one.\n'
      '\n'
      'Files must be provided in chronological order (oldest first).\n'
      '\n'
      'Exit codes:\n'
      '  0  Chain is VALID - all links verified\n'
      '  1  Chain is BROKEN or error\n'
      '\n'
      'Examples:\n'
      '  zegel version-chain-verify --files v1.zgl --files v2.zgl --files v3.zgl\n'
      '  zegel version-chain-verify --files draft.zgl --files review.zgl --files final.zgl';

  @override
  Future<int> run() async {
    final filePaths = argResults!['files'] as List<String>;
    if (filePaths.length < 2) {
      throw UsageException('At least 2 files are needed for chain verification.', usage);
    }

    stdout.writeln('Verifying version chain of ${filePaths.length} file(s)...');
    stdout.writeln();

    bool allValid = true;

    for (int i = 0; i < filePaths.length; i++) {
      final file = File(filePaths[i]);
      if (!file.existsSync()) {
        stderr.writeln("${Ansi.error('Error:')} File not found: ${filePaths[i]}");
        return 1;
      }

      final bytes = Uint8List.fromList(file.readAsBytesSync());
      final header = RawZegelHeader.parse(bytes);
      final name = filePaths[i].split(Platform.pathSeparator).last;

      if (i == 0) {
        // First file: no chain hash expected
        if (header.versionChainHash != null) {
          stdout.writeln('  ${Ansi.info("ℹ")} $name has chain hash (references prior version)');
        } else {
          stdout.writeln('  ${Ansi.success("✓")} $name (chain start)');
        }
      } else {
        // Subsequent files: verify chain hash
        if (header.versionChainHash == null) {
          stdout.writeln('  ${Ansi.error("✗")} $name: missing version chain hash');
          allValid = false;
          continue;
        }

        final prevBytes = Uint8List.fromList(File(filePaths[i - 1]).readAsBytesSync());
        final prevHeader = RawZegelHeader.parse(prevBytes);
        final prevSeal = Uint8List.fromList(
          prevBytes.sublist(prevBytes.length - ZegelFormat.sealSize),
        );

        final valid = ContentVersioning.verifyChain(
          header.versionChainHash!,
          prevHeader.merkleRoot,
          prevSeal,
        );

        if (valid) {
          stdout.writeln('  ${Ansi.success("✓")} $name links to ${filePaths[i - 1].split(Platform.pathSeparator).last}');
        } else {
          stdout.writeln('  ${Ansi.error("✗")} $name: chain hash mismatch');
          allValid = false;
        }
      }
    }

    stdout.writeln();
    if (allValid) {
      stdout.writeln(Ansi.success('Version chain is valid'));
    } else {
      stdout.writeln(Ansi.error('Version chain verification failed'));
    }
    return allValid ? 0 : 1;
  }
}
