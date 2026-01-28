import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

// =============================================================================
// Common test helpers
// =============================================================================

/// Creates a 32-byte test master key (0x00...01).
Uint8List _testKey() {
  final key = Uint8List(32);
  key[31] = 0x01;
  return key;
}

/// Creates a 32-byte all-zeros salt for deterministic testing.
Uint8List _zeroSalt() => Uint8List(32);

/// Derives a 32-byte signer key from a string identifier.
Uint8List _signerKey(String id) {
  return Uint8List.fromList(sha256.convert(utf8.encode(id)).bytes);
}

/// Extracts the Merkle root from a sealed file by parsing the binary structure.
///
/// ZegelInspection does not expose the Merkle root, so we parse the binary
/// directly: skip header, extended header, block directory, and read the
/// next 32 bytes.
Uint8List _getMerkleRoot(Uint8List fileBytes) {
  final bd = ByteData.sublistView(fileBytes);
  final flags = bd.getUint16(10, Endian.big);
  final filenameLen = bd.getUint16(84, Endian.big);
  final saltOffset = 86 + filenameLen;
  final blockCountOffset = saltOffset + ZegelFormat.saltSize;
  final blockCount = bd.getUint32(blockCountOffset, Endian.big);

  int cursor = blockCountOffset + 4;
  if (flags & ZegelFormat.flagPasswordDerived != 0) cursor += 8;
  if (flags & ZegelFormat.flagHasExpiration != 0) cursor += 8;
  if (flags & ZegelFormat.flagHasCanary != 0) cursor += 32;
  if (flags & ZegelFormat.flagSplitKey != 0) cursor += 2;
  if (flags & ZegelFormat.flagVersioned != 0) cursor += 32;
  if (flags & ZegelFormat.flagHasPublicMetadata != 0) {
    final pubMetaLen = bd.getUint32(cursor, Endian.big);
    cursor += 4 + pubMetaLen;
  }

  // Skip block directory.
  cursor += blockCount * ZegelFormat.blockDirectoryEntrySize;

  // Merkle root is here (32 bytes).
  return Uint8List.fromList(fileBytes.sublist(cursor, cursor + 32));
}

/// Extracts the salt from a sealed file.
Uint8List _getSalt(Uint8List fileBytes) {
  final bd = ByteData.sublistView(fileBytes);
  final filenameLen = bd.getUint16(84, Endian.big);
  final saltOffset = 86 + filenameLen;
  return Uint8List.fromList(
    fileBytes.sublist(saltOffset, saltOffset + ZegelFormat.saltSize),
  );
}

/// Extracts the master seal (last 64 bytes) from a sealed file.
Uint8List _getMasterSeal(Uint8List fileBytes) {
  return Uint8List.fromList(
    fileBytes.sublist(fileBytes.length - ZegelFormat.sealSize),
  );
}

/// Extracts leaf hashes from a sealed file's block directory.
List<Uint8List> _getLeafHashes(Uint8List fileBytes) {
  final bd = ByteData.sublistView(fileBytes);
  final flags = bd.getUint16(10, Endian.big);
  final filenameLen = bd.getUint16(84, Endian.big);
  final saltOffset = 86 + filenameLen;
  final blockCountOffset = saltOffset + ZegelFormat.saltSize;
  final blockCount = bd.getUint32(blockCountOffset, Endian.big);

  int cursor = blockCountOffset + 4;
  if (flags & ZegelFormat.flagPasswordDerived != 0) cursor += 8;
  if (flags & ZegelFormat.flagHasExpiration != 0) cursor += 8;
  if (flags & ZegelFormat.flagHasCanary != 0) cursor += 32;
  if (flags & ZegelFormat.flagSplitKey != 0) cursor += 2;
  if (flags & ZegelFormat.flagVersioned != 0) cursor += 32;
  if (flags & ZegelFormat.flagHasPublicMetadata != 0) {
    final pubMetaLen = bd.getUint32(cursor, Endian.big);
    cursor += 4 + pubMetaLen;
  }

  final hashes = <Uint8List>[];
  for (int i = 0; i < blockCount; i++) {
    final entryOffset = cursor + (i * ZegelFormat.blockDirectoryEntrySize);
    // Skip type (1 byte); hash is next 32 bytes.
    hashes.add(Uint8List.fromList(
      fileBytes.sublist(entryOffset + 1, entryOffset + 33),
    ));
  }
  return hashes;
}

