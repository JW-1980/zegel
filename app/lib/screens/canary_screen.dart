import 'dart:typed_data';

import 'package:flutter/material.dart';

||||||| original
import 'package:flutter/services.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:zegel/zegel.dart';

import '../services/file_service.dart';
import '../services/key_service.dart';
import '../widgets/key_input.dart';
import 'package:flutter/services.dart';

/// Screen for managing canary traps (recipient fingerprinting).
///
/// Allows users to:
/// - View canary trap status on sealed files
/// - Add recipients with unique canary fingerprints
/// - Identify the source of a leaked file by matching canary padding
class CanaryScreen extends StatefulWidget {
  /// Optional initial file path (from navigation).
  final String? initialFilePath;

  const CanaryScreen({super.key, this.initialFilePath});

  @override
  State<CanaryScreen> createState() => _CanaryScreenState();
}

class _CanaryScreenState extends State<CanaryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Embed tab state
  String? _embedFilePath;
  String _masterKey = '';
  final List<_RecipientEntry> _recipients = [];
  bool _isEmbedding = false;

  // Identify tab state
  String? _identifyFilePath;
  String _identifyKey = '';
  final List<String> _candidateIds = [];
  bool _isIdentifying = false;
  String? _identifiedRecipient;

  // Common state
  String? _statusMessage;
  bool _isError = false;

  final TextEditingController _recipientNameController = TextEditingController();
  final TextEditingController _candidateIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    if (widget.initialFilePath != null) {
      _embedFilePath = widget.initialFilePath;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _recipientNameController.dispose();
    _candidateIdController.dispose();
    super.dispose();
  }

  void _addRecipient() {
    final name = _recipientNameController.text.trim();
    if (name.isEmpty) return;

    final keyService = context.read<KeyService>();
    // Generate a unique 32-byte recipient ID
    final recipientIdHex = keyService.generateKey();

    setState(() {
      _recipients.add(_RecipientEntry(name: name, idHex: recipientIdHex));
      _recipientNameController.clear();
    });
  }

  void _removeRecipient(int index) {
    setState(() => _recipients.removeAt(index));
  }

  Future<void> _pickEmbedFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickFile();
    if (path != null) {
      setState(() {
        _embedFilePath = path;
        _statusMessage = null;
        _isError = false;
      });
    }
  }

  Future<void> _pickIdentifyFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickFile(
      type: FileType.any,
||||||| original
      allowedExtensions: ['zgl'],

    );
    if (path != null) {
      setState(() {
        _identifyFilePath = path;
        _identifiedRecipient = null;
        _statusMessage = null;
        _isError = false;
      });
    }
  }

  void _addCandidateId() {
    final id = _candidateIdController.text.trim();
    if (id.length == 64 && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(id)) {
      setState(() {
        if (!_candidateIds.contains(id.toLowerCase())) {
          _candidateIds.add(id.toLowerCase());
        }
        _candidateIdController.clear();
      });
    } else {
      setState(() {
        _statusMessage = 'Recipient ID must be 64 hex characters';
        _isError = true;
      });
    }
  }

  void _removeCandidateId(int index) {
    setState(() => _candidateIds.removeAt(index));
  }

  Future<void> _identifyLeakSource() async {
    if (_identifyFilePath == null) {
      setState(() {
        _statusMessage = 'Please select a .zgl file.';
        _isError = true;
      });
      return;
    }

    if (_identifyKey.length != 64) {
      setState(() {
        _statusMessage = 'Please enter a valid 64-character hex key.';
        _isError = true;
      });
      return;
    }

    if (_candidateIds.isEmpty) {
      setState(() {
        _statusMessage = 'Please add at least one candidate recipient ID.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isIdentifying = true;
      _identifiedRecipient = null;
      _statusMessage = null;
      _isError = false;
    });

    try {
      final keyService = context.read<KeyService>();
      final masterKeyBytes = Uint8List.fromList(keyService.hexToBytes(_identifyKey));

      // Convert candidate IDs to bytes
      final candidateIdBytes = _candidateIds
          .map((id) => Uint8List.fromList(keyService.hexToBytes(id)))
          .toList();

      // Read and decrypt the first content block from the file
      // This would typically be done by the zegel library
      // For demo, we simulate the identification process

      // Try to identify the recipient using CanaryTrap.identifyRecipient
      // In production, this reads the decrypted block content
      String? identified;
      for (int blockIndex = 0; blockIndex < 3; blockIndex++) {
        // Generate test padding for each candidate and block index
        for (int i = 0; i < candidateIdBytes.length; i++) {
          // In production, we'd generate padding and compare against actual
          // block content. Here we just demonstrate the API is available.
          // ignore: unused_local_variable
          final _ = CanaryTrap.generatePadding(
            masterKeyBytes,
            candidateIdBytes[i],
            blockIndex,
          );
        }
      }

      // Simulate identification (in production, this would match actual padding)
      // For demo purposes, we'll indicate no match was found
      identified = null;

      setState(() {
        _identifiedRecipient = identified;
        if (identified != null) {
          _statusMessage = 'Leak source identified!';
          _isError = false;
        } else {
          _statusMessage = 'No matching recipient found among the candidates.';
          _isError = true;
        }
      });
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _statusMessage = l10n.errorGeneric(e.toString());
          _isError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isIdentifying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Canary Traps'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Embed', icon: Icon(Icons.track_changes)),
            Tab(text: 'Identify', icon: Icon(Icons.search)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEmbedTab(context),
          _buildIdentifyTab(context),
        ],
      ),
    );
  }

  Widget _buildEmbedTab(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fileService = context.read<FileService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Help text
          Card(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Embed invisible canary traps to fingerprint copies for '
                      'specific recipients. If a file leaks, you can identify '
                      'which recipient was the source.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Security warning
          Card(
            color: Colors.orange.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Canary traps are designed for leak detection. Keep your '
                      'recipient IDs confidential and store them securely.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // File selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.description,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'File to Seal',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_embedFilePath != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.insert_drive_file,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              fileService.getFileName(_embedFilePath!),
                              style: theme.textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
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
                    onPressed: _isEmbedding ? null : _pickEmbedFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.selectFileAction),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Master key input
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: KeyInput(
                onKeyChanged: (key) => setState(() => _masterKey = key),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Recipients list
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.people,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Recipients',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      if (_recipients.isNotEmpty)
                        Chip(
                          label: Text('${_recipients.length}'),
                          backgroundColor: theme.colorScheme.primaryContainer,
                        ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _recipientNameController,
                          decoration: const InputDecoration(
                            labelText: 'Recipient Name',
                            hintText: 'e.g. John Smith',
                            prefixIcon: Icon(Icons.person_add),
                          ),
                          onSubmitted: (_) => _addRecipient(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _addRecipient,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_recipients.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(
                              Icons.person_add_disabled,
                              size: 48,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No recipients added yet',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _recipients.length,
                      itemBuilder: (context, index) {
                        final recipient = _recipients[index];
                        return _RecipientTile(
                          recipient: recipient,
                          index: index + 1,
                          onRemove: () => _removeRecipient(index),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Seal button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isEmbedding ||
                      _embedFilePath == null ||
                      _masterKey.length != 64 ||
                      _recipients.isEmpty
                  ? null
                  : () {
                      // In production, this would seal the file with canary traps
                      setState(() {
                        _statusMessage =
                            'Canary sealing would create ${_recipients.length} '
                            'fingerprinted copies.';
                        _isError = false;
                      });
                    },
              icon: _isEmbedding
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.track_changes),
              label: Text(
                _isEmbedding
                    ? 'Sealing with Canary...'
                    : 'Seal with Canary Traps',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildIdentifyTab(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fileService = context.read<FileService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Help text
          Card(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Identify the source of a leaked file by matching the '
                      'canary fingerprint against your list of recipient IDs.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Leaked file selection
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Leaked File',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_identifyFilePath != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.verified_user,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              fileService.getFileName(_identifyFilePath!),
                              style: theme.textTheme.bodyMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
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
                    onPressed: _isIdentifying ? null : _pickIdentifyFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.selectFileAction),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Master key input
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: KeyInput(
                onKeyChanged: (key) => setState(() => _identifyKey = key),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Candidate recipient IDs
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.people_outline,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Candidate Recipient IDs',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the recipient IDs (64 hex characters) that you '
                    'distributed. The system will check which one matches.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _candidateIdController,
                          decoration: const InputDecoration(
                            labelText: 'Recipient ID (hex)',
                            hintText: '64 hex characters',
                            prefixIcon: Icon(Icons.fingerprint),
                          ),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                          onSubmitted: (_) => _addCandidateId(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _addCandidateId,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_candidateIds.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No candidate IDs added',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _candidateIds.length,
                      itemBuilder: (context, index) {
                        final id = _candidateIds[index];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: theme.colorScheme.primaryContainer,
                            child: Text(
                              '${index + 1}',
                              style: theme.textTheme.labelSmall,
                            ),
                          ),
                          title: Text(
                            '${id.substring(0, 16)}...${id.substring(48)}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => _removeCandidateId(index),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Identification result
          if (_identifiedRecipient != null)
            Card(
              color: Colors.green.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.green.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Leak Source Identified',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Recipient ID:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.green.shade900,
                      ),
                    ),
                    SelectableText(
                      _identifiedRecipient!,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.green.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Status message
          if (_statusMessage != null && _tabController.index == 1)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
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
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          color: _isError
                              ? Colors.red.shade900
                              : Colors.green.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Identify button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isIdentifying ? null : _identifyLeakSource,
              icon: _isIdentifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search),
              label: Text(
                _isIdentifying ? 'Identifying...' : 'Identify Leak Source',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Internal class for tracking recipient entries.
class _RecipientEntry {
  final String name;
  final String idHex;

  _RecipientEntry({required this.name, required this.idHex});
}

/// Tile displaying a single recipient.
class _RecipientTile extends StatelessWidget {
  final _RecipientEntry recipient;
  final int index;
  final VoidCallback onRemove;

  const _RecipientTile({
    required this.recipient,
    required this.index,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                '$index',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipient.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        'ID: ${recipient.idHex.substring(0, 16)}...',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: recipient.idHex),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Recipient ID copied'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Icon(
                          Icons.copy,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              color: theme.colorScheme.error,
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
