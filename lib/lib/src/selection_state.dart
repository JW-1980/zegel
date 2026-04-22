/// Bulk selection state model (improvement #18).
///
/// Backs the "select all / select none / invert selection" toolbar in
/// batch screens. The class is generic on the item type so callers can
/// reuse it for file lists, recipient lists, shortcut bindings, and so on.
///
/// The selection is stored as a `Set<T>` for O(1) lookup; the total set
/// of items drives "select all" behaviour.
class SelectionState<T> {
  SelectionState({Iterable<T>? items})
      : _items = <T>{...?items},
        _selected = <T>{};

  final Set<T> _items;
  final Set<T> _selected;

  /// All items currently tracked by this selection.
  Iterable<T> get items => List<T>.unmodifiable(_items);

  /// Currently selected items (unordered).
  Iterable<T> get selected => List<T>.unmodifiable(_selected);

  /// Number of items currently selected.
  int get selectedCount => _selected.length;

  /// Total items available for selection.
  int get itemCount => _items.length;

  /// True when every item is selected.
  bool get isAllSelected =>
      _items.isNotEmpty && _selected.length == _items.length;

  /// True when no item is selected.
  bool get isNoneSelected => _selected.isEmpty;

  /// Whether [item] is currently in the selected set.
  bool isSelected(T item) => _selected.contains(item);

  /// Adds [item] to the set of tracked items.
  void addItem(T item) {
    _items.add(item);
  }

  /// Removes [item] from both the tracked and selected sets.
  void removeItem(T item) {
    _items.remove(item);
    _selected.remove(item);
  }

  /// Replaces the full set of tracked items, preserving any selection
  /// that still overlaps with the new set.
  void setItems(Iterable<T> newItems) {
    _items
      ..clear()
      ..addAll(newItems);
    _selected.removeWhere((item) => !_items.contains(item));
  }

  /// Adds [item] to the selected set. Must already be part of [items].
  void select(T item) {
    if (!_items.contains(item)) {
      throw StateError('Cannot select item that is not in items: $item');
    }
    _selected.add(item);
  }

  /// Removes [item] from the selected set.
  void deselect(T item) {
    _selected.remove(item);
  }

  /// Flips the selection state of [item].
  void toggle(T item) {
    if (_selected.contains(item)) {
      _selected.remove(item);
    } else {
      select(item);
    }
  }

  /// Selects every tracked item.
  void selectAll() {
    _selected
      ..clear()
      ..addAll(_items);
  }

  /// Deselects every tracked item.
  void clear() => _selected.clear();

  /// Inverts the selection: every selected item becomes deselected and
  /// vice versa.
  void invert() {
    final next = _items.where((item) => !_selected.contains(item)).toSet();
    _selected
      ..clear()
      ..addAll(next);
  }
}