/// Converts hex string to bytes.
Uint8List _hexToBytes(String hex) {
  final length = hex.length ~/ 2;
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

void main() {
  // ===========================================================================
  // Use Case: House Purchase Contract
  // ===========================================================================
  group('Use Case: House Purchase Contract', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    test('full contract workflow: seal, attest by multiple parties, verify policy', () {
      // 1. Seal the contract
      final contractText = utf8.encode(
        'PURCHASE AGREEMENT\n'
        'Property: 123 Main St\n'
        'Price: EUR 350,000\n'
        'Buyer: Alice Johnson\n'
        'Seller: Bob Smith\n'
        'Date: 2026-01-28',
      );
      final content = Uint8List.fromList(contractText);
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'purchase-agreement.txt',
        salt: _zeroSalt(),
        metadata: {
          'document_type': 'purchase_agreement',
          'property_address': '123 Main St',
          'price_eur': 350000,
        },
      );
      final fileBytes = ZegelWriter(masterKey, options).seal(content);
      final merkleRoot = _getMerkleRoot(fileBytes);

      // 2. Buyer attests with role "signer"
      final buyerKey = _signerKey('buyer-alice');
      final buyerAttestation = Attestation.createRoleAttestation(
        merkleRoot,
        'alice.johnson@email.com',
        buyerKey,
        'I agree to purchase the property at the stated price',
        ZegelFormat.roleSigner,
        timestamp: DateTime.utc(2026, 1, 28, 10, 0, 0),
      );
      expect(buyerAttestation['role'], equals(ZegelFormat.roleSigner));

      // 3. Seller attests with role "owner"
      final sellerKey = _signerKey('seller-bob');
      final sellerAttestation = Attestation.createRoleAttestation(
        merkleRoot,
        'bob.smith@email.com',
        sellerKey,
        'I agree to sell the property at the stated price',
        ZegelFormat.roleOwner,
        timestamp: DateTime.utc(2026, 1, 28, 10, 30, 0),
      );
      expect(sellerAttestation['role'], equals(ZegelFormat.roleOwner));

      // 4. Notary attests with role "notary"
      final notaryKey = _signerKey('notary-office');
      final notaryAttestation = Attestation.createRoleAttestation(
        merkleRoot,
        'notary@dutch-notary.nl',
        notaryKey,
        'I have verified the identities of both parties and notarize this agreement',
        ZegelFormat.roleNotary,
        timestamp: DateTime.utc(2026, 1, 28, 11, 0, 0),
      );
      expect(notaryAttestation['role'], equals(ZegelFormat.roleNotary));

      // 5. Check attestation policy requires all three roles
      final attestations = [
        buyerAttestation,
        sellerAttestation,
        notaryAttestation,
      ];
      final signerKeys = {
        'alice.johnson@email.com': buyerKey,
        'bob.smith@email.com': sellerKey,
        'notary@dutch-notary.nl': notaryKey,
      };

      final policyResult = Attestation.checkPolicy(
        attestations,
        [ZegelFormat.roleSigner, ZegelFormat.roleOwner, ZegelFormat.roleNotary],
        merkleRoot,
        signerKeys,
      );
      expect(policyResult.allRolesFulfilled, isTrue,
          reason: 'All three parties have attested');

      // 6. Verify all attestations individually
      expect(
        Attestation.verifyRoleAttestation(
            buyerAttestation, merkleRoot, buyerKey),
        isTrue,
      );
      expect(
        Attestation.verifyRoleAttestation(
            sellerAttestation, merkleRoot, sellerKey),
        isTrue,
      );
      expect(
        Attestation.verifyRoleAttestation(
            notaryAttestation, merkleRoot, notaryKey),
        isTrue,
      );
    });

    test('selective disclosure: bank sees only financial terms', () {
      // Create a multi-block contract where blocks contain different sections.
      // Block 0: metadata, Block 1-3: content blocks (3 chunks)
      final content = Uint8List(65536 * 2 + 100);
      for (var i = 0; i < content.length; i++) {
        content[i] = i & 0xFF;
      }
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'contract-full.txt',
        salt: _zeroSalt(),
        metadata: {
          'document_type': 'purchase_agreement',
          'sections': ['financial', 'personal', 'legal'],
        },
      );
      final fileBytes = ZegelWriter(masterKey, options).seal(content);
      final merkleRoot = _getMerkleRoot(fileBytes);
      final salt = _getSalt(fileBytes);

      // Generate disclosure token for metadata (block 0) and first content block (block 1)
      final token = SelectiveDisclosure.generateToken(
        masterKey,
        merkleRoot,
        salt,
        [0, 1],
      );

      // Bank extracts with token -- should see metadata and first content block
      final result = const ZegelReader().extractWithToken(fileBytes, token);
      expect(result.valid, isTrue);
      // Metadata was disclosed (block 0)
      expect(result.metadata, isNotNull);
      // First content block was disclosed (block 1), but not all content
      expect(result.content, isNotNull);
      expect(result.content!.length, equals(65536));
    });

    test('redact personal data for public records', () {
      // Seal a contract with personal data blocks
      final content = Uint8List(65536 * 2 + 100);
      for (var i = 0; i < content.length; i++) {
        content[i] = i & 0xFF;
      }
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'contract-personal.txt',
        salt: _zeroSalt(),
      );
      final fileBytes = ZegelWriter(masterKey, options).seal(content);

      // Verify original is valid
      final originalResult = const ZegelReader().verify(fileBytes, masterKey);
      expect(originalResult.valid, isTrue);

      // Redact block 2 (personal data)
      final redacted = Redaction.redactBlocks(fileBytes, masterKey, [2]);

      // Verify redacted file is still valid
      final redactedResult = const ZegelReader().verify(redacted, masterKey);
      expect(redactedResult.valid, isTrue);

      // Block 2 should be marked as redacted
      expect(redactedResult.redactedBlocks, contains(2));

      // Non-redacted blocks should still be extractable
      expect(redactedResult.content, isNotNull);
      expect(redactedResult.content!.length, greaterThan(0));
    });
  });

  // ===========================================================================
  // Use Case: Financial Audit
  // ===========================================================================
  group('Use Case: Financial Audit', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    test('batch verify quarterly statements', () {
      // Seal 4 quarterly statements
      final quarters = ['Q1', 'Q2', 'Q3', 'Q4'];
      final sealedStatements = <MapEntry<String, Uint8List>>[];

      for (final quarter in quarters) {
        final content = Uint8List.fromList(
          utf8.encode('Financial statement for $quarter 2025\n'
              'Revenue: EUR 1,200,000\n'
              'Expenses: EUR 900,000\n'),
        );
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'statement_${quarter}_2025.txt',
          salt: _zeroSalt(),
          metadata: {
            'quarter': quarter,
            'year': 2025,
            'type': 'financial_statement',
          },
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);

        sealedStatements.add(MapEntry(
          'statement_${quarter}_2025',
          fileBytes,
        ));
      }

      // Batch verify all
      final results = BatchOperations.batchVerify(
        sealedStatements,
        masterKey,
      );

      expect(results.length, equals(4));
      for (var i = 0; i < results.length; i++) {
        expect(results[i]['success'], isTrue,
            reason: '${quarters[i]} statement should verify');
        expect(results[i]['name'] as String, contains(quarters[i]));
      }
    });

    test('manifest for audit package', () {
      // Seal the statements and collect Merkle roots
      final merkleRoots = <String, Uint8List>{};
      final sealedFiles = <String, Uint8List>{};

      for (final quarter in ['Q1', 'Q2', 'Q3', 'Q4']) {
        final content = Uint8List.fromList(
          utf8.encode('Statement $quarter'),
        );
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'stmt_$quarter.txt',
          salt: _zeroSalt(),
        );
        final fileBytes = ZegelWriter(masterKey, options).seal(content);
        final merkleRoot = _getMerkleRoot(fileBytes);

        merkleRoots['stmt_$quarter.txt'] = merkleRoot;
        sealedFiles['stmt_$quarter.txt'] = fileBytes;
      }

      // Create manifest
      final auditorKey = _signerKey('auditor');
      final manifest = ZegelManifest.create(
        merkleRoots,
        auditorKey,
        'auditor@accounting-firm.com',
      );

      // Verify manifest signature
      expect(
        ZegelManifest.verify(manifest, auditorKey),
        isTrue,
        reason: 'Manifest signature should be valid',
      );

      // Check that all files match the manifest
      final checkResult = ZegelManifest.checkFiles(manifest, merkleRoots);
      for (final filename in merkleRoots.keys) {
        expect(checkResult[filename], isTrue,
            reason: '$filename should match the manifest');
      }
    });
  });

  // ===========================================================================
  // Use Case: Academic Credentials
  // ===========================================================================
  group('Use Case: Academic Credentials', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    test('issue and verify diploma', () {
      // Seal the diploma document
      final diplomaContent = utf8.encode(
        'DIPLOMA\n'
        'Name: Jane Doe\n'
        'Degree: Master of Computer Science\n'
        'University: Technical University\n'
        'Date: 2026-06-15\n'
        'GPA: 3.9/4.0',
      );
      final content = Uint8List.fromList(diplomaContent);
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'diploma_jane_doe_2026.txt',
        salt: _zeroSalt(),
        metadata: {
          'student_id': '2020-CS-1234',
          'degree': 'MSc Computer Science',
          'honors': 'magna cum laude',
        },
        publicMetadata: {
          'issuer': 'Technical University',
          'document_type': 'diploma',
          'issued_date': '2026-06-15',
        },
      );
      final fileBytes = ZegelWriter(masterKey, options).seal(content);

      // University attests with role "owner" (the issuing institution)
      final merkleRoot = _getMerkleRoot(fileBytes);
      final universityKey = _signerKey('technical-university');
      final attestation = Attestation.createRoleAttestation(
        merkleRoot,
        'registrar@tu.edu',
        universityKey,
        'This diploma is issued by the Office of the Registrar',
        ZegelFormat.roleOwner,
        timestamp: DateTime.utc(2026, 6, 15, 14, 0, 0),
      );

      expect(attestation['role'], equals(ZegelFormat.roleOwner));

      // Employer verifies the attestation
      final isValid = Attestation.verifyRoleAttestation(
        attestation,
        merkleRoot,
        universityKey,
      );
      expect(isValid, isTrue,
          reason: 'Employer should be able to verify the university attestation');

      // Employer can also inspect public metadata without the master key
      final inspection = const ZegelReader().inspect(fileBytes);
      expect(inspection.publicMetadata!['issuer'],
          equals('Technical University'));
      expect(inspection.publicMetadata!['document_type'], equals('diploma'));
    });
  });

  // ===========================================================================
  // Use Case: Government Classified Documents
  // ===========================================================================
  group('Use Case: Government Classified', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    test('classify, distribute, declassify', () {
      // 1. Seal with TOP_SECRET classification
      final content = Uint8List(65536 * 2 + 500);
      for (var i = 0; i < content.length; i++) {
        content[i] = i & 0xFF;
      }
      final classificationMeta = Classification.createClassificationMetadata(
        level: ZegelFormat.classificationTopSecret,
        authority: 'National Security Office',
        caveat: 'NOFORN',
      );
      final options = ZegelOptions(
        contentType: 'application/octet-stream',
        filename: 'intel-report.bin',
        salt: _zeroSalt(),
        publicMetadata: classificationMeta,
      );
      final fileBytes = ZegelWriter(masterKey, options).seal(content);

      // 2. Verify classification level via public metadata
      final inspection = const ZegelReader().inspect(fileBytes);
      final classInfo =
          inspection.publicMetadata!['classification'] as Map<String, dynamic>;
      expect(classInfo['level'],
          equals(ZegelFormat.classificationTopSecret));
      expect(classInfo['caveat'], equals('NOFORN'));

      // 3. Declassify to CONFIDENTIAL with redaction of block 0
      final declassified = Classification.declassify(
        fileBytes,
        masterKey,
        ZegelFormat.classificationConfidential,
        'Declassification Review Board',
        redactBlocks: [0],
      );

      // 4. Verify new classification level
      final declInspection = const ZegelReader().inspect(declassified);
      final declClassInfo =
          declInspection.publicMetadata!['classification'] as Map<String, dynamic>;
      expect(declClassInfo['level'],
          equals(ZegelFormat.classificationConfidential));

      // 5. Verify declassified file is still valid
      final result = const ZegelReader().verify(declassified, masterKey);
      expect(result.valid, isTrue);

      // 6. Content should be present (re-sealed from non-redacted blocks)
      expect(result.content, isNotNull);
      expect(result.content!.length, lessThan(content.length));
    });
  });

  // ===========================================================================
  // Use Case: Journalism Excerpt Proof
  // ===========================================================================
  group('Use Case: Journalism Excerpt', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    test('prove quote exists in sealed source', () {
      // A journalist seals a source document
      final sourceText =
          'The internal memo reveals that the budget was '
          'overspent by EUR 2.5 million in the third quarter. '
          'Management attempted to conceal this by deferring '
          'expenses to the next fiscal year. '
          '${'X' * 50000}'; // padding to ensure multiple blocks
      final content = Uint8List.fromList(utf8.encode(sourceText));
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'source-memo.txt',
        salt: _zeroSalt(),
      );
      final fileBytes = ZegelWriter(masterKey, options).seal(content);

      // Extract leaf hashes and Merkle root from the sealed file
      final leafHashes = _getLeafHashes(fileBytes);
      final merkleRoot = _getMerkleRoot(fileBytes);

      // Generate an excerpt proof for one block (block 0)
      final proof = ExcerptProof.generateProof(leafHashes, 0);

      expect(proof, isNotNull);
      expect(proof['block_hash'], isNotNull);
      expect(proof['merkle_root'], isNotNull);
      expect(proof['proof'], isA<List<dynamic>>());

      // The proof can be verified WITHOUT the master key
      // The verifier only needs the Merkle root (from public header)
      // and the proof data
      final isValid = ExcerptProof.verifyProof(proof, merkleRoot);
      expect(isValid, isTrue,
          reason:
              'Third party should be able to verify the excerpt without the key');

      // Verify the Merkle root in the proof matches the file
      expect(proof['merkle_root'],
          equals(merkleRoot.map((b) => b.toRadixString(16).padLeft(2, '0')).join()));
    });
  });

  // ===========================================================================
  // Use Case: Insurance Claim
  // ===========================================================================
  group('Use Case: Insurance Claim', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    test('seal damage photos with GPS metadata', () {
      // Create GPS metadata for the damage location as a regular map
      final gpsMetadata = <String, dynamic>{
        'gps': {
          'latitude': 52.3676,
          'longitude': 4.9041,
          'altitude': 2.5,
          'timestamp': DateTime.utc(2026, 1, 20, 14, 30, 0).toIso8601String(),
        },
      };

      // Simulate a JPEG photo (magic bytes + random data)
      final photoContent = Uint8List(1024);
      photoContent[0] = 0xFF;
      photoContent[1] = 0xD8;
      photoContent[2] = 0xFF;
      for (var i = 3; i < 1024; i++) {
        photoContent[i] = i & 0xFF;
      }

      // Seal the photo with GPS metadata
      final options = ZegelOptions(
        contentType: 'image/jpeg',
        filename: 'damage_photo_001.jpg',
        salt: _zeroSalt(),
        metadata: {
          ...gpsMetadata,
          'claim_id': 'INS-2026-12345',
          'damage_type': 'water_damage',
          'photographer': 'claims_adjuster@insurance.com',
        },
      );
      final fileBytes =
          ZegelWriter(masterKey, options).seal(photoContent);

      // Extract and verify GPS is preserved
      final result = const ZegelReader().verify(fileBytes, masterKey);
      expect(result.valid, isTrue);
      expect(result.metadata, isNotNull);
      expect(result.metadata!.containsKey('gps'), isTrue);

      final gps = result.metadata!['gps'] as Map<String, dynamic>;
      expect(gps['latitude'], closeTo(52.3676, 0.0001));
      expect(gps['longitude'], closeTo(4.9041, 0.0001));
      expect(gps['altitude'], closeTo(2.5, 0.01));

      // Verify claim metadata
      expect(result.metadata!['claim_id'], equals('INS-2026-12345'));
      expect(result.metadata!['damage_type'], equals('water_damage'));

      // Verify content type
      final inspection = const ZegelReader().inspect(fileBytes);
      expect(inspection.contentType, equals('image/jpeg'));
      expect(inspection.filename, equals('damage_photo_001.jpg'));
    });

    test('batch verify claim documents with provenance', () {
      // Seal multiple claim documents
      final documents = ['damage_report.txt', 'estimate.txt', 'policy.txt'];
      final sealedDocs = <MapEntry<String, Uint8List>>[];

      for (final docName in documents) {
        final content = Uint8List.fromList(
          utf8.encode('Content of $docName for claim INS-2026-12345'),
        );
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: docName,
          salt: _zeroSalt(),
        );
        final fileBytes =
            ZegelWriter(masterKey, options).seal(content);

        sealedDocs.add(MapEntry(docName, fileBytes));
      }

      // Batch verify all claim documents
      final results = BatchOperations.batchVerify(sealedDocs, masterKey);

      expect(results.length, equals(3));
      for (final result in results) {
        expect(result['success'], isTrue);
      }
    });
  });

  // ===========================================================================
  // Use Case: Whistleblower Protection
  // ===========================================================================
  group('Use Case: Whistleblower', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    test('seal with split key for secure submission', () {
      final content = Uint8List.fromList(
        utf8.encode('Confidential whistleblower report: '
            'Evidence of fraudulent accounting practices...'),
      );
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'whistleblower-report.txt',
        salt: _zeroSalt(),
        splitKeyThreshold: 3,
        splitKeyTotal: 5,
      );
      final fileBytes = ZegelWriter(masterKey, options).seal(content);

      // Verify the file is valid
      final result = const ZegelReader().verify(fileBytes, masterKey);
      expect(result.valid, isTrue);

      // Inspect shows split key params
      final inspection = const ZegelReader().inspect(fileBytes);
      expect(inspection.flags & ZegelFormat.flagSplitKey, isNonZero);

      // Split the master key
      final shares = ShamirSecretSharing.split(masterKey, 3, 5);
      expect(shares.length, equals(5));

      // Reconstruct with any 3 of 5 shares
      final reconstructed = ShamirSecretSharing.reconstruct(
        [shares[0], shares[2], shares[4]],
        3,
      );

      // Verify with reconstructed key
      final verifyResult =
          const ZegelReader().verify(fileBytes, reconstructed);
      expect(verifyResult.valid, isTrue,
          reason: 'Reconstructed key should verify the file');
    });
  });

  // ===========================================================================
  // Use Case: Supply Chain
  // ===========================================================================
  group('Use Case: Supply Chain', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    test('track provenance through supply chain', () {
      // Create a sealed file to get a Merkle root for provenance binding
      final productData = Uint8List.fromList(
        utf8.encode('Product LOT-2026-001 certification data'),
      );
      final sealedProduct = ZegelWriter(masterKey, ZegelOptions(
        contentType: 'application/octet-stream',
        filename: 'product_lot_2026_001.bin',
        salt: _zeroSalt(),
      )).seal(productData);
      final merkleRoot = _getMerkleRoot(sealedProduct);

      final signingKey = _signerKey('supply-chain');

      // Create a provenance chain
      final entries = <Map<String, dynamic>>[];

      // Step 1: Manufacturer creates
      final entry1 = ProvenanceVerification.createEvent(
        'manufactured',
        'manufacturer@factory.com',
        signingKey,
        merkleRoot,
        details: {'batch': 'LOT-2026-001', 'location': 'Factory A'},
        timestamp: DateTime.utc(2026, 1, 10, 8, 0, 0),
      );
      entries.add(entry1);

      // Step 2: QA inspection
      final entry2 = ProvenanceVerification.createEvent(
        'inspected',
        'qa@factory.com',
        signingKey,
        merkleRoot,
        previousEventHash: entry1['event_hash'] as String,
        details: {'result': 'passed', 'defects': 0},
        timestamp: DateTime.utc(2026, 1, 11, 10, 0, 0),
      );
      entries.add(entry2);

      // Step 3: Shipped
      final entry3 = ProvenanceVerification.createEvent(
        'shipped',
        'logistics@shipping.com',
        signingKey,
        merkleRoot,
        previousEventHash: entry2['event_hash'] as String,
        details: {'tracking': 'TRK-123456', 'carrier': 'DHL'},
        timestamp: DateTime.utc(2026, 1, 15, 6, 0, 0),
      );
      entries.add(entry3);

      // Step 4: Received by retailer
      final entry4 = ProvenanceVerification.createEvent(
        'received',
        'receiving@retailer.com',
        signingKey,
        merkleRoot,
        previousEventHash: entry3['event_hash'] as String,
        details: {'condition': 'good', 'quantity': 100},
        timestamp: DateTime.utc(2026, 1, 20, 14, 0, 0),
      );
      entries.add(entry4);

      // Verify the entire chain
      final chainResult = ProvenanceVerification.verifyChain(
        entries,
        signingKey,
      );
      expect(chainResult['valid'], isTrue,
          reason: 'Supply chain provenance should verify');

      // Verify chronological ordering manually
      for (int i = 1; i < entries.length; i++) {
        expect(
          (entries[i]['timestamp'] as int) >=
              (entries[i - 1]['timestamp'] as int),
          isTrue,
          reason: 'Supply chain should be chronologically ordered',
        );
      }
    });
  });

  // ===========================================================================
  // Use Case: Software Distribution
  // ===========================================================================
  group('Use Case: Software Distribution', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    test('seal binary with version chain for updates', () {
      // Version 1.0
      final v1Content = Uint8List.fromList(
        utf8.encode('Software binary v1.0 payload'),
      );
      final v1Options = ZegelOptions(
        contentType: 'application/octet-stream',
        filename: 'software_v1.0.bin',
        salt: _zeroSalt(),
        publicMetadata: {
          'software': 'MyApp',
          'version': '1.0.0',
          'release_date': '2026-01-01',
        },
      );
      final v1Bytes = ZegelWriter(masterKey, v1Options).seal(v1Content);

      // Verify v1
      final v1Result = const ZegelReader().verify(v1Bytes, masterKey);
      expect(v1Result.valid, isTrue);

      // Create chain hash for v2
      final v1Root = _getMerkleRoot(v1Bytes);
      final v1Seal = _getMasterSeal(v1Bytes);
      final chainHash = ContentVersioning.computeChainHash(v1Root, v1Seal);

      // Version 2.0 linked to v1
      final v2Content = Uint8List.fromList(
        utf8.encode('Software binary v2.0 payload with new features'),
      );
      final v2Options = ZegelOptions(
        contentType: 'application/octet-stream',
        filename: 'software_v2.0.bin',
        salt: _zeroSalt(),
        versionChainHash: chainHash,
        publicMetadata: {
          'software': 'MyApp',
          'version': '2.0.0',
          'release_date': '2026-02-01',
        },
      );
      final v2Bytes = ZegelWriter(masterKey, v2Options).seal(v2Content);

      // Verify v2
      final v2Result = const ZegelReader().verify(v2Bytes, masterKey);
      expect(v2Result.valid, isTrue);

      // Verify the version chain
      final chainValid =
          ContentVersioning.verifyVersionChain([v1Bytes, v2Bytes]);
      expect(chainValid, isTrue,
          reason: 'Software version chain should verify');

      // Inspect v2 for version info
      final v2Inspection = const ZegelReader().inspect(v2Bytes);
      expect(v2Inspection.flags & ZegelFormat.flagVersioned, isNonZero);
      expect(v2Inspection.publicMetadata!['version'], equals('2.0.0'));
    });
  });

  // ===========================================================================
  // Use Case: Contract Negotiation
  // ===========================================================================
  group('Use Case: Contract Negotiation', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    test('multiple versions with attestations at each stage', () {
      // Draft 1
      final draft1 = Uint8List.fromList(
        utf8.encode('Contract Draft 1: Initial terms...'),
      );
      final draft1Options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'contract_draft1.txt',
        salt: _zeroSalt(),
      );
      final draft1Bytes =
          ZegelWriter(masterKey, draft1Options).seal(draft1);

      // Lawyer attests draft 1
      final lawyerKey = _signerKey('lawyer');
      final draft1Root = _getMerkleRoot(draft1Bytes);
      final draft1Attestation = Attestation.createRoleAttestation(
        draft1Root,
        'lawyer@lawfirm.com',
        lawyerKey,
        'Reviewed draft 1, recommend changes to clause 3',
        ZegelFormat.roleReviewer,
        timestamp: DateTime.utc(2026, 1, 10),
      );
      expect(
        Attestation.verifyRoleAttestation(
            draft1Attestation, draft1Root, lawyerKey),
        isTrue,
      );

      // Create draft 2 linked to draft 1
      final draft1Seal = _getMasterSeal(draft1Bytes);
      final chainHash = ContentVersioning.computeChainHash(
        draft1Root,
        draft1Seal,
      );

      final draft2 = Uint8List.fromList(
        utf8.encode('Contract Draft 2: Revised clause 3...'),
      );
      final draft2Options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'contract_draft2.txt',
        salt: _zeroSalt(),
        versionChainHash: chainHash,
      );
      final draft2Bytes =
          ZegelWriter(masterKey, draft2Options).seal(draft2);

      // Both parties attest draft 2
      final draft2Root = _getMerkleRoot(draft2Bytes);
      final partyAKey = _signerKey('party-a');
      final partyBKey = _signerKey('party-b');

      final partyAAttestation = Attestation.createRoleAttestation(
        draft2Root,
        'ceo@company-a.com',
        partyAKey,
        'Agreed to final terms',
        ZegelFormat.roleSigner,
        timestamp: DateTime.utc(2026, 1, 20),
      );
      final partyBAttestation = Attestation.createRoleAttestation(
        draft2Root,
        'ceo@company-b.com',
        partyBKey,
        'Agreed to final terms',
        ZegelFormat.roleSigner,
        timestamp: DateTime.utc(2026, 1, 21),
      );

      expect(
        Attestation.verifyRoleAttestation(
            partyAAttestation, draft2Root, partyAKey),
        isTrue,
      );
      expect(
        Attestation.verifyRoleAttestation(
            partyBAttestation, draft2Root, partyBKey),
        isTrue,
      );

      // Verify version chain
      final chainValid = ContentVersioning.verifyVersionChain(
        [draft1Bytes, draft2Bytes],
      );
      expect(chainValid, isTrue);
    });
  });

  // ===========================================================================
  // Use Case: Digital Art Provenance
  // ===========================================================================
  group('Use Case: Digital Art Provenance', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    test('seal artwork with creator attestation and provenance', () {
      // Seal the digital artwork
      final artContent = Uint8List(2048);
      for (var i = 0; i < artContent.length; i++) {
        artContent[i] = i & 0xFF;
      }
      final options = ZegelOptions(
        contentType: 'image/png',
        filename: 'digital_art_001.png',
        salt: _zeroSalt(),
        metadata: {
          'title': 'Sunset Over Amsterdam',
          'artist': 'Jane Artist',
          'created': '2026-01-15',
          'medium': 'digital',
          'dimensions': '4096x2160',
        },
        publicMetadata: {
          'title': 'Sunset Over Amsterdam',
          'artist': 'Jane Artist',
          'edition': '1/1',
        },
      );
      final fileBytes =
          ZegelWriter(masterKey, options).seal(artContent);

      // Creator attests
      final merkleRoot = _getMerkleRoot(fileBytes);
      final artistKey = _signerKey('jane-artist');
      final attestation = Attestation.createRoleAttestation(
        merkleRoot,
        'jane@artist-studio.com',
        artistKey,
        'I am the original creator of this artwork',
        ZegelFormat.roleOwner,
        timestamp: DateTime.utc(2026, 1, 15, 10, 0, 0),
      );

      expect(attestation['role'], equals(ZegelFormat.roleOwner));
      expect(
        Attestation.verifyRoleAttestation(
            attestation, merkleRoot, artistKey),
        isTrue,
      );

      // Public metadata should be visible without the key
      final inspection = const ZegelReader().inspect(fileBytes);
      expect(inspection.publicMetadata!['artist'], equals('Jane Artist'));
      expect(inspection.publicMetadata!['edition'], equals('1/1'));
    });
  });

  // ===========================================================================
  // Use Case: Medical Records
  // ===========================================================================
  group('Use Case: Medical Records', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    test('seal patient record with selective disclosure for specialist', () {
      // Create a multi-block patient record
      final record = Uint8List(65536 * 2 + 500);
      for (var i = 0; i < record.length; i++) {
        record[i] = i & 0xFF;
      }
      final options = ZegelOptions(
        contentType: 'application/json',
        filename: 'patient_record_12345.json',
        salt: _zeroSalt(),
        metadata: {
          'patient_id': 'PAT-12345',
          'record_type': 'medical_history',
          'sections': ['demographics', 'cardiology', 'allergies'],
        },
      );
      final fileBytes = ZegelWriter(masterKey, options).seal(record);
      final merkleRoot = _getMerkleRoot(fileBytes);
      final salt = _getSalt(fileBytes);

      // Verify the record
      final result = const ZegelReader().verify(fileBytes, masterKey);
      expect(result.valid, isTrue);

      // Generate disclosure token for cardiologist (block 0: metadata, block 1: first content)
      final cardioToken = SelectiveDisclosure.generateToken(
        masterKey,
        merkleRoot,
        salt,
        [0, 1], // metadata + first content block (cardiology data)
      );

      final cardioResult =
          const ZegelReader().extractWithToken(fileBytes, cardioToken);
      expect(cardioResult.valid, isTrue);
      // Metadata was disclosed
      expect(cardioResult.metadata, isNotNull);
      // First content block was disclosed
      expect(cardioResult.content, isNotNull);
      expect(cardioResult.content!.length, equals(65536));
    });
  });

  // ===========================================================================
  // Use Case: Voting / Election
  // ===========================================================================
  group('Use Case: Voting', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    test('seal ballot with audit trail', () {
      final ballot = Uint8List.fromList(
        utf8.encode('BALLOT: Candidate A [X] Candidate B [ ]'),
      );
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'ballot_encrypted.txt',
        salt: _zeroSalt(),
        metadata: {
          'election': 'Municipal 2026',
          'district': 'District 5',
          'booth': 'A-12',
        },
      );
      final fileBytes = ZegelWriter(masterKey, options).seal(ballot);

      // Create audit trail
      final auditEntries = <Map<String, dynamic>>[];
      Uint8List? prevHash;

      final entry1 = AuditTrail.createEntry(
        'voter-terminal@election.gov',
        'sealed',
        details: {'booth': 'A-12'},
        previousChainHash: prevHash,
      );
      auditEntries.add(entry1);
      prevHash = _hexToBytes(entry1['chain_hash'] as String);

      final entry2 = AuditTrail.createEntry(
        'tally-system@election.gov',
        'verified',
        details: {'verification': 'automatic'},
        previousChainHash: prevHash,
      );
      auditEntries.add(entry2);

      // Verify audit chain
      final auditValid = AuditTrail.verifyChain(auditEntries);
      expect(auditValid, isTrue);

      // Verify the ballot file
      final result = const ZegelReader().verify(fileBytes, masterKey);
      expect(result.valid, isTrue);
    });
  });

  // ===========================================================================
  // Use Case: Legal Discovery
  // ===========================================================================
  group('Use Case: Legal Discovery', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    test('seal evidence, redact privileged content, verify chain', () {
      // Seal evidence document
      final evidence = Uint8List(65536 * 3 + 200);
      for (var i = 0; i < evidence.length; i++) {
        evidence[i] = i & 0xFF;
      }
      final options = ZegelOptions(
        contentType: 'application/pdf',
        filename: 'evidence_exhibit_A.pdf',
        salt: _zeroSalt(),
        metadata: {
          'case_number': 'CV-2026-9876',
          'exhibit': 'A',
          'privilege_log':
              'Blocks 1-2 contain attorney-client privileged material',
        },
      );
      final fileBytes =
          ZegelWriter(masterKey, options).seal(evidence);

      // Verify original
      final originalResult =
          const ZegelReader().verify(fileBytes, masterKey);
      expect(originalResult.valid, isTrue);

      // Redact privileged blocks (1 and 2)
      final redacted =
          Redaction.redactBlocks(fileBytes, masterKey, [1, 2]);

      // Redacted file still verifies
      final redactedResult =
          const ZegelReader().verify(redacted, masterKey);
      expect(redactedResult.valid, isTrue);

      // Privileged blocks are marked as redacted
      expect(redactedResult.redactedBlocks, containsAll([1, 2]));

      // Non-privileged content (blocks 0, 3) still available
      expect(redactedResult.content, isNotNull);
      expect(redactedResult.content!.length, greaterThan(0));
    });
  });

  // ===========================================================================
  // Use Case: IP / Patents
  // ===========================================================================
  group('Use Case: IP / Patents', () {
    late Uint8List masterKey;

    setUp(() {
      masterKey = _testKey();
    });

    test('timestamp invention disclosure for prior art', () {
      final disclosure = Uint8List.fromList(
        utf8.encode(
          'INVENTION DISCLOSURE\n'
          'Title: Novel Quantum Computing Algorithm\n'
          'Inventor: Dr. Smith\n'
          'Date: 2026-01-28\n'
          'Description: A new approach to quantum error correction...',
        ),
      );
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'invention_disclosure_2026_001.txt',
        salt: _zeroSalt(),
        metadata: {
          'inventor': 'Dr. Smith',
          'department': 'R&D',
          'disclosure_number': 'ID-2026-001',
        },
      );
      final fileBytes =
          ZegelWriter(masterKey, options).seal(disclosure);

      // Create a local trusted timestamp for the sealed file
      final merkleRoot = _getMerkleRoot(fileBytes);
      final masterSeal = _getMasterSeal(fileBytes);
      final tsaKey = _signerKey('tsa-authority');

      final tsToken = TrustedTimestamp.createLocalToken(
        merkleRoot,
        masterSeal,
        tsaKey,
      );

      expect(tsToken['merkle_root'], isNotNull);
      expect(tsToken['type'], equals('local'));
      expect(tsToken['timestamp'], isA<int>());

      // Verify the local timestamp
      final tsValid = TrustedTimestamp.verifyLocalToken(
        tsToken,
        merkleRoot,
        masterSeal,
        tsaKey,
      );
      expect(tsValid, isTrue,
          reason: 'Trusted timestamp should verify');

      // Verify the file itself
      final result = const ZegelReader().verify(fileBytes, masterKey);
      expect(result.valid, isTrue);
    });
  });
}
