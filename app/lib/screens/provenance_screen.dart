import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/zegel_service.dart';
import '../widgets/key_input.dart';
import 'package:intl/intl.dart';

/// Provenance viewer screen.
///
/// Displays a timeline of all provenance events recorded in a .zgl file,
/// showing the chain of custody with actor, action, timestamp, and
/// signature verification status.
class ProvenanceScreen extends StatefulWidget {
  const ProvenanceScreen({super.key});

  @override
  State<ProvenanceScreen> createState() => _ProvenanceScreenState();
}

class _ProvenanceScreenState extends State<ProvenanceScreen> {
  String? _filePath;
  String _hexKey = '';
  bool _isLoading = false;
  List<ProvenanceEvent>? _events;
  String? _statusMessage;
  bool _isError = false;

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickZegelFile();
    if (path != null) {
      setState(() {
        _filePath = path;
        _events = null;
        _statusMessage = null;
      });
    }
  }

  Future<void> _loadProvenance() async {
    if (_filePath == null || _hexKey.length != 64) {
      setState(() {
        _statusMessage = 'Please select a file and enter the master key.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _events = null;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final events = await zegelService.verifyProvenance(_filePath!, _hexKey);
      if (mounted) {
        setState(() {
          _events = events;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error: $e';
          _isError = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _exportReport() async {
    if (_events == null || _events!.isEmpty) return;

    try {
      final fileService = context.read<FileService>();
      final reportBuffer = StringBuffer();
      reportBuffer.writeln('Provenance Report');
      reportBuffer.writeln('=================');
      reportBuffer.writeln('File: ${fileService.getFileName(_filePath!)}');
      reportBuffer.writeln(
          'Generated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
      reportBuffer.writeln('');

      for (final event in _events!) {
        reportBuffer.writeln('--- Event ---');
        reportBuffer.writeln('Actor: ${event.actor}');
        reportBuffer.writeln('Action: ${event.action}');
        reportBuffer.writeln(
            'Timestamp: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(event.timestamp)}');
        reportBuffer.writeln(
            'Signature: ${event.isSignatureVerified ? "VERIFIED" : "UNVERIFIED"}');
        reportBuffer.writeln('');
      }

      final bytes =
          List<int>.from(reportBuffer.toString().codeUnits);
      final savedPath = await fileService.saveFile(
        Uint8List.fromList(bytes),
        'provenance_report.txt',
      );

      if (savedPath != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Provenance report exported.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.provenanceTitle),
        actions: [
          if (_events != null && _events!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: l10n.provenanceExportReport,
              onPressed: _exportReport,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // File picker
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.history, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          l10n.provenanceFileLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_filePath != null)
                      Text(
                        context.read<FileService>().getFileName(_filePath!),
                        style: theme.textTheme.bodyMedium,
                      )
                    else
                      Text(
                        l10n.noFileSelected,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: Text(l10n.selectFileAction),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Key input
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: KeyInput(
                  onKeyChanged: (key) => setState(() => _hexKey = key),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Load button
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _loadProvenance,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.timeline),
                label: Text(
                  _isLoading
                      ? l10n.provenanceLoading
                      : l10n.provenanceLoadAction,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Status message
            if (_statusMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _isError
                      ? Colors.red.withValues(alpha: 0.1)
                      : Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isError
                        ? Colors.red.withValues(alpha: 0.3)
                        : Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isError ? Icons.error : Icons.check_circle,
                      color: _isError ? Colors.red : Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_statusMessage!)),
                  ],
                ),
              ),

            // Timeline view
            if (_events != null && _events!.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.timeline,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            l10n.provenanceTimeline,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_events!.length} events',
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
                        itemCount: _events!.length,
                        itemBuilder: (context, index) {
                          return _ProvenanceEventTile(
                            event: _events![index],
                            isFirst: index == 0,
                            isLast: index == _events!.length - 1,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              )
            else if (_events != null && _events!.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      l10n.provenanceNoEvents,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single provenance event tile in the timeline.
class _ProvenanceEventTile extends StatelessWidget {
  final ProvenanceEvent event;
  final bool isFirst;
  final bool isLast;

  const _ProvenanceEventTile({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  Color _actionColor(ColorScheme colorScheme) {
    switch (event.action) {
      case 'created':
        return colorScheme.primary;
      case 'signed':
        return const Color(0xFF1565C0);
      case 'transferred':
        return const Color(0xFF6A1B9A);
      case 'verified':
        return const Color(0xFF2E7D32);
      case 'modified':
        return const Color(0xFFE65100);
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  IconData _actionIcon() {
    switch (event.action) {
      case 'created':
        return Icons.create;
      case 'signed':
        return Icons.draw;
      case 'transferred':
        return Icons.swap_horiz;
      case 'verified':
        return Icons.verified;
      case 'modified':
        return Icons.edit;
      default:
        return Icons.article;
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
          // Event content
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
                        event.action.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        event.isSignatureVerified
                            ? Icons.verified_user
                            : Icons.gpp_bad,
                        size: 16,
                        color: event.isSignatureVerified
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFC62828),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        event.isSignatureVerified ? 'Verified' : 'Unverified',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: event.isSignatureVerified
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFFC62828),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.actor,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    dateFormatter.format(event.timestamp),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
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
