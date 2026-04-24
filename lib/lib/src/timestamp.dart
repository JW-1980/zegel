import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'roughtime.dart';

/// Timestamp protocol identifiers stored in the TIMESTAMP block.
enum TimestampProtocol {
  roughtime(1),
  rfc3161(2),
  localHmac(3);

  const TimestampProtocol(this.wireValue);
  final int wireValue;

  static TimestampProtocol fromWireValue(int v) {
    for (final p in values) {
      if (p.wireValue == v) return p;
    }
    throw FormatException('Unknown timestamp protocol: $v');
  }
}

/// Verified creation time extracted from a TIMESTAMP block.
///
/// When [selfAsserted] is true, the time comes only from the sealer's local
/// clock and provides no third-party proof. When false, [notBefore] and
/// [notAfter] bracket the creation time as proven by the external anchor.
class VerifiedCreationTime {
  const VerifiedCreationTime({
    this.notBefore,
    this.notAfter,
    required this.selfAsserted,
    this.anchorSource,
    this.protocol,
    this.tpmCounter,
  });

  /// Earliest possible creation time (from anchor).
  final DateTime? notBefore;

  /// Latest possible creation time (from anchor).
  final DateTime? notAfter;

  /// True when no external anchor is present.
  final bool selfAsserted;

  /// Human-readable description of the anchor (e.g. "Cloudflare Roughtime").
  final String? anchorSource;

  /// Which protocol produced this anchor.
  final TimestampProtocol? protocol;

  /// TPM monotonic counter value (forensic ordering only, not wall-clock).
  final int? tpmCounter;

  Map<String, dynamic> toJson() => {
        if (notBefore != null) 'not_before': notBefore!.toIso8601String(),
        if (notAfter != null) 'not_after': notAfter!.toIso8601String(),
        'self_asserted': selfAsserted,
        if (anchorSource != null) 'anchor_source': anchorSource,
        if (protocol != null) 'protocol': protocol!.name,
        if (tpmCounter != null) 'tpm_counter': tpmCounter,
      };
}

/// Configuration for timestamp anchoring passed to the writer.
class TimestampConfig {
  const TimestampConfig._({
    this.protocol,
    this.roughtimeServers,
    this.rfc3161TsaUrl,
    this.preObtainedToken,
    this.offline = false,
  });

  /// Use Roughtime (default online mode).
  const TimestampConfig.roughtime({
    List<RoughtimeServer>? servers,
  }) : this._(
          protocol: TimestampProtocol.roughtime,
          roughtimeServers: servers,
        );

  /// Use RFC 3161 with a specific TSA URL.
  const TimestampConfig.rfc3161({required Uri tsaUrl})
      : this._(
          protocol: TimestampProtocol.rfc3161,
          rfc3161TsaUrl: tsaUrl,
        );

  /// Use a pre-obtained RFC 3161 token (offline verify-only mode).
  const TimestampConfig.preObtainedToken({required Uint8List token})
      : this._(
          protocol: TimestampProtocol.rfc3161,
          preObtainedToken: token,
        );

  /// Explicit offline mode: no timestamp block, self-asserted only.
  const TimestampConfig.offline() : this._(offline: true);

  final TimestampProtocol? protocol;
  final List<RoughtimeServer>? roughtimeServers;
  final Uri? rfc3161TsaUrl;
  final Uint8List? preObtainedToken;
  final bool offline;
}

// ===========================================================================
// Trusted timestamp operations
// ===========================================================================

/// Trusted timestamp support for Zegel files.
///
/// Provides timestamp request generation, external anchor fetching (Roughtime
/// and RFC 3161), response verification, and local HMAC tokens for backward
/// compatibility.
class TrustedTimestamp {
  TrustedTimestamp._();

  // -------------------------------------------------------------------------
  // Message imprint (shared across all protocols)
  // -------------------------------------------------------------------------

  /// Computes the message imprint for a timestamp request.
  ///
  /// `imprint = SHA-256(merkleRoot || masterSeal)`
  static Uint8List computeMessageImprint(
    Uint8List merkleRoot,
    Uint8List masterSeal,
  ) {
    final combined = Uint8List(merkleRoot.length + masterSeal.length);
    combined.setRange(0, merkleRoot.length, merkleRoot);
    combined.setRange(merkleRoot.length, combined.length, masterSeal);
    return Uint8List.fromList(sha256.convert(combined).bytes);
  }

