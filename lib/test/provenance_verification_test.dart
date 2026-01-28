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

/// Creates a second distinct key.
Uint8List _otherKey() {
  final key = Uint8List(32);
  key[31] = 0x02;
  return key;
}

/// Creates a provenance chain of [count] entries using
/// ProvenanceVerification.createSignedEntry.
List<Map<String, dynamic>> _createChain(
  Uint8List signingKey,
  int count, {
  bool chronological = true,
}) {
  final entries = <Map<String, dynamic>>[];
  Uint8List? previousHash;

  for (var i = 0; i < count; i++) {
    final timestamp = chronological
        ? DateTime.utc(2026, 1, 1 + i, 10, 0, 0)
        : DateTime.utc(2026, 1, count - i, 10, 0, 0); // reverse order

    final entry = ProvenanceVerification.createSignedEntry(
      actor: 'user_$i@example.com',
      action: i == 0 ? 'created' : 'transferred',
      signingKey: signingKey,
      timestamp: timestamp,
      previousChainHash: previousHash,
      details: {'step': i, 'note': 'Step $i in chain'},
    );

    entries.add(entry);
    previousHash = _hexToBytes(entry['chain_hash'] as String);
  }

  return entries;
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
  group('ProvenanceVerification', () {
    late Uint8List signingKey;

    setUp(() {
      signingKey = _testKey();
    });

    group('chronological verification', () {
      test('succeeds for ordered entries', () {
        final entries = _createChain(signingKey, 5);

        final result = ProvenanceVerification.verifyChronological(entries);
        expect(result, isTrue,
            reason:
                'Chronologically ordered entries should pass verification');
      });

      test('fails for out-of-order timestamps', () {
        // Create entries with reverse timestamps
        final entries = _createChain(signingKey, 5, chronological: false);

        final result = ProvenanceVerification.verifyChronological(entries);
        expect(result, isFalse,
            reason:
                'Non-chronological timestamps should fail verification');
      });
    });

    group('createSignedEntry', () {
      test('includes HMAC', () {
        final entry = ProvenanceVerification.createSignedEntry(
          actor: 'alice@example.com',
          action: 'created',
          signingKey: signingKey,
          timestamp: DateTime.utc(2026, 1, 15, 12, 0, 0),
        );

        expect(entry.containsKey('hmac_hex'), isTrue,
            reason: 'Signed entry must contain HMAC');
        final hmacHex = entry['hmac_hex'] as String;
        expect(hmacHex.length, equals(64),
            reason: 'HMAC-SHA256 should be 64 hex chars (32 bytes)');
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(hmacHex), isTrue,
            reason: 'HMAC should be lowercase hex');
      });

      test('includes actor and action', () {
        final entry = ProvenanceVerification.createSignedEntry(
          actor: 'bob@example.com',
          action: 'transferred',
          signingKey: signingKey,
          timestamp: DateTime.utc(2026, 2, 1, 9, 0, 0),
        );

        expect(entry['actor'], equals('bob@example.com'));
        expect(entry['action'], equals('transferred'));
      });

      test('includes timestamp', () {
        final ts = DateTime.utc(2026, 6, 15, 14, 30, 0);
        final entry = ProvenanceVerification.createSignedEntry(
          actor: 'carol@example.com',
          action: 'verified',
          signingKey: signingKey,
          timestamp: ts,
        );

        expect(entry.containsKey('timestamp'), isTrue);
        final storedTs = entry['timestamp'] as int;
        expect(storedTs, equals(ts.millisecondsSinceEpoch ~/ 1000));
      });

      test('includes chain_hash', () {
        final entry = ProvenanceVerification.createSignedEntry(
          actor: 'david@example.com',
          action: 'sealed',
          signingKey: signingKey,
          timestamp: DateTime.utc(2026, 3, 1),
        );

        expect(entry.containsKey('chain_hash'), isTrue);
        final chainHash = entry['chain_hash'] as String;
        expect(chainHash.length, equals(64));
      });

      test('includes optional details', () {
        final entry = ProvenanceVerification.createSignedEntry(
          actor: 'eve@example.com',
          action: 'reviewed',
          signingKey: signingKey,
          timestamp: DateTime.utc(2026, 4, 1),
          details: {'department': 'Legal', 'approval_level': 2},
        );

        expect(entry.containsKey('details'), isTrue);
        final details = entry['details'] as Map<String, dynamic>;
        expect(details['department'], equals('Legal'));
        expect(details['approval_level'], equals(2));
      });
    });

    group('signed entry verification', () {
      test('succeeds with correct key', () {
        final entries = _createChain(signingKey, 3);

        for (final entry in entries) {
          final isValid = ProvenanceVerification.verifyEntryHmac(
            entry,
            signingKey,
          );
          expect(isValid, isTrue,
              reason: 'Entry HMAC should verify with correct key');
        }
      });

      test('fails with wrong key', () {
        final wrongKey = _otherKey();
        final entries = _createChain(signingKey, 3);

        for (final entry in entries) {
          final isValid = ProvenanceVerification.verifyEntryHmac(
            entry,
            wrongKey,
          );
          expect(isValid, isFalse,
              reason: 'Entry HMAC should fail with wrong key');
        }
      });

      test('fails if entry is tampered', () {
        final entry = ProvenanceVerification.createSignedEntry(
          actor: 'alice@example.com',
          action: 'created',
          signingKey: signingKey,
          timestamp: DateTime.utc(2026, 5, 1),
        );

        // Tamper with the entry
        final tampered = Map<String, dynamic>.from(entry);
        tampered['action'] = 'deleted';

        final isValid = ProvenanceVerification.verifyEntryHmac(
          tampered,
          signingKey,
        );
        expect(isValid, isFalse,
            reason: 'Tampered entry should fail HMAC verification');
      });
    });

    group('chain verification', () {
      test('full chain verification succeeds', () {
        final entries = _createChain(signingKey, 5);

        final result = ProvenanceVerification.verifyChain(
          entries,
          signingKey,
        );
        expect(result, isTrue,
            reason: 'Valid chain should pass full verification');
      });

      test('broken chain hash fails', () {
        final entries = _createChain(signingKey, 5);

        // Tamper with the chain_hash of entry 2
        entries[2]['chain_hash'] = 'ff' * 32;

        final result = ProvenanceVerification.verifyChain(
          entries,
          signingKey,
        );
        expect(result, isFalse,
            reason: 'Broken chain hash should fail verification');
      });
    });

    group('edge cases', () {
      test('empty provenance chain is valid', () {
        final result = ProvenanceVerification.verifyChronological(
          <Map<String, dynamic>>[],
        );
        expect(result, isTrue,
            reason: 'Empty chain should be considered valid');

        final chainResult = ProvenanceVerification.verifyChain(
          <Map<String, dynamic>>[],
          signingKey,
        );
        expect(chainResult, isTrue,
            reason: 'Empty chain should pass full verification');
      });

      test('single entry chain is valid', () {
        final entries = _createChain(signingKey, 1);

        final chronoResult =
            ProvenanceVerification.verifyChronological(entries);
        expect(chronoResult, isTrue,
            reason: 'Single entry is trivially chronological');

        final chainResult = ProvenanceVerification.verifyChain(
          entries,
          signingKey,
        );
        expect(chainResult, isTrue,
            reason: 'Single entry chain should be valid');
      });

      test('chain with same-second timestamps is valid', () {
        final sameTime = DateTime.utc(2026, 7, 1, 12, 0, 0);
        final entry1 = ProvenanceVerification.createSignedEntry(
          actor: 'a@example.com',
          action: 'created',
          signingKey: signingKey,
          timestamp: sameTime,
        );
        final entry2 = ProvenanceVerification.createSignedEntry(
          actor: 'b@example.com',
          action: 'witnessed',
          signingKey: signingKey,
          timestamp: sameTime,
          previousChainHash: _hexToBytes(entry1['chain_hash'] as String),
        );

        final result = ProvenanceVerification.verifyChronological(
          [entry1, entry2],
        );
        // Same-second timestamps should be acceptable (non-strictly ordered)
        expect(result, isTrue,
            reason: 'Same-second timestamps should be acceptable');
      });
    });
  });
}
