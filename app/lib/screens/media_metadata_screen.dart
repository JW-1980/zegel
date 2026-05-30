import 'dart:io';

import 'package:zegel_app/utils/hex_utils.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:zegel/zegel.dart' as core;

import '../services/file_service.dart';
import '../services/zegel_service.dart';
import '../widgets/key_input.dart';

/// Screen for viewing media metadata from sealed image/video files.
///
/// Displays EXIF/GPS metadata including capture date, camera info,
/// and GPS coordinates. Shows on a map if GPS data is present.
class MediaMetadataScreen extends StatefulWidget {
  /// Optional initial .zgl file path.
  final String? initialFilePath;

  const MediaMetadataScreen({super.key, this.initialFilePath});

  @override
  State<MediaMetadataScreen> createState() => _MediaMetadataScreenState();
}

class _MediaMetadataScreenState extends State<MediaMetadataScreen> {
  String? _filePath;
  String _hexKey = '';
  bool _isLoading = false;
  Map<String, dynamic>? _metadata;
  String? _errorMessage;
  ZegelInspection? _inspection;
  // ignore: unused_element
  ZegelInspection? get _unusedInspection => _inspection;

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
        _metadata = null;
        _errorMessage = null;
        _inspection = null;
      });
    }
  }

  Future<void> _loadMetadata() async {
    if (_filePath == null) {
      setState(() => _errorMessage = 'Please select a .zgl file.');
      return;
    }
    if (_hexKey.length != 64) {
      setState(
        () => _errorMessage = 'Please enter a valid 64-character hex key.',
      );
      return;
    }

    final zegelService = context.read<ZegelService>();
    setState(() {
      _isLoading = true;
      _metadata = null;
      _errorMessage = null;
    });

    try {
      final file = File(_filePath!);
      if (!await file.exists()) {
        throw const FileSystemException('File does not exist');
      }

      final bytes = await file.readAsBytes();
      const reader = core.ZegelReader();

      // First inspect the file
      final inspection = await zegelService.inspect(_filePath!);

      // Verify and extract content
      final masterKey = HexUtils.hexToBytes(_hexKey);
      final result = reader.verify(
        bytes,
        masterKey,
      ); // Note: still returns core.ZegelResult

      if (!result.valid) {
        throw const FileSystemException('File verification failed');
      }

      // Extract basic metadata from content
      final content = result.content;
      if (content == null || content.isEmpty) {
        throw const FileSystemException('No content found in file');
      }

      // Use MediaMetadata to extract metadata
      final basicMetadata = core.MediaMetadata.extractBasicMetadata(
        content,
        result.filename ?? 'unknown',
      );

      // Merge with any metadata stored in the file
      final mergedMetadata = <String, dynamic>{
        ...basicMetadata,
        if (result.metadata != null) ...result.metadata!,
        if (inspection.publicMetadata != null) ...inspection.publicMetadata!,
      };

      if (mounted) {
        setState(() {
          _metadata = mergedMetadata;
          _inspection = inspection;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _errorMessage = l10n.errorGeneric(e.toString());
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fileService = context.read<FileService>();

    return Scaffold(
      appBar: AppBar(title: const Text('Media Metadata')),
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
                        Icon(Icons.image, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Media File (.zgl)',
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
                      onPressed: _isLoading ? null : _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Select .zgl File'),
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

            // Load metadata button
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _loadMetadata,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.photo_library),
                label: Text(
                  _isLoading ? 'Loading...' : 'Load Metadata',
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

            // Metadata display
            if (_metadata != null) ...[
              // File info
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
                      if (_metadata!['filename'] != null)
                        _buildInfoRow(
                          'Filename',
                          _metadata!['filename'].toString(),
                          theme,
                        ),
                      if (_metadata!['file_size'] != null)
                        _buildInfoRow(
                          'File Size',
                          _formatFileSize(_metadata!['file_size'] as int),
                          theme,
                        ),
                      if (_metadata!['detected_type'] != null)
                        _buildInfoRow(
                          'Detected Type',
                          _metadata!['detected_type'].toString(),
                          theme,
                        ),
                      if (_metadata!['content_hash'] != null)
                        _buildInfoRow(
                          'Content Hash',
                          _truncateHash(_metadata!['content_hash'].toString()),
                          theme,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // GPS coordinates (if present)
              if (_metadata!['gps_latitude'] != null &&
                  _metadata!['gps_longitude'] != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'GPS Location',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        _buildInfoRow(
                          'Latitude',
                          _metadata!['gps_latitude'].toString(),
                          theme,
                        ),
                        _buildInfoRow(
                          'Longitude',
                          _metadata!['gps_longitude'].toString(),
                          theme,
                        ),
                        const SizedBox(height: 12),
                        // Interactive map button
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            icon: const Icon(Icons.map),
                            label: const Text('Open in Maps'),
                            onPressed: () async {
                              final lat = double.tryParse(_metadata!['gps_latitude'].toString()) ?? 0.0;
                              final lng = double.tryParse(_metadata!['gps_longitude'].toString()) ?? 0.0;
                              final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url);
                              } else {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Could not open map')),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Camera info (if present)
              if (_metadata!['camera_make'] != null ||
                  _metadata!['camera_model'] != null ||
                  _metadata!['date_taken'] != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.camera_alt,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Camera Information',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        if (_metadata!['camera_make'] != null)
                          _buildInfoRow(
                            'Camera Make',
                            _metadata!['camera_make'].toString(),
                            theme,
                          ),
                        if (_metadata!['camera_model'] != null)
                          _buildInfoRow(
                            'Camera Model',
                            _metadata!['camera_model'].toString(),
                            theme,
                          ),
                        if (_metadata!['date_taken'] != null)
                          _buildInfoRow(
                            'Date Taken',
                            _metadata!['date_taken'].toString(),
                            theme,
                          ),
                        if (_metadata!['software'] != null)
                          _buildInfoRow(
                            'Software',
                            _metadata!['software'].toString(),
                            theme,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // All metadata (raw view)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.code, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'All Metadata',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      ..._metadata!.entries.map(
                        (entry) => _buildInfoRow(
                          entry.key,
                          entry.value.toString(),
                          theme,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _truncateHash(String hash) {
    if (hash.length <= 20) return hash;
    return '${hash.substring(0, 8)}...${hash.substring(hash.length - 8)}';
  }

  Widget _buildInfoRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
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
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
