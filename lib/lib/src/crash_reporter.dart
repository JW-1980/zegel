import 'dart:convert';
import 'dart:io';

import 'anonymizer.dart';
import 'hardware_info.dart';

/// Opt-in crash reporting (improvement #32).
///
/// Collects uncaught exception information and device fingerprints into a
/// local JSON log that the user can inspect or forward. The reporter is
/// paired with an [Anonymizer] to strip personally identifiable tokens
/// (hostname, username, paths) from stack traces and environment data.
///
/// Nothing is transmitted automatically. A dispatcher (e.g. `ZegelWebhook`)
/// can pick reports up later and send them to a telemetry endpoint.
class CrashReporter {
  CrashReporter({
    this.enabled = false,
    Anonymizer? anonymizer,
  }) : _anonymizer = anonymizer ?? Anonymizer.random();

  /// Master toggle for the reporter. When false every `report*` call is a
  /// no-op.
  bool enabled;

  final Anonymizer _anonymizer;
  final List<CrashReport> _reports = <CrashReport>[];

  /// Reports an [error] with its [stackTrace]. [context] may include a
  /// human-readable summary of what the app was doing at the time.
  CrashReport? report(
    Object error,
    StackTrace stackTrace, {
    String? context,
    Map<String, dynamic>? extra,
    HardwareInfo? hardware,
    DateTime? at,
  }) {
    if (!enabled) return null;
    final report = CrashReport(
      at: (at ?? DateTime.now().toUtc()).toUtc(),
      message: error.toString(),
      stackTrace: _anonymizer.scrubStackTrace(stackTrace.toString()),
      context: context == null ? null : _anonymizer.scrub(context),
      hardware: (hardware ?? HardwareInfo.detect()).toJson(),
      extra: extra ?? const <String, dynamic>{},
    );
    _reports.add(report);
    return report;
  }

  /// Wraps a synchronous function, reporting any thrown error and
  /// rethrowing it so callers still observe the failure.
  T runGuarded<T>(T Function() fn, {String? context}) {
    try {
      return fn();
    } catch (error, stack) {
      report(error, stack, context: context);
      rethrow;
    }
  }

  /// Read-only view of collected reports.
  List<CrashReport> get reports => List<CrashReport>.unmodifiable(_reports);

  /// Clears the in-memory buffer.
  void clear() => _reports.clear();

  String encode() => jsonEncode({
        'enabled': enabled,
        'reports': _reports.map((r) => r.toJson()).toList(),
      });

  static CrashReporter decodeJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final reporter = CrashReporter(enabled: m['enabled'] as bool? ?? false);
    for (final entry
        in (m['reports'] as List<dynamic>? ?? const <dynamic>[])) {
      reporter._reports.add(
        CrashReport.fromJson(entry as Map<String, dynamic>),
      );
    }
    return reporter;
  }

  void saveFile(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encode());
  }

  static CrashReporter loadFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return CrashReporter();
    return decodeJson(file.readAsStringSync());
  }
}

class CrashReport {
  const CrashReport({
    required this.at,
    required this.message,
    required this.stackTrace,
    required this.hardware,
    required this.extra,
    this.context,
  });

  static CrashReport fromJson(Map<String, dynamic> json) => CrashReport(
        at: DateTime.parse(json['at'] as String).toUtc(),
        message: json['message'] as String,
        stackTrace: json['stack_trace'] as String,
        context: json['context'] as String?,
        hardware: json['hardware'] == null
            ? const <String, dynamic>{}
            : Map<String, dynamic>.from(json['hardware'] as Map<String, dynamic>),
        extra: json['extra'] == null
            ? const <String, dynamic>{}
            : Map<String, dynamic>.from(json['extra'] as Map<String, dynamic>),
      );

  final DateTime at;
  final String message;
  final String stackTrace;
  final String? context;
  final Map<String, dynamic> hardware;
  final Map<String, dynamic> extra;

  Map<String, dynamic> toJson() => {
        'at': at.toUtc().toIso8601String(),
        'message': message,
        'stack_trace': stackTrace,
        if (context != null) 'context': context,
        'hardware': hardware,
        'extra': extra,
      };
}
