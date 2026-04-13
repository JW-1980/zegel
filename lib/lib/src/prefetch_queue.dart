import 'dart:async';
import 'dart:collection';

/// Pre-fetch queue for predictable network requests (improvement #68).
///
/// Zegel issues a small number of repeatable network calls (timestamp
/// authorities, webhook endpoints, key directory lookups) that often
/// happen immediately after a user-triggered action. Pre-fetching warms
/// the caches for those calls so the interactive flow stays fast.
///
/// The queue caches results by [PrefetchKey] and honours an optional TTL.
/// Callers invoke [prefetch] in the background and later [fetch] on the
/// hot path — if the cached value is still fresh, [fetch] resolves
/// synchronously; otherwise it kicks off a fresh fetch.
class PrefetchQueue<K, V> {
  PrefetchQueue({
    required this.loader,
    this.ttl = const Duration(minutes: 5),
    this.maxEntries = 32,
  });

  /// The underlying loader invoked to resolve a key.
  final Future<V> Function(K key) loader;

  /// Time-to-live for cached entries.
  final Duration ttl;

  /// Maximum number of entries retained. Oldest (by cachedAt) are
  /// evicted on overflow.
  final int maxEntries;

  final LinkedHashMap<K, _CachedValue<V>> _cache =
      LinkedHashMap<K, _CachedValue<V>>();
  final Set<K> _inFlight = <K>{};

  /// Number of cached entries.
  int get length => _cache.length;

  /// True if [key] currently has a fresh cached value.
  bool isHot(K key, {DateTime? now}) {
    final entry = _cache[key];
    if (entry == null) return false;
    final cutoff = (now ?? DateTime.now().toUtc()).toUtc();
    return cutoff.difference(entry.cachedAt) <= ttl;
  }

  /// Kicks off a prefetch for [key] in the background. Safe to call
  /// repeatedly — in-flight fetches are deduplicated. Returns the
  /// pending Future (useful for tests).
  Future<V> prefetch(K key) {
    if (isHot(key)) {
      return Future<V>.value(_cache[key]!.value);
    }
    if (_inFlight.contains(key)) {
      // Another prefetch is already running; wait for it to finish.
      return _waitUntilCached(key);
    }
    _inFlight.add(key);
    return _fetchAndStore(key);
  }

  /// Resolves [key] from the cache if hot, otherwise loads it.
  Future<V> fetch(K key) async {
    if (isHot(key)) {
      return _cache[key]!.value;
    }
    return prefetch(key);
  }

  /// Manually invalidates a cached entry.
  void invalidate(K key) {
    _cache.remove(key);
  }

  /// Clears all cached entries.
  void clear() => _cache.clear();

  Future<V> _fetchAndStore(K key) async {
    try {
      final value = await loader(key);
      _cache[key] = _CachedValue<V>(
        value: value,
        cachedAt: DateTime.now().toUtc(),
      );
      _evictIfNeeded();
      return value;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<V> _waitUntilCached(K key) async {
    while (_inFlight.contains(key)) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final entry = _cache[key];
    if (entry == null) {
      throw StateError('Prefetch for $key failed');
    }
    return entry.value;
  }

  void _evictIfNeeded() {
    while (_cache.length > maxEntries) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }
  }
}

class _CachedValue<V> {
  const _CachedValue({required this.value, required this.cachedAt});

  final V value;
  final DateTime cachedAt;
}
