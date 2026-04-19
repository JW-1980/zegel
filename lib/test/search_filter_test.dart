import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

class _Record {
  const _Record({
    required this.name,
    required this.status,
    required this.tags,
  });

  final String name;
  final String status;
  final List<String> tags;
}

void main() {
  group('SearchQuery.parse', () {
    test('empty input returns empty query', () {
      final q = SearchQuery.parse('');
      expect(q.isEmpty, isTrue);
    });

    test('extracts free-text terms', () {
      final q = SearchQuery.parse('hello world');
      expect(q.terms, ['hello', 'world']);
      expect(q.filters, isEmpty);
    });

    test('parses field:value filters', () {
      final q = SearchQuery.parse('status:failed year:2026');
      expect(q.filters['status'], ['failed']);
      expect(q.filters['year'], ['2026']);
    });

    test('handles quoted multi-word tokens', () {
      final q = SearchQuery.parse('"quarterly report"');
      expect(q.terms, ['quarterly report']);
    });

    test('combines filters and terms', () {
      final q = SearchQuery.parse('status:ok seal');
      expect(q.filters['status'], ['ok']);
      expect(q.terms, ['seal']);
    });
  });

  group('SearchQuery.matches', () {
    test('matches records satisfying all filters and terms', () {
      final records = <_Record>[
        const _Record(
          name: 'alpha',
          status: 'ok',
          tags: ['finance', 'q1'],
        ),
        const _Record(
          name: 'beta',
          status: 'failed',
          tags: ['finance', 'q2'],
        ),
      ];
      final q = SearchQuery.parse('status:failed finance');
      final matching = records
          .where(
            (r) => q.matches<_Record>(
              record: r,
              searchable: (r) => <String>[r.name, r.status, ...r.tags],
              fieldExtractor: (r, field) {
                switch (field) {
                  case 'status':
                    return r.status;
                  case 'name':
                    return r.name;
                  default:
                    return null;
                }
              },
            ),
          )
          .toList();
      expect(matching.length, 1);
      expect(matching.first.name, 'beta');
    });

    test('empty query matches every record', () {
      final q = SearchQuery.parse('');
      expect(
        q.matches<_Record>(
          record: const _Record(name: 'a', status: 's', tags: <String>[]),
          searchable: (r) => <String>[r.name],
          fieldExtractor: (_, __) => null,
        ),
        isTrue,
      );
    });
  });
}
