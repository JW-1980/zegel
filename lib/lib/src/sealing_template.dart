import 'dart:convert';
import 'dart:io';

/// Reusable sealing-configuration template (improvement #19).
///
/// A sealing template captures a named bundle of options that the user
/// normally has to re-enter every time they seal a file: default
/// classification, expiration policy, compression, default content type,
/// public metadata, and so on.
///
/// Templates are stored as JSON in a template directory, one file per
/// template, so the file picker in the GUI or a CLI command can easily
/// enumerate them.
///
/// Note: this is different from the envelope-recipient template system in
/// `template.dart` — that feature describes multi-party signing workflows,
/// while this one captures reusable `ZegelOptions` presets.
class SealingTemplate {
  const SealingTemplate({
    required this.name,
    this.description,
    this.contentType,
    this.classification,
    this.compress = false,
    this.passwordDerived = false,
    this.expirationFromNow,
    this.blockSize,
    this.publicMetadata = const <String, dynamic>{},
    this.metadata = const <String, dynamic>{},
    required this.createdAt,
  });

  /// Unique, user-supplied name.
  final String name;

  /// Optional human description.
  final String? description;

  /// Default content type (e.g. `application/pdf`).
  final String? contentType;

  /// Default classification level (e.g. `INTERNAL`, `TOP_SECRET`).
  final String? classification;

  /// Whether to enable zlib compression by default.
  final bool compress;

  /// Whether to enable password-derived keys.
  final bool passwordDerived;

  /// Optional default expiration relative to "now" at sealing time.
  final Duration? expirationFromNow;

  /// Default block size in bytes. `null` uses the writer's default.
  final int? blockSize;

  /// Default public metadata to include on every seal.
  final Map<String, dynamic> publicMetadata;

  /// Default encrypted metadata to include on every seal.
  final Map<String, dynamic> metadata;

  /// ISO-8601 timestamp of when the template was created.
  final DateTime createdAt;

  /// Returns a copy of this template with updated fields.
  SealingTemplate copyWith({
    String? name,
    String? description,
    String? contentType,
    String? classification,
    bool? compress,
    bool? passwordDerived,
    Duration? expirationFromNow,
    int? blockSize,
    Map<String, dynamic>? publicMetadata,
    Map<String, dynamic>? metadata,
  }) {
    return SealingTemplate(
      name: name ?? this.name,
      description: description ?? this.description,
      contentType: contentType ?? this.contentType,
      classification: classification ?? this.classification,
      compress: compress ?? this.compress,
      passwordDerived: passwordDerived ?? this.passwordDerived,
      expirationFromNow: expirationFromNow ?? this.expirationFromNow,
      blockSize: blockSize ?? this.blockSize,
      publicMetadata: publicMetadata ?? this.publicMetadata,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (description != null) 'description': description,
    if (contentType != null) 'content_type': contentType,
    if (classification != null) 'classification': classification,
    'compress': compress,
    'password_derived': passwordDerived,
    if (expirationFromNow != null)
      'expiration_from_now_seconds': expirationFromNow!.inSeconds,
    if (blockSize != null) 'block_size': blockSize,
    'public_metadata': publicMetadata,
    'metadata': metadata,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  static SealingTemplate fromJson(Map<String, dynamic> json) {
    return SealingTemplate(
      name: json['name'] as String,
      description: json['description'] as String?,
      contentType: json['content_type'] as String?,
      classification: json['classification'] as String?,
      compress: json['compress'] as bool? ?? false,
      passwordDerived: json['password_derived'] as bool? ?? false,
      expirationFromNow: json['expiration_from_now_seconds'] == null
          ? null
          : Duration(
              seconds: (json['expiration_from_now_seconds'] as num).toInt(),
            ),
      blockSize: (json['block_size'] as num?)?.toInt(),
      publicMetadata: json['public_metadata'] == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(
              json['public_metadata'] as Map<String, dynamic>,
            ),
      metadata: json['metadata'] == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(json['metadata'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// A directory-backed store for [SealingTemplate]s. Templates are saved as
/// `<name>.json` inside a single directory and listed by filename.
class SealingTemplateStore {
  SealingTemplateStore(this.directory);

  /// The directory holding the template files.
  final String directory;

  Directory get _dir {
    final d = Directory(directory);
    if (!d.existsSync()) {
      d.createSync(recursive: true);
    }
    return d;
  }

  String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  File _fileFor(String name) =>
      File('${_dir.path}${Platform.pathSeparator}${_sanitize(name)}.json');

  /// Saves [template], overwriting an existing template with the same name.
  void save(SealingTemplate template) {
    final file = _fileFor(template.name);
    file.writeAsStringSync(jsonEncode(template.toJson()));
  }

  /// Loads the template with the given name, or returns `null` if none.
  SealingTemplate? load(String name) {
    final file = _fileFor(name);
    if (!file.existsSync()) return null;
    return SealingTemplate.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
  }

  /// Deletes the template with the given name. Returns true if it existed.
  bool delete(String name) {
    final file = _fileFor(name);
    if (!file.existsSync()) return false;
    file.deleteSync();
    return true;
  }

  /// Lists all stored template names (without the `.json` extension).
  List<String> list() {
    final d = _dir;
    return d
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .map(
          (f) => f.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), ''),
        )
        .toList()
      ..sort();
  }
}
