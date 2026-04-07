import 'dart:convert';
import 'dart:io' hide BytesBuilder;
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Parent command for media metadata operations.
///
/// Usage:
///   zegel media-metadata <subcommand> [options]
///
/// Subcommands:
///   extract  Extract metadata from a media file
///   view     View preserved metadata in a sealed file
class MediaMetadataCommand extends Command<int> {
  @override
  final String name = 'media-metadata';

  @override
  String get description => 'Media metadata extraction and viewing.\n'
      '\n'
      'Utilities for handling metadata from media files (images, videos,\n'
      'documents). Metadata can be extracted from raw files or viewed\n'
      'from sealed .zgl files that have preserved metadata.\n'
      '\n'
      'Subcommands:\n'
      '  extract  Extract metadata from a media file\n'
      '  view     View preserved metadata in a sealed file\n'
      '\n'
      'Examples:\n'
      '  zegel media-metadata extract photo.jpg\n'
      '  zegel media-metadata view document.zgl -k <key>';

  MediaMetadataCommand() {
    addSubcommand(MediaMetadataExtractCommand());
    addSubcommand(MediaMetadataViewCommand());
  }

  @override
  Future<int> run() async {
    // Show help if no subcommand specified.
    printUsage();
    return 0;
  }
}

/// Extracts metadata from a media file.
class MediaMetadataExtractCommand extends Command<int> {
  @override
  final String name = 'extract';

  @override
  String get description => 'Extract metadata from a media file.\n'
      '\n'
      'Reads a media file (image, video, document) and extracts basic\n'
      'metadata including file size, content hash, and detected file type.\n'
      '\n'
      'Exit codes:\n'
      '  0  Success\n'
      '  1  Error\n'
      '\n'
      'Examples:\n'
      '  zegel media-metadata extract photo.jpg\n'
      '  zegel media-metadata extract document.pdf --json\n'
      '  zegel media-metadata extract video.mp4 -o metadata.json';

  @override
  final String invocation = 'zegel media-metadata extract <file> [options]';

  MediaMetadataExtractCommand() {
    argParser.addFlag(
      'json',
      help: 'Output metadata as JSON.',
      defaultsTo: false,
    );

    addOutputOption(
      argParser,
      help: 'Output path for metadata JSON file.',
    );
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('No file specified.', usage);
    }

    final filePath = argResults!.rest.first;
    final file = File(filePath);

    if (!file.existsSync()) {
      exitError('File not found: $filePath');
    }

    final content = Uint8List.fromList(file.readAsBytesSync());
    final filename = file.uri.pathSegments.last;

    // Extract metadata using the library.
    final metadata = MediaMetadata.extractBasicMetadata(content, filename);

    // Add additional info.
    metadata['extraction_time'] = DateTime.now().toUtc().toIso8601String();

    final jsonOutput = argResults!['json'] as bool;
    final outputPath = argResults!['output'] as String?;

    if (outputPath != null && outputPath.isNotEmpty) {
      final outputFile = File(outputPath);
      outputFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(metadata),
      );
      stdout.writeln(Ansi.success('Metadata saved to $outputPath'));
      return 0;
    }

    if (jsonOutput) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(metadata));
      return 0;
    }

    // Human-readable output.
    stdout.writeln(Ansi.header('Media Metadata - $filePath'));
    stdout.writeln();
    stdout.writeln('  Filename:     ${metadata['filename']}');
    stdout.writeln(
        '  File size:    ${formatFileSize(metadata['file_size'] as int)}');
    stdout.writeln('  Detected type: ${metadata['detected_type']}');
    stdout.writeln('  Content hash: ${metadata['content_hash']}');

    return 0;
  }
}

/// Views preserved metadata in a sealed .zgl file.
class MediaMetadataViewCommand extends Command<int> {
  @override
  final String name = 'view';

  @override
  String get description => 'View preserved metadata in a sealed .zgl file.\n'
      '\n'
      'Displays metadata that was preserved when the file was sealed\n'
      'with the --preserve-media-metadata flag. This includes both the\n'
      'original file metadata and any provenance information.\n'
      '\n'
      'Exit codes:\n'
      '  0  Success\n'
      '  1  Error\n'
      '\n'
      'Examples:\n'
      '  zegel media-metadata view document.zgl -k <key>\n'
      '  zegel media-metadata view photo.zgl --key-file master.key --json';

