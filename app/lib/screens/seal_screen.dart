import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/zegel_service.dart';
import '../widgets/key_input.dart';

/// Screen for sealing a file into the Zegel .zgl format.
///
/// Shows file info, key input, optional metadata, advanced options,
/// and a seal button that creates the .zgl output file.
class SealScreen extends StatefulWidget {
  /// Optional initial file path (from drag-and-drop or file picker).
  final String? initialFilePath;

  const SealScreen({super.key, this.initialFilePath});

  @override
  State<SealScreen> createState() => _SealScreenState();
}

class _SealScreenState extends State<SealScreen> {
  String? _filePath;
  String _hexKey = '';
  bool _isSealing = false;
  String? _statusMessage;
  bool _isError = false;

  // Advanced options
  bool _showAdvanced = false;
  bool _compress = false;
  DateTime? _expirationDate;
  String _recipientId = '';
  bool _enableSelectiveDisclosure = false;
  int _splitKeyThreshold = 0;
  int _splitKeyTotal = 0;

  // New advanced options
  bool _anonymousMode = false;
  String _classificationLevel = '';
  DateTime? _regulatoryHoldDate;
  bool _preserveMediaMetadata = false;

  // Metadata key-value pairs
  final List<_MetadataEntry> _metadataEntries = [];

