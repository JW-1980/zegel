import 'dart:convert';
import 'dart:io' hide BytesBuilder;
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// `zegel manifest-create` - Create a signed manifest for multiple .zgl files.
class ManifestCreateCommand extends Command<int> {
  ManifestCreateCommand() {
    argParser.addOption(
      'directory',
      abbr: 'd',
      help: 'Directory containing .zgl files to include.',
      valueHelp: 'path',
    );
    addKeyOptions(argParser);
    argParser.addOption(
      'signer-id',
      help: 'Identifier of the manifest signer.',
      valueHelp: 'id',
    );
    addOutputOption(argParser, help: 'Output path for manifest JSON.');
  }

  @override
  String get name => 'manifest-create';

  @override
  String get description =>
      'Create a signed manifest from a collection of .zgl files.\n'
      '\n'
      'Generates a JSON manifest listing all .zgl files in a directory\n'
      'with their Merkle roots, signed with HMAC-SHA256 using the\n'
      'provided key. Use "zegel manifest-verify" to verify later.\n'
      '\n'
      'The manifest includes each file\'s Merkle root, allowing\n'
      'verification that no files have been added, removed, or replaced.\n'
      '\n'
      'Exit codes:\n'
      '  0  Manifest created successfully\n'
      '  1  Error\n'
      '\n'
      'Examples:\n'
      '  zegel manifest-create -d ./sealed/ -k <hex-key> --signer-id admin -o manifest.json\n'
      '  zegel manifest-create -d ./archive/ --key-file sign.key --signer-id archiver -o manifest.json';

  @override
  Future<int> run() async {
    final dirPath = argResults!['directory'] as String?;
    final signerId = argResults!['signer-id'] as String?;
    final outputPath = argResults!['output'] as String?;
    if (dirPath == null || signerId == null || outputPath == null) {
      throw UsageException(
        '--directory, --signer-id, and --output are required.',
        usage,
      );
    }

    final key = parseKeyFromArgs(argResults!);
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      stderr.writeln('${Ansi.error('Error:')} Directory not found: $dirPath');
      return 1;
    }

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.zgl'))
        .toList();

    if (files.isEmpty) {
      stdout.writeln('No .zgl files found in $dirPath');
      return 1;
    }

    final entries = <String, Uint8List>{};
    for (final file in files) {
      final name = file.path.split(Platform.pathSeparator).last;
      final bytes = Uint8List.fromList(file.readAsBytesSync());
      final header = RawZegelHeader.parse(bytes);
      entries[name] = header.merkleRoot;
    }

    final manifest = ZegelManifest.create(entries, key, signerId);
    File(
      outputPath,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));

    stdout.writeln(
      "${Ansi.success('Manifest created')} with ${entries.length} file(s)",
    );
    stdout.writeln('  Output: $outputPath');
    return 0;
  }
}

/// `zegel manifest-verify` - Verify a manifest against .zgl files.
class ManifestVerifyCommand extends Command<int> {
  ManifestVerifyCommand() {
    argParser.addOption(
      'manifest',
      abbr: 'm',
      help: 'Path to the manifest JSON file.',
      valueHelp: 'path',
    );
    argParser.addOption(
      'directory',
      abbr: 'd',
      help: 'Directory containing .zgl files to verify against.',
      valueHelp: 'path',
    );
    addKeyOptions(argParser);
  }

  @override
  String get name => 'manifest-verify';

  @override
  String get description => 'Verify a manifest against .zgl files on disk.\n'
      '\n'
      'Checks that the manifest signature is valid, then verifies\n'
      'that each file listed in the manifest exists in the directory\n'
      'and its Merkle root matches the manifest entry.\n'
      '\n'
      'Exit codes:\n'
      '  0  All files match the manifest\n'
      '  1  Signature invalid or one or more files do not match\n'
      '\n'
      'Examples:\n'
      '  zegel manifest-verify -m manifest.json -d ./sealed/ -k <hex-key>\n'
      '  zegel manifest-verify -m manifest.json -d ./archive/ --key-file sign.key';

  @override
  Future<int> run() async {
    final manifestPath = argResults!['manifest'] as String?;
    final dirPath = argResults!['directory'] as String?;
    if (manifestPath == null || dirPath == null) {
      throw UsageException('--manifest and --directory are required.', usage);
    }

    final key = parseKeyFromArgs(argResults!);
    final manifestFile = File(manifestPath);
    if (!manifestFile.existsSync()) {
      stderr.writeln(
        "${Ansi.error('Error:')} Manifest not found: $manifestPath",
      );
      return 1;
    }

    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;

    // Verify manifest signature
    if (!ZegelManifest.verify(manifest, key)) {
      stderr.writeln("${Ansi.error('Error:')} Manifest signature is invalid");
      return 1;
    }
    stdout.writeln("${Ansi.success('✓')} Manifest signature valid");

    // Check files
    final dir = Directory(dirPath);
    final actualRoots = <String, Uint8List>{};
    for (final file in dir.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.zgl'),
        )) {
      final name = file.path.split(Platform.pathSeparator).last;
      final bytes = Uint8List.fromList(file.readAsBytesSync());
      final header = RawZegelHeader.parse(bytes);
      actualRoots[name] = header.merkleRoot;
    }

    final fileResults = ZegelManifest.checkFiles(manifest, actualRoots);
    int matched = 0;
    int missing = 0;

    for (final entry in fileResults.entries) {
      if (entry.value) {
        stdout.writeln('  ${Ansi.success("✓")} ${entry.key}');
        matched++;
      } else {
        stdout.writeln('  ${Ansi.error("✗")} ${entry.key}');
        missing++;
      }
    }

    stdout.writeln();
    stdout.writeln('$matched matched, $missing failed');
    return missing > 0 ? 1 : 0;
  }
}
