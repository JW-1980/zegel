import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:zegel/zegel.dart';

import 'common.dart';

/// Parent command for creative proof-of-origination operations.
///
/// ```
/// zegel creative seal <file> --signing-key <key> -k <master-key> ...
/// zegel creative verify <file.zgl> -k <master-key>
/// zegel creative inspect <file.zgl>
/// zegel creative extract <file.zgl> -k <master-key> -o <output>
/// ```
class CreativeCommand extends Command<int> {
  @override
  final String name = 'creative';

  @override
  final String description =
      'Creative proof-of-origination: seal creative works with\n'
      'creator identity, Ed25519 signature, and optional ID document scans.\n'
      'Proves who created what, and when.';

  CreativeCommand() {
    addSubcommand(CreativeSealCommand());
    addSubcommand(CreativeVerifyCommand());
    addSubcommand(CreativeInspectCommand());
    addSubcommand(CreativeExtractCommand());
  }
}

// ---------------------------------------------------------------------------
// creative seal
// ---------------------------------------------------------------------------

class CreativeSealCommand extends Command<int> {
  @override
  final String name = 'seal';

  @override
  final String description =
      'Seal a creative work with proof-of-origination.\n'
      '\n'
      'Embeds creator identity, Ed25519 signature binding the content hash\n'
      'to the creator, and optional ID document scans.\n'
      '\n'
      'Examples:\n'
      '  zegel creative seal song.mp3 --signing-key creator.key -k <hex> \\\n'
      '      --first-name Alice --family-name Nakamoto --city Amsterdam\n'
      '  zegel creative seal photo.jpg --signing-key creator.key -k <hex> \\\n'
      '      --first-name Bob --family-name Smith --id-scan passport.jpg';

  CreativeSealCommand() {
    addKeyOptions(argParser);
    argParser.addOption(
      'signing-key',
      abbr: 's',
      help: 'Path to 32-byte Ed25519 private key (or 64-char hex file).',
      mandatory: true,
    );
    addOutputOption(
      argParser,
      help: 'Output .zgl file path. Defaults to <input>.zgl.',
    );

    // Creator identity fields.
    argParser.addOption('first-name',
        help: 'Creator first name.', mandatory: true);
    argParser.addOption('family-name',
        help: 'Creator family name.', mandatory: true);
    argParser.addOption('middle-name', help: 'Creator middle name.');
    argParser.addOption('date-of-birth',
        help: 'Creator date of birth (YYYY-MM-DD).');
    argParser.addOption('address', help: 'Creator street address.');
    argParser.addOption('zip-code', help: 'Creator zip/postal code.');
    argParser.addOption('city', help: 'Creator city.');
    argParser.addOption('state', help: 'Creator state/province.');
    argParser.addOption('country', help: 'Creator country (ISO 3166-1 alpha-2).');
    argParser.addOption('company', help: 'Creator company name.');
    argParser.addOption('company-reg',
        help: 'Company registration number (e.g. KvK).');
    argParser.addOption('email', help: 'Creator email address.');
    argParser.addOption('phone', help: 'Creator phone number.');
    argParser.addOption('website', help: 'Creator website URL.');
    argParser.addOption('title', help: 'Creator professional title.');

    // Work metadata.
    argParser.addOption('work-title', help: 'Title of the creative work.');
    argParser.addOption('work-description',
        help: 'Description of the work.');
    argParser.addOption('work-type',
        help: 'Type of creative work.\n'
            'Options: music, image, video, photo, document, software,\n'
            '         design, animation, poem, screenplay, other.',
        defaultsTo: 'other');
    argParser.addMultiOption('tag',
        help: 'Tag(s) for the work (can be repeated).');

    // ID document scans.
    argParser.addMultiOption('id-scan',
        help: 'Path to ID document scan image (can be repeated).\n'
            'Format: <type>:<path> where type is passport, id-card,\n'
            'driver-license, residence-permit, or other.\n'
            'Example: --id-scan passport:scan.jpg');

    // Options.
    argParser.addFlag('compress',
        help: 'Enable zlib compression.', defaultsTo: false);
    argParser.addFlag('private-identity',
        help: 'Exclude creator identity from public metadata.\n'
            'Identity will only be visible with the master key.',
        defaultsTo: false);
    argParser.addOption('content-type',
        help: 'MIME type override (auto-detected from extension by default).');
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('No input file specified.');
    }

