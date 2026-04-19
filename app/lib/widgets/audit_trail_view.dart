import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';

import '../services/zegel_service.dart';

/// A vertical timeline widget displaying the audit trail entries.
///
/// Each entry shows: actor, action, timestamp, details, and chain hash
/// verification status. The timeline is scrollable for long trails.
class AuditTrailView extends StatelessWidget {
  /// The list of audit trail entries to display.
  final List<ZegelAuditEntry> entries;

  const AuditTrailView({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (entries.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No audit trail entries',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.auditTrailTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${entries.length} entries',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const Divider(),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                return _AuditEntryTile(
                  entry: entries[index],
                  isFirst: index == 0,
                  isLast: index == entries.length - 1,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditEntryTile extends StatelessWidget {
  final ZegelAuditEntry entry;
  final bool isFirst;
  final bool isLast;

  const _AuditEntryTile({
    required this.entry,
    required this.isFirst,
    required this.isLast,
  });

  IconData _actionIcon() {
    switch (entry.action) {
      case 'sealed':
        return Icons.lock;
      case 'verified':
        return Icons.verified;
      case 'redacted':
        return Icons.content_cut;
      case 'attested':
        return Icons.approval;
      case 'disclosed':
        return Icons.visibility;
      default:
        return Icons.article;
    }
  }

  Color _actionColor(ColorScheme colorScheme) {
    switch (entry.action) {
      case 'sealed':
        return colorScheme.primary;
      case 'verified':
        return const Color(0xFF2E7D32);
      case 'redacted':
        return const Color(0xFFE65100);
      case 'attested':
        return const Color(0xFF1565C0);
      case 'disclosed':
        return const Color(0xFF6A1B9A);
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateFormatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    final color = _actionColor(colorScheme);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line and dot
          SizedBox(
            width: 40,
            child: Column(
              children: [
                if (!isFirst)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(
                      color: color.withValues(alpha: 0.3),
                      width: 3,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: colorScheme.outline.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
          // Entry content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_actionIcon(), size: 16, color: color),
                      const SizedBox(width: 4),
                      Text(
                        entry.action.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      // Chain hash verification indicator
                      Icon(
                        entry.isChainValid ? Icons.link : Icons.link_off,
                        size: 14,
                        color: entry.isChainValid
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFC62828),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        entry.isChainValid ? 'Chain valid' : 'Chain broken',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: entry.isChainValid
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFC62828),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.actor,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    dateFormatter.format(entry.timestamp),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (entry.details != null && entry.details!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    ...entry.details!.entries.map((e) {
                      return Text(
                        '${e.key}: ${e.value}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    'Chain: ${entry.chainHash.substring(0, 16)}...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
