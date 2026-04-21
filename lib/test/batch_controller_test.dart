import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('BatchController', () {
    test('starts in running state', () {
      final c = BatchController();
      expect(c.state, BatchState.running);
      expect(c.isRunning, isTrue);
    });

    test('pause transitions to paused, resume back to running', () {
      final c = BatchController();
      c.pause();
      expect(c.state, BatchState.paused);
      c.resume();
      expect(c.state, BatchState.running);
    });

    test('awaitResume yields immediately when running', () async {
      final c = BatchController();
      await c.awaitResume();
      expect(c.isRunning, isTrue);
    });

    test('awaitResume blocks when paused until resumed', () async {
      final c = BatchController();
      c.pause();
      var resumed = false;
      final future = c.awaitResume().then((_) => resumed = true);
      // Should not be resumed yet.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(resumed, isFalse);
      c.resume();
      await future;
      expect(resumed, isTrue);
    });

    test('cancel transitions to cancelled and unblocks awaitResume', () async {
      final c = BatchController();
      c.pause();
      final future = c.awaitResume();
      c.cancel();
      await future;
      expect(c.state, BatchState.cancelled);
      expect(c.isCancelled, isTrue);
    });

    test('complete transitions to completed state', () async {
      final c = BatchController();
      c.complete();
      expect(c.state, BatchState.completed);
      await c.close();
    });

    test('stream emits state transitions', () async {
      final c = BatchController();
      final received = <BatchState>[];
      c.stream.listen(received.add);
      c.pause();
      c.resume();
      c.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(
          received,
          containsAllInOrder([
            BatchState.paused,
            BatchState.running,
            BatchState.cancelled,
          ]));
    });
  });
}