    final inputPath = argResults!.rest.first;
    final inputFile = File(inputPath);
    if (!inputFile.existsSync()) {
      exitError('Input file not found: $inputPath');
    }

    final outputPath = argResults!['output'] as String? ?? '$inputPath.zgl';
    final masterKey = parseKeyFromArgs(argResults!);
    if (masterKey.length != 32) {
      exitError('Master key must be exactly 32 bytes (64 hex characters).');
    }

    final signingKeyPath = argResults!['signing-key'] as String;
    final signingKey = readKeyFile(signingKeyPath);
    if (signingKey.length != 32) {
      exitError('Signing key must be exactly 32 bytes.');
    }

    final content = Uint8List.fromList(inputFile.readAsBytesSync());
    final filename = inputFile.uri.pathSegments.last;
    final contentType = argResults!['content-type'] as String? ??
        CreativeProof.guessMimeType(filename);

    // Build creator identity.
    final creator = CreatorIdentity(
      firstName: argResults!['first-name'] as String,
      familyName: argResults!['family-name'] as String,
      middleName: argResults!['middle-name'] as String?,
      dateOfBirth: argResults!['date-of-birth'] as String?,
      address: argResults!['address'] as String?,
      zipCode: argResults!['zip-code'] as String?,
      city: argResults!['city'] as String?,
      stateProvince: argResults!['state'] as String?,
      country: argResults!['country'] as String?,
      companyName: argResults!['company'] as String?,
      companyRegistrationNumber: argResults!['company-reg'] as String?,
      email: argResults!['email'] as String?,
      phone: argResults!['phone'] as String?,
      website: argResults!['website'] as String?,
      professionalTitle: argResults!['title'] as String?,
    );

    // Parse work type.
    final workTypeStr = (argResults!['work-type'] as String).toLowerCase();
    final workType = CreativeWorkType.values.firstWhere(
      (t) => t.name == workTypeStr,
      orElse: () => CreativeProof.guessWorkType(contentType),
    );

    // Parse ID document scans.
    final idScanArgs = argResults!['id-scan'] as List<String>;
    final List<IdDocument> idDocuments = [];
    for (final scanArg in idScanArgs) {
      final colonIdx = scanArg.indexOf(':');
      if (colonIdx < 1) {
        exitError(
          'Invalid --id-scan format: "$scanArg". '
          'Expected <type>:<path>, e.g. passport:scan.jpg',
        );
      }
      final typeStr = scanArg.substring(0, colonIdx).toLowerCase();
      final scanPath = scanArg.substring(colonIdx + 1);

      final scanFile = File(scanPath);
      if (!scanFile.existsSync()) {
        exitError('ID scan file not found: $scanPath');
      }

      final docType = _parseIdDocType(typeStr);
      final scanBytes = Uint8List.fromList(scanFile.readAsBytesSync());
      final scanMime = CreativeProof.guessMimeType(scanPath);

      idDocuments.add(IdDocument(
        type: docType,
        scanBytes: scanBytes,
        scanMimeType: scanMime,
        issuingCountry: argResults!['country'] as String?,
        holderName: creator.displayName,
      ));
    }

    final tags = argResults!['tag'] as List<String>;
    final privateIdentity = argResults!['private-identity'] as bool;

    final options = CreativeProofOptions(
      workType: workType,
      workTitle: argResults!['work-title'] as String?,
      workDescription: argResults!['work-description'] as String?,
      tags: tags.isNotEmpty ? tags : null,
      compress: argResults!['compress'] as bool,
      includeIdentityInPublicMetadata: !privateIdentity,
    );

    final sealed = CreativeProof.seal(
      content: content,
      contentType: contentType,
      filename: filename,
      masterKey: masterKey,
      creatorSigningKey: signingKey,
      creator: creator,
      options: options,
      idDocuments: idDocuments.isNotEmpty ? idDocuments : null,
    );

    File(outputPath).writeAsBytesSync(sealed);

