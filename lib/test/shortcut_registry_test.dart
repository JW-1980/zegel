import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('Shortcut equality', () {
    test('compares modifiers and key case-insensitively', () {
      const a = Shortcut(modifiers: {ShortcutModifier.control}, key: 'S');
      const b = Shortcut(modifiers: {ShortcutModifier.control}, key: 's');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('ShortcutRegistry', () {
    test('register and lookup round trip', () {
      final reg = ShortcutRegistry();
      const shortcut = Shortcut(
        modifiers: {ShortcutModifier.control},
        key: 's',
      );
      reg.register(shortcut, 'action.seal');
      expect(reg.actionFor(shortcut), 'action.seal');
      expect(reg.shortcutFor('action.seal'), shortcut);
    });

    test('register throws on conflict', () {
      final reg = ShortcutRegistry();
      const shortcut = Shortcut(
        modifiers: {ShortcutModifier.control},
        key: 's',
      );
      reg.register(shortcut, 'action.seal');
      expect(() => reg.register(shortcut, 'action.other'), throwsArgumentError);
    });

    test('override replaces existing bindings silently', () {
      final reg = ShortcutRegistry();
      const shortcut = Shortcut(
        modifiers: {ShortcutModifier.control},
        key: 's',
      );
      reg.register(shortcut, 'action.seal');
      reg.override(shortcut, 'action.newer');
      expect(reg.actionFor(shortcut), 'action.newer');
    });

    test('defaults include common Zegel actions', () {
      final reg = ShortcutRegistry.defaults();
      expect(
        reg.actionFor(
          const Shortcut(modifiers: {ShortcutModifier.control}, key: 's'),
        ),
        'action.seal',
      );
      expect(
        reg.actionFor(
          const Shortcut(modifiers: {ShortcutModifier.control}, key: 'e'),
        ),
        'action.extract',
      );
    });

    test('displayLabel formats as expected', () {
      const shortcut = Shortcut(
        modifiers: {ShortcutModifier.control, ShortcutModifier.shift},
        key: 'n',
      );
      expect(shortcut.displayLabel, 'Ctrl+Shift+N');
    });
  });
}
