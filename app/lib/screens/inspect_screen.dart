import 'dart:io';

import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:zegel/zegel.dart';

import '../services/file_service.dart';

/// Screen for inspecting .zgl files without requiring the master key.
///
/// Displays header information including version, flags, timestamp,
/// content-type, filename, block count, public metadata, split-key
/// parameters, and expiration date.
class InspectScreen extends StatefulWidget {
  /// Optional initial .zgl file path.
  final String? initialFilePath;

  const InspectScreen({super.key, this.initialFilePath});

  @override
  State<InspectScreen> createState() => _InspectScreenState();
}

class _InspectScreenState extends State<InspectScreen> {
  String? _filePath;
  bool _isInspecting = false;
  ZegelInspection? _inspection;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilePath != null) {
      _filePath = widget.initialFilePath;
    }
  }

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickZegelFile();
    if (path != null) {
      setState(() {
        _filePath = path;
        _inspection = null;
        _errorMessage = null;
      });
    }
  }

  Future<void> _inspect() async {
    if (_filePath == null) {
      setState(() => _errorMessage = 'Please select a .zgl file.');
      return;
    }

    setState(() {
      _isInspecting = true;
      _inspection = null;
      _errorMessage = null;
    });

    try {
      final file = File(_filePath!);
      if (!await file.exists()) {
        throw Exception('File does not exist');
      }

      final bytes = await file.readAsBytes();
      final reader = const ZegelReader();
      final inspection = reader.inspect(bytes);

      if (mounted) {
        setState(() {
          _inspection = inspection;
          _isInspecting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _errorMessage = l10n.errorGeneric(e.toString());
          _isInspecting = false;
        });
      }
    }
  }

  String _formatTimestamp(int epochSeconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(
      epochSeconds * 1000,
      isUtc: true,
    );
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')} UTC';
  }

  List<String> _getFlagNames(int flags) {
    final names = <String>[];
    if (flags & 0x0001 != 0) names.add('HAS_METADATA');
    if (flags & 0x0002 != 0) names.add('COMPRESSED');
    if (flags & 0x0004 != 0) names.add('PASSWORD_DERIVED');
    if (flags & 0x0008 != 0) names.add('HAS_KEY_COMMITMENT');
    if (flags & 0x0010 != 0) names.add('HAS_EXPIRATION');
    if (flags & 0x0020 != 0) names.add('HAS_PUBLIC_METADATA');
    if (flags & 0x0040 != 0) names.add('MULTI_FILE');
    if (flags & 0x0080 != 0) names.add('HAS_CANARY');
    if (flags & 0x0100 != 0) names.add('HAS_REDACTIONS');
    if (flags & 0x0200 != 0) names.add('SPLIT_KEY');
    if (flags & 0x0400 != 0) names.add('SELECTIVE_DISCLOSURE');
    if (flags & 0x0800 != 0) names.add('VERSIONED');
    return names;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fileService = context.read<FileService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inspectAction),
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
                        Icon(
                          Icons.search,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'File to Inspect',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_filePath != null)
                      Text(
                        l10n.fileSelected(fileService.getFileName(_filePath!)),
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
                      onPressed: _isInspecting ? null : _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Select .zgl File'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Inspect button
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isInspecting ? null : _inspect,
                icon: _isInspecting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.info_outline),
                label: Text(
                  _isInspecting ? 'Inspecting...' : l10n.inspectAction,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Error message
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                    ),
                  ],
                ),
              ),

            // Inspection result
            if (_inspection != null) ...[
              // Version info
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info, color: theme.colorScheme.primary),
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
                      _buildInfoRow('Version', _inspection!.version, theme),
                      _buildInfoRow(
                        'Created',
                        _formatTimestamp(_inspection!.timestamp),
                        theme,
                      ),
                      if (_inspection!.filename != null)
                        _buildInfoRow(
                          'Original Filename',
                          _inspection!.filename!,
                          theme,
                        ),
                      if (_inspection!.contentType != null)
                        _buildInfoRow(
                          'Content-Type',
                          _inspection!.contentType!,
                          theme,
                        ),
                      _buildInfoRow(
                        'Block Count',
                        _inspection!.blockCount.toString(),
                        theme,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Flags
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.flag, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Feature Flags',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      _buildInfoRow(
                        'Raw Flags',
                        '0x${_inspection!.flags.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                        theme,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _getFlagNames(_inspection!.flags)
                            .map((name) => Chip(
                                  label: Text(
                                    name,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  backgroundColor:
                                      theme.colorScheme.primaryContainer,
                                ))
                            .toList(),
                      ),
                      if (_getFlagNames(_inspection!.flags).isEmpty)
                        Text(
                          'No flags set',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Split-key parameters (if present)
              if (_inspection!.splitKeyParams != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.key, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Split-Key Parameters',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        _buildInfoRow(
                          'Threshold (M)',
                          _inspection!.splitKeyParams!['threshold'].toString(),
                          theme,
                        ),
                        _buildInfoRow(
                          'Total Shares (N)',
                          _inspection!.splitKeyParams!['total'].toString(),
                          theme,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Requires ${_inspection!.splitKeyParams!['threshold']} of '
                          '${_inspection!.splitKeyParams!['total']} shares to reconstruct',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Expiration (if present)
              if (_inspection!.expirationTimestamp != null) ...[
                Card(
                  color: _isExpired()
                      ? Colors.red.shade50
                      : Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              color: _isExpired()
                                  ? Colors.red
                                  : Colors.orange.shade800,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Expiration',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _isExpired()
                                    ? Colors.red.shade900
                                    : Colors.orange.shade900,
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        _buildInfoRow(
                          'Expires At',
                          _formatTimestamp(_inspection!.expirationTimestamp!),
                          theme,
                          valueColor: _isExpired()
                              ? Colors.red.shade900
                              : Colors.orange.shade900,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              _isExpired()
                                  ? Icons.warning
                                  : Icons.timer,
                              size: 16,
                              color: _isExpired()
                                  ? Colors.red
                                  : Colors.orange.shade800,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isExpired()
                                  ? 'FILE HAS EXPIRED - Content is cryptographically unreadable'
                                  : 'File will expire - content will become unreadable after this date',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _isExpired()
                                    ? Colors.red.shade800
                                    : Colors.orange.shade800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Public metadata (if present)
              if (_inspection!.publicMetadata != null &&
                  _inspection!.publicMetadata!.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.description,
                                color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Public Metadata',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        ..._inspection!.publicMetadata!.entries
                            .map((entry) => _buildInfoRow(
                                  entry.key,
                                  entry.value.toString(),
                                  theme,
                                )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ],
        ),
      ),
    );
  }

  bool _isExpired() {
    if (_inspection?.expirationTimestamp == null) return false;
    final nowEpoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    return nowEpoch >= _inspection!.expirationTimestamp!;
  }

  Widget _buildInfoRow(
    String label,
    String value,
    ThemeData theme, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