    stdout.writeln(Ansi.success('Creative proof sealed successfully.'));
    stdout.writeln();
    stdout.writeln('  Input:      $inputPath (${formatFileSize(content.length)})');
    stdout.writeln('  Output:     $outputPath (${formatFileSize(sealed.length)})');
    stdout.writeln('  Creator:    ${creator.displayName}');
    stdout.writeln('  Work type:  ${workType.name}');
    if (options.workTitle != null) {
      stdout.writeln('  Title:      ${options.workTitle}');
    }
    stdout.writeln('  MIME:       $contentType');
    if (idDocuments.isNotEmpty) {
      stdout.writeln('  ID docs:    ${idDocuments.length} attached');
    }
    stdout.writeln();
    stdout.writeln(Ansi.info(
      'The creator\'s Ed25519 signature cryptographically binds this\n'
      '  content to ${creator.displayName}\'s identity at creation time.',
    ));

    return 0;
  }

  IdDocumentType _parseIdDocType(String s) {
    switch (s) {
      case 'passport':
        return IdDocumentType.passport;
      case 'id-card':
      case 'idcard':
      case 'identity-card':
        return IdDocumentType.identityCard;
      case 'driver-license':
      case 'driverlicense':
      case 'drivers-license':
        return IdDocumentType.driverLicense;
      case 'residence-permit':
      case 'residencepermit':
        return IdDocumentType.residencePermit;
      default:
        return IdDocumentType.other;
    }
  }
}

// ---------------------------------------------------------------------------
// creative verify
// ---------------------------------------------------------------------------

class CreativeVerifyCommand extends Command<int> {
  @override
  final String name = 'verify';

  @override
  final String description =
      'Verify a creative proof container and display creator info.\n'
      '\n'
      'Performs full cryptographic verification including the Ed25519\n'
      'creator signature. Shows creator identity, work metadata, and\n'
      'whether the content has been tampered with.';

  CreativeVerifyCommand() {
    addKeyOptions(argParser);
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('No input file specified.');
    }

    final inputPath = argResults!.rest.first;
    final inputFile = File(inputPath);
    if (!inputFile.existsSync()) {
      exitError('File not found: $inputPath');
    }

    final masterKey = parseKeyFromArgs(argResults!);
    if (masterKey.length != 32) {
      exitError('Master key must be exactly 32 bytes.');
    }

    final fileBytes = Uint8List.fromList(inputFile.readAsBytesSync());
    final result = CreativeProof.verify(fileBytes, masterKey);

    if (!result.valid) {
      stdout.writeln(Ansi.error('TAMPERED — Content integrity check FAILED.'));
      return 1;
    }

    // Header.
    stdout.writeln(Ansi.success('VALID — Creative proof verified.'));
    stdout.writeln();

    // Creator info.
    stdout.writeln(Ansi.header('Creator Identity'));
    stdout.writeln('  Name:         ${result.creator?.displayName ?? 'N/A'}');
    if (result.creator?.companyName != null) {
      stdout.writeln('  Company:      ${result.creator!.companyName}');
    }
    if (result.creator?.city != null) {
      stdout.writeln('  City:         ${result.creator!.city}');
    }
    if (result.creator?.country != null) {
      stdout.writeln('  Country:      ${result.creator!.country}');
    }
    if (result.creator?.email != null) {
      stdout.writeln('  Email:        ${result.creator!.email}');
    }
    if (result.creator?.professionalTitle != null) {
      stdout.writeln('  Title:        ${result.creator!.professionalTitle}');
    }
    stdout.writeln('  Fingerprint:  ${result.creator?.fingerprint ?? 'N/A'}');
    stdout.writeln();

    // Signature.
    stdout.writeln(Ansi.header('Cryptographic Proof'));
    stdout.writeln(
      '  Signature:    ${result.signatureValid ? Ansi.success("VALID") : Ansi.error("INVALID")}',
    );
    stdout.writeln('  Public key:   ${result.creatorPublicKeyHex ?? 'N/A'}');
    stdout.writeln('  Content hash: ${result.contentHashHex ?? 'N/A'}');
    if (result.createdAt != null) {
      stdout.writeln('  Created:      ${formatTimestamp(result.createdAt!)}');
    }
    stdout.writeln();

