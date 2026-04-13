import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Webhook integration for triggering external services (improvement #25).
///
/// A small, dependency-free HTTP POST dispatcher. Zegel events — successful
/// verification, a batch completing, a seal being created, a token expiring —
/// can be forwarded to user-configured webhook URLs so that automation
/// pipelines can react to them.
///
/// Each payload can be signed with an HMAC-SHA256 shared secret via the
/// `X-Zegel-Signature` header, so the receiver can verify authenticity.
class ZegelWebhook {
  ZegelWebhook({
    required this.url,
    required this.eventType,
    this.secret,
    this.timeout = const Duration(seconds: 10),
    this.headers = const <String, String>{},
  });

  /// The destination URL.
  final Uri url;

  /// Optional shared secret used to HMAC the JSON body.
  final String? secret;

  /// Request timeout.
  final Duration timeout;

  /// Extra headers sent on every request.
  final Map<String, String> headers;

  /// Event type label to include in every payload (e.g. `verify_succeeded`).
  final String eventType;

  /// Builds the canonical JSON payload for an event with the given [data].
  ///
  /// The payload always includes `event`, `timestamp` and `data`.
  String buildPayload(Map<String, dynamic> data, {DateTime? at}) {
    return jsonEncode({
      'event': eventType,
      'timestamp': (at ?? DateTime.now().toUtc()).toUtc().toIso8601String(),
      'data': data,
    });
  }

  /// Computes the HMAC-SHA256 signature for a payload using [secret].
  /// Returns the hex-encoded digest.
  static String signPayload(String payload, String secret) {
    final hmac = Hmac(sha256, utf8.encode(secret));
    return hmac.convert(utf8.encode(payload)).toString();
  }

  /// Sends [data] as an event. Returns the HTTP status code.
  ///
  /// An [httpClient] can be supplied for test injection; otherwise a default
  /// `HttpClient` is used.
  Future<int> dispatch(
    Map<String, dynamic> data, {
    HttpClient? httpClient,
    DateTime? at,
  }) async {
    final payload = buildPayload(data, at: at);
    final bytes = Uint8List.fromList(utf8.encode(payload));
    final client = httpClient ?? HttpClient();
    try {
      final request = await client.postUrl(url).timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.headers.set('User-Agent', 'zegel-webhook/1.0');
      if (secret != null) {
        request.headers.set(
          'X-Zegel-Signature',
          'sha256=${signPayload(payload, secret!)}',
        );
      }
      headers.forEach(request.headers.set);
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(timeout);
      // Drain body to allow connection reuse.
      await response.drain<void>();
      return response.statusCode;
    } finally {
      if (httpClient == null) client.close(force: true);
    }
  }
}
