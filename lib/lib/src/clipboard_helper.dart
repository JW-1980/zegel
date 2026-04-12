/// Clipboard interaction helper (improvement #16).
///
/// The core library cannot actually touch the clipboard — that requires
/// a platform channel — but we can capture the *semantics* of a "copy"
/// action here and let the UI layer forward the call to its native API.
///
/// Each [ClipboardItem] encodes:
/// - The value that should be placed on the clipboard.
/// - A user-facing label, so the UI can show "Copied ‹Master key›!".
/// - Optional auto-clear semantics, so the UI knows when to wipe the
///   clipboard after the paste window closes.
class ClipboardHelper {
  ClipboardHelper._();

  /// Default auto-clear window for sensitive values (45 seconds).
  static const Duration defaultAutoClear = Duration(seconds: 45);

  /// Returns a [ClipboardItem] suitable for "copy this hash" use cases.
  static ClipboardItem hash(String hex, {String label = 'Hash'}) {
    return ClipboardItem(
      value: hex,
      label: label,
      autoClear: null,
      sensitive: false,
    );
  }

  /// Returns a [ClipboardItem] configured for sensitive data. Sensitive
  /// items have a shorter auto-clear window and can be paired with
  /// the UI's "clipboard cleared" toast.
  static ClipboardItem secret(
    String value, {
    String label = 'Secret',
    Duration autoClear = defaultAutoClear,
  }) {
    return ClipboardItem(
      value: value,
      label: label,
      autoClear: autoClear,
      sensitive: true,
    );
  }

  /// Returns a safe preview of the clipboard value for toast messages.
  /// Sensitive items are masked, non-sensitive ones are truncated.
  static String previewFor(ClipboardItem item) {
    if (item.sensitive) {
      if (item.value.length <= 4) return '•' * item.value.length;
      return '${item.value.substring(0, 2)}…${'•' * 4}';
    }
    if (item.value.length <= 40) return item.value;
    return '${item.value.substring(0, 37)}…';
  }
}

class ClipboardItem {
  const ClipboardItem({
    required this.value,
    required this.label,
    required this.autoClear,
    required this.sensitive,
  });

  /// The text that should land on the OS clipboard.
  final String value;

  /// Human label for toast / status bar messages.
  final String label;

  /// Auto-clear window. `null` means the value persists until the user
  /// copies something else.
  final Duration? autoClear;

  /// Whether the value should be treated as sensitive (masked preview,
  /// shorter auto-clear, clipboard-listener warning).
  final bool sensitive;
}
