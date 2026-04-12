import 'dart:convert';
import 'dart:io' hide BytesBuilder;
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// `zegel excerpt-proof` - Generate Merkle inclusion proof for specific blocks.
class ExcerptProofCommand extends Command<int> {
  ExcerptProofCommand() {
    argParser.addOption(
      'file',
      abbr: 'f',
      help: 'Path to the .zgl file.',
      valueHelp: 'path',
    );
    addKeyOptions(argParser);
    argParser.addOption(
      'block',
      abbr: 'b',
      help: 'Block index to generate proof for.',
      valueHelp: 'index',
    );
    addOutputOption(argParser, help: 'Output path for proof JSON.');
  }

  @override
  String get name => 'excerpt-proof';

  @override
  String get description => 'Generate a Merkle inclusion proof for a block.\n\n'
      'Creates a cryptographic proof that a specific block belongs to\n'
      'a sealed file, without revealing other blocks.\n\n'
      'Examples:\n'
      '  zegel excerpt-proof -f doc.zgl -k <hex-key> -b 0 -o proof.json';

  @override
  Future<int> run() async {
    final filePath = argResults!['file'] as String?;
    final blockStr = argResults!['block'] as String?;
    if (filePath == null || blockStr == null) {
      throw UsageException('--file and --block are required.', usage);
    }

    // final key = parseKeyFromArgs(argResults!);
    final blockIndex = int.parse(blockStr);

    final fileBytes = Uint8List.fromList(File(filePath).readAsBytesSync());
    final header = RawZegelHeader.parse(fileBytes);

    // Use the block hashes from the directory as leaf hashes
    final leafHashes =
        header.blockDirectory.map((e) => e.plaintextHash).toList();

    final proof = ExcerptProof.generateProof(leafHashes, blockIndex);

    final outputPath = argResults!['output'] as String? ?? 'excerpt_proof.json';
    File(
      outputPath,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(proof));

    stdout.writeln(Ansi.success('Excerpt proof generated'));
    stdout.writeln('  Block: $blockIndex');
    stdout.writeln('  Proof path: ${(proof["proof"] as List).length} nodes');
    stdout.writeln('  Output: $outputPath');
    return 0;
  }
}

/// `zegel verify-excerpt` - Verify an excerpt proof.
class VerifyExcerptCommand extends Command<int> {
  VerifyExcerptCommand() {
    argParser.addOption(
      'proof',
      abbr: 'p',
      help: 'Path to the proof JSON file.',
      valueHelp: 'path',
    );
    argParser.addOption(
      'file',
      abbr: 'f',
      help: 'Path to the .zgl file to verify against.',
      valueHelp: 'path',
    );
  }

  @override
  String get name => 'verify-excerpt';

  @override
  String get description => 'Verify a Merkle inclusion proof.\n\n'
      'Checks that an excerpt proof is valid against a sealed file\'s\n'
      'Merkle root.\n\n'
      'Examples:\n'
      '  zegel verify-excerpt -p proof.json -f doc.zgl';

  @override
  Future<int> run() async {
    final proofPath = argResults!['proof'] as String?;
    final filePath = argResults!['file'] as String?;
    if (proofPath == null || filePath == null) {
      throw UsageException('--proof and --file are required.', usage);
    }

    final proofData =
        jsonDecode(File(proofPath).readAsStringSync()) as Map<String, dynamic>;
    final fileBytes = Uint8List.fromList(File(filePath).readAsBytesSync());
    final header = RawZegelHeader.parse(fileBytes);

    final valid = ExcerptProof.verifyProof(proofData, header.merkleRoot);

    if (valid) {
      stdout.writeln(Ansi.success('✓ Excerpt proof is VALID'));
      stdout.writeln(
        '  Block ${proofData["block_index"]} verified against Merkle root',
      );
    } else {
      stdout.writeln(Ansi.error('✗ Excerpt proof is INVALID'));
    }
    return valid ? 0 : 1;
  }
}
