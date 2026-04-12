import 'dart:convert';
import 'dart:typed_data';

/// Structured block types for specific use cases (v1.2+).
///
/// Each structured block type provides domain-specific serialisation for
/// common use cases. All blocks are serialised as JSON and encrypted as
/// regular Zegel blocks, benefiting from the same tamper-evidence and
/// integrity guarantees.
///
/// Block types and their constants:
/// - [SbomBlock] (0x10): Software Bill of Materials
/// - [RoyaltyBlock] (0x11): Payment split ratios
/// - [MeasurementBlock] (0x12): Sensor/measurement data
/// - [PrivilegeLogBlock] (0x13): Legal basis for redactions

// =============================================================================
// SbomBlock - Software Bill of Materials
// =============================================================================

/// A Software Bill of Materials (SBOM) entry describing a software package.
class SbomPackage {

  /// Deserialises from a JSON-compatible map.
  factory SbomPackage.fromJson(Map<String, dynamic> json) {
    return SbomPackage(
      name: json['name'] as String,
      version: json['version'] as String,
      hashAlgorithm: json['hash_algorithm'] as String?,
      hashValue: json['hash_value'] as String?,
      license: json['license'] as String?,
      supplier: json['supplier'] as String?,
      purl: json['purl'] as String?,
    );
  }
  /// Creates an [SbomPackage].
  const SbomPackage({
    required this.name,
    required this.version,
    this.hashAlgorithm,
    this.hashValue,
    this.license,
    this.supplier,
    this.purl,
  });

  /// Package name (e.g. "crypto").
  final String name;

  /// Package version string (e.g. "3.0.3").
  final String version;

  /// Hash algorithm used for integrity (e.g. "SHA-256").
  final String? hashAlgorithm;

  /// Hex-encoded hash value of the package archive.
  final String? hashValue;

  /// SPDX license identifier (e.g. "MIT", "Apache-2.0").
  final String? license;

  /// Supplier or publisher name.
  final String? supplier;

  /// Package URL (purl) for universal identification.
  final String? purl;

  /// Serialises to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = <String, dynamic>{
      'name': name,
      'version': version,
    };
    if (hashAlgorithm != null) result['hash_algorithm'] = hashAlgorithm;
    if (hashValue != null) result['hash_value'] = hashValue;
    if (license != null) result['license'] = license;
    if (supplier != null) result['supplier'] = supplier;
    if (purl != null) result['purl'] = purl;
    return result;
  }
}

/// Software Bill of Materials block (type 0x10).
///
/// Contains a list of software packages with their versions, hashes, and
/// license information. Useful for supply chain transparency and compliance
/// (e.g. Executive Order 14028 on software supply chain security).
class SbomBlock {

  /// Deserialises from a JSON-compatible map.
  factory SbomBlock.fromJson(Map<String, dynamic> json) {
    final List<dynamic> packagesJson = json['packages'] as List<dynamic>;
    return SbomBlock(
      packages: packagesJson
          .map((p) => SbomPackage.fromJson(p as Map<String, dynamic>))
          .toList(),
      sbomFormat: json['sbom_format'] as String?,
      createdAt: json['created_at'] as int?,
      toolName: json['tool_name'] as String?,
      toolVersion: json['tool_version'] as String?,
    );
  }
  /// Creates an [SbomBlock].
  const SbomBlock({
    required this.packages,
    this.sbomFormat,
    this.createdAt,
    this.toolName,
    this.toolVersion,
  });

  /// List of software packages in the bill of materials.
  final List<SbomPackage> packages;

  /// SBOM format standard (e.g. "CycloneDX", "SPDX").
  final String? sbomFormat;

  /// Unix epoch seconds when the SBOM was generated.
  final int? createdAt;

  /// Name of the tool that generated the SBOM.
  final String? toolName;

  /// Version of the tool that generated the SBOM.
  final String? toolVersion;

  /// Encodes the SBOM block to bytes (UTF-8 JSON).
  Uint8List encode() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  }

  /// Decodes an SBOM block from bytes.
  static SbomBlock decode(Uint8List data) {
    final Map<String, dynamic> json =
        jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    return SbomBlock.fromJson(json);
  }

  /// Serialises to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = <String, dynamic>{
      'block_type': 'sbom',
      'packages': packages.map((p) => p.toJson()).toList(),
    };
    if (sbomFormat != null) result['sbom_format'] = sbomFormat;
    if (createdAt != null) result['created_at'] = createdAt;
    if (toolName != null) result['tool_name'] = toolName;
    if (toolVersion != null) result['tool_version'] = toolVersion;
    return result;
  }
}

