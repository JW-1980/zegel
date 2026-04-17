import 'dart:io' hide BytesBuilder;
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// `zegel batch-verify` - Verify multiple .zgl files at once.
class BatchVerifyCommand extends Command<int> {
  BatchVerifyCommand() {
    argParser.addOption(
      'directory',
      abbr: 'd',
      help: 'Directory containing .zgl files to verify.',
      valueHelp: 'path',
    );
    addKeyOptions(argParser);
    argParser.addFlag(
      'stop-on-failure',
      help: 'Stop on first verification failure.',
      defaultsTo: false,
    );
    argParser.addFlag(
      'verbose',
      abbr: 'v',
      help: 'Show detailed output for each file.',
    );
  }

  @override
  String get name => 'batch-verify';

  @override
  String get description =>
      'Verify the integrity of multiple .zgl files at once.\n'
      '\n'
      'Scans the given directory for .zgl files and verifies each one\n'
      'against the provided master key. Produces a summary table with\n'
      'the filename, verification status, and elapsed time.\n'
      '\n'
      'Use --stop-on-failure to halt processing after the first\n'
      'verification failure, useful in CI/CD pipelines.\n'
      '\n'
      'Exit codes:\n'
      '  0  All files VALID\n'
      '  1  One or more files TAMPERED, EXPIRED, or errored\n'
      '\n'
      'Examples:\n'
      '  zegel batch-verify -d ./contracts/ -k <hex-key>\n'
      '  zegel batch-verify -d ./archive/ --key-file my.key --stop-on-failure\n'
      '  zegel batch-verify -d ./sealed/ -k <hex> --verbose';

  @override
  Future<int> run() async {
    final dirPath = argResults!['directory'] as String?;
    if (dirPath == null) {
      throw UsageException('--directory (-d) is required.', usage);
    }

    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      stderr.writeln("${Ansi.error('Error:')} Directory not found: $dirPath");
      return 1;
    }

    final key = parseKeyFromArgs(argResults!);
    final stopOnFailure = argResults!['stop-on-failure'] as bool;

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.zgl'))
        .toList();

    if (files.isEmpty) {
      stdout.writeln('No .zgl files found in $dirPath');
      return 0;
    }

    stdout.writeln('Verifying ${files.length} file(s)...');
    stdout.writeln();

    final entries = await Future.wait(files.map((f) async => MapEntry(
        f.path.split(Platform.pathSeparator).last, await f.readAsBytes())));
    final results = BatchOperations.batchVerify(
      entries,
      key,
      stopOnFirstFailure: stopOnFailure,
    );

    final rows = <List<String>>[
      ['File', 'Status', 'Time'],
    ];
    int passed = 0;
    int failed = 0;

    for (final r in results) {
      final success = r['success'] as bool;
      if (success) {
        passed++;
      } else {
        failed++;
      }
      rows.add([
        r['name'] as String,
        success ? Ansi.success('VALID') : Ansi.error('FAILED'),
        '${r['duration_ms']}ms',
      ]);
    }

    printTable(rows);
    stdout.writeln();
    stdout.writeln(
      '${Ansi.success("$passed passed")}, ${failed > 0 ? Ansi.error("$failed failed") : "$failed failed"}',
    );

    return failed > 0 ? 1 : 0;
  }
}

/// `zegel batch-seal` - Seal multiple files at once.
class BatchSealCommand extends Command<int> {
  BatchSealCommand() {
    argParser.addOption(
      'directory',
      abbr: 'd',
      help: 'Directory containing files to seal.',
      valueHelp: 'path',
    );
    addKeyOptions(argParser);
    addOutputOption(argParser, help: 'Output directory for .zgl files.');
    argParser.addFlag(
      'compress',
      abbr: 'c',
      help: 'Compress content blocks with zlib.',
    );
    argParser.addOption(
      'content-type',
      help: 'Content type for all files.',
      valueHelp: 'mime-type',
    );
  }

  @override
  String get name => 'batch-seal';

  @override
  String get description =>
      'Seal multiple files from a directory into .zgl containers.\n'
      '\n'
      'Reads all files from the input directory and creates .zgl\n'
      'containers in the output directory. All files are sealed\n'
      'with the same master key.\n'
      '\n'
      'Use --compress to enable zlib compression on all files.\n'
      'Use --content-type to set a uniform MIME type for all files.\n'
      '\n'
      'Exit codes:\n'
      '  0  All files sealed successfully\n'
      '  1  One or more files failed\n'
      '\n'
      'Examples:\n'
      '  zegel batch-seal -d ./documents/ -k <hex-key> -o ./sealed/\n'
      '  zegel batch-seal -d ./images/ --key-file my.key -o ./sealed/ --compress\n'
      '  zegel batch-seal -d ./data/ -k <hex> -o ./sealed/ --content-type application/json';

  @override
  Future<int> run() async {
    final dirPath = argResults!['directory'] as String?;
    final outputPath = argResults!['output'] as String?;
    if (dirPath == null || outputPath == null) {
      throw UsageException(
        '--directory (-d) and --output (-o) are required.',
        usage,
      );
    }

    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      stderr.writeln("${Ansi.error('Error:')} Directory not found: $dirPath");
      return 1;
    }

    final outputDir = Directory(outputPath);
    if (!outputDir.existsSync()) {
      outputDir.createSync(recursive: true);
    }

    final key = parseKeyFromArgs(argResults!);
    final compress = argResults!['compress'] as bool;
    final contentType = argResults!['content-type'] as String?;

    final files = dir.listSync().whereType<File>().toList();
    if (files.isEmpty) {
      stdout.writeln('No files found in $dirPath');
      return 0;
    }

    stdout.writeln('Sealing ${files.length} file(s)...');
    int sealed = 0;

    // Chunking to avoid "Too many open files" when batching a massive number of files.
    const chunkSize = 50;
    for (var i = 0; i < files.length; i += chunkSize) {
      final chunk = files.sublist(
        i,
        i + chunkSize > files.length ? files.length : i + chunkSize,
      );

      final tasks = chunk.map((file) async {
        final name = file.path.split(Platform.pathSeparator).last;
        final content = Uint8List.fromList(await file.readAsBytes());

        final sealedBytes = await Future.microtask(() {
          final writer = ZegelWriter(
            key,
            ZegelOptions(
              contentType: contentType ?? 'application/octet-stream',
              filename: name,
              compress: compress,
              enableKeyCommitment: true,
            ),
          );
          return writer.seal(content);
        });

        await File(
          '${outputDir.path}${Platform.pathSeparator}$name.zgl',
        ).writeAsBytes(sealedBytes);

        stdout.writeln('  ${Ansi.success("✓")} $name -> $name.zgl');
      });

      await Future.wait(tasks);
      sealed += chunk.length;
    }

    stdout.writeln();
    stdout.writeln('${Ansi.success("$sealed file(s) sealed")} to $outputPath');
    return 0;
  }
}
