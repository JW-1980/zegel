import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/zegel_service.dart';
import '../widgets/key_input.dart';
import '../widgets/status_badge.dart';
import '../widgets/file_info_card.dart';
import '../widgets/attestation_badge.dart';
import '../widgets/audit_trail_view.dart';
import '../widgets/classification_badge.dart';
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
  ZegelInspection? _inspection;
  bool _provenanceExpanded = false;

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
      setState(
          () => _errorMessage = 'Please enter a valid 64-character hex key.');
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

      // Also try to load inspection data for additional display
      ZegelInspection? inspection;
      try {
        inspection = await zegelService.inspect(_filePath!);
      } catch (_) {
        // Inspection is optional; if it fails, we still show verify result.
      }

      if (mounted) {
        setState(() {
          _result = result;
          _inspection = inspection;
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

              // Classification level badge
              if (_result!.metadata != null &&
                  _result!.metadata!.containsKey('classification')) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.security, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          l10n.verifyClassificationLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        ClassificationBadge(
                          level: _result!.metadata!['classification'] as String,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Regulatory hold status
              if (_result!.metadata != null &&
                  _result!.metadata!.containsKey('regulatory_hold_until')) ...[
                Card(
                  color: Colors.amber.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.gavel, color: Colors.amber.shade800),
                        const SizedBox(width: 8),
                        Text(
                          l10n.verifyRegulatoryHold(
                            _result!.metadata!['regulatory_hold_until']
                                .toString(),
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Timestamp authority info
              if (_result!.metadata != null &&
                  _result!.metadata!.containsKey('tsa_url')) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.access_time,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          l10n.verifyTimestampAuthority,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _result!.metadata!['tsa_url'].toString(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // File info card (if valid)
              if (_result!.status == ZegelStatus.valid) ...[
                FileInfoCard(
                  filename: _result!.originalFilename,
                  contentType: _result!.contentType,
                  createdAt: _result!.createdAt,
                  blockCount: _result!.blockCount,
                  flags: _result!.flags,
                  publicMetadata: _result!.metadata,
                  inspection: _inspection,
                ),
                const SizedBox(height: 16),
              ],

              // Attestation policy check
              if (_result!.attestations != null &&
                  _result!.attestations!.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.policy,
                                color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              l10n.verifyAttestationPolicy,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        Row(
                          children: [
                            Icon(
                              _result!.attestations!.every((a) => a.isVerified)
                                  ? Icons.check_circle
                                  : Icons.warning,
                              color: _result!.attestations!
                                      .every((a) => a.isVerified)
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _result!.attestations!.every((a) => a.isVerified)
                                  ? l10n.verifyAllAttestationsValid
                                  : l10n.verifySomeAttestationsInvalid,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _result!.attestations!
                                        .every((a) => a.isVerified)
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_result!.attestations!.where((a) => a.isVerified).length} / ${_result!.attestations!.length} attestations verified',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
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

              // Provenance timeline preview (collapsed, expandable)
              if (_result!.auditTrail != null &&
                  _result!.auditTrail!.isNotEmpty) ...[
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.timeline,
                            color: theme.colorScheme.primary),
                        title: Text(
                          l10n.verifyProvenancePreview,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          '${_result!.auditTrail!.length} events',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        trailing: Icon(
                          _provenanceExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                        onTap: () {
                          setState(
                              () => _provenanceExpanded = !_provenanceExpanded);
                        },
                      ),
                      if (_provenanceExpanded)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: AuditTrailView(entries: _result!.auditTrail!),
                        ),
                    ],
                  ),
                ),
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
