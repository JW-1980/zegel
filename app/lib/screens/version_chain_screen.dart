import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:zegel/zegel.dart';

import '../services/file_service.dart';

/// Version information extracted from a .zgl file.
class _VersionEntry {
  final String filename;
  final String version;
  final int timestamp;
  final String? chainHash;
  final bool isChainValid;
  final Map<String, dynamic>? versionInfo;

  const _VersionEntry({
    required this.filename,
    required this.version,
    required this.timestamp,
    this.chainHash,
    this.isChainValid = false,
    this.versionInfo,
  });
}

/// Screen for viewing version history of a document.
///
/// Displays chain hashes linking versions, verifies chain integrity,
/// and shows version metadata.
class VersionChainScreen extends StatefulWidget {
  const VersionChainScreen({super.key});

  @override
  State<VersionChainScreen> createState() => _VersionChainScreenState();
}

class _VersionChainScreenState extends State<VersionChainScreen> {
  final List<String> _filePaths = [];
  final List<_VersionEntry> _versions = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool? _chainValid;

  Future<void> _pickFiles() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickZegelFile();
    if (path != null && !_filePaths.contains(path)) {
      setState(() {
        _filePaths.add(path);
        _versions.clear();
        _chainValid = null;
        _errorMessage = null;
      });
    }
  }

  void _removeFile(int index) {
    setState(() {
      _filePaths.removeAt(index);
      _versions.clear();
      _chainValid = null;
      _errorMessage = null;
    });
  }

  void _clearFiles() {
    setState(() {
      _filePaths.clear();
      _versions.clear();
      _chainValid = null;
      _errorMessage = null;
    });
  }

  Future<void> _loadVersionChain() async {
    if (_filePaths.isEmpty) {
      setState(() => _errorMessage = 'Please add at least one .zgl file.');
      return;
    }

    setState(() {
      _isLoading = true;
      _versions.clear();
      _chainValid = null;
      _errorMessage = null;
    });

    try {
      final fileService = context.read<FileService>();
      const reader = ZegelReader();
      final versions = <_VersionEntry>[];
      final fileBytesList = <Uint8List>[];

      // Load and inspect all files
      for (final filePath in _filePaths) {
        final file = File(filePath);
        if (!await file.exists()) {
          throw Exception('File does not exist: $filePath');
        }

        final bytes = await file.readAsBytes();
        fileBytesList.add(bytes);

        // ignore: unused_local_variable
        // ignore: unused_local_variable
        final inspection = reader.inspect(bytes);

        // Extract version chain hash if present
        String? chainHash;
        if (inspection.flags & ZegelFormat.flagVersioned != 0) {
          chainHash = _extractChainHashHex(bytes);
        }

        // Extract version info from public metadata
        Map<String, dynamic>? versionInfo;
        if (inspection.publicMetadata != null &&
            inspection.publicMetadata!.containsKey('version_info')) {
          versionInfo = inspection.publicMetadata!['version_info']
              as Map<String, dynamic>?;
        }

        versions.add(
          _VersionEntry(
            filename: fileService.getFileName(filePath),
            version: inspection.version,
            timestamp: inspection.timestamp,
            chainHash: chainHash,
            versionInfo: versionInfo,
          ),
        );
      }

      // Verify chain integrity if we have 2+ files
      bool chainValid = true;
      if (fileBytesList.length >= 2) {
        try {
          chainValid = ContentVersioning.verifyVersionChain(fileBytesList);
        } catch (e) {
          chainValid = false;
        }
      }

      // Update chain validity for each entry
      final updatedVersions = <_VersionEntry>[];
      for (int i = 0; i < versions.length; i++) {
        updatedVersions.add(
          _VersionEntry(
            filename: versions[i].filename,
            version: versions[i].version,
            timestamp: versions[i].timestamp,
            chainHash: versions[i].chainHash,
            isChainValid: i == 0 ? true : chainValid,
            versionInfo: versions[i].versionInfo,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _versions.clear();
          _versions.addAll(updatedVersions);
          _chainValid = chainValid;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        // ignore: unused_local_variable
        // ignore: unused_local_variable
        // ignore: unused_local_variable
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _errorMessage = l10n.errorGeneric(e.toString());
          _isLoading = false;
        });
      }
    }
  }

  String? _extractChainHashHex(Uint8List bytes) {
    try {
      final bd = ByteData.sublistView(bytes);

      // Skip to flags
      final flags = bd.getUint16(10, Endian.big);
      if (flags & ZegelFormat.flagVersioned == 0) return null;

      // Calculate offset to version chain hash
      final filenameLen = bd.getUint16(84, Endian.big);
      final blockCountOffset = 86 + filenameLen + ZegelFormat.saltSize;

      int cursor = blockCountOffset + 4;
      if (flags & ZegelFormat.flagPasswordDerived != 0) cursor += 8;
      if (flags & ZegelFormat.flagHasExpiration != 0) cursor += 8;
      if (flags & ZegelFormat.flagHasCanary != 0) cursor += 32;
      if (flags & ZegelFormat.flagSplitKey != 0) cursor += 2;

      // Now we're at the version chain hash
      final chainHash = bytes.sublist(cursor, cursor + 32);
      return chainHash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    } catch (e) {
      return null;
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

  String _truncateHash(String hash) {
    if (hash.length <= 20) return hash;
    return '${hash.substring(0, 8)}...${hash.substring(hash.length - 8)}';
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fileService = context.read<FileService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Version Chain'),
        actions: [
          if (_filePaths.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all),
              tooltip: 'Clear all files',
              onPressed: _clearFiles,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info card
            Card(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Add multiple versions of a document (oldest first) to verify the cryptographic chain linking them.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // File list
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.folder, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Version Files',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: _isLoading ? null : _pickFiles,
                          icon: const Icon(Icons.add),
                          label: const Text('Add File'),
                        ),
                      ],
                    ),
                    const Divider(),
                    if (_filePaths.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No files added. Add files in chronological order (oldest first).',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _filePaths.length,
                        // ignore: deprecated_member_use
                        onReorderItem: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) newIndex--;
                            final item = _filePaths.removeAt(oldIndex);
                            _filePaths.insert(newIndex, item);
                            _versions.clear();
                            _chainValid = null;
                          });
                        },
                        itemBuilder: (context, index) {
                          final path = _filePaths[index];
                          return ListTile(
                            key: ValueKey(path),
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                            title: Text(
                              fileService.getFileName(path),
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              index == 0
                                  ? 'First version'
                                  : 'Version ${index + 1}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () => _removeFile(index),
                                  tooltip: 'Remove',
                                ),
                                const Icon(Icons.drag_handle),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Verify button
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _loadVersionChain,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.link),
                label: Text(
                  _isLoading ? 'Verifying...' : 'Verify Version Chain',
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
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
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

            // Chain validity status
            if (_chainValid != null) ...[
              Card(
                color: _chainValid! ? Colors.green.shade50 : Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        _chainValid! ? Icons.check_circle : Icons.error,
                        color: _chainValid! ? Colors.green : Colors.red,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _chainValid!
                                  ? 'Version Chain VALID'
                                  : 'Version Chain BROKEN',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: _chainValid!
                                    ? Colors.green.shade900
                                    : Colors.red.shade900,
                              ),
                            ),
                            Text(
                              _chainValid!
                                  ? 'All version links verified successfully'
                                  : 'One or more version links could not be verified',
                              style: TextStyle(
                                color: _chainValid!
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Version timeline
            if (_versions.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.timeline,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Version Timeline',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      ..._buildVersionTimeline(theme),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildVersionTimeline(ThemeData theme) {
    final widgets = <Widget>[];

    for (int i = 0; i < _versions.length; i++) {
      final version = _versions[i];
      final isFirst = i == 0;
      final isLast = i == _versions.length - 1;

      widgets.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline line
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    if (!isFirst)
                      Container(
                        width: 2,
                        height: 20,
                        color: version.isChainValid ? Colors.green : Colors.red,
                      ),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isFirst
                            ? theme.colorScheme.primary
                            : (version.isChainValid
                                ? Colors.green
                                : Colors.red),
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.3,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Version details
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              version.filename,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isFirst)
                            Chip(
                              label: const Text('Original'),
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              labelStyle: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildSmallInfoRow(
                        'Format',
                        'v${version.version}',
                        theme,
                      ),
                      _buildSmallInfoRow(
                        'Created',
                        _formatTimestamp(version.timestamp),
                        theme,
                      ),
                      if (version.chainHash != null)
                        _buildSmallInfoRow(
                          'Chain Hash',
                          _truncateHash(version.chainHash!),
                          theme,
                        ),
                      if (version.versionInfo != null) ...[
                        if (version.versionInfo!['version_number'] != null)
                          _buildSmallInfoRow(
                            'Version #',
                            version.versionInfo!['version_number'].toString(),
                            theme,
                          ),
                        if (version.versionInfo!['change_summary'] != null)
                          _buildSmallInfoRow(
                            'Changes',
                            version.versionInfo!['change_summary'].toString(),
                            theme,
                          ),
                      ],
                      if (!isFirst)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Icon(
                                version.isChainValid
                                    ? Icons.link
                                    : Icons.link_off,
                                size: 16,
                                color: version.isChainValid
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                version.isChainValid
                                    ? 'Linked to previous version'
                                    : 'Chain link BROKEN',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: version.isChainValid
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildSmallInfoRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