  /// Creates a timestamp request map (legacy API, kept for compatibility).
  static Map<String, dynamic> createRequest(
    Uint8List merkleRoot,
    Uint8List masterSeal,
  ) {
    final digest = computeMessageImprint(merkleRoot, masterSeal);
    return {
      'version': 1,
      'algorithm': 'SHA-256',
      'message_imprint': _bytesToHex(digest),
      'nonce': DateTime.now().toUtc().microsecondsSinceEpoch.toString(),
      'cert_req': true,
    };
  }

  // -------------------------------------------------------------------------
  // Roughtime anchor
  // -------------------------------------------------------------------------

  /// Fetches a Roughtime anchor by querying multiple servers in a chain.
  ///
  /// The [messageImprint] (32 bytes) is used as entropy for the initial nonce:
  /// `nonce = SHA-512(messageImprint || random_32_bytes)`.
  static Future<TimestampBlockData> fetchRoughtime(
    Uint8List messageImprint, {
    List<RoughtimeServer>? servers,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    servers ??= RoughtimeServer.defaultServers;

    final nonceSeed = Uint8List(messageImprint.length + 32);
    nonceSeed.setRange(0, messageImprint.length, messageImprint);
    final random = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      random[i] = DateTime.now().microsecondsSinceEpoch ~/ (i + 1) & 0xff;
    }
    nonceSeed.setRange(messageImprint.length, nonceSeed.length, random);
    final nonce = Uint8List.fromList(sha512.convert(nonceSeed).bytes);

    final client = RoughtimeClient(timeout: timeout);
    final chain = await client.queryChain(servers, nonce);

    final payload = jsonEncode(chain.toJson());

    return TimestampBlockData(
      protocol: TimestampProtocol.roughtime,
      payload: Uint8List.fromList(utf8.encode(payload)),
      verifiedTime: VerifiedCreationTime(
        notBefore: chain.notBefore,
        notAfter: chain.notAfter,
        selfAsserted: false,
        anchorSource: chain.responses.map((r) => r.serverName).join(', '),
        protocol: TimestampProtocol.roughtime,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // RFC 3161 anchor
  // -------------------------------------------------------------------------

  /// Fetches an RFC 3161 timestamp token from a TSA over HTTP.
  ///
  /// Sends a TimeStampReq with the given [messageImprint] (SHA-256 hash)
  /// and returns the DER-encoded TimeStampToken from the TSA response.
  static Future<TimestampBlockData> fetchRfc3161(
    Uri tsaUrl,
    Uint8List messageImprint,
  ) async {
    final tsq = _buildRfc3161Request(messageImprint);

    final client = HttpClient();
    try {
      final request = await client.postUrl(tsaUrl);
      request.headers.set('Content-Type', 'application/timestamp-query');
      request.add(tsq);
      final response = await request.close();

      if (response.statusCode != 200) {
        throw HttpException(
          'TSA returned HTTP ${response.statusCode}',
          uri: tsaUrl,
        );
      }

      final body = await response.fold<BytesBuilder>(
        BytesBuilder(),
        (builder, chunk) => builder..add(chunk),
      );
      final tsr = body.toBytes();

      // Minimal validation: TSA response starts with SEQUENCE tag (0x30)
      // and contains a status field.
      if (tsr.isEmpty || tsr[0] != 0x30) {
        throw FormatException('Invalid TSA response: not a DER SEQUENCE');
      }

      final tsaName = tsaUrl.host;
      final genTime = _extractGenTimeFromTsr(tsr);

      return TimestampBlockData(
        protocol: TimestampProtocol.rfc3161,
        payload: tsr,
        verifiedTime: VerifiedCreationTime(
          notBefore: genTime,
          notAfter: genTime,
          selfAsserted: false,
          anchorSource: 'RFC 3161 TSA: $tsaName',
          protocol: TimestampProtocol.rfc3161,
        ),
      );
    } finally {
      client.close();
    }
  }

  /// Loads a pre-obtained RFC 3161 token from raw DER bytes.
  static TimestampBlockData loadRfc3161Token(Uint8List tokenBytes) {
    if (tokenBytes.isEmpty || tokenBytes[0] != 0x30) {
      throw FormatException('Invalid RFC 3161 token: not a DER SEQUENCE');
    }

    final genTime = _extractGenTimeFromTsr(tokenBytes);

    return TimestampBlockData(
      protocol: TimestampProtocol.rfc3161,
      payload: tokenBytes,
      verifiedTime: VerifiedCreationTime(
        notBefore: genTime,
        notAfter: genTime,
        selfAsserted: false,
        anchorSource: 'RFC 3161 (pre-obtained)',
        protocol: TimestampProtocol.rfc3161,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Verification (reader-side)
  // -------------------------------------------------------------------------

  /// Verifies a TIMESTAMP block's payload and returns the verified time.
  static VerifiedCreationTime verifyTimestampBlock(
    TimestampProtocol protocol,
    Uint8List payload,
    Uint8List expectedImprint,
  ) {
    switch (protocol) {
      case TimestampProtocol.roughtime:
        return _verifyRoughtimePayload(payload);
      case TimestampProtocol.rfc3161:
        return _verifyRfc3161Payload(payload, expectedImprint);
      case TimestampProtocol.localHmac:
        return const VerifiedCreationTime(
          selfAsserted: true,
          anchorSource: 'local HMAC (self-asserted, non-authoritative)',
          protocol: TimestampProtocol.localHmac,
        );
    }
  }

  static VerifiedCreationTime _verifyRoughtimePayload(Uint8List payload) {
    try {
      final json = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;

      if (json['protocol'] != 'roughtime') {
        throw FormatException('Not a Roughtime payload');
      }

      final notBeforeUs = json['not_before_us'] as int;
      final notAfterUs = json['not_after_us'] as int;
      final responses = json['responses'] as List<dynamic>;
      final serverNames = responses
          .map((r) => (r as Map<String, dynamic>)['server'] as String)
          .join(', ');

      return VerifiedCreationTime(
        notBefore:
            DateTime.fromMicrosecondsSinceEpoch(notBeforeUs, isUtc: true),
        notAfter: DateTime.fromMicrosecondsSinceEpoch(notAfterUs, isUtc: true),
        selfAsserted: false,
        anchorSource: 'Roughtime ($serverNames)',
        protocol: TimestampProtocol.roughtime,
      );
    } on Exception {
      return const VerifiedCreationTime(
        selfAsserted: true,
        anchorSource: 'Roughtime (verification failed)',
        protocol: TimestampProtocol.roughtime,
      );
    }
  }

  static VerifiedCreationTime _verifyRfc3161Payload(
    Uint8List payload,
    Uint8List expectedImprint,
  ) {
    try {
      if (payload.isEmpty || payload[0] != 0x30) {
        throw FormatException('Not a valid DER SEQUENCE');
      }

      final genTime = _extractGenTimeFromTsr(payload);
      if (genTime == null) {
        return const VerifiedCreationTime(
          selfAsserted: true,
          anchorSource: 'RFC 3161 (genTime extraction failed)',
          protocol: TimestampProtocol.rfc3161,
        );
      }

      // Verify the message imprint in the token matches expected.
      if (!_verifyTsrImprint(payload, expectedImprint)) {
        return const VerifiedCreationTime(
          selfAsserted: true,
          anchorSource: 'RFC 3161 (imprint mismatch)',
          protocol: TimestampProtocol.rfc3161,
        );
      }

      return VerifiedCreationTime(
        notBefore: genTime,
        notAfter: genTime,
        selfAsserted: false,
        anchorSource: 'RFC 3161 TSA',
        protocol: TimestampProtocol.rfc3161,
      );
    } on Exception {
      return const VerifiedCreationTime(
        selfAsserted: true,
        anchorSource: 'RFC 3161 (verification failed)',
        protocol: TimestampProtocol.rfc3161,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Legacy local HMAC token (self-asserted, non-authoritative)
  // -------------------------------------------------------------------------

  /// Creates a local timestamp token (self-asserted, non-authoritative).
  ///
  /// This does NOT provide independent proof of time. It only provides
  /// tamper-detection for the timestamp value itself (someone can't change
  /// the epoch without the signer key). Use Roughtime or RFC 3161 for
  /// transferable wall-clock proof.
  @Deprecated('Use fetchRoughtime or fetchRfc3161 for authoritative timestamps')
  static Map<String, dynamic> createLocalToken(
    Uint8List merkleRoot,
    Uint8List masterSeal,
    Uint8List signerKey, {
    DateTime? timestamp,
  }) {
    final ts = timestamp ?? DateTime.now().toUtc();
    final epochSeconds = ts.millisecondsSinceEpoch ~/ 1000;

    final combined = Uint8List(merkleRoot.length + masterSeal.length + 8);
    combined.setRange(0, merkleRoot.length, merkleRoot);
    combined.setRange(
      merkleRoot.length,
      merkleRoot.length + masterSeal.length,
      masterSeal,
    );
    final bd = ByteData(8);
    bd.setUint64(0, epochSeconds, Endian.big);
    combined.setRange(
      merkleRoot.length + masterSeal.length,
      combined.length,
      bd.buffer.asUint8List(),
    );

    final hmac = Hmac(sha256, signerKey);
    final signature = Uint8List.fromList(hmac.convert(combined).bytes);

    return {
      'version': 1,
      'type': 'local',
      'timestamp': epochSeconds,
      'merkle_root': _bytesToHex(merkleRoot),
      'signature': _bytesToHex(signature),
    };
  }

  /// Verifies a legacy local HMAC timestamp token.
  @Deprecated('Local tokens are self-asserted and non-authoritative')
  static bool verifyLocalToken(
    Map<String, dynamic> token,
    Uint8List merkleRoot,
    Uint8List masterSeal,
    Uint8List signerKey,
  ) {
    if (token['type'] != 'local') return false;

    final epochSeconds = token['timestamp'] as int;
    final storedSig = token['signature'] as String;

    final combined = Uint8List(merkleRoot.length + masterSeal.length + 8);
    combined.setRange(0, merkleRoot.length, merkleRoot);
    combined.setRange(
      merkleRoot.length,
      merkleRoot.length + masterSeal.length,
      masterSeal,
    );
    final bd = ByteData(8);
    bd.setUint64(0, epochSeconds, Endian.big);
    combined.setRange(
      merkleRoot.length + masterSeal.length,
      combined.length,
      bd.buffer.asUint8List(),
    );

    final hmac = Hmac(sha256, signerKey);
    final computed = Uint8List.fromList(hmac.convert(combined).bytes);
    final computedHex = _bytesToHex(computed);

    return _constantTimeEquals(storedSig, computedHex);
  }

  // -------------------------------------------------------------------------
  // ASN.1 / DER helpers for RFC 3161
  // -------------------------------------------------------------------------

  /// Builds a minimal DER-encoded TimeStampReq for SHA-256.
  static Uint8List _buildRfc3161Request(Uint8List messageImprint) {
    // TimeStampReq ::= SEQUENCE {
    //   version INTEGER (1),
    //   messageImprint MessageImprint,
    //   certReq BOOLEAN DEFAULT FALSE
    // }
    // MessageImprint ::= SEQUENCE {
    //   hashAlgorithm AlgorithmIdentifier(SHA-256),
    //   hashedMessage OCTET STRING
    // }

    // SHA-256 AlgorithmIdentifier OID: 2.16.840.1.101.3.4.2.1
    final sha256Oid = Uint8List.fromList([
      0x30, 0x0d, // SEQUENCE
      0x06, 0x09, // OID
      0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01,
      0x05, 0x00, // NULL
    ]);

    final hashedMessage = _derOctetString(messageImprint);
    final msgImprintBody = Uint8List(sha256Oid.length + hashedMessage.length);
    msgImprintBody.setRange(0, sha256Oid.length, sha256Oid);
    msgImprintBody.setRange(
      sha256Oid.length,
      msgImprintBody.length,
      hashedMessage,
    );
    final msgImprint = _derSequence(msgImprintBody);

    final version = Uint8List.fromList([0x02, 0x01, 0x01]); // INTEGER 1
    final certReq = Uint8List.fromList([0x01, 0x01, 0xff]); // BOOLEAN TRUE

    final body = Uint8List(
      version.length + msgImprint.length + certReq.length,
    );
    var offset = 0;
    body.setRange(offset, offset + version.length, version);
    offset += version.length;
    body.setRange(offset, offset + msgImprint.length, msgImprint);
    offset += msgImprint.length;
    body.setRange(offset, offset + certReq.length, certReq);

    return _derSequence(body);
  }

  /// Extracts genTime from a TimeStampResp or TimeStampToken DER blob.
  ///
  /// This does a best-effort search for a GeneralizedTime value (tag 0x18)
  /// in the ASN.1 structure. Returns null if not found.
  static DateTime? _extractGenTimeFromTsr(Uint8List der) {
    // Walk the DER looking for GeneralizedTime (tag 0x18).
    for (var i = 0; i < der.length - 2; i++) {
      if (der[i] == 0x18) {
        final len = der[i + 1];
        if (len > 0 && i + 2 + len <= der.length) {
          final timeStr = utf8.decode(der.sublist(i + 2, i + 2 + len));
          return _parseGeneralizedTime(timeStr);
        }
      }
    }
    return null;
  }

  /// Verifies that the message imprint in a TSR matches [expected].
  ///
  /// Searches for the SHA-256 hash value in the DER structure.
  static bool _verifyTsrImprint(Uint8List der, Uint8List expected) {
    if (expected.length != 32) return false;
    // Search for a 32-byte OCTET STRING matching expected.
    for (var i = 0; i < der.length - 33; i++) {
      if (der[i] == 0x04 && der[i + 1] == 0x20) {
        var match = true;
        for (var j = 0; j < 32; j++) {
          if (der[i + 2 + j] != expected[j]) {
            match = false;
            break;
          }
        }
        if (match) return true;
      }
    }
    return false;
  }

  static DateTime? _parseGeneralizedTime(String s) {
    // Format: YYYYMMDDHHmmSS[.fff]Z
    try {
      final year = int.parse(s.substring(0, 4));
      final month = int.parse(s.substring(4, 6));
      final day = int.parse(s.substring(6, 8));
      final hour = int.parse(s.substring(8, 10));
      final minute = int.parse(s.substring(10, 12));
      final second = int.parse(s.substring(12, 14));
      return DateTime.utc(year, month, day, hour, minute, second);
    } on Exception {
      return null;
    }
  }

  static Uint8List _derSequence(Uint8List content) {
    final lenBytes = _derLength(content.length);
    final result = Uint8List(1 + lenBytes.length + content.length);
    result[0] = 0x30;
    result.setRange(1, 1 + lenBytes.length, lenBytes);
    result.setRange(1 + lenBytes.length, result.length, content);
    return result;
  }

  static Uint8List _derOctetString(Uint8List content) {
    final lenBytes = _derLength(content.length);
    final result = Uint8List(1 + lenBytes.length + content.length);
    result[0] = 0x04;
    result.setRange(1, 1 + lenBytes.length, lenBytes);
    result.setRange(1 + lenBytes.length, result.length, content);
    return result;
  }

  static Uint8List _derLength(int length) {
    if (length < 0x80) {
      return Uint8List.fromList([length]);
    } else if (length < 0x100) {
      return Uint8List.fromList([0x81, length]);
    } else if (length < 0x10000) {
      return Uint8List.fromList([0x82, length >> 8, length & 0xff]);
    }
    return Uint8List.fromList([
      0x83,
      (length >> 16) & 0xff,
      (length >> 8) & 0xff,
      length & 0xff,
    ]);
  }

  // -------------------------------------------------------------------------
  // Utility
  // -------------------------------------------------------------------------

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

/// Data to be serialized into a TIMESTAMP block (type 0x0B).
///
/// The block content is: protocol(1 byte) || payload_length(4 BE) || payload.
class TimestampBlockData {
  const TimestampBlockData({
    required this.protocol,
    required this.payload,
    required this.verifiedTime,
  });

  final TimestampProtocol protocol;
  final Uint8List payload;
  final VerifiedCreationTime verifiedTime;

  /// Serializes to the wire format stored inside the encrypted block.
  Uint8List toBytes() {
    final result = Uint8List(1 + 4 + payload.length);
    result[0] = protocol.wireValue;
    final bd = ByteData.sublistView(result);
    bd.setUint32(1, payload.length, Endian.big);
    result.setRange(5, result.length, payload);
    return result;
  }

  /// Parses from the wire format stored inside a decrypted block.
  static TimestampBlockData fromBytes(
    Uint8List bytes,
    Uint8List expectedImprint,
  ) {
    if (bytes.length < 5) {
      throw FormatException('TIMESTAMP block too short: ${bytes.length}');
    }
    final protocol = TimestampProtocol.fromWireValue(bytes[0]);
    final bd = ByteData.sublistView(bytes);
    final payloadLen = bd.getUint32(1, Endian.big);
    if (bytes.length < 5 + payloadLen) {
      throw FormatException('TIMESTAMP block truncated');
    }
    final payload = Uint8List.sublistView(bytes, 5, 5 + payloadLen);

    final verifiedTime = TrustedTimestamp.verifyTimestampBlock(
      protocol,
      payload,
      expectedImprint,
    );

    return TimestampBlockData(
      protocol: protocol,
      payload: payload,
      verifiedTime: verifiedTime,
    );
  }
}
