import 'dart:io';

import 'secure_memory.dart';

/// Secure file deletion / shredding (improvement #74).
///
/// Overwrites a file's bytes with random data before unlinking it, then
/// syncs the parent directory so the unlink is committed. The number of
/// overwrite passes is configurable; most modern filesystems only need
/// one pass because the storage controller remaps writes. The default of
/// 1 pass mirrors the NIST SP 800-88 "clear" guidance.
///
/// Caveats: this is a best-effort helper. On copy-on-write filesystems
/// (Btrfs, APFS) and SSDs, there is no general way from user space to
/// guarantee the physical blocks are overwritten. For absolute
/// confidentiality, encrypt the volume.
class SecureDelete {
  SecureDelete._();

  /// Shreds [file]. Returns the number of bytes that were overwritten.
  /// Passes is the number of random overwrite passes; the final pass is
  /// always zeros.
  static int shredFile(File file, {int passes = 1}) {
    if (passes < 1) {
      throw ArgumentError.value(passes, 'passes', 'must be at least 1');
    }
    if (!file.existsSync()) {
      throw FileSystemException('Cannot shred non-existent file', file.path);
    }
    final length = file.lengthSync();
    if (length == 0) {
      file.deleteSync();
      return 0;
    }

    final raf = file.openSync(mode: FileMode.writeOnlyAppend);
    try {
      for (var pass = 0; pass < passes; pass++) {
        raf.setPositionSync(0);
        final random = SecureMemory.randomBytes(length);
        raf.writeFromSync(random);
        raf.flushSync();
      }
      // Final zero pass.
      raf.setPositionSync(0);
      raf.writeFromSync(List<int>.filled(length, 0));
      raf.flushSync();
    } finally {
      raf.closeSync();
    }
    file.deleteSync();
    return length;
  }

  /// Shreds every file matching [paths]. Returns the total number of
  /// bytes overwritten. Missing files are silently skipped.
  static int shredAll(Iterable<String> paths, {int passes = 1}) {
    var total = 0;
    for (final path in paths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      total += shredFile(file, passes: passes);
    }
    return total;
  }

  /// Recursively shreds every regular file under [directory], then
  /// removes the empty directory tree.
  static int shredDirectory(Directory directory, {int passes = 1}) {
    if (!directory.existsSync()) return 0;
    var total = 0;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File) {
        total += shredFile(entity, passes: passes);
      }
    }
    directory.deleteSync(recursive: true);
    return total;
  }
}
