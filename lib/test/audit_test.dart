import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

/// Helper to compute SHA-256 of bytes.
Uint8List _sha256(Uint8List data) {
  return Uint8List.fromList(sha256.convert(data).bytes);
}

/// Helper to concatenate two Uint8Lists.
Uint8List _concat(Uint8List a, Uint8List b) {
  final result = Uint8List(a.length + b.length);
  result.setAll(0, a);
  result.setAll(a.length, b);
  return result;
}

/// Helper to convert bytes to hex string.
String _toHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

void main() {
  group('Audit trail', () {
    group('single entry', () {
      test('create single audit entry with zero initial chain hash', () {
        final initialChainHash = Uint8List(32); // 32 zero bytes
        final entry = ZegelAudit.createEntry(
          actor: 'user:1:admin@example.com',
          action: 'sealed',
          timestamp: 1706367600,
          details: {'filename': 'doc.pdf'},
          previousChainHash: initialChainHash,
        );

        expect(entry, isNotNull);
        expect(entry.actor, equals('user:1:admin@example.com'));
        expect(entry.action, equals('sealed'));
        expect(entry.timestamp, equals(1706367600));
        expect(entry.chainHash, isNotNull);
        expect(entry.chainHash.length, equals(32));
      });

      test('chain hash = SHA-256(zeros_32 || entry_json) for first entry', () {
        final initialChainHash = Uint8List(32);
        final entry = ZegelAudit.createEntry(
          actor: 'user:1:admin@example.com',
          action: 'sealed',
          timestamp: 1706367600,
          details: {},
          previousChainHash: initialChainHash,
        );

        // Reconstruct the expected chain hash
        final entryJson = entry.toJson();
        // Remove chain_hash from JSON to compute it (the chain_hash
        // in the JSON should match what we compute)
        final entryJsonForHash = Map<String, dynamic>.from(entryJson);
        entryJsonForHash.remove('chain_hash');
        final entryJsonStr = jsonEncode(entryJsonForHash);
        final entryJsonBytes = Uint8List.fromList(utf8.encode(entryJsonStr));

        final expectedHash = _sha256(_concat(initialChainHash, entryJsonBytes));
        expect(entry.chainHash, equals(expectedHash));
      });
    });

    group('chain of entries', () {
      test('create chain of 3 entries and verify chain', () {
        final initialChainHash = Uint8List(32);

        final entry0 = ZegelAudit.createEntry(
          actor: 'user:1:admin@example.com',
          action: 'sealed',
          timestamp: 1706367600,
          details: {},
          previousChainHash: initialChainHash,
        );

        final entry1 = ZegelAudit.createEntry(
          actor: 'user:2:auditor@example.com',
          action: 'verified',
          timestamp: 1706368000,
          details: {'result': 'valid'},
          previousChainHash: entry0.chainHash,
        );

        final entry2 = ZegelAudit.createEntry(
          actor: 'user:1:admin@example.com',
          action: 'redacted',
          timestamp: 1706368400,
          details: {'blocks': [1]},
          previousChainHash: entry1.chainHash,
        );

        // Verify the chain
        final isValid = ZegelAudit.verifyChain([entry0, entry1, entry2]);
        expect(isValid, isTrue,
            reason: 'Valid chain of 3 entries should verify');
      });

      test('chain hash ordering is correct', () {
        final initialChainHash = Uint8List(32);

        final entry0 = ZegelAudit.createEntry(
          actor: 'actor0',
          action: 'sealed',
          timestamp: 1000,
          details: {},
          previousChainHash: initialChainHash,
        );

        final entry1 = ZegelAudit.createEntry(
          actor: 'actor1',
          action: 'verified',
          timestamp: 2000,
          details: {},
          previousChainHash: entry0.chainHash,
        );

        // entry1's chain hash should incorporate entry0's chain hash
        // chain_hash[1] = SHA-256(chain_hash[0] || entry_1_json)
        final entry1JsonForHash = Map<String, dynamic>.from(entry1.toJson());
        entry1JsonForHash.remove('chain_hash');
        final entry1JsonStr = jsonEncode(entry1JsonForHash);
        final entry1JsonBytes =
            Uint8List.fromList(utf8.encode(entry1JsonStr));

        final expectedHash1 =
            _sha256(_concat(entry0.chainHash, entry1JsonBytes));
        expect(entry1.chainHash, equals(expectedHash1));
      });
    });

    group('tamper detection', () {
      test('tamper with entry in middle of chain -> verification fails', () {
        final initialChainHash = Uint8List(32);

        final entry0 = ZegelAudit.createEntry(
          actor: 'admin',
          action: 'sealed',
          timestamp: 1000,
          details: {},
          previousChainHash: initialChainHash,
        );

        final entry1 = ZegelAudit.createEntry(
          actor: 'auditor',
          action: 'verified',
          timestamp: 2000,
          details: {'result': 'valid'},
          previousChainHash: entry0.chainHash,
        );

        final entry2 = ZegelAudit.createEntry(
          actor: 'admin',
          action: 'redacted',
          timestamp: 3000,
          details: {'blocks': [1]},
          previousChainHash: entry1.chainHash,
        );

        // Tamper with entry1: create a fake entry with different action
        final tamperedEntry1 = ZegelAudit.createEntry(
          actor: 'auditor',
          action: 'disclosed', // changed from 'verified'
          timestamp: 2000,
          details: {'result': 'valid'},
          previousChainHash: entry0.chainHash,
        );

        // The tampered chain should fail because entry2's chain hash
        // was computed from the original entry1, not the tampered one
        final isValid = ZegelAudit.verifyChain(
            [entry0, tamperedEntry1, entry2]);
        expect(isValid, isFalse,
            reason:
                'Tampered entry in middle of chain should break verification');
      });

      test('tamper with first entry -> chain verification fails', () {
        final initialChainHash = Uint8List(32);

        final entry0 = ZegelAudit.createEntry(
          actor: 'admin',
          action: 'sealed',
          timestamp: 1000,
          details: {},
          previousChainHash: initialChainHash,
        );

        final entry1 = ZegelAudit.createEntry(
          actor: 'auditor',
          action: 'verified',
          timestamp: 2000,
          details: {},
          previousChainHash: entry0.chainHash,
        );

        // Create a tampered first entry
        final tamperedEntry0 = ZegelAudit.createEntry(
          actor: 'attacker',
          action: 'sealed',
          timestamp: 1000,
          details: {},
          previousChainHash: initialChainHash,
        );

        final isValid =
            ZegelAudit.verifyChain([tamperedEntry0, entry1]);
        expect(isValid, isFalse,
            reason: 'Tampered first entry should break chain');
      });

      test('reordering entries -> chain verification fails', () {
        final initialChainHash = Uint8List(32);

        final entry0 = ZegelAudit.createEntry(
          actor: 'admin',
          action: 'sealed',
          timestamp: 1000,
          details: {},
          previousChainHash: initialChainHash,
        );

        final entry1 = ZegelAudit.createEntry(
          actor: 'auditor',
          action: 'verified',
          timestamp: 2000,
          details: {},
          previousChainHash: entry0.chainHash,
        );

        // Swap entries
        final isValid = ZegelAudit.verifyChain([entry1, entry0]);
        expect(isValid, isFalse,
            reason: 'Reordered chain should fail verification');
      });
    });

    group('action types', () {
      test('sealed action', () {
        final entry = ZegelAudit.createEntry(
          actor: 'user:1:admin@example.com',
          action: 'sealed',
          timestamp: 1706367600,
          details: {'filename': 'report.pdf'},
          previousChainHash: Uint8List(32),
        );
        expect(entry.action, equals('sealed'));
      });

      test('verified action', () {
        final entry = ZegelAudit.createEntry(
          actor: 'user:2:auditor@example.com',
          action: 'verified',
          timestamp: 1706367600,
          details: {'result': 'valid'},
          previousChainHash: Uint8List(32),
        );
        expect(entry.action, equals('verified'));
      });

      test('redacted action', () {
        final entry = ZegelAudit.createEntry(
          actor: 'user:1:admin@example.com',
          action: 'redacted',
          timestamp: 1706367600,
          details: {'blocks': [1, 3]},
          previousChainHash: Uint8List(32),
        );
        expect(entry.action, equals('redacted'));
      });

      test('attested action', () {
        final entry = ZegelAudit.createEntry(
          actor: 'user:3:reviewer@example.com',
          action: 'attested',
          timestamp: 1706367600,
          details: {'statement': 'Reviewed and approved'},
          previousChainHash: Uint8List(32),
        );
        expect(entry.action, equals('attested'));
      });

      test('disclosed action', () {
        final entry = ZegelAudit.createEntry(
          actor: 'user:1:admin@example.com',
          action: 'disclosed',
          timestamp: 1706367600,
          details: {'blocks': [0, 2], 'recipient': 'external-auditor'},
          previousChainHash: Uint8List(32),
        );
        expect(entry.action, equals('disclosed'));
      });
    });

    group('entry JSON serialization', () {
      test('entry serializes to JSON with all required fields', () {
        final entry = ZegelAudit.createEntry(
          actor: 'admin',
          action: 'sealed',
          timestamp: 1706367600,
          details: {'key': 'value'},
          previousChainHash: Uint8List(32),
        );

        final json = entry.toJson();
        expect(json.containsKey('actor'), isTrue);
        expect(json.containsKey('action'), isTrue);
        expect(json.containsKey('timestamp'), isTrue);
        expect(json.containsKey('details'), isTrue);
        expect(json.containsKey('chain_hash'), isTrue);

        expect(json['actor'], equals('admin'));
        expect(json['action'], equals('sealed'));
        expect(json['timestamp'], equals(1706367600));
        expect(json['details'], equals({'key': 'value'}));
        expect(json['chain_hash'], isA<String>());
        expect((json['chain_hash'] as String).length, equals(64));
      });

      test('chain_hash in JSON is hex-encoded', () {
        final entry = ZegelAudit.createEntry(
          actor: 'admin',
          action: 'sealed',
          timestamp: 1706367600,
          details: {},
          previousChainHash: Uint8List(32),
        );

        final json = entry.toJson();
        final chainHashHex = json['chain_hash'] as String;
        expect(chainHashHex.length, equals(64));
        expect(RegExp(r'^[0-9a-f]+$').hasMatch(chainHashHex), isTrue,
            reason: 'chain_hash should be lowercase hex');
        expect(chainHashHex, equals(_toHex(entry.chainHash)));
      });
    });

    group('single entry chain', () {
      test('single entry verifies', () {
        final entry = ZegelAudit.createEntry(
          actor: 'admin',
          action: 'sealed',
          timestamp: 1000,
          details: {},
          previousChainHash: Uint8List(32),
        );

        final isValid = ZegelAudit.verifyChain([entry]);
        expect(isValid, isTrue);
      });
    });

    group('empty chain', () {
      test('empty chain is trivially valid', () {
        final isValid = ZegelAudit.verifyChain([]);
        expect(isValid, isTrue,
            reason: 'Empty chain has nothing to verify');
      });
    });

    group('long chains', () {
      test('chain of 10 entries verifies correctly', () {
        var previousHash = Uint8List(32);
        final entries = <AuditEntry>[];

        final actions = [
          'sealed',
          'verified',
          'attested',
          'verified',
          'redacted',
          'verified',
          'disclosed',
          'verified',
          'attested',
          'verified',
        ];

        for (var i = 0; i < 10; i++) {
          final entry = ZegelAudit.createEntry(
            actor: 'user:${i % 3}:actor${i % 3}@example.com',
            action: actions[i],
            timestamp: 1706367600 + i * 3600,
            details: {'step': i},
            previousChainHash: previousHash,
          );
          entries.add(entry);
          previousHash = entry.chainHash;
        }

        final isValid = ZegelAudit.verifyChain(entries);
        expect(isValid, isTrue,
            reason: 'Valid chain of 10 entries should verify');
      });
    });
  });
}
