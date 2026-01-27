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

/// Creates a 32-byte recipient ID from a string identifier.
Uint8List _recipientId(String id) {
  return Uint8List.fromList(sha256.convert(utf8.encode(id)).bytes);
}

void main() {
  group('Canary trap', () {
    late Uint8List masterKey;
    late Uint8List content;
    late Uint8List recipientA;
    late Uint8List recipientB;

    setUp(() {
      masterKey = _testKey();
      content = Uint8List.fromList(utf8.encode('Confidential document content'));
      recipientA = _recipientId('user:1:alice@example.com');
      recipientB = _recipientId('user:2:bob@example.com');
    });

    group('padding generation', () {
      test('generates different padding for recipient A and B', () {
        final paddingA =
            CanaryTrap.generatePadding(masterKey, recipientA, 0);
        final paddingB =
            CanaryTrap.generatePadding(masterKey, recipientB, 0);

        expect(paddingA, isNot(equals(paddingB)),
            reason:
                'Different recipients should produce different padding');
      });

      test('padding length is always 1-16 bytes', () {
        // Test with multiple block indices and recipients
        for (var blockIndex = 0; blockIndex < 20; blockIndex++) {
          final paddingA = CanaryTrap.generatePadding(
              masterKey, recipientA, blockIndex);
          final paddingB = CanaryTrap.generatePadding(
              masterKey, recipientB, blockIndex);

          expect(paddingA.length, greaterThanOrEqualTo(1),
              reason:
                  'Padding for A at block $blockIndex should be >= 1 byte');
          expect(paddingA.length, lessThanOrEqualTo(16),
              reason:
                  'Padding for A at block $blockIndex should be <= 16 bytes');
          expect(paddingB.length, greaterThanOrEqualTo(1),
              reason:
                  'Padding for B at block $blockIndex should be >= 1 byte');
          expect(paddingB.length, lessThanOrEqualTo(16),
              reason:
                  'Padding for B at block $blockIndex should be <= 16 bytes');
        }
      });

      test('padding is deterministic for same inputs', () {
        final padding1 =
            CanaryTrap.generatePadding(masterKey, recipientA, 0);
        final padding2 =
            CanaryTrap.generatePadding(masterKey, recipientA, 0);

        expect(padding1, equals(padding2));
      });

      test('padding differs across block indices for same recipient', () {
        final padding0 =
            CanaryTrap.generatePadding(masterKey, recipientA, 0);
        final padding1 =
            CanaryTrap.generatePadding(masterKey, recipientA, 1);

        // While they could theoretically be the same by coincidence,
        // it is extremely unlikely with HMAC-SHA256
        expect(padding0, isNot(equals(padding1)),
            reason: 'Different block indices should produce different padding');
      });

      test('last byte of padding equals padding length (PKCS#7 style)', () {
        for (var blockIndex = 0; blockIndex < 10; blockIndex++) {
          final padding = CanaryTrap.generatePadding(
              masterKey, recipientA, blockIndex);
          expect(padding.last, equals(padding.length),
              reason:
                  'Last byte should equal padding length at block $blockIndex');
        }
      });
    });

    group('seal with canary', () {
      test('same content for different recipients produces same Merkle root', () {
        final optionsA = ZegelOptions(
          contentType: 'text/plain',
          filename: 'doc.txt',
          salt: _zeroSalt(),
          recipientId: recipientA,
        );
        final optionsB = ZegelOptions(
          contentType: 'text/plain',
          filename: 'doc.txt',
          salt: _zeroSalt(),
          recipientId: recipientB,
        );

        final fileA = ZegelWriter.seal(content, masterKey, options: optionsA);
        final fileB = ZegelWriter.seal(content, masterKey, options: optionsB);

        // Merkle roots should be the same because padding is applied
        // BEFORE hashing (the plaintext hash includes padding)
        // Actually, per spec: padding is appended before encryption,
        // and the plaintext hash is of the padded content.
        // So different recipients will have different plaintext hashes
        // and therefore different Merkle roots.
        //
        // Wait - re-reading the spec more carefully:
        // The spec says the Merkle root should be the same for the SAME content.
        // But canary padding changes the plaintext per-recipient.
        //
        // Let me re-check: "Same content for different recipients produces
        // same Merkle root" from test spec. This implies the Merkle root
        // is computed from the original content BEFORE padding.
        //
        // This is a design choice test. The test requirement says:
        // "Same content for different recipients produces same Merkle root"
        final inspectionA = ZegelReader.inspect(fileA);
        final inspectionB = ZegelReader.inspect(fileB);

        expect(inspectionA.merkleRoot, equals(inspectionB.merkleRoot),
            reason:
                'Same content should produce same Merkle root regardless of recipient');
      });

      test('different ciphertexts for different recipients', () {
        final optionsA = ZegelOptions(
          contentType: 'text/plain',
          filename: 'doc.txt',
          salt: _zeroSalt(),
          recipientId: recipientA,
        );
        final optionsB = ZegelOptions(
          contentType: 'text/plain',
          filename: 'doc.txt',
          salt: _zeroSalt(),
          recipientId: recipientB,
        );

        final fileA = ZegelWriter.seal(content, masterKey, options: optionsA);
        final fileB = ZegelWriter.seal(content, masterKey, options: optionsB);

        // The encrypted block data should differ due to different canary padding
        // (Even with same IV, which won't happen in practice since IVs are random)
        // Files should differ somewhere in the encrypted data region
        expect(fileA, isNot(equals(fileB)),
            reason: 'Files for different recipients should differ');
      });

      test('canary flag is set in output file', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'doc.txt',
          salt: _zeroSalt(),
          recipientId: recipientA,
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        final inspection = ZegelReader.inspect(fileBytes);
        expect(
          inspection.flags & ZegelFormat.flagHasCanary,
          isNonZero,
          reason: 'HAS_CANARY flag should be set',
        );
      });
    });

    group('recipient identification', () {
      test('identifyRecipient correctly identifies recipient A', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'doc.txt',
          salt: _zeroSalt(),
          recipientId: recipientA,
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        final identified = CanaryTrap.identifyRecipient(
          fileBytes,
          masterKey,
          [recipientA, recipientB],
        );

        expect(identified, equals(recipientA),
            reason: 'Should identify recipient A');
      });

      test('identifyRecipient correctly identifies recipient B', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'doc.txt',
          salt: _zeroSalt(),
          recipientId: recipientB,
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        final identified = CanaryTrap.identifyRecipient(
          fileBytes,
          masterKey,
          [recipientA, recipientB],
        );

        expect(identified, equals(recipientB),
            reason: 'Should identify recipient B');
      });

      test('identifyRecipient returns null for unknown recipient', () {
        final unknownRecipient = _recipientId('user:3:charlie@example.com');
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'doc.txt',
          salt: _zeroSalt(),
          recipientId: unknownRecipient,
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        final identified = CanaryTrap.identifyRecipient(
          fileBytes,
          masterKey,
          [recipientA, recipientB], // charlie not in candidates
        );

        expect(identified, isNull,
            reason: 'Should return null for unknown recipient');
      });

      test('identifyRecipient works with many candidates', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'doc.txt',
          salt: _zeroSalt(),
          recipientId: recipientA,
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        // Create 100 candidate IDs with recipient A somewhere in the list
        final candidates = List.generate(
          100,
          (i) => _recipientId('user:$i:test$i@example.com'),
        );
        candidates[42] = recipientA; // Put the real recipient at position 42

        final identified = CanaryTrap.identifyRecipient(
          fileBytes,
          masterKey,
          candidates,
        );

        expect(identified, equals(recipientA));
      });
    });

    group('strip padding', () {
      test('strip padding recovers original content', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'doc.txt',
          salt: _zeroSalt(),
          recipientId: recipientA,
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        final result = ZegelReader.extract(fileBytes, masterKey);
        expect(result.valid, isTrue);
        // After extraction, canary padding should be stripped
        expect(result.content, equals(content));
      });

      test('strip padding works for recipient B', () {
        final options = ZegelOptions(
          contentType: 'text/plain',
          filename: 'doc.txt',
          salt: _zeroSalt(),
          recipientId: recipientB,
        );
        final fileBytes =
            ZegelWriter.seal(content, masterKey, options: options);

        final result = ZegelReader.extract(fileBytes, masterKey);
        expect(result.valid, isTrue);
        expect(result.content, equals(content));
      });

      test('strip padding works across multiple blocks', () {
        // Multi-block content
        final largeContent = Uint8List(65536 + 100);
        for (var i = 0; i < largeContent.length; i++) {
          largeContent[i] = i & 0xFF;
        }

        final options = ZegelOptions(
          contentType: 'application/octet-stream',
          filename: 'large.bin',
          salt: _zeroSalt(),
          recipientId: recipientA,
        );
        final fileBytes =
            ZegelWriter.seal(largeContent, masterKey, options: options);

        final result = ZegelReader.extract(fileBytes, masterKey);
        expect(result.valid, isTrue);
        expect(result.content, equals(largeContent));
      });
    });

    group('padding algorithm correctness', () {
      test('padding matches HMAC-SHA256 based generation', () {
        // Verify against the spec algorithm:
        // mac = HMAC-SHA256(master_key, recipient_id || pack_uint32_be(block_index))
        // pad_len = (mac[0] % 16) + 1
        // padding = mac[1..pad_len-1] || byte(pad_len)
        final blockIndex = 0;
        final message = Uint8List(recipientA.length + 4);
        message.setAll(0, recipientA);
        ByteData.sublistView(message, recipientA.length, recipientA.length + 4)
            .setUint32(0, blockIndex, Endian.big);

        final mac = Hmac(sha256, masterKey).convert(message);
        final macBytes = mac.bytes;
        final padLen = (macBytes[0] % 16) + 1;

        final expectedPadding = Uint8List(padLen);
        for (var i = 0; i < padLen - 1; i++) {
          expectedPadding[i] = macBytes[i + 1];
        }
        expectedPadding[padLen - 1] = padLen;

        final actualPadding =
            CanaryTrap.generatePadding(masterKey, recipientA, blockIndex);
        expect(actualPadding, equals(expectedPadding));
      });
    });
  });
}
