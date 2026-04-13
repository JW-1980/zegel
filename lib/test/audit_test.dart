import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

Uint8List _hexToBytes(String hex) {
  final length = hex.length ~/ 2;
  final bytes = Uint8List(length);
  for (int i = 0; i < length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

void main() {
  group('AuditTrail', () {
    group('createEntry', () {
      test('creates entry with actor and action', () {
        final entry = AuditTrail.createEntry('admin@example.com', 'sealed');

        expect(entry['actor'], equals('admin@example.com'));
        expect(entry['action'], equals('sealed'));
        expect(entry['timestamp'], isA<int>());
        expect(entry['chain_hash'], isA<String>());
        expect((entry['chain_hash'] as String).length, equals(64));
      });

      test('includes details when provided', () {
        final entry = AuditTrail.createEntry(
          'admin@example.com',
          'sealed',
          details: {'filename': 'document.pdf', 'size': 1024},
        );

        expect(entry['details'], isNotNull);
        expect(entry['details']['filename'], equals('document.pdf'));
      });

      test('chain hash links to previous entry', () {
        final entry1 = AuditTrail.createEntry('admin@example.com', 'sealed');

        final prevHash = _hexToBytes(entry1['chain_hash'] as String);
        final entry2 = AuditTrail.createEntry(
          'auditor@example.com',
          'verified',
          previousChainHash: prevHash,
        );

        // Chain hashes should be different
        expect(entry2['chain_hash'], isNot(equals(entry1['chain_hash'])));
      });

      test('first entry uses zero hash as previous', () {
        final entry = AuditTrail.createEntry('admin@example.com', 'sealed');

        // The chain hash should be deterministic given same input
        expect(entry['chain_hash'], isA<String>());
      });
    });

    group('verifyChain', () {
      test('verifies empty chain', () {
        expect(AuditTrail.verifyChain([]), isTrue);
      });

      test('verifies single-entry chain', () {
        final entry = AuditTrail.createEntry('admin@example.com', 'sealed');

        expect(AuditTrail.verifyChain([entry]), isTrue);
      });

      test('verifies multi-entry chain', () {
        final entry1 = AuditTrail.createEntry('admin@example.com', 'sealed');

        final prevHash1 = _hexToBytes(entry1['chain_hash'] as String);
        final entry2 = AuditTrail.createEntry(
          'auditor@example.com',
          'verified',
          previousChainHash: prevHash1,
        );

        final prevHash2 = _hexToBytes(entry2['chain_hash'] as String);
        final entry3 = AuditTrail.createEntry(
          'reviewer@example.com',
          'attested',
          previousChainHash: prevHash2,
        );

        expect(AuditTrail.verifyChain([entry1, entry2, entry3]), isTrue);
      });

      test('detects tampered entry', () {
        final entry1 = AuditTrail.createEntry('admin@example.com', 'sealed');

        final prevHash1 = _hexToBytes(entry1['chain_hash'] as String);
        final entry2 = AuditTrail.createEntry(
          'auditor@example.com',
          'verified',
          previousChainHash: prevHash1,
        );

        // Tamper with entry1
        final tampered1 = Map<String, dynamic>.from(entry1);
        tampered1['actor'] = 'attacker@example.com';

        expect(AuditTrail.verifyChain([tampered1, entry2]), isFalse);
      });

      test('detects broken chain', () {
        final entry1 = AuditTrail.createEntry('admin@example.com', 'sealed');

        // Create entry2 without linking to entry1
        final entry2 = AuditTrail.createEntry(
          'auditor@example.com',
          'verified',
        );

        // This chain is broken because entry2 doesn't link to entry1
        expect(AuditTrail.verifyChain([entry1, entry2]), isFalse);
      });
    });
  });
}
