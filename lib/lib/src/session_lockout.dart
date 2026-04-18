import 'dart:async';

/// Automatic idle-lockout tracker (improvement #53).
///
/// Maintains a "last activity" timestamp that the caller bumps on user
/// interaction. When the idle interval exceeds [timeout] a `lock` event
/// is emitted through [events] and the session is marked as locked.
/// Callers typically wrap sensitive screens (keygen, split-key, attest)
/// with a listener that navigates away on lock.
///
/// This class does not handle authentication; it only decides when to
/// *require* re-authentication.
class SessionLockout {
  SessionLockout({
    this.timeout = const Duration(minutes: 5),
    DateTime? nowOverride,
  }) : _lastActivity = nowOverride ?? DateTime.now().toUtc();

  /// How long the session may be idle before locking.
  Duration timeout;

  DateTime _lastActivity;
  bool _locked = false;
  Timer? _timer;

  final StreamController<SessionLockoutEvent> _events =
      StreamController<SessionLockoutEvent>.broadcast();

  /// Broadcast stream of lock/unlock events.
  Stream<SessionLockoutEvent> get events => _events.stream;

  /// Whether the session is currently locked.
  bool get isLocked => _locked;

  /// Timestamp of the most recent recorded activity.
  DateTime get lastActivity => _lastActivity;

  /// Records a user interaction. Has no effect if the session is locked
  /// (use [unlock] to revive it).
  void recordActivity({DateTime? at}) {
    if (_locked) return;
    _lastActivity = (at ?? DateTime.now().toUtc()).toUtc();
  }

  /// Returns true if the session would be locked at [now] given the
  /// current [timeout]. Used by lazy, poll-driven callers.
  bool isIdleAt(DateTime now) =>
      now.toUtc().difference(_lastActivity) >= timeout;

  /// Forces a lock and emits a lock event.
  void lock({DateTime? at}) {
    if (_locked) return;
    _locked = true;
    if (!_events.isClosed) {
      _events.add(
        SessionLockoutEvent(
          type: SessionLockoutEventType.locked,
          at: (at ?? DateTime.now().toUtc()).toUtc(),
        ),
      );
    }
  }

  /// Unlocks after a successful re-authentication.
  void unlock({DateTime? at}) {
    if (!_locked) return;
    _locked = false;
    final now = (at ?? DateTime.now().toUtc()).toUtc();
    _lastActivity = now;
    if (!_events.isClosed) {
      _events.add(
        SessionLockoutEvent(type: SessionLockoutEventType.unlocked, at: now),
      );
    }
  }

  /// Starts a background timer that polls at [pollInterval] and locks
  /// when idle. Intended for long-lived processes; UI apps usually
  /// prefer calling [isIdleAt] from their existing event loop.
  void startTimer({Duration pollInterval = const Duration(seconds: 30)}) {
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) {
      if (!_locked && isIdleAt(DateTime.now().toUtc())) {
        lock();
      }
    });
  }

  /// Stops the background timer if one is running.
  void stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Closes the event stream.
  Future<void> close() async {
    stopTimer();
    if (!_events.isClosed) await _events.close();
  }
}

class SessionLockoutEvent {
  const SessionLockoutEvent({required this.type, required this.at});

  final SessionLockoutEventType type;
  final DateTime at;
}

enum SessionLockoutEventType { locked, unlocked }
