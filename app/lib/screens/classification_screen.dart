import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/zegel_service.dart';
import '../widgets/classification_badge.dart';

/// Classification management screen.
///
/// Allows viewing, setting, and changing the classification level
/// of a .zgl file. Supports levels from PUBLIC to TOP_SECRET.
class ClassificationScreen extends StatefulWidget {
  const ClassificationScreen({super.key});

  @override
  State<ClassificationScreen> createState() => _ClassificationScreenState();
}

class _ClassificationScreenState extends State<ClassificationScreen> {
  String? _filePath;
  String? _currentClassification;
  String _classifyLevel = 'PUBLIC';
  String _classifyAuthority = '';
  String _classifyCaveat = '';
  String _declassifyLevel = 'PUBLIC';
  String _declassifyAuthority = '';
  final List<int> _redactBlockIndices = [];
  bool _isProcessing = false;
  String? _statusMessage;
  bool _isError = false;
  // ignore: unused_field
  // ignore: unused_field
  // ignore: unused_field
  ZegelInspection? _inspection;

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickZegelFile();
    if (path != null) {
      setState(() {
        _filePath = path;
        _statusMessage = null;
        _isError = false;
      });
      await _loadClassification();
    }
  }

  Future<void> _loadClassification() async {
    if (_filePath == null) return;
    try {
      if (!mounted) return;
      final zegelService = context.read<ZegelService>();
      // ignore: unused_local_variable
      // ignore: unused_local_variable
      final inspection = await zegelService.inspect(_filePath!);
      if (mounted) {
        setState(() {
          _inspection = inspection;
          _currentClassification =
              inspection.publicMetadata?['classification'] as String?;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Failed to load classification: $e';
          _isError = true;
        });
      }
    }
  }

  Future<void> _setClassification() async {
    if (_filePath == null) return;
    setState(() {
      _isProcessing = true;
      _statusMessage = null;
    });

    try {
      if (!mounted) return;
      final zegelService = context.read<ZegelService>();
      await zegelService.classify(
        _filePath!,
        _classifyLevel,
        _classifyAuthority,
        caveat: _classifyCaveat.isNotEmpty ? _classifyCaveat : null,
      );
      if (mounted) {
        setState(() {
          _currentClassification = _classifyLevel;
          _statusMessage = 'Classification set to $_classifyLevel';
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
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _declassify() async {
    if (_filePath == null) return;

    // Confirm declassification
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        // ignore: unused_local_variable
        // ignore: unused_local_variable
        final l10n = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(l10n.classificationDeclassifyWarningTitle),
          content: Text(l10n.classificationDeclassifyWarningBody),
          actions: [
            TextButton(
              onPressed: () => // ignore: use_build_context_synchronously
      Navigator.of(context).pop(false),
              child: Text(l10n.cancelAction),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
              onPressed: () => // ignore: use_build_context_synchronously
      Navigator.of(context).pop(true),
              child: Text(l10n.classificationDeclassifyAction),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = null;
    });

    try {
      if (!mounted) return;
      final zegelService = context.read<ZegelService>();
      await zegelService.declassify(
        _filePath!,
        _declassifyLevel,
        _declassifyAuthority,
        redactBlocks: _redactBlockIndices.isNotEmpty ? _redactBlockIndices : null,
      );
      if (mounted) {
        setState(() {
          _currentClassification = _declassifyLevel;
          _statusMessage = 'Declassified to $_declassifyLevel';
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
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  int _classificationRank(String level) {
    switch (level) {
      case 'PUBLIC':
        return 0;
      case 'INTERNAL':
        return 1;
      case 'CONFIDENTIAL':
        return 2;
      case 'SECRET':
        return 3;
      case 'TOP_SECRET':
        return 4;
      default:
        return 0;
    }
  }

  List<String> _lowerClassifications(String currentLevel) {
    final rank = _classificationRank(currentLevel);
    return ['PUBLIC', 'INTERNAL', 'CONFIDENTIAL', 'SECRET', 'TOP_SECRET']
        .where((level) => _classificationRank(level) < rank)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.classificationTitle),
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
                        Icon(Icons.shield, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          l10n.classificationFileLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_filePath != null) ...[
                      Text(
                        context.read<FileService>().getFileName(_filePath!),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_currentClassification != null)
                        Row(
                          children: [
                            Text(
                              l10n.classificationCurrentLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ClassificationBadge(
                              level: _currentClassification!,
                            ),
                          ],
                        )
                      else
                        Text(
                          l10n.classificationNone,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ] else
                      Text(
                        l10n.noFileSelected,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: Text(l10n.selectFileAction),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Classify section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.security, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          l10n.classificationSetLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _classifyLevel,
                      decoration: InputDecoration(
                        labelText: l10n.classificationLevelLabel,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        'PUBLIC',
                        'INTERNAL',
                        'CONFIDENTIAL',
                        'SECRET',
                        'TOP_SECRET',
                      ]
                          .map((level) => DropdownMenuItem(
                                // ignore: deprecated_member_use
                                // ignore: deprecated_member_use
                                value: level,
                                child: ClassificationBadge(level: level),
                              ))
                          .toList(),
                      onChanged: _isProcessing
                          ? null
                          : (v) {
                              if (v != null) {
                                setState(() => _classifyLevel = v);
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        labelText: l10n.classificationAuthorityLabel,
                        hintText: l10n.classificationAuthorityHint,
                      ),
                      onChanged: (v) =>
                          setState(() => _classifyAuthority = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: InputDecoration(
                        labelText: l10n.classificationCaveatLabel,
                        hintText: l10n.classificationCaveatHint,
                      ),
                      onChanged: (v) =>
                          setState(() => _classifyCaveat = v),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing || _filePath == null
                            ? null
                            : _setClassification,
                        icon: const Icon(Icons.security),
                        label: Text(l10n.classificationSetAction),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Declassify section
            if (_currentClassification != null &&
                _classificationRank(_currentClassification!) > 0)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lock_open,
                              color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          Text(
                            l10n.classificationDeclassifyLabel,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _declassifyLevel,
                        decoration: InputDecoration(
                          labelText: l10n.classificationNewLevelLabel,
                          border: const OutlineInputBorder(),
                        ),
                        items: _lowerClassifications(_currentClassification!)
                            .map((level) => DropdownMenuItem(
                                  // ignore: deprecated_member_use
                                  // ignore: deprecated_member_use
                                  value: level,
                                  child: ClassificationBadge(level: level),
                                ))
                            .toList(),
                        onChanged: _isProcessing
                            ? null
                            : (v) {
                                if (v != null) {
                                  setState(() => _declassifyLevel = v);
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          labelText: l10n.classificationAuthorityLabel,
                          hintText: l10n.classificationDeclassifyAuthorityHint,
                        ),
                        onChanged: (v) =>
                            setState(() => _declassifyAuthority = v),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing || _filePath == null
                              ? null
                              : _declassify,
                          icon: const Icon(Icons.lock_open),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                          ),
                          label: Text(l10n.classificationDeclassifyAction),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Status message
            if (_statusMessage != null)
              Container(
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
          ],
        ),
      ),
    );
  }
}
