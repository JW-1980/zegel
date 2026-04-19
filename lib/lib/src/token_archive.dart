import 'dart:convert';
import 'dart:io';

/// Auto-archiving of expired selective-disclosure tokens (improvement #22).
///
/// Keeps an on-disk inventory of issued tokens so that expired ones can be
/// swept into an archive directory, separating "live" and "retired" tokens
/// without losing audit history. Nothing cryptographic happens here — the
/// archive is purely operational hygiene.
///
/// Tokens are identified by their filename and, optionally, an explicit
/// expiration timestamp. If no timestamp is supplied, [addToken] tries to
/// parse the token JSON and read its `expires_at` field (ISO-8601).
class TokenArchive {
  TokenArchive({
    required this.liveDirectory,
    required this.archiveDirectory,
  });

  /// Directory where live (unexpired) tokens are kept.
  final String liveDirectory;

  /// Directory where expired tokens are moved.
  final String archiveDirectory;

  Directory get _liveDir {
    final d = Directory(liveDirectory);
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Directory get _archiveDir {
    final d = Directory(archiveDirectory);
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// Adds a token JSON blob to the live directory. If [expiresAt] is null
  /// the token body is inspected for an `expires_at` field.
  ///
  /// [name] must be a filename-safe identifier: only ASCII alphanumerics,
  /// `_`, `-`, and `.` are allowed. Path separators, `..` segments, null
  /// bytes, and leading dots are rejected to prevent directory traversal
  /// and shadow-file attacks on the live and archive directories.
  void addToken(String name, String tokenJson, {DateTime? expiresAt}) {
    final safe = _requireSafeName(name);
    final file = File('${_liveDir.path}${Platform.pathSeparator}$safe.json');
    file.writeAsStringSync(tokenJson);
    if (expiresAt != null) {
      File('${file.path}.meta').writeAsStringSync(
        jsonEncode({'expires_at': expiresAt.toUtc().toIso8601String()}),
      );
    }
  }

  /// Validates and returns [name] if it is a safe filename component.
  /// Throws [ArgumentError] otherwise.
  static String _requireSafeName(String name) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'token name must not be empty');
    }
    if (name.length > 128) {
      throw ArgumentError.value(
        name,
        'name',
        'token name must be 128 characters or fewer',
      );
    }
    // Reject anything that isn't a simple filename component. We also
    // explicitly reject a leading dot so callers cannot hide tokens on
    // POSIX or overwrite sidecar files like `.meta`.
    if (name.startsWith('.') ||
        name.contains('..') ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains('\x00') ||
        !RegExp(r'^[A-Za-z0-9._\-]+$').hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'token name must contain only [A-Za-z0-9._-] and may not traverse '
            'directories',
      );
    }
    return name;
  }

  /// Sweeps expired tokens into the archive directory.
  ///
  /// [now] defaults to the current UTC time. A token is considered expired if
  /// its side-car `.meta` file says `expires_at < now`, or if no meta exists
  /// and the JSON itself contains a top-level `expires_at` earlier than `now`.
  ///
  /// Returns the list of token names that were archived.
  List<String> sweep({DateTime? now}) {
    final cutoff = (now ?? DateTime.now().toUtc()).toUtc();
    final archived = <String>[];
    final d = _liveDir;
    if (!d.existsSync()) return archived;

    for (final entity in d.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final expiry = _readExpiry(entity);
      if (expiry == null) continue;
      if (expiry.isBefore(cutoff)) {
        final name = entity.uri.pathSegments.last;
        final dest = File('${_archiveDir.path}${Platform.pathSeparator}$name');
        dest.parent.createSync(recursive: true);
        entity.renameSync(dest.path);
        final meta = File('${entity.path}.meta');
        if (meta.existsSync()) {
          meta.renameSync('${dest.path}.meta');
        }
        archived.add(name.replaceFirst(RegExp(r'\.json$'), ''));
      }
    }
    return archived;
  }

  /// Returns live token names (without the `.json` extension).
  List<String> liveTokens() {
    final d = _liveDir;
    if (!d.existsSync()) return const <String>[];
    return d
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .map(
            (f) => f.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), ''))
        .toList()
      ..sort();
  }

  /// Returns archived token names.
  List<String> archivedTokens() {
    final d = _archiveDir;
    if (!d.existsSync()) return const <String>[];
    return d
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .map(
            (f) => f.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), ''))
        .toList()
      ..sort();
  }

  DateTime? _readExpiry(File tokenFile) {
    final metaFile = File('${tokenFile.path}.meta');
    if (metaFile.existsSync()) {
      try {
        final m =
            jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        final v = m['expires_at'];
        if (v is String) return DateTime.parse(v).toUtc();
      } catch (_) {
        // fall through
      }
    }
    try {
      final decoded = jsonDecode(tokenFile.readAsStringSync());
      if (decoded is Map<String, dynamic> && decoded['expires_at'] is String) {
        return DateTime.parse(decoded['expires_at'] as String).toUtc();
      }
    } catch (_) {
      // Ignore parse failures — token without an expiry is treated as live.
    }
    return null;
  }
}
