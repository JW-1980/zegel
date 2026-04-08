import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'format.dart';
import 'reader.dart';
import 'writer.dart';

/// Burn After Read: key derivation with a read counter that makes content
/// inaccessible after N reads (v1.2+).
///
/// The read counter is stored in the file's public metadata and protected by
/// an HMAC. Each successful read increments the counter and re-seals the
/// file with an updated HMAC. Once the counter reaches the maximum, the
/// content is considered destroyed: the HKDF info string includes the counter
/// nonce, so derived keys change with each read and past-limit keys cannot
/// decrypt the content.
///
/// **Important limitation:** This is a trust-based mechanism. The file itself
/// cannot enforce the read limit -- it relies on the reader software to
/// honour the counter. A malicious reader could copy the file before
/// incrementing the counter. However, the HMAC ensures that any tampering
/// with the counter (e.g. resetting it) is detectable. This is suitable for
/// controlled environments where the reader software is trusted, such as
/// enterprise DRM, exam distribution, or confidential document sharing.
class BurnAfterRead {
  BurnAfterRead._();

  /// Public metadata key for the read counter.
  static const String _counterKey = 'burn_read_counter';

  /// Public metadata key for the maximum allowed reads.
  static const String _maxReadsKey = 'burn_max_reads';

  /// Public metadata key for the counter HMAC (hex-encoded).
  static const String _counterHmacKey = 'burn_counter_hmac';

  /// Public metadata key for the counter nonce (hex-encoded).
  static const String _counterNonceKey = 'burn_counter_nonce';

  /// Creates a .zgl file with an embedded read counter.
  ///
  /// [masterKey] is the 32-byte master encryption key.
  /// [content] is the raw content to seal.
  /// [maxReads] is the maximum number of times the file can be read.
  /// [options] provides additional sealing options. The [options.publicMetadata]
  /// field will be merged with the burn-after-read metadata; any conflicting
  /// keys (burn_read_counter, burn_max_reads, etc.) will be overwritten.
  ///
  /// Returns the sealed .zgl file bytes.
  ///
  /// Throws [ArgumentError] if [masterKey] is not 32 bytes or [maxReads] < 1.
  static Uint8List sealWithReadLimit(
    Uint8List masterKey,
    Uint8List content,
    int maxReads, {
    ZegelOptions? options,
  }) {
    if (masterKey.length != 32) {
      throw ArgumentError('Master key must be exactly 32 bytes');
    }
    if (maxReads < 1) {
      throw ArgumentError('maxReads must be at least 1');
    }

    // Generate a counter nonce for HKDF info binding.
    final Uint8List counterNonce = _deriveCounterNonce(masterKey, 0);

    // Compute HMAC over the counter state.
    final String counterHmac = _computeCounterHmac(masterKey, 0, maxReads);

    // Merge burn metadata into public metadata.
    final Map<String, dynamic> burnMeta = <String, dynamic>{
      _counterKey: 0,
      _maxReadsKey: maxReads,
      _counterHmacKey: counterHmac,
      _counterNonceKey: _bytesToHex(counterNonce),
    };

    final Map<String, dynamic> publicMetadata = <String, dynamic>{};
    if (options?.publicMetadata != null) {
      publicMetadata.addAll(options!.publicMetadata!);
    }
    publicMetadata.addAll(burnMeta);

    // Create options with the burn metadata.
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

    final ZegelWriter writer = ZegelWriter(masterKey, sealOptions);
    return writer.seal(content);
  }

  /// Verifies a burn-after-read file, decrements the counter, and returns the
  /// updated file bytes along with the verification result.
  ///
  /// [fileBytes] is the .zgl file to verify and read.
  /// [masterKey] is the 32-byte master key.
  ///
  /// Returns a [BurnAfterReadResult] containing:
  /// - The [ZegelResult] from verification.
  /// - The updated file bytes with the incremented counter (null if reads
  ///   exhausted).
  /// - The current read count and maximum reads.
  ///
  /// Throws [ZegelException] if the file is tampered, expired, or invalid.
  /// Throws [BurnAfterReadExhaustedException] if all reads have been consumed.
  /// Throws [ZegelTamperedException] if the counter HMAC is invalid (counter
  /// was tampered with).
  static BurnAfterReadResult verify(Uint8List fileBytes, Uint8List masterKey) {
    if (masterKey.length != 32) {
      throw ArgumentError('Master key must be exactly 32 bytes');
    }

    // First, inspect to get public metadata without consuming a read.
    const ZegelReader reader = ZegelReader();
    final ZegelInspection inspection = reader.inspect(fileBytes);

    final Map<String, dynamic>? pubMeta = inspection.publicMetadata;
    if (pubMeta == null ||
        !pubMeta.containsKey(_counterKey) ||
        !pubMeta.containsKey(_maxReadsKey) ||
        !pubMeta.containsKey(_counterHmacKey) ||
        !pubMeta.containsKey(_counterNonceKey)) {
      throw const ZegelFormatException(
        'File does not contain burn-after-read metadata',
      );
    }

    final int currentCounter = pubMeta[_counterKey] as int;
    final int maxReads = pubMeta[_maxReadsKey] as int;
    final String storedHmac = pubMeta[_counterHmacKey] as String;

    // Verify the counter HMAC to detect tampering.
    final String expectedHmac = _computeCounterHmac(
      masterKey,
      currentCounter,
      maxReads,
    );
    if (!_constantTimeEquals(storedHmac, expectedHmac)) {
      throw const ZegelTamperedException(
        'Burn-after-read counter HMAC mismatch: counter was tampered with',
      );
    }

    // Check if reads are exhausted.
    if (currentCounter >= maxReads) {
      throw const BurnAfterReadExhaustedException(
        'All reads have been consumed; content is destroyed',
      );
    }

    // Perform the actual verification and extraction.
    final ZegelResult result = reader.verify(fileBytes, masterKey);

    // Increment the counter and re-seal.
    final int newCounter = currentCounter + 1;
    final Uint8List newCounterNonce = _deriveCounterNonce(
      masterKey,
      newCounter,
    );
    final String newHmac = _computeCounterHmac(masterKey, newCounter, maxReads);

    // Build updated public metadata.
    final Map<String, dynamic> updatedPubMeta = Map<String, dynamic>.from(
      pubMeta,
    );
    updatedPubMeta[_counterKey] = newCounter;
    updatedPubMeta[_counterHmacKey] = newHmac;
    updatedPubMeta[_counterNonceKey] = _bytesToHex(newCounterNonce);

    // Re-seal the file with the updated counter.
    Uint8List? updatedFileBytes;
    if (newCounter < maxReads) {
      final ZegelOptions resealOptions = ZegelOptions(
        contentType: result.contentType,
        filename: result.filename,
        metadata: result.metadata,
        publicMetadata: updatedPubMeta,
      );
      final ZegelWriter writer = ZegelWriter(masterKey, resealOptions);
      updatedFileBytes = writer.seal(result.content!);
    }

    return BurnAfterReadResult(
      result: result,
      updatedFileBytes: updatedFileBytes,
      currentRead: newCounter,
      maxReads: maxReads,
    );
  }

