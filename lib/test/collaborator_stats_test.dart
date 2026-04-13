import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('CollaboratorStats', () {
    test('ranks top collaborators by count', () {
      final stats = CollaboratorStats()
        ..record('alice')
        ..record('alice')
        ..record('bob')
        ..record('alice')
        ..record('charlie')
        ..record('bob');

      final top = stats.topCollaborators();
      expect(top.first.contactId, 'alice');
      expect(top.first.count, 3);
      expect(top[1].contactId, 'bob');
      expect(stats.uniqueCollaborators, 3);
      expect(stats.totalCollaborations, 6);
    });

    test('resolves display names from the contact book', () {
      final book = ContactBook()
        ..upsert(Contact(
          id: 'alice',
          displayName: 'Alice Adams',
          trusted: true,
          addedAt: DateTime.utc(2026, 1, 1),
        ));
      final stats = CollaboratorStats(contactBook: book)..record('alice');
      final ranked = stats.topCollaborators();
      expect(ranked.first.displayName, 'Alice Adams');
      expect(ranked.first.trusted, isTrue);
    });

    test('activeSince filters by last-seen timestamp', () {
      final stats = CollaboratorStats()
        ..record('alice', at: DateTime.utc(2026, 1, 1))
        ..record('bob', at: DateTime.utc(2026, 5, 1));
      final recent = stats.activeSince(DateTime.utc(2026, 3, 1));
      expect(recent.length, 1);
      expect(recent.first.contactId, 'bob');
    });

    test('reset clears counts', () {
      final stats = CollaboratorStats()..record('alice');
      stats.reset();
      expect(stats.uniqueCollaborators, 0);
    });
  });
}
