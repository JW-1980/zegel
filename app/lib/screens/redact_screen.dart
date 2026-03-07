import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/zegel_service.dart';
import '../widgets/key_input.dart';

/// Screen for permanently redacting blocks from a .zgl file.
///
/// Shows a list of blocks with checkboxes for selecting which blocks
/// to redact, with warnings about irreversibility and a confirmation dialog.
class RedactScreen extends StatefulWidget {
  const RedactScreen({super.key});

  @override
  State<RedactScreen> createState() => _RedactScreenState();
}

class _RedactScreenState extends State<RedactScreen> {
  String? _filePath;
  String _hexKey = '';
  bool _isLoading = false;
  bool _isRedacting = false;
  String? _statusMessage;
  bool _isError = false;

  List<ZegelBlockInfo>? _blocks;
  final Set<int> _selectedBlocks = {};

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickZegelFile();
    if (path != null) {
      setState(() {
        _filePath = path;
        _blocks = null;
        _selectedBlocks.clear();
        _statusMessage = null;
        _isError = false;
      });
    }
  }

  Future<void> _loadBlocks() async {
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

    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final blocks = await zegelService.listBlocks(_filePath!, _hexKey);

      if (mounted) {
        setState(() {
          _blocks = blocks;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _statusMessage = l10n.errorGeneric(e.toString());
          _isError = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _redactSelected() async {
    if (_selectedBlocks.isEmpty) {
      setState(() {
        _statusMessage = 'Please select at least one block to redact.';
        _isError = true;
      });
      return;
    }

    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.red),
              SizedBox(width: 8),
              Text('Confirm Redaction'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This action is IRREVERSIBLE.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The following ${_selectedBlocks.length} block(s) will be '
                'permanently destroyed:',
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: _selectedBlocks.map((i) {
                  return Chip(
                    label: Text(
                      'Block $i',
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: Colors.red.withValues(alpha:0.1),
                    backgroundColor: Colors.red.withValues(alpha: 0.1),
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              const Text(
                'The original content of these blocks will be replaced with '
                'random data. The Merkle tree integrity is preserved, but '
                'the content cannot be recovered.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Redact Permanently'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() {
      _isRedacting = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final fileService = context.read<FileService>();

      final redactedBytes = await zegelService.redact(
        _filePath!,
        _hexKey,
        _selectedBlocks.toList()..sort(),
      );

      final suggestedName =
          fileService.getFileName(_filePath!).replaceAll('.zgl', '_redacted.zgl');
      final savedPath =
          await fileService.saveFile(redactedBytes, suggestedName);

      if (savedPath != null && mounted) {
        setState(() {
          _statusMessage =
              'Redaction complete. ${_selectedBlocks.length} block(s) permanently removed.';
          _isError = false;
        });
      }
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
        setState(() => _isRedacting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fileService = context.read<FileService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.redactAction),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Warning banner
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha:0.3)),
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Redaction permanently destroys selected block content. '
                      'This cannot be undone.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // File picker
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                      onPressed: _isRedacting ? null : _pickFile,
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

            // Load blocks button
            if (_blocks == null)
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _loadBlocks,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.list),
                label: Text(
                  _isLoading ? 'Loading blocks...' : 'Load Block List',
                ),
              ),

            // Block list with checkboxes
            if (_blocks != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.view_list,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Blocks (${_blocks!.length})',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_selectedBlocks.length} selected',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),
                      ..._blocks!.map((block) {
                        final isRedacted = block.isRedacted;
                        return CheckboxListTile(
                          value: _selectedBlocks.contains(block.index),
                          onChanged: isRedacted
                              ? null
                              : (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _selectedBlocks.add(block.index);
                                    } else {
                                      _selectedBlocks.remove(block.index);
                                    }
                                  });
                                },
                          title: Text(
                            'Block ${block.index} - ${block.blockTypeName}',
                            style: TextStyle(
                              decoration: isRedacted
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: isRedacted
                                  ? theme.colorScheme.onSurfaceVariant
                                  : null,
                            ),
                          ),
                          subtitle: Text(
                            isRedacted
                                ? 'Already redacted'
                                : '${block.ciphertextLength} bytes',
                            style: theme.textTheme.bodySmall,
                          ),
                          secondary: Icon(
                            isRedacted
                                ? Icons.block
                                : Icons.data_array,
                            size: 20,
                            color: isRedacted ? Colors.red : null,
                          ),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Redact button
              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed:
                      _isRedacting || _selectedBlocks.isEmpty
                          ? null
                          : _redactSelected,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                  icon: _isRedacting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.content_cut),
                  label: Text(
                    _isRedacting
                        ? 'Redacting...'
                        : 'Redact ${_selectedBlocks.length} Block(s)',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],

            // Status message
            if (_statusMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isError
                        ? Colors.red.withValues(alpha:0.1)
                        : Colors.green.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isError
                          ? Colors.red.withValues(alpha:0.3)
                          : Colors.green.withValues(alpha:0.3),
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
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
