import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

class _AppendCommand extends UndoableCommand {
  _AppendCommand(this.list, this.value);

  final List<int> list;
  final int value;

  @override
  String get label => 'Append $value';

  @override
  void do_() => list.add(value);

  @override
  void undo_() => list.remove(value);
}

void main() {
  group('UndoManager', () {
    test('execute applies the command and enables undo', () {
      final mgr = UndoManager();
      final list = <int>[];
      mgr.execute(_AppendCommand(list, 1));
      expect(list, [1]);
      expect(mgr.canUndo, isTrue);
      expect(mgr.canRedo, isFalse);
    });

    test('undo reverses commands and enables redo', () {
      final mgr = UndoManager();
      final list = <int>[];
      mgr.execute(_AppendCommand(list, 1));
      mgr.execute(_AppendCommand(list, 2));
      mgr.undo();
      expect(list, [1]);
      expect(mgr.canRedo, isTrue);
      mgr.redo();
      expect(list, [1, 2]);
    });

    test('executing a new command clears the redo stack', () {
      final mgr = UndoManager();
      final list = <int>[];
      mgr.execute(_AppendCommand(list, 1));
      mgr.undo();
      mgr.execute(_AppendCommand(list, 2));
      expect(mgr.canRedo, isFalse);
    });

    test('maxEntries caps the undo stack', () {
      final mgr = UndoManager(maxEntries: 3);
      final list = <int>[];
      for (var i = 0; i < 5; i++) {
        mgr.execute(_AppendCommand(list, i));
      }
      expect(mgr.undoStack.length, 3);
    });

    test('clear empties both stacks', () {
      final mgr = UndoManager();
      mgr.execute(_AppendCommand(<int>[], 1));
      mgr.clear();
      expect(mgr.canUndo, isFalse);
      expect(mgr.canRedo, isFalse);
    });
  });
}
