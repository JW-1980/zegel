import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'format.dart';
import 'reader.dart';
import 'writer.dart';

/// Time-locked release using sequential computation puzzles (v1.2+).
///
/// Implements a time-lock puzzle based on iterated hashing. The actual
/// decryption key is `SHA-256^N(masterKey)` where N is calibrated to the
/// desired time duration. Since each hash depends on the previous one, there
/// is no shortcut: the solver must perform all N iterations sequentially,
/// regardless of how many CPUs they have.
///
/// Puzzle parameters are stored in the file's public metadata so that anyone
/// can solve the puzzle after the intended time, but nobody can solve it
/// faster than the calibrated duration.
///
/// **Security model:** The time-lock provides a lower bound on how long it
/// takes to access the content, assuming the solver has a single core
/// performing SHA-256 at a known speed. An adversary with a faster SHA-256
/// implementation (e.g. custom ASIC) may solve it earlier. Calibrate
/// conservatively.
class TimeLock {
  TimeLock._();

  /// Default assumed SHA-256 hashing rate (iterations per second).
  ///
  /// This is a conservative estimate for a modern CPU core. Adjust using
  /// [calibrate] for your specific hardware.
  static const int defaultHashRate = 2000000; // 2M hashes/sec

  /// Public metadata key prefix for time-lock puzzle parameters.
  static const String _puzzleIterationsKey = 'timelock_iterations';
  static const String _puzzleHashAlgorithmKey = 'timelock_hash_algorithm';
  static const String _puzzleVerificationHashKey = 'timelock_verification_hash';
  static const String _puzzleCreatedKey = 'timelock_created';
  static const String _puzzleTargetKey = 'timelock_target_epoch';

  /// Calibrates the hash rate on the current hardware by performing a short
  /// benchmark.
  ///
  /// [durationMs] is the benchmark duration in milliseconds (default: 1000).
  ///
  /// Returns the measured iterations per second.
  static int calibrate({int durationMs = 1000}) {
    final Uint8List seed = Uint8List(32);
    Uint8List current = seed;
    int count = 0;
    final Stopwatch sw = Stopwatch()..start();

    while (sw.elapsedMilliseconds < durationMs) {
      current = Uint8List.fromList(sha256.convert(current).bytes);
      count++;
    }
    sw.stop();

    final double elapsed = sw.elapsedMilliseconds / 1000.0;
    return (count / elapsed).round();
  }

  /// Creates a time-lock puzzle that requires sequential computation.
  ///
  /// [masterKey] is the 32-byte key to lock.
  /// [duration] is the desired minimum time to unlock.
  /// [hashRate] is the assumed iterations per second (use [calibrate] to
  /// measure). Defaults to [defaultHashRate].
  ///
  /// Returns a [TimeLockPuzzle] containing the puzzle parameters and the
  /// locked key (the result of N iterated hashes).
  static TimeLockPuzzle createTimeLockPuzzle(
    Uint8List masterKey,
    Duration duration, {
    int hashRate = defaultHashRate,
  }) {
    if (masterKey.length != 32) {
      throw ArgumentError('Master key must be exactly 32 bytes');
    }
    if (duration.inSeconds < 1) {
      throw ArgumentError('Duration must be at least 1 second');
    }

    final int iterations = hashRate * duration.inSeconds;

    // Compute hash^N(masterKey).
    Uint8List lockedKey = Uint8List.fromList(masterKey);
    for (int i = 0; i < iterations; i++) {
      lockedKey = Uint8List.fromList(sha256.convert(lockedKey).bytes);
    }

    // Compute a verification hash so the solver can confirm they got the
    // right answer without needing to try decryption.
    final Uint8List verificationHash = Uint8List.fromList(
      sha256
          .convert(
            Uint8List.fromList([
              ...lockedKey,
              ...utf8.encode('timelock-verify-v1'),
            ]),
          )
          .bytes,
    );

    final int nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final int targetEpoch = nowEpoch + duration.inSeconds;

    return TimeLockPuzzle(
      iterations: iterations,
      hashAlgorithm: 'SHA-256',
      verificationHash: verificationHash,
      lockedKey: lockedKey,
      createdEpoch: nowEpoch,
      targetEpoch: targetEpoch,
    );
  }

