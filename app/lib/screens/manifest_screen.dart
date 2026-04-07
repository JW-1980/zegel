import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/zegel_service.dart';
import '../widgets/key_input.dart';

/// Manifest management screen for creating and verifying file manifests.
///
/// A manifest is a signed list of .zgl files that can be used to
/// verify a collection of documents together.
class ManifestScreen extends StatefulWidget {
  const ManifestScreen({super.key});

  @override
  State<ManifestScreen> createState() => _ManifestScreenState();
}

class _ManifestScreenState extends State<ManifestScreen>
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
        title: Text(l10n.manifestTitle),
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.onPrimary,
          unselectedLabelColor: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
          indicatorColor: theme.colorScheme.onPrimary,
          tabs: [
            Tab(text: l10n.manifestCreateTab),
            Tab(text: l10n.manifestVerifyTab),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ManifestCreateTab(),
          _ManifestVerifyTab(),
        ],
      ),
    );
  }
}

/// Create tab: add files, set signer info, create manifest.
class _ManifestCreateTab extends StatefulWidget {
  const _ManifestCreateTab();

  @override
  State<_ManifestCreateTab> createState() => _ManifestCreateTabState();
}

class _ManifestCreateTabState extends State<_ManifestCreateTab> {
  final List<String> _filePaths = [];
  String _signerKeyHex = '';
  final _signerIdController = TextEditingController();
  bool _isCreating = false;
  String? _statusMessage;
  bool _isError = false;

  @override
  void dispose() {
    _signerIdController.dispose();
    super.dispose();
  }

  Future<void> _addFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickFile();
    if (path != null && !_filePaths.contains(path)) {
      setState(() => _filePaths.add(path));
    }
  }

  void _removeFile(int index) {
    setState(() => _filePaths.removeAt(index));
  }

  Future<void> _createManifest() async {
    if (_filePaths.isEmpty ||
        _signerKeyHex.length != 64 ||
        _signerIdController.text.trim().isEmpty) {
      setState(() {
        _statusMessage = 'Please provide files, signer key, and signer ID.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isCreating = true;
      _statusMessage = null;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final fileService = context.read<FileService>();
      final manifestBytes = await zegelService.createManifest(
        _filePaths,
        _signerKeyHex,
        _signerIdController.text.trim(),
      );
      final savedPath =
          await fileService.saveFile(manifestBytes, 'manifest.json');
      if (savedPath != null && mounted) {
        setState(() {
          _statusMessage = 'Manifest created and saved.';
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
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fileService = context.read<FileService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // File list
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.list_alt, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.manifestFilesLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        tooltip: l10n.manifestAddFile,
                        onPressed: _isCreating ? null : _addFile,
                      ),
                    ],
                  ),
                  if (_filePaths.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        l10n.manifestNoFiles,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    ..._filePaths.asMap().entries.map((entry) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.insert_drive_file, size: 20),
                        title: Text(
                          fileService.getFileName(entry.value),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          entry.value,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Colors.red, size: 20),
                          onPressed: () => _removeFile(entry.key),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Signer key
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: KeyInput(
                onKeyChanged: (key) => setState(() => _signerKeyHex = key),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Signer ID
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _signerIdController,
                decoration: InputDecoration(
                  labelText: l10n.manifestSignerIdLabel,
                  hintText: l10n.manifestSignerIdHint,
                  prefixIcon: const Icon(Icons.person),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

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

          // Create button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isCreating ? null : _createManifest,
              icon: _isCreating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.create_new_folder),
              label: Text(
                _isCreating
                    ? l10n.manifestCreating
                    : l10n.manifestCreateAction,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Verify tab: load manifest, verify all files.
class _ManifestVerifyTab extends StatefulWidget {
  const _ManifestVerifyTab();

  @override
  State<_ManifestVerifyTab> createState() => _ManifestVerifyTabState();
}

class _ManifestVerifyTabState extends State<_ManifestVerifyTab> {
  String? _manifestPath;
  String _signerKeyHex = '';
  String? _fileDirectory;
  bool _isVerifying = false;
  List<ManifestFileResult>? _results;
  String? _statusMessage;
  bool _isError = false;

  Future<void> _pickManifest() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickFile();
    if (path != null) {
      setState(() {
        _manifestPath = path;
        _results = null;
        _statusMessage = null;
      });
    }
  }

  Future<void> _pickFileDirectory() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickDirectory();
    if (path != null) {
      setState(() => _fileDirectory = path);
    }
  }

  Future<void> _verifyManifest() async {
    if (_manifestPath == null || _signerKeyHex.length != 64) {
      setState(() {
        _statusMessage = 'Please provide manifest file and signer key.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _statusMessage = null;
      _results = null;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final results = await zegelService.verifyManifest(
        _manifestPath!,
        _signerKeyHex,
        fileDirectory: _fileDirectory,
      );
      if (mounted) {
        final allValid = results.every((r) => r.isValid);
        setState(() {
          _results = results;
          _statusMessage = allValid
              ? 'All files in manifest verified successfully.'
              : 'Some files failed verification.';
          _isError = !allValid;
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
          // Manifest file picker
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.receipt_long,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.manifestFileLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_manifestPath != null)
                    Text(
                      context.read<FileService>().getFileName(_manifestPath!),
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
                    onPressed: _isVerifying ? null : _pickManifest,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.selectFileAction),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Signer key
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: KeyInput(
                onKeyChanged: (key) => setState(() => _signerKeyHex = key),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Optional file directory
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
                        l10n.manifestFileDirectoryLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.manifestFileDirectoryHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_fileDirectory != null)
                    Text(_fileDirectory!, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isVerifying ? null : _pickFileDirectory,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.selectFolderAction),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

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

          // Verify button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isVerifying ? null : _verifyManifest,
              icon: _isVerifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.verified_user),
              label: Text(
                _isVerifying
                    ? l10n.manifestVerifying
                    : l10n.manifestVerifyAction,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Results per file
          if (_results != null && _results!.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.manifestResultsLabel,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(),
                    ..._results!.map((r) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            r.isValid ? Icons.check_circle : Icons.error,
                            color: r.isValid ? Colors.green : Colors.red,
                          ),
                          title: Text(r.filename),
                          subtitle: Text(
                            r.message,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
