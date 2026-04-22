import 'dart:io';

/// Hardware & OS capability detection (improvements #34 and #37).
///
/// Returns a best-effort snapshot of the machine running Zegel so the
/// application can size background isolate pools, choose block sizes,
/// and report platform information for troubleshooting telemetry.
///
/// Everything is read from `dart:io` — no platform channels required.
class HardwareInfo {
  const HardwareInfo({
    required this.processorCount,
    required this.operatingSystem,
    required this.operatingSystemVersion,
    required this.hostname,
    required this.architecture,
    required this.dartVersion,
    required this.localHostname,
  });

  /// Physical CPU cores as reported by `Platform.numberOfProcessors`.
  final int processorCount;

  /// Operating-system identifier (`linux`, `macos`, `windows`, ...).
  final String operatingSystem;

  /// OS version string.
  final String operatingSystemVersion;

  /// Host name.
  final String hostname;

  /// Process architecture, inferred from environment variables or `uname`.
  /// Falls back to `"unknown"` when it cannot be determined.
  final String architecture;

  /// Dart runtime version.
  final String dartVersion;

  /// Local hostname short form (first label).
  final String localHostname;

  /// Probes the current environment for hardware and OS information.
  static HardwareInfo detect() {
    final host = Platform.localHostname;
    return HardwareInfo(
      processorCount: Platform.numberOfProcessors,
      operatingSystem: Platform.operatingSystem,
      operatingSystemVersion: Platform.operatingSystemVersion,
      hostname: host,
      architecture: _detectArchitecture(),
      dartVersion: Platform.version,
      localHostname: host.split('.').first,
    );
  }

  /// Recommends a degree of parallelism for batch operations given the
  /// number of CPU cores detected. Leaves one core free for the UI.
  int recommendedBatchConcurrency() {
    if (processorCount <= 1) return 1;
    if (processorCount <= 2) return 2;
    return processorCount - 1;
  }

  /// Recommends a block size in bytes based on the detected environment.
  /// Larger blocks amortize overhead on powerful machines; smaller ones
  /// avoid memory pressure on constrained devices.
  int recommendedBlockSizeBytes() {
    if (processorCount >= 8) return 262144; // 256 KB
    if (processorCount >= 4) return 131072; // 128 KB
    if (processorCount >= 2) return 65536; //  64 KB
    return 32768; //  32 KB
  }

  Map<String, dynamic> toJson() => {
        'processor_count': processorCount,
        'operating_system': operatingSystem,
        'operating_system_version': operatingSystemVersion,
        'hostname': hostname,
        'architecture': architecture,
        'dart_version': dartVersion,
        'local_hostname': localHostname,
        'recommended_batch_concurrency': recommendedBatchConcurrency(),
        'recommended_block_size_bytes': recommendedBlockSizeBytes(),
      };

  static String _detectArchitecture() {
    final env = Platform.environment;
    final candidates = [
      env['PROCESSOR_ARCHITECTURE'], // Windows
      env['HOSTTYPE'], // Some shells
      env['MACHTYPE'], // Bash
    ];
    for (final c in candidates) {
      if (c != null && c.isNotEmpty) return c.toLowerCase();
    }
    // Fallback: infer from Dart's version string, which contains
    // "<arch>_<os>" like "linux_x64" or "macos_arm64".
    final version = Platform.version;
    final match = RegExp(r'"([^"]+)"').firstMatch(version);
    if (match != null) {
      final token = match.group(1)!;
      if (token.contains('arm64')) return 'arm64';
      if (token.contains('x64')) return 'x64';
      if (token.contains('ia32')) return 'ia32';
    }
    return 'unknown';
  }
}
