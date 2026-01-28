import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:zegel/zegel.dart';

import '../services/file_service.dart';
import '../services/zegel_service.dart';
import '../widgets/key_input.dart';
import '../widgets/audit_trail_view.dart';

/// Screen for viewing and adding audit trail entries.
///
/// Displays the tamper-evident audit trail from a .zgl file, verifies
/// chain hash integrity, and allows adding new audit entries.
class AuditScreen extends StatefulWidget {
  /// Optional initial file path (from navigation).
  final String? initialFilePath;

  const AuditScreen({super.key, this.initialFilePath});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  String? _filePath;
  String _hexKey = '';
  bool _isLoading = false;
  bool _isAddingEntry = false;
  String? _statusMessage;
  bool _isError = false;
  List<ZegelAuditEntry>? _auditEntries;
  bool _isChainValid = false;

  // New entry fields
  String _actor = '';
  String _action = 'verified';
  final Map<String, String> _details = {};
  final TextEditingController _actorController = TextEditingController();
  final TextEditingController _detailKeyController = TextEditingController();
  final TextEditingController _detailValueController = TextEditingController();

  static const List<String> _actionTypes = [
    'sealed',
    'verified',
    'redacted',
    'attested',
    'disclosed',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initialFilePath != null) {
      _setFile(widget.initialFilePath!);
    }
  }

  @override
  void dispose() {
    _actorController.dispose();
    _detailKeyController.dispose();
    _detailValueController.dispose();
    super.dispose();
  }

  Future<void> _setFile(String path) async {
    setState(() {
      _filePath = path;
      _statusMessage = null;
      _isError = false;
      _auditEntries = null;
      _isChainValid = false;
    });
  }

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickFile(
      allowedExtensions: ['zgl'],
    );
    if (path != null) {
      await _setFile(path);
    }
  }

  Future<void> _loadAuditTrail() async {
    if (_filePath == null || _hexKey.length != 64) return;

    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final result = await zegelService.verify(_filePath!, _hexKey);

      // Verify chain integrity using the AuditTrail class
      final entries = result.auditTrail ?? [];
      final chainValid = entries.isEmpty ||
          AuditTrail.verifyChain(
            entries
                .map((e) => <String, dynamic>{
                      'actor': e.actor,
                      'action': e.action,
                      'timestamp': e.timestamp.millisecondsSinceEpoch ~/ 1000,
                      if (e.details != null) 'details': e.details,
                      'chain_hash': e.chainHash,
                    })
                .toList(),
          );

      setState(() {
        _auditEntries = entries;
        _isChainValid = chainValid;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Failed to load audit trail: $e';
          _isError = true;
          _isLoading = false;
        });
      }
    }
  }

  void _addDetail() {
    final key = _detailKeyController.text.trim();
    final value = _detailValueController.text.trim();
    if (key.isNotEmpty && value.isNotEmpty) {
      setState(() {
        _details[key] = value;
        _detailKeyController.clear();
        _detailValueController.clear();
      });
    }
  }

  void _removeDetail(String key) {
    setState(() => _details.remove(key));
  }

  Future<void> _addAuditEntry() async {
    if (_filePath == null) {
      setState(() {
        _statusMessage = 'Please select a .zgl file.';
        _isError = true;
      });
      return;
    }

    if (_hexKey.length != 64) {
      setState(() {
        _statusMessage = 'Please enter a valid 64-character hex key.';
        _isError = true;
      });
      return;
    }

    if (_actor.trim().isEmpty) {
      setState(() {
        _statusMessage = 'Please enter an actor ID.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isAddingEntry = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      // Get the previous chain hash from the last entry
      Uint8List? previousChainHash;
      if (_auditEntries != null && _auditEntries!.isNotEmpty) {
        final lastHash = _auditEntries!.last.chainHash;
        previousChainHash = _hexToBytes(lastHash);
      }

      // Create the new audit entry
      final newEntry = AuditTrail.createEntry(
        _actor.trim(),
        _action,
        details: _details.isNotEmpty ? Map<String, dynamic>.from(_details) : null,
        previousChainHash: previousChainHash,
      );

      // For demo purposes, show success and refresh
      // In production, this would write the entry to the file
      setState(() {
        _statusMessage = 'Audit entry created (chain hash: ${(newEntry['chain_hash'] as String).substring(0, 16)}...)';
        _isError = false;
        _actorController.clear();
        _actor = '';
        _details.clear();
      });

      // Reload the audit trail
      await _loadAuditTrail();
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
        setState(() => _isAddingEntry = false);
      }
    }
  }

  Uint8List _hexToBytes(String hex) {
    final length = hex.length ~/ 2;
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fileService = context.read<FileService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.auditTrailTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Help text
            Card(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
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
                        'View the tamper-evident audit trail. Each entry is '
                        'cryptographically chained to the previous one, making '
                        'any modifications detectable.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // File selection card
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
                          'File to Inspect',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_filePath != null)
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
                                fileService.getFileName(_filePath!),
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
                      onPressed: _isAddingEntry ? null : _pickFile,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KeyInput(
                      onKeyChanged: (key) {
                        setState(() => _hexKey = key);
                        if (key.length == 64 && _filePath != null) {
                          _loadAuditTrail();
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _filePath != null && _hexKey.length == 64
                          ? _loadAuditTrail
                          : null,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Load Audit Trail'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Chain integrity status
            if (_auditEntries != null)
              Card(
                color: _isChainValid
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        _isChainValid ? Icons.link : Icons.link_off,
                        color: _isChainValid ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isChainValid
                                  ? 'Chain Integrity Verified'
                                  : 'Chain Integrity Broken',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _isChainValid ? Colors.green : Colors.red,
                              ),
                            ),
                            Text(
                              _isChainValid
                                  ? 'All audit entries are cryptographically linked correctly.'
                                  : 'One or more audit entries have been modified!',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _isChainValid
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
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

            // Audit trail display
            if (_isLoading)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_auditEntries != null)
              AuditTrailView(entries: _auditEntries!),

            const SizedBox(height: 16),

            // Add new entry section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.add_circle,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Add Audit Entry',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _actorController,
                      decoration: const InputDecoration(
                        labelText: 'Actor',
                        hintText: 'e.g. user:42:admin@example.com',
                        prefixIcon: Icon(Icons.person),
                      ),
                      onChanged: (v) => setState(() => _actor = v),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _action,
                      decoration: const InputDecoration(
                        labelText: 'Action',
                        prefixIcon: Icon(Icons.play_arrow),
                      ),
                      items: _actionTypes.map((action) {
                        return DropdownMenuItem(
                          value: action,
                          child: Row(
                            children: [
                              Icon(_actionIcon(action), size: 18),
                              const SizedBox(width: 8),
                              Text(action.toUpperCase()),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: _isAddingEntry
                          ? null
                          : (v) => setState(() => _action = v!),
                    ),
                    const SizedBox(height: 16),

                    // Details section
                    Text(
                      'Details (optional)',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _detailKeyController,
                            decoration: const InputDecoration(
                              labelText: 'Key',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _detailValueController,
                            decoration: const InputDecoration(
                              labelText: 'Value',
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: _addDetail,
                        ),
                      ],
                    ),
                    if (_details.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _details.entries.map((entry) {
                          return Chip(
                            label: Text('${entry.key}: ${entry.value}'),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () => _removeDetail(entry.key),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Status message
            if (_statusMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isError
                        ? Colors.red.withOpacity(0.1)
                        : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isError
                          ? Colors.red.withOpacity(0.3)
                          : Colors.green.withOpacity(0.3),
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

            // Add entry button
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isAddingEntry ? null : _addAuditEntry,
                icon: _isAddingEntry
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.add),
                label: Text(
                  _isAddingEntry ? 'Adding Entry...' : 'Add Audit Entry',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  IconData _actionIcon(String action) {
    switch (action) {
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
}
