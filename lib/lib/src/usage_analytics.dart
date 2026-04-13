import 'dart:convert';
import 'dart:io';

/// Opt-in local usage analytics (improvements #33, #36, #39).
///
/// Counts CLI commands, GUI screen visits, crypto-algorithm usage, and
/// average file sizes. Everything stays on disk inside a single JSON file;
/// nothing is transmitted unless a caller explicitly forwards the data via
/// the webhook or another integration.
///
/// The collector is strictly opt-in: if [enabled] is false every `record*`
/// call becomes a no-op.
class UsageAnalytics {
  UsageAnalytics({this.enabled = false});

  bool enabled;
  final Map<String, int> _commandCounts = {};
  final Map<String, int> _screenCounts = {};
  final Map<String, int> _algorithmCounts = {};
  int _totalFilesSealed = 0;
  int _totalBytesSealed = 0;

  /// Records a single invocation of a CLI command.
  void recordCommand(String command) {
    if (!enabled) return;
    _commandCounts[command] = (_commandCounts[command] ?? 0) + 1;
  }

  /// Records opening a GUI screen.
  void recordScreen(String screen) {
    if (!enabled) return;
    _screenCounts[screen] = (_screenCounts[screen] ?? 0) + 1;
  }

  /// Records one use of a named crypto algorithm or key size
  /// (e.g. `AES-256-GCM`, `Ed25519`, `Argon2id`).
  void recordAlgorithm(String algorithm) {
    if (!enabled) return;
    _algorithmCounts[algorithm] = (_algorithmCounts[algorithm] ?? 0) + 1;
  }

  /// Records that a file of [bytes] length was sealed.
  void recordFileSealed(int bytes) {
    if (!enabled) return;
    if (bytes < 0) return;
    _totalFilesSealed += 1;
    _totalBytesSealed += bytes;
  }

  /// Average file size across all `recordFileSealed` calls. Returns 0 when
  /// no files have been recorded.
  double get averageFileSizeBytes {
    if (_totalFilesSealed == 0) return 0;
    return _totalBytesSealed / _totalFilesSealed;
  }

  int get totalFilesSealed => _totalFilesSealed;
  int get totalBytesSealed => _totalBytesSealed;

  Map<String, int> get commandCounts =>
      Map<String, int>.unmodifiable(_commandCounts);
  Map<String, int> get screenCounts =>
      Map<String, int>.unmodifiable(_screenCounts);
  Map<String, int> get algorithmCounts =>
      Map<String, int>.unmodifiable(_algorithmCounts);

  /// Returns the [limit] most-used CLI commands.
  List<MapEntry<String, int>> topCommands({int limit = 10}) =>
      _top(_commandCounts, limit);

  /// Returns the [limit] most-visited GUI screens.
  List<MapEntry<String, int>> topScreens({int limit = 10}) =>
      _top(_screenCounts, limit);

  /// Returns the [limit] most-used crypto algorithms.
  List<MapEntry<String, int>> topAlgorithms({int limit = 10}) =>
      _top(_algorithmCounts, limit);

  List<MapEntry<String, int>> _top(Map<String, int> source, int limit) {
    final entries = source.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  /// Clears all counters.
  void reset() {
    _commandCounts.clear();
    _screenCounts.clear();
    _algorithmCounts.clear();
    _totalFilesSealed = 0;
    _totalBytesSealed = 0;
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'command_counts': _commandCounts,
        'screen_counts': _screenCounts,
        'algorithm_counts': _algorithmCounts,
        'total_files_sealed': _totalFilesSealed,
        'total_bytes_sealed': _totalBytesSealed,
      };

  String encode() => jsonEncode(toJson());

  static UsageAnalytics decodeJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final a = UsageAnalytics(enabled: m['enabled'] as bool? ?? false);
    (m['command_counts'] as Map<String, dynamic>?)?.forEach((k, v) {
      a._commandCounts[k] = (v as num).toInt();
    });
    (m['screen_counts'] as Map<String, dynamic>?)?.forEach((k, v) {
      a._screenCounts[k] = (v as num).toInt();
    });
    (m['algorithm_counts'] as Map<String, dynamic>?)?.forEach((k, v) {
      a._algorithmCounts[k] = (v as num).toInt();
    });
    a._totalFilesSealed = (m['total_files_sealed'] as num?)?.toInt() ?? 0;
    a._totalBytesSealed = (m['total_bytes_sealed'] as num?)?.toInt() ?? 0;
    return a;
  }

  /// Saves analytics to [path]. Creates parent directories as needed.
  void saveFile(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encode());
  }

  /// Loads analytics from [path], returning an empty (disabled) collector
  /// if the file does not yet exist.
  static UsageAnalytics loadFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return UsageAnalytics();
    return decodeJson(file.readAsStringSync());
  }
}
