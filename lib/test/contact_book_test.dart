import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('ContactBook', () {
    test('upsert adds and replaces contacts by id', () {
      final book = ContactBook();
      book.upsert(
        Contact(
          id: '1',
          displayName: 'Alice',
          addedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      book.upsert(
        Contact(
          id: '1',
          displayName: 'Alice Updated',
          addedAt: DateTime.utc(2026, 1, 2),
        ),
      );
      expect(book.length, 1);
      expect(book.get('1')!.displayName, 'Alice Updated');
    });

    test('markTrusted flips the flag', () {
      final book = ContactBook();
      book.upsert(
        Contact(
          id: '1',
          displayName: 'Alice',
          addedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      book.markTrusted('1');
      expect(book.get('1')!.trusted, isTrue);
      book.markTrusted('1', trusted: false);
      expect(book.get('1')!.trusted, isFalse);
    });

    test('markTrusted throws for missing contacts', () {
      final book = ContactBook();
      expect(() => book.markTrusted('missing'), throwsStateError);
    });

    test('search matches case-insensitively', () {
      final book = ContactBook();
      book.upsert(
        Contact(
          id: '1',
          displayName: 'Alice Adams',
          email: 'alice@example.org',
          addedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      book.upsert(
        Contact(
          id: '2',
          displayName: 'Bob Builder',
          organization: 'Acme Corp',
          addedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(book.search('alice').length, 1);
      expect(book.search('ACME').length, 1);
      expect(book.search('nomatch'), isEmpty);
    });

    test('list is sorted alphabetically', () {
      final book = ContactBook();
      book.upsert(
        Contact(
          id: '1',
          displayName: 'Charlie',
          addedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      book.upsert(
        Contact(
          id: '2',
          displayName: 'Alice',
          addedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final list = book.list();
      expect(list.first.displayName, 'Alice');
      expect(list.last.displayName, 'Charlie');
    });

    test('encode/decodeJson round trip', () {
      final book = ContactBook();
      book.upsert(
        Contact(
          id: '1',
          displayName: 'Alice',
          email: 'alice@example.org',
          publicKeyFingerprint: 'fp-1234',
          trusted: true,
          notes: 'co-signer',
          addedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      final restored = ContactBook.decodeJson(book.encode());
      expect(restored.length, 1);
      final c = restored.get('1')!;
      expect(c.displayName, 'Alice');
      expect(c.publicKeyFingerprint, 'fp-1234');
      expect(c.trusted, isTrue);
    });
  });
}
