import 'contact_book.dart';

/// Frequent collaborator statistics (improvement #88).
///
/// Tracks how often each contact co-signs a document and produces a
/// ranked list suitable for "Your top collaborators" dashboard cards.
/// The stats are purely operational — they do not affect cryptographic
/// trust; a high collaboration count does not make a contact "verified".
class CollaboratorStats {
  CollaboratorStats({ContactBook? contactBook}) : _contactBook = contactBook;

  final ContactBook? _contactBook;
  final Map<String, int> _counts = <String, int>{};
  final Map<String, DateTime> _lastSeen = <String, DateTime>{};

  /// Records a single collaboration with [contactId]. The optional
  /// [at] parameter overrides the timestamp, useful for tests.
  void record(String contactId, {DateTime? at}) {
    _counts[contactId] = (_counts[contactId] ?? 0) + 1;
    _lastSeen[contactId] = (at ?? DateTime.now().toUtc()).toUtc();
  }

  /// Records every id in [contactIds] as a single collaboration each.
  void recordAll(Iterable<String> contactIds, {DateTime? at}) {
    for (final id in contactIds) {
      record(id, at: at);
    }
  }

  /// Number of distinct collaborators.
  int get uniqueCollaborators => _counts.length;

  /// Total collaborations recorded.
  int get totalCollaborations => _counts.values.fold<int>(0, (a, b) => a + b);

  /// Ranked list of collaborators, highest count first. Limit to the
  /// top [limit] entries.
  List<CollaboratorRank> topCollaborators({int limit = 10}) {
    final entries = _counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final out = <CollaboratorRank>[];
    for (final entry in entries.take(limit)) {
      final contact = _contactBook?.get(entry.key);
      out.add(CollaboratorRank(
        contactId: entry.key,
        count: entry.value,
        lastSeen: _lastSeen[entry.key],
        displayName: contact?.displayName ?? entry.key,
        trusted: contact?.trusted ?? false,
      ));
    }
    return out;
  }

  /// Returns the collaborators seen since [cutoff], ranked by count.
  List<CollaboratorRank> activeSince(DateTime cutoff) {
    final cutoffUtc = cutoff.toUtc();
    return topCollaborators(limit: _counts.length)
        .where((c) => c.lastSeen != null && !c.lastSeen!.isBefore(cutoffUtc))
        .toList();
  }

  /// Resets all counts.
  void reset() {
    _counts.clear();
    _lastSeen.clear();
  }
}

class CollaboratorRank {
  const CollaboratorRank({
    required this.contactId,
    required this.count,
    required this.displayName,
    required this.trusted,
    this.lastSeen,
  });

  final String contactId;
  final int count;
  final String displayName;
  final bool trusted;
  final DateTime? lastSeen;
}
