import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('ThemeScheduler', () {
    group('alwaysLight mode', () {
      const scheduler = ThemeScheduler(mode: ThemeScheduleMode.alwaysLight);

      test('returns light regardless of time', () {
        expect(
          scheduler.currentThemeAt(DateTime(2026, 1, 1, 2, 0)),
          ThemeBrightness.light,
        );
        expect(
          scheduler.currentThemeAt(DateTime(2026, 1, 1, 22, 0)),
          ThemeBrightness.light,
        );
      });

      test('ignores systemBrightness parameter', () {
        expect(
          scheduler.currentThemeAt(
            DateTime(2026, 1, 1, 12, 0),
            systemBrightness: ThemeBrightness.dark,
          ),
          ThemeBrightness.light,
        );
      });

      test('nextTransitionAfter returns null', () {
        expect(scheduler.nextTransitionAfter(DateTime(2026, 1, 1, 12, 0)), isNull);
      });
    });

    group('alwaysDark mode', () {
      const scheduler = ThemeScheduler(mode: ThemeScheduleMode.alwaysDark);

      test('returns dark regardless of time', () {
        expect(
          scheduler.currentThemeAt(DateTime(2026, 1, 1, 10, 0)),
          ThemeBrightness.dark,
        );
        expect(
          scheduler.currentThemeAt(DateTime(2026, 1, 1, 14, 30)),
          ThemeBrightness.dark,
        );
      });

      test('ignores systemBrightness parameter', () {
        expect(
          scheduler.currentThemeAt(
            DateTime(2026, 1, 1, 12, 0),
            systemBrightness: ThemeBrightness.light,
          ),
          ThemeBrightness.dark,
        );
      });

      test('nextTransitionAfter returns null', () {
        expect(scheduler.nextTransitionAfter(DateTime(2026, 1, 1, 12, 0)), isNull);
      });
    });

    group('system mode', () {
      const scheduler = ThemeScheduler(mode: ThemeScheduleMode.system);

      test('forwards systemBrightness.light', () {
        expect(
          scheduler.currentThemeAt(
            DateTime(2026, 1, 1, 12, 0),
            systemBrightness: ThemeBrightness.light,
          ),
          ThemeBrightness.light,
        );
      });

      test('forwards systemBrightness.dark', () {
        expect(
          scheduler.currentThemeAt(
            DateTime(2026, 1, 1, 12, 0),
            systemBrightness: ThemeBrightness.dark,
          ),
          ThemeBrightness.dark,
        );
      });

      test('uses default systemBrightness light when not supplied', () {
        expect(
          scheduler.currentThemeAt(DateTime(2026, 1, 1, 12, 0)),
          ThemeBrightness.light,
        );
      });

      test('nextTransitionAfter returns null', () {
        expect(scheduler.nextTransitionAfter(DateTime(2026, 1, 1, 12, 0)), isNull);
      });
    });

    group('timeOfDay mode — normal schedule (light 07:00, dark 20:00)', () {
      // lightStart=07:00, darkStart=20:00
      const scheduler = ThemeScheduler(mode: ThemeScheduleMode.timeOfDay);

      test('morning is light (08:00)', () {
        expect(
          scheduler.currentThemeAt(DateTime(2026, 6, 1, 8, 0)),
          ThemeBrightness.light,
        );
      });

      test('afternoon is light (13:30)', () {
        expect(
          scheduler.currentThemeAt(DateTime(2026, 6, 1, 13, 30)),
          ThemeBrightness.light,
        );
      });

      test('evening is dark (21:00)', () {
        expect(
          scheduler.currentThemeAt(DateTime(2026, 6, 1, 21, 0)),
          ThemeBrightness.dark,
        );
      });

      test('midnight is dark (00:00)', () {
        expect(
          scheduler.currentThemeAt(DateTime(2026, 6, 1, 0, 0)),
          ThemeBrightness.dark,
        );
      });

      test('just before lightStart is dark (06:59)', () {
        expect(
          scheduler.currentThemeAt(DateTime(2026, 6, 1, 6, 59)),
          ThemeBrightness.dark,
        );
      });

      test('exactly at lightStart is light (07:00)', () {
        expect(
          scheduler.currentThemeAt(DateTime(2026, 6, 1, 7, 0)),
          ThemeBrightness.light,
        );
      });

      test('exactly at darkStart is dark (20:00)', () {
        expect(
          scheduler.currentThemeAt(DateTime(2026, 6, 1, 20, 0)),
          ThemeBrightness.dark,
        );
      });

      test('just before darkStart is light (19:59)', () {
        expect(
          scheduler.currentThemeAt(DateTime(2026, 6, 1, 19, 59)),
          ThemeBrightness.light,
        );
      });
    });

    group('nextTransitionAfter — timeOfDay mode', () {
      const scheduler = ThemeScheduler(
        mode: ThemeScheduleMode.timeOfDay,
        lightStart: TimeOfDay(hour: 7, minute: 0),
        darkStart: TimeOfDay(hour: 20, minute: 0),
      );

      test('returns lightStart when reference is before it', () {
        final ref = DateTime(2026, 6, 1, 5, 0); // 05:00
        final next = scheduler.nextTransitionAfter(ref);
        expect(next, isNotNull);
        expect(next!.hour, 7);
        expect(next.minute, 0);
        expect(next.day, ref.day);
      });

      test('returns darkStart when reference is between light and dark starts', () {
        final ref = DateTime(2026, 6, 1, 12, 0); // 12:00
        final next = scheduler.nextTransitionAfter(ref);
        expect(next, isNotNull);
        expect(next!.hour, 20);
        expect(next.minute, 0);
        expect(next.day, ref.day);
      });

      test('returns next day lightStart when both transitions have passed', () {
        final ref = DateTime(2026, 6, 1, 23, 0); // 23:00
        final next = scheduler.nextTransitionAfter(ref);
        expect(next, isNotNull);
        expect(next!.day, 2); // next day
        expect(next.hour, 7);
        expect(next.minute, 0);
      });

      test('reference exactly at lightStart returns darkStart same day', () {
        final ref = DateTime(2026, 6, 1, 7, 0);
        final next = scheduler.nextTransitionAfter(ref);
        expect(next, isNotNull);
        expect(next!.hour, 20);
        expect(next.day, ref.day);
      });

      test('reference exactly at darkStart returns next day lightStart', () {
        final ref = DateTime(2026, 6, 1, 20, 0);
        final next = scheduler.nextTransitionAfter(ref);
        expect(next, isNotNull);
        expect(next!.day, 2);
        expect(next.hour, 7);
      });
    });

    group('edge cases', () {
      test('equal darkStart and lightStart always returns light', () {
        const scheduler = ThemeScheduler(
          mode: ThemeScheduleMode.timeOfDay,
          lightStart: TimeOfDay(hour: 8, minute: 0),
          darkStart: TimeOfDay(hour: 8, minute: 0),
        );
        expect(
          scheduler.currentThemeAt(DateTime(2026, 1, 1, 8, 0)),
          ThemeBrightness.light,
        );
        expect(
          scheduler.currentThemeAt(DateTime(2026, 1, 1, 20, 0)),
          ThemeBrightness.light,
        );
      });

      test('TimeOfDay.fromDateTime extracts hour and minute', () {
        final dt = DateTime(2026, 3, 15, 14, 37);
        final tod = TimeOfDay.fromDateTime(dt);
        expect(tod.hour, 14);
        expect(tod.minute, 37);
      });

      test('TimeOfDay.toString pads single digits', () {
        const tod = TimeOfDay(hour: 7, minute: 5);
        expect(tod.toString(), '07:05');
      });

      test('ThemeScheduler default mode is system', () {
        const s = ThemeScheduler();
        expect(s.mode, ThemeScheduleMode.system);
      });

      test('ThemeScheduler default darkStart is 20:00', () {
        const s = ThemeScheduler();
        expect(s.darkStart.hour, 20);
        expect(s.darkStart.minute, 0);
      });

      test('ThemeScheduler default lightStart is 07:00', () {
        const s = ThemeScheduler();
        expect(s.lightStart.hour, 7);
        expect(s.lightStart.minute, 0);
      });
    });
  });
}