    // Work metadata.
    stdout.writeln(Ansi.header('Work Details'));
    stdout.writeln('  Type:         ${result.workType?.name ?? 'N/A'}');
    if (result.workTitle != null) {
      stdout.writeln('  Title:        ${result.workTitle}');
    }
    if (result.workDescription != null) {
      stdout.writeln('  Description:  ${result.workDescription}');
    }
    stdout.writeln('  MIME:         ${result.contentType ?? 'N/A'}');
    stdout.writeln('  Filename:     ${result.originalFilename ?? 'N/A'}');
    if (result.content != null) {
      stdout.writeln(
        '  Content size: ${formatFileSize(result.content!.length)}',
      );
    }
    if (result.tags != null && result.tags!.isNotEmpty) {
      stdout.writeln('  Tags:         ${result.tags!.join(', ')}');
    }
    stdout.writeln();

    // ID documents.
    if (result.idDocuments != null && result.idDocuments!.isNotEmpty) {
      stdout.writeln(Ansi.header('Identity Documents'));
      for (int i = 0; i < result.idDocuments!.length; i++) {
        final doc = result.idDocuments![i];
        stdout.writeln('  [${i + 1}] ${doc.type.name}');
        stdout.writeln('      Format:   ${doc.scanMimeType}');
        stdout.writeln(
          '      Size:     ${formatFileSize(doc.scanBytes.length)}',
        );
        if (doc.issuingCountry != null) {
          stdout.writeln('      Country:  ${doc.issuingCountry}');
        }
        if (doc.holderName != null) {
          stdout.writeln('      Holder:   ${doc.holderName}');
        }
      }
      stdout.writeln();
    }

    return result.signatureValid ? 0 : 2;
  }
}

// ---------------------------------------------------------------------------
// creative inspect
// ---------------------------------------------------------------------------

class CreativeInspectCommand extends Command<int> {
  @override
  final String name = 'inspect';

  @override
  final String description =
      'Inspect a creative proof container without the master key.\n'
      '\n'
      'Shows publicly available information: creator name, work type,\n'
      'content hash, signature, and ID document summaries.\n'
      'Also verifies the Ed25519 signature against the public data.';

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('No input file specified.');
    }

    final inputPath = argResults!.rest.first;
    final inputFile = File(inputPath);
    if (!inputFile.existsSync()) {
      exitError('File not found: $inputPath');
    }

    final fileBytes = Uint8List.fromList(inputFile.readAsBytesSync());
    final insp = CreativeProof.inspect(fileBytes);

    if (!insp.isCreativeProof) {
      stdout.writeln(Ansi.warning(
        'This file is not a creative proof container.',
      ));
      stdout.writeln('It is a standard .zgl file without creative metadata.');
      return 1;
    }

    // Verify public signature.
    final sigValid = CreativeProof.verifyPublicSignature(fileBytes);

    stdout.writeln(Ansi.header('Creative Proof Inspection'));
    stdout.writeln();
    stdout.writeln('  Creator:        ${insp.creatorName ?? 'N/A'}');
    stdout.writeln('  Fingerprint:    ${insp.creatorFingerprint ?? 'N/A'}');
    stdout.writeln('  Work type:      ${insp.workType ?? 'N/A'}');
    if (insp.workTitle != null) {
      stdout.writeln('  Title:          ${insp.workTitle}');
    }
    stdout.writeln('  MIME:           ${insp.contentType ?? 'N/A'}');
    stdout.writeln('  Filename:       ${insp.originalFilename ?? 'N/A'}');
    if (insp.createdAt != null) {
      stdout.writeln('  Created:        ${formatTimestamp(insp.createdAt!)}');
    }
    if (insp.tags != null && insp.tags!.isNotEmpty) {
      stdout.writeln('  Tags:           ${insp.tags!.join(', ')}');
    }
    stdout.writeln();

    stdout.writeln(Ansi.header('Cryptographic Proof'));
    stdout.writeln(
      '  Signature:      ${sigValid ? Ansi.success("VALID") : Ansi.error("INVALID")}',
    );
    stdout.writeln('  Public key:     ${insp.creatorPublicKeyHex ?? 'N/A'}');
    stdout.writeln('  Content hash:   ${insp.contentHashHex ?? 'N/A'}');
    stdout.writeln();

    if (insp.idDocumentSummaries != null &&
        insp.idDocumentSummaries!.isNotEmpty) {
      stdout.writeln(Ansi.header('Identity Documents (summary)'));
      for (int i = 0; i < insp.idDocumentSummaries!.length; i++) {
        final doc = insp.idDocumentSummaries![i];
        stdout.writeln(
          '  [${i + 1}] ${doc['type']} (${doc['scan_mime_type']})',
        );
        stdout.writeln('      Size:   ${formatFileSize(doc['scan_size_bytes'] as int)}');
        stdout.writeln('      Hash:   ${doc['scan_hash']}');
        if (doc['issuing_country'] != null) {
          stdout.writeln('      Country: ${doc['issuing_country']}');
        }
      }
      stdout.writeln();
    }

    if (sigValid) {
      stdout.writeln(Ansi.success(
        'Creator signature is VALID. This content was sealed by '
        '${insp.creatorName ?? "the holder of the signing key"}.',
      ));
    } else {
      stdout.writeln(Ansi.error(
        'Creator signature is INVALID. The integrity of this proof is '
        'compromised.',
      ));
    }

    return sigValid ? 0 : 2;
  }
}

