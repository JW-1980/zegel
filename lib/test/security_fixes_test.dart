import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

/// Creates a 32-byte test master key (0x00...01).
Uint8List _testKey() {
  final key = Uint8List(32);
  key[31] = 0x01;
  return key;
}

/// Creates a 32-byte all-zeros salt for deterministic testing.
Uint8List _zeroSalt() => Uint8List(32);

/// Creates a different 32-byte master key (0x00...02).
Uint8List _differentKey() {
  final key = Uint8List(32);
  key[31] = 0x02;
  return key;
}

void main() {
  group('Security Fix: Merkle tree domain separation (RFC 6962)', () {
    test('leaf hashes use 0x00 prefix', () {
      final leafData = Uint8List.fromList(sha256.convert([1, 2, 3]).bytes);
      final leafHash = MerkleTree.hashLeaf(leafData);

      // Manually compute expected: SHA-256(0x00 || leafData)
      final prefixed = Uint8List(1 + leafData.length);
      prefixed[0] = 0x00;
      prefixed.setRange(1, prefixed.length, leafData);
      final expected = Uint8List.fromList(sha256.convert(prefixed).bytes);

      expect(leafHash, equals(expected));
    });

    test('internal nodes differ from leaf nodes with same 64-byte data', () {
      // This is the second preimage attack scenario:
      // A 64-byte leaf that equals left||right of two child hashes
      // should NOT produce the same hash as the internal node.
      final left = Uint8List.fromList(sha256.convert([1]).bytes);
      final right = Uint8List.fromList(sha256.convert([2]).bytes);

      // Build tree with two leaves
      final root = MerkleTree.buildRoot([left, right]);

      // Now create a single leaf that is the concatenation of the
      // domain-separated leaf hashes
      final leftLeafHash = MerkleTree.hashLeaf(left);
      final rightLeafHash = MerkleTree.hashLeaf(right);
      final fakeLeafData = Uint8List(64);
      fakeLeafData.setRange(0, 32, leftLeafHash);
      fakeLeafData.setRange(32, 64, rightLeafHash);

      // Hash of this "fake" data as a single leaf
      final fakeHash = Uint8List.fromList(sha256.convert(fakeLeafData).bytes);
      final fakeRoot = MerkleTree.buildRoot([fakeHash]);

      // The roots must differ -- this proves domain separation works.
      expect(root, isNot(equals(fakeRoot)),
          reason: 'Domain separation must prevent leaf/node confusion');
    });

    test('buildRoot produces different result than naive (no prefix) tree', () {
      final leaf1 = Uint8List.fromList(sha256.convert([10]).bytes);
      final leaf2 = Uint8List.fromList(sha256.convert([20]).bytes);

      final root = MerkleTree.buildRoot([leaf1, leaf2]);

      // Naive internal node: SHA-256(left || right) without prefix
      final naiveLeaf1 = leaf1; // No hashLeaf
      final naiveLeaf2 = leaf2;
      final naiveCombined = Uint8List(64);
      naiveCombined.setRange(0, 32, naiveLeaf1);
      naiveCombined.setRange(32, 64, naiveLeaf2);
      final naiveRoot = Uint8List.fromList(sha256.convert(naiveCombined).bytes);

      expect(root, isNot(equals(naiveRoot)),
          reason: 'Domain-separated root must differ from naive root');
    });

    test('single leaf root is domain-separated', () {
      final leaf = Uint8List.fromList(sha256.convert([42]).bytes);
      final root = MerkleTree.buildRoot([leaf]);

      // Should be SHA-256(0x00 || leaf), not just leaf itself.
      expect(root, isNot(equals(leaf)),
          reason: 'Single leaf should still be domain-separated');
      expect(root, equals(MerkleTree.hashLeaf(leaf)));
    });

    test('inclusion proof works with domain separation', () {
      final leaves = <Uint8List>[
        Uint8List.fromList(sha256.convert([1]).bytes),
        Uint8List.fromList(sha256.convert([2]).bytes),
        Uint8List.fromList(sha256.convert([3]).bytes),
        Uint8List.fromList(sha256.convert([4]).bytes),
      ];

      final root = MerkleTree.buildRoot(leaves);
      final proof = MerkleTree.generateProof(leaves, 2);

      expect(
        MerkleTree.verifyInclusion(root, leaves[2], 2, proof, 4),
        isTrue,
        reason: 'Valid inclusion proof should verify',
      );
    });

    test('inclusion proof rejects wrong leaf', () {
      final leaves = <Uint8List>[
        Uint8List.fromList(sha256.convert([1]).bytes),
        Uint8List.fromList(sha256.convert([2]).bytes),
        Uint8List.fromList(sha256.convert([3]).bytes),
      ];

      final root = MerkleTree.buildRoot(leaves);
      final proof = MerkleTree.generateProof(leaves, 0);

      // Try verifying with wrong leaf
      final wrongLeaf = Uint8List.fromList(sha256.convert([99]).bytes);
      expect(
        MerkleTree.verifyInclusion(root, wrongLeaf, 0, proof, 3),
        isFalse,
        reason: 'Wrong leaf should not verify',
      );
    });

    test('roundtrip seal/verify works with domain-separated Merkle tree', () {
      final key = _testKey();
      final content = Uint8List.fromList(utf8.encode('Domain separation test'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'domain.txt',
        salt: _zeroSalt(),
      );

      final sealed = ZegelWriter(key, options).seal(content);
      final result = const ZegelReader().verify(sealed, key);

      expect(result.valid, isTrue);
      expect(result.content, equals(content));
    });
  });

  group('Security Fix: Shamir SSS validation', () {
    test('gfInverse(0) throws ArgumentError', () {
      expect(
        () => ShamirSecretSharing.gfInverse(0),
        throwsA(isA<ArgumentError>()),
        reason: 'Zero has no multiplicative inverse',
      );
    });

    test('gfInverse works for non-zero values', () {
      // a * a^(-1) = 1 in GF(256) for all non-zero a.
      for (int a = 1; a <= 255; a++) {
        final inv = ShamirSecretSharing.gfInverse(a);
        expect(
          ShamirSecretSharing.gfMultiply(a, inv),
          equals(1),
          reason: '$a * inverse($a) should equal 1',
        );
      }
    });

    test('reconstruct rejects duplicate x-coordinates', () {
      final key = _testKey();
      final shares = ShamirSecretSharing.split(key, 3, 5);

      // Create duplicates
      final dupeShares = [shares[0], shares[0], shares[2]];

      expect(
        () => ShamirSecretSharing.reconstruct(dupeShares, 3),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('Duplicate x-coordinate'),
        )),
      );
    });

    test('reconstruct rejects zero x-coordinate', () {
      final key = _testKey();
      final shares = ShamirSecretSharing.split(key, 3, 5);

      // Corrupt first share's x-coordinate to 0
      final badShare = Uint8List.fromList(shares[0]);
      badShare[0] = 0;

      expect(
        () => ShamirSecretSharing.reconstruct(
            [badShare, shares[1], shares[2]], 3),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('invalid x-coordinate 0'),
        )),
      );
    });

    test('reconstruct rejects invalid share length', () {
      final shortShare = Uint8List(10); // Should be 33
      shortShare[0] = 1;

      expect(
        () => ShamirSecretSharing.reconstruct(
          [shortShare, Uint8List(33)..first, Uint8List(33)],
          3,
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('invalid length'),
        )),
      );
    });

    test('M shares reconstruct correctly', () {
      final key = _testKey();
      final shares = ShamirSecretSharing.split(key, 3, 5);

      final reconstructed = ShamirSecretSharing.reconstruct(
        [shares[0], shares[2], shares[4]],
        3,
      );
      expect(reconstructed, equals(key));
    });

    test('M-1 shares produce wrong key', () {
      final key = _testKey();
      final shares = ShamirSecretSharing.split(key, 3, 5);

      // Use only 2 shares (below threshold of 3) -- this will throw since
      // we need at least threshold shares.
      expect(
        () => ShamirSecretSharing.reconstruct([shares[0], shares[1]], 3),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('extra shares beyond threshold still work', () {
      final key = _testKey();
      final shares = ShamirSecretSharing.split(key, 3, 5);

      // Provide 4 shares (more than threshold of 3) -- only first 3 are used
      final reconstructed = ShamirSecretSharing.reconstruct(
        [shares[0], shares[1], shares[2], shares[3]],
        3,
      );
      expect(reconstructed, equals(key));
    });
  });

  group('Security Fix: Disclosure token expiration', () {
    test('extractWithToken rejects expired token', () {
      final key = _testKey();
      final content = Uint8List.fromList(utf8.encode('Token expiry test'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'token.txt',
        salt: _zeroSalt(),
        enableSelectiveDisclosure: true,
      );

      final sealed = ZegelWriter(key, options).seal(content);
      final inspection = const ZegelReader().inspect(sealed);

      // Create a token that expired 1 hour ago.
      final int pastEpoch =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 - 3600;

      final token = <String, dynamic>{
        'version': 1,
        'merkle_root': 'dummy',
        'block_keys': <String, dynamic>{},
        'expires_at': pastEpoch,
      };

      expect(
        () => const ZegelReader().extractWithToken(sealed, token),
        throwsA(isA<ZegelExpiredException>()),
        reason: 'Expired tokens must be rejected',
      );
    });

    test('extractWithToken accepts non-expired token', () {
      final key = _testKey();
      final content = Uint8List.fromList(utf8.encode('Valid token test'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'valid.txt',
        salt: _zeroSalt(),
        enableSelectiveDisclosure: true,
      );

      final sealed = ZegelWriter(key, options).seal(content);

      // Parse the file to get merkle root and salt for token generation.
      final inspection = const ZegelReader().inspect(sealed);

      // For a full token test, we'd need to generate a proper token with
      // real block keys. Here we just verify the expiration check path
      // by providing a token that expires in the future.
      final int futureEpoch =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600;

      // This token has a valid expiration but wrong block keys, so it will
      // fail at decryption, not at expiration check.
      final token = <String, dynamic>{
        'version': 1,
        'block_keys': <String, dynamic>{},
        'expires_at': futureEpoch,
      };

      // Should not throw ZegelExpiredException (may throw other errors
      // due to empty block_keys, but that's expected).
      try {
        const ZegelReader().extractWithToken(sealed, token);
      } on ZegelExpiredException {
        fail('Non-expired token should not throw ZegelExpiredException');
      } catch (_) {
        // Other exceptions are acceptable (e.g., no block keys to decrypt).
      }
    });

    test('isTokenExpired correctly identifies expired tokens', () {
      final pastToken = <String, dynamic>{
        'expires_at':
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 - 3600,
      };
      final futureToken = <String, dynamic>{
        'expires_at':
            DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 3600,
      };
      final noExpiryToken = <String, dynamic>{};

      expect(SelectiveDisclosure.isTokenExpired(pastToken), isTrue);
      expect(SelectiveDisclosure.isTokenExpired(futureToken), isFalse);
      expect(SelectiveDisclosure.isTokenExpired(noExpiryToken), isFalse);
    });
  });

  group('Security Fix: Argon2id minimum parameters', () {
    test('rejects time cost below minimum', () {
      expect(
        () => ZegelWriter(
          _testKey(),
          const ZegelOptions(
            argon2TimeCost: 1, // Below minimum of 2
            argon2MemoryCost: 19456,
          ),
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('time cost'),
        )),
      );
    });

    test('rejects memory cost below minimum', () {
      expect(
        () => ZegelWriter(
          _testKey(),
          const ZegelOptions(
            argon2TimeCost: 2,
            argon2MemoryCost: 1024, // Below minimum of 19456
          ),
        ),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('memory cost'),
        )),
      );
    });

    test('accepts OWASP-compliant parameters', () {
      // Should not throw.
      final writer = ZegelWriter(
        _testKey(),
        const ZegelOptions(
          argon2TimeCost: 2,
          argon2MemoryCost: 19456,
        ),
      );
      expect(writer, isNotNull);
    });

    test('accepts parameters above minimum', () {
      final writer = ZegelWriter(
        _testKey(),
        const ZegelOptions(
          argon2TimeCost: 4,
          argon2MemoryCost: 65536, // 64 MiB
        ),
      );
      expect(writer, isNotNull);
    });
  });

  group('Security Fix: Key commitment auto-enabled with passwords', () {
    test('password-derived files have key commitment flag set', () {
      final key = _testKey();
      final content = Uint8List.fromList(utf8.encode('Password test'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'pwd.txt',
        salt: _zeroSalt(),
        argon2TimeCost: 2,
        argon2MemoryCost: 19456,
        // Note: enableKeyCommitment is NOT explicitly set
      );

      final sealed = ZegelWriter(key, options).seal(content);
      final inspection = const ZegelReader().inspect(sealed);

      expect(
        inspection.flags & ZegelFormat.flagHasKeyCommitment != 0,
        isTrue,
        reason: 'Password-derived files must auto-enable key commitment',
      );
      expect(
        inspection.flags & ZegelFormat.flagPasswordDerived != 0,
        isTrue,
      );
    });

    test('non-password files without explicit flag have no key commitment', () {
      final key = _testKey();
      final content = Uint8List.fromList(utf8.encode('No password'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'nopwd.txt',
        salt: _zeroSalt(),
      );

      final sealed = ZegelWriter(key, options).seal(content);
      final inspection = const ZegelReader().inspect(sealed);

      expect(
        inspection.flags & ZegelFormat.flagHasKeyCommitment != 0,
        isFalse,
        reason: 'Non-password files should not auto-enable key commitment',
      );
    });
  });

  group('Security Fix: AAD in AES-GCM', () {
    test('roundtrip works with AAD', () {
      final key = _testKey();
      final content = Uint8List.fromList(utf8.encode('AAD test content'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'aad.txt',
        salt: _zeroSalt(),
      );

      final sealed = ZegelWriter(key, options).seal(content);
      final result = const ZegelReader().verify(sealed, key);

      expect(result.valid, isTrue);
      expect(result.content, equals(content));
    });

    test('roundtrip with metadata and AAD', () {
      final key = _testKey();
      final content = Uint8List.fromList(utf8.encode('Metadata + AAD'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'meta_aad.txt',
        salt: _zeroSalt(),
        metadata: {'key': 'value', 'number': 42},
      );

      final sealed = ZegelWriter(key, options).seal(content);
      final result = const ZegelReader().verify(sealed, key);

      expect(result.valid, isTrue);
      expect(result.content, equals(content));
      expect(result.metadata!['key'], equals('value'));
      expect(result.metadata!['number'], equals(42));
    });

    test('roundtrip with compression and AAD', () {
      final key = _testKey();
      final content = Uint8List.fromList(
        utf8.encode('Compressed AAD test ' * 100),
      );
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'compress_aad.txt',
        salt: _zeroSalt(),
        compress: true,
      );

      final sealed = ZegelWriter(key, options).seal(content);
      final result = const ZegelReader().verify(sealed, key);

      expect(result.valid, isTrue);
      expect(result.content, equals(content));
    });

    test('roundtrip with key commitment and AAD', () {
      final key = _testKey();
      final content = Uint8List.fromList(utf8.encode('Key commit + AAD'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'kc_aad.txt',
        salt: _zeroSalt(),
        enableKeyCommitment: true,
      );

      final sealed = ZegelWriter(key, options).seal(content);
      final result = const ZegelReader().verify(sealed, key);

      expect(result.valid, isTrue);
      expect(result.content, equals(content));
    });

    test('wrong key fails with AAD', () {
      final key = _testKey();
      final wrongKey = _differentKey();
      final content = Uint8List.fromList(utf8.encode('Wrong key + AAD'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'wrongkey.txt',
        salt: _zeroSalt(),
      );

      final sealed = ZegelWriter(key, options).seal(content);

      expect(
        () => const ZegelReader().verify(sealed, wrongKey),
        throwsA(anything),
        reason: 'Wrong key must fail verification',
      );
    });

    test('multi-block roundtrip with AAD', () {
      final key = _testKey();
      // 2 blocks + partial third block
      final content = Uint8List(65536 * 2 + 100);
      for (int i = 0; i < content.length; i++) {
        content[i] = i & 0xFF;
      }
      final options = ZegelOptions(
        contentType: 'application/octet-stream',
        filename: 'multiblock_aad.bin',
        salt: _zeroSalt(),
      );

      final sealed = ZegelWriter(key, options).seal(content);
      final result = const ZegelReader().verify(sealed, key);

      expect(result.valid, isTrue);
      expect(result.content, equals(content));
    });

    test('selective disclosure with AAD', () {
      final key = _testKey();
      final content = Uint8List.fromList(utf8.encode('Disclosure + AAD'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'disclose_aad.txt',
        salt: _zeroSalt(),
        enableSelectiveDisclosure: true,
      );

      final sealed = ZegelWriter(key, options).seal(content);

      // Full verification should work.
      final result = const ZegelReader().verify(sealed, key);
      expect(result.valid, isTrue);
      expect(result.content, equals(content));
    });

    test('canary trap roundtrip with AAD', () {
      final key = _testKey();
      final content = Uint8List.fromList(utf8.encode('Canary + AAD'));
      final recipientId = Uint8List(32);
      recipientId[0] = 0xAB;

      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'canary_aad.txt',
        salt: _zeroSalt(),
        recipientId: recipientId,
      );

      final sealed = ZegelWriter(key, options).seal(content);
      final result = const ZegelReader().verify(sealed, key);

      expect(result.valid, isTrue);
      expect(result.content, equals(content));
    });
  });

  group('Security Fix: Wrong key detection', () {
    test('random wrong key fails', () {
      final key = _testKey();
      final wrongKey = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        wrongKey[i] = 0xFF;
      }

      final content = Uint8List.fromList(utf8.encode('Wrong key test'));
      final sealed = ZegelWriter(
          key,
          const ZegelOptions(
            contentType: 'text/plain',
            filename: 'test.txt',
            salt: null,
          )).seal(content);

      expect(
        () => const ZegelReader().verify(sealed, wrongKey),
        throwsA(anything),
      );
    });

    test('key differing by 1 bit fails', () {
      final key = _testKey();
      final almostKey = Uint8List.fromList(key);
      almostKey[0] ^= 0x01; // Flip 1 bit

      final content = Uint8List.fromList(utf8.encode('1-bit key test'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: '1bit.txt',
        salt: _zeroSalt(),
      );

      final sealed = ZegelWriter(key, options).seal(content);

      expect(
        () => const ZegelReader().verify(sealed, almostKey),
        throwsA(anything),
      );
    });

    test('all-zeros key fails when file was sealed with different key', () {
      final key = _testKey();
      final zeroKey = Uint8List(32);

      final content = Uint8List.fromList(utf8.encode('Zero key test'));
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'zero.txt',
        salt: _zeroSalt(),
      );

      final sealed = ZegelWriter(key, options).seal(content);

      expect(
        () => const ZegelReader().verify(sealed, zeroKey),
        throwsA(anything),
      );
    });
  });

  group('Structured blocks roundtrip', () {
    test('SbomBlock encode/decode', () {
      const sbom = SbomBlock(
        packages: [
          SbomPackage(
            name: 'crypto',
            version: '3.0.3',
            hashAlgorithm: 'SHA-256',
            hashValue: 'abc123',
            license: 'BSD-3-Clause',
          ),
          SbomPackage(
            name: 'pointycastle',
            version: '3.7.3',
            license: 'MIT',
          ),
        ],
        sbomFormat: 'CycloneDX',
        toolName: 'zegel-sbom',
      );

      final encoded = sbom.encode();
      final decoded = SbomBlock.decode(encoded);

      expect(decoded.packages.length, equals(2));
      expect(decoded.packages[0].name, equals('crypto'));
      expect(decoded.packages[0].version, equals('3.0.3'));
      expect(decoded.packages[0].hashAlgorithm, equals('SHA-256'));
      expect(decoded.packages[1].name, equals('pointycastle'));
      expect(decoded.sbomFormat, equals('CycloneDX'));
      expect(decoded.toolName, equals('zegel-sbom'));
    });

    test('RoyaltyBlock encode/decode', () {
      final royalty = RoyaltyBlock(
        recipients: [
          const RoyaltyRecipient(
            identifier: 'artist-001',
            percentage: 60.0,
            name: 'Main Artist',
            role: 'creator',
          ),
          const RoyaltyRecipient(
            identifier: 'producer-001',
            percentage: 25.0,
            name: 'Producer',
            role: 'producer',
          ),
          const RoyaltyRecipient(
            identifier: 'label-001',
            percentage: 15.0,
            name: 'Record Label',
            role: 'distributor',
          ),
        ],
        currency: 'USD',
      );

      final encoded = royalty.encode();
      final decoded = RoyaltyBlock.decode(encoded);

      expect(decoded.recipients.length, equals(3));
      expect(decoded.recipients[0].percentage, equals(60.0));
      expect(decoded.recipients[1].name, equals('Producer'));
      expect(decoded.currency, equals('USD'));
    });

    test('RoyaltyBlock rejects percentages not summing to 100', () {
      expect(
        () => RoyaltyBlock(
          recipients: [
            const RoyaltyRecipient(identifier: 'a', percentage: 50.0),
            const RoyaltyRecipient(identifier: 'b', percentage: 30.0),
            // Missing 20%
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('MeasurementBlock encode/decode', () {
      const measurement = MeasurementBlock(
        timestamp: 1700000000,
        sensorId: 'temp-sensor-01',
        value: 2.5,
        unit: 'celsius',
        measurementType: 'temperature',
        location: 'lat:52.3676,lon:4.9041',
        calibration: const CalibrationInfo(
          calibratedAt: 1690000000,
          calibrationAuthority: 'NIST',
          accuracy: '+/- 0.1',
        ),
      );

      final encoded = measurement.encode();
      final decoded = MeasurementBlock.decode(encoded);

      expect(decoded.value, equals(2.5));
      expect(decoded.unit, equals('celsius'));
      expect(decoded.sensorId, equals('temp-sensor-01'));
      expect(decoded.location, equals('lat:52.3676,lon:4.9041'));
      expect(decoded.calibration!.calibrationAuthority, equals('NIST'));
    });

    test('PrivilegeLogBlock encode/decode', () {
      const privilegeLog = PrivilegeLogBlock(
        entries: [
          RedactionBasis(
            blockIndex: 3,
            legalAuthority: 'FOIA Exemption 5',
            reason: 'Deliberative process privilege',
            date: 1700000000,
            authorisedBy: 'J. Smith, Esq.',
            caseReference: 'ACME-2024-001',
          ),
        ],
        caseTitle: 'ACME v. State',
      );

      final encoded = privilegeLog.encode();
      final decoded = PrivilegeLogBlock.decode(encoded);

      expect(decoded.entries.length, equals(1));
      expect(decoded.entries[0].blockIndex, equals(3));
      expect(decoded.entries[0].legalAuthority, equals('FOIA Exemption 5'));
      expect(decoded.caseTitle, equals('ACME v. State'));
    });
  });

  group('Format constants: new block types', () {
    test('new block type constants are defined', () {
      expect(ZegelFormat.blockSignature, equals(0x0E));
      expect(ZegelFormat.blockDeviceAttestation, equals(0x0F));
      expect(ZegelFormat.blockSbom, equals(0x10));
      expect(ZegelFormat.blockRoyalty, equals(0x11));
      expect(ZegelFormat.blockMeasurement, equals(0x12));
      expect(ZegelFormat.blockPrivilegeLog, equals(0x13));
      expect(ZegelFormat.blockBuildAttestation, equals(0x14));
    });

    test('new block types do not conflict with existing types', () {
      final existingTypes = <int>{
        ZegelFormat.blockContent,
        ZegelFormat.blockMetadata,
        ZegelFormat.blockPublicMetadata,
        ZegelFormat.blockFileHeader,
        ZegelFormat.blockProvenance,
        ZegelFormat.blockRedacted,
        ZegelFormat.blockAttestation,
        ZegelFormat.blockReference,
        ZegelFormat.blockAudit,
        ZegelFormat.blockDisclosureIndex,
        ZegelFormat.blockTimestamp,
        ZegelFormat.blockExcerpt,
        ZegelFormat.blockManifestEntry,
      };

      final newTypes = <int>{
        ZegelFormat.blockSignature,
        ZegelFormat.blockDeviceAttestation,
        ZegelFormat.blockSbom,
        ZegelFormat.blockRoyalty,
        ZegelFormat.blockMeasurement,
        ZegelFormat.blockPrivilegeLog,
        ZegelFormat.blockBuildAttestation,
      };

      // No overlap between existing and new.
      expect(existingTypes.intersection(newTypes), isEmpty);
      // No duplicates within new types.
      expect(newTypes.length, equals(7));
    });
  });
}
