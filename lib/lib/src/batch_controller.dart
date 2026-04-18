import 'dart:async';

/// Pause/resume/cancel controller for long-running batch operations
/// (improvement #44).
///
/// A lightweight coordination primitive: the worker loop periodically
/// calls [awaitResume] between iterations to yield if the user clicked
/// "Pause", and checks [isCancelled] to bail out if the user clicked
/// "Cancel". Because the controller exposes state through [state] and
/// [stream] it can also drive UI indicators without any framework
/// dependency.
class BatchController {
  BatchController();

  BatchState _state = BatchState.running;
  Completer<void>? _pauseCompleter;
  final StreamController<BatchState> _stream =
      StreamController<BatchState>.broadcast();

  /// Current state of the controller.
  BatchState get state => _state;

  /// Broadcast stream of state transitions.
  Stream<BatchState> get stream => _stream.stream;

  /// Convenience flags.
  bool get isRunning => _state == BatchState.running;
  bool get isPaused => _state == BatchState.paused;
  bool get isCancelled => _state == BatchState.cancelled;
  bool get isComplete => _state == BatchState.completed;

  /// Pauses the batch. The worker loop must call [awaitResume] at the
  /// next safe point for the pause to take effect.
  void pause() {
    if (_state != BatchState.running) return;
    _pauseCompleter = Completer<void>();
    _setState(BatchState.paused);
  }

  /// Resumes the batch. Completes any pending [awaitResume] call.
  void resume() {
    if (_state != BatchState.paused) return;
    _setState(BatchState.running);
    _pauseCompleter?.complete();
    _pauseCompleter = null;
  }

  /// Cancels the batch. Resolves any pending [awaitResume] call so the
  /// worker does not block waiting for a resume that will never arrive.
  void cancel() {
    if (_state == BatchState.completed || _state == BatchState.cancelled) {
      return;
    }
    _setState(BatchState.cancelled);
    _pauseCompleter?.complete();
    _pauseCompleter = null;
  }

  /// Marks the batch as completed (no more work to do).
  void complete() {
    if (_state == BatchState.cancelled) return;
    _setState(BatchState.completed);
    _pauseCompleter?.complete();
    _pauseCompleter = null;
  }

  /// Awaited by the worker loop between iterations. Returns immediately
  /// if the controller is running. When paused, it returns a Future that
  /// resolves only when the controller is resumed or cancelled.
  Future<void> awaitResume() {
    if (_state == BatchState.paused) {
      return _pauseCompleter!.future;
    }
    return Future<void>.value();
  }

  /// Closes the stream. Call when the batch is done so listeners unblock.
  Future<void> close() async {
    if (!_stream.isClosed) {
      await _stream.close();
    }
  }

  void _setState(BatchState next) {
    if (_state == next) return;
    _state = next;
    if (!_stream.isClosed) _stream.add(next);
  }
}

enum BatchState { running, paused, cancelled, completed }