  @override
  final String invocation = 'zegel media-metadata view <file.zgl> [options]';

  MediaMetadataViewCommand() {
    addKeyOptions(argParser);

    argParser.addFlag(
      'json',
      help: 'Output metadata as JSON.',
      defaultsTo: false,
    );
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('No .zgl file specified.', usage);
    }

    final filePath = argResults!.rest.first;
    final file = File(filePath);

    if (!file.existsSync()) {
      exitError('File not found: $filePath');
    }

    // Parse master key.
    final masterKey = parseKeyFromArgs(argResults!);
    if (masterKey.length != 32) {
      exitError(
        'Master key must be exactly 32 bytes (64 hex characters). '
        'Got ${masterKey.length} bytes.',
      );
    }

    final fileBytes = Uint8List.fromList(file.readAsBytesSync());

    // Verify and extract the file.
    const reader = ZegelReader();
    ZegelResult result;
    try {
      result = reader.verify(fileBytes, masterKey);
    } on ZegelException catch (e) {
      exitError('File verification failed: ${e.message}');
    }

    // Ensure we have valid content.
    if (result.content == null) {
      exitError('Failed to extract content from file.');
    }
    final content = result.content!;
    final filename = result.filename ?? 'unknown';

    // Collect all metadata.
    final allMetadata = <String, dynamic>{
      'file': filePath,
      'filename': result.filename,
      'content_type': result.contentType,
      'file_size': content.length,
    };

    // Add encrypted metadata if present.
    if (result.metadata != null && result.metadata!.isNotEmpty) {
      allMetadata['encrypted_metadata'] = result.metadata;
    }

    // Check for public metadata.
    final rawHeader = RawZegelHeader.parse(fileBytes);
    if (rawHeader.publicMetadata != null) {
      allMetadata['public_metadata'] = rawHeader.publicMetadata;
    }

    // Extract media-specific metadata from content.
    final contentMetadata = MediaMetadata.extractBasicMetadata(
      content,
      filename,
    );
    allMetadata['content_analysis'] = contentMetadata;

    // Check for provenance entries.
    if (result.provenance != null && result.provenance!.isNotEmpty) {
      allMetadata['provenance'] = result.provenance;
    }

    final jsonOutput = argResults!['json'] as bool;

    if (jsonOutput) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(allMetadata));
      return 0;
    }

    // Human-readable output.
    stdout.writeln(Ansi.header('Media Metadata - $filePath'));
    stdout.writeln();
    stdout.writeln(Ansi.header('File Information:'));
    stdout.writeln('  Filename:      ${result.filename}');
    stdout.writeln('  Content type:  ${result.contentType}');
    stdout.writeln('  Content size:  ${formatFileSize(content.length)}');

    stdout.writeln();
    stdout.writeln(Ansi.header('Content Analysis:'));
    stdout.writeln('  Detected type: ${contentMetadata['detected_type']}');
    stdout.writeln('  Content hash:  ${contentMetadata['content_hash']}');

    if (result.metadata != null && result.metadata!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('Encrypted Metadata:'));
      for (final entry in result.metadata!.entries) {
        stdout.writeln('  ${entry.key}: ${entry.value}');
      }
    }

    if (rawHeader.publicMetadata != null &&
        rawHeader.publicMetadata!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('Public Metadata:'));
      for (final entry in rawHeader.publicMetadata!.entries) {
        stdout.writeln('  ${entry.key}: ${entry.value}');
      }
    }

    if (result.provenance != null && result.provenance!.isNotEmpty) {
      stdout.writeln();
      stdout.writeln(Ansi.header('Provenance:'));
      for (int i = 0; i < result.provenance!.length; i++) {
        final prov = result.provenance![i];
        stdout.writeln('  Entry ${i + 1}:');
        for (final entry in prov.entries) {
          stdout.writeln('    ${entry.key}: ${entry.value}');
        }
      }
    }

    return 0;
  }
}
