/// Safe view transformation for sensitive text (improvement #72).
///
/// Given a string that may contain private keys, passwords or other
/// secrets, returns a version with the interior obscured. The first and
/// last few characters are left visible so the user can still recognise
/// which value they are looking at, matching common "reveal on hover"
/// conventions.
class SafeView {
  SafeView._();

  /// Default mask character.
  static const String defaultMaskChar = '•';

  /// Minimum number of masked characters even when the original value
  /// is short (prevents a short secret from being fully visible after
  /// showing head/tail).
  static const int minMaskLength = 4;

  /// Obscures the middle of [value].
  ///
  /// - [visibleHead] characters at the start are kept.
  /// - [visibleTail] characters at the end are kept.
  /// - Everything between is replaced with [maskChar].
  ///
  /// If [value] is shorter than `visibleHead + visibleTail`, the result
  /// is entirely masked.
  static String obscure(
    String value, {
    int visibleHead = 4,
    int visibleTail = 4,
    String maskChar = defaultMaskChar,
  }) {
    if (visibleHead < 0 || visibleTail < 0) {
      throw ArgumentError('visible counts must be non-negative');
    }
    if (maskChar.isEmpty) {
      throw ArgumentError('maskChar must not be empty');
    }
    if (value.isEmpty) return value;

    final total = value.length;
    if (total <= visibleHead + visibleTail) {
      return maskChar * total;
    }

    final maskedLength = total - visibleHead - visibleTail;
    final minPadded = maskedLength < minMaskLength ? minMaskLength : maskedLength;
    final head = value.substring(0, visibleHead);
    final tail = value.substring(total - visibleTail);
    return '$head${maskChar * minPadded}$tail';
  }

  /// Obscures a full key or password (no visible head/tail), useful for
  /// passwords typed into a field.
  static String obscureFully(String value, {String maskChar = defaultMaskChar}) {
    return obscure(value, visibleHead: 0, visibleTail: 0, maskChar: maskChar);
  }

  /// Lists the regions of [value] that would be visible given the
  /// parameters. Useful for UI that draws head/tail in a different
  /// colour without re-running the obscure logic.
  static List<SafeViewRegion> regions(
    String value, {
    int visibleHead = 4,
    int visibleTail = 4,
  }) {
    if (value.isEmpty) return const <SafeViewRegion>[];
    final total = value.length;
    if (total <= visibleHead + visibleTail) {
      return <SafeViewRegion>[
        SafeViewRegion(start: 0, end: total, visible: false),
      ];
    }
    return <SafeViewRegion>[
      SafeViewRegion(start: 0, end: visibleHead, visible: true),
      SafeViewRegion(
        start: visibleHead,
        end: total - visibleTail,
        visible: false,
      ),
      SafeViewRegion(
        start: total - visibleTail,
        end: total,
        visible: true,
      ),
    ];
  }
}

class SafeViewRegion {
  const SafeViewRegion({
    required this.start,
    required this.end,
    required this.visible,
  });

  final int start;
  final int end;
  final bool visible;

  int get length => end - start;
}
