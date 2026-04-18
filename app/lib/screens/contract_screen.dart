import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/zegel_service.dart';
import '../widgets/key_input.dart';
import '../widgets/party_manager.dart';
import '../widgets/workflow_stepper.dart';

/// Contract workflow screen for multi-party document signing.
///
/// Supports use cases like house purchase contracts where multiple parties
/// (buyer, seller, notary, bank, agent) need to attest to a document.
class ContractScreen extends StatefulWidget {
  const ContractScreen({super.key});

  @override
  State<ContractScreen> createState() => _ContractScreenState();
}

class _ContractScreenState extends State<ContractScreen> {
  String? _filePath;
  String _ownerKeyHex = '';
  final List<ContractParty> _parties = [];
  bool _isProcessing = false;
  String? _statusMessage;
  bool _isError = false;

  // Split key configuration
  int _splitKeyThreshold = 2;
  int _splitKeyTotal = 3;
  bool _enableSplitKey = false;

  // Workflow state
  int _currentStep = 0;
  final List<WorkflowStep> _workflowSteps = [];

  @override
  void initState() {
    super.initState();
    _initWorkflowSteps();
  }

  void _initWorkflowSteps() {
    _workflowSteps.clear();
    _workflowSteps.addAll([
      const WorkflowStep(
        title: 'Seal Contract',
        description: 'Owner seals the contract document',
        status: WorkflowStepStatus.pending,
      ),
      const WorkflowStep(
        title: 'Distribute to Parties',
        description: 'Distribute with canary traps per recipient',
        status: WorkflowStepStatus.pending,
      ),
      const WorkflowStep(
        title: 'Collect Attestations',
        description: 'Each party reviews and attests',
        status: WorkflowStepStatus.pending,
      ),
      const WorkflowStep(
        title: 'Check Attestation Policy',
        description: 'Verify all required roles have attested',
        status: WorkflowStepStatus.pending,
      ),
      const WorkflowStep(
        title: 'Extract for Closing',
        description: 'Extract original document for final closing',
        status: WorkflowStepStatus.pending,
      ),
    ]);
  }

