import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('ZegelFormat', () {
    group('magic bytes', () {
      test('magic bytes are exactly ZEGEL\\x00\\x01\\x00', () {
        final expected = Uint8List.fromList([
          0x5A, 0x45, 0x47, 0x45, 0x4C, // ZEGEL
          0x00, 0x01, 0x00, // null, 1, null
        ]);
        expect(ZegelFormat.magicBytes, equals(expected));
      });

      test('magic bytes length is 8', () {
        expect(ZegelFormat.magicBytes.length, equals(8));
      });

      test('magic bytes start with ASCII "ZEGEL"', () {
        final magic = ZegelFormat.magicBytes;
        expect(String.fromCharCodes(magic.sublist(0, 5)), equals('ZEGEL'));
      });
    });

    group('version', () {
      test('version major is 1', () {
        expect(ZegelFormat.versionMajor, equals(1));
      });

      test('version minor is 2', () {
        expect(ZegelFormat.versionMinor, equals(2));
      });
    });

    group('flags', () {
      test('HAS_METADATA is 0x0001', () {
        expect(ZegelFormat.flagHasMetadata, equals(0x0001));
      });

      test('COMPRESSED is 0x0002', () {
        expect(ZegelFormat.flagCompressed, equals(0x0002));
      });

      test('PASSWORD_DERIVED is 0x0004', () {
        expect(ZegelFormat.flagPasswordDerived, equals(0x0004));
      });

      test('HAS_KEY_COMMITMENT is 0x0008', () {
        expect(ZegelFormat.flagHasKeyCommitment, equals(0x0008));
      });

      test('HAS_EXPIRATION is 0x0010', () {
        expect(ZegelFormat.flagHasExpiration, equals(0x0010));
      });

      test('HAS_PUBLIC_METADATA is 0x0020', () {
        expect(ZegelFormat.flagHasPublicMetadata, equals(0x0020));
      });

      test('MULTI_FILE is 0x0040', () {
        expect(ZegelFormat.flagMultiFile, equals(0x0040));
      });

      test('HAS_CANARY is 0x0080', () {
        expect(ZegelFormat.flagHasCanary, equals(0x0080));
      });

      test('HAS_REDACTIONS is 0x0100', () {
        expect(ZegelFormat.flagHasRedactions, equals(0x0100));
      });

      test('SPLIT_KEY is 0x0200', () {
        expect(ZegelFormat.flagSplitKey, equals(0x0200));
      });

      test('SELECTIVE_DISCLOSURE is 0x0400', () {
        expect(ZegelFormat.flagSelectiveDisclosure, equals(0x0400));
      });

      test('VERSIONED is 0x0800', () {
        expect(ZegelFormat.flagVersioned, equals(0x0800));
      });

      test('all flags are non-overlapping powers of 2', () {
        final flags = [
          ZegelFormat.flagHasMetadata,
          ZegelFormat.flagCompressed,
          ZegelFormat.flagPasswordDerived,
          ZegelFormat.flagHasKeyCommitment,
          ZegelFormat.flagHasExpiration,
          ZegelFormat.flagHasPublicMetadata,
          ZegelFormat.flagMultiFile,
          ZegelFormat.flagHasCanary,
          ZegelFormat.flagHasRedactions,
          ZegelFormat.flagSplitKey,
          ZegelFormat.flagSelectiveDisclosure,
          ZegelFormat.flagVersioned,
        ];

        // Each flag should be a power of 2
        for (final flag in flags) {
          expect(flag & (flag - 1), equals(0),
              reason: '0x${flag.toRadixString(16)} is not a power of 2');
          expect(flag, greaterThan(0));
        }

        // No two flags should share any bits (OR of all == sum of all)
        var orResult = 0;
        var sum = 0;
        for (final flag in flags) {
          orResult |= flag;
          sum += flag;
        }
        expect(orResult, equals(sum),
            reason: 'Flags overlap - some bits are shared');
      });

      test('all flags fit within uint16', () {
        final allFlags = ZegelFormat.flagHasMetadata |
            ZegelFormat.flagCompressed |
            ZegelFormat.flagPasswordDerived |
            ZegelFormat.flagHasKeyCommitment |
            ZegelFormat.flagHasExpiration |
            ZegelFormat.flagHasPublicMetadata |
            ZegelFormat.flagMultiFile |
            ZegelFormat.flagHasCanary |
            ZegelFormat.flagHasRedactions |
            ZegelFormat.flagSplitKey |
            ZegelFormat.flagSelectiveDisclosure |
            ZegelFormat.flagVersioned;
        expect(allFlags, lessThanOrEqualTo(0xFFFF));
      });
    });

    group('block types', () {
      test('CONTENT is 0x01', () {
        expect(ZegelFormat.blockTypeContent, equals(0x01));
      });

      test('METADATA is 0x02', () {
        expect(ZegelFormat.blockTypeMetadata, equals(0x02));
      });

      test('PUBLIC_METADATA is 0x03', () {
        expect(ZegelFormat.blockTypePublicMetadata, equals(0x03));
      });

      test('FILE_HEADER is 0x04', () {
        expect(ZegelFormat.blockTypeFileHeader, equals(0x04));
      });

      test('PROVENANCE is 0x05', () {
        expect(ZegelFormat.blockTypeProvenance, equals(0x05));
      });

      test('REDACTED is 0x06', () {
        expect(ZegelFormat.blockTypeRedacted, equals(0x06));
      });

      test('ATTESTATION is 0x07', () {
        expect(ZegelFormat.blockTypeAttestation, equals(0x07));
      });

      test('REFERENCE is 0x08', () {
        expect(ZegelFormat.blockTypeReference, equals(0x08));
      });

      test('AUDIT is 0x09', () {
        expect(ZegelFormat.blockTypeAudit, equals(0x09));
      });

      test('DISCLOSURE_INDEX is 0x0A', () {
        expect(ZegelFormat.blockTypeDisclosureIndex, equals(0x0A));
      });

      test('block types are sequential from 0x01 to 0x0A', () {
        final types = [
          ZegelFormat.blockTypeContent,
          ZegelFormat.blockTypeMetadata,
          ZegelFormat.blockTypePublicMetadata,
          ZegelFormat.blockTypeFileHeader,
          ZegelFormat.blockTypeProvenance,
          ZegelFormat.blockTypeRedacted,
          ZegelFormat.blockTypeAttestation,
          ZegelFormat.blockTypeReference,
          ZegelFormat.blockTypeAudit,
          ZegelFormat.blockTypeDisclosureIndex,
        ];

        for (var i = 0; i < types.length; i++) {
          expect(types[i], equals(i + 1),
              reason: 'Block type at index $i should be ${i + 1}');
        }
      });

      test('all block types are unique', () {
        final types = {
          ZegelFormat.blockTypeContent,
          ZegelFormat.blockTypeMetadata,
          ZegelFormat.blockTypePublicMetadata,
          ZegelFormat.blockTypeFileHeader,
          ZegelFormat.blockTypeProvenance,
          ZegelFormat.blockTypeRedacted,
          ZegelFormat.blockTypeAttestation,
          ZegelFormat.blockTypeReference,
          ZegelFormat.blockTypeAudit,
          ZegelFormat.blockTypeDisclosureIndex,
        };
        expect(types.length, equals(10));
      });
    });

    group('size constants', () {
      test('hash size is 32 bytes (SHA-256)', () {
        expect(ZegelFormat.hashSize, equals(32));
      });

      test('IV size is 12 bytes (AES-GCM nonce)', () {
        expect(ZegelFormat.ivSize, equals(12));
      });

      test('tag size is 16 bytes (AES-GCM auth tag)', () {
        expect(ZegelFormat.tagSize, equals(16));
      });

      test('seal size is 64 bytes (HMAC-SHA512)', () {
        expect(ZegelFormat.sealSize, equals(64));
      });

      test('directory entry size is 65 bytes', () {
        // 1 (type) + 32 (hash) + 4 (ciphertext len) + 12 (IV) + 16 (tag) = 65
        expect(ZegelFormat.directoryEntrySize, equals(65));
      });

      test('salt size is 32 bytes', () {
        expect(ZegelFormat.saltSize, equals(32));
      });

      test('default block size is 65536 bytes (64 KB)', () {
        expect(ZegelFormat.defaultBlockSize, equals(65536));
      });

      test('content type field size is 64 bytes', () {
        expect(ZegelFormat.contentTypeSize, equals(64));
      });

      test('max filename length is 255 bytes', () {
        expect(ZegelFormat.maxFilenameLength, equals(255));
      });

      test('magic bytes size is 8', () {
        expect(ZegelFormat.magicSize, equals(8));
      });

      test('key size is 32 bytes (AES-256)', () {
        expect(ZegelFormat.keySize, equals(32));
      });
    });

    group('HKDF info prefix', () {
      test('HKDF info prefix is correct', () {
        expect(ZegelFormat.hkdfInfoPrefix, equals('zegel-block-key-v1:'));
      });
    });
  });
}