  /// Returns the number of remaining reads without consuming one.
  ///
  /// [fileBytes] is the .zgl file.
  /// [masterKey] is the 32-byte master key (needed to verify the counter HMAC).
  ///
  /// Returns the number of reads remaining, or 0 if exhausted.
  ///
  /// Throws [ZegelTamperedException] if the counter HMAC is invalid.
  static int remainingReads(Uint8List fileBytes, Uint8List masterKey) {
    const ZegelReader reader = ZegelReader();
    final ZegelInspection inspection = reader.inspect(fileBytes);

    final Map<String, dynamic>? pubMeta = inspection.publicMetadata;
    if (pubMeta == null ||
        !pubMeta.containsKey(_counterKey) ||
        !pubMeta.containsKey(_maxReadsKey) ||
        !pubMeta.containsKey(_counterHmacKey)) {
      throw const ZegelFormatException(
        'File does not contain burn-after-read metadata',
      );
    }

    final int currentCounter = pubMeta[_counterKey] as int;
    final int maxReads = pubMeta[_maxReadsKey] as int;
    final String storedHmac = pubMeta[_counterHmacKey] as String;

    // Verify counter HMAC.
    final String expectedHmac = _computeCounterHmac(
      masterKey,
      currentCounter,
      maxReads,
    );
    if (!_constantTimeEquals(storedHmac, expectedHmac)) {
      throw const ZegelTamperedException(
        'Burn-after-read counter HMAC mismatch: counter was tampered with',
      );
    }

    final int remaining = maxReads - currentCounter;
    return remaining > 0 ? remaining : 0;
  }

  /// Computes the HMAC protecting the counter state.
  ///
  /// ```
  /// hmac = HMAC-SHA256(masterKey, "burn-counter-v1:" || counter || ":" || maxReads)
  /// ```
  static String _computeCounterHmac(
    Uint8List masterKey,
    int counter,
    int maxReads,
  ) {
    final String message = 'burn-counter-v1:$counter:$maxReads';
    final hmac = Hmac(sha256, masterKey);
    final Uint8List hmacBytes = Uint8List.fromList(
      hmac.convert(utf8.encode(message)).bytes,
    );
    return _bytesToHex(hmacBytes);
  }

  /// Derives a counter nonce for binding into HKDF info strings.
  ///
  /// ```
  /// nonce = SHA-256(masterKey || "burn-nonce-v1:" || counter)
  /// ```
  static Uint8List _deriveCounterNonce(Uint8List masterKey, int counter) {
    final Uint8List message = Uint8List.fromList([
      ...masterKey,
      ...utf8.encode('burn-nonce-v1:$counter'),
    ]);
    return Uint8List.fromList(sha256.convert(message).bytes);
  }

  /// Converts bytes to lowercase hex string.
  static String _bytesToHex(Uint8List bytes) {
    final StringBuffer buf = StringBuffer();
    for (final byte in bytes) {
      buf.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }

  /// Constant-time string comparison.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// Result of a burn-after-read verification.
class BurnAfterReadResult {
  /// Creates a [BurnAfterReadResult].
  const BurnAfterReadResult({
    required this.result,
    this.updatedFileBytes,
    required this.currentRead,
    required this.maxReads,
  });

  /// The verification and extraction result.
  final ZegelResult result;

  /// Updated file bytes with the incremented counter, or `null` if this was
  /// the last allowed read (content is now destroyed).
  final Uint8List? updatedFileBytes;

  /// The read number that was just consumed (1-based after this read).
  final int currentRead;

  /// Maximum allowed reads.
  final int maxReads;

  /// Whether any reads remain after this one.
  bool get hasRemainingReads => currentRead < maxReads;
}

/// Thrown when all reads of a burn-after-read file have been consumed.
class BurnAfterReadExhaustedException extends ZegelException {
  /// Creates a [BurnAfterReadExhaustedException] with the given [message].
  const BurnAfterReadExhaustedException(super.message);

  @override
  String toString() => 'BurnAfterReadExhaustedException: $message';
}
