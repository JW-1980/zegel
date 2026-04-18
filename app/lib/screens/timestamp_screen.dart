import 'package:zegel_app/utils/hex_utils.dart';
import 'dart:io';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:zegel/zegel.dart';

import '../services/file_service.dart';
import '../widgets/key_input.dart';

/// Screen for timestamp management - requesting trusted timestamps
/// and verifying existing timestamps.
class TimestampScreen extends StatefulWidget {
  /// Optional initial .zgl file path.
  final String? initialFilePath;

  const TimestampScreen({super.key, this.initialFilePath});

  @override
  State<TimestampScreen> createState() => _TimestampScreenState();
}

class _TimestampScreenState extends State<TimestampScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _filePath;
  String _hexKey = '';
  // ignore: unused_field
  // ignore: unused_field
  // ignore: unused_field
  String _tsaUrl = '';
  bool _isLoading = false;
  Map<String, dynamic>? _timestampToken;
  String? _errorMessage;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.initialFilePath != null) {
      _filePath = widget.initialFilePath;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickZegelFile();
    if (path != null) {
      setState(() {
        _filePath = path;
        _timestampToken = null;
        _errorMessage = null;
        _successMessage = null;
      });
    }
  }

  Future<void> _createTimestamp() async {
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

    setState(() {
      _isLoading = true;
      _timestampToken = null;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final file = File(_filePath!);
      if (!await file.exists()) {
        throw Exception('File does not exist');
      }

      final bytes = await file.readAsBytes();
      const reader = ZegelReader();
      // ignore: unused_local_variable
      // ignore: unused_local_variable
      // ignore: unused_local_variable
      final inspection = reader.inspect(bytes);

      // Extract Merkle root and master seal from file
      // The Merkle root is at a known position after the block directory
      // The master seal is the last 64 bytes
      final masterSeal = Uint8List.fromList(
        bytes.sublist(bytes.length - ZegelFormat.sealSize),
      );

      // Parse enough to get the Merkle root (simplified)
      // In a real implementation, this would be extracted from the reader
      final merkleRoot = _extractMerkleRoot(bytes);

      // Create a local timestamp token using the signer key
      final signerKey = HexUtils.hexToBytes(_hexKey);
      final token = TrustedTimestamp.createLocalToken(
        merkleRoot,
        masterSeal,
        signerKey,
      );

      if (mounted) {
        setState(() {
          _timestampToken = token;
          _successMessage = 'Timestamp created successfully';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
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

  Future<void> _verifyTimestamp() async {
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
    if (_timestampToken == null) {
      setState(() => _errorMessage = 'No timestamp token to verify.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final file = File(_filePath!);
      if (!await file.exists()) {
        throw Exception('File does not exist');
      }

      final bytes = await file.readAsBytes();

      // Extract Merkle root and master seal
      final masterSeal = Uint8List.fromList(
        bytes.sublist(bytes.length - ZegelFormat.sealSize),
      );
      final merkleRoot = _extractMerkleRoot(bytes);
      final signerKey = HexUtils.hexToBytes(_hexKey);

      // Verify the timestamp token
      final isValid = TrustedTimestamp.verifyLocalToken(
        _timestampToken!,
        merkleRoot,
        masterSeal,
        signerKey,
      );

      if (mounted) {
        setState(() {
          if (isValid) {
            _successMessage = 'Timestamp is VALID';
          } else {
            _errorMessage = 'Timestamp verification FAILED';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
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

  Uint8List _extractMerkleRoot(Uint8List bytes) {
    // Simplified Merkle root extraction
    // In practice, this should use the ZegelReader's parsing
    final bd = ByteData.sublistView(bytes);

    // Skip magic (8) + version (2) + flags (2) + timestamp (8) + content-type (64)
    final filenameLen = bd.getUint16(84, Endian.big);
    final saltOffset = 86 + filenameLen;
    final blockCountOffset = saltOffset + ZegelFormat.saltSize;
    final blockCount = bd.getUint32(blockCountOffset, Endian.big);
    final flags = bd.getUint16(10, Endian.big);

    // Calculate directory start after extended header
    int cursor = blockCountOffset + 4;
    if (flags & ZegelFormat.flagPasswordDerived != 0) cursor += 8;
    if (flags & ZegelFormat.flagHasExpiration != 0) cursor += 8;
    if (flags & ZegelFormat.flagHasCanary != 0) cursor += 32;
    if (flags & ZegelFormat.flagSplitKey != 0) cursor += 2;
    if (flags & ZegelFormat.flagVersioned != 0) cursor += 32;
    if (flags & ZegelFormat.flagHasPublicMetadata != 0) {
      final pubMetaLen = bd.getUint32(cursor, Endian.big);
      cursor += 4 + pubMetaLen;
    }

    // Skip block directory
    cursor += blockCount * ZegelFormat.blockDirectoryEntrySize;

    // Merkle root is here (32 bytes)
    return Uint8List.fromList(
      bytes.sublist(cursor, cursor + ZegelFormat.hashSize),
    );
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

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fileService = context.read<FileService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trusted Timestamps'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Create'),
            Tab(text: 'Verify'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Create timestamp tab
          _buildCreateTab(theme, l10n, fileService),
          // Verify timestamp tab
          _buildVerifyTab(theme, l10n, fileService),
        ],
      ),
    );
  }

  Widget _buildCreateTab(
    ThemeData theme,
    AppLocalizations l10n,
    FileService fileService,
  ) {
    return SingleChildScrollView(
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
                      'Create a trusted timestamp to prove a file existed at a specific time.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // File picker
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'File to Timestamp',
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

          // TSA URL input (optional)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.public, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Timestamp Authority (Optional)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      labelText: l10n.settingsTsaUrl,
                      hintText: l10n.settingsTsaUrlHint,
                      helperText: 'Leave empty to create a local timestamp',
                    ),
                    // ignore: deprecated_member_use
                    // ignore: deprecated_member_use
                    onChanged: (value) => setState(() => _tsaUrl = value),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Create button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _createTimestamp,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.schedule_send),
              label: Text(
                _isLoading ? 'Creating...' : 'Create Timestamp',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Messages
          if (_errorMessage != null)
            _buildMessageBox(_errorMessage!, Colors.red, Icons.error),
          if (_successMessage != null)
            _buildMessageBox(
              _successMessage!,
              Colors.green,
              Icons.check_circle,
            ),

          // Timestamp token display
          if (_timestampToken != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.receipt_long,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Timestamp Token',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    _buildInfoRow(
                      'Type',
                      _timestampToken!['type']?.toString() ?? 'local',
                      theme,
                    ),
                    _buildInfoRow(
                      'Timestamp',
                      _formatTimestamp(_timestampToken!['timestamp'] as int),
                      theme,
                    ),
                    _buildInfoRow(
                      'Merkle Root',
                      _truncateHash(
                        _timestampToken!['merkle_root']?.toString() ?? '',
                      ),
                      theme,
                    ),
                    _buildInfoRow(
                      'Signature',
                      _truncateHash(
                        _timestampToken!['signature']?.toString() ?? '',
                      ),
                      theme,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVerifyTab(
    ThemeData theme,
    AppLocalizations l10n,
    FileService fileService,
  ) {
    return SingleChildScrollView(
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
                      'Verify that a timestamp token matches a .zgl file.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

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
                        Icons.verified_user,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'File to Verify',
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

          // Timestamp token status
          if (_timestampToken != null) ...[
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Timestamp token loaded',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          Text(
                            'Created: ${_formatTimestamp(_timestampToken!['timestamp'] as int)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade800,
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
          ] else ...[
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No timestamp token loaded. Create a timestamp first.',
                        style: TextStyle(color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Verify button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: (_isLoading || _timestampToken == null)
                  ? null
                  : _verifyTimestamp,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.verified),
              label: Text(
                _isLoading ? 'Verifying...' : 'Verify Timestamp',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Messages
          if (_errorMessage != null)
            _buildMessageBox(_errorMessage!, Colors.red, Icons.error),
          if (_successMessage != null)
            _buildMessageBox(
              _successMessage!,
              Colors.green,
              Icons.check_circle,
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBox(String message, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: color.shade900)),
          ),
        ],
      ),
    );
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
            width: 100,
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
            ),
          ),
        ],
      ),
    );
  }
}

extension on Color {
  Color get shade900 => this;
}
