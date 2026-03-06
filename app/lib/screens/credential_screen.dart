import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/zegel_service.dart';
import '../widgets/key_input.dart';

/// Credential/diploma management screen.
///
/// Supports issuing academic credentials sealed in .zgl format
/// and verifying credential attestations without requiring a key.
class CredentialScreen extends StatefulWidget {
  const CredentialScreen({super.key});

  @override
  State<CredentialScreen> createState() => _CredentialScreenState();
}

class _CredentialScreenState extends State<CredentialScreen>
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
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.credentialTitle),
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.onPrimary,
<<<<<<< /tmp/.tmpMuSj9Z/ours
          unselectedLabelColor: theme.colorScheme.onPrimary.withValues(alpha:0.7),
=======
          unselectedLabelColor: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
>>>>>>> /tmp/.tmpMuSj9Z/theirs
          indicatorColor: theme.colorScheme.onPrimary,
          tabs: [
            Tab(text: l10n.credentialIssueTab),
            Tab(text: l10n.credentialVerifyTab),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _CredentialIssueTab(),
          _CredentialVerifyTab(),
        ],
      ),
    );
  }
}

/// Issue tab: select document, enter institution details, issue credential.
class _CredentialIssueTab extends StatefulWidget {
  const _CredentialIssueTab();

  @override
  State<_CredentialIssueTab> createState() => _CredentialIssueTabState();
}

class _CredentialIssueTabState extends State<_CredentialIssueTab> {
  String? _filePath;
  String _hexKey = '';
  final _institutionNameController = TextEditingController();
  final _institutionIdController = TextEditingController();
  final _recipientNameController = TextEditingController();
  final _recipientIdController = TextEditingController();
  String _credentialType = 'diploma';
  bool _isIssuing = false;
  String? _statusMessage;
  bool _isError = false;

  @override
  void dispose() {
    _institutionNameController.dispose();
    _institutionIdController.dispose();
    _recipientNameController.dispose();
    _recipientIdController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickFile();
    if (path != null) {
      setState(() {
        _filePath = path;
        _statusMessage = null;
      });
    }
  }

