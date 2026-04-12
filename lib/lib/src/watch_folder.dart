import 'dart:async';
import 'dart:io';

/// Watch-folder integration (improvement #21).
///
/// Polls a directory (non-recursive by default) and emits an event the
/// first time a new file appears. The caller hooks the emitted event to
/// a sealing routine so dropping a file into a designated folder
/// automatically produces a sealed `.zgl`.
///
/// `dart:io`'s `Directory.watch` uses native FS notifications but is not
/// available on every platform — a polling fallback keeps the feature
/// usable everywhere.
class WatchFolder {
  WatchFolder({
    required this.directory,
    this.pollInterval = const Duration(seconds: 5),
    this.includeExtensions = const <String>{},
    this.skipZegel = true,
  });

  /// Absolute path of the watched directory.
  final String directory;

  /// Polling interval (only used when native watching is disabled).
  final Duration pollInterval;

  /// File extensions to consider. An empty set accepts everything.
  final Set<String> includeExtensions;

  /// If true, .zgl files are skipped (we don't seal already-sealed files).
  final bool skipZegel;

  final StreamController<WatchEvent> _controller =
      StreamController<WatchEvent>.broadcast();
  final Set<String> _seen = <String>{};
  Timer? _timer;
  bool _running = false;

  /// Stream of newly-discovered files.
  Stream<WatchEvent> get events => _controller.stream;

  /// Kicks off watching. Initial population of the directory is emitted
  /// as a batch of events on the next tick.
  void start() {
    if (_running) return;
    _running = true;
    _scan(initial: true);
    _timer = Timer.periodic(pollInterval, (_) => _scan());
  }

  /// Stops watching and closes the event stream.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _running = false;
    await _controller.close();
  }

  /// Runs a single scan pass. Exposed for tests that don't want a running
  /// periodic timer.
  List<WatchEvent> pollOnce() {
    return _scan();
  }

  List<WatchEvent> _scan({bool initial = false}) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return const <WatchEvent>[];
    final emitted = <WatchEvent>[];
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      final path = entity.path;
      if (_seen.contains(path)) continue;
      final ext = _extensionOf(path);
      if (skipZegel && ext == 'zgl') {
        _seen.add(path);
        continue;
      }
      if (includeExtensions.isNotEmpty && !includeExtensions.contains(ext)) {
        continue;
      }
      _seen.add(path);
      final event = WatchEvent(
        path: path,
        discoveredAt: DateTime.now().toUtc(),
        initialScan: initial,
      );
      emitted.add(event);
      if (!_controller.isClosed) {
        _controller.add(event);
      }
    }
    return emitted;
  }

  static String _extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final idx = name.lastIndexOf('.');
    if (idx == -1 || idx == name.length - 1) return '';
    return name.substring(idx + 1).toLowerCase();
  }
}

class WatchEvent {
  const WatchEvent({
    required this.path,
    required this.discoveredAt,
    required this.initialScan,
  });

  final String path;
  final DateTime discoveredAt;
  final bool initialScan;
}
