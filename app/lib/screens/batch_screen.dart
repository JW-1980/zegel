import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/zegel_service.dart';
import '../widgets/key_input.dart';

/// Batch operations screen for verifying or sealing multiple files at once.
///
/// Features two tabs:
/// - Batch Verify: verify a folder of .zgl files
/// - Batch Seal: seal a folder of files into .zgl format
class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key});

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen>
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
        title: Text(l10n.batchOperationsTitle),
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.onPrimary,
          unselectedLabelColor: theme.colorScheme.onPrimary.withValues(
            alpha: 0.7,
          ),
          indicatorColor: theme.colorScheme.onPrimary,
          tabs: [
            Tab(text: l10n.batchVerifyTab),
            Tab(text: l10n.batchSealTab),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_BatchVerifyTab(), _BatchSealTab()],
      ),
    );
  }
}

/// Status of a single file in a batch operation.
class _BatchFileResult {
  final String filename;
  final bool success;
  final String message;
  final Duration duration;

  const _BatchFileResult({
    required this.filename,
    required this.success,
    required this.message,
    required this.duration,
  });
}

/// Batch Verify tab: pick a folder, enter key, verify all .zgl files.
class _BatchVerifyTab extends StatefulWidget {
  const _BatchVerifyTab();

  @override
  State<_BatchVerifyTab> createState() => _BatchVerifyTabState();
}

class _BatchVerifyTabState extends State<_BatchVerifyTab> {
  String? _folderPath;
  String _hexKey = '';
  bool _isProcessing = false;
  double _progress = 0.0;
  List<_BatchFileResult> _results = [];
  int _totalFiles = 0;
  int _processedFiles = 0;