  Future<void> _issueCredential() async {
    if (_filePath == null ||
        _hexKey.length != 64 ||
        _institutionNameController.text.trim().isEmpty ||
        _recipientNameController.text.trim().isEmpty) {
      setState(() {
        _statusMessage =
            'Please provide file, key, institution, and recipient details.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isIssuing = true;
      _statusMessage = null;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final fileService = context.read<FileService>();
      final credentialBytes = await zegelService.issueCredential(
        _filePath!,
        _hexKey,
        institutionName: _institutionNameController.text.trim(),
        institutionId: _institutionIdController.text.trim(),
        credentialType: _credentialType,
        recipientName: _recipientNameController.text.trim(),
        recipientId: _recipientIdController.text.trim(),
      );
      final fileName = fileService.getFileName(_filePath!);
      final savedPath = await fileService.saveFile(
        credentialBytes,
        '${fileName}_credential.zgl',
      );
      if (savedPath != null && mounted) {
        setState(() {
          _statusMessage = 'Credential issued and saved.';
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
      if (mounted) setState(() => _isIssuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      Icon(Icons.school, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.credentialDocumentLabel,
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
                    onPressed: _isIssuing ? null : _pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.selectFileAction),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Institution details
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.business, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.credentialInstitutionLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _institutionNameController,
                    decoration: InputDecoration(
                      labelText: l10n.credentialInstitutionNameLabel,
                      hintText: l10n.credentialInstitutionNameHint,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _institutionIdController,
                    decoration: InputDecoration(
                      labelText: l10n.credentialInstitutionIdLabel,
                      hintText: l10n.credentialInstitutionIdHint,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Credential type
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.card_membership,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.credentialTypeLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _credentialType,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: l10n.credentialTypeLabel,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'diploma',
                        child: Text(l10n.credentialTypeDiploma),
                      ),
                      DropdownMenuItem(
                        value: 'certificate',
                        child: Text(l10n.credentialTypeCertificate),
                      ),
                      DropdownMenuItem(
                        value: 'license',
                        child: Text(l10n.credentialTypeLicense),
                      ),
                      DropdownMenuItem(
                        value: 'accreditation',
                        child: Text(l10n.credentialTypeAccreditation),
                      ),
                    ],
                    onChanged: _isIssuing
                        ? null
                        : (v) {
                            if (v != null) {
                              setState(() => _credentialType = v);
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Recipient info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.credentialRecipientLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _recipientNameController,
                    decoration: InputDecoration(
                      labelText: l10n.credentialRecipientNameLabel,
                      hintText: l10n.credentialRecipientNameHint,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _recipientIdController,
                    decoration: InputDecoration(
                      labelText: l10n.credentialRecipientIdLabel,
                      hintText: l10n.credentialRecipientIdHint,
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

          // Status message
          if (_statusMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isError
<<<<<<< /tmp/.tmpMuSj9Z/ours
                      ? Colors.red.withValues(alpha:0.1)
                      : Colors.green.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isError
                        ? Colors.red.withValues(alpha:0.3)
                        : Colors.green.withValues(alpha:0.3),
=======
                      ? Colors.red.withValues(alpha: 0.1)
                      : Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isError
                        ? Colors.red.withValues(alpha: 0.3)
                        : Colors.green.withValues(alpha: 0.3),
>>>>>>> /tmp/.tmpMuSj9Z/theirs
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

          // Issue button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isIssuing ? null : _issueCredential,
              icon: _isIssuing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.verified),
              label: Text(
                _isIssuing
                    ? l10n.credentialIssuing
                    : l10n.credentialIssueAction,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Verify tab: public verification of credential attestations.
class _CredentialVerifyTab extends StatefulWidget {
  const _CredentialVerifyTab();

  @override
  State<_CredentialVerifyTab> createState() => _CredentialVerifyTabState();
}

class _CredentialVerifyTabState extends State<_CredentialVerifyTab> {
  String? _filePath;
  bool _isVerifying = false;
  CredentialInfo? _credentialInfo;
  String? _statusMessage;
  bool _isError = false;

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickZegelFile();
    if (path != null) {
      setState(() {
        _filePath = path;
        _credentialInfo = null;
        _statusMessage = null;
      });
    }
  }

  Future<void> _verifyCredential() async {
    if (_filePath == null) {
      setState(() {
        _statusMessage = 'Please select a .zgl credential file.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _statusMessage = null;
      _credentialInfo = null;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final info = await zegelService.verifyCredential(_filePath!);
      if (mounted) {
        setState(() {
          _credentialInfo = info;
          _statusMessage = info.isValid
              ? 'Credential is VALID'
              : 'Credential is INVALID';
          _isError = !info.isValid;
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
                      Icon(Icons.school, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.credentialFileLabel,
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

          // Verify button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isVerifying || _filePath == null
                  ? null
                  : _verifyCredential,
              icon: _isVerifying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.verified),
              label: Text(
                _isVerifying
                    ? l10n.credentialVerifying
                    : l10n.credentialVerifyAction,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Status message
          if (_statusMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _isError
<<<<<<< /tmp/.tmpMuSj9Z/ours
                    ? Colors.red.withValues(alpha:0.1)
                    : Colors.green.withValues(alpha:0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isError
                      ? Colors.red.withValues(alpha:0.3)
                      : Colors.green.withValues(alpha:0.3),
=======
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isError
                      ? Colors.red.withValues(alpha: 0.3)
                      : Colors.green.withValues(alpha: 0.3),
>>>>>>> /tmp/.tmpMuSj9Z/theirs
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
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Credential details
          if (_credentialInfo != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.card_membership,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          l10n.credentialDetailsLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    _CredentialDetailRow(
                      label: l10n.credentialTypeLabel,
                      value: _credentialInfo!.credentialType,
                    ),
                    _CredentialDetailRow(
                      label: l10n.credentialInstitutionNameLabel,
                      value: _credentialInfo!.institutionName,
                    ),
                    _CredentialDetailRow(
                      label: l10n.credentialInstitutionIdLabel,
                      value: _credentialInfo!.institutionId,
                    ),
                    _CredentialDetailRow(
                      label: l10n.credentialRecipientNameLabel,
                      value: _credentialInfo!.recipientName,
                    ),
                    _CredentialDetailRow(
                      label: l10n.credentialRecipientIdLabel,
                      value: _credentialInfo!.recipientId,
                    ),
                    if (_credentialInfo!.issuedAt != null)
                      _CredentialDetailRow(
                        label: l10n.credentialIssuedAtLabel,
                        value: _credentialInfo!.issuedAt.toString(),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          _credentialInfo!.isValid
                              ? Icons.verified
                              : Icons.gpp_bad,
                          color: _credentialInfo!.isValid
                              ? Colors.green
                              : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _credentialInfo!.isValid
                              ? l10n.credentialValidStatus
                              : l10n.credentialInvalidStatus,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _credentialInfo!.isValid
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ],
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

class _CredentialDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _CredentialDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
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
