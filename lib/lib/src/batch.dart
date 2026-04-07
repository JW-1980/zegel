import 'dart:typed_data';

import 'reader.dart';
import 'writer.dart';
import 'format.dart';

/// Batch operations for processing multiple .zgl files (v1.3).
///
/// Provides methods for batch verification and batch sealing of files,
/// with progress reporting and configurable error handling.
class BatchOperations {
  BatchOperations._();

  /// Result of a batch operation on a single file.
  static Map<String, dynamic> _result(
      String name, bool success, String message, int durationMs) {
    return {
      'name': name,
      'success': success,
      'message': message,
      'duration_ms': durationMs,
    };
  }

  /// Verifies multiple .zgl files against the same master key.
  ///
  /// Returns a list of result maps, each containing:
  /// - `name`: the file identifier
  /// - `success`: whether verification passed
  /// - `message`: status message
  /// - `duration_ms`: time taken
  ///
  /// If [stopOnFirstFailure] is true, stops after the first failed file.
  static List<Map<String, dynamic>> batchVerify(
    List<MapEntry<String, Uint8List>> files,
    Uint8List masterKey, {
    bool stopOnFirstFailure = false,
  }) {
    final results = <Map<String, dynamic>>[];
    const reader = ZegelReader();

    for (final entry in files) {
      final sw = Stopwatch()..start();
      try {
        final result = reader.verify(entry.value, masterKey);
        sw.stop();
        results.add(_result(
          entry.key,
          result.valid,
          result.valid ? 'Valid' : 'Verification failed',
          sw.elapsedMilliseconds,
        ));
        if (!result.valid && stopOnFirstFailure) break;
      } on ZegelException catch (e) {
        sw.stop();
        results
            .add(_result(entry.key, false, e.message, sw.elapsedMilliseconds));
        if (stopOnFirstFailure) break;
      } catch (e) {
        sw.stop();
        results.add(
            _result(entry.key, false, e.toString(), sw.elapsedMilliseconds));
        if (stopOnFirstFailure) break;
      }
    }
    return results;
  }

  /// Seals multiple content entries into individual .zgl files.
  ///
  /// Each entry maps a name to the raw content bytes. All files are sealed
  /// with the same [masterKey] and [options].
  ///
  /// Returns a list of result maps plus the sealed bytes via the callback.
  static List<MapEntry<String, Uint8List>> batchSeal(
    List<MapEntry<String, Uint8List>> contents,
    Uint8List masterKey,
    ZegelOptions options,
  ) {
    final results = <MapEntry<String, Uint8List>>[];
    for (final entry in contents) {
      final writer = ZegelWriter(
          masterKey,
          ZegelOptions(
            contentType: options.contentType,
            filename: entry.key,
            metadata: options.metadata,
            compress: options.compress,
            enableKeyCommitment: options.enableKeyCommitment,
            blockSize: options.blockSize,
          ));
      results.add(MapEntry(entry.key, writer.seal(entry.value)));
    }
    return results;
  }
}
