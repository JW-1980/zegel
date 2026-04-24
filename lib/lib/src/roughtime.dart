import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pinenacl/ed25519.dart' as pinenacl;

/// Pure-Dart Roughtime client (draft-roughtime-aanchal compatible).
///
/// Roughtime is a protocol for obtaining rough, authenticated wall-clock time
/// from multiple servers. Each response is cryptographically signed and binds
/// the client's nonce, making replay and forgery detectable.
///
/// Querying multiple servers in a chain (each nonce derived from the previous
/// response) produces an auditable happens-before chain that detects lying
/// servers after the fact.

// ---------------------------------------------------------------------------
// Wire format: tag-length-value messages
// ---------------------------------------------------------------------------

/// A single tag-value pair in a Roughtime message.
class RoughtimeTag {
  const RoughtimeTag(this.tag, this.value);

  final int tag;
  final Uint8List value;
}

/// Encodes a list of tag-value pairs into the Roughtime wire format.
///
/// Tags must be provided in ascending uint32-LE order. The format is:
///   uint32 LE  num_tags
///   (num_tags - 1) x uint32 LE  cumulative offsets
///   num_tags x 4-byte tags
///   concatenated values
Uint8List encodeMessage(List<RoughtimeTag> tags) {
  if (tags.isEmpty) return Uint8List(4); // just num_tags = 0

  final numTags = tags.length;
  var totalValueLen = 0;
  for (final t in tags) {
    totalValueLen += t.value.length;
  }

  final headerLen = 4 + (numTags - 1) * 4 + numTags * 4;
  final buf = ByteData(headerLen + totalValueLen);
  var offset = 0;

  buf.setUint32(offset, numTags, Endian.little);
  offset += 4;

  var cumOffset = 0;
  for (var i = 0; i < numTags - 1; i++) {
    cumOffset += tags[i].value.length;
    buf.setUint32(offset, cumOffset, Endian.little);
    offset += 4;
  }

  for (final t in tags) {
    buf.setUint32(offset, t.tag, Endian.little);
    offset += 4;
  }

  for (final t in tags) {
    final bytes = buf.buffer.asUint8List();
    bytes.setRange(offset, offset + t.value.length, t.value);
    offset += t.value.length;
  }

  return buf.buffer.asUint8List();
}

/// Decodes a Roughtime wire-format message into tag-value pairs.
Map<int, Uint8List> decodeMessage(Uint8List data) {
  if (data.length < 4) {
    throw FormatException('Roughtime message too short: ${data.length} bytes');
  }

  final bd = ByteData.sublistView(data);
  final numTags = bd.getUint32(0, Endian.little);

  if (numTags == 0) return {};

  final minLen = 4 + (numTags - 1) * 4 + numTags * 4;
  if (data.length < minLen) {
    throw FormatException(
      'Roughtime message truncated: need $minLen, got ${data.length}',
    );
  }

  final offsets = <int>[0];
  for (var i = 0; i < numTags - 1; i++) {
    offsets.add(bd.getUint32(4 + i * 4, Endian.little));
  }
  final valuesStart = (4 + (numTags - 1) * 4 + numTags * 4);
  final totalValueLen = data.length - valuesStart;
  offsets.add(totalValueLen);

  final tags = <int>[];
  final tagsStart = 4 + (numTags - 1) * 4;
  for (var i = 0; i < numTags; i++) {
    tags.add(bd.getUint32(tagsStart + i * 4, Endian.little));
  }

  final result = <int, Uint8List>{};
  for (var i = 0; i < numTags; i++) {
    final start = valuesStart + offsets[i];
    final end = valuesStart + offsets[i + 1];
    result[tags[i]] = Uint8List.sublistView(data, start, end);
  }

  return result;
}

// ---------------------------------------------------------------------------
// Tag constants (as uint32 LE)
// ---------------------------------------------------------------------------

int _tagFromAscii(String s) {
  assert(s.length == 4);
  return s.codeUnitAt(0) |
      (s.codeUnitAt(1) << 8) |
      (s.codeUnitAt(2) << 16) |
      (s.codeUnitAt(3) << 24);
}

