import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('SelectionState<String>', () {
    SelectionState<String> makeState([List<String>? items]) =>
        SelectionState<String>(items: items ?? ['a', 'b', 'c', 'd', 'e']);

    group('initial state', () {
      test('no items selected when constructed without items', () {
        final s = SelectionState<String>();
        expect(s.selectedCount, 0);
        expect(s.itemCount, 0);
        expect(s.isNoneSelected, isTrue);
      });

      test('constructed items are tracked but none selected', () {
        final s = makeState();
        expect(s.itemCount, 5);
        expect(s.selectedCount, 0);
        expect(s.isNoneSelected, isTrue);
        expect(s.isAllSelected, isFalse);
      });

      test('items getter returns all tracked items', () {
        final s = makeState(['x', 'y', 'z']);
        expect(s.items, containsAll(['x', 'y', 'z']));
      });
    });

    group('select', () {
      test('adds item to selected set', () {
        final s = makeState();
        s.select('a');
        expect(s.isSelected('a'), isTrue);
        expect(s.selectedCount, 1);
      });

      test('selecting the same item twice does not duplicate it', () {
        final s = makeState();
        s.select('b');
        s.select('b');
        expect(s.selectedCount, 1);
      });

      test('throws StateError when item is not in items', () {
        final s = makeState();
        expect(() => s.select('z'), throwsStateError);
      });

      test('selecting all items makes isAllSelected true', () {
        final s = makeState(['p', 'q']);
        s.select('p');
        s.select('q');
        expect(s.isAllSelected, isTrue);
      });
    });

    group('deselect', () {
      test('removes item from selected set', () {
        final s = makeState();
        s.select('a');
        s.deselect('a');
        expect(s.isSelected('a'), isFalse);
        expect(s.selectedCount, 0);
      });

      test('deselectng unselected item is a no-op', () {
        final s = makeState();
        expect(() => s.deselect('a'), returnsNormally);
        expect(s.selectedCount, 0);
      });

      test('deselect does not remove item from tracked set', () {
        final s = makeState();
        s.select('c');
        s.deselect('c');
        expect(s.itemCount, 5);
        expect(s.items, contains('c'));
      });
    });

    group('toggle', () {
      test('selects an unselected item', () {
        final s = makeState();
        s.toggle('a');
        expect(s.isSelected('a'), isTrue);
      });

      test('deselects a selected item', () {
        final s = makeState();
        s.select('a');
        s.toggle('a');
        expect(s.isSelected('a'), isFalse);
      });

      test('double toggle returns to original state', () {
        final s = makeState();
        s.toggle('b');
        s.toggle('b');
        expect(s.isSelected('b'), isFalse);
      });

      test('throws StateError when item is not tracked', () {
        final s = makeState();
        expect(() => s.toggle('zzz'), throwsStateError);
      });
    });

    group('selectAll', () {
      test('selects every tracked item', () {
        final s = makeState();
        s.selectAll();
        expect(s.selectedCount, s.itemCount);
        expect(s.isAllSelected, isTrue);
      });

      test('is a no-op when item set is empty', () {
        final s = SelectionState<String>();
        expect(s.selectAll, returnsNormally);
        expect(s.selectedCount, 0);
      });

      test('calling selectAll twice is idempotent', () {
        final s = makeState();
        s.selectAll();
        s.selectAll();
        expect(s.selectedCount, s.itemCount);
      });

      test('isAllSelected is false for empty item set', () {
        final s = SelectionState<String>();
        s.selectAll();
        expect(s.isAllSelected, isFalse); // empty set never isAllSelected
      });
    });

    group('clear', () {
      test('deselects all items', () {
        final s = makeState();
        s.selectAll();
        s.clear();
        expect(s.selectedCount, 0);
        expect(s.isNoneSelected, isTrue);
      });

      test('clear does not remove items from the tracked set', () {
        final s = makeState();
        s.selectAll();
        s.clear();
        expect(s.itemCount, 5);
      });

      test('clear on empty selection is a no-op', () {
        final s = makeState();
        expect(s.clear, returnsNormally);
        expect(s.selectedCount, 0);
      });
    });

    group('invert', () {
      test('inverts an empty selection to all selected', () {
        final s = makeState(['x', 'y', 'z']);
        s.invert();
        expect(s.isAllSelected, isTrue);
      });

      test('inverts a full selection to none selected', () {
        final s = makeState(['x', 'y', 'z']);
        s.selectAll();
        s.invert();
        expect(s.isNoneSelected, isTrue);
      });

      test('inverts a partial selection correctly', () {
        final s = makeState(['x', 'y', 'z']);
        s.select('x');
        s.invert();
        // 'x' was selected, now should be deselected.
        expect(s.isSelected('x'), isFalse);
        // 'y' and 'z' were not selected, now should be.
        expect(s.isSelected('y'), isTrue);
        expect(s.isSelected('z'), isTrue);
        expect(s.selectedCount, 2);
      });

      test('double invert returns to original selection', () {
        final s = makeState(['a', 'b', 'c']);
        s.select('a');
        s.invert();
        s.invert();
        expect(s.isSelected('a'), isTrue);
        expect(s.isSelected('b'), isFalse);
        expect(s.isSelected('c'), isFalse);
      });

      test('invert on empty item set is a no-op', () {
        final s = SelectionState<String>();
        expect(s.invert, returnsNormally);
        expect(s.selectedCount, 0);
      });
    });

    group('isAllSelected', () {
      test('false when nothing is selected', () {
        expect(makeState().isAllSelected, isFalse);
      });

      test('true when all items are selected', () {
        final s = makeState();
        s.selectAll();
        expect(s.isAllSelected, isTrue);
      });

      test('false when one item remains unselected', () {
        final s = makeState(['a', 'b', 'c']);
        s.select('a');
        s.select('b');
        expect(s.isAllSelected, isFalse);
      });

      test('false for empty item set (guard against vacuous truth)', () {
        expect(SelectionState<String>().isAllSelected, isFalse);
      });
    });

    group('removeItem', () {
      test('removes item from tracked set', () {
        final s = makeState(['a', 'b', 'c']);
        s.removeItem('b');
        expect(s.itemCount, 2);
        expect(s.items, isNot(contains('b')));
      });

      test('also removes item from selection if it was selected', () {
        final s = makeState(['a', 'b', 'c']);
        s.select('b');
        s.removeItem('b');
        expect(s.isSelected('b'), isFalse);
        expect(s.selectedCount, 0);
      });

      test('removing untracked item is a no-op', () {
        final s = makeState(['a', 'b']);
        expect(() => s.removeItem('z'), returnsNormally);
        expect(s.itemCount, 2);
      });

      test('removing last item leaves state empty', () {
        final s = SelectionState<String>(items: ['only']);
        s.select('only');
        s.removeItem('only');
        expect(s.itemCount, 0);
        expect(s.selectedCount, 0);
      });

      test('isAllSelected reflects removal correctly', () {
        final s = makeState(['a', 'b']);
        s.selectAll();
        s.removeItem('a'); // now only 'b' tracked and still selected
        expect(s.isAllSelected, isTrue);
      });
    });

    group('setItems', () {
      test('replaces tracked items with new set', () {
        final s = makeState(['a', 'b', 'c']);
        s.setItems(['x', 'y']);
        expect(s.itemCount, 2);
        expect(s.items, containsAll(['x', 'y']));
        expect(s.items, isNot(contains('a')));
      });

      test('preserves selection for items that remain in the new set', () {
        final s = makeState(['a', 'b', 'c']);
        s.select('a');
        s.select('b');
        s.setItems(['a', 'c', 'd']); // 'b' is removed, 'a' survives
        expect(s.isSelected('a'), isTrue);
        expect(s.isSelected('b'), isFalse); // removed from tracking
        expect(s.selectedCount, 1);
      });

      test('clears all selection when new items have no overlap', () {
        final s = makeState(['a', 'b', 'c']);
        s.selectAll();
        s.setItems(['x', 'y', 'z']);
        expect(s.selectedCount, 0);
      });

      test('setting empty list clears items and selection', () {
        final s = makeState(['a', 'b']);
        s.selectAll();
        s.setItems([]);
        expect(s.itemCount, 0);
        expect(s.selectedCount, 0);
      });

      test('setting the same items is idempotent', () {
        final s = makeState(['a', 'b', 'c']);
        s.select('a');
        s.setItems(['a', 'b', 'c']);
        expect(s.itemCount, 3);
        expect(s.isSelected('a'), isTrue);
      });
    });

    group('selected getter', () {
      test('returns only the currently selected items', () {
        final s = makeState(['a', 'b', 'c']);
        s.select('a');
        s.select('c');
        expect(s.selected, containsAll(['a', 'c']));
        expect(s.selected, isNot(contains('b')));
      });
    });

    group('generic type parameter', () {
      test('works with integer items', () {
        final s = SelectionState<int>(items: [1, 2, 3]);
        s.select(2);
        expect(s.isSelected(2), isTrue);
        expect(s.isSelected(1), isFalse);
        s.toggle(2);
        expect(s.isSelected(2), isFalse);
      });
    });
  });
}
