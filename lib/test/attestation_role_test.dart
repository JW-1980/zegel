import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

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
        final attestation = Attestation.createRoleAttestation(
          merkleRoot,
          'notary@example.com',
          signerKey,
          'Notarized and approved',
          ZegelFormat.roleNotary,
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
          final attestation = Attestation.createRoleAttestation(
            merkleRoot,
            'user-$role@example.com',
            signerKey,
            'Attestation with role $role',
            role,
            timestamp: DateTime.utc(2026, 1, 15, 12, 0, 0),
          );

          expect(
            attestation['role'],
            equals(role),
            reason: 'Role "$role" should be accepted and stored',
          );
          expect(attestation['hmac_hex'], isNotNull);
        }
      });

      test('rejects invalid roles', () {
        final signerKey = _signerKey('user');
        expect(
          () => Attestation.createRoleAttestation(
            merkleRoot,
            'user@example.com',
            signerKey,
            'Statement',
            'invalid_role',
          ),
          throwsA(isA<ArgumentError>()),
        );
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

        expect(
          attestation.containsKey('role'),
          isFalse,
          reason: 'Role should be absent when not specified',
        );
      });
    });

    group('attestation verification with roles', () {
      test('verification succeeds for role attestation', () {
        final signerKey = _signerKey('auditor');
        final attestation = Attestation.createRoleAttestation(
          merkleRoot,
          'auditor@example.com',
          signerKey,
          'Audit completed',
          ZegelFormat.roleAuditor,
          timestamp: DateTime.utc(2026, 3, 1, 9, 0, 0),
        );

        final isValid = Attestation.verifyRoleAttestation(
          attestation,
          merkleRoot,
          signerKey,
        );
        expect(isValid, isTrue);
      });

      test('role verification fails with wrong key', () {
        final signerKey = _signerKey('legit');
        final wrongKey = _signerKey('imposter');
        final attestation = Attestation.createRoleAttestation(
          merkleRoot,
          'legit@example.com',
          signerKey,
          'Legitimate attestation',
          ZegelFormat.roleSigner,
          timestamp: DateTime.utc(2026, 3, 1, 9, 0, 0),
        );

        final isValid = Attestation.verifyRoleAttestation(
          attestation,
          merkleRoot,
          wrongKey,
        );
        expect(isValid, isFalse);
      });
    });

    group('checkPolicy', () {
      test('succeeds when all required roles are present', () {
        final signerKey = _signerKey('signer');
        final notaryKey = _signerKey('notary');
        final auditorKey = _signerKey('auditor');

        final attestations = <Map<String, dynamic>>[
          Attestation.createRoleAttestation(
            merkleRoot,
            'signer@example.com',
            signerKey,
            'I approve',
            ZegelFormat.roleSigner,
            timestamp: DateTime.utc(2026, 2, 1, 10, 0, 0),
          ),
          Attestation.createRoleAttestation(
            merkleRoot,
            'notary@example.com',
            notaryKey,
            'Notarized',
            ZegelFormat.roleNotary,
            timestamp: DateTime.utc(2026, 2, 1, 10, 30, 0),
          ),
          Attestation.createRoleAttestation(
            merkleRoot,
            'auditor@example.com',
            auditorKey,
            'Audited',
            ZegelFormat.roleAuditor,
            timestamp: DateTime.utc(2026, 2, 1, 11, 0, 0),
          ),
        ];

        final signerKeys = <String, Uint8List>{
          'signer@example.com': signerKey,
          'notary@example.com': notaryKey,
          'auditor@example.com': auditorKey,
        };

        final result = Attestation.checkPolicy(
          attestations,
          [
            ZegelFormat.roleSigner,
            ZegelFormat.roleNotary,
            ZegelFormat.roleAuditor,
          ],
          merkleRoot,
          signerKeys,
        );

        expect(
          result.allRolesFulfilled,
          isTrue,
          reason: 'All required roles are present',
        );
        expect(result.missingRoles, isEmpty);
      });

      test('fails when a required role is missing', () {
        final signerKey = _signerKey('signer');

        final attestations = <Map<String, dynamic>>[
          Attestation.createRoleAttestation(
            merkleRoot,
            'signer@example.com',
            signerKey,
            'Signed',
            ZegelFormat.roleSigner,
            timestamp: DateTime.utc(2026, 2, 1, 10, 0, 0),
          ),
        ];

        final signerKeys = <String, Uint8List>{'signer@example.com': signerKey};

        final result = Attestation.checkPolicy(
          attestations,
          [ZegelFormat.roleSigner, ZegelFormat.roleNotary],
          merkleRoot,
          signerKeys,
        );

        expect(
          result.allRolesFulfilled,
          isFalse,
          reason: 'Notary role is missing',
        );
        expect(result.missingRoles, contains(ZegelFormat.roleNotary));
      });

      test('fails when HMAC verification fails', () {
        final signerKey = _signerKey('signer');
        final wrongKey = _signerKey('wrong');

        final attestations = <Map<String, dynamic>>[
          Attestation.createRoleAttestation(
            merkleRoot,
            'signer@example.com',
            signerKey,
            'Signed',
            ZegelFormat.roleSigner,
            timestamp: DateTime.utc(2026, 2, 1, 10, 0, 0),
          ),
        ];

        // Provide wrong key for verification
        final signerKeys = <String, Uint8List>{'signer@example.com': wrongKey};

        final result = Attestation.checkPolicy(
          attestations,
          [ZegelFormat.roleSigner],
          merkleRoot,
          signerKeys,
        );

        expect(
          result.allRolesFulfilled,
          isFalse,
          reason: 'Policy check should fail when HMAC verification fails',
        );
        expect(result.invalidSigners, contains('signer@example.com'));
      });

      test('empty required roles always passes', () {
        final result = Attestation.checkPolicy(
          <Map<String, dynamic>>[],
          <String>[],
          merkleRoot,
          <String, Uint8List>{},
        );

        expect(
          result.allRolesFulfilled,
          isTrue,
          reason: 'No required roles means policy is trivially satisfied',
        );
        expect(result.missingRoles, isEmpty);
      });
    });
  });
}
