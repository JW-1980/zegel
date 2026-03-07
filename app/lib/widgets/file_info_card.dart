import 'package:flutter/material.dart';

import '../services/zegel_service.dart';
import 'classification_badge.dart';
import 'package:intl/intl.dart';

/// A card displaying detailed file metadata.
///
/// Shows filename, size, content type, creation timestamp,
/// flags, block count, and public metadata if present.
class FileInfoCard extends StatelessWidget {
  /// The original filename.
  final String? filename;

  /// File size in bytes.
  final int? fileSize;

  /// MIME content type.
  final String? contentType;

  /// When the file was created/sealed.
  final DateTime? createdAt;

  /// File format flags value.
  final int? flags;

  /// Number of blocks in the container.
  final int? blockCount;

  /// Public metadata JSON (if present).
  final Map<String, dynamic>? publicMetadata;

  /// Inspection data (optional, for more detail).
  final ZegelInspection? inspection;

  /// Classification level (e.g. PUBLIC, SECRET).
  final String? classificationLevel;

  /// Regulatory hold expiry date string.
  final String? regulatoryHoldUntil;

  /// Number of attestations present.
  final int? attestationCount;

  /// Roles of attestors.
  final List<String>? attestationRoles;

  /// Whether the version chain is valid.
  final bool? versionChainValid;

  const FileInfoCard({
    super.key,
    this.filename,
    this.fileSize,
    this.contentType,
    this.createdAt,
    this.flags,
    this.blockCount,
    this.publicMetadata,
    this.inspection,
    this.classificationLevel,
    this.regulatoryHoldUntil,
    this.attestationCount,
    this.attestationRoles,
    this.versionChainValid,
  });

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  List<String> _decodedFlags(int flagValue) {
    final names = <String>[];
    if (flagValue & 0x0001 != 0) names.add('Encrypted Metadata');
    if (flagValue & 0x0002 != 0) names.add('Compressed');
    if (flagValue & 0x0004 != 0) names.add('Password Derived');
    if (flagValue & 0x0008 != 0) names.add('Key Commitment');
    if (flagValue & 0x0010 != 0) names.add('Expiration');
    if (flagValue & 0x0020 != 0) names.add('Public Metadata');
    if (flagValue & 0x0040 != 0) names.add('Multi-File');
    if (flagValue & 0x0080 != 0) names.add('Canary Trap');
    if (flagValue & 0x0100 != 0) names.add('Redactions');
    if (flagValue & 0x0200 != 0) names.add('Split Key');
    if (flagValue & 0x0400 != 0) names.add('Selective Disclosure');
    if (flagValue & 0x0800 != 0) names.add('Versioned');
    return names;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormatter = DateFormat('yyyy-MM-dd HH:mm:ss');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'File Information',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            if (filename != null)
              _InfoRow(label: 'Filename', // ignore: deprecated_member_use
 // ignore: deprecated_member_use
 value: filename!),
||||||| original
            if (filename != null)
              _InfoRow(label: 'Filename', value: filename!),
            if (filename != null) _InfoRow(label: 'Filename', value: filename!),
            if (fileSize != null)
              _InfoRow(label: 'Size', // ignore: deprecated_member_use
 // ignore: deprecated_member_use
 value: _formatFileSize(fileSize!)),
            if (contentType != null)
              _InfoRow(label: 'Content Type', // ignore: deprecated_member_use
 // ignore: deprecated_member_use
 value: contentType!),
            if (createdAt != null)
              _InfoRow(
                label: 'Created',
                // ignore: deprecated_member_use
                // ignore: deprecated_member_use
                value: dateFormatter.format(createdAt!),
              ),
            if (blockCount != null)
              _InfoRow(label: 'Block Count', // ignore: deprecated_member_use
 // ignore: deprecated_member_use
 value: blockCount.toString()),
            if (inspection != null) ...[
              _InfoRow(
                label: 'Format Version',
                value:
                    '${inspection!.versionMajor}.${inspection!.versionMinor}',
              ),
              if (inspection!.expiresAt != null)
                _InfoRow(
                  label: 'Expires',
                  // ignore: deprecated_member_use
                  // ignore: deprecated_member_use
                  value: dateFormatter.format(inspection!.expiresAt!),
                ),
              if (inspection!.isSplitKey)
                _InfoRow(
                  label: 'Split Key',
                  value:
                      '${inspection!.splitKeyThreshold}-of-${inspection!.splitKeyTotal}',
                ),
            ],
            // Classification level
            if (classificationLevel != null &&
                classificationLevel!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      'Classification',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  ClassificationBadge(
                    level: classificationLevel!,
                    compact: true,
                  ),
                ],
              ),
            ],

            // Regulatory hold
            if (regulatoryHoldUntil != null &&
                regulatoryHoldUntil!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      'Regulatory Hold',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border:
                          Border.all(color: Colors.amber.withValues(alpha: 0.5)),
||||||| original
                      border:
                          Border.all(color: Colors.amber.withOpacity(0.5)),
                      border: Border.all(color: Colors.amber.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.gavel,
                            size: 12, color: Colors.amber.shade800),
                        const SizedBox(width: 4),
                        Text(
                          'HELD UNTIL $regulatoryHoldUntil',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],

            // Attestation count and roles
            if (attestationCount != null && attestationCount! > 0) ...[
              const SizedBox(height: 4),
              _InfoRow(
                label: 'Attestations',
                // ignore: deprecated_member_use
                // ignore: deprecated_member_use
                value: '$attestationCount',
              ),
              if (attestationRoles != null && attestationRoles!.isNotEmpty)
                _InfoRow(
                  label: 'Roles',
                  // ignore: deprecated_member_use
                  // ignore: deprecated_member_use
                  value: attestationRoles!.join(', '),
                ),
            ],

            // Version chain info
            if (versionChainValid != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      'Version Chain',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    versionChainValid! ? Icons.link : Icons.link_off,
                    size: 14,
                    color: versionChainValid!
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFC62828),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    versionChainValid! ? 'Chain intact' : 'Chain broken',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: versionChainValid!
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFC62828),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],

            if (flags != null && flags! > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Features',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _decodedFlags(flags!).map((flag) {
                  return Chip(
                    label: Text(
                      flag,
                      style: const TextStyle(fontSize: 11),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  );
                }).toList(),
              ),
            ],
            if (publicMetadata != null && publicMetadata!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Public Metadata',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              ...publicMetadata!.entries.map(
                (entry) => _InfoRow(
                  label: entry.key,
                  // ignore: deprecated_member_use
                  // ignore: deprecated_member_use
                  value: entry.value.toString(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A single row in the file info card showing a label-value pair.
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
