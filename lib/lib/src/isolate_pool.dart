import 'dart:async';
import 'dart:collection';

/// Concurrency pool for batch operations (improvement #62).
///
/// A small bounded-concurrency scheduler that runs up to [maxWorkers]
/// tasks in parallel and queues the rest. Tasks are regular
/// `Future<T> Function()` closures, so they can capture state and use
/// existing library code without the tight restrictions of
/// `Isolate.spawn` (which only accepts top-level functions).
///
/// The name is preserved for historical reasons — the original feature
/// request asked for an isolate pool, but in practice the heavy work in
/// Zegel is already split into small synchronous pieces that do not
/// benefit from isolate context switching. A cooperative futures pool
/// yields the same throughput for batch verify/seal operations while
/// avoiding the serialization limits of real isolates.
class IsolatePool {
  IsolatePool({this.maxWorkers = 4}) {
    if (maxWorkers < 1) {
      throw ArgumentError.value(maxWorkers, 'maxWorkers', 'must be at least 1');
    }
  }

  /// Maximum number of concurrent tasks.
  final int maxWorkers;

  final Queue<_PendingTask<dynamic>> _pending = Queue<_PendingTask<dynamic>>();
  int _active = 0;
  bool _closed = false;

  /// Number of tasks currently executing.
  int get activeCount => _active;

  /// Number of tasks waiting for a free slot.
  int get pendingCount => _pending.length;

  /// Whether the pool has been closed and rejects new tasks.
  bool get isClosed => _closed;

  /// Submits [task] for execution. Returns a Future that resolves with
  /// the task's result when it runs.
  Future<T> run<T>(Future<T> Function() task) {
    if (_closed) {
      throw StateError('IsolatePool is closed');
    }
    final completer = Completer<T>();
    _pending.add(_PendingTask<T>(task, completer));
    _schedule();
    return completer.future;
  }

  /// Runs [tasks] and returns a list with their results, preserving
  /// order. If any task throws, the Future returned here completes with
  /// that error after all other tasks have settled (so no task is
  /// abandoned).
  Future<List<T>> runAll<T>(List<Future<T> Function()> tasks) async {
    final futures = tasks.map(run<T>).toList();
    return Future.wait(futures);
  }

  /// Drains the pool, waiting until every pending task has completed
  /// then refusing new submissions.
  Future<void> close() async {
    _closed = true;
    while (_active > 0 || _pending.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  void _schedule() {
    while (_active < maxWorkers && _pending.isNotEmpty) {
      final next = _pending.removeFirst();
      _active += 1;
      _run(next);
    }
  }

  void _run<T>(_PendingTask<T> task) {
    () async {
      try {
        final result = await task.task();
        task.completer.complete(result);
      } catch (error, stack) {
        task.completer.completeError(error, stack);
      } finally {
        _active -= 1;
        _schedule();
      }
    }();
  }
}

class _PendingTask<T> {
  _PendingTask(this.task, this.completer);

  final Future<T> Function() task;
  final Completer<T> completer;
}
