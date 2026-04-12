import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/zegel_service.dart';
import '../widgets/key_input.dart';

/// Excerpt proof management screen.
///
/// Allows generating cryptographic proofs for specific blocks of a .zgl file,
/// and verifying those proofs without needing the master key.
class ExcerptScreen extends StatefulWidget {
  const ExcerptScreen({super.key});

  @override
  State<ExcerptScreen> createState() => _ExcerptScreenState();
}

class _ExcerptScreenState extends State<ExcerptScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.excerptTitle),
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.onPrimary,
          unselectedLabelColor: theme.colorScheme.onPrimary.withValues(
            alpha: 0.7,
          ),
          indicatorColor: theme.colorScheme.onPrimary,
          tabs: [
            Tab(text: l10n.excerptGenerateTab),
            Tab(text: l10n.excerptVerifyTab),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_ExcerptGenerateTab(), _ExcerptVerifyTab()],
      ),
    );
  }
}

/// Generate tab: pick .zgl file, select blocks, generate proof JSON.
class _ExcerptGenerateTab extends StatefulWidget {
  const _ExcerptGenerateTab();

  @override
  State<_ExcerptGenerateTab> createState() => _ExcerptGenerateTabState();
}

class _ExcerptGenerateTabState extends State<_ExcerptGenerateTab> {
  String? _filePath;
  String _hexKey = '';
  List<ZegelBlockInfo>? _blocks;
  final Set<int> _selectedBlocks = {};
  bool _isLoading = false;
  bool _isGenerating = false;
  String? _statusMessage;
  bool _isError = false;

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickZegelFile();
    if (path != null) {
      setState(() {
        _filePath = path;
        _blocks = null;
        _selectedBlocks.clear();
        _statusMessage = null;
      });
    }
  }

  Future<void> _loadBlocks() async {
    if (_filePath == null || _hexKey.length != 64) return;

    setState(() {
      _isLoading = true;
      _statusMessage = null;
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
        setState(() {
          _statusMessage = 'Error loading blocks: $e';
          _isError = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _generateProof() async {
    if (_filePath == null || _selectedBlocks.isEmpty || _hexKey.length != 64) {
      setState(() {
        _statusMessage = 'Please select a file, enter key, and choose blocks.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isGenerating = true;
      _statusMessage = null;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final fileService = context.read<FileService>();
      final proofJson = await zegelService.generateExcerptProof(
        _filePath!,
        _hexKey,
        _selectedBlocks.toList()..sort(),
      );
      final savedPath = await fileService.saveFile(
        proofJson,
        'excerpt_proof.json',
      );
      if (savedPath != null && mounted) {
        setState(() {
          _statusMessage = 'Excerpt proof saved.';
          _isError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error: $e';
          _isError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SingleChildScrollView(
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
                      Icon(Icons.description, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.excerptFileLabel,
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
                    onPressed: _isGenerating ? null : _pickFile,
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

          // Load blocks button
          if (_filePath != null && _hexKey.length == 64 && _blocks == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _loadBlocks,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(l10n.excerptLoadBlocks),
              ),
            ),

          // Block selector
          if (_blocks != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.view_list, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          l10n.excerptSelectBlocks,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    ..._blocks!.map((block) {
                      return CheckboxListTile(
                        dense: true,
                        title: Text(
                          'Block ${block.index}: ${block.blockTypeName}',
                          style: theme.textTheme.bodyMedium,
                        ),
                        subtitle: Text(
                          '${block.ciphertextLength} bytes${block.isRedacted ? ' (REDACTED)' : ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: block.isRedacted
                                ? Colors.red
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        // ignore: deprecated_member_use
                        // ignore: deprecated_member_use
                        value: _selectedBlocks.contains(block.index),
                        onChanged: block.isRedacted
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
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Status message
          if (_statusMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
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
                    Expanded(child: Text(_statusMessage!)),
                  ],
                ),
              ),
            ),

          // Generate button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isGenerating || _selectedBlocks.isEmpty
                  ? null
                  : _generateProof,
              icon: _isGenerating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.receipt_long),
              label: Text(
                _isGenerating
                    ? l10n.excerptGenerating
                    : l10n.excerptGenerateAction,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Verify tab: pick .zgl file and proof JSON, verify without key.
class _ExcerptVerifyTab extends StatefulWidget {
  const _ExcerptVerifyTab();

  @override
  State<_ExcerptVerifyTab> createState() => _ExcerptVerifyTabState();
}

class _ExcerptVerifyTabState extends State<_ExcerptVerifyTab> {
  String? _filePath;
  String? _proofPath;
  bool _isVerifying = false;
  bool? _isValid;
  String? _statusMessage;

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickZegelFile();
    if (path != null) {
      setState(() {
        _filePath = path;
        _isValid = null;
        _statusMessage = null;
      });
    }
  }

  Future<void> _pickProof() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickFile();
    if (path != null) {
      setState(() {
        _proofPath = path;
        _isValid = null;
        _statusMessage = null;
      });
    }
  }

  Future<void> _verifyProof() async {
    if (_filePath == null || _proofPath == null) {
      setState(() {
        _statusMessage = 'Please select both the .zgl file and proof file.';
        _isValid = null;
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _isValid = null;
      _statusMessage = null;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final valid = await zegelService.verifyExcerptProof(
        _filePath!,
        _proofPath!,
      );
      if (mounted) {
        setState(() {
          _isValid = valid;
          _statusMessage = valid
              ? 'Excerpt proof is VALID'
              : 'Excerpt proof is INVALID';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isValid = false;
          _statusMessage = 'Error: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // .zgl file picker
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
                        l10n.excerptZglFileLabel,
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
                    onPressed: _isVerifying ? null : _pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.selectFileAction),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Proof file picker
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
                        l10n.excerptProofFileLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_proofPath != null)
                    Text(
                      context.read<FileService>().getFileName(_proofPath!),
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
                    onPressed: _isVerifying ? null : _pickProof,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.selectFileAction),
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
              onPressed: _isVerifying || _filePath == null || _proofPath == null
                  ? null
                  : _verifyProof,
              icon: _isVerifying
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
                _isVerifying ? l10n.excerptVerifying : l10n.excerptVerifyAction,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Large status indicator
          if (_isValid != null)
            Center(
              child: Column(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (_isValid! ? Colors.green : Colors.red).withValues(
                        alpha: 0.1,
                      ),
                      border: Border.all(
                        color: _isValid! ? Colors.green : Colors.red,
                        width: 3,
                      ),
                    ),
                    child: Icon(
                      _isValid! ? Icons.verified : Icons.gpp_bad,
                      size: 64,
                      color: _isValid! ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage ?? '',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _isValid! ? Colors.green : Colors.red,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
