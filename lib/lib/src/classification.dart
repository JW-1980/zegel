import 'dart:typed_data';

import 'format.dart';
import 'reader.dart';
import 'redaction.dart';
import 'writer.dart';

/// Document classification and declassification for government and enterprise
/// use cases.
///
/// Supports a hierarchical classification scheme:
/// `PUBLIC < INTERNAL < CONFIDENTIAL < SECRET < TOP_SECRET`.
///
/// Classification metadata is stored in the **public metadata** block so that
/// access-control systems can inspect the classification level without needing
/// the master key. The classification itself does not affect encryption
/// strength -- all levels use the same AES-256-GCM -- but downstream systems
/// are expected to enforce handling rules based on the level.
///
/// Use cases:
/// - **Government agencies**: Marking documents with national security
///   classifications and caveats (e.g. "NOFORN", "REL TO FVEY").
/// - **Enterprise**: Separating internal memos from customer-facing reports
///   with enforceable labelling.
/// - **Declassification workflows**: Reducing a document's classification
///   level over time, optionally redacting sensitive blocks.
class Classification {
  Classification._();

  /// Ordered list of classification levels from least to most restrictive.
  static const List<String> levels = <String>[
    ZegelFormat.classificationPublic,
    ZegelFormat.classificationInternal,
    ZegelFormat.classificationConfidential,
    ZegelFormat.classificationSecret,
    ZegelFormat.classificationTopSecret,
  ];

  /// Compares two classification levels.
  ///
  /// Returns a negative value if [a] is less restrictive than [b], zero if
  /// they are equal, and a positive value if [a] is more restrictive.
  ///
  /// Throws [ArgumentError] if either level is not recognised.
  static int compare(String a, String b) {
    final int indexA = levels.indexOf(a);
    final int indexB = levels.indexOf(b);
    if (indexA < 0) {
      throw ArgumentError('Unknown classification level: $a');
    }
    if (indexB < 0) {
      throw ArgumentError('Unknown classification level: $b');
    }
    return indexA - indexB;
  }

  /// Validates that a classification level string is recognised.
  ///
  /// Returns `true` if [level] is one of the known classification levels.
  static bool isValidLevel(String level) => levels.contains(level);

  /// Creates classification metadata suitable for inclusion in the public
  /// metadata block of a .zgl file.
  ///
  /// [level] is the classification level (must be one of [levels]).
  /// [authority] identifies who assigned the classification.
  /// [caveat] is an optional handling caveat (e.g. `"NOFORN"`).
  /// [declassifyOn] is the optional date when the document should be
  /// declassified.
  ///
  /// Returns a structured map that can be merged into public metadata.
  static Map<String, dynamic> createClassificationMetadata({
    required String level,
    required String authority,
    String? caveat,
    DateTime? declassifyOn,
  }) {
    if (!isValidLevel(level)) {
      throw ArgumentError('Unknown classification level: $level');
    }

    final Map<String, dynamic> classification = <String, dynamic>{
      'level': level,
      'authority': authority,
      'classified_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (caveat != null) {
      classification['caveat'] = caveat;
    }

    if (declassifyOn != null) {
      classification['declassify_on'] = declassifyOn.toUtc().toIso8601String();
    }

    return <String, dynamic>{
      'classification': classification,
    };
  }

  /// Declassifies a sealed .zgl file by reducing its classification level.
  ///
  /// This operation:
  /// 1. Verifies the file's integrity.
  /// 2. Reads the current public metadata and classification.
  /// 3. Validates that [newLevel] is less restrictive than the current level.
  /// 4. Optionally redacts blocks specified in [redactBlocks].
  /// 5. Re-seals the file with updated public metadata recording the
  ///    declassification event.
  ///
  /// [fileBytes] is the original sealed .zgl file.
  /// [masterKey] is the 32-byte master key.
  /// [newLevel] is the target (less restrictive) classification level.
  /// [authority] identifies who authorised the declassification.
  /// [redactBlocks] is an optional list of block indices to redact during
  /// declassification.
  ///
  /// Returns the re-sealed file bytes with updated classification.
  ///
  /// Throws [ArgumentError] if [newLevel] is not less restrictive than the
  /// current level.
  /// Throws [ZegelTamperedException] if the original file fails verification.
  static Uint8List declassify(
    Uint8List fileBytes,
    Uint8List masterKey,
    String newLevel,
    String authority, {
    List<int>? redactBlocks,
  }) {
    if (!isValidLevel(newLevel)) {
      throw ArgumentError('Unknown classification level: $newLevel');
    }

    // Verify and extract the original file.
    const ZegelReader reader = ZegelReader();
    final ZegelResult result = reader.verify(fileBytes, masterKey);

    if (!result.valid) {
      throw const ZegelTamperedException(
        'Cannot declassify: file integrity verification failed',
      );
    }

    // Determine current classification level.
    String currentLevel = ZegelFormat.classificationTopSecret;
    Map<String, dynamic> existingPublicMeta = <String, dynamic>{};

    if (result.publicMetadata != null) {
      existingPublicMeta = Map<String, dynamic>.from(result.publicMetadata!);
      if (existingPublicMeta.containsKey('classification')) {
        final Map<String, dynamic> classInfo =
            existingPublicMeta['classification'] as Map<String, dynamic>;
        currentLevel = classInfo['level'] as String;
      }
    }

    // Validate the new level is less restrictive.
    if (compare(newLevel, currentLevel) >= 0) {
      throw ArgumentError(
        'New level "$newLevel" must be less restrictive than '
        'current level "$currentLevel"',
      );
    }

    // Apply optional redactions first.
    Uint8List workingBytes = fileBytes;
    if (redactBlocks != null && redactBlocks.isNotEmpty) {
      workingBytes = Redaction.redactBlocks(workingBytes, masterKey, redactBlocks);
    }

    // Re-verify after redaction (if applied) and re-extract.
    final ZegelResult postRedactResult = reader.verify(workingBytes, masterKey);
    if (!postRedactResult.valid) {
      throw const ZegelTamperedException(
        'Post-redaction verification failed',
      );
    }

    // Build updated public metadata with declassification record.
    final Map<String, dynamic> updatedClassification =
        createClassificationMetadata(
      level: newLevel,
      authority: authority,
    );

    // Add declassification history.
    final List<Map<String, dynamic>> history = <Map<String, dynamic>>[];
    if (existingPublicMeta.containsKey('declassification_history')) {
      final List<dynamic> existing =
          existingPublicMeta['declassification_history'] as List<dynamic>;
      for (final dynamic entry in existing) {
        history.add(Map<String, dynamic>.from(entry as Map<String, dynamic>));
      }
    }
    history.add(<String, dynamic>{
      'from_level': currentLevel,
      'to_level': newLevel,
      'authority': authority,
      'declassified_at': DateTime.now().toUtc().toIso8601String(),
      'redacted_blocks': redactBlocks ?? <int>[],
    });

    final Map<String, dynamic> newPublicMeta = <String, dynamic>{
      ...existingPublicMeta,
      ...updatedClassification,
      'declassification_history': history,
    };

    // Re-seal with updated public metadata.
    final ZegelOptions opts = ZegelOptions(
      contentType: postRedactResult.contentType,
      filename: postRedactResult.filename,
      metadata: postRedactResult.metadata,
      publicMetadata: newPublicMeta,
      enableKeyCommitment: true,
    );

    final ZegelWriter writer = ZegelWriter(masterKey, opts);
    return writer.seal(postRedactResult.content!);
  }
}
