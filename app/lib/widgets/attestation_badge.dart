import 'package:flutter/material.dart';

import '../services/zegel_service.dart';
import 'package:intl/intl.dart';

/// Displays an attestation (co-signature) as a badge.
///
/// Shows signer_id, statement, and timestamp. A green check indicates
/// that the HMAC was verified; a red X means verification failed.
/// The badge is expandable to show full details.
class AttestationBadge extends StatelessWidget {
  /// The attestation to display.
  final ZegelAttestation attestation;

  const AttestationBadge({super.key, required this.attestation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormatter = DateFormat('yyyy-MM-dd HH:mm');
    final isVerified = attestation.isVerified;
    final badgeColor = isVerified
        ? const Color(0xFF2E7D32)
        : const Color(0xFFC62828);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: badgeColor.withValues(alpha: 0.3), width: 1),
      ),
      child: ExpansionTile(
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: badgeColor.withValues(alpha: 0.1),
          child: Icon(
            isVerified ? Icons.check_circle : Icons.cancel,
            color: badgeColor,
            size: 20,
          ),
        ),
        title: Text(
          attestation.signerId,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          attestation.statement,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Icon(
              isVerified ? Icons.verified_user : Icons.gpp_bad,
              color: badgeColor,
              size: 18,
            ),
            Text(
              dateFormatter.format(attestation.timestamp),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                _DetailRow(
                  label: 'Signer ID',
                  // ignore: deprecated_member_use
                  // ignore: deprecated_member_use
                  value: attestation.signerId,
                ),
                _DetailRow(
                  label: 'Statement',
                  // ignore: deprecated_member_use
                  // ignore: deprecated_member_use
                  value: attestation.statement,
                ),
                _DetailRow(
                  label: 'Timestamp',
                  // ignore: deprecated_member_use
                  // ignore: deprecated_member_use
                  value: dateFormatter.format(attestation.timestamp),
                ),
                _DetailRow(
                  label: 'HMAC',
                  value: attestation.hmacHex.length > 32
                      ? '${attestation.hmacHex.substring(0, 32)}...'
                      : attestation.hmacHex,
                  mono: true,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      isVerified ? Icons.check_circle : Icons.cancel,
                      color: badgeColor,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isVerified
                          ? 'HMAC signature verified'
                          : 'HMAC signature verification failed',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: mono ? 'monospace' : null,
                fontSize: mono ? 11 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of attestation badges, for use on the verify screen.
class AttestationBadgeList extends StatelessWidget {
  final List<ZegelAttestation> attestations;

  const AttestationBadgeList({super.key, required this.attestations});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (attestations.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.approval, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'Attestations',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '(${attestations.length})',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...attestations.map(
          (a) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AttestationBadge(attestation: a),
          ),
        ),
      ],
    );
  }
}
