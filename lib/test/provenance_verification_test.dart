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

/// Creates a second distinct key.
Uint8List _otherKey() {
  final key = Uint8List(32);
  key[31] = 0x02;
  return key;
}

/// Creates a 32-byte test Merkle root.
Uint8List _testMerkleRoot() {
  return Uint8List.fromList(sha256.convert([0x01, 0x02, 0x03]).bytes);
}

/// Creates a provenance chain of [count] entries using
/// ProvenanceVerification.createEvent.
List<Map<String, dynamic>> _createChain(
  Uint8List signerKey,
  Uint8List merkleRoot,
  int count, {
  bool chronological = true,
}) {
  final entries = <Map<String, dynamic>>[];
  String? previousEventHash;

  for (var i = 0; i < count; i++) {
    final timestamp = chronological
        ? DateTime.utc(2026, 1, 1 + i, 10, 0, 0)
        : DateTime.utc(2026, 1, count - i, 10, 0, 0); // reverse order

    final entry = ProvenanceVerification.createEvent(
      i == 0 ? 'created' : 'transferred',
      'user_$i@example.com',
      signerKey,
      merkleRoot,
      previousEventHash: previousEventHash,
      details: {'step': i, 'note': 'Step $i in chain'},
      timestamp: timestamp,
    );

    entries.add(entry);
    previousEventHash = entry['event_hash'] as String?;
  }

  return entries;
}

