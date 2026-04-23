/// Catalog of customizable dashboard widgets (improvement #46).
///
/// The dashboard renders an ordered list of [DashboardWidgetSpec]s,
/// each identified by a unique key. Users can hide, show, reorder, and
/// resize widgets; the catalog serializes to JSON so user preferences
/// can persist between sessions.
///
/// The catalog is deliberately agnostic to the UI framework: callers
/// drive their own widget tree and use the catalog solely to decide
/// which widgets to display and in what order.
class DashboardCatalog {
  DashboardCatalog({List<DashboardWidgetSpec>? specs})
    : _specs = _buildIndex(specs ?? DashboardCatalog.defaultSpecs);

  static Map<String, DashboardWidgetSpec> _buildIndex(
    List<DashboardWidgetSpec> specs,
  ) {
    final map = <String, DashboardWidgetSpec>{};
    for (final spec in specs) {
      map[spec.key] = spec;
    }
    return map;
  }

  final Map<String, DashboardWidgetSpec> _specs;

  /// Default set of dashboard widgets shipped with Zegel.
  static const List<DashboardWidgetSpec> defaultSpecs = <DashboardWidgetSpec>[
    DashboardWidgetSpec(
      key: 'files_sealed_today',
      title: 'Files sealed today',
      description: 'Total number of files sealed in the last 24 hours.',
      category: DashboardCategory.activity,
      visible: true,
      sortOrder: 0,
    ),
    DashboardWidgetSpec(
      key: 'verification_success_rate',
      title: 'Verification success rate',
      description: 'Percentage of verify operations that succeeded.',
      category: DashboardCategory.activity,
      visible: true,
      sortOrder: 1,
    ),
    DashboardWidgetSpec(
      key: 'key_health',
      title: 'Key health',
      description:
          'Overview of master keys and their rotation status (OK / due / overdue).',
      category: DashboardCategory.security,
      visible: true,
      sortOrder: 2,
    ),
    DashboardWidgetSpec(
      key: 'classification_distribution',
      title: 'Classification distribution',
      description: 'Breakdown of documents by classification level.',
      category: DashboardCategory.insights,
      visible: true,
      sortOrder: 3,
    ),
    DashboardWidgetSpec(
      key: 'top_collaborators',
      title: 'Top collaborators',
      description: 'Most frequent signers and collaborators.',
      category: DashboardCategory.insights,
      visible: true,
      sortOrder: 4,
    ),
    DashboardWidgetSpec(
      key: 'time_saved',
      title: 'Time saved by batch operations',
      description:
          'Cumulative wall-clock time saved vs. processing files manually.',
      category: DashboardCategory.insights,
      visible: true,
      sortOrder: 5,
    ),
    DashboardWidgetSpec(
      key: 'storage_saved',
      title: 'Storage saved',
      description: 'Bytes saved by enabling compression on sealed files.',
      category: DashboardCategory.activity,
      visible: true,
      sortOrder: 6,
    ),
  ];

  /// Returns every visible widget spec, ordered by `sortOrder`.
  List<DashboardWidgetSpec> visibleSpecs() =>
      _specs.values.where((s) => s.visible).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// Returns every spec (visible or hidden), ordered by `sortOrder`.
  List<DashboardWidgetSpec> allSpecs() =>
      _specs.values.toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// Looks up a widget spec by its key.
  DashboardWidgetSpec? lookup(String key) => _specs[key];

  /// Toggles visibility for the widget with [key]. Throws [StateError]
  /// if the key does not exist.
  void setVisible(String key, bool visible) {
    final existing = _specs[key];
    if (existing == null) {
      throw StateError('Unknown dashboard widget: $key');
    }
    _specs[key] = existing.copyWith(visible: visible);
  }

  /// Reorders widgets by providing a new list of keys in the desired
  /// order. Keys not in [orderedKeys] retain their current relative
  /// order but are placed after the explicit ones.
  void reorder(List<String> orderedKeys) {
    var next = 0;
    for (final key in orderedKeys) {
      final existing = _specs[key];
      if (existing == null) continue;
      _specs[key] = existing.copyWith(sortOrder: next);
      next += 1;
    }
    // Push the rest afterwards, preserving their prior relative order.
    final leftover =
        _specs.values.where((s) => !orderedKeys.contains(s.key)).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    for (final spec in leftover) {
      _specs[spec.key] = spec.copyWith(sortOrder: next);
      next += 1;
    }
  }
}

class DashboardWidgetSpec {
  const DashboardWidgetSpec({
    required this.key,
    required this.title,
    required this.description,
    required this.category,
    required this.visible,
    required this.sortOrder,
  });

  final String key;
  final String title;
  final String description;
  final DashboardCategory category;
  final bool visible;
  final int sortOrder;

  DashboardWidgetSpec copyWith({bool? visible, int? sortOrder}) {
    return DashboardWidgetSpec(
      key: key,
      title: title,
      description: description,
      category: category,
      visible: visible ?? this.visible,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

enum DashboardCategory { activity, security, insights }
