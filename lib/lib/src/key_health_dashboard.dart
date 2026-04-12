import 'key_rotation_reminder.dart';

/// Key health dashboard aggregator (improvement #87).
///
/// Consumes the state of a [KeyRotationReminder] and produces a
/// dashboard-ready summary: how many keys are OK, due, or overdue; the
/// single most-urgent key; and a `healthScore` in `[0.0, 1.0]` where 1.0
/// means every key is fresh and 0.0 means every key is overdue.
class KeyHealthDashboard {
  KeyHealthDashboard._();

  /// Builds a snapshot from a [KeyRotationReminder].
  static KeyHealthSnapshot from(
    KeyRotationReminder reminder, {
    DateTime? now,
  }) {
    final summaries = reminder.summarize(now: now);
    var ok = 0;
    var due = 0;
    var overdue = 0;
    for (final summary in summaries) {
      switch (summary.status) {
        case RotationStatus.ok:
          ok += 1;
          break;
        case RotationStatus.due:
          due += 1;
          break;
        case RotationStatus.overdue:
          overdue += 1;
          break;
        case RotationStatus.unknown:
          break;
      }
    }
    final total = ok + due + overdue;
    final healthScore = total == 0
        ? 1.0
        : (ok * 1.0 + due * 0.5 + overdue * 0.0) / total;

    KeyRotationSummary? mostUrgent;
    if (summaries.isNotEmpty) {
      mostUrgent = summaries.first;
    }

    return KeyHealthSnapshot(
      ok: ok,
      due: due,
      overdue: overdue,
      total: total,
      healthScore: healthScore,
      mostUrgent: mostUrgent,
    );
  }
}

class KeyHealthSnapshot {
  const KeyHealthSnapshot({
    required this.ok,
    required this.due,
    required this.overdue,
    required this.total,
    required this.healthScore,
    this.mostUrgent,
  });

  final int ok;
  final int due;
  final int overdue;
  final int total;

  /// Value in `[0.0, 1.0]`. 1.0 means every key is fresh; 0.0 means
  /// every key is overdue. Undefined on an empty tracker (returned as
  /// 1.0, which is a defensible default for "no keys to worry about").
  final double healthScore;

  /// The most urgent key summary (highest age) or null when no keys
  /// are tracked.
  final KeyRotationSummary? mostUrgent;

  bool get isHealthy => overdue == 0 && due == 0;
}