void main() {
  group('ProvenanceVerification', () {
    late Uint8List signerKey;
    late Uint8List merkleRoot;

    setUp(() {
      signerKey = _testKey();
      merkleRoot = _testMerkleRoot();
    });

    group('chronological verification', () {
      test('succeeds for ordered entries', () {
        final entries = _createChain(signerKey, merkleRoot, 5);

        final result = ProvenanceVerification.verifyChain(entries, signerKey);
        expect(
          result['valid'],
          isTrue,
          reason: 'Chronologically ordered entries should pass verification',
        );
      });

      test('fails for out-of-order timestamps', () {
        // Create entries with reverse timestamps
        final entries = _createChain(
          signerKey,
          merkleRoot,
          5,
          chronological: false,
        );

        final result = ProvenanceVerification.verifyChain(entries, signerKey);
        // Out-of-order timestamps or broken chain links should cause errors
        final errors = result['errors'] as List<String>;
        expect(
          errors,
          isNotEmpty,
          reason:
              'Non-chronological timestamps should produce verification errors',
        );
      });
    });

    group('createEvent', () {
      test('includes signature', () {
        final entry = ProvenanceVerification.createEvent(
          'created',
          'alice@example.com',
          signerKey,
          merkleRoot,
          timestamp: DateTime.utc(2026, 1, 15, 12, 0, 0),
        );

        expect(
          entry.containsKey('signature'),
          isTrue,
          reason: 'Signed entry must contain signature',
        );
        final sigHex = entry['signature'] as String;
        expect(
          sigHex.length,
          equals(64),
          reason: 'HMAC-SHA256 should be 64 hex chars (32 bytes)',
        );
        expect(
          RegExp(r'^[0-9a-f]+$').hasMatch(sigHex),
          isTrue,
          reason: 'Signature should be lowercase hex',
        );
      });

      test('includes actor and action', () {
        final entry = ProvenanceVerification.createEvent(
          'transferred',
          'bob@example.com',
          signerKey,
          merkleRoot,
          timestamp: DateTime.utc(2026, 2, 1, 9, 0, 0),
        );

        expect(entry['actor'], equals('bob@example.com'));
        expect(entry['action'], equals('transferred'));
      });

      test('includes timestamp', () {
        final ts = DateTime.utc(2026, 6, 15, 14, 30, 0);
        final entry = ProvenanceVerification.createEvent(
          'verified',
          'carol@example.com',
          signerKey,
          merkleRoot,
          timestamp: ts,
        );

        expect(entry.containsKey('timestamp'), isTrue);
        final storedTs = entry['timestamp'] as int;
        expect(storedTs, equals(ts.millisecondsSinceEpoch ~/ 1000));
      });

      test('includes event_hash', () {
        final entry = ProvenanceVerification.createEvent(
          'sealed',
          'david@example.com',
          signerKey,
          merkleRoot,
          timestamp: DateTime.utc(2026, 3, 1),
        );

        expect(entry.containsKey('event_hash'), isTrue);
        final eventHash = entry['event_hash'] as String;
        expect(eventHash.length, equals(64));
      });

      test('includes optional details', () {
        final entry = ProvenanceVerification.createEvent(
          'reviewed',
          'eve@example.com',
          signerKey,
          merkleRoot,
          timestamp: DateTime.utc(2026, 4, 1),
          details: {'department': 'Legal', 'approval_level': 2},
        );

        expect(entry.containsKey('details'), isTrue);
        final details = entry['details'] as Map<String, dynamic>;
        expect(details['department'], equals('Legal'));
        expect(details['approval_level'], equals(2));
      });
    });

    group('signature verification via verifyChain', () {
      test('succeeds with correct key', () {
        final entries = _createChain(signerKey, merkleRoot, 3);

        // Verify each entry individually via verifyChain with single entry
        for (final entry in entries) {
          final result = ProvenanceVerification.verifyChain([entry], signerKey);
          expect(
            result['valid'],
            isTrue,
            reason: 'Entry signature should verify with correct key',
          );
        }
      });

      test('fails with wrong key', () {
        final wrongKey = _otherKey();
        final entries = _createChain(signerKey, merkleRoot, 3);

        // Verify each entry individually with the wrong key
        for (final entry in entries) {
          final result = ProvenanceVerification.verifyChain([entry], wrongKey);
          final errors = result['errors'] as List<String>;
          expect(
            errors,
            isNotEmpty,
            reason: 'Entry signature should fail with wrong key',
          );
        }
      });

      test('fails if entry is tampered', () {
        final entry = ProvenanceVerification.createEvent(
          'created',
          'alice@example.com',
          signerKey,
          merkleRoot,
          timestamp: DateTime.utc(2026, 5, 1),
        );

        // Tamper with the entry
        final tampered = Map<String, dynamic>.from(entry);
        tampered['action'] = 'deleted';

        final result = ProvenanceVerification.verifyChain([
          tampered,
        ], signerKey);
        final errors = result['errors'] as List<String>;
        expect(
          errors,
          isNotEmpty,
          reason: 'Tampered entry should fail signature verification',
        );
      });
    });

    group('chain verification', () {
      test('full chain verification succeeds', () {
        final entries = _createChain(signerKey, merkleRoot, 5);

        final result = ProvenanceVerification.verifyChain(entries, signerKey);
        expect(
          result['valid'],
          isTrue,
          reason: 'Valid chain should pass full verification',
        );
      });

      test('broken chain hash fails', () {
        final entries = _createChain(signerKey, merkleRoot, 5);

        // Tamper with the event_hash of entry 2
        entries[2]['event_hash'] = 'ff' * 32;

        final result = ProvenanceVerification.verifyChain(entries, signerKey);
        expect(
          result['valid'],
          isFalse,
          reason: 'Broken chain hash should fail verification',
        );
      });
    });

    group('edge cases', () {
      test('empty provenance chain is valid', () {
        final result = ProvenanceVerification.verifyChain(
          <Map<String, dynamic>>[],
          signerKey,
        );
        expect(
          result['valid'],
          isTrue,
          reason: 'Empty chain should be considered valid',
        );
      });

      test('single entry chain is valid', () {
        final entries = _createChain(signerKey, merkleRoot, 1);

        final result = ProvenanceVerification.verifyChain(entries, signerKey);
        expect(
          result['valid'],
          isTrue,
          reason: 'Single entry chain should be valid',
        );
      });

      test('chain with same-second timestamps is valid', () {
        final sameTime = DateTime.utc(2026, 7, 1, 12, 0, 0);
        final entry1 = ProvenanceVerification.createEvent(
          'created',
          'a@example.com',
          signerKey,
          merkleRoot,
          timestamp: sameTime,
        );
        final entry2 = ProvenanceVerification.createEvent(
          'witnessed',
          'b@example.com',
          signerKey,
          merkleRoot,
          timestamp: sameTime,
          previousEventHash: entry1['event_hash'] as String,
        );

        final result = ProvenanceVerification.verifyChain([
          entry1,
          entry2,
        ], signerKey);
        // Same-second timestamps should be acceptable (non-strictly ordered)
        expect(
          result['valid'],
          isTrue,
          reason: 'Same-second timestamps should be acceptable',
        );
      });
    });
  });
}
