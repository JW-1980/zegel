import 'dart:io';

/// Lightweight CPU / memory resource monitor (improvement #86).
///
/// Reports process-level resource usage without pulling in any platform
/// channels or native plugins. Where the host OS exposes the information
/// (Linux via `/proc/self/status`, macOS via `task_info` equivalents,
/// Windows via `GetProcessMemoryInfo`) we surface what we can from
/// `dart:io` alone. When a value cannot be read it is returned as
/// `null`; callers should degrade gracefully.
class ResourceMonitor {
  ResourceMonitor._();

  /// Samples current memory usage in bytes. Returns `null` when the
  /// value cannot be determined on the current platform.
  static int? sampleResidentMemoryBytes() {
    if (Platform.isLinux) {
      return _linuxResident();
    }
    return null;
  }

  /// Samples a rough CPU percent from `/proc/self/stat` deltas. Because
  /// Dart doesn't expose kernel tick rates portably, callers must
  /// supply two snapshots taken at known wall-clock times and the
  /// function returns the difference divided by the elapsed interval.
  static double? sampleCpuPercent(
    CpuSnapshot previous,
    CpuSnapshot current,
  ) {
    final elapsed = current.wallClock.difference(previous.wallClock);
    if (elapsed.inMilliseconds <= 0) return null;
    final userDelta = current.userTicks - previous.userTicks;
    final systemDelta = current.systemTicks - previous.systemTicks;
    if (userDelta < 0 || systemDelta < 0) return null;
    final ticks = userDelta + systemDelta;
    // Standard USER_HZ on Linux is 100; approximate elsewhere.
    const usecPerTick = 10000; // 10 ms
    final busyMicros = ticks * usecPerTick;
    final percent = busyMicros / elapsed.inMicroseconds * 100.0;
    return percent.clamp(0.0, 100.0 * Platform.numberOfProcessors);
  }

  /// Captures a CPU snapshot for use with [sampleCpuPercent]. Returns
  /// `null` when the process statistics cannot be read.
  static CpuSnapshot? captureCpuSnapshot() {
    if (!Platform.isLinux) return null;
    try {
      final stat = File('/proc/self/stat').readAsStringSync();
      // The comm field is parenthesized and may contain spaces, so we
      // skip past the last ')' to find the remaining numeric fields.
      final end = stat.lastIndexOf(')');
      if (end < 0) return null;
      final fields = stat.substring(end + 2).split(' ');
      // After the 2nd field (end of comm), utime is at index 11 of the
      // original fields → index 11 - 2 = 9 here. Similarly stime is 10.
      if (fields.length < 15) return null;
      final utime = int.parse(fields[11]);
      final stime = int.parse(fields[12]);
      return CpuSnapshot(
        wallClock: DateTime.now().toUtc(),
        userTicks: utime,
        systemTicks: stime,
      );
    } catch (_) {
      return null;
    }
  }

  static int? _linuxResident() {
    try {
      final status = File('/proc/self/status').readAsStringSync();
      for (final line in status.split('\n')) {
        if (line.startsWith('VmRSS:')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final kb = int.tryParse(parts[1]);
            if (kb != null) return kb * 1024;
          }
        }
      }
    } catch (_) {
      // ignore
    }
    return null;
  }
}

class CpuSnapshot {
  const CpuSnapshot({
    required this.wallClock,
    required this.userTicks,
    required this.systemTicks,
  });

  final DateTime wallClock;
  final int userTicks;
  final int systemTicks;
}
