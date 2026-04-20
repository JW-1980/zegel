import 'dart:io';

import 'dart:convert';
import 'package:flutter/services.dart';

import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/zegel_service.dart';
import '../widgets/key_input.dart';

/// Screen for selective disclosure of .zgl file blocks.
///
/// Two modes:
/// - Generate Token: select blocks to disclose, create a JSON token
/// - Extract with Token: load a token file, extract disclosed blocks
class DiscloseScreen extends StatefulWidget {
  const DiscloseScreen({super.key});

  @override
  State<DiscloseScreen> createState() => _DiscloseScreenState();
}

class _DiscloseScreenState extends State<DiscloseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Generate tab state
  String? _generateFilePath;
  String _generateHexKey = '';
  List<ZegelBlockInfo>? _blocks;
  final Set<int> _selectedBlocks = {};
  bool _isLoadingBlocks = false;
  bool _isGenerating = false;
  DisclosureToken? _generatedToken;
  String? _generateError;

  // Extract tab state
  String? _extractFilePath;
  DisclosureToken? _loadedToken;
  bool _isExtracting = false;
  String? _extractStatus;
  bool _extractIsError = false;

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

  // --- Generate Token methods ---

  Future<void> _pickGenerateFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickZegelFile();
    if (path != null) {
      setState(() {
        _generateFilePath = path;
        _blocks = null;
        _selectedBlocks.clear();
        _generatedToken = null;
        _generateError = null;
      });
    }
  }

  Future<void> _loadBlocks() async {
    if (_generateFilePath == null || _generateHexKey.length != 64) {
      setState(() => _generateError = 'Select a file and enter a valid key.');
      return;
    }

    setState(() {
      _isLoadingBlocks = true;
      _generateError = null;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final blocks = await zegelService.listBlocks(
        _generateFilePath!,
        _generateHexKey,
      );
      if (mounted) {
        setState(() {
          _blocks = blocks;
          _isLoadingBlocks = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _generateError = e.toString();
          _isLoadingBlocks = false;
        });
      }
    }
  }

  Future<void> _generateToken() async {
    if (_selectedBlocks.isEmpty) {
      setState(() => _generateError = 'Select at least one block to disclose.');
      return;
    }

    setState(() {
      _isGenerating = true;
      _generateError = null;
      _generatedToken = null;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final token = await zegelService.generateDisclosureToken(
        _generateFilePath!,
        _generateHexKey,
        _selectedBlocks.toList()..sort(),
      );

      if (mounted) {
        setState(() {
          _generatedToken = token;
          _isGenerating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _generateError = e.toString();
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _exportToken() async {
    if (_generatedToken == null) return;

    final fileService = context.read<FileService>();
    final jsonStr = _generatedToken!.toJsonString();
    final bytes = utf8.encode(jsonStr);

    await fileService.saveFile(
      Uint8List.fromList(bytes),
      'disclosure_token.json',
    );
  }

  // --- Extract with Token methods ---

  Future<void> _pickExtractFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickZegelFile();
    if (path != null) {
      setState(() {
        _extractFilePath = path;
        _extractStatus = null;
        _extractIsError = false;
      });
    }
  }

  Future<void> _pickTokenFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickFile();
    if (path == null) return;

    try {
      final content = await File(path).readAsString();
      final token = DisclosureToken.fromJsonString(content);
      setState(() {
        _loadedToken = token;
        _extractStatus = null;
        _extractIsError = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _extractStatus = 'Invalid token file: $e';
          _extractIsError = true;
        });
      }
    }
  }

  Future<void> _extractWithToken() async {
    if (_extractFilePath == null || _loadedToken == null) {
      setState(() {
        _extractStatus = 'Select a .zgl file and a token file.';
        _extractIsError = true;
      });
      return;
    }

    setState(() {
      _isExtracting = true;
      _extractStatus = null;
      _extractIsError = false;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final fileService = context.read<FileService>();

      final extractedBytes = await zegelService.extractWithToken(
        _extractFilePath!,
        _loadedToken!,
        'disclosed_output',
      );

      final savedPath = await fileService.saveFile(
        extractedBytes,
        'disclosed_content',
      );

      if (savedPath != null && mounted) {
        // ignore: unused_local_variable
        // ignore: unused_local_variable
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _extractStatus = l10n.extractSuccess;
          _extractIsError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        // ignore: unused_local_variable
        // ignore: unused_local_variable
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _extractStatus = l10n.errorGeneric(e.toString());
          _extractIsError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isExtracting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.disclosureAction),
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.onPrimary,
          unselectedLabelColor: theme.colorScheme.onPrimary.withValues(
            alpha: 0.6,
          ),
          indicatorColor: theme.colorScheme.onPrimary,
          tabs: const [
            Tab(text: 'Generate Token'),
            Tab(text: 'Extract with Token'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGenerateTab(context, l10n, theme),
          _buildExtractTab(context, l10n, theme),
        ],
      ),
    );
  }

  Widget _buildGenerateTab(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    final fileService = context.read<FileService>();

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
                  if (_generateFilePath != null)
                    Text(
                      l10n.fileSelected(
                        fileService.getFileName(_generateFilePath!),
                      ),
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
                    onPressed: _pickGenerateFile,
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
                onKeyChanged: (key) => setState(() => _generateHexKey = key),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Load blocks
          if (_blocks == null)
            OutlinedButton.icon(
              onPressed: _isLoadingBlocks ? null : _loadBlocks,
              icon: _isLoadingBlocks
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.list),
              label: Text(_isLoadingBlocks ? 'Loading...' : 'Load Block List'),
            ),

          // Block list
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
                          Icons.visibility,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Select Blocks to Disclose',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_selectedBlocks.length} selected',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const Divider(),
                    ..._blocks!.map((block) {
                      return CheckboxListTile(
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
                        title: Text(
                          'Block ${block.index} - ${block.blockTypeName}',
                        ),
                        subtitle: Text(
                          block.isRedacted
                              ? 'Redacted'
                              : '${block.ciphertextLength} bytes',
                          style: theme.textTheme.bodySmall,
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

            // Generate button
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isGenerating || _selectedBlocks.isEmpty
                    ? null
                    : _generateToken,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.token),
                label: Text(
                  _isGenerating ? 'Generating...' : 'Generate Token',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],

          // Error
          if (_generateError != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _generateError!,
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
            ),

          // Generated token display
          if (_generatedToken != null) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          'Disclosure Token Generated',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    Text(
                      'Blocks disclosed: ${_generatedToken!.blockKeys.keys.toList()..sort()}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _generatedToken!.toJsonString(),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copy'),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(
                                text: _generatedToken!.toJsonString(),
                              ),
                            );
                            if (mounted) {
                              // ignore: use_build_context_synchronously
                              // ignore: use_build_context_synchronously
                              // ignore: use_build_context_synchronously
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Token copied to clipboard'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.save, size: 18),
                          label: const Text('Export'),
                          onPressed: _exportToken,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildExtractTab(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    final fileService = context.read<FileService>();

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
                        Icons.file_present,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '.zgl File',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_extractFilePath != null)
                    Text(
                      fileService.getFileName(_extractFilePath!),
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
                    onPressed: _isExtracting ? null : _pickExtractFile,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Select .zgl File'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Token file picker
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.token, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Disclosure Token',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_loadedToken != null) ...[
                    Text(
                      'Token loaded: ${_loadedToken!.blockKeys.length} block(s)',
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      'Blocks: ${_loadedToken!.blockKeys.keys.toList()..sort()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ] else
                    Text(
                      'No token loaded',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isExtracting ? null : _pickTokenFile,
                    icon: const Icon(Icons.file_open),
                    label: const Text('Load Token File'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Extract button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed:
                  _isExtracting ||
                      _extractFilePath == null ||
                      _loadedToken == null
                  ? null
                  : _extractWithToken,
              icon: _isExtracting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.file_download),
              label: Text(
                _isExtracting ? 'Extracting...' : 'Extract Disclosed Blocks',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),

          // Status
          if (_extractStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _extractIsError
                      ? Colors.red.withValues(alpha: 0.1)
                      : Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _extractIsError
                        ? Colors.red.withValues(alpha: 0.3)
                        : Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _extractIsError ? Icons.error : Icons.check_circle,
                      color: _extractIsError ? Colors.red : Colors.green,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _extractStatus!,
                        style: TextStyle(
                          color: _extractIsError
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
    );
  }
}
