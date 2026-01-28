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

/// Derives a 32-byte signer key from a string identifier.
Uint8List _signerKey(String id) {
  return Uint8List.fromList(sha256.convert(utf8.encode(id)).bytes);
}

/// Creates a 32-byte Merkle root for testing.
Uint8List _testMerkleRoot() {
  return Uint8List.fromList(
    sha256.convert(utf8.encode('test-merkle-root-attestation')).bytes,
  );
}

void main() {
  group('Attestation Roles', () {
    late Uint8List merkleRoot;

    setUp(() {
      merkleRoot = _testMerkleRoot();
    });

    group('createRoleAttestation', () {
      test('includes role in JSON', () {
        final signerKey = _signerKey('notary');
        final attestation = Attestation.createAttestation(
          merkleRoot,
          'notary@example.com',
          signerKey,
          'Notarized and approved',
          role: ZegelFormat.roleNotary,
          timestamp: DateTime.utc(2026, 1, 15, 12, 0, 0),
        );

        expect(attestation.containsKey('role'), isTrue);
        expect(attestation['role'], equals(ZegelFormat.roleNotary));
      });

      test('all standard roles are accepted', () {
        final standardRoles = [
          ZegelFormat.roleOwner,
          ZegelFormat.roleSigner,
          ZegelFormat.roleWitness,
          ZegelFormat.roleNotary,
          ZegelFormat.roleAuditor,
          ZegelFormat.roleReviewer,
        ];

        for (final role in standardRoles) {
          final signerKey = _signerKey('user-$role');
          final attestation = Attestation.createAttestation(
            merkleRoot,
            'user-$role@example.com',
            signerKey,
            'Attestation with role $role',
            role: role,
            timestamp: DateTime.utc(2026, 1, 15, 12, 0, 0),
          );

          expect(attestation['role'], equals(role),
              reason: 'Role "$role" should be accepted and stored');
          expect(attestation['hmac_hex'], isNotNull);
        }
      });

      test('attestation without role omits role field', () {
        final signerKey = _signerKey('no-role');
        final attestation = Attestation.createAttestation(
          merkleRoot,
          'anon@example.com',
          signerKey,
          'Approved without role',
          timestamp: DateTime.utc(2026, 1, 15, 12, 0, 0),
        );

        // When no role is specified, the field should be absent
        expect(attestation.containsKey('role'), isFalse,
            reason: 'Role should be absent when not specified');
      });
    });

    group('attestation verification with roles', () {
      test('verification succeeds for attestation with role', () {
        final signerKey = _signerKey('auditor');
        final attestation = Attestation.createAttestation(
          merkleRoot,
          'auditor@example.com',
          signerKey,
          'Audit completed',
          role: ZegelFormat.roleAuditor,
          timestamp: DateTime.utc(2026, 3, 1, 9, 0, 0),
        );

        final isValid = Attestation.verifyAttestation(
          attestation,
          merkleRoot,
          signerKey,
        );
        expect(isValid, isTrue);
      });

      test('verification fails with wrong key', () {
        final signerKey = _signerKey('legit');
        final wrongKey = _signerKey('imposter');
        final attestation = Attestation.createAttestation(
          merkleRoot,
          'legit@example.com',
          signerKey,
          'Legitimate attestation',
          role: ZegelFormat.roleSigner,
          timestamp: DateTime.utc(2026, 3, 1, 9, 0, 0),
        );

        final isValid = Attestation.verifyAttestation(
          attestation,
          merkleRoot,
          wrongKey,
        );
        expect(isValid, isFalse);
      });
    });

    group('checkPolicy', () {
      test('succeeds when all required roles are present', () {
        final buyerKey = _signerKey('buyer');
        final sellerKey = _signerKey('seller');
        final notaryKey = _signerKey('notary');

        final attestations = <Map<String, dynamic>>[
          Attestation.createAttestation(
            merkleRoot,
            'buyer@example.com',
            buyerKey,
            'I agree to purchase',
            role: 'buyer',
            timestamp: DateTime.utc(2026, 2, 1, 10, 0, 0),
          ),
          Attestation.createAttestation(
            merkleRoot,
            'seller@example.com',
            sellerKey,
            'I agree to sell',
            role: 'seller',
            timestamp: DateTime.utc(2026, 2, 1, 10, 30, 0),
          ),
          Attestation.createAttestation(
            merkleRoot,
            'notary@example.com',
            notaryKey,
            'Notarized',
            role: ZegelFormat.roleNotary,
            timestamp: DateTime.utc(2026, 2, 1, 11, 0, 0),
          ),
        ];

        final signerKeys = {
          'buyer@example.com': buyerKey,
          'seller@example.com': sellerKey,
          'notary@example.com': notaryKey,
        };

        final result = Attestation.checkPolicy(
          attestations: attestations,
          merkleRoot: merkleRoot,
          requiredRoles: ['buyer', 'seller', ZegelFormat.roleNotary],
          signerKeys: signerKeys,
        );

        expect(result.satisfied, isTrue,
            reason: 'All required roles are present');
        expect(result.missingRoles, isEmpty);
      });

      test('fails when a required role is missing', () {
        final buyerKey = _signerKey('buyer');
        final sellerKey = _signerKey('seller');

        final attestations = <Map<String, dynamic>>[
          Attestation.createAttestation(
            merkleRoot,
            'buyer@example.com',
            buyerKey,
            'I agree to purchase',
            role: 'buyer',
            timestamp: DateTime.utc(2026, 2, 1, 10, 0, 0),
          ),
          Attestation.createAttestation(
            merkleRoot,
            'seller@example.com',
            sellerKey,
            'I agree to sell',
            role: 'seller',
            timestamp: DateTime.utc(2026, 2, 1, 10, 30, 0),
          ),
          // Notary attestation is missing
        ];

        final signerKeys = {
          'buyer@example.com': buyerKey,
          'seller@example.com': sellerKey,
        };

        final result = Attestation.checkPolicy(
          attestations: attestations,
          merkleRoot: merkleRoot,
          requiredRoles: ['buyer', 'seller', ZegelFormat.roleNotary],
          signerKeys: signerKeys,
        );

        expect(result.satisfied, isFalse,
            reason: 'Notary role is missing');
        expect(result.missingRoles, contains(ZegelFormat.roleNotary));
      });

      test('verifies HMAC for each attestation', () {
        final buyerKey = _signerKey('buyer');
        final wrongKey = _signerKey('wrong');

        final attestations = <Map<String, dynamic>>[
          Attestation.createAttestation(
            merkleRoot,
            'buyer@example.com',
            buyerKey,
            'I agree',
            role: 'buyer',
            timestamp: DateTime.utc(2026, 2, 1, 10, 0, 0),
          ),
        ];

        // Provide wrong key for verification
        final signerKeys = {
          'buyer@example.com': wrongKey, // wrong key
        };

        final result = Attestation.checkPolicy(
          attestations: attestations,
          merkleRoot: merkleRoot,
          requiredRoles: ['buyer'],
          signerKeys: signerKeys,
        );

        expect(result.satisfied, isFalse,
            reason:
                'Policy check should fail when HMAC verification fails');
      });

      test('multiple attestations with same role are allowed', () {
        final witness1Key = _signerKey('witness1');
        final witness2Key = _signerKey('witness2');

        final attestations = <Map<String, dynamic>>[
          Attestation.createAttestation(
            merkleRoot,
            'witness1@example.com',
            witness1Key,
            'I witnessed the signing',
            role: ZegelFormat.roleWitness,
            timestamp: DateTime.utc(2026, 2, 1, 10, 0, 0),
          ),
          Attestation.createAttestation(
            merkleRoot,
            'witness2@example.com',
            witness2Key,
            'I also witnessed the signing',
            role: ZegelFormat.roleWitness,
            timestamp: DateTime.utc(2026, 2, 1, 10, 5, 0),
          ),
        ];

        final signerKeys = {
          'witness1@example.com': witness1Key,
          'witness2@example.com': witness2Key,
        };

        final result = Attestation.checkPolicy(
          attestations: attestations,
          merkleRoot: merkleRoot,
          requiredRoles: [ZegelFormat.roleWitness],
          signerKeys: signerKeys,
        );

        expect(result.satisfied, isTrue,
            reason:
                'Multiple attestations with same role should satisfy policy');
      });

      test('empty required roles always passes', () {
        final result = Attestation.checkPolicy(
          attestations: <Map<String, dynamic>>[],
          merkleRoot: merkleRoot,
          requiredRoles: <String>[],
          signerKeys: <String, Uint8List>{},
        );

        expect(result.satisfied, isTrue,
            reason: 'No required roles means policy is trivially satisfied');
        expect(result.missingRoles, isEmpty);
      });
    });

    group('role attestation in sealed files', () {
      test('attestation role preserved through seal/extract', () {
        final masterKey = _testKey();
        final content = Uint8List.fromList(utf8.encode('Contract'));
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'contract.txt',
          salt: _zeroSalt(),
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        // Get Merkle root for attestation
        final inspection = ZegelReader.inspect(fileBytes);
        final fileRoot = inspection.merkleRoot!;

        // Create a role attestation
        final notaryKey = _signerKey('notary');
        final attestation = Attestation.createAttestation(
          fileRoot,
          'notary@example.com',
          notaryKey,
          'Notarized',
          role: ZegelFormat.roleNotary,
          timestamp: DateTime.utc(2026, 4, 1, 12, 0, 0),
        );

        expect(attestation['role'], equals(ZegelFormat.roleNotary));
        expect(attestation['signer_id'], equals('notary@example.com'));
        expect(attestation['statement'], equals('Notarized'));

        // Verify the attestation
        final isValid = Attestation.verifyAttestation(
          attestation,
          fileRoot,
          notaryKey,
        );
        expect(isValid, isTrue);
      });
    });
  });
}