  /// Solves a time-lock puzzle by performing the sequential computation.
  ///
  /// [puzzle] is the puzzle to solve.
  /// [startKey] is the original master key (the starting point for iteration).
  ///
  /// Returns the derived key after N iterations, or `null` if the verification
  /// hash does not match (indicating either a wrong start key or corrupted
  /// puzzle parameters).
  ///
  /// [onProgress] is an optional callback invoked periodically with the
  /// fraction complete (0.0 to 1.0). The callback frequency is approximately
  /// every 1% of progress.
  static Uint8List? solveTimeLockPuzzle(
    TimeLockPuzzle puzzle,
    Uint8List startKey, {
    void Function(double progress)? onProgress,
  }) {
    if (startKey.length != 32) {
      throw ArgumentError('Start key must be exactly 32 bytes');
    }

    Uint8List current = Uint8List.fromList(startKey);
    final int progressInterval = (puzzle.iterations / 100).ceil().clamp(
      1,
      puzzle.iterations,
    );

    for (int i = 0; i < puzzle.iterations; i++) {
      current = Uint8List.fromList(sha256.convert(current).bytes);
      if (onProgress != null && i % progressInterval == 0) {
        onProgress(i / puzzle.iterations);
      }
    }

    if (onProgress != null) {
      onProgress(1.0);
    }

    // Verify the result.
    final Uint8List verificationHash = Uint8List.fromList(
      sha256
          .convert(
            Uint8List.fromList([
              ...current,
              ...utf8.encode('timelock-verify-v1'),
            ]),
          )
          .bytes,
    );

    if (!_constantTimeEquals(verificationHash, puzzle.verificationHash)) {
      return null; // Wrong start key or corrupted puzzle.
    }

    return current;
  }

  /// Seals content with a time-locked key.
  ///
  /// The content is encrypted with the time-locked key (hash^N(masterKey)).
  /// The puzzle parameters are stored in public metadata so anyone can solve
  /// the puzzle after the intended duration, but the [masterKey] itself is
  /// required as the starting point for the sequential computation.
  ///
  /// [content] is the raw content to seal.
  /// [masterKey] is the 32-byte master key (puzzle starting point).
  /// [duration] is the desired minimum time before content is accessible.
  /// [options] provides additional sealing options.
  /// [hashRate] is the assumed iterations per second.
  ///
  /// Returns a [TimeLockSealResult] containing the sealed file bytes and
  /// the puzzle for distribution.
  static TimeLockSealResult sealWithTimeLock(
    Uint8List content,
    Uint8List masterKey,
    Duration duration, {
    ZegelOptions? options,
    int hashRate = defaultHashRate,
  }) {
    final TimeLockPuzzle puzzle = createTimeLockPuzzle(
      masterKey,
      duration,
      hashRate: hashRate,
    );

    // Build public metadata with puzzle parameters.
    final Map<String, dynamic> puzzleMeta = <String, dynamic>{
      _puzzleIterationsKey: puzzle.iterations,
      _puzzleHashAlgorithmKey: puzzle.hashAlgorithm,
      _puzzleVerificationHashKey: _bytesToHex(puzzle.verificationHash),
      _puzzleCreatedKey: puzzle.createdEpoch,
      _puzzleTargetKey: puzzle.targetEpoch,
    };

    final Map<String, dynamic> publicMetadata = <String, dynamic>{};
    if (options?.publicMetadata != null) {
      publicMetadata.addAll(options!.publicMetadata!);
    }
    publicMetadata.addAll(puzzleMeta);

    // Seal with the time-locked key.
    final ZegelOptions sealOptions = ZegelOptions(
      contentType: options?.contentType,
      filename: options?.filename,
      metadata: options?.metadata,
      compress: options?.compress ?? false,
      argon2TimeCost: options?.argon2TimeCost,
      argon2MemoryCost: options?.argon2MemoryCost,
      expiration: options?.expiration,
      recipientId: options?.recipientId,
      splitKeyThreshold: options?.splitKeyThreshold,
      splitKeyTotal: options?.splitKeyTotal,
      publicMetadata: publicMetadata,
      versionChainHash: options?.versionChainHash,
      enableKeyCommitment: options?.enableKeyCommitment ?? false,
      enableSelectiveDisclosure: options?.enableSelectiveDisclosure ?? false,
      blockSize: options?.blockSize ?? ZegelFormat.defaultBlockSize,
      salt: options?.salt,
    );

    final ZegelWriter writer = ZegelWriter(puzzle.lockedKey, sealOptions);
    final Uint8List sealedBytes = writer.seal(content);

    return TimeLockSealResult(fileBytes: sealedBytes, puzzle: puzzle);
  }