// ---------------------------------------------------------------------------
// creative extract
// ---------------------------------------------------------------------------

class CreativeExtractCommand extends Command<int> {
  @override
  final String name = 'extract';

  @override
  final String description =
      'Extract the original creative asset from a proof container.\n'
      '\n'
      'Verifies the container, then writes the original file bytes to\n'
      'the output path. The extracted file is bit-identical to the original.';

  CreativeExtractCommand() {
    addKeyOptions(argParser);
    addOutputOption(
      argParser,
      help: 'Output file path for the extracted asset.',
    );
    argParser.addFlag('extract-id-docs',
        help: 'Also extract ID document scans to the output directory.',
        defaultsTo: false);
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      usageException('No input file specified.');
    }

    final inputPath = argResults!.rest.first;
    final inputFile = File(inputPath);
    if (!inputFile.existsSync()) {
      exitError('File not found: $inputPath');
    }

    final masterKey = parseKeyFromArgs(argResults!);
    if (masterKey.length != 32) {
      exitError('Master key must be exactly 32 bytes.');
    }

    final fileBytes = Uint8List.fromList(inputFile.readAsBytesSync());
    final result = CreativeProof.verify(fileBytes, masterKey);

    if (!result.valid) {
      stdout.writeln(Ansi.error(
        'Verification FAILED. Content may be tampered with.',
      ));
      return 1;
    }

    if (!result.signatureValid) {
      stdout.writeln(Ansi.warning(
        'Warning: Creator signature is INVALID. Content extracted anyway.',
      ));
    }

    // Determine output path.
    final outputPath = argResults!['output'] as String? ??
        result.originalFilename ??
        'extracted_content';

    File(outputPath).writeAsBytesSync(result.content!);
    stdout.writeln(Ansi.success('Extracted: $outputPath'));
    stdout.writeln(
      '  Size: ${formatFileSize(result.content!.length)}',
    );
    stdout.writeln('  Creator: ${result.creator?.displayName ?? 'N/A'}');
    stdout.writeln(
      '  Signature: ${result.signatureValid ? "VALID" : "INVALID"}',
    );

    // Extract ID docs if requested.
    final extractIdDocs = argResults!['extract-id-docs'] as bool;
    if (extractIdDocs &&
        result.idDocuments != null &&
        result.idDocuments!.isNotEmpty) {
      final outputDir = File(outputPath).parent.path;
      for (int i = 0; i < result.idDocuments!.length; i++) {
        final doc = result.idDocuments![i];
        final ext = doc.scanMimeType.split('/').last;
        final docPath = '$outputDir/id_doc_${i + 1}_${doc.type.name}.$ext';
        File(docPath).writeAsBytesSync(doc.scanBytes);
        stdout.writeln('  ID doc ${i + 1}: $docPath');
      }
    }

    return 0;
  }
}