  int? _fileSize;
  String? _fileName;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilePath != null) {
      _setFile(widget.initialFilePath!);
    }
  }

  Future<void> _setFile(String path) async {
    final fileService = context.read<FileService>();
    final size = await fileService.getFileSize(path);
    final name = fileService.getFileName(path);

    setState(() {
      _filePath = path;
      _fileSize = size;
      _fileName = name;
      _statusMessage = null;
      _isError = false;
    });
  }

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickFile();
    if (path != null) {
      await _setFile(path);
    }
  }

  Future<void> _pickExpirationDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expirationDate ?? now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 100)),
    );
    if (picked != null) {
      setState(() => _expirationDate = picked);
    }
  }

  void _addMetadataEntry() {
    setState(() {
      _metadataEntries.add(_MetadataEntry());
    });
  }

  void _removeMetadataEntry(int index) {
    setState(() {
      _metadataEntries.removeAt(index);
    });
  }

  Future<void> _seal() async {
    if (_filePath == null) {
      setState(() {
        _statusMessage = 'Please select a file to seal.';
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
      _isSealing = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final fileService = context.read<FileService>();

      // Build metadata map
      Map<String, dynamic>? metadata;
      if (_metadataEntries.isNotEmpty) {
        metadata = {};
        for (final entry in _metadataEntries) {
          if (entry.key.isNotEmpty && entry.value.isNotEmpty) {
            metadata[entry.key] = entry.value;
          }
        }
        if (metadata.isEmpty) metadata = null;
      }

      final options = SealOptions(
        compress: _compress,
        expirationDate: _expirationDate,
        recipientId: _recipientId.isNotEmpty ? _recipientId : null,
        splitKeyThreshold: _splitKeyThreshold > 0 ? _splitKeyThreshold : null,
        splitKeyTotal: _splitKeyTotal > 0 ? _splitKeyTotal : null,
        enableSelectiveDisclosure: _enableSelectiveDisclosure,
        metadata: metadata,
      );

      final sealedBytes = await zegelService.seal(_filePath!, _hexKey, options);

      final suggestedName = '${_fileName ?? 'output'}.zgl';
      final savedPath = await fileService.saveFile(sealedBytes, suggestedName);

      if (savedPath != null && mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _statusMessage = l10n.sealSuccess;
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
        setState(() => _isSealing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fileService = context.read<FileService>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sealAction)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // File selection drop zone (Brutalist style)
            InkWell(
              onTap: _isSealing ? null : _pickFile,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 48,
                  horizontal: 24,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.4),
                    style: BorderStyle.solid,
                    width: 2,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.upload_file,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _filePath != null
                          ? _fileName ?? ''
                          : 'DROP .ZGL OR ASSET FILE HERE',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: theme.colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    if (_filePath == null)
                      Text(
                        'Accepts .doc, .pdf, .zip, .encrypted',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (_filePath != null && _fileSize != null)
                      Text(
                        fileService.formatFileSize(_fileSize!),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.bold,
                        ),
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

            // Metadata entries (Brutalist style)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'METADATA PAIRS',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('ADD PAIR'),
                        onPressed: _isSealing ? null : _addMetadataEntry,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_metadataEntries.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ..._metadataEntries.asMap().entries.map((entry) {
                      final index = entry.key;
                      final meta = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                decoration: InputDecoration(
                                  labelText: 'Key',
                                  isDense: true,
                                  filled: true,
                                  fillColor:
                                      theme.colorScheme.surfaceContainerLow,
                                ),
                                onChanged: (v) => meta.key = v,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                decoration: InputDecoration(
                                  labelText: 'Value',
                                  isDense: true,
                                  filled: true,
                                  fillColor:
                                      theme.colorScheme.surfaceContainerLow,
                                ),
                                onChanged: (v) => meta.value = v,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              color: theme.colorScheme.error,
                              onPressed: () => _removeMetadataEntry(index),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Advanced options
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.tune, color: theme.colorScheme.primary),
                    title: Text(
                      'Advanced Options',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    trailing: Icon(
                      _showAdvanced ? Icons.expand_less : Icons.expand_more,
                    ),
                    onTap: () {
                      setState(() => _showAdvanced = !_showAdvanced);
                    },
                  ),
                  if (_showAdvanced)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        children: [
                          const Divider(),
                          SwitchListTile(
                            title: Text(l10n.compressionLabel),
                            subtitle: const Text(
                              'zlib compression before encryption',
                            ),
                            value: _compress,
                            onChanged: _isSealing
                                ? null
                                : (v) => setState(() => _compress = v),
                          ),
                          ListTile(
                            title: Text(l10n.expirationLabel),
                            subtitle: Text(
                              _expirationDate != null
                                  ? '${_expirationDate!.year}-${_expirationDate!.month.toString().padLeft(2, '0')}-${_expirationDate!.day.toString().padLeft(2, '0')}'
                                  : 'Not set',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_expirationDate != null)
                                  IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      setState(() => _expirationDate = null);
                                    },
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.calendar_today),
                                  onPressed:
                                      _isSealing ? null : _pickExpirationDate,
                                ),
                              ],
                            ),
                          ),
                          TextField(
                            decoration: InputDecoration(
                              labelText: l10n.recipientLabel,
                              hintText: '64-character hex recipient ID',
                            ),
                            onChanged: (v) => setState(() => _recipientId = v),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  decoration: InputDecoration(
                                    labelText: l10n.thresholdLabel,
                                    hintText: 'e.g. 3',
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => setState(
                                    () => _splitKeyThreshold =
                                        int.tryParse(v) ?? 0,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  decoration: InputDecoration(
                                    labelText: l10n.totalSharesLabel,
                                    hintText: 'e.g. 5',
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) => setState(
                                    () => _splitKeyTotal = int.tryParse(v) ?? 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            title: const Text('Enable Selective Disclosure'),
                            subtitle: const Text(
                              'Allow generating per-block access tokens',
                            ),
                            value: _enableSelectiveDisclosure,
                            onChanged: _isSealing
                                ? null
                                : (v) => setState(
                                      () => _enableSelectiveDisclosure = v,
                                    ),
                          ),
                          const Divider(),
                          SwitchListTile(
                            title: Text(l10n.sealAnonymousMode),
                            subtitle: Text(l10n.sealAnonymousModeDesc),
                            value: _anonymousMode,
                            onChanged: _isSealing
                                ? null
                                : (v) => setState(() => _anonymousMode = v),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: _classificationLevel.isEmpty
                                ? null
                                : _classificationLevel,
                            decoration: InputDecoration(
                              labelText: l10n.sealClassificationLevel,
                              border: const OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'PUBLIC',
                                child: Text('PUBLIC'),
                              ),
                              DropdownMenuItem(
                                value: 'INTERNAL',
                                child: Text('INTERNAL'),
                              ),
                              DropdownMenuItem(
                                value: 'CONFIDENTIAL',
                                child: Text('CONFIDENTIAL'),
                              ),
                              DropdownMenuItem(
                                value: 'SECRET',
                                child: Text('SECRET'),
                              ),
                              DropdownMenuItem(
                                value: 'TOP_SECRET',
                                child: Text('TOP SECRET'),
                              ),
                            ],
                            onChanged: _isSealing
                                ? null
                                : (v) => setState(
                                      () => _classificationLevel = v ?? '',
                                    ),
                          ),
                          if (_classificationLevel.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            TextField(
                              decoration: InputDecoration(
                                labelText: l10n.sealClassificationAuthority,
                                hintText: l10n.sealClassificationAuthorityHint,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          ListTile(
                            title: Text(l10n.sealRegulatoryHold),
                            subtitle: Text(
                              _regulatoryHoldDate != null
                                  ? '${_regulatoryHoldDate!.year}-${_regulatoryHoldDate!.month.toString().padLeft(2, '0')}-${_regulatoryHoldDate!.day.toString().padLeft(2, '0')}'
                                  : l10n.sealNotSet,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_regulatoryHoldDate != null)
                                  IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () => setState(
                                      () => _regulatoryHoldDate = null,
                                    ),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.calendar_today),
                                  onPressed: _isSealing
                                      ? null
                                      : () async {
                                          final now = DateTime.now();
                                          final picked = await showDatePicker(
                                            context: context,
                                            initialDate: _regulatoryHoldDate ??
                                                now.add(
                                                  const Duration(days: 365 * 7),
                                                ),
                                            firstDate: now,
                                            lastDate: now.add(
                                              const Duration(days: 365 * 100),
                                            ),
                                          );
                                          if (picked != null) {
                                            setState(
                                              () =>
                                                  _regulatoryHoldDate = picked,
                                            );
                                          }
                                        },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            decoration: InputDecoration(
                              labelText: l10n.sealTsaUrl,
                              hintText: l10n.sealTsaUrlHint,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            title: Text(l10n.sealPreserveMediaMetadata),
                            subtitle: Text(l10n.sealPreserveMediaMetadataDesc),
                            value: _preserveMediaMetadata,
                            onChanged: _isSealing
                                ? null
                                : (v) => setState(
                                      () => _preserveMediaMetadata = v,
                                    ),
                          ),
                        ],
                      ),
                    ),
                ],
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
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
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

            // Seal button
            SizedBox(
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _isSealing ? null : _seal,
                icon: _isSealing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.lock, size: 28),
                label: Text(
                  _isSealing ? 'SEALING...' : 'SEAL CONTAINER',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
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

/// Helper class for mutable metadata key-value pairs.
class _MetadataEntry {
  String key = '';
  String value = '';
}

/// A row showing a file detail (icon + label + value).
// ignore: unused_element
class _FileDetail extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _FileDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
