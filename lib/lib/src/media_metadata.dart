import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Media metadata extraction and preservation (v1.3).
///
/// Provides utilities for handling metadata from media files (images, videos,
/// documents) that should be preserved or stripped when sealing.
class MediaMetadata {
  MediaMetadata._();

  /// Extracts basic metadata from a file's content bytes.
  ///
  /// Returns a map of metadata fields. Currently supports:
  /// - File size
  /// - Content hash
  /// - Detection of common file signatures (JPEG, PNG, PDF, etc.)
  static Map<String, dynamic> extractBasicMetadata(
    Uint8List content,
    String filename,
  ) {
    final hash = sha256.convert(content);

    final metadata = <String, dynamic>{
      'filename': filename,
      'file_size': content.length,
      'content_hash': hash.toString(),
      'detected_type': _detectFileType(content),
    };

    return metadata;
  }

  /// Creates a metadata-stripped copy of the content.
  ///
  /// For now, returns the content as-is since full EXIF stripping requires
  /// format-specific parsers. The [strippedFields] output parameter receives
  /// a list of field names that would be stripped.
  static Uint8List stripMetadata(
    Uint8List content,
    String detectedType, {
    List<String>? strippedFields,
  }) {
    // Full EXIF/XMP stripping would require format-specific parsers.
    // For now, return content as-is and document what would be stripped.
    strippedFields?.addAll([
      'GPS coordinates',
      'Camera make/model',
      'Date/time original',
      'Software version',
      'Author/artist',
    ]);
    return Uint8List.fromList(content);
  }

  /// Detects the file type from magic bytes.
  static String _detectFileType(Uint8List content) {
    if (content.length < 4) return 'unknown';

    // JPEG
    if (content[0] == 0xFF && content[1] == 0xD8 && content[2] == 0xFF) {
      return 'image/jpeg';
    }
    // PNG
    if (content[0] == 0x89 &&
        content[1] == 0x50 &&
        content[2] == 0x4E &&
        content[3] == 0x47) {
      return 'image/png';
    }
    // PDF
    if (content[0] == 0x25 &&
        content[1] == 0x50 &&
        content[2] == 0x44 &&
        content[3] == 0x46) {
      return 'application/pdf';
    }
    // ZIP (also DOCX, XLSX, etc.)
    if (content[0] == 0x50 &&
        content[1] == 0x4B &&
        content[2] == 0x03 &&
        content[3] == 0x04) {
      return 'application/zip';
    }
    // GIF
    if (content[0] == 0x47 && content[1] == 0x49 && content[2] == 0x46) {
      return 'image/gif';
    }
    return 'application/octet-stream';
  }

  /// Creates a provenance metadata entry for a media file.
  ///
  /// Records the creation context for chain of custody tracking.
  static Map<String, dynamic> createProvenanceEntry(
    String filename,
    String action,
    String actor, {
    Map<String, dynamic>? additionalFields,
  }) {
    return {
      'filename': filename,
      'action': action,
      'actor': actor,
      'timestamp': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      if (additionalFields != null) ...additionalFields,
    };
  }
}
