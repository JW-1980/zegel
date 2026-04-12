/// Zegel: A tamper-proof container format library.
///
/// Zegel ("seal" in Dutch) wraps any file in a cryptographic container that
/// makes the content physically unreadable if even a single byte is modified
/// after creation. This is not a "check and warn" system -- the cryptographic
/// math itself prevents decoding of tampered content.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:zegel/zegel.dart';
///
/// // Create a sealed container
/// final writer = ZegelWriter(masterKey, ZegelOptions(contentType: 'text/plain'));
/// final sealed = writer.seal(utf8.encode('Hello, Zegel!'));
///
/// // Verify and extract
/// final reader = ZegelReader();
/// final result = reader.verify(sealed, masterKey);
/// assert(result.valid);
/// ```
library zegel;

export 'src/format.dart';
export 'src/merkle_tree.dart';
export 'src/key_derivation.dart';
export 'src/writer.dart';
export 'src/reader.dart';
export 'src/canary.dart';
export 'src/shamir.dart';
export 'src/redaction.dart';
export 'src/attestation.dart';
export 'src/disclosure.dart';
export 'src/audit.dart';
export 'src/versioning.dart';
export 'src/batch.dart';
export 'src/manifest.dart';
export 'src/classification.dart';
export 'src/excerpt.dart';
export 'src/media_metadata.dart';
export 'src/timestamp.dart';
export 'src/provenance_verification.dart';
export 'src/hierarchical_split_key.dart';
export 'src/streaming.dart';
export 'src/burn_after_read.dart';
export 'src/time_lock.dart';
export 'src/identity.dart';
export 'src/supply_chain.dart';
export 'src/structured_blocks.dart';
export 'src/wet_signature.dart';
export 'src/envelope.dart';
export 'src/template.dart';
export 'src/certificate_of_completion.dart';
export 'src/bulk_send.dart';