  Future<void> _pickFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickFile();
    if (path != null) {
      setState(() {
        _filePath = path;
        _statusMessage = null;
        _currentStep = 0;
        _initWorkflowSteps();
      });
    }
  }

  void _addParty(ContractParty party) {
    setState(() => _parties.add(party));
  }

  void _removeParty(int index) {
    setState(() => _parties.removeAt(index));
  }

  void _updateParty(int index, ContractParty party) {
    setState(() => _parties[index] = party);
  }

  Future<void> _sealContract() async {
    if (_filePath == null || _ownerKeyHex.length != 64) {
      setState(() {
        _statusMessage = 'Please select a file and enter the owner key.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = null;
      _workflowSteps[0] = _workflowSteps[0].copyWith(
        status: WorkflowStepStatus.inProgress,
      );
    });

    try {
      final zegelService = context.read<ZegelService>();
      final fileService = context.read<FileService>();

      // Build metadata with party information
      final metadata = <String, dynamic>{
        'document_type': 'contract',
        'parties':
            _parties.map((p) => {'name': p.name, 'role': p.role}).toList(),
      };

      final options = SealOptions(
        compress: true,
        enableSelectiveDisclosure: true,
        metadata: metadata,
        splitKeyThreshold: _enableSplitKey ? _splitKeyThreshold : null,
        splitKeyTotal: _enableSplitKey ? _splitKeyTotal : null,
      );

      // Add canary traps for each party
      for (final party in _parties) {
        if (party.keyHex.isNotEmpty) {
          final recipientOptions = SealOptions(
            compress: options.compress,
            enableSelectiveDisclosure: options.enableSelectiveDisclosure,
            metadata: metadata,
            recipientId: party.keyHex.isNotEmpty
                ? party.keyHex.substring(0, 64.clamp(0, party.keyHex.length))
                : null,
          );
          // Each party gets a canary-trapped copy
          await zegelService.seal(_filePath!, _ownerKeyHex, recipientOptions);
        }
      }

      // Create the master sealed copy
      final sealedBytes = await zegelService.seal(
        _filePath!,
        _ownerKeyHex,
        options,
      );
      final fileName = fileService.getFileName(_filePath!);
      await fileService.saveFile(sealedBytes, '${fileName}_contract.zgl');

      if (mounted) {
        setState(() {
          _workflowSteps[0] = _workflowSteps[0].copyWith(
            status: WorkflowStepStatus.completed,
          );
          _workflowSteps[1] = _workflowSteps[1].copyWith(
            status: WorkflowStepStatus.inProgress,
          );
          _currentStep = 1;
          _statusMessage = 'Contract sealed successfully.';
          _isError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _workflowSteps[0] = _workflowSteps[0].copyWith(
            status: WorkflowStepStatus.failed,
          );
          _statusMessage = 'Error sealing contract: $e';
          _isError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _verifyAllAttestations() async {
    if (_filePath == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = null;
      _workflowSteps[3] = _workflowSteps[3].copyWith(
        status: WorkflowStepStatus.inProgress,
      );
    });

    try {
      final zegelService = context.read<ZegelService>();
      final result = await zegelService.verify(
        _filePath!.replaceAll(RegExp(r'\.[^.]+$'), '_contract.zgl'),
        _ownerKeyHex,
      );

      if (result.attestations != null && result.attestations!.isNotEmpty) {
        // Check if all required roles have attested
        final attestedRoles =
            result.attestations!.map((a) => a.signerId).toSet();
        final requiredRoles = _parties.map((p) => p.name).toSet();
        final allAttested = requiredRoles.every(attestedRoles.contains);

        if (mounted) {
          setState(() {
            _workflowSteps[3] = _workflowSteps[3].copyWith(
              status: allAttested
                  ? WorkflowStepStatus.completed
                  : WorkflowStepStatus.failed,
            );
            if (allAttested) {
              _workflowSteps[4] = _workflowSteps[4].copyWith(
                status: WorkflowStepStatus.pending,
              );
              _currentStep = 4;
            }
            _statusMessage = allAttested
                ? 'All parties have attested. Ready for closing.'
                : 'Not all required parties have attested yet.';
            _isError = !allAttested;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _workflowSteps[3] = _workflowSteps[3].copyWith(
              status: WorkflowStepStatus.failed,
            );
            _statusMessage = 'No attestations found.';
            _isError = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _workflowSteps[3] = _workflowSteps[3].copyWith(
            status: WorkflowStepStatus.failed,
          );
          _statusMessage = 'Error verifying attestations: $e';
          _isError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.contractTitle)),
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
                          Icons.description,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.contractDocumentLabel,
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
                      onPressed: _isProcessing ? null : _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: Text(l10n.selectFileAction),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Owner key input
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.contractOwnerKeyLabel,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    KeyInput(
                      onKeyChanged: (key) => setState(() => _ownerKeyHex = key),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Party management
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PartyManager(
                  parties: _parties,
                  onAddParty: _addParty,
                  onRemoveParty: _removeParty,
                  onUpdateParty: _updateParty,
                  enabled: !_isProcessing,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Split key configuration
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
                          l10n.contractSplitKeyLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      title: Text(l10n.contractEnableSplitKey),
                      // ignore: deprecated_member_use
                      // ignore: deprecated_member_use
                      value: _enableSplitKey,
                      onChanged: _isProcessing
                          ? null
                          : (v) => setState(() => _enableSplitKey = v),
                    ),
                    if (_enableSplitKey) ...[
                      const SizedBox(height: 8),
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
                                () => _splitKeyThreshold = int.tryParse(v) ?? 2,
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
                                () => _splitKeyTotal = int.tryParse(v) ?? 3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Workflow stepper
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.checklist, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          l10n.contractWorkflowLabel,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    WorkflowStepperWidget(
                      steps: _workflowSteps,
                      currentStep: _currentStep,
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

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ||
                              _filePath == null ||
                              _ownerKeyHex.length != 64
                          ? null
                          : _sealContract,
                      icon: const Icon(Icons.lock),
                      label: Text(l10n.contractSealAction),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _verifyAllAttestations,
                      icon: const Icon(Icons.verified_user),
                      label: Text(l10n.contractVerifyAttestations),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
