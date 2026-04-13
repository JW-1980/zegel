/// Generic search-and-filter query parser (improvement #13).
///
/// Parses user input like `status:failed seal 2026` into a structured
/// [SearchQuery] that callers can evaluate against a list of records.
/// The parser is intentionally small: unquoted whitespace-separated
/// tokens become either a `field:value` filter (when they contain a
/// colon) or a free-text search term.
///
/// The `SearchQuery.matches` method takes a `SearchField` extractor and
/// returns true when every filter matches and every free-text term
/// appears somewhere in the searchable fields.
class SearchQuery {
  const SearchQuery({required this.terms, required this.filters});

  /// Free-text search terms (all must match, case-insensitive).
  final List<String> terms;

  /// `field:value` filters. All must match exactly (case-insensitive).
  final Map<String, List<String>> filters;

  /// Whether the query has no tokens — [matches] returns true for
  /// every record in that case.
  bool get isEmpty => terms.isEmpty && filters.isEmpty;

  /// Evaluates the query against a record. [searchable] is the list of
  /// fields to check for free-text matches. [fieldExtractor] is called
  /// for every `field:value` filter and should return the record's
  /// value for that field, or null.
  bool matches<T>({
    required T record,
    required List<String> Function(T) searchable,
    required String? Function(T, String field) fieldExtractor,
  }) {
    for (final entry in filters.entries) {
      final actual = fieldExtractor(record, entry.key);
      if (actual == null) return false;
      final needle = actual.toLowerCase();
      // Any of the provided values may match.
      var any = false;
      for (final want in entry.value) {
        if (needle == want.toLowerCase()) {
          any = true;
          break;
        }
      }
      if (!any) return false;
    }
    if (terms.isEmpty) return true;
    final haystack = searchable(record).join(' ').toLowerCase();
    for (final term in terms) {
      if (!haystack.contains(term.toLowerCase())) return false;
    }
    return true;
  }

  /// Parses [input] into a [SearchQuery]. Returns an empty query for
  /// blank input.
  static SearchQuery parse(String input) {
    final terms = <String>[];
    final filters = <String, List<String>>{};
    final tokens = _tokenize(input);
    for (final token in tokens) {
      final colon = token.indexOf(':');
      if (colon > 0 && colon < token.length - 1) {
        final key = token.substring(0, colon);
        final value = token.substring(colon + 1);
        filters.putIfAbsent(key, () => <String>[]).add(value);
      } else {
        terms.add(token);
      }
    }
    return SearchQuery(terms: terms, filters: filters);
  }

  static List<String> _tokenize(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return const <String>[];
    final tokens = <String>[];
    var i = 0;
    while (i < trimmed.length) {
      // Skip whitespace.
      while (i < trimmed.length && trimmed[i].trim().isEmpty) {
        i++;
      }
      if (i >= trimmed.length) break;
      // Quoted token.
      if (trimmed[i] == '"') {
        final end = trimmed.indexOf('"', i + 1);
        if (end == -1) {
          tokens.add(trimmed.substring(i + 1));
          break;
        }
        tokens.add(trimmed.substring(i + 1, end));
        i = end + 1;
        continue;
      }
      // Plain token.
      var j = i;
      while (j < trimmed.length && !trimmed[j].trim().isEmpty) {
        j++;
      }
      tokens.add(trimmed.substring(i, j));
      i = j;
    }
    return tokens;
  }
}
