/// Contextual help registry (improvement #14).
///
/// Every screen, CLI command, and cryptographic term is associated with a
/// [HelpEntry] describing what it does and linking to related entries.
/// The registry is populated at startup and consulted by both the GUI
/// help panels and a CLI `zegel explain <topic>` command.
class HelpRegistry {
  HelpRegistry();

  final Map<String, HelpEntry> _entries = <String, HelpEntry>{};

  /// Registers a help entry. Duplicates overwrite the previous entry.
  void register(HelpEntry entry) {
    _entries[entry.topic] = entry;
  }

  /// Bulk-registers a list of entries.
  void registerAll(Iterable<HelpEntry> entries) {
    for (final entry in entries) {
      register(entry);
    }
  }

  /// Looks up a help entry by topic id.
  HelpEntry? lookup(String topic) => _entries[topic];

  /// Returns the list of topics beginning with [prefix], sorted
  /// alphabetically. Useful for fuzzy CLI completions.
  List<String> topicsWithPrefix(String prefix) {
    final lower = prefix.toLowerCase();
    return _entries.keys
        .where((k) => k.toLowerCase().startsWith(lower))
        .toList()
      ..sort();
  }

  /// Substring search across topic, title, summary, and body. Returns
  /// a ranked list: exact topic matches first, then title matches, then
  /// body matches.
  List<HelpEntry> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const <HelpEntry>[];
    final topicHits = <HelpEntry>[];
    final titleHits = <HelpEntry>[];
    final bodyHits = <HelpEntry>[];
    for (final entry in _entries.values) {
      if (entry.topic.toLowerCase() == needle) {
        topicHits.add(entry);
      } else if (entry.title.toLowerCase().contains(needle)) {
        titleHits.add(entry);
      } else if (entry.summary.toLowerCase().contains(needle) ||
          entry.body.toLowerCase().contains(needle)) {
        bodyHits.add(entry);
      }
    }
    return <HelpEntry>[...topicHits, ...titleHits, ...bodyHits];
  }

  int get length => _entries.length;

  /// Populates the registry with the default Zegel help entries.
  factory HelpRegistry.defaults() {
    final registry = HelpRegistry()
      ..registerAll(<HelpEntry>[
        const HelpEntry(
          topic: 'seal',
          title: 'Sealing a file',
          summary: 'Turn any file into a tamper-proof .zgl container.',
          body:
              'Sealing wraps the file in a Merkle-tree-keyed envelope. Modifying '
              'a single byte of the sealed file makes it unreadable, because the '
              'derived keys depend on the integrity of every other byte.',
          related: <String>['verify', 'extract', 'key'],
        ),
        const HelpEntry(
          topic: 'verify',
          title: 'Verifying a sealed file',
          summary: 'Check that a .zgl file has not been tampered with.',
          body:
              'Verification re-derives the Merkle tree and decrypts the content '
              'blocks. A valid result guarantees both integrity (no byte modified) '
              'and authenticity (signed with the expected master key).',
          related: <String>['seal', 'attest'],
        ),
        const HelpEntry(
          topic: 'split-key',
          title: 'Shamir Secret Sharing',
          summary: 'Split a master key into N shares, any M of which can '
              'reconstruct it.',
          body:
              'Split-key support lets you hand out different shares to different '
              'people so that no single person can unseal a file alone. '
              'Reconstruction requires collecting the threshold number of shares.',
          related: <String>['key', 'reconstruct'],
        ),
        const HelpEntry(
          topic: 'merkle-root',
          title: 'Merkle root',
          summary: 'The single hash that commits to every block in the file.',
          body:
              'Each content block is hashed, and the hashes are combined pairwise '
              'into a binary tree. The root of the tree is the "Merkle root". '
              'Any change to any block changes the root, which in turn changes '
              'every derived key.',
          related: <String>['seal', 'verify'],
        ),
      ]);
    return registry;
  }
}

class HelpEntry {
  const HelpEntry({
    required this.topic,
    required this.title,
    required this.summary,
    required this.body,
    this.related = const <String>[],
  });

  /// Stable, lower-case identifier (used by URLs and `zegel explain`).
  final String topic;

  /// Display title.
  final String title;

  /// One-line summary for tooltips and list previews.
  final String summary;

  /// Full explanation (markdown allowed).
  final String body;

  /// Related topic ids to link from the help panel.
  final List<String> related;
}
