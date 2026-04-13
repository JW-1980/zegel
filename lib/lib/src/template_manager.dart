import 'sealing_template.dart';

/// Cross-cutting CRUD facade for sealing templates (improvement #92).
///
/// `SealingTemplateStore` handles raw persistence, while this facade
/// adds the operations the GUI and CLI share: update-by-name,
/// duplication, import/export, and convenience lookups such as
/// "default template".
class TemplateManager {
  TemplateManager(this.store);

  final SealingTemplateStore store;

  String? _defaultName;

  /// Lists every template name.
  List<String> list() => store.list();

  /// Returns every template as an instantiated object.
  List<SealingTemplate> allTemplates() {
    final names = store.list();
    final out = <SealingTemplate>[];
    for (final name in names) {
      final template = store.load(name);
      if (template != null) out.add(template);
    }
    return out;
  }

  /// Reads a template by name.
  SealingTemplate? get(String name) => store.load(name);

  /// Inserts or updates a template.
  void upsert(SealingTemplate template) => store.save(template);

  /// Updates mutable fields on the named template. Throws
  /// [StateError] when the template is missing.
  SealingTemplate update(
    String name, {
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
    final existing = store.load(name);
    if (existing == null) {
      throw StateError('No template named "$name"');
    }
    final updated = existing.copyWith(
      description: description,
      contentType: contentType,
      classification: classification,
      compress: compress,
      passwordDerived: passwordDerived,
      expirationFromNow: expirationFromNow,
      blockSize: blockSize,
      publicMetadata: publicMetadata,
      metadata: metadata,
    );
    store.save(updated);
    return updated;
  }

  /// Deletes a template by name.
  bool delete(String name) {
    if (_defaultName == name) _defaultName = null;
    return store.delete(name);
  }

  /// Duplicates [sourceName] under [newName]. Returns the newly-saved
  /// copy or null when the source does not exist.
  SealingTemplate? duplicate(String sourceName, String newName) {
    final source = store.load(sourceName);
    if (source == null) return null;
    final copy = source.copyWith(name: newName);
    store.save(copy);
    return copy;
  }

  /// Marks a template as the default. Useful for "apply this preset on
  /// every new seal" preferences.
  void setDefault(String name) {
    if (store.load(name) == null) {
      throw StateError('Cannot set unknown template as default: $name');
    }
    _defaultName = name;
  }

  /// Returns the default template, or null if none has been set.
  SealingTemplate? defaultTemplate() {
    final name = _defaultName;
    if (name == null) return null;
    return store.load(name);
  }
}
