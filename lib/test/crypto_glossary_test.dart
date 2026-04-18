import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('CryptoGlossary', () {
    // Known terms included in the glossary.
    const knownKeys = <String>[
      'merkle-tree',
      'merkle-root',
      'aes-256-gcm',
      'hmac-sha256',
      'shamir-secret-sharing',
      'ed25519',
      'argon2id',
      'nonce',
      'attestation',
      'audit-trail',
    ];

    group('lookup', () {
      test('returns a GlossaryTerm for every known key', () {
        for (final key in knownKeys) {
          final term = CryptoGlossary.lookup(key);
          expect(term, isNotNull, reason: 'Expected to find term "$key"');
        }
      });

      test('returns null for an unknown key', () {
        expect(CryptoGlossary.lookup('definitely-not-a-term'), isNull);
      });

      test('is case-insensitive', () {
        expect(CryptoGlossary.lookup('Merkle-Tree'), isNotNull);
        expect(CryptoGlossary.lookup('MERKLE-TREE'), isNotNull);
        expect(CryptoGlossary.lookup('AES-256-GCM'), isNotNull);
        expect(CryptoGlossary.lookup('Argon2id'), isNotNull);
      });

      test('returned term has non-empty title and tooltip', () {
        final term = CryptoGlossary.lookup('nonce')!;
        expect(term.title, isNotEmpty);
        expect(term.tooltip, isNotEmpty);
        expect(term.description, isNotEmpty);
      });

      test('merkle-tree term has expected seeAlso entries', () {
        final term = CryptoGlossary.lookup('merkle-tree')!;
        expect(term.seeAlso, contains('merkle-root'));
        expect(term.seeAlso, contains('seal'));
      });

      test('returned term key matches the lookup key', () {
        final term = CryptoGlossary.lookup('argon2id')!;
        expect(term.term, 'argon2id');
      });
    });

    group('all()', () {
      test('returns a non-empty list', () {
        expect(CryptoGlossary.all(), isNotEmpty);
      });

      test('contains all known terms', () {
        final allTerms = CryptoGlossary.all().map((t) => t.term).toSet();
        for (final key in knownKeys) {
          expect(
            allTerms,
            contains(key),
            reason: 'Expected all() to contain "$key"',
          );
        }
      });

      test('returns terms sorted alphabetically by term key', () {
        final terms = CryptoGlossary.all();
        for (var i = 0; i < terms.length - 1; i++) {
          expect(
            terms[i].term.compareTo(terms[i + 1].term),
            lessThanOrEqualTo(0),
            reason:
                '"${terms[i].term}" should sort before "${terms[i + 1].term}"',
          );
        }
      });

      test('list length matches the expected number of built-in terms', () {
        expect(CryptoGlossary.all().length, knownKeys.length);
      });

      test('each term has a unique key', () {
        final terms = CryptoGlossary.all();
        final keys = terms.map((t) => t.term).toSet();
        expect(keys.length, terms.length);
      });
    });

    group('tooltipFor', () {
      test('returns the tooltip string for a known key', () {
        final expected = CryptoGlossary.lookup('nonce')!.tooltip;
        expect(CryptoGlossary.tooltipFor('nonce'), expected);
      });

      test('returns empty string for unknown key', () {
        expect(CryptoGlossary.tooltipFor('not-a-real-term'), '');
      });

      test('is case-insensitive (forwarded from lookup)', () {
        expect(
          CryptoGlossary.tooltipFor('NONCE'),
          CryptoGlossary.tooltipFor('nonce'),
        );
      });

      test('aes-256-gcm tooltip mentions encryption', () {
        final tooltip = CryptoGlossary.tooltipFor('aes-256-gcm').toLowerCase();
        expect(tooltip, contains('encrypt'));
      });

      test('shamir-secret-sharing tooltip mentions shares', () {
        final tooltip = CryptoGlossary.tooltipFor(
          'shamir-secret-sharing',
        ).toLowerCase();
        expect(tooltip, contains('share'));
      });
    });

    group('search', () {
      test('empty query returns empty list', () {
        expect(CryptoGlossary.search(''), isEmpty);
      });

      test('whitespace-only query returns empty list', () {
        expect(CryptoGlossary.search('   '), isEmpty);
      });

      test('exact term key matches', () {
        final results = CryptoGlossary.search('nonce');
        expect(results.map((t) => t.term), contains('nonce'));
      });

      test('partial term key matches', () {
        final results = CryptoGlossary.search('merkle');
        final keys = results.map((t) => t.term).toList();
        expect(keys, contains('merkle-tree'));
        expect(keys, contains('merkle-root'));
      });

      test('title substring matches (case-insensitive)', () {
        // "Argon2id" title contains "Argon".
        final results = CryptoGlossary.search('Argon');
        expect(results.map((t) => t.term), contains('argon2id'));
      });

      test('tooltip substring matches', () {
        // "authenticated" appears in the AES-256-GCM tooltip.
        final results = CryptoGlossary.search('authenticated');
        expect(results.map((t) => t.term), contains('aes-256-gcm'));
      });

      test('unknown query returns empty list', () {
        expect(CryptoGlossary.search('zzznomatchzzz'), isEmpty);
      });

      test('search is case-insensitive', () {
        final lower = CryptoGlossary.search(
          'shamir',
        ).map((t) => t.term).toSet();
        final upper = CryptoGlossary.search(
          'SHAMIR',
        ).map((t) => t.term).toSet();
        expect(lower, equals(upper));
      });

      test('results include GlossaryTerm objects with full data', () {
        final results = CryptoGlossary.search('audit');
        expect(results, isNotEmpty);
        final term = results.first;
        expect(term.description, isNotEmpty);
      });
    });

    group('GlossaryTerm structure', () {
      test('seeAlso defaults to empty list when not provided', () {
        const term = GlossaryTerm(
          term: 'test-term',
          title: 'Test',
          tooltip: 'A test',
          description: 'A longer test description',
        );
        expect(term.seeAlso, isEmpty);
      });

      test('all built-in terms have non-empty description', () {
        for (final term in CryptoGlossary.all()) {
          expect(
            term.description,
            isNotEmpty,
            reason: '${term.term} description should not be empty',
          );
        }
      });
    });
  });
}
