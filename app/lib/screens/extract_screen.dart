import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/zegel_service.dart';
import '../widgets/key_input.dart';

/// Screen for extracting the original file from a .zgl container.
///
/// Allows selecting a .zgl file, entering the master key,
/// and saving the extracted original file.
class ExtractScreen extends StatefulWidget {
  /// Optional initial .zgl file path.
  final String? initialFilePath;

  /// Optional initial key value.
  final String? initialKey;

  const ExtractScreen({
    super.key,
    this.initialFilePath,
    this.initialKey,
  });

  @override
  State<ExtractScreen> createState() => _ExtractScreenState();
}

class _ExtractScreenState extends State<ExtractScreen> {
  String? _filePath;
  String _hexKey = '';
  bool _isExtracting = false;
  String? _statusMessage;
  bool _isError = false;
  ZegelInspection? _inspection;

  @override
  void initState() {
    super.initState();
    _filePath = widget.initialFilePath;
    _hexKey = widget.initialKey ?? '';
    if (_filePath != null) {
      _inspectFile();
    }
  }

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickZegelFile();
    if (path != null) {
      setState(() {
        _filePath = path;
        _statusMessage = null;
        _isError = false;
        _inspection = null;
      });
      await _inspectFile();
    }
  }

  Future<void> _inspectFile() async {
    if (_filePath == null) return;

    try {
      final zegelService = context.read<ZegelService>();
      final inspection = await zegelService.inspect(_filePath!);
      if (mounted) {
        setState(() => _inspection = inspection);
      }
    } catch (e) {
      // Inspection failure is non-critical; user can still try extraction
    }
  }

  Future<void> _extract() async {
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
      _isExtracting = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final fileService = context.read<FileService>();

      // Use a temp path then show save dialog
      final suggestedName =
          _inspection?.originalFilename ?? 'extracted_file';

      // First verify and extract to bytes via the zegel service
      final result = await zegelService.verify(_filePath!, _hexKey);

      if (result.status == ZegelStatus.tampered) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          setState(() {
            _statusMessage = l10n.verifyTampered;
            _isError = true;
          });
        }
        return;
      }

      if (result.status == ZegelStatus.expired) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          setState(() {
            _statusMessage = l10n.verifyExpired;
            _isError = true;
          });
        }
        return;
      }

      // The actual extraction would write the file
      final success = await zegelService.extract(
        _filePath!,
        _hexKey,
        suggestedName,
      );

      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _statusMessage = l10n.extractSuccess;
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
        setState(() => _isExtracting = false);
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
        title: Text(l10n.extractAction),
      ),
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
                        Icon(
                          Icons.file_download,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'File to Extract',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_filePath != null) ...[
                      Text(
                        l10n.fileSelected(fileService.getFileName(_filePath!)),
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (_inspection != null) ...[
                        const SizedBox(height: 8),
                        _ExtractionDetail(
                          label: 'Original Filename',
                          value: _inspection!.originalFilename,
                        ),
                        _ExtractionDetail(
                          label: 'Content Type',
                          value: _inspection!.contentType,
                        ),
                        _ExtractionDetail(
                          label: 'Block Count',
                          value: _inspection!.blockCount.toString(),
                        ),
                        _ExtractionDetail(
                          label: 'Format Version',
                          value:
                              '${_inspection!.versionMajor}.${_inspection!.versionMinor}',
                        ),
                      ],
                    ] else
                      Text(
                        l10n.noFileSelected,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _isExtracting ? null : _pickFile,
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
                  initialKey: widget.initialKey,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Status message
            if (_statusMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
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

            // Extract button
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isExtracting ? null : _extract,
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
                  _isExtracting ? 'Extracting...' : l10n.extractAction,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExtractionDetail extends StatelessWidget {
  final String label;
  final String value;

  const _ExtractionDetail({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
