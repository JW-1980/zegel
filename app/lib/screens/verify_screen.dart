import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/zegel_service.dart';
import '../widgets/key_input.dart';
import '../widgets/status_badge.dart';
import '../widgets/file_info_card.dart';
import '../widgets/attestation_badge.dart';
import '../widgets/audit_trail_view.dart';
import 'extract_screen.dart';

/// Screen for verifying the integrity of a .zgl file.
///
/// Displays a large visual status indicator (intact/tampered/expired),
/// metadata, attestations, audit trail, and provides an extract button.
class VerifyScreen extends StatefulWidget {
  /// Optional initial .zgl file path.
  final String? initialFilePath;

  const VerifyScreen({super.key, this.initialFilePath});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  String? _filePath;
  String _hexKey = '';
  bool _isVerifying = false;
  ZegelResult? _result;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilePath != null) {
      _filePath = widget.initialFilePath;
    }
  }

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickZegelFile();
    if (path != null) {
      setState(() {
        _filePath = path;
        _result = null;
        _errorMessage = null;
      });
    }
  }

  Future<void> _verify() async {
    if (_filePath == null) {
      setState(() => _errorMessage = 'Please select a .zgl file.');
      return;
    }
    if (_hexKey.length != 64) {
      setState(() =>
          _errorMessage = 'Please enter a valid 64-character hex key.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _result = null;
      _errorMessage = null;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final result = await zegelService.verify(_filePath!, _hexKey);

      if (mounted) {
        setState(() {
          _result = result;
          _isVerifying = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _errorMessage = l10n.errorGeneric(e.toString());
          _isVerifying = false;
        });
      }
    }
  }

  void _navigateToExtract() {
    if (_filePath == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExtractScreen(
          initialFilePath: _filePath,
          initialKey: _hexKey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fileService = context.read<FileService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.verifyAction),
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
                          Icons.verified_user,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'File to Verify',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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
                      onPressed: _isVerifying ? null : _pickFile,
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

            // Verify button
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isVerifying ? null : _verify,
                icon: _isVerifying
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.shield),
                label: Text(
                  _isVerifying ? 'Verifying...' : l10n.verifyAction,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Error message
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                    ),
                  ],
                ),
              ),

            // Verification result
            if (_result != null) ...[
              // Large status badge
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: StatusBadge(status: _result!.status),
                ),
              ),

              // File info card (if valid)
              if (_result!.status == ZegelStatus.valid) ...[
                FileInfoCard(
                  filename: _result!.originalFilename,
                  contentType: _result!.contentType,
                  createdAt: _result!.createdAt,
                  blockCount: _result!.blockCount,
                  flags: _result!.flags,
                  publicMetadata: _result!.metadata,
                ),
                const SizedBox(height: 16),
              ],

              // Attestation badges
              if (_result!.attestations != null &&
                  _result!.attestations!.isNotEmpty) ...[
                AttestationBadgeList(attestations: _result!.attestations!),
                const SizedBox(height: 16),
              ],

              // Audit trail
              if (_result!.auditTrail != null &&
                  _result!.auditTrail!.isNotEmpty) ...[
                AuditTrailView(entries: _result!.auditTrail!),
                const SizedBox(height: 16),
              ],

              // Extract button (only if valid)
              if (_result!.status == ZegelStatus.valid) ...[
                SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _navigateToExtract,
                    icon: const Icon(Icons.file_download),
                    label: Text(
                      l10n.extractAction,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