// =============================================================================
// RoyaltyBlock - Payment Split Ratios
// =============================================================================

/// A single payment split recipient.
class RoyaltyRecipient {

  /// Deserialises from a JSON-compatible map.
  factory RoyaltyRecipient.fromJson(Map<String, dynamic> json) {
    return RoyaltyRecipient(
      identifier: json['identifier'] as String,
      percentage: (json['percentage'] as num).toDouble(),
      name: json['name'] as String?,
      paymentAddress: json['payment_address'] as String?,
      role: json['role'] as String?,
    );
  }
  /// Creates a [RoyaltyRecipient].
  const RoyaltyRecipient({
    required this.identifier,
    required this.percentage,
    this.name,
    this.paymentAddress,
    this.role,
  });

  /// Unique identifier for the recipient (e.g. wallet address, account ID).
  final String identifier;

  /// Percentage of the total payment (0.0 to 100.0). All recipients'
  /// percentages must sum to exactly 100.0.
  final double percentage;

  /// Human-readable name of the recipient.
  final String? name;

  /// Payment address or routing information.
  final String? paymentAddress;

  /// Role description (e.g. "creator", "producer", "distributor").
  final String? role;

  /// Serialises to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = <String, dynamic>{
      'identifier': identifier,
      'percentage': percentage,
    };
    if (name != null) result['name'] = name;
    if (paymentAddress != null) result['payment_address'] = paymentAddress;
    if (role != null) result['role'] = role;
    return result;
  }
}

/// Royalty / payment split block (type 0x11).
///
/// Defines how payments should be distributed among recipients. The
/// percentages are tamper-evident: any modification to the split ratios
/// will be detected by the Merkle tree.
class RoyaltyBlock {

  /// Deserialises from a JSON-compatible map.
  factory RoyaltyBlock.fromJson(Map<String, dynamic> json) {
    final List<dynamic> recipientsJson = json['recipients'] as List<dynamic>;
    return RoyaltyBlock(
      recipients: recipientsJson
          .map((r) => RoyaltyRecipient.fromJson(r as Map<String, dynamic>))
          .toList(),
      currency: json['currency'] as String?,
      effectiveDate: json['effective_date'] as int?,
      expirationDate: json['expiration_date'] as int?,
      contractReference: json['contract_reference'] as String?,
    );
  }
  /// Creates a [RoyaltyBlock].
  ///
  /// Throws [ArgumentError] if percentages do not sum to 100.0 (within
  /// floating-point tolerance of 0.01).
  RoyaltyBlock({
    required this.recipients,
    this.currency,
    this.effectiveDate,
    this.expirationDate,
    this.contractReference,
  }) {
    final double total = recipients.fold(0.0, (sum, r) => sum + r.percentage);
    if ((total - 100.0).abs() > 0.01) {
      throw ArgumentError(
        'Recipient percentages must sum to 100.0 (got $total)',
      );
    }
  }

  /// List of payment recipients with their split percentages.
  final List<RoyaltyRecipient> recipients;

  /// Currency code (e.g. "USD", "EUR", "BTC").
  final String? currency;

  /// Effective date as Unix epoch seconds.
  final int? effectiveDate;

  /// Expiration date as Unix epoch seconds.
  final int? expirationDate;

  /// Reference to the governing contract or agreement.
  final String? contractReference;

  /// Encodes the royalty block to bytes (UTF-8 JSON).
  Uint8List encode() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  }

  /// Decodes a royalty block from bytes.
  static RoyaltyBlock decode(Uint8List data) {
    final Map<String, dynamic> json =
        jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    return RoyaltyBlock.fromJson(json);
  }

  /// Serialises to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = <String, dynamic>{
      'block_type': 'royalty',
      'recipients': recipients.map((r) => r.toJson()).toList(),
    };
    if (currency != null) result['currency'] = currency;
    if (effectiveDate != null) result['effective_date'] = effectiveDate;
    if (expirationDate != null) result['expiration_date'] = expirationDate;
    if (contractReference != null) {
      result['contract_reference'] = contractReference;
    }
    return result;
  }
}

// =============================================================================
// MeasurementBlock - Sensor Data
// =============================================================================

/// Calibration metadata for a sensor measurement.
class CalibrationInfo {

