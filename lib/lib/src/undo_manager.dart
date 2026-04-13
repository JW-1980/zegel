/// Generic undo/redo manager (improvement #41).
///
/// Commands implement [UndoableCommand.do_] and [UndoableCommand.undo_].
/// The manager keeps a bounded undo stack and a redo stack that is
/// cleared whenever a new command is executed. This is the backbone of
/// "Undo" functionality for batch lists, redaction selections, and
/// template editing screens.
abstract class UndoableCommand {
  /// Label displayed in the UI (e.g. "Remove file alpha.pdf").
  String get label;

  /// Applies the command.
  void do_();

  /// Reverts the command.
  void undo_();
}

class UndoManager {
  UndoManager({this.maxEntries = 50});

  /// Maximum number of undoable commands retained. Older commands are
  /// dropped silently.
  final int maxEntries;

  final List<UndoableCommand> _undoStack = <UndoableCommand>[];
  final List<UndoableCommand> _redoStack = <UndoableCommand>[];

  /// True if there is at least one command that can be undone.
  bool get canUndo => _undoStack.isNotEmpty;

  /// True if there is at least one command that can be redone.
  bool get canRedo => _redoStack.isNotEmpty;

  /// Label of the next command to be undone, or `null` if none.
  String? get undoLabel => canUndo ? _undoStack.last.label : null;

  /// Label of the next command to be redone, or `null` if none.
  String? get redoLabel => canRedo ? _redoStack.last.label : null;

  /// Executes [command] and pushes it onto the undo stack. Clears the
  /// redo stack, matching the behaviour of most text editors.
  void execute(UndoableCommand command) {
    command.do_();
    _undoStack.add(command);
    _redoStack.clear();
    while (_undoStack.length > maxEntries) {
      _undoStack.removeAt(0);
    }
  }

  /// Undoes the most recent command. Returns the command if one was
  /// undone, or `null` if the stack was empty.
  UndoableCommand? undo() {
    if (_undoStack.isEmpty) return null;
    final command = _undoStack.removeLast();
    command.undo_();
    _redoStack.add(command);
    return command;
  }

  /// Re-applies the last undone command. Returns the command if one was
  /// redone, or `null` if the redo stack was empty.
  UndoableCommand? redo() {
    if (_redoStack.isEmpty) return null;
    final command = _redoStack.removeLast();
    command.do_();
    _undoStack.add(command);
    return command;
  }

  /// Clears both stacks.
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }

  /// Exposes the undo stack for inspection. Most callers should use
  /// [canUndo] / [undoLabel].
  List<UndoableCommand> get undoStack =>
      List<UndoableCommand>.unmodifiable(_undoStack);

  /// Exposes the redo stack for inspection.
  List<UndoableCommand> get redoStack =>
      List<UndoableCommand>.unmodifiable(_redoStack);
}