  /// Extracts puzzle parameters from a .zgl file's public metadata.
  ///
  /// Returns a [TimeLockPuzzle] if the file contains time-lock metadata,
  /// or `null` if it does not.
  static TimeLockPuzzle? extractPuzzle(Uint8List fileBytes) {
    const ZegelReader reader = ZegelReader();
    final ZegelInspection inspection = reader.inspect(fileBytes);

    final Map<String, dynamic>? pubMeta = inspection.publicMetadata;
    if (pubMeta == null ||
        !pubMeta.containsKey(_puzzleIterationsKey) ||
        !pubMeta.containsKey(_puzzleVerificationHashKey)) {
      return null;
    }

    return TimeLockPuzzle(
      iterations: pubMeta[_puzzleIterationsKey] as int,
      hashAlgorithm: (pubMeta[_puzzleHashAlgorithmKey] as String?) ?? 'SHA-256',
      verificationHash: _hexToBytes(
        pubMeta[_puzzleVerificationHashKey] as String,
      ),
      lockedKey: Uint8List(0), // Not stored in metadata for security.
      createdEpoch: (pubMeta[_puzzleCreatedKey] as int?) ?? 0,
      targetEpoch: (pubMeta[_puzzleTargetKey] as int?) ?? 0,
    );
  }

  /// Converts bytes to lowercase hex string.
  static String _bytesToHex(Uint8List bytes) {
    final StringBuffer buf = StringBuffer();
    for (final byte in bytes) {
      buf.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  /// Converts a hex string to bytes.
  static Uint8List _hexToBytes(String hex) {
    final int length = hex.length ~/ 2;
    final Uint8List bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Constant-time comparison of two byte arrays.
  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// Parameters and result of a time-lock puzzle.
class TimeLockPuzzle {
  /// Deserialises a puzzle from a JSON-compatible map.
  factory TimeLockPuzzle.fromJson(Map<String, dynamic> json) {
    return TimeLockPuzzle(
      iterations: json['iterations'] as int,
      hashAlgorithm: (json['hash_algorithm'] as String?) ?? 'SHA-256',
      verificationHash: _hexToBytes(json['verification_hash'] as String),
      lockedKey: Uint8List(0),
      createdEpoch: (json['created_epoch'] as int?) ?? 0,
      targetEpoch: (json['target_epoch'] as int?) ?? 0,
    );
  }

  /// Creates a [TimeLockPuzzle].
  const TimeLockPuzzle({
    required this.iterations,
    required this.hashAlgorithm,
    required this.verificationHash,
    required this.lockedKey,
    required this.createdEpoch,
    required this.targetEpoch,
  });

  /// Number of sequential hash iterations required.
  final int iterations;

  /// Hash algorithm used (always "SHA-256" in v1.2).
  final String hashAlgorithm;

  /// Verification hash to confirm the solver reached the correct result.
  /// Computed as SHA-256(lockedKey || "timelock-verify-v1").
  final Uint8List verificationHash;

  /// The derived key after N iterations. This is the actual encryption key.
  /// Not stored in file metadata -- only available to the puzzle creator.
  final Uint8List lockedKey;

  /// Unix epoch seconds when the puzzle was created.
  final int createdEpoch;

  /// Target Unix epoch seconds when the puzzle should be solvable.
  final int targetEpoch;

  /// Serialises the puzzle to a JSON-compatible map.
  ///
  /// The [lockedKey] is NOT included (it is the secret). Only the parameters
  /// needed by a solver are included.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'iterations': iterations,
      'hash_algorithm': hashAlgorithm,
      'verification_hash': _bytesToHex(verificationHash),
      'created_epoch': createdEpoch,
      'target_epoch': targetEpoch,
    };
  }

  static String _bytesToHex(Uint8List bytes) {
    final StringBuffer buf = StringBuffer();
    for (final byte in bytes) {
      buf.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  static Uint8List _hexToBytes(String hex) {
    final int length = hex.length ~/ 2;
    final Uint8List bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}

/// Result of sealing content with a time-lock.
class TimeLockSealResult {
  /// Creates a [TimeLockSealResult].
  const TimeLockSealResult({required this.fileBytes, required this.puzzle});

  /// The sealed .zgl file bytes.
  final Uint8List fileBytes;

  /// The time-lock puzzle (distribute to intended recipients).
  final TimeLockPuzzle puzzle;
}