final int tagNonc = _tagFromAscii('NONC');
final int tagSrep = _tagFromAscii('SREP');
final int tagSig = _tagFromAscii('SIG\x00');
final int tagCert = _tagFromAscii('CERT');
final int tagDele = _tagFromAscii('DELE');
final int tagMaxt = _tagFromAscii('MAXT');
final int tagMint = _tagFromAscii('MINT');
final int tagRadi = _tagFromAscii('RADI');
final int tagMidp = _tagFromAscii('MIDP');
final int tagRoot = _tagFromAscii('ROOT');
final int tagIndx = _tagFromAscii('INDX');
final int tagPath = _tagFromAscii('PATH');
final int tagPubk = _tagFromAscii('PUBK');
final int tagVer = _tagFromAscii('VER\xff');

// Roughtime context strings for signature domain separation.
final Uint8List _certContext = Uint8List.fromList(
  'RoughTime v1 delegation signature--\x00'.codeUnits,
);
final Uint8List _srepContext = Uint8List.fromList(
  'RoughTime v1 response signature\x00'.codeUnits,
);

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------

/// A known Roughtime server.
class RoughtimeServer {
  const RoughtimeServer({
    required this.name,
    required this.address,
    required this.port,
    required this.publicKey,
  });

  final String name;
  final String address;
  final int port;
  final Uint8List publicKey;

  static final List<RoughtimeServer> defaultServers = [
    RoughtimeServer(
      name: 'Cloudflare',
      address: 'roughtime.cloudflare.com',
      port: 2002,
      publicKey: _hexDecode(
        '0d04e2122839b053723e2b1142518ab1b5e0515ee3e4358483d4e50cba74c5a0',
      ),
    ),
    RoughtimeServer(
      name: 'Google',
      address: 'roughtime.sandbox.google.com',
      port: 2002,
      publicKey: _hexDecode(
        '7ad3da688c5c04c635a14f28643db4f08123a16518d15b7a2845e7b8ee35ce10',
      ),
    ),
  ];
}

/// A verified Roughtime response.
class RoughtimeResponse {
  const RoughtimeResponse({
    required this.midpoint,
    required this.radius,
    required this.serverName,
    required this.rawResponse,
  });

  /// Server-attested midpoint (UTC).
  final DateTime midpoint;

  /// Uncertainty radius (the real time is within midpoint +/- radius).
  final Duration radius;

  /// Which server produced this response.
  final String serverName;

  /// Raw response bytes for embedding in a .zgl file.
  final Uint8List rawResponse;

  Map<String, dynamic> toJson() => {
        'server': serverName,
        'midpoint_us': midpoint.toUtc().microsecondsSinceEpoch,
        'radius_us': radius.inMicroseconds,
      };
}

/// Result of a chained multi-server Roughtime query.
class RoughtimeChain {
  const RoughtimeChain({required this.responses});

  final List<RoughtimeResponse> responses;

  /// Tightest time bound across all responses.
  DateTime get notBefore {
    DateTime latest = DateTime.utc(1970);
    for (final r in responses) {
      final lb = r.midpoint.subtract(r.radius);
      if (lb.isAfter(latest)) latest = lb;
    }
    return latest;
  }

  DateTime get notAfter {
    DateTime earliest = DateTime.utc(9999);
    for (final r in responses) {
      final ub = r.midpoint.add(r.radius);
      if (ub.isBefore(earliest)) earliest = ub;
    }
    return earliest;
  }

  /// Serializes for embedding in a TIMESTAMP block.
  Map<String, dynamic> toJson() => {
        'protocol': 'roughtime',
        'responses': responses.map((r) => r.toJson()).toList(),
        'not_before_us': notBefore.toUtc().microsecondsSinceEpoch,
        'not_after_us': notAfter.toUtc().microsecondsSinceEpoch,
      };
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// Queries Roughtime servers over UDP and returns verified time.
class RoughtimeClient {
  RoughtimeClient({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;

  /// Queries a single server with the given nonce.
  ///
  /// The [nonce] must be 64 bytes. Returns a verified response.
  /// Throws on network error, timeout, or signature verification failure.
  Future<RoughtimeResponse> querySingle(
    RoughtimeServer server,
    Uint8List nonce,
  ) async {
    if (nonce.length != 64) {
      throw ArgumentError('Roughtime nonce must be 64 bytes');
    }

    final request = _buildRequest(nonce);

    final addresses = await InternetAddress.lookup(server.address);
    if (addresses.isEmpty) {
      throw SocketException('Cannot resolve ${server.address}');
    }

    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      socket.send(request, addresses.first, server.port);

      final completer = <Uint8List>[];
      await for (final event in socket.timeout(timeout)) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            completer.add(Uint8List.fromList(datagram.data));
            break;
          }
        }
      }