  /// Deserialises from a JSON-compatible map.
  factory CalibrationInfo.fromJson(Map<String, dynamic> json) {
    return CalibrationInfo(
      calibratedAt: json['calibrated_at'] as int,
      calibrationAuthority: json['calibration_authority'] as String?,
      certificateReference: json['certificate_reference'] as String?,
      nextCalibrationDue: json['next_calibration_due'] as int?,
      accuracy: json['accuracy'] as String?,
      resolution: json['resolution'] as String?,
    );
  }
  /// Creates a [CalibrationInfo].
  const CalibrationInfo({
    required this.calibratedAt,
    this.calibrationAuthority,
    this.certificateReference,
    this.nextCalibrationDue,
    this.accuracy,
    this.resolution,
  });

  /// Unix epoch seconds when the sensor was last calibrated.
  final int calibratedAt;

  /// Authority that performed the calibration.
  final String? calibrationAuthority;

  /// Reference to the calibration certificate.
  final String? certificateReference;

  /// Unix epoch seconds when the next calibration is due.
  final int? nextCalibrationDue;

  /// Measurement accuracy (e.g. "+/- 0.1").
  final String? accuracy;

  /// Measurement resolution (e.g. "0.01").
  final String? resolution;

  /// Serialises to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = <String, dynamic>{
      'calibrated_at': calibratedAt,
    };
    if (calibrationAuthority != null) {
      result['calibration_authority'] = calibrationAuthority;
    }
    if (certificateReference != null) {
      result['certificate_reference'] = certificateReference;
    }
    if (nextCalibrationDue != null) {
      result['next_calibration_due'] = nextCalibrationDue;
    }
    if (accuracy != null) result['accuracy'] = accuracy;
    if (resolution != null) result['resolution'] = resolution;
    return result;
  }
}

/// Sensor measurement block (type 0x12).
///
/// Records a single measurement from a sensor or instrument, including
/// timestamp, sensor identification, value, unit, and optional calibration
/// metadata. Useful for IoT, scientific instruments, environmental
/// monitoring, and industrial quality control.
class MeasurementBlock {

  /// Deserialises from a JSON-compatible map.
  factory MeasurementBlock.fromJson(Map<String, dynamic> json) {
    return MeasurementBlock(
      timestamp: json['timestamp'] as int,
      sensorId: json['sensor_id'] as String,
      value: (json['value'] as num).toDouble(),
      unit: json['unit'] as String,
      measurementType: json['measurement_type'] as String?,
      location: json['location'] as String?,
      calibration: json['calibration'] != null
          ? CalibrationInfo.fromJson(
              json['calibration'] as Map<String, dynamic>,
            )
          : null,
      batchId: json['batch_id'] as String?,
      sequenceNumber: json['sequence_number'] as int?,
    );
  }
  /// Creates a [MeasurementBlock].
  const MeasurementBlock({
    required this.timestamp,
    required this.sensorId,
    required this.value,
    required this.unit,
    this.measurementType,
    this.location,
    this.calibration,
    this.batchId,
    this.sequenceNumber,
  });

  /// Unix epoch seconds (or milliseconds) when the measurement was taken.
  final int timestamp;

  /// Unique identifier of the sensor or instrument.
  final String sensorId;

  /// Measured value (numeric).
  final double value;

  /// Unit of measurement (e.g. "celsius", "ppm", "Pa", "lux").
  final String unit;

  /// Type of measurement (e.g. "temperature", "pressure", "humidity").
  final String? measurementType;

  /// Location of the sensor (free-text or structured, e.g. "lat:51.5,lon:-0.1").
  final String? location;

  /// Calibration metadata for the sensor.
  final CalibrationInfo? calibration;

  /// Batch or session identifier grouping related measurements.
  final String? batchId;

  /// Sequence number within the batch for ordering.
  final int? sequenceNumber;

  /// Encodes the measurement block to bytes (UTF-8 JSON).
  Uint8List encode() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  }

  /// Decodes a measurement block from bytes.
  static MeasurementBlock decode(Uint8List data) {
    final Map<String, dynamic> json =
        jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    return MeasurementBlock.fromJson(json);
  }

  /// Serialises to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = <String, dynamic>{
      'block_type': 'measurement',
      'timestamp': timestamp,
      'sensor_id': sensorId,
      'value': value,
      'unit': unit,
    };
    if (measurementType != null) result['measurement_type'] = measurementType;
    if (location != null) result['location'] = location;
    if (calibration != null) result['calibration'] = calibration!.toJson();
    if (batchId != null) result['batch_id'] = batchId;
    if (sequenceNumber != null) result['sequence_number'] = sequenceNumber;
    return result;
  }
}

