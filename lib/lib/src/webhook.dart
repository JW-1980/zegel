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
///
/// **Security defaults:**
/// - Only `https://` URLs are accepted. Plain `http://` would leak event
///   contents and HMAC signatures to any on-path attacker.
/// - Loopback / link-local / RFC 1918 / ULA hosts are rejected to prevent
///   server-side request forgery from abusing webhooks to probe internal
///   services. Set [allowPrivateHosts] to `true` to opt out when talking to
///   an intentional on-LAN listener.
class ZegelWebhook {
  ZegelWebhook({
    required this.url,
    required this.eventType,
    this.secret,
    this.timeout = const Duration(seconds: 10),
    this.headers = const <String, String>{},
    this.allowPrivateHosts = false,
    this.allowHttp = false,
  }) {
    _validateUrl(url,
        allowPrivateHosts: allowPrivateHosts, allowHttp: allowHttp);
  }

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

  /// Whether to allow webhook deliveries to loopback / private-network hosts.
  /// Default `false` rejects SSRF-prone targets like `127.0.0.1`, `10.0.0.0/8`,
  /// `192.168.0.0/16`, `172.16.0.0/12`, and IPv6 ULAs (`fc00::/7`).
  final bool allowPrivateHosts;

  /// Whether to allow plain `http://` URLs. Default `false` only accepts
  /// `https://` to avoid leaking payloads (including HMAC signatures) to
  /// on-path attackers.
  final bool allowHttp;

  /// Validates the target URL for scheme and host safety. Throws
  /// [ArgumentError] if the URL uses an unsupported scheme or targets a
  /// reserved / private host (unless explicitly opted in).
  static void _validateUrl(
    Uri url, {
    required bool allowPrivateHosts,
    required bool allowHttp,
  }) {
    final scheme = url.scheme.toLowerCase();
    if (scheme != 'https' && !(allowHttp && scheme == 'http')) {
      throw ArgumentError.value(
        url.toString(),
        'url',
        'Webhook URL must use https:// '
            '(pass allowHttp: true to accept http:// explicitly)',
      );
    }
    final host = url.host;
    if (host.isEmpty) {
      throw ArgumentError.value(
          url.toString(), 'url', 'Webhook URL has no host');
    }
    if (allowPrivateHosts) return;

    final lower = host.toLowerCase();
    // Reject obvious loopback / metadata aliases.
    const bannedHostnames = <String>{
      'localhost',
      'ip6-localhost',
      'ip6-loopback',
      'broadcasthost',
      // AWS / GCP / Azure instance metadata.
      'metadata.google.internal',
      'metadata.goog',
    };
    if (bannedHostnames.contains(lower)) {
      throw ArgumentError.value(
        url.toString(),
        'url',
        'Webhook URL targets a reserved host ($host). '
            'Pass allowPrivateHosts: true if intentional.',
      );
    }

    // Try to parse as a literal IP. If it parses, apply address-family checks.
    final InternetAddress? addr = _tryParseIp(lower);
    if (addr != null) {
      if (_isForbiddenAddress(addr)) {
        throw ArgumentError.value(
          url.toString(),
          'url',
          'Webhook URL targets a loopback, link-local, or private '
              'address ($host). Pass allowPrivateHosts: true if intentional.',
        );
      }
    }
  }

  static InternetAddress? _tryParseIp(String host) {
    // Strip bracketed IPv6 literals (Uri.host returns unbracketed, but be safe).
    final cleaned = host.startsWith('[') && host.endsWith(']')
        ? host.substring(1, host.length - 1)
        : host;
    return InternetAddress.tryParse(cleaned);
  }

  static bool _isForbiddenAddress(InternetAddress addr) {
    if (addr.isLoopback || addr.isLinkLocal || addr.isMulticast) return true;
    final raw = addr.rawAddress;
    if (addr.type == InternetAddressType.IPv4 && raw.length == 4) {
      final a = raw[0];
      final b = raw[1];
      // 10.0.0.0/8
      if (a == 10) return true;
      // 172.16.0.0/12
      if (a == 172 && (b & 0xF0) == 16) return true;
      // 192.168.0.0/16
      if (a == 192 && b == 168) return true;
      // 169.254.0.0/16 is link-local (already covered) but be explicit.
      if (a == 169 && b == 254) return true;
      // 0.0.0.0/8 (any address)
      if (a == 0) return true;
      // 127.0.0.0/8 (loopback) -- already covered by isLoopback.
    } else if (addr.type == InternetAddressType.IPv6 && raw.length == 16) {
      // fc00::/7 (Unique Local Addresses)
      if ((raw[0] & 0xFE) == 0xFC) return true;
      // ::1 is loopback (covered). fe80::/10 is link-local (covered).
      // ::ffff:0:0/96 (IPv4-mapped): re-check as IPv4.
      bool isV4Mapped = true;
      for (int i = 0; i < 10; i++) {
        if (raw[i] != 0) {
          isV4Mapped = false;
          break;
        }
      }
      if (isV4Mapped && raw[10] == 0xFF && raw[11] == 0xFF) {
        final mapped = InternetAddress.fromRawAddress(
          Uint8List.fromList(raw.sublist(12, 16)),
          type: InternetAddressType.IPv4,
        );
        return _isForbiddenAddress(mapped);
      }
    }
    return false;
  }

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
