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

/// Creates a 32-byte recipient identifier from a string.
Uint8List _recipientId(String name) {
  return Uint8List.fromList(sha256.convert(utf8.encode(name)).bytes);
}

/// Extracts the Merkle root from a sealed file.
Uint8List _getMerkleRoot(Uint8List fileBytes) {
  final inspection = ZegelReader.inspect(fileBytes);
  return inspection.merkleRoot!;
}

/// Extracts the master seal (last 64 bytes) from a sealed file.
Uint8List _getMasterSeal(Uint8List fileBytes) {
  return Uint8List.fromList(fileBytes.sublist(fileBytes.length - 64));
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
      final fileBytes =
          ZegelWriter.seal(content, masterKey, options: options);
      final merkleRoot = _getMerkleRoot(fileBytes);

      // 2. Buyer attests with role "buyer"
      final buyerKey = _signerKey('buyer-alice');
      final buyerAttestation = Attestation.createAttestation(
        merkleRoot,
        'alice.johnson@email.com',
        buyerKey,
        'I agree to purchase the property at the stated price',
        role: 'buyer',
        timestamp: DateTime.utc(2026, 1, 28, 10, 0, 0),
      );
      expect(buyerAttestation['role'], equals('buyer'));

      // 3. Seller attests with role "seller"
      final sellerKey = _signerKey('seller-bob');
      final sellerAttestation = Attestation.createAttestation(
        merkleRoot,
        'bob.smith@email.com',
        sellerKey,
        'I agree to sell the property at the stated price',
        role: 'seller',
        timestamp: DateTime.utc(2026, 1, 28, 10, 30, 0),
      );
      expect(sellerAttestation['role'], equals('seller'));

      // 4. Notary attests with role "notary"
      final notaryKey = _signerKey('notary-office');
      final notaryAttestation = Attestation.createAttestation(
        merkleRoot,
        'notary@dutch-notary.nl',
        notaryKey,
        'I have verified the identities of both parties and notarize this agreement',
        role: ZegelFormat.roleNotary,
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
        attestations: attestations,
        merkleRoot: merkleRoot,
        requiredRoles: ['buyer', 'seller', ZegelFormat.roleNotary],
        signerKeys: signerKeys,
      );
      expect(policyResult.satisfied, isTrue,
          reason: 'All three parties have attested');

      // 6. Verify all attestations individually
      expect(
        Attestation.verifyAttestation(buyerAttestation, merkleRoot, buyerKey),
        isTrue,
      );
      expect(
        Attestation.verifyAttestation(sellerAttestation, merkleRoot, sellerKey),
        isTrue,
      );
      expect(
        Attestation.verifyAttestation(notaryAttestation, merkleRoot, notaryKey),
        isTrue,
      );
    });

    test('selective disclosure: bank sees only financial terms', () {
      // Create a multi-block contract where blocks contain different sections.
      // Block 0: metadata, Block 1: financial terms, Block 2: personal data
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
      final fileBytes =
          ZegelWriter.seal(content, masterKey, options: options);

      // Generate disclosure token for metadata (block 0) and financial block (block 1)
      final token = ZegelDisclosure.generateToken(
        fileBytes,
        masterKey,
        [0, 1],
      );

      // Bank extracts with token -- should only see blocks 0 and 1
      final result = ZegelDisclosure.extractWithToken(fileBytes, token);
      expect(result.valid, isTrue);
      expect(result.disclosedBlocks, contains(0));
      expect(result.disclosedBlocks, contains(1));
      // Block 2+ should not be accessible
      expect(result.disclosedBlocks, isNot(contains(2)));
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
      final fileBytes =
          ZegelWriter.seal(content, masterKey, options: options);

      // Verify original is valid
      final originalResult = ZegelReader.verify(fileBytes, masterKey);
      expect(originalResult.valid, isTrue);

      // Redact block 2 (personal data)
      final redacted = ZegelRedaction.redact(fileBytes, masterKey, [2]);

      // Verify redacted file is still valid
      final redactedResult = ZegelReader.verify(redacted, masterKey);
      expect(redactedResult.valid, isTrue);

      // Block 2 should be marked as redacted
      final extractResult = ZegelReader.extract(redacted, masterKey);
      expect(extractResult.valid, isTrue);
      expect(extractResult.redactedBlocks, contains(2));

      // Non-redacted blocks should still be extractable
      expect(extractResult.content, isNotNull);
      expect(extractResult.content!.length, greaterThan(0));
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
      final sealedStatements = <BatchEntry>[];

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
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        sealedStatements.add(BatchEntry(
          label: 'statement_${quarter}_2025',
          fileBytes: fileBytes,
          key: masterKey,
        ));
      }

      // Batch verify all
      final results = BatchOperations.batchVerify(sealedStatements);

      expect(results.length, equals(4));
      for (var i = 0; i < results.length; i++) {
        expect(results[i].valid, isTrue,
            reason: '${quarters[i]} statement should verify');
        expect(results[i].label, contains(quarters[i]));
      }
    });

    test('manifest for audit package', () {
      // Seal the statements
      final entries = <ManifestFileEntry>[];
      for (final quarter in ['Q1', 'Q2', 'Q3', 'Q4']) {
        final content = Uint8List.fromList(
          utf8.encode('Statement $quarter'),
        );
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'stmt_$quarter.txt',
          salt: _zeroSalt(),
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);
        final inspection = ZegelReader.inspect(fileBytes);

        entries.add(ManifestFileEntry(
          filename: 'stmt_$quarter.txt',
          merkleRoot: inspection.merkleRoot!,
          contentType: 'text/plain',
          fileSize: fileBytes.length,
          fileBytes: fileBytes,
        ));
      }

      // Create manifest
      final auditorKey = _signerKey('auditor');
      final manifest = ZegelManifest.create(
        entries: entries,
        signerId: 'auditor@accounting-firm.com',
        signerKey: auditorKey,
        metadata: {
          'audit_period': 'FY2025',
          'auditor': 'Big Four Accounting',
        },
      );

      // Verify manifest signature
      expect(
        ZegelManifest.verifySignature(manifest, auditorKey),
        isTrue,
        reason: 'Manifest signature should be valid',
      );

      // Deep verify
      final fileMap = <String, Uint8List>{};
      for (final entry in entries) {
        fileMap[entry.filename] = entry.fileBytes!;
      }

      final deepResult = ZegelManifest.deepVerify(
        manifest,
        auditorKey,
        fileMap,
      );
      expect(deepResult.valid, isTrue,
          reason: 'All files should match the manifest');
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
      final fileBytes =
          ZegelWriter.seal(content, masterKey, options: options);

      // University attests with role "issuer"
      final merkleRoot = _getMerkleRoot(fileBytes);
      final universityKey = _signerKey('technical-university');
      final attestation = Attestation.createAttestation(
        merkleRoot,
        'registrar@tu.edu',
        universityKey,
        'This diploma is issued by the Office of the Registrar',
        role: 'issuer',
        timestamp: DateTime.utc(2026, 6, 15, 14, 0, 0),
      );

      expect(attestation['role'], equals('issuer'));

      // Employer verifies the attestation
      final isValid = Attestation.verifyAttestation(
        attestation,
        merkleRoot,
        universityKey,
      );
      expect(isValid, isTrue,
          reason: 'Employer should be able to verify the university attestation');

      // Employer can also inspect public metadata without the master key
      final inspection = ZegelReader.inspect(fileBytes);
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
        classifiedBy: 'director@nso.gov',
        caveat: 'NOFORN',
      );
      final options = ZegelOptions(
        contentType: 'application/octet-stream',
        filename: 'intel-report.bin',
        salt: _zeroSalt(),
        publicMetadata: classificationMeta,
      );
      final fileBytes =
          ZegelWriter.seal(content, masterKey, options: options);

      // 2. Verify classification level
      final inspection = ZegelReader.inspect(fileBytes);
      expect(
        inspection.publicMetadata!['classification_level'],
        equals(ZegelFormat.classificationTopSecret),
      );
      expect(inspection.publicMetadata!['caveat'], equals('NOFORN'));

      // 3. Declassify to CONFIDENTIAL with redaction
      final declassified = Classification.declassify(
        fileBytes: fileBytes,
        masterKey: masterKey,
        newLevel: ZegelFormat.classificationConfidential,
        authority: 'Declassification Review Board',
        declassifiedBy: 'reviewer@drb.gov',
        redactBlockIndices: [0], // Redact the first content block
      );

      // 4. Verify new level
      final declInspection = ZegelReader.inspect(declassified);
      expect(
        declInspection.publicMetadata!['classification_level'],
        equals(ZegelFormat.classificationConfidential),
      );

      // 5. Verify declassified file is still valid
      final result = ZegelReader.verify(declassified, masterKey);
      expect(result.valid, isTrue);

      // 6. Confirm redacted blocks
      expect(result.redactedBlocks, isNotNull);
      expect(result.redactedBlocks, contains(0));
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
          'expenses to the next fiscal year. ' +
          'X' * 50000; // padding to ensure multiple blocks
      final content = Uint8List.fromList(utf8.encode(sourceText));
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'source-memo.txt',
        salt: _zeroSalt(),
      );
      final fileBytes =
          ZegelWriter.seal(content, masterKey, options: options);

      // Generate an excerpt proof for one block (block 0)
      final proof = ExcerptProof.generate(
        fileBytes: fileBytes,
        masterKey: masterKey,
        blockIndex: 0,
      );

      expect(proof, isNotNull);
      expect(proof.excerpt, isNotNull);
      expect(proof.excerpt.isNotEmpty, isTrue);

      // The proof can be verified WITHOUT the master key
      // The verifier only needs the Merkle root (from public header)
      // and the proof data
      final isValid = ExcerptProof.verifyProof(proof);
      expect(isValid, isTrue,
          reason:
              'Third party should be able to verify the excerpt without the key');

      // Verify the Merkle root in the proof matches the file
      final inspection = ZegelReader.inspect(fileBytes);
      expect(proof.merkleRoot, equals(inspection.merkleRoot));
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
      // Create GPS metadata for the damage location
      final gpsMetadata = MediaMetadata.createGpsMetadata(
        latitude: 52.3676,
        longitude: 4.9041,
        altitude: 2.5,
        timestamp: DateTime.utc(2026, 1, 20, 14, 30, 0),
      );

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
          ZegelWriter.seal(photoContent, masterKey, options: options);

      // Extract and verify GPS is preserved
      final result = ZegelReader.extract(fileBytes, masterKey);
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
      final inspection = ZegelReader.inspect(fileBytes);
      expect(inspection.contentType, equals('image/jpeg'));
      expect(inspection.filename, equals('damage_photo_001.jpg'));
    });

    test('batch verify claim documents with provenance', () {
      // Seal multiple claim documents
      final documents = ['damage_report.txt', 'estimate.txt', 'policy.txt'];
      final sealedDocs = <BatchEntry>[];

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
            ZegelWriter.seal(content, masterKey, options: options);

        sealedDocs.add(BatchEntry(
          label: docName,
          fileBytes: fileBytes,
          key: masterKey,
        ));
      }

      // Batch verify all claim documents
      final results = BatchOperations.batchVerify(sealedDocs);

      expect(results.length, equals(3));
      for (final result in results) {
        expect(result.valid, isTrue);
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
      final fileBytes =
          ZegelWriter.seal(content, masterKey, options: options);

      // Verify the file is valid
      final result = ZegelReader.verify(fileBytes, masterKey);
      expect(result.valid, isTrue);

      // Inspect shows split key params
      final inspection = ZegelReader.inspect(fileBytes);
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
      final verifyResult = ZegelReader.verify(fileBytes, reconstructed);
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
      final signingKey = _signerKey('supply-chain');

      // Create a provenance chain
      Uint8List? prevHash;
      final entries = <Map<String, dynamic>>[];

      // Step 1: Manufacturer creates
      final entry1 = ProvenanceVerification.createSignedEntry(
        actor: 'manufacturer@factory.com',
        action: 'manufactured',
        signingKey: signingKey,
        timestamp: DateTime.utc(2026, 1, 10, 8, 0, 0),
        details: {'batch': 'LOT-2026-001', 'location': 'Factory A'},
      );
      entries.add(entry1);
      prevHash = _hexToBytes(entry1['chain_hash'] as String);

      // Step 2: QA inspection
      final entry2 = ProvenanceVerification.createSignedEntry(
        actor: 'qa@factory.com',
        action: 'inspected',
        signingKey: signingKey,
        timestamp: DateTime.utc(2026, 1, 11, 10, 0, 0),
        previousChainHash: prevHash,
        details: {'result': 'passed', 'defects': 0},
      );
      entries.add(entry2);
      prevHash = _hexToBytes(entry2['chain_hash'] as String);

      // Step 3: Shipped
      final entry3 = ProvenanceVerification.createSignedEntry(
        actor: 'logistics@shipping.com',
        action: 'shipped',
        signingKey: signingKey,
        timestamp: DateTime.utc(2026, 1, 15, 6, 0, 0),
        previousChainHash: prevHash,
        details: {'tracking': 'TRK-123456', 'carrier': 'DHL'},
      );
      entries.add(entry3);
      prevHash = _hexToBytes(entry3['chain_hash'] as String);

      // Step 4: Received by retailer
      final entry4 = ProvenanceVerification.createSignedEntry(
        actor: 'receiving@retailer.com',
        action: 'received',
        signingKey: signingKey,
        timestamp: DateTime.utc(2026, 1, 20, 14, 0, 0),
        previousChainHash: prevHash,
        details: {'condition': 'good', 'quantity': 100},
      );
      entries.add(entry4);

      // Verify the entire chain
      final chainValid = ProvenanceVerification.verifyChain(
        entries,
        signingKey,
      );
      expect(chainValid, isTrue,
          reason: 'Supply chain provenance should verify');

      final chronoValid =
          ProvenanceVerification.verifyChronological(entries);
      expect(chronoValid, isTrue,
          reason: 'Supply chain should be chronologically ordered');
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
      final v1Bytes =
          ZegelWriter.seal(v1Content, masterKey, options: v1Options);

      // Verify v1
      final v1Result = ZegelReader.verify(v1Bytes, masterKey);
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
      final v2Bytes =
          ZegelWriter.seal(v2Content, masterKey, options: v2Options);

      // Verify v2
      final v2Result = ZegelReader.verify(v2Bytes, masterKey);
      expect(v2Result.valid, isTrue);

      // Verify the version chain
      final chainValid =
          ContentVersioning.verifyVersionChain([v1Bytes, v2Bytes]);
      expect(chainValid, isTrue,
          reason: 'Software version chain should verify');

      // Inspect v2 for version info
      final v2Inspection = ZegelReader.inspect(v2Bytes);
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
          ZegelWriter.seal(draft1, masterKey, options: draft1Options);

      // Lawyer attests draft 1
      final lawyerKey = _signerKey('lawyer');
      final draft1Root = _getMerkleRoot(draft1Bytes);
      final draft1Attestation = Attestation.createAttestation(
        draft1Root,
        'lawyer@lawfirm.com',
        lawyerKey,
        'Reviewed draft 1, recommend changes to clause 3',
        role: ZegelFormat.roleReviewer,
        timestamp: DateTime.utc(2026, 1, 10),
      );
      expect(
        Attestation.verifyAttestation(
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
          ZegelWriter.seal(draft2, masterKey, options: draft2Options);

      // Both parties attest draft 2
      final draft2Root = _getMerkleRoot(draft2Bytes);
      final partyAKey = _signerKey('party-a');
      final partyBKey = _signerKey('party-b');

      final partyAAttestation = Attestation.createAttestation(
        draft2Root,
        'ceo@company-a.com',
        partyAKey,
        'Agreed to final terms',
        role: ZegelFormat.roleSigner,
        timestamp: DateTime.utc(2026, 1, 20),
      );
      final partyBAttestation = Attestation.createAttestation(
        draft2Root,
        'ceo@company-b.com',
        partyBKey,
        'Agreed to final terms',
        role: ZegelFormat.roleSigner,
        timestamp: DateTime.utc(2026, 1, 21),
      );

      expect(
        Attestation.verifyAttestation(
            partyAAttestation, draft2Root, partyAKey),
        isTrue,
      );
      expect(
        Attestation.verifyAttestation(
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
          ZegelWriter.seal(artContent, masterKey, options: options);

      // Creator attests
      final merkleRoot = _getMerkleRoot(fileBytes);
      final artistKey = _signerKey('jane-artist');
      final attestation = Attestation.createAttestation(
        merkleRoot,
        'jane@artist-studio.com',
        artistKey,
        'I am the original creator of this artwork',
        role: ZegelFormat.roleOwner,
        timestamp: DateTime.utc(2026, 1, 15, 10, 0, 0),
      );

      expect(attestation['role'], equals(ZegelFormat.roleOwner));
      expect(
        Attestation.verifyAttestation(attestation, merkleRoot, artistKey),
        isTrue,
      );

      // Public metadata should be visible without the key
      final inspection = ZegelReader.inspect(fileBytes);
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
      final fileBytes =
          ZegelWriter.seal(record, masterKey, options: options);

      // Verify the record
      final result = ZegelReader.verify(fileBytes, masterKey);
      expect(result.valid, isTrue);

      // Generate disclosure token for cardiologist (block 0: metadata, block 1: first content)
      final cardioToken = ZegelDisclosure.generateToken(
        fileBytes,
        masterKey,
        [0, 1], // metadata + first content block (cardiology data)
      );

      final cardioResult =
          ZegelDisclosure.extractWithToken(fileBytes, cardioToken);
      expect(cardioResult.valid, isTrue);
      expect(cardioResult.disclosedBlocks, contains(0));
      expect(cardioResult.disclosedBlocks, contains(1));
      // Other blocks should not be accessible
      expect(cardioResult.disclosedBlocks, isNot(contains(2)));
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
      final fileBytes =
          ZegelWriter.seal(ballot, masterKey, options: options);

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
      final result = ZegelReader.verify(fileBytes, masterKey);
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
          'privilege_log': 'Blocks 1-2 contain attorney-client privileged material',
        },
      );
      final fileBytes =
          ZegelWriter.seal(evidence, masterKey, options: options);

      // Verify original
      final originalResult = ZegelReader.verify(fileBytes, masterKey);
      expect(originalResult.valid, isTrue);

      // Redact privileged blocks (1 and 2)
      final redacted =
          ZegelRedaction.redact(fileBytes, masterKey, [1, 2]);

      // Redacted file still verifies
      final redactedResult = ZegelReader.verify(redacted, masterKey);
      expect(redactedResult.valid, isTrue);

      // Privileged blocks are marked as redacted
      final extractResult = ZegelReader.extract(redacted, masterKey);
      expect(extractResult.redactedBlocks, containsAll([1, 2]));

      // Non-privileged content (blocks 0, 3) still available
      expect(extractResult.content, isNotNull);
      expect(extractResult.content!.length, greaterThan(0));
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
          ZegelWriter.seal(disclosure, masterKey, options: options);

      // Create a trusted timestamp for the sealed file
      final merkleRoot = _getMerkleRoot(fileBytes);
      final tsBlock = TrustedTimestamp.createTimestampBlock(
        merkleRoot: merkleRoot,
        tsaUrl: 'https://freetsa.org/tsr',
      );

      expect(tsBlock['merkle_root_hex'], isNotNull);
      expect(tsBlock['tsa_url'], equals('https://freetsa.org/tsr'));
      expect(tsBlock['timestamp'], isA<int>());

      // Verify the file
      final result = ZegelReader.verify(fileBytes, masterKey);
      expect(result.valid, isTrue);
    });
  });
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
