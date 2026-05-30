import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

Uint8List _testKey() {
  final key = Uint8List(32);
  key[31] = 0x01;
  return key;
}

Uint8List _zeroSalt() => Uint8List(32);

CreatorIdentity _testCreator() {
  return const CreatorIdentity(
    firstName: 'Alice',
    familyName: 'Nakamoto',
    middleName: 'B',
    dateOfBirth: '1990-01-15',
    address: '123 Crypto Lane',
    zipCode: '1011AB',
    city: 'Amsterdam',
    stateProvince: 'Noord-Holland',
    country: 'NL',
    companyName: 'Creative Works BV',
    companyRegistrationNumber: 'KVK-12345678',
    email: 'alice@example.com',
    phone: '+31612345678',
    website: 'https://alice.example.com',
    professionalTitle: 'Composer',
  );
}

void main() {
  group('CreatorIdentity', () {
    test('toJson/fromJson roundtrip', () {
      final creator = _testCreator();
      final json = creator.toJson();
      final restored = CreatorIdentity.fromJson(json);

      expect(restored.firstName, equals('Alice'));
      expect(restored.familyName, equals('Nakamoto'));
      expect(restored.middleName, equals('B'));
      expect(restored.city, equals('Amsterdam'));
      expect(restored.companyName, equals('Creative Works BV'));
      expect(restored.displayName, equals('Alice B Nakamoto'));
    });

    test('fingerprint is deterministic', () {
      final creator = _testCreator();
      final fp1 = creator.fingerprint;
      final fp2 = creator.fingerprint;
      expect(fp1, equals(fp2));
      expect(fp1.length, equals(16));
    });

    test('displayName without middle name', () {
      const creator = CreatorIdentity(
        firstName: 'Bob',
        familyName: 'Jones',
      );
      expect(creator.displayName, equals('Bob Jones'));
    });
  });

  group('IdDocument', () {
    test('toJson/fromJson roundtrip', () {
      final doc = IdDocument(
        type: IdDocumentType.passport,
        scanBytes: Uint8List.fromList(utf8.encode('fake-scan-data')),
        scanMimeType: 'image/jpeg',
        documentNumber: 'AB1234567',
        issuingCountry: 'NL',
        expiryDate: '2030-12-31',
        holderName: 'Alice Nakamoto',
      );

      final json = doc.toJson();
      final restored = IdDocument.fromJson(json);

      expect(restored.type, equals(IdDocumentType.passport));
      expect(restored.scanMimeType, equals('image/jpeg'));
      expect(restored.documentNumber, equals('AB1234567'));
      expect(restored.issuingCountry, equals('NL'));
      expect(utf8.decode(restored.scanBytes), equals('fake-scan-data'));
    });

    test('toPublicJson excludes scan bytes but includes hash', () {
      final scanData = Uint8List.fromList(utf8.encode('secret-scan'));
      final doc = IdDocument(
        type: IdDocumentType.identityCard,
        scanBytes: scanData,
        scanMimeType: 'image/png',
        issuingCountry: 'DE',
        holderName: 'Bob Mueller',
      );

      final pubJson = doc.toPublicJson();
      expect(pubJson.containsKey('scan_b64'), isFalse);
      expect(pubJson['scan_hash'], isNotEmpty);
      expect(pubJson['scan_size_bytes'], equals(scanData.length));
      expect(pubJson['issuing_country'], equals('DE'));
    });
  });

  group('CreativeProof', () {
    late Uint8List masterKey;
    late ZegelKeyPair creatorKeys;
    late CreatorIdentity creator;

    setUp(() {
      masterKey = _testKey();
      creatorKeys = CreativeProof.generateCreatorKeypair();
      creator = _testCreator();
    });

    test('seal and verify roundtrip with text content', () {
      final content = Uint8List.fromList(
        utf8.encode('This is my original poem about Dart.'),
      );

      final sealed = CreativeProof.seal(
        content: content,
        contentType: 'text/plain',
        filename: 'poem.txt',
        masterKey: masterKey,
        creatorSigningKey: creatorKeys.privateKey,
        creator: creator,
        options: CreativeProofOptions(
          workType: CreativeWorkType.poem,
          workTitle: 'Ode to Dart',
          workDescription: 'A short poem.',
          tags: ['poetry', 'dart', 'programming'],
          salt: _zeroSalt(),
        ),
      );

      expect(sealed.length, greaterThan(content.length));

      final result = CreativeProof.verify(sealed, masterKey);

      expect(result.valid, isTrue);
      expect(result.signatureValid, isTrue);
      expect(result.content, equals(content));
      expect(result.contentType, equals('text/plain'));
      expect(result.originalFilename, equals('poem.txt'));
      expect(result.creator!.firstName, equals('Alice'));
      expect(result.creator!.familyName, equals('Nakamoto'));
      expect(result.creator!.companyName, equals('Creative Works BV'));
      expect(result.workType, equals(CreativeWorkType.poem));
      expect(result.workTitle, equals('Ode to Dart'));
      expect(result.tags, equals(['poetry', 'dart', 'programming']));
      expect(result.createdAt, isNotNull);
      expect(result.contentHashHex, isNotNull);
      expect(result.signatureHex, isNotNull);
    });

    test('seal and verify with ID documents', () {
      final content = Uint8List.fromList(
        utf8.encode('My original song lyrics'),
      );

      final passportScan = Uint8List.fromList(
        utf8.encode('fake-passport-jpeg-bytes'),
      );
      final idCardScan = Uint8List.fromList(
        utf8.encode('fake-idcard-png-bytes'),
      );

      final sealed = CreativeProof.seal(
        content: content,
        contentType: 'text/plain',
        filename: 'lyrics.txt',
        masterKey: masterKey,
        creatorSigningKey: creatorKeys.privateKey,
        creator: creator,
        options: CreativeProofOptions(
          workType: CreativeWorkType.music,
          workTitle: 'My Song',
          salt: _zeroSalt(),
        ),
        idDocuments: [
          IdDocument(
            type: IdDocumentType.passport,
            scanBytes: passportScan,
            scanMimeType: 'image/jpeg',
            issuingCountry: 'NL',
            holderName: 'Alice B Nakamoto',
          ),
          IdDocument(
            type: IdDocumentType.identityCard,
            scanBytes: idCardScan,
            scanMimeType: 'image/png',
            issuingCountry: 'NL',
          ),
        ],
      );

      final result = CreativeProof.verify(sealed, masterKey);

      expect(result.valid, isTrue);
      expect(result.signatureValid, isTrue);
      expect(result.idDocuments, isNotNull);
      expect(result.idDocuments!.length, equals(2));
      expect(result.idDocuments![0].type, equals(IdDocumentType.passport));
      expect(result.idDocuments![0].issuingCountry, equals('NL'));
      expect(
        utf8.decode(result.idDocuments![0].scanBytes),
        equals('fake-passport-jpeg-bytes'),
      );
      expect(result.idDocuments![1].type, equals(IdDocumentType.identityCard));
    });

    test('seal with compression and verify', () {
      final content = Uint8List.fromList(
        List.generate(10000, (i) => i % 256),
      );

      final sealed = CreativeProof.seal(
        content: content,
        contentType: 'application/octet-stream',
        filename: 'data.bin',
        masterKey: masterKey,
        creatorSigningKey: creatorKeys.privateKey,
        creator: creator,
        options: CreativeProofOptions(
          workType: CreativeWorkType.software,
          compress: true,
          salt: _zeroSalt(),
        ),
      );

      final result = CreativeProof.verify(sealed, masterKey);
      expect(result.valid, isTrue);
      expect(result.signatureValid, isTrue);
      expect(result.content, equals(content));
    });

    test('inspect without key returns public creator info', () {
      final content = Uint8List.fromList(utf8.encode('creative work'));

      final sealed = CreativeProof.seal(
        content: content,
        contentType: 'image/png',
        filename: 'art.png',
        masterKey: masterKey,
        creatorSigningKey: creatorKeys.privateKey,
        creator: creator,
        options: CreativeProofOptions(
          workType: CreativeWorkType.image,
          workTitle: 'Digital Art',
          tags: ['art', 'digital'],
          salt: _zeroSalt(),
        ),
      );

      final insp = CreativeProof.inspect(sealed);

      expect(insp.isCreativeProof, isTrue);
      expect(insp.workType, equals('image'));
      expect(insp.workTitle, equals('Digital Art'));
      expect(insp.creatorName, equals('Alice B Nakamoto'));
      expect(insp.contentHashHex, isNotNull);
      expect(insp.signatureHex, isNotNull);
      expect(insp.creatorPublicKeyHex, isNotNull);
      expect(insp.createdAt, isNotNull);
      expect(insp.tags, equals(['art', 'digital']));
    });

    test('verifyPublicSignature validates signature without master key', () {
      final content = Uint8List.fromList(utf8.encode('another work'));

      final sealed = CreativeProof.seal(
        content: content,
        contentType: 'audio/mpeg',
        filename: 'song.mp3',
        masterKey: masterKey,
        creatorSigningKey: creatorKeys.privateKey,
        creator: creator,
        options: CreativeProofOptions(
          workType: CreativeWorkType.music,
          salt: _zeroSalt(),
        ),
      );

      expect(CreativeProof.verifyPublicSignature(sealed), isTrue);
    });

    test('tampered file fails verification', () {
      final content = Uint8List.fromList(utf8.encode('original'));

      final sealed = CreativeProof.seal(
        content: content,
        contentType: 'text/plain',
        filename: 'test.txt',
        masterKey: masterKey,
        creatorSigningKey: creatorKeys.privateKey,
        creator: creator,
        options: CreativeProofOptions(
          workType: CreativeWorkType.document,
          salt: _zeroSalt(),
        ),
      );

      final tampered = Uint8List.fromList(sealed);
      tampered[sealed.length ~/ 2] ^= 0xFF;

      expect(
        () => CreativeProof.verify(tampered, masterKey),
        throwsA(isA<ZegelTamperedException>()),
      );
    });

    test('wrong key fails verification', () {
      final content = Uint8List.fromList(utf8.encode('secret'));

      final sealed = CreativeProof.seal(
        content: content,
        contentType: 'text/plain',
        filename: 'secret.txt',
        masterKey: masterKey,
        creatorSigningKey: creatorKeys.privateKey,
        creator: creator,
        options: CreativeProofOptions(
          workType: CreativeWorkType.document,
          salt: _zeroSalt(),
        ),
      );

      final wrongKey = Uint8List(32);
      wrongKey[0] = 0xFF;

      expect(
        () => CreativeProof.verify(sealed, wrongKey),
        throwsA(isA<ZegelTamperedException>()),
      );
    });

    test('inspect non-creative-proof .zgl returns isCreativeProof false', () {
      final options = ZegelOptions(
        contentType: 'text/plain',
        filename: 'normal.txt',
        salt: _zeroSalt(),
      );
      final writer = ZegelWriter(masterKey, options);
      final sealed = writer.seal(Uint8List.fromList(utf8.encode('normal')));

      final insp = CreativeProof.inspect(sealed);
      expect(insp.isCreativeProof, isFalse);
    });

    test('identity with social media handles', () {
      const creator2 = CreatorIdentity(
        firstName: 'Carol',
        familyName: 'Voss',
        socialMediaHandles: {
          'twitter': '@carol_art',
          'instagram': '@carol.creates',
        },
      );

      final json = creator2.toJson();
      final restored = CreatorIdentity.fromJson(json);
      expect(restored.socialMediaHandles!['twitter'], equals('@carol_art'));
      expect(
        restored.socialMediaHandles!['instagram'],
        equals('@carol.creates'),
      );
    });
  });

  group('MIME type guessing', () {
    test('audio types', () {
      expect(CreativeProof.guessMimeType('song.mp3'), equals('audio/mpeg'));
      expect(CreativeProof.guessMimeType('track.wav'), equals('audio/wav'));
      expect(CreativeProof.guessMimeType('album.flac'), equals('audio/flac'));
    });

    test('image types', () {
      expect(CreativeProof.guessMimeType('photo.png'), equals('image/png'));
      expect(CreativeProof.guessMimeType('pic.jpg'), equals('image/jpeg'));
      expect(CreativeProof.guessMimeType('art.webp'), equals('image/webp'));
    });

    test('video types', () {
      expect(CreativeProof.guessMimeType('movie.mp4'), equals('video/mp4'));
      expect(CreativeProof.guessMimeType('clip.avi'),
          equals('video/x-msvideo'));
    });

    test('document types', () {
      expect(CreativeProof.guessMimeType('doc.pdf'), equals('application/pdf'));
      expect(CreativeProof.guessMimeType('notes.txt'), equals('text/plain'));
    });

    test('unknown extension', () {
      expect(CreativeProof.guessMimeType('data.xyz'),
          equals('application/octet-stream'));
    });
  });

  group('Work type guessing', () {
    test('audio -> music', () {
      expect(CreativeProof.guessWorkType('audio/mpeg'),
          equals(CreativeWorkType.music));
    });

    test('image -> image', () {
      expect(CreativeProof.guessWorkType('image/png'),
          equals(CreativeWorkType.image));
    });

    test('photoshop -> design', () {
      expect(CreativeProof.guessWorkType('image/vnd.adobe.photoshop'),
          equals(CreativeWorkType.design));
    });

    test('video -> video', () {
      expect(CreativeProof.guessWorkType('video/mp4'),
          equals(CreativeWorkType.video));
    });

    test('text -> document', () {
      expect(CreativeProof.guessWorkType('text/plain'),
          equals(CreativeWorkType.document));
    });
  });
}
