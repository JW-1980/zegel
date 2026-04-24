import 'dart:io';

import 'package:test/test.dart';
import 'package:zegel/zegel.dart';

void main() {
  group('ResourceMonitor', () {
    test('sampleResidentMemoryBytes returns non-null on Linux', () {
      if (!Platform.isLinux) return;
      final rss = ResourceMonitor.sampleResidentMemoryBytes();
      expect(rss, isNotNull);
      expect(rss, greaterThan(0));
    });

    test('captureCpuSnapshot returns ticks on Linux', () {
      if (!Platform.isLinux) return;
      final snap = ResourceMonitor.captureCpuSnapshot();
      expect(snap, isNotNull);
      expect(snap!.userTicks, greaterThanOrEqualTo(0));
    });

    test('sampleCpuPercent handles inverted snapshots gracefully', () {
      final a = CpuSnapshot(
        wallClock: DateTime.utc(2026, 1, 1, 12, 0, 0),
        userTicks: 100,
        systemTicks: 20,
      );
      final b = CpuSnapshot(
        wallClock: DateTime.utc(2026, 1, 1, 12, 0, 1),
        userTicks: 120,
        systemTicks: 25,
      );
      final percent = ResourceMonitor.sampleCpuPercent(a, b);
      expect(percent, isNotNull);
      expect(percent!, greaterThanOrEqualTo(0));
    });

    test('sampleCpuPercent returns null for zero elapsed time', () {
      final ts = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final snap = CpuSnapshot(wallClock: ts, userTicks: 100, systemTicks: 20);
      expect(ResourceMonitor.sampleCpuPercent(snap, snap), isNull);
    });
  });
}
