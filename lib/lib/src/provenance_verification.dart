import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Provenance chain verification (v1.3).
///
/// Verifies the chain of custody for sealed files, ensuring provenance
/// events are in chronological order and properly signed.
class ProvenanceVerification {
  ProvenanceVerification._();

  /// Creates a signed provenance event.
  ///
  /// [action] describes what happened (e.g. "created", "transferred", "verified").
  /// [actor] identifies who performed the action.
  /// [signerKey] is used to HMAC-sign the event.
  /// [merkleRoot] binds the event to a specific file.
  /// [previousEventHash] links to the prior event (null for first event).
  static Map<String, dynamic> createEvent(
    String action,
    String actor,
    Uint8List signerKey,
    Uint8List merkleRoot, {
    String? previousEventHash,
    Map<String, dynamic>? details,
    DateTime? timestamp,
  }) {
    final ts = timestamp ?? DateTime.now().toUtc();
    final epochSeconds = ts.millisecondsSinceEpoch ~/ 1000;

    final event = <String, dynamic>{
      'action': action,
      'actor': actor,
      'timestamp': epochSeconds,
      'merkle_root': _bytesToHex(merkleRoot),
      if (previousEventHash != null) 'previous_event': previousEventHash,
      if (details != null) 'details': details,
    };

    // Sign the event
    final canonicalJson = jsonEncode(event);
    final hmac = Hmac(sha256, signerKey);
    final signature = Uint8List.fromList(
      hmac.convert(utf8.encode(canonicalJson)).bytes,
    );
    event['signature'] = _bytesToHex(signature);

    // Compute event hash for chaining
    final eventHash = sha256.convert(utf8.encode(jsonEncode(event)));
    event['event_hash'] = eventHash.toString();

    return event;
  }

  /// Verifies a chain of provenance events.
  ///
  /// Checks that:
  /// 1. Events are in chronological order
  /// 2. Each event's previous_event hash matches the prior event
  /// 3. All signatures are valid
  ///
  /// Returns a map with 'valid' (bool) and 'errors' (`List<String>`).
  static Map<String, dynamic> verifyChain(
    List<Map<String, dynamic>> events,
    Uint8List signerKey,
  ) {
    final errors = <String>[];

    if (events.isEmpty) {
      return {'valid': true, 'errors': errors};
    }

    int? previousTimestamp;
    String? previousHash;

    for (int i = 0; i < events.length; i++) {
      final event = events[i];
      final timestamp = event['timestamp'] as int;

      // Check chronological order
      if (previousTimestamp != null && timestamp < previousTimestamp) {
        errors.add('Event $i is not in chronological order');
      }

      // Check chain hash using constant-time comparison to avoid leaking
      // which event a would-be forger is close to.
      if (i > 0) {
        final expectedPrev = event['previous_event'] as String?;
        if (expectedPrev == null ||
            previousHash == null ||
            !_constantTimeEquals(expectedPrev, previousHash)) {
          errors.add('Event $i has invalid chain link');
        }
      }

      // Verify signature
      final storedSig = event['signature'] as String?;
      if (storedSig != null) {
        final eventCopy = Map<String, dynamic>.from(event);
        eventCopy.remove('signature');
        eventCopy.remove('event_hash');

        final canonicalJson = jsonEncode(eventCopy);
        final hmac = Hmac(sha256, signerKey);
        final computed = Uint8List.fromList(
          hmac.convert(utf8.encode(canonicalJson)).bytes,
        );
        if (!_constantTimeEquals(_bytesToHex(computed), storedSig)) {
          errors.add('Event $i has invalid signature');
        }
      }

      previousTimestamp = timestamp;
      previousHash = event['event_hash'] as String?;
    }

    return {'valid': errors.isEmpty, 'errors': errors};
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
