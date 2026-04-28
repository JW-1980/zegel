import re

with open('lib/lib/src/identity.dart', 'r') as f:
    content = f.read()

pqc_classes = """
/// A Post-Quantum (ML-DSA / Dilithium) signing keypair for Zegel identity.
///
/// Note: PQC implementations are currently stubbed in pure Dart
/// pending stable ecosystem support.
class ZegelPqcKeyPair {
  /// Creates a [ZegelPqcKeyPair].
  const ZegelPqcKeyPair({required this.privateKey, required this.publicKey, this.algorithm = 'ML-DSA-65'});

  /// The Post-Quantum private key.
  final Uint8List privateKey;

  /// The Post-Quantum public key.
  final Uint8List publicKey;

  /// The Post-Quantum algorithm used.
  final String algorithm;
}

/// A Post-Quantum signature over a .zgl file's integrity markers.
class ZegelPqcSignature {
  /// Creates a [ZegelPqcSignature].
  const ZegelPqcSignature({
    required this.signature,
    required this.timestamp,
    required this.merkleRootHex,
    this.algorithm = 'ML-DSA-65',
  });

  /// The Post-Quantum signature.
  final Uint8List signature;

  /// Unix epoch seconds when the signature was created.
  final int timestamp;

  /// Hex-encoded Merkle root that was signed.
  final String merkleRootHex;

  /// The Post-Quantum algorithm used.
  final String algorithm;
}
"""

pqc_attestation_methods = """
  /// Creates a signed attestation block from device information using Post-Quantum Cryptography.
  ///
  /// Note: This is currently a stub for ML-DSA-65 / Dilithium until a pure-dart
  /// PQC library is stable enough for use in Zegel. It currently just generates a mock signature placeholder.
  ///
  /// [deviceInfo] is the captured device information.
  /// [keyPair] is a [ZegelPqcKeyPair].
  ///
  /// Returns a JSON-serialisable map suitable for inclusion as a
  /// DEVICE_ATTESTATION block.
  static Map<String, dynamic> createPqcAttestation(
    DeviceInfo deviceInfo,
    ZegelPqcKeyPair keyPair,
  ) {
    final Map<String, dynamic> infoMap = deviceInfo.toJson();
    final String infoJson = jsonEncode(infoMap);
    final Uint8List infoBytes = Uint8List.fromList(utf8.encode(infoJson));

    // Sign the device info JSON with Post-Quantum algorithm (stubbed to mock)
    final Uint8List digest = Uint8List.fromList(
      sha256.convert(infoBytes).bytes,
    );

    // MOCK PQC implementation
    final Uint8List signature = digest;

    return <String, dynamic>{
      'device_info': infoMap,
      'signature_hex': _bytesToHex(Uint8List.fromList(signature)),
      'public_key_hex': _bytesToHex(Uint8List.fromList(keyPair.publicKey)),
      'algorithm': keyPair.algorithm,
    };
  }

  /// Verifies a device attestation signature using Post-Quantum Cryptography.
  ///
  /// Note: This is a stub for ML-DSA-65.
  ///
  /// [attestation] is the attestation map (as produced by [createPqcAttestation]).
  /// [publicKey] is the Post-Quantum public key. If null, the public key
  /// embedded in the attestation is used.
  ///
  /// Returns `true` if the signature is valid.
  static bool verifyPqcAttestation(
    Map<String, dynamic> attestation, {
    Uint8List? publicKey,
  }) {
    final String algorithm = attestation['algorithm'] as String? ?? 'ML-DSA-65';
    if (!algorithm.startsWith('ML-DSA') &&
        !algorithm.startsWith('Dilithium') &&
        !algorithm.startsWith('Falcon')) {
      return false; // Not a supported PQC algorithm
    }

    final Map<String, dynamic> infoMap =
        attestation['device_info'] as Map<String, dynamic>;
    final String infoJson = jsonEncode(infoMap);
    final Uint8List infoBytes = Uint8List.fromList(utf8.encode(infoJson));
    final Uint8List digest = Uint8List.fromList(
      sha256.convert(infoBytes).bytes,
    );

    final Uint8List signatureBytes = _hexToBytes(
      attestation['signature_hex'] as String,
    );

    // MOCK PQC verification
    if (signatureBytes.length != digest.length) return false;
    for (int i = 0; i < digest.length; i++) {
        if (signatureBytes[i] != digest[i]) return false;
    }

    return true;
  }
"""

if "class ZegelPqcKeyPair" not in content:
    content += "\n" + pqc_classes

if "createPqcAttestation" not in content:
    match = re.search(r'class DeviceAttestation \{([\s\S]*?)\n\}\n\n/// Captured device and platform information\.', content)
    if match:
        class_body = match.group(1)
        new_class_body = class_body + "\n" + pqc_attestation_methods
        content = content.replace(match.group(0), f"class DeviceAttestation {{{new_class_body}\n}}\n\n/// Captured device and platform information.")

with open('lib/lib/src/identity.dart', 'w') as f:
    f.write(content)