// =============================================================================
// PrivilegeLogBlock - Legal Basis for Redactions
// =============================================================================

/// Legal basis record for a single redaction.
class RedactionBasis {

  /// Deserialises from a JSON-compatible map.
  factory RedactionBasis.fromJson(Map<String, dynamic> json) {
    return RedactionBasis(
      blockIndex: json['block_index'] as int,
      legalAuthority: json['legal_authority'] as String,
      reason: json['reason'] as String,
      date: json['date'] as int,
      authorisedBy: json['authorised_by'] as String?,
      expiresAt: json['expires_at'] as int?,
      caseReference: json['case_reference'] as String?,
    );
  }
  /// Creates a [RedactionBasis].
  const RedactionBasis({
    required this.blockIndex,
    required this.legalAuthority,
    required this.reason,
    required this.date,
    this.authorisedBy,
    this.expiresAt,
    this.caseReference,
  });

  /// Zero-based index of the redacted block.
  final int blockIndex;

  /// Legal authority for the redaction (e.g. "GDPR Art. 17", "FOIA Exemption 6",
  /// "Court Order 2024-CR-1234").
  final String legalAuthority;

  /// Human-readable reason for the redaction.
  final String reason;

  /// Unix epoch seconds when the redaction was authorised.
  final int date;

  /// Identity of the person who authorised the redaction.
  final String? authorisedBy;

  /// Unix epoch seconds when the redaction expires (content should be restored).
  final int? expiresAt;

  /// Reference to the legal case, regulation, or order.
  final String? caseReference;

  /// Serialises to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = <String, dynamic>{
      'block_index': blockIndex,
      'legal_authority': legalAuthority,
      'reason': reason,
      'date': date,
    };
    if (authorisedBy != null) result['authorised_by'] = authorisedBy;
    if (expiresAt != null) result['expires_at'] = expiresAt;
    if (caseReference != null) result['case_reference'] = caseReference;
    return result;
  }
}

/// Privilege log block (type 0x13).
///
/// Documents the legal basis for each redaction in a .zgl file. Required for
/// legal compliance in contexts like litigation (FRCP), FOIA responses, and
/// GDPR right-to-erasure requests. Each redacted block should have a
/// corresponding entry in the privilege log explaining the authority and
/// reason for redaction.
class PrivilegeLogBlock {

  /// Deserialises from a JSON-compatible map.
  factory PrivilegeLogBlock.fromJson(Map<String, dynamic> json) {
    final List<dynamic> entriesJson = json['entries'] as List<dynamic>;
    return PrivilegeLogBlock(
      entries: entriesJson
          .map((e) => RedactionBasis.fromJson(e as Map<String, dynamic>))
          .toList(),
      preparedBy: json['prepared_by'] as String?,
      preparedAt: json['prepared_at'] as int?,
      caseTitle: json['case_title'] as String?,
    );
  }
  /// Creates a [PrivilegeLogBlock].
  const PrivilegeLogBlock({
    required this.entries,
    this.preparedBy,
    this.preparedAt,
    this.caseTitle,
  });

  /// List of redaction basis entries, one per redacted block.
  final List<RedactionBasis> entries;

  /// Identity of the person who prepared the privilege log.
  final String? preparedBy;

  /// Unix epoch seconds when the log was prepared.
  final int? preparedAt;

  /// Title of the legal case or matter.
  final String? caseTitle;

  /// Encodes the privilege log block to bytes (UTF-8 JSON).
  Uint8List encode() {
    return Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
  }

  /// Decodes a privilege log block from bytes.
  static PrivilegeLogBlock decode(Uint8List data) {
    final Map<String, dynamic> json =
        jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
    return PrivilegeLogBlock.fromJson(json);
  }

  /// Serialises to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = <String, dynamic>{
      'block_type': 'privilege_log',
      'entries': entries.map((e) => e.toJson()).toList(),
    };
    if (preparedBy != null) result['prepared_by'] = preparedBy;
    if (preparedAt != null) result['prepared_at'] = preparedAt;
    if (caseTitle != null) result['case_title'] = caseTitle;
    return result;
  }
}
