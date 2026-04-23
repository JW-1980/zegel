import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Scheduled key backup planner (improvement #23).
///
/// Describes a backup schedule and performs a backup pass on demand. The
/// planner copies a set of key files into a destination directory under
/// timestamped subfolders, records a manifest of SHA-256 hashes, and
/// prunes older snapshots when the retention count is exceeded.
///
/// The planner is deliberately agnostic to secret material — it never
/// decodes keys; it only copies bytes and hashes them. Encryption of the
/// destination directory is the caller's responsibility.
class KeyBackupPlanner {
  KeyBackupPlanner({
    required this.sourcePaths,
    required this.destinationDirectory,
    this.retainSnapshots = 5,
  });

  /// Absolute paths of the key files to back up.
  final List<String> sourcePaths;

  /// Directory where timestamped snapshots are written.
  final String destinationDirectory;

  /// Maximum number of snapshots kept. Older snapshots are pruned.
  final int retainSnapshots;

  /// Runs a backup pass. Returns the [KeyBackupResult] describing the
  /// snapshot that was just created (or loaded from disk if the backup
  /// was skipped because nothing changed).
  KeyBackupResult backupNow({DateTime? now, bool skipIfUnchanged = true}) {
    final timestamp = (now ?? DateTime.now().toUtc()).toUtc();
    final snapshotName = _snapshotName(timestamp);
    final destDir = Directory(
      '$destinationDirectory${Platform.pathSeparator}$snapshotName',
    );

    final manifest = <String, String>{};
    for (final path in sourcePaths) {
      final file = File(path);
      if (!file.existsSync()) {
        throw FileSystemException('Source key file missing', path);
      }
      final bytes = file.readAsBytesSync();
      manifest[_basename(path)] = sha256.convert(bytes).toString();
    }

    if (skipIfUnchanged) {
      final existing = _findLatestSnapshot();
      if (existing != null && _manifestsMatch(existing.manifest, manifest)) {
        return existing.copyWithSkipped();
      }
    }

    destDir.createSync(recursive: true);
    // Restrict snapshot directory to owner access on POSIX.
    if (!Platform.isWindows) {
      try {
        Process.runSync('chmod', <String>['700', destDir.path]);
      } catch (_) {
        /* best effort */
      }
    }

    for (final path in sourcePaths) {
      final file = File(path);
      final target = File(
        '${destDir.path}${Platform.pathSeparator}${_basename(path)}',
      );
      // Write via openSync so we can flush, and chmod the target before
      // the snapshot directory prune runs.
      final bytes = file.readAsBytesSync();
      final raf = target.openSync(mode: FileMode.write);
      try {
        raf.writeFromSync(bytes);
        raf.flushSync();
      } finally {
        raf.closeSync();
      }
      if (!Platform.isWindows) {
        try {
          Process.runSync('chmod', <String>['600', target.path]);
        } catch (_) {
          /* best effort */
        }
      }
    }

    final manifestFile = File(
      '${destDir.path}${Platform.pathSeparator}manifest.json',
    );
    manifestFile.writeAsStringSync(
      jsonEncode({'timestamp': timestamp.toIso8601String(), 'files': manifest}),
    );
    if (!Platform.isWindows) {
      try {
        Process.runSync('chmod', <String>['600', manifestFile.path]);
      } catch (_) {
        /* best effort */
      }
    }

    _pruneOldSnapshots();

    return KeyBackupResult(
      snapshotDirectory: destDir.path,
      timestamp: timestamp,
      manifest: manifest,
      skipped: false,
    );
  }

  /// Returns every snapshot currently present on disk, oldest first.
  List<KeyBackupResult> listSnapshots() {
    final root = Directory(destinationDirectory);
    if (!root.existsSync()) return const <KeyBackupResult>[];
    final snapshots = <KeyBackupResult>[];
    for (final entity in root.listSync()) {
      if (entity is! Directory) continue;
      final manifestFile = File(
        '${entity.path}${Platform.pathSeparator}manifest.json',
      );
      if (!manifestFile.existsSync()) continue;
      try {
        final data =
            jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
        snapshots.add(
          KeyBackupResult(
            snapshotDirectory: entity.path,
            timestamp: DateTime.parse(data['timestamp'] as String).toUtc(),
            manifest: Map<String, String>.from(
              data['files'] as Map<String, dynamic>,
            ),
            skipped: false,
          ),
        );
      } catch (_) {
        continue;
      }
    }
    snapshots.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return snapshots;
  }

  KeyBackupResult? _findLatestSnapshot() {
    final all = listSnapshots();
    if (all.isEmpty) return null;
    return all.last;
  }

  void _pruneOldSnapshots() {
    final all = listSnapshots();
    if (all.length <= retainSnapshots) return;
    final toRemove = all.take(all.length - retainSnapshots);
    for (final snapshot in toRemove) {
      final dir = Directory(snapshot.snapshotDirectory);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  }

  bool _manifestsMatch(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  static String _snapshotName(DateTime ts) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'snapshot_${ts.year}${two(ts.month)}${two(ts.day)}_'
        '${two(ts.hour)}${two(ts.minute)}${two(ts.second)}';
  }

  static String _basename(String path) =>
      path.split(Platform.pathSeparator).last;
}

class KeyBackupResult {
  const KeyBackupResult({
    required this.snapshotDirectory,
    required this.timestamp,
    required this.manifest,
    required this.skipped,
  });

  /// Absolute path of the snapshot directory.
  final String snapshotDirectory;

  /// UTC timestamp of when the snapshot was (or would have been) taken.
  final DateTime timestamp;

  /// Filename -> SHA-256 hex digest of the backed-up bytes.
  final Map<String, String> manifest;

  /// True when this backup pass did nothing because the source hashes
  /// matched the most recent snapshot.
  final bool skipped;

  KeyBackupResult copyWithSkipped() => KeyBackupResult(
        snapshotDirectory: snapshotDirectory,
        timestamp: timestamp,
        manifest: manifest,
        skipped: true,
      );
}
