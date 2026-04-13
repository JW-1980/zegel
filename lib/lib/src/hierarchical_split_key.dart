import 'dart:math';
import 'dart:typed_data';

import 'shamir.dart';

/// Hierarchical split-key for multi-level access control.
///
/// Implements nested Shamir's Secret Sharing where higher classification
/// levels require additional key shares beyond the base threshold. The master
/// key is split into intermediate keys using XOR chaining, and each
/// intermediate key is further split using Shamir's Secret Sharing with
/// level-specific thresholds.
///
/// Example:
/// - CONFIDENTIAL requires 2-of-3 shares to reconstruct the first
///   intermediate key.
/// - SECRET requires those 2 shares **plus** 2-of-3 additional shares to
///   reconstruct the second intermediate key.
/// - The master key is recovered by XOR-combining all intermediate keys up to
///   the target level.
///
/// This enables organisations to enforce multi-level access control where
/// each higher level requires progressively more signers, without issuing
/// separate master keys per level.
///
/// Use cases:
/// - **Government**: Documents classified at different levels share a single
///   master key, but higher-clearance content requires more key-holders to
///   collaborate.
/// - **Finance**: Trade confirmations need 2 signers, but settlements need 4.
/// - **Healthcare**: General records need 2 of 3, but psychiatric notes
///   need an additional 2 of 3 specialists.
class HierarchicalSplitKey {
  HierarchicalSplitKey._();

  /// Splits a master key into hierarchical share groups.
  ///
  /// The [masterKey] is decomposed into intermediate keys such that
  /// `masterKey = intermediateKey_0 XOR intermediateKey_1 XOR ... XOR intermediateKey_n`.
  ///
  /// Each intermediate key is then split using Shamir's Secret Sharing with
  /// the threshold and share count specified in the corresponding [levels]
  /// entry.
  ///
  /// [levels] must contain at least one level, ordered from least restrictive
  /// to most restrictive.
  ///
  /// Returns a [HierarchicalShares] containing the shares grouped by
  /// classification level.
  static HierarchicalShares split(
    final Uint8List masterKey,
    List<ShareLevel> levels,
  ) {
    if (masterKey.length != 32) {
      throw ArgumentError('Master key must be exactly 32 bytes');
    }
    if (levels.isEmpty) {
      throw ArgumentError('At least one share level is required');
    }

    // Generate intermediate keys using XOR chaining.
    // key_0 XOR key_1 XOR ... XOR key_n = masterKey
    // We generate random intermediate keys for levels 0..n-1 and compute the
    // last one so the XOR of all equals the master key.
    final List<Uint8List> intermediateKeys = <Uint8List>[];
    final Random rng = Random.secure();

    final Uint8List xorAccumulator = Uint8List(32);
    for (int i = 0; i < levels.length - 1; i++) {
      final Uint8List key = Uint8List(32);
      for (int j = 0; j < 32; j++) {
        key[j] = rng.nextInt(256);
      }
      intermediateKeys.add(key);
      for (int j = 0; j < 32; j++) {
        xorAccumulator[j] ^= key[j];
      }
    }

    // Last intermediate key = masterKey XOR (all previous intermediate keys).
    final Uint8List lastKey = Uint8List(32);
    for (int j = 0; j < 32; j++) {
      lastKey[j] = masterKey[j] ^ xorAccumulator[j];
    }
    intermediateKeys.add(lastKey);

    // Split each intermediate key with Shamir's Secret Sharing.
    final Map<String, List<Uint8List>> sharesByLevel =
        <String, List<Uint8List>>{};

    for (int i = 0; i < levels.length; i++) {
      final ShareLevel level = levels[i];
      final List<Uint8List> shares = ShamirSecretSharing.split(
        intermediateKeys[i],
        level.threshold,
        level.totalShares,
      );
      sharesByLevel[level.classification] = shares;
    }

    return HierarchicalShares(sharesByLevel: sharesByLevel);
  }

  /// Reconstructs the master key from shares at the specified levels.
  ///
  /// [providedShares] contains the shares for each level that the user can
  /// access. The user must provide shares for **all** levels in [levels]
  /// to reconstruct the full master key.
  ///
  /// [levels] defines the threshold requirements per level (must match the
  /// configuration used during [split]).
  ///
  /// Returns the reconstructed 32-byte master key.
  ///
  /// Throws [ArgumentError] if insufficient shares are provided for any level.
  static Uint8List reconstruct(
    List<LevelShares> providedShares,
    List<ShareLevel> levels,
  ) {
    if (providedShares.length != levels.length) {
      throw ArgumentError(
        'Must provide shares for all ${levels.length} levels, '
        'got ${providedShares.length}',
      );
    }

    // Build a map for quick lookup.
    final Map<String, LevelShares> shareMap = <String, LevelShares>{};
    for (final LevelShares ls in providedShares) {
      shareMap[ls.classification] = ls;
    }

    // Reconstruct each intermediate key and XOR them together.
    final Uint8List masterKey = Uint8List(32);

    for (final ShareLevel level in levels) {
      final LevelShares? ls = shareMap[level.classification];
      if (ls == null) {
        throw ArgumentError(
          'No shares provided for level "${level.classification}"',
        );
      }
      if (ls.shares.length < level.threshold) {
        throw ArgumentError(
          'Level "${level.classification}" requires ${level.threshold} shares, '
          'but only ${ls.shares.length} were provided',
        );
      }

      final Uint8List intermediateKey = ShamirSecretSharing.reconstruct(
        ls.shares.sublist(0, level.threshold),
        level.threshold,
      );

      // XOR the intermediate key into the master key accumulator.
      for (int j = 0; j < 32; j++) {
        masterKey[j] ^= intermediateKey[j];
      }
    }

    return masterKey;
  }
}

/// Defines a single level in a hierarchical split-key scheme.
class ShareLevel {
  /// Creates a [ShareLevel].
  ///
  /// [classification] is the level name (e.g. `"CONFIDENTIAL"`, `"SECRET"`).
  /// [threshold] is the minimum number of shares needed (M).
  /// [totalShares] is the total number of shares generated (N).
  ShareLevel({
    required this.classification,
    required this.threshold,
    required this.totalShares,
  }) {
    if (threshold < 1) {
      throw ArgumentError('Threshold must be at least 1');
    }
    if (totalShares < threshold) {
      throw ArgumentError('Total shares must be >= threshold');
    }
  }

  /// The classification level name.
  final String classification;

  /// Minimum shares needed to reconstruct (M).
  final int threshold;

  /// Total shares generated (N).
  final int totalShares;
}

/// Contains the Shamir shares grouped by classification level.
class HierarchicalShares {
  /// Creates a [HierarchicalShares].
  HierarchicalShares({required this.sharesByLevel});

  /// Map from classification level to the list of Shamir shares.
  ///
  /// Each share is a byte array in the format used by [ShamirSecretSharing].
  final Map<String, List<Uint8List>> sharesByLevel;
}

/// Shares provided for a single level during reconstruction.
class LevelShares {
  /// Creates a [LevelShares].
  ///
  /// [classification] must match the level name used during splitting.
  /// [shares] is the list of Shamir shares available for this level.
  LevelShares({required this.classification, required this.shares});

  /// The classification level name.
  final String classification;

  /// The Shamir shares for this level.
  final List<Uint8List> shares;
}
