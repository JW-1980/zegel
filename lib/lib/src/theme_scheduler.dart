/// Automatic dark/light theme scheduler (improvement #1).
///
/// Tells the UI which theme to use at a given moment based on a simple,
/// cross-platform schedule. Three strategies are supported:
/// - `system`: follow the OS-reported theme (the UI decides how to read
///   that; the scheduler simply forwards a given [systemBrightness]).
/// - `time-of-day`: switch at configurable sunrise/sunset times.
/// - `always-dark` / `always-light`: static overrides.
///
/// The class has no Flutter imports so it can be unit-tested without a
/// framework. The Flutter app binds `currentThemeAt(DateTime.now())` to
/// its `ThemeMode`.
class ThemeScheduler {
  const ThemeScheduler({
    this.mode = ThemeScheduleMode.system,
    this.darkStart = const TimeOfDay(hour: 20, minute: 0),
    this.lightStart = const TimeOfDay(hour: 7, minute: 0),
  });

  final ThemeScheduleMode mode;
  final TimeOfDay darkStart;
  final TimeOfDay lightStart;

  /// Returns the brightness to use at [time]. [systemBrightness] must be
  /// provided for [ThemeScheduleMode.system] and is ignored otherwise.
  ThemeBrightness currentThemeAt(
    DateTime time, {
    ThemeBrightness systemBrightness = ThemeBrightness.light,
  }) {
    switch (mode) {
      case ThemeScheduleMode.alwaysLight:
        return ThemeBrightness.light;
      case ThemeScheduleMode.alwaysDark:
        return ThemeBrightness.dark;
      case ThemeScheduleMode.system:
        return systemBrightness;
      case ThemeScheduleMode.timeOfDay:
        return _isDarkAt(TimeOfDay.fromDateTime(time))
            ? ThemeBrightness.dark
            : ThemeBrightness.light;
    }
  }

  /// Returns the next [DateTime] at which the theme would flip if the
  /// mode is [ThemeScheduleMode.timeOfDay]. Returns `null` for the
  /// static modes.
  DateTime? nextTransitionAfter(DateTime reference) {
    if (mode != ThemeScheduleMode.timeOfDay) return null;
    final base = DateTime(reference.year, reference.month, reference.day);
    final candidates = <DateTime>[
      base.add(Duration(hours: lightStart.hour, minutes: lightStart.minute)),
      base.add(Duration(hours: darkStart.hour, minutes: darkStart.minute)),
    ];
    for (final candidate in candidates) {
      if (candidate.isAfter(reference)) return candidate;
    }
    // Both times have passed today — return tomorrow's first event.
    return candidates.first.add(const Duration(days: 1));
  }

  bool _isDarkAt(TimeOfDay current) {
    final now = current._minutes;
    final dark = darkStart._minutes;
    final light = lightStart._minutes;
    if (dark == light) return false;
    if (dark > light) {
      // Normal case: light in the morning, dark in the evening.
      return now >= dark || now < light;
    }
    // Inverted (e.g. dark 3am -> light 5am) — midnight to lightStart
    // is dark, lightStart to darkStart is dark too when dark < light.
    return now >= dark && now < light;
  }
}

enum ThemeScheduleMode { system, alwaysLight, alwaysDark, timeOfDay }

enum ThemeBrightness { light, dark }

class TimeOfDay {
  const TimeOfDay({required this.hour, required this.minute})
    : assert(hour >= 0 && hour < 24, 'hour out of range'),
      assert(minute >= 0 && minute < 60, 'minute out of range');

  factory TimeOfDay.fromDateTime(DateTime dt) =>
      TimeOfDay(hour: dt.hour, minute: dt.minute);

  final int hour;
  final int minute;

  int get _minutes => hour * 60 + minute;

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
