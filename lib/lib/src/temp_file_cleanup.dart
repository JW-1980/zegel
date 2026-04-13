import 'dart:io';

import 'secure_memory.dart';

/// Automatic cleanup of temporary unsealed files (improvement #26).
///
/// When the GUI or CLI extracts a sealed file to inspect it, the plaintext
/// often lands in a temp directory. This helper tracks those files, can
/// securely overwrite them, and sweeps them away when the session ends or
/// after a configurable age.
class TempFileCleanup {
  TempFileCleanup({
    required this.directory,
    this.maxAge = const Duration(hours: 1),
    this.secureWipe = true,
  });

  /// Root directory where managed temp files live.
  final String directory;

  /// Maximum age before a file is eligible for sweeping.
  final Duration maxAge;

  /// Whether to overwrite file contents before deletion.
  final bool secureWipe;

  final Set<String> _tracked = <String>{};

  Directory get _dir {
    final d = Directory(directory);
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// Creates and tracks a new temporary file inside [directory]. Returns
  /// the full path. The file is created empty.
  String createTempFile(String basename) {
    final path = '${_dir.path}${Platform.pathSeparator}$basename';
    final file = File(path);
    if (!file.existsSync()) file.createSync();
    _tracked.add(path);
    return path;
  }

  /// Adds an existing file to the tracked set so it participates in
  /// [sweep] and [clearAll].
  void track(String path) => _tracked.add(path);

  /// Number of tracked files.
  int get trackedCount => _tracked.length;

  /// Read-only view of tracked paths.
  Iterable<String> get trackedPaths => List<String>.unmodifiable(_tracked);

  /// Removes expired files from the tracked set and disk. Returns the
  /// list of paths that were deleted.
  List<String> sweep({DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).subtract(maxAge);
    final deleted = <String>[];
    final stillTracked = <String>{};
    for (final path in _tracked) {
      final file = File(path);
      if (!file.existsSync()) continue;
      final stat = file.statSync();
      if (stat.modified.isBefore(cutoff)) {
        _delete(file);
        deleted.add(path);
      } else {
        stillTracked.add(path);
      }
    }
    _tracked
      ..clear()
      ..addAll(stillTracked);
    return deleted;
  }

  /// Deletes every tracked file. Returns the number removed.
  int clearAll() {
    var count = 0;
    for (final path in _tracked) {
      final file = File(path);
      if (file.existsSync()) {
        _delete(file);
        count += 1;
      }
    }
    _tracked.clear();
    return count;
  }

  void _delete(File file) {
    if (secureWipe) {
      try {
        final length = file.lengthSync();
        if (length > 0) {
          final sink = file.openSync(mode: FileMode.write);
          try {
            final random = SecureMemory.randomBytes(length);
            sink.writeFromSync(random);
            final zeros = List<int>.filled(length, 0);
            sink.setPositionSync(0);
            sink.writeFromSync(zeros);
          } finally {
            sink.closeSync();
          }
        }
      } catch (_) {
        // Secure wipe is best-effort; proceed to unlink even on failure.
      }
    }
    try {
      file.deleteSync();
    } catch (_) {
      // Ignore — caller may have removed the file already.
    }
  }
}