  Future<void> _pickFolder() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickDirectory();
    if (path != null) {
      setState(() {
        _folderPath = path;
        _results = [];
      });
    }
  }

  Future<void> _startBatchVerify() async {
    if (_folderPath == null || _hexKey.length != 64) return;

    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _results = [];
      _processedFiles = 0;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final fileService = context.read<FileService>();
      final files = await fileService.listZegelFiles(_folderPath!);
      _totalFiles = files.length;

      const chunkSize = 20;
      for (int i = 0; i < files.length; i += chunkSize) {
        final end = (i + chunkSize < files.length)
            ? i + chunkSize
            : files.length;
        final chunk = files.sublist(i, end);

        final futures = chunk.map((filePath) async {
          final stopwatch = Stopwatch()..start();
          try {
            final result = await zegelService.verify(filePath, _hexKey);
            stopwatch.stop();
            return _BatchFileResult(
              filename: fileService.getFileName(filePath),
              success: result.status == ZegelStatus.valid,
              message: result.message,
              duration: stopwatch.elapsed,
            );
          } catch (e) {
            stopwatch.stop();
            return _BatchFileResult(
              filename: fileService.getFileName(filePath),
              success: false,
              message: e.toString(),
              duration: stopwatch.elapsed,
            );
          }
        });

        final chunkResults = await Future.wait(futures);

        if (mounted) {
          setState(() {
            _processedFiles += chunk.length;
            _progress = _processedFiles / _totalFiles;
            _results.addAll(chunkResults);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Batch verify error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final successCount = _results.where((r) => r.success).length;
    final failedCount = _results.where((r) => !r.success).length;
    final totalTime = _results.fold<Duration>(
      Duration.zero,
      (sum, r) => sum + r.duration,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Folder picker
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
                        l10n.batchInputFolder,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_folderPath != null)
                    Text(_folderPath!, style: theme.textTheme.bodyMedium)
                  else
                    Text(
                      l10n.noFolderSelected,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _pickFolder,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.selectFolderAction),
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

          // Progress bar
          if (_isProcessing) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      // ignore: deprecated_member_use
                      // ignore: deprecated_member_use
                      value: _progress,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_processedFiles / $_totalFiles files processed',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Start button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed:
                  _isProcessing || _folderPath == null || _hexKey.length != 64
                  ? null
                  : _startBatchVerify,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(
                _isProcessing ? l10n.batchProcessing : l10n.batchStartVerify,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Results table
          if (_results.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.batchResults,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(),
                    ..._results.map((r) => _ResultRow(result: r)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Summary card
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _SummaryItem(
                      icon: Icons.check_circle,
                      color: Colors.green,
                      label: l10n.batchVerified,
                      // ignore: deprecated_member_use
                      // ignore: deprecated_member_use
                      value: '$successCount',
                    ),
                    _SummaryItem(
                      icon: Icons.error,
                      color: Colors.red,
                      label: l10n.batchFailed,
                      // ignore: deprecated_member_use
                      // ignore: deprecated_member_use
                      value: '$failedCount',
                    ),
                    _SummaryItem(
                      icon: Icons.timer,
                      color: theme.colorScheme.primary,
                      label: l10n.batchTotalTime,
                      // ignore: deprecated_member_use
                      // ignore: deprecated_member_use
                      value: '${totalTime.inMilliseconds}ms',
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
}

/// Batch Seal tab: pick input/output folders, enter key, seal all files.
class _BatchSealTab extends StatefulWidget {
  const _BatchSealTab();

  @override
  State<_BatchSealTab> createState() => _BatchSealTabState();
}

class _BatchSealTabState extends State<_BatchSealTab> {
  String? _inputFolder;
  String? _outputFolder;
  String _hexKey = '';
  bool _isProcessing = false;
  double _progress = 0.0;
  List<_BatchFileResult> _results = [];
  int _totalFiles = 0;
  int _processedFiles = 0;
  bool _compress = false;

  Future<void> _pickInputFolder() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickDirectory();
    if (path != null) {
      setState(() {
        _inputFolder = path;
        _results = [];
      });
    }
  }

  Future<void> _pickOutputFolder() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickDirectory();
    if (path != null) {
      setState(() => _outputFolder = path);
    }
  }

  Future<void> _startBatchSeal() async {
    if (_inputFolder == null || _outputFolder == null || _hexKey.length != 64) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _results = [];
      _processedFiles = 0;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final fileService = context.read<FileService>();
      final files = await fileService.listAllFiles(_inputFolder!);
      _totalFiles = files.length;

      final options = SealOptions(compress: _compress);
      const chunkSize = 20;

      for (int i = 0; i < files.length; i += chunkSize) {
        final end = (i + chunkSize < files.length)
            ? i + chunkSize
            : files.length;
        final chunk = files.sublist(i, end);

        final futures = chunk.map((filePath) async {
          final stopwatch = Stopwatch()..start();
          try {
            final sealedBytes = await zegelService.seal(
              filePath,
              _hexKey,
              options,
            );
            final fileName = fileService.getFileName(filePath);
            final outputPath = '$_outputFolder/$fileName.zgl';
            await fileService.saveFileToPath(sealedBytes, outputPath);
            stopwatch.stop();

            return _BatchFileResult(
              filename: fileName,
              success: true,
              message: 'Sealed successfully',
              duration: stopwatch.elapsed,
            );
          } catch (e) {
            stopwatch.stop();
            return _BatchFileResult(
              filename: fileService.getFileName(filePath),
              success: false,
              message: e.toString(),
              duration: stopwatch.elapsed,
            );
          }
        });

        final chunkResults = await Future.wait(futures);

        if (mounted) {
          setState(() {
            _processedFiles += chunk.length;
            _progress = _processedFiles / _totalFiles;
            _results.addAll(chunkResults);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Batch seal error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final successCount = _results.where((r) => r.success).length;
    final failedCount = _results.where((r) => !r.success).length;
    final totalTime = _results.fold<Duration>(
      Duration.zero,
      (sum, r) => sum + r.duration,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Input folder picker
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
                        l10n.batchInputFolder,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_inputFolder != null)
                    Text(_inputFolder!, style: theme.textTheme.bodyMedium)
                  else
                    Text(
                      l10n.noFolderSelected,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _pickInputFolder,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.selectFolderAction),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Output folder picker
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.folder_special,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.batchOutputFolder,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_outputFolder != null)
                    Text(_outputFolder!, style: theme.textTheme.bodyMedium)
                  else
                    Text(
                      l10n.noFolderSelected,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _pickOutputFolder,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.selectFolderAction),
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

          // Options
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.batchOptions,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    title: Text(l10n.compressionLabel),
                    // ignore: deprecated_member_use
                    // ignore: deprecated_member_use
                    value: _compress,
                    onChanged: _isProcessing
                        ? null
                        : (v) => setState(() => _compress = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Progress
          if (_isProcessing) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      // ignore: deprecated_member_use
                      // ignore: deprecated_member_use
                      value: _progress,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_processedFiles / $_totalFiles files processed',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Start button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed:
                  _isProcessing ||
                      _inputFolder == null ||
                      _outputFolder == null ||
                      _hexKey.length != 64
                  ? null
                  : _startBatchSeal,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(
                _isProcessing ? l10n.batchProcessing : l10n.batchStartSeal,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Results table
          if (_results.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.batchResults,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(),
                    ..._results.map((r) => _ResultRow(result: r)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Summary card
            Card(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _SummaryItem(
                      icon: Icons.check_circle,
                      color: Colors.green,
                      label: l10n.batchSealed,
                      // ignore: deprecated_member_use
                      // ignore: deprecated_member_use
                      value: '$successCount',
                    ),
                    _SummaryItem(
                      icon: Icons.error,
                      color: Colors.red,
                      label: l10n.batchFailed,
                      // ignore: deprecated_member_use
                      // ignore: deprecated_member_use
                      value: '$failedCount',
                    ),
                    _SummaryItem(
                      icon: Icons.timer,
                      color: theme.colorScheme.primary,
                      label: l10n.batchTotalTime,
                      // ignore: deprecated_member_use
                      // ignore: deprecated_member_use
                      value: '${totalTime.inMilliseconds}ms',
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
}

/// A single row in the results table.
class _ResultRow extends StatelessWidget {
  final _BatchFileResult result;

  const _ResultRow({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            result.success ? Icons.check_circle : Icons.error,
            color: result.success ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              result.filename,
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${result.duration.inMilliseconds}ms',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// A summary item showing an icon, label, and value.
class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _SummaryItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
