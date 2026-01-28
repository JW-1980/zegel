import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Multi-file manifest for batch integrity (v1.3).
///
/// A manifest is a signed JSON document that lists multiple .zgl files with
/// their Merkle roots and file hashes, enabling batch verification of
/// document sets (e.g. all files in a real estate closing).
class ZegelManifest {
  ZegelManifest._();

  /// Creates a manifest for a set of files.
  ///
  /// [entries] maps filenames to their Merkle root (32 bytes).
  /// [signerKey] is the 32-byte key used to HMAC-sign the manifest.
  /// [signerId] identifies the manifest creator.
  ///
  /// Returns a JSON-serialisable map.
  static Map<String, dynamic> create(
    Map<String, Uint8List> entries,
    Uint8List signerKey,
    String signerId,
  ) {
    final fileEntries = <Map<String, String>>[];
    for (final entry in entries.entries) {
      fileEntries.add({
        'filename': entry.key,
        'merkle_root': _bytesToHex(entry.value),
      });
    }

    final int createdAt = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

    final payload = <String, dynamic>{
      'version': 1,
      'signer_id': signerId,
      'created_at': createdAt,
      'files': fileEntries,
    };

    // Sign the canonical JSON of files + metadata.
    final canonicalJson = jsonEncode({
      'version': 1,
      'signer_id': signerId,
      'created_at': createdAt,
      'files': fileEntries,
    });
    final hmac = Hmac(sha256, signerKey);
    final signature = Uint8List.fromList(
      hmac.convert(utf8.encode(canonicalJson)).bytes,
    );

    payload['signature'] = _bytesToHex(signature);
    return payload;
  }

  /// Verifies a manifest's signature.
  ///
  /// Returns true if the HMAC signature matches.
  static bool verify(Map<String, dynamic> manifest, Uint8List signerKey) {
    final storedSig = manifest['signature'] as String;

    // Reconstruct payload without signature.
    final payload = <String, dynamic>{
      'version': manifest['version'],
      'signer_id': manifest['signer_id'],
      'created_at': manifest['created_at'],
      'files': manifest['files'],
    };

    final canonicalJson = jsonEncode(payload);
    final hmac = Hmac(sha256, signerKey);
    final computed = Uint8List.fromList(
      hmac.convert(utf8.encode(canonicalJson)).bytes,
    );
    final computedHex = _bytesToHex(computed);

    return _constantTimeEquals(storedSig, computedHex);
  }

  /// Checks whether all files in the manifest match expected Merkle roots.
  ///
  /// [actualRoots] maps filenames to their actual Merkle root bytes.
  /// Returns a map of filename -> match result.
  static Map<String, bool> checkFiles(
    Map<String, dynamic> manifest,
    Map<String, Uint8List> actualRoots,
  ) {
    final files = manifest['files'] as List<dynamic>;
    final results = <String, bool>{};

    for (final file in files) {
      final fileMap = file as Map<String, dynamic>;
      final filename = fileMap['filename'] as String;
      final expectedRoot = fileMap['merkle_root'] as String;

      if (actualRoots.containsKey(filename)) {
        results[filename] = _bytesToHex(actualRoots[filename]!) == expectedRoot;
      } else {
        results[filename] = false;
      }
    }
    return results;
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
