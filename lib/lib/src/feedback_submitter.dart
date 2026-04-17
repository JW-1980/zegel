import 'dart:convert';
import 'dart:io';

/// In-app feedback / bug report collector (improvement #31).
///
/// Stores feedback entries on disk as newline-delimited JSON. A higher
/// layer (webhook, email, HTTP POST) can pick them up and forward them
/// to the developer. Keeping the collector local means the user can
/// review what is about to be sent before it leaves their machine —
/// satisfying the "no telemetry without consent" requirement.
class FeedbackSubmitter {
  FeedbackSubmitter({required this.storagePath});

  /// Absolute path to the ND-JSON feedback file.
  final String storagePath;

  /// Records a new feedback [entry]. Returns the entry that was stored.
  ///
  /// The write is fully synchronous: we use `writeAsStringSync` with
  /// `FileMode.append` rather than `openWrite`, because the latter returns
  /// an `IOSink.close()` that is a `Future<void>` and therefore cannot be
  /// awaited from a synchronous call site, leading to racy reads in tests
  /// and in downstream code that calls `list()` immediately after `submit`.
  FeedbackEntry submit({
    required FeedbackCategory category,
    required String message,
    String? email,
    String? screen,
    Map<String, dynamic>? context,
    DateTime? at,
  }) {
    final entry = FeedbackEntry(
      id: _generateId(),
      at: (at ?? DateTime.now().toUtc()).toUtc(),
      category: category,
      message: message,
      email: email,
      screen: screen,
      context: context ?? const <String, dynamic>{},
    );
    final file = File(storagePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${jsonEncode(entry.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
    return entry;
  }

  /// Returns every stored entry. Returns an empty list when the file
  /// does not exist yet.
  List<FeedbackEntry> list() {
    final file = File(storagePath);
    if (!file.existsSync()) return const <FeedbackEntry>[];
    final out = <FeedbackEntry>[];
    for (final line in const LineSplitter().convert(file.readAsStringSync())) {
      if (line.trim().isEmpty) continue;
      out.add(FeedbackEntry.fromJson(
        jsonDecode(line) as Map<String, dynamic>,
      ));
    }
    return out;
  }

  /// Clears the feedback log.
  void clear() {
    final file = File(storagePath);
    if (file.existsSync()) file.deleteSync();
  }

  String _generateId() {
    // Monotonic enough for local use without pulling in UUID.
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    return 'fb_${now.toRadixString(36)}';
  }
}

enum FeedbackCategory { bug, feature, question, praise, other }

class FeedbackEntry {
  const FeedbackEntry({
    required this.id,
    required this.at,
    required this.category,
    required this.message,
    required this.context,
    this.email,
    this.screen,
  });

  static FeedbackEntry fromJson(Map<String, dynamic> json) => FeedbackEntry(
        id: json['id'] as String,
        at: DateTime.parse(json['at'] as String).toUtc(),
        category: FeedbackCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => FeedbackCategory.other,
        ),
        message: json['message'] as String,
        email: json['email'] as String?,
        screen: json['screen'] as String?,
        context: json['context'] == null
            ? const <String, dynamic>{}
            : Map<String, dynamic>.from(json['context'] as Map<String, dynamic>),
      );

  final String id;
  final DateTime at;
  final FeedbackCategory category;
  final String message;
  final String? email;
  final String? screen;
  final Map<String, dynamic> context;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'at': at.toUtc().toIso8601String(),
        'category': category.name,
        'message': message,
        if (email != null) 'email': email,
        if (screen != null) 'screen': screen,
        'context': context,
      };
}
