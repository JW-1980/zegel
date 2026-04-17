/// Keyboard shortcut registry (improvement #11).
///
/// A platform-agnostic data model mapping `(modifiers, key)` tuples to
/// named actions. The Flutter app binds the registry to its
/// `CallbackShortcuts` widget, and the CLI can dump the registry into a
/// help screen. Keeping the data here (rather than inside the UI) makes
/// it testable without pulling in Flutter.
class ShortcutRegistry {
  ShortcutRegistry({Map<Shortcut, String>? initial})
      : _bindings = Map<Shortcut, String>.of(
          initial ?? const <Shortcut, String>{},
        );

  final Map<Shortcut, String> _bindings;

  /// Registers [shortcut] to trigger [actionId]. Throws [ArgumentError]
  /// if a different action is already bound to the same shortcut.
  void register(Shortcut shortcut, String actionId) {
    final existing = _bindings[shortcut];
    if (existing != null && existing != actionId) {
      throw ArgumentError(
        'Shortcut ${shortcut.displayLabel} is already bound to $existing',
      );
    }
    _bindings[shortcut] = actionId;
  }

  /// Replaces any existing binding for [shortcut] with [actionId].
  void override(Shortcut shortcut, String actionId) {
    _bindings[shortcut] = actionId;
  }

  /// Removes the binding for [shortcut]. Returns true if one existed.
  bool remove(Shortcut shortcut) => _bindings.remove(shortcut) != null;

  /// Returns the action id for [shortcut], or `null` if unbound.
  String? actionFor(Shortcut shortcut) => _bindings[shortcut];

  /// Returns the shortcut bound to [actionId], or `null`.
  Shortcut? shortcutFor(String actionId) {
    for (final entry in _bindings.entries) {
      if (entry.value == actionId) return entry.key;
    }
    return null;
  }

  /// Returns all bound shortcuts sorted by display label.
  List<ShortcutBinding> list() {
    final bindings = _bindings.entries
        .map((e) => ShortcutBinding(shortcut: e.key, actionId: e.value))
        .toList()
      ..sort(
        (a, b) =>
            a.shortcut.displayLabel.compareTo(b.shortcut.displayLabel),
      );
    return bindings;
  }

  /// The number of registered shortcuts.
  int get length => _bindings.length;

  /// Creates a registry with Zegel's default shortcuts: Ctrl+S to seal,
  /// Ctrl+O to open/verify, Ctrl+E to extract.
  factory ShortcutRegistry.defaults() {
    return ShortcutRegistry()
      ..override(
        const Shortcut(modifiers: {ShortcutModifier.control}, key: 's'),
        'action.seal',
      )
      ..override(
        const Shortcut(modifiers: {ShortcutModifier.control}, key: 'o'),
        'action.open',
      )
      ..override(
        const Shortcut(modifiers: {ShortcutModifier.control}, key: 'e'),
        'action.extract',
      )
      ..override(
        const Shortcut(modifiers: {ShortcutModifier.control}, key: 'k'),
        'action.keygen',
      )
      ..override(
        const Shortcut(modifiers: {ShortcutModifier.control}, key: 'f'),
        'action.find',
      )
      ..override(
        const Shortcut(modifiers: {ShortcutModifier.control}, key: ','),
        'action.settings',
      );
  }
}

class Shortcut {
  const Shortcut({required this.modifiers, required this.key});

  final Set<ShortcutModifier> modifiers;
  final String key;

  String get displayLabel {
    final mods = <String>[];
    if (modifiers.contains(ShortcutModifier.control)) mods.add('Ctrl');
    if (modifiers.contains(ShortcutModifier.shift)) mods.add('Shift');
    if (modifiers.contains(ShortcutModifier.alt)) mods.add('Alt');
    if (modifiers.contains(ShortcutModifier.meta)) mods.add('Meta');
    mods.add(key.toUpperCase());
    return mods.join('+');
  }

  @override
  bool operator ==(Object other) {
    if (other is! Shortcut) return false;
    if (other.key.toLowerCase() != key.toLowerCase()) return false;
    if (other.modifiers.length != modifiers.length) return false;
    return other.modifiers.containsAll(modifiers);
  }

  @override
  int get hashCode {
    var hash = key.toLowerCase().hashCode;
    for (final mod in modifiers) {
      hash ^= mod.hashCode;
    }
    return hash;
  }
}

enum ShortcutModifier { control, shift, alt, meta }

class ShortcutBinding {
  const ShortcutBinding({required this.shortcut, required this.actionId});

  final Shortcut shortcut;
  final String actionId;
}
