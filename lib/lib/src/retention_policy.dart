import 'dart:convert';

/// Retention policies for activity logs (improvement #80).
///
/// Defines how long different categories of log events are kept and
/// applies the policy to an ordered list of events. Callers hand in
/// objects that expose a timestamp and category string; the policy drops
/// events that exceed their category's retention window.
class RetentionPolicy {
  RetentionPolicy({
    this.defaultRetention = const Duration(days: 365),
    Map<String, Duration>? rules,
  }) : _rules = Map<String, Duration>.of(rules ?? const <String, Duration>{});

  /// Default retention windows applied when a category has no explicit rule.
  final Duration defaultRetention;

  /// Per-category overrides.
  final Map<String, Duration> _rules;

  /// Adds or replaces the retention duration for [category].
  void setRule(String category, Duration retention) {
    _rules[category] = retention;
  }

  /// Removes a per-category rule, falling back to the default.
  void removeRule(String category) {
    _rules.remove(category);
  }

  /// Returns the retention window in effect for [category].
  Duration retentionFor(String category) =>
      _rules[category] ?? defaultRetention;

  /// Returns `true` when [event] is older than the category's retention
  /// window at [now] (defaults to the current UTC time).
  bool isExpired(RetainableEvent event, {DateTime? now}) {
    final cutoff = (now ?? DateTime.now().toUtc()).toUtc();
    final window = retentionFor(event.category);
    return cutoff.difference(event.timestamp) > window;
  }

  /// Returns the list of events still retained at [now].
  List<T> apply<T extends RetainableEvent>(List<T> events, {DateTime? now}) {
    return events.where((e) => !isExpired(e, now: now)).toList();
  }

  /// Splits [events] into `(kept, expired)` pairs.
  ({List<T> kept, List<T> expired}) partition<T extends RetainableEvent>(
    List<T> events, {
    DateTime? now,
  }) {
    final kept = <T>[];
    final expired = <T>[];
    for (final e in events) {
      if (isExpired(e, now: now)) {
        expired.add(e);
      } else {
        kept.add(e);
      }
    }
    return (kept: kept, expired: expired);
  }

  Map<String, dynamic> toJson() => {
    'default_retention_seconds': defaultRetention.inSeconds,
    'rules': {for (final e in _rules.entries) e.key: e.value.inSeconds},
  };

  String encode() => jsonEncode(toJson());

  static RetentionPolicy decodeJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final rules = <String, Duration>{};
    (m['rules'] as Map<String, dynamic>?)?.forEach((k, v) {
      rules[k] = Duration(seconds: (v as num).toInt());
    });
    return RetentionPolicy(
      defaultRetention: Duration(
        seconds:
            (m['default_retention_seconds'] as num?)?.toInt() ??
            const Duration(days: 365).inSeconds,
      ),
      rules: rules,
    );
  }
}

/// Interface for anything the retention policy can operate on.
abstract class RetainableEvent {
  DateTime get timestamp;
  String get category;
}
