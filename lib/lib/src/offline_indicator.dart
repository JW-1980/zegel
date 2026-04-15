import 'dart:async';
import 'dart:io';

/// Offline / online connectivity indicator (improvement #42).
///
/// Probes a list of "heartbeat" endpoints (the TSA URL, a webhook, etc.)
/// and reports whether any of them are reachable. The indicator emits
/// state transitions over [stream] so the UI can pop up a toast when
/// the network goes away and hide it when it comes back.
///
/// The probe uses `InternetAddress.lookup` by default because it works
/// without holding open a socket. Callers can supply a custom prober
/// (useful for tests).
class OfflineIndicator {
  OfflineIndicator({
    required this.endpoints,
    this.pollInterval = const Duration(seconds: 30),
    Future<bool> Function(String)? prober,
  }) : _prober = prober ?? _defaultProber;

  /// Hostnames or URLs to probe.
  final List<String> endpoints;

  /// Interval between probes when [start] has been called.
  final Duration pollInterval;

  final Future<bool> Function(String) _prober;
  // sync: true delivers events synchronously from `add()`, so callers that
  // `await probeOnce()` are guaranteed to observe the emitted state on any
  // listener they attached before calling it. Without this, broadcast
  // delivery is a microtask and consumers can cancel their subscription
  // before the event is routed.
  final StreamController<ConnectivityState> _stream =
      StreamController<ConnectivityState>.broadcast(sync: true);

  ConnectivityState _state = ConnectivityState.unknown;
  Timer? _timer;

  /// Current state.
  ConnectivityState get state => _state;

  /// Broadcast stream of state transitions.
  Stream<ConnectivityState> get stream => _stream.stream;

  /// Probes every endpoint once and updates [state]. Useful for unit
  /// tests that don't want a running timer.
  Future<ConnectivityState> probeOnce() async {
    ConnectivityState result = ConnectivityState.offline;
    for (final endpoint in endpoints) {
      try {
        if (await _prober(endpoint)) {
          result = ConnectivityState.online;
          break;
        }
      } catch (_) {
        // continue probing the remaining endpoints
      }
    }
    _setState(result);
    return result;
  }

  /// Starts polling in the background.
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => probeOnce());
  }

  /// Stops the background poll.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Closes the stream controller.
  Future<void> close() async {
    stop();
    if (!_stream.isClosed) await _stream.close();
  }

  void _setState(ConnectivityState next) {
    if (next == _state) return;
    _state = next;
    if (!_stream.isClosed) _stream.add(next);
  }

  static Future<bool> _defaultProber(String endpoint) async {
    final host = _hostOf(endpoint);
    try {
      final addresses = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 5));
      return addresses.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static String _hostOf(String endpoint) {
    if (endpoint.contains('://')) {
      try {
        return Uri.parse(endpoint).host;
      } catch (_) {
        // fall through
      }
    }
    return endpoint;
  }
}

enum ConnectivityState { unknown, online, offline }
