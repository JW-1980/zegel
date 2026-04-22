import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// In-memory LRU cache of verification results (improvement #65).
///
/// Verifying a `.zgl` file is not the dominant cost of most workflows, but
/// when the GUI re-opens the same file (or a dashboard keeps re-polling a
/// directory of sealed files) we can skip the work if the file bytes have
/// not changed. The cache keys on the SHA-256 of the file contents, so any
/// byte-level change invalidates the entry automatically.
class VerificationCache {
  VerificationCache({this.maxEntries = 128, this.ttl});

  /// Maximum number of entries retained; oldest (least-recently used)
  /// entries are evicted on overflow.
  final int maxEntries;

  /// Optional time-to-live for entries. `null` means entries never expire.
  final Duration? ttl;

  /// Backing LRU map. `LinkedHashMap` gives us predictable insertion order,
  /// and we promote keys on read to implement the "recently used" piece.
  final LinkedHashMap<String, CachedVerification> _entries =
      LinkedHashMap<String, CachedVerification>();

  /// Computes the cache key for the bytes of a file.
  static String keyFor(Uint8List fileBytes) {
    return sha256.convert(fileBytes).toString();
  }

  /// Looks up a cached result for the given [fileBytes].
  CachedVerification? lookup(Uint8List fileBytes, {DateTime? now}) {
    final k = keyFor(fileBytes);
    final entry = _entries.remove(k);
    if (entry == null) return null;
    if (_expired(entry, now: now)) {
      return null;
    }
    _entries[k] = entry; // re-insert at the end -> MRU
    return entry;
  }

  /// Inserts or updates the cached verification result for [fileBytes].
  void put({
    required Uint8List fileBytes,
    required bool valid,
    String? failureReason,
    Map<String, dynamic>? metadata,
    DateTime? cachedAt,
  }) {
    final k = keyFor(fileBytes);
    _entries.remove(k);
    _entries[k] = CachedVerification(
      key: k,
      valid: valid,
      failureReason: failureReason,
      metadata: metadata ?? const <String, dynamic>{},
      cachedAt: (cachedAt ?? DateTime.now().toUtc()).toUtc(),
    );
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Removes the entry for [fileBytes]. Returns true if one was removed.
  bool invalidate(Uint8List fileBytes) =>
      _entries.remove(keyFor(fileBytes)) != null;

  /// Drops all entries.
  void clear() => _entries.clear();

  /// Current number of entries in the cache.
  int get length => _entries.length;

  /// Read-only iterable of entries, MRU last.
  Iterable<CachedVerification> get entries => _entries.values;

  bool _expired(CachedVerification e, {DateTime? now}) {
    if (ttl == null) return false;
    final cutoff = (now ?? DateTime.now().toUtc()).toUtc();
    return cutoff.difference(e.cachedAt) > ttl!;
  }

  String encode() => jsonEncode({
        'max_entries': maxEntries,
        'ttl_seconds': ttl?.inSeconds,
        'entries': _entries.values.map((e) => e.toJson()).toList(),
      });

  static VerificationCache decodeJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final cache = VerificationCache(
      maxEntries: (m['max_entries'] as num?)?.toInt() ?? 128,
      ttl: m['ttl_seconds'] == null
          ? null
          : Duration(seconds: (m['ttl_seconds'] as num).toInt()),
    );
    for (final entry in (m['entries'] as List<dynamic>? ?? const <dynamic>[])) {
      final obj = CachedVerification.fromJson(entry as Map<String, dynamic>);
      cache._entries[obj.key] = obj;
    }
    return cache;
  }
}

class CachedVerification {
  const CachedVerification({
    required this.key,
    required this.valid,
    this.failureReason,
    required this.metadata,
    required this.cachedAt,
  });

  static CachedVerification fromJson(Map<String, dynamic> json) =>
      CachedVerification(
        key: json['key'] as String,
        valid: json['valid'] as bool,
        failureReason: json['failure_reason'] as String?,
        metadata: json['metadata'] == null
            ? const <String, dynamic>{}
            : Map<String, dynamic>.from(
                json['metadata'] as Map<String, dynamic>,
              ),
        cachedAt: DateTime.parse(json['cached_at'] as String).toUtc(),
      );

  final String key;
  final bool valid;
  final String? failureReason;
  final Map<String, dynamic> metadata;
  final DateTime cachedAt;

  Map<String, dynamic> toJson() => {
        'key': key,
        'valid': valid,
        if (failureReason != null) 'failure_reason': failureReason,
        'metadata': metadata,
        'cached_at': cachedAt.toUtc().toIso8601String(),
      };
}
