import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:zegel/zegel.dart';

import '../services/file_service.dart';
import '../services/zegel_service.dart';
import '../widgets/key_input.dart';

/// Screen for adding attestations to sealed .zgl files.
///
/// Supports role-based attestations (owner, signer, witness, notary, auditor,
/// reviewer) and displays existing attestations on the file.
class AttestScreen extends StatefulWidget {
  /// Optional initial file path (from navigation).
  final String? initialFilePath;

  const AttestScreen({super.key, this.initialFilePath});

  @override
  State<AttestScreen> createState() => _AttestScreenState();
}

class _AttestScreenState extends State<AttestScreen> {
  String? _filePath;
  String _signerKey = '';
  String _signerId = '';
  String _statement = '';
  String _selectedRole = ZegelFormat.roleSigner;
  bool _isLoading = false;
  bool _isAttesting = false;
  String? _statusMessage;
  bool _isError = false;
  List<ZegelAttestation>? _existingAttestations;

  final TextEditingController _signerIdController = TextEditingController();
  final TextEditingController _statementController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialFilePath != null) {
      _setFile(widget.initialFilePath!);
    }
  }

  @override
  void dispose() {
    _signerIdController.dispose();
    _statementController.dispose();
    super.dispose();
  }

  Future<void> _setFile(String path) async {
    setState(() {
      _filePath = path;
      _statusMessage = null;
      _isError = false;
      _existingAttestations = null;
    });
  }

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickZegelFile();
    if (path != null) {
      await _setFile(path);
    }
  }

  Future<void> _loadExistingAttestations() async {
    if (_filePath == null || _signerKey.length != 64) return;

    setState(() {
      _isLoading = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final result = await zegelService.verify(_filePath!, _signerKey);

      setState(() {
        _existingAttestations = result.attestations ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Failed to load attestations: $e';
          _isError = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addAttestation() async {
    if (_filePath == null) {
      setState(() {
        _statusMessage = 'Please select a .zgl file.';
        _isError = true;
      });
      return;
    }

    if (_signerKey.length != 64) {
      setState(() {
        _statusMessage = 'Please enter a valid 64-character hex signer key.';
        _isError = true;
      });
      return;
    }

    if (_signerId.trim().isEmpty) {
      setState(() {
        _statusMessage = 'Please enter a signer ID.';
        _isError = true;
      });
      return;
    }

    if (_statement.trim().isEmpty) {
      setState(() {
        _statusMessage = 'Please enter an attestation statement.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isAttesting = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final fileService = context.read<FileService>();

      // Create the attestation using the zegel library
      final sealedBytes = await zegelService.createAttestation(
        _filePath!,
        _signerKey,
        _signerId.trim(),
        _statement.trim(),
      );

      // Save the updated file
      final fileName = fileService.getFileName(_filePath!);
      final savedPath = await fileService.saveFile(sealedBytes, fileName);

      if (savedPath != null && mounted) {
        setState(() {
          _statusMessage = 'Attestation added successfully!';
          _isError = false;
          _signerIdController.clear();
          _statementController.clear();
          _signerId = '';
          _statement = '';
        });

        // Reload attestations
        await _loadExistingAttestations();
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
        setState(() => _isAttesting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fileService = context.read<FileService>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.attestAction)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Help text
            Card(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Add cryptographic attestations to sealed files. '
                        'Attestations allow third parties to co-sign and '
                        'verify document integrity.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // File selection card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.description,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'File to Attest',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_filePath != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.verified_user,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                fileService.getFileName(_filePath!),
                                style: theme.textTheme.bodyMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
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
                      onPressed: _isAttesting ? null : _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: Text(l10n.selectFileAction),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Signer key input
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.key, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Signer Key',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    KeyInput(
                      onKeyChanged: (key) {
                        setState(() => _signerKey = key);
                        if (key.length == 64 && _filePath != null) {
                          _loadExistingAttestations();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Attestation details
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.approval, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'New Attestation',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _signerIdController,
                      decoration: const InputDecoration(
                        labelText: 'Signer ID',
                        hintText: 'e.g. user:42:reviewer@example.com',
                        prefixIcon: Icon(Icons.person),
                      ),
                      onChanged: (v) => setState(() => _signerId = v),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      // ignore: deprecated_member_use
                      initialValue: _selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'Role',
                        prefixIcon: Icon(Icons.badge),
                      ),
                      items: Attestation.validRoles.map((role) {
                        return DropdownMenuItem(
                          value: role,
                          child: Row(
                            children: [
                              Icon(_roleIcon(role), size: 18),
                              const SizedBox(width: 8),
                              Text(_roleDisplayName(role)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: _isAttesting
                          ? null
                          : (v) => setState(() => _selectedRole = v!),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _statementController,
                      decoration: const InputDecoration(
                        labelText: 'Statement',
                        hintText: 'e.g. Reviewed and approved',
                        prefixIcon: Icon(Icons.edit_note),
                      ),
                      maxLines: 2,
                      onChanged: (v) => setState(() => _statement = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Existing attestations
            if (_isLoading)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_existingAttestations != null &&
                _existingAttestations!.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.history, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Existing Attestations',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Chip(
                            label: Text('${_existingAttestations!.length}'),
                            backgroundColor: theme.colorScheme.primaryContainer,
                          ),
                        ],
                      ),
                      const Divider(),
                      ..._existingAttestations!.map((attestation) {
                        return _AttestationCard(attestation: attestation);
                      }),
                    ],
                  ),
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

            // Add attestation button
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isAttesting ? null : _addAttestation,
                icon: _isAttesting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.approval),
                label: Text(
                  _isAttesting ? 'Adding Attestation...' : l10n.attestAction,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'owner':
        return Icons.person;
      case 'signer':
        return Icons.edit;
      case 'witness':
        return Icons.visibility;
      case 'notary':
        return Icons.gavel;
      case 'auditor':
        return Icons.fact_check;
      case 'reviewer':
        return Icons.rate_review;
      default:
        return Icons.badge;
    }
  }

  String _roleDisplayName(String role) {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'signer':
        return 'Signer';
      case 'witness':
        return 'Witness';
      case 'notary':
        return 'Notary';
      case 'auditor':
        return 'Auditor';
      case 'reviewer':
        return 'Reviewer';
      default:
        return role;
    }
  }
}

/// Card displaying a single attestation.
class _AttestationCard extends StatelessWidget {
  final ZegelAttestation attestation;

  const _AttestationCard({required this.attestation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormatter = DateFormat('yyyy-MM-dd HH:mm');
    final isVerified = attestation.isVerified;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isVerified
            ? Colors.green.withValues(alpha: 0.05)
            : Colors.red.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isVerified
              ? Colors.green.withValues(alpha: 0.2)
              : Colors.red.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isVerified ? Icons.verified : Icons.warning,
                color: isVerified ? Colors.green : Colors.red,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  attestation.signerId,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            attestation.statement,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dateFormatter.format(attestation.timestamp),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}