      if (completer.isEmpty) {
        throw SocketException(
          'Roughtime query to ${server.name} timed out after $timeout',
        );
      }

      final rawResponse = completer.first;
      return _verifyResponse(rawResponse, nonce, server);
    } finally {
      socket.close();
    }
  }

  /// Queries multiple servers in a chain.
  ///
  /// Each subsequent nonce is SHA-512 of the previous raw response,
  /// creating an auditable happens-before ordering.
  Future<RoughtimeChain> queryChain(
    List<RoughtimeServer> servers,
    Uint8List initialNonce,
  ) async {
    if (servers.isEmpty) {
      throw ArgumentError('At least one server required');
    }

    final responses = <RoughtimeResponse>[];
    var nonce = initialNonce;

    for (final server in servers) {
      final response = await querySingle(server, nonce);
      responses.add(response);
      nonce = Uint8List.fromList(sha512.convert(response.rawResponse).bytes);
    }

    return RoughtimeChain(responses: responses);
  }

  Uint8List _buildRequest(Uint8List nonce) {
    final tags = [
      RoughtimeTag(tagNonc, nonce),
    ];
    if (tagVer < tagNonc) {
      tags.insert(0, RoughtimeTag(tagVer, _packUint32LE(0x80000003)));
    } else {
      tags.add(RoughtimeTag(tagVer, _packUint32LE(0x80000003)));
    }
    tags.sort((a, b) => a.tag.compareTo(b.tag));
    return encodeMessage(tags);
  }

  RoughtimeResponse _verifyResponse(
    Uint8List rawResponse,
    Uint8List nonce,
    RoughtimeServer server,
  ) {
    final msg = decodeMessage(rawResponse);

    final sigBytes = msg[tagSig];
    final srepBytes = msg[tagSrep];
    final certBytes = msg[tagCert];

    if (sigBytes == null || sigBytes.length != 64) {
      throw FormatException('Missing or invalid SIG in Roughtime response');
    }
    if (srepBytes == null) {
      throw FormatException('Missing SREP in Roughtime response');
    }
    if (certBytes == null) {
      throw FormatException('Missing CERT in Roughtime response');
    }

    // Parse certificate: contains DELE and SIG.
    final cert = decodeMessage(certBytes);
    final certSig = cert[tagSig];
    final deleBytes = cert[tagDele];
    if (certSig == null || certSig.length != 64 || deleBytes == null) {
      throw FormatException('Malformed CERT in Roughtime response');
    }

    // Verify delegation: long-term key signs DELE.
    final certSignedMsg = Uint8List(_certContext.length + deleBytes.length);
    certSignedMsg.setRange(0, _certContext.length, _certContext);
    certSignedMsg.setRange(
        _certContext.length, certSignedMsg.length, deleBytes);

    if (!_ed25519Verify(server.publicKey, certSignedMsg, certSig)) {
      throw StateError(
        'Roughtime delegation signature verification failed for ${server.name}',
      );
    }

    // Extract delegated public key and validity window from DELE.
    final dele = decodeMessage(deleBytes);
    final delegatedPubKey = dele[tagPubk];
    if (delegatedPubKey == null || delegatedPubKey.length != 32) {
      throw FormatException('Missing PUBK in delegation');
    }

    // Verify SREP with delegated key.
    final srepSignedMsg = Uint8List(_srepContext.length + srepBytes.length);
    srepSignedMsg.setRange(0, _srepContext.length, _srepContext);
    srepSignedMsg.setRange(
      _srepContext.length,
      srepSignedMsg.length,
      srepBytes,
    );

    if (!_ed25519Verify(delegatedPubKey, srepSignedMsg, sigBytes)) {
      throw StateError(
        'Roughtime response signature verification failed for ${server.name}',
      );
    }

    // Parse SREP: contains MIDP, RADI, ROOT.
    final srep = decodeMessage(srepBytes);
    final midpBytes = srep[tagMidp];
    final radiBytes = srep[tagRadi];
    final rootBytes = srep[tagRoot];

    if (midpBytes == null || midpBytes.length != 8) {
      throw FormatException('Missing or invalid MIDP in SREP');
    }
    if (radiBytes == null || radiBytes.length != 4) {
      throw FormatException('Missing or invalid RADI in SREP');
    }
    if (rootBytes == null || rootBytes.length != 32) {
      throw FormatException('Missing or invalid ROOT in SREP');
    }

    final midpUs = ByteData.sublistView(midpBytes).getUint64(0, Endian.little);
    final radiUs = ByteData.sublistView(radiBytes).getUint32(0, Endian.little);

    // Verify nonce is in the Merkle tree rooted at ROOT.
    final nonceHash = Uint8List.fromList(sha512.convert(nonce).bytes);
    final indxBytes = msg[tagIndx];
    final pathBytes = msg[tagPath];

    if (indxBytes == null || indxBytes.length != 4) {
      throw FormatException('Missing INDX in Roughtime response');
    }

    final index = ByteData.sublistView(indxBytes).getUint32(0, Endian.little);
    _verifyMerkleTree(nonceHash, index, pathBytes ?? Uint8List(0), rootBytes);

    // Check delegation validity window.
    final mintBytes = dele[tagMint];
    final maxtBytes = dele[tagMaxt];
    if (mintBytes != null && mintBytes.length == 8) {
      final mint = ByteData.sublistView(mintBytes).getUint64(0, Endian.little);
      if (midpUs < mint) {
        throw StateError('Roughtime midpoint before delegation MINT');
      }
    }
    if (maxtBytes != null && maxtBytes.length == 8) {
      final maxt = ByteData.sublistView(maxtBytes).getUint64(0, Endian.little);
      if (midpUs > maxt) {
        throw StateError('Roughtime midpoint after delegation MAXT');
      }
    }

    return RoughtimeResponse(
      midpoint: DateTime.fromMicrosecondsSinceEpoch(midpUs, isUtc: true),
      radius: Duration(microseconds: radiUs),
      serverName: server.name,
      rawResponse: rawResponse,
    );
  }

  void _verifyMerkleTree(
    Uint8List nonceHash,
    int index,
    Uint8List path,
    Uint8List expectedRoot,
  ) {
    if (path.length % 64 != 0) {
      throw FormatException('Roughtime PATH length must be multiple of 64');
    }

    var current = nonceHash;
    final levels = path.length ~/ 64;

    for (var i = 0; i < levels; i++) {
      final sibling = Uint8List.sublistView(path, i * 64, (i + 1) * 64);
      if (index & 1 == 0) {
        current =
            Uint8List.fromList(sha512.convert([...current, ...sibling]).bytes);
      } else {
        current =
            Uint8List.fromList(sha512.convert([...sibling, ...current]).bytes);
      }
      index >>= 1;
    }

    // ROOT is first 32 bytes of the SHA-512 tree hash.
    final rootCandidate = Uint8List.sublistView(current, 0, 32);
    for (var i = 0; i < 32; i++) {
      if (rootCandidate[i] != expectedRoot[i]) {
        throw StateError('Roughtime Merkle tree verification failed');
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

bool _ed25519Verify(Uint8List publicKey, Uint8List message, Uint8List sig) {
  try {
    final vk = pinenacl.VerifyKey(publicKey);
    final signedMessage = Uint8List(sig.length + message.length);
    signedMessage.setRange(0, sig.length, sig);
    signedMessage.setRange(sig.length, signedMessage.length, message);
    vk.verifySignedMessage(
        signedMessage:
            pinenacl.SignedMessage.fromList(signedMessage: signedMessage));
    return true;
  } on Exception {
    return false;
  }
}

Uint8List _packUint32LE(int value) {
  final bd = ByteData(4);
  bd.setUint32(0, value, Endian.little);
  return bd.buffer.asUint8List();
}

Uint8List _hexDecode(String hex) {
  final result = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < result.length; i++) {
    result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return result;
}
