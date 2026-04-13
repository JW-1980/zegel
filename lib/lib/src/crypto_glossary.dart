/// Concise cryptographic glossary (improvement #10).
///
/// Powers tooltips in the GUI and a `zegel explain <term>` CLI command.
/// Each [GlossaryTerm] includes a one-line summary for hover tooltips,
/// a longer explanation for hover-pinned pop-ups, and optional "see
/// also" terms that let users explore related concepts.
///
/// The glossary is intentionally tight — only the crypto terms Zegel
/// actually uses are included.
class CryptoGlossary {
  CryptoGlossary._();

  static final Map<String, GlossaryTerm> _terms = <String, GlossaryTerm>{
    'merkle-tree': const GlossaryTerm(
      term: 'merkle-tree',
      title: 'Merkle tree',
      tooltip: 'A binary tree of hashes that commits to every leaf.',
      description:
          'Each data block is hashed, and the hashes are combined pairwise '
          'into a binary tree. The root (the Merkle root) is a fingerprint '
          'of every block: changing any byte anywhere changes the root.',
      seeAlso: <String>['merkle-root', 'seal'],
    ),
    'merkle-root': const GlossaryTerm(
      term: 'merkle-root',
      title: 'Merkle root',
      tooltip: 'The topmost hash of a Merkle tree.',
      description:
          'The Merkle root is the single 32-byte hash that fingerprints every '
          'block in a sealed file. Zegel uses it as entropy to derive per-block '
          'encryption keys, so modifying any byte makes the file unreadable.',
      seeAlso: <String>['merkle-tree'],
    ),
    'aes-256-gcm': const GlossaryTerm(
      term: 'aes-256-gcm',
      title: 'AES-256-GCM',
      tooltip: 'Authenticated symmetric encryption with a 256-bit key.',
      description:
          'AES-256-GCM is the encryption algorithm that wraps each content '
          'block. It provides confidentiality plus a 16-byte authentication '
          'tag that detects any tampering with the ciphertext.',
      seeAlso: <String>['merkle-root', 'nonce'],
    ),
    'hmac-sha256': const GlossaryTerm(
      term: 'hmac-sha256',
      title: 'HMAC-SHA256',
      tooltip: 'Keyed message authentication code based on SHA-256.',
      description:
          'HMAC combines a secret key with a message and produces a fixed-size '
          'tag. Zegel uses HMAC-SHA256 to authenticate attestations and audit '
          'trail chain hashes.',
      seeAlso: <String>['attestation', 'audit-trail'],
    ),
    'shamir-secret-sharing': const GlossaryTerm(
      term: 'shamir-secret-sharing',
      title: 'Shamir Secret Sharing',
      tooltip: 'Split a secret into N shares, any M of which reconstruct it.',
      description:
          'Shamir Secret Sharing splits a master key into N individual "shares" '
          'such that any M of them can reconstruct the original secret, while '
          'any M-1 reveal nothing. Zegel uses it to distribute sealing keys '
          'across multiple parties.',
      seeAlso: <String>['split-key'],
    ),
    'ed25519': const GlossaryTerm(
      term: 'ed25519',
      title: 'Ed25519',
      tooltip: 'Modern elliptic-curve signature scheme used for identity.',
      description:
          'Ed25519 is a fast, deterministic digital signature scheme. Zegel '
          'uses it so the creator of a file can sign its Merkle root; any '
          'party can later verify the signature with the public key alone.',
      seeAlso: <String>['identity'],
    ),
    'argon2id': const GlossaryTerm(
      term: 'argon2id',
      title: 'Argon2id',
      tooltip: 'Memory-hard password hashing algorithm.',
      description:
          'Argon2id is the key-derivation function Zegel uses when a file is '
          'sealed with a password. It is deliberately slow and memory-hard to '
          'resist brute-force attacks.',
      seeAlso: <String>['password-derived'],
    ),
    'nonce': const GlossaryTerm(
      term: 'nonce',
      title: 'Nonce',
      tooltip: 'A number used once per encryption operation.',
      description:
          'A nonce is a unique value, typically random, that is passed to the '
          'cipher alongside the key. Reusing a nonce with the same key in '
          'AES-GCM catastrophically breaks confidentiality, so Zegel derives a '
          'fresh nonce per block from the Merkle root.',
      seeAlso: <String>['aes-256-gcm'],
    ),
    'attestation': const GlossaryTerm(
      term: 'attestation',
      title: 'Attestation',
      tooltip: 'A signed statement about a file.',
      description:
          'An attestation is a block added to a sealed file in which a named '
          'signer asserts something ("Reviewed and approved") along with a '
          'cryptographic signature over the Merkle root. Multiple attestations '
          'can be combined for multi-party approval workflows.',
      seeAlso: <String>['hmac-sha256', 'role-based-attestation'],
    ),
    'audit-trail': const GlossaryTerm(
      term: 'audit-trail',
      title: 'Audit trail',
      tooltip: 'Hash-chained log of events attached to a file.',
      description:
          'Zegel files can carry an append-only audit log where each entry '
          'references the hash of the previous entry, forming a tamper-evident '
          'chain. Any modification to any entry breaks the chain.',
      seeAlso: <String>['chain-hash'],
    ),
  };

  /// Returns the term for [key], or null if unknown.
  static GlossaryTerm? lookup(String key) => _terms[key.toLowerCase()];

  /// Returns every known term, sorted alphabetically.
  static List<GlossaryTerm> all() {
    final list = _terms.values.toList()
      ..sort((a, b) => a.term.compareTo(b.term));
    return list;
  }

  /// Returns a one-line tooltip string for [key], or empty if unknown.
  static String tooltipFor(String key) => lookup(key)?.tooltip ?? '';

  /// Case-insensitive substring search over terms, titles and tooltips.
  static List<GlossaryTerm> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const <GlossaryTerm>[];
    return _terms.values
        .where((term) =>
            term.term.contains(needle) ||
            term.title.toLowerCase().contains(needle) ||
            term.tooltip.toLowerCase().contains(needle))
        .toList();
  }
}

class GlossaryTerm {
  const GlossaryTerm({
    required this.term,
    required this.title,
    required this.tooltip,
    required this.description,
    this.seeAlso = const <String>[],
  });

  final String term;
  final String title;
  final String tooltip;
  final String description;
  final List<String> seeAlso;
}
