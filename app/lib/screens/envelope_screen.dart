import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zegel/zegel.dart';

/// Screen for creating and managing signing envelopes (DocuSign-style).
///
/// Allows the user to:
/// - Create a new envelope from scratch or from a template
/// - Add recipients with roles and routing order
/// - Choose routing mode (sequential / parallel / mixed)
/// - Configure authentication requirements per recipient
/// - Set expiration and reminder settings
/// - View the audit trail for any envelope
class EnvelopeScreen extends StatefulWidget {
  /// Optional envelope to load for editing.
  final Envelope? initialEnvelope;

  const EnvelopeScreen({super.key, this.initialEnvelope});

  @override
  State<EnvelopeScreen> createState() => _EnvelopeScreenState();
}

class _EnvelopeScreenState extends State<EnvelopeScreen> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  final _senderNameController = TextEditingController();
  final _senderEmailController = TextEditingController();
  RoutingMode _routingMode = RoutingMode.sequential;
  final List<_RecipientDraft> _recipients = <_RecipientDraft>[];
  bool _remindersEnabled = false;
  int _reminderIntervalDays = 3;
  int _reminderMaxCount = 3;
  int? _expirationDays;

  Envelope? _createdEnvelope;

  @override
  void initState() {
    super.initState();
    if (widget.initialEnvelope != null) {
      _loadEnvelope(widget.initialEnvelope!);
    } else {
      // Start with one empty recipient.
      _recipients.add(_RecipientDraft());
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    _senderNameController.dispose();
    _senderEmailController.dispose();
    for (final r in _recipients) {
      r.dispose();
    }
    super.dispose();
  }

  void _loadEnvelope(Envelope envelope) {
    _subjectController.text = envelope.subject;
    _messageController.text = envelope.message ?? '';
    _senderNameController.text = envelope.senderName ?? '';
    _senderEmailController.text = envelope.senderEmail ?? '';
    _routingMode = envelope.routingMode;
    _remindersEnabled = envelope.remindersEnabled;
    _reminderIntervalDays = envelope.reminderIntervalDays;
    _reminderMaxCount = envelope.reminderMaxCount;
    for (final r in envelope.recipients) {
      final draft = _RecipientDraft();
      draft.nameController.text = r.name;
      draft.emailController.text = r.email;
      draft.role = r.role;
      draft.routingOrder = r.routingOrder;
      draft.authentication = r.authentication;
      _recipients.add(draft);
    }
  }

  void _addRecipient() {
    setState(() {
      final draft = _RecipientDraft();
      draft.routingOrder = _recipients.length + 1;
      _recipients.add(draft);
    });
  }

  void _removeRecipient(int index) {
    setState(() {
      _recipients[index].dispose();
      _recipients.removeAt(index);
    });
  }

  Future<void> _createEnvelope() async {
    // Validate inputs.
    if (_subjectController.text.trim().isEmpty) {
      _showError('Subject is required');
      return;
    }
    if (_recipients.isEmpty) {
      _showError('At least one recipient is required');
      return;
    }
    for (final r in _recipients) {
      if (r.nameController.text.trim().isEmpty ||
          r.emailController.text.trim().isEmpty) {
        _showError('All recipients must have a name and email');
        return;
      }
    }

    // Build envelope.
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final expiresAt =
        _expirationDays != null ? now + _expirationDays! * 86400 : null;

    final envelopeRecipients = <EnvelopeRecipient>[];
    for (var i = 0; i < _recipients.length; i++) {
      final draft = _recipients[i];
      envelopeRecipients.add(
        EnvelopeRecipient(
          id: 'rcpt-${i + 1}',
          name: draft.nameController.text.trim(),
          email: draft.emailController.text.trim(),
          role: draft.role,
          routingOrder: draft.routingOrder,
          authentication: draft.authentication,
        ),
      );
    }

    final envelope = Envelope(
      id: 'env-${DateTime.now().millisecondsSinceEpoch}',
      subject: _subjectController.text.trim(),
      message: _messageController.text.trim().isEmpty
          ? null
          : _messageController.text.trim(),
      senderName: _senderNameController.text.trim().isEmpty
          ? null
          : _senderNameController.text.trim(),
      senderEmail: _senderEmailController.text.trim().isEmpty
          ? null
          : _senderEmailController.text.trim(),
      routingMode: _routingMode,
      recipients: envelopeRecipients,
      createdAt: now,
      expiresAt: expiresAt,
      remindersEnabled: _remindersEnabled,
      reminderIntervalDays: _reminderIntervalDays,
      reminderMaxCount: _reminderMaxCount,
    );

    // Add creation event to audit trail.
    envelope.appendEvent(
      EnvelopeEvent(
        timestamp: now,
        eventType: 'envelope_created',
        description: 'Envelope created with ${envelope.recipients.length} '
            'recipient(s), routing: ${_routingMode.name}',
      ),
    );

    // Save envelope to a JSON file so it persists across sessions.
    try {
      final encoded = envelope.encode();
      final homeDir = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '.';
      final outputPath = '$homeDir/zegel-envelope-${envelope.id}.json';
      await File(outputPath).writeAsBytes(encoded);

      setState(() {
        _createdEnvelope = envelope;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Envelope saved to ${outputPath.split('/').last} '
              '(${envelope.recipients.length} recipients)',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      _showError('Failed to save envelope: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showHelpSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'How Signing Envelopes Work',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              const _HelpStep(
                number: '1',
                title: 'Add Recipients',
                description:
                    'Add the people who need to sign. Set each person\'s '
                    'role (signer, approver, witness) and authentication method.',
              ),
              const _HelpStep(
                number: '2',
                title: 'Choose Routing',
                description:
                    'Sequential: each person signs in order. '
                    'Parallel: everyone signs at the same time. '
                    'Mixed: groups sign in sequence, within groups in parallel.',
              ),
              const _HelpStep(
                number: '3',
                title: 'Send the Envelope',
                description:
                    'The envelope is sealed with Zegel\'s tamper-proof '
                    'format. Any modification after sending is detected.',
              ),
              const _HelpStep(
                number: '4',
                title: 'Collect Signatures',
                description:
                    'Each recipient uses the Wet Signature pad or digital '
                    'attestation to sign. An audit trail records every action.',
              ),
              const _HelpStep(
                number: '5',
                title: 'Certificate of Completion',
                description:
                    'Once all parties sign, a tamper-evident Certificate '
                    'of Completion is generated with the full audit trail.',
              ),
              const SizedBox(height: 24),
              const Text(
                'All signatures and audit events are cryptographically '
                'chained, making any tampering immediately detectable.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signing Envelope'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: 'How envelopes work',
            onPressed: () => _showHelpSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: 'Create Envelope',
            onPressed: _createEnvelope,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Envelope metadata
            _sectionCard(
              title: 'Envelope Details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _subjectController,
                    decoration: const InputDecoration(
                      labelText: 'Subject *',
                      hintText: 'e.g. NDA for vendor onboarding',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _messageController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Message (optional)',
                      hintText: 'Message to recipients',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _senderNameController,
                          decoration: const InputDecoration(
                            labelText: 'Sender Name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _senderEmailController,
                          decoration: const InputDecoration(
                            labelText: 'Sender Email',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Routing mode
            _sectionCard(
              title: 'Routing Mode',
              child: SegmentedButton<RoutingMode>(
                segments: const [
                  ButtonSegment(
                    value: RoutingMode.sequential,
                    label: Text('Sequential'),
                    icon: Icon(Icons.linear_scale),
                  ),
                  ButtonSegment(
                    value: RoutingMode.parallel,
                    label: Text('Parallel'),
                    icon: Icon(Icons.multiple_stop),
                  ),
                  ButtonSegment(
                    value: RoutingMode.mixed,
                    label: Text('Mixed'),
                    icon: Icon(Icons.call_split),
                  ),
                ],
                selected: {_routingMode},
                onSelectionChanged: (selection) {
                  setState(() => _routingMode = selection.first);
                },
              ),
            ),

            const SizedBox(height: 16),

            // Recipients
            _sectionCard(
              title: 'Recipients (${_recipients.length})',
              trailing: IconButton(
                icon: const Icon(Icons.add),
                onPressed: _addRecipient,
                tooltip: 'Add recipient',
              ),
              child: Column(
                children: [
                  for (var i = 0; i < _recipients.length; i++)
                    _buildRecipientEditor(i),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Reminders & expiration
            _sectionCard(
              title: 'Reminders & Expiration',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    title: const Text('Enable automatic reminders'),
                    value: _remindersEnabled,
                    onChanged: (v) => setState(() => _remindersEnabled = v),
                  ),
                  if (_remindersEnabled) ...[
                    Row(
                      children: [
                        const Text('Remind every '),
                        DropdownButton<int>(
                          value: _reminderIntervalDays,
                          items: [1, 2, 3, 5, 7, 14]
                              .map((d) =>
                                  DropdownMenuItem(value: d, child: Text('$d')))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _reminderIntervalDays = v);
                            }
                          },
                        ),
                        const Text(' days, up to '),
                        DropdownButton<int>(
                          value: _reminderMaxCount,
                          items: [1, 2, 3, 5, 10]
                              .map((c) =>
                                  DropdownMenuItem(value: c, child: Text('$c')))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _reminderMaxCount = v);
                            }
                          },
                        ),
                        const Text(' times'),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Expires after: '),
                      DropdownButton<int?>(
                        value: _expirationDays,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Never')),
                          DropdownMenuItem(value: 7, child: Text('7 days')),
                          DropdownMenuItem(value: 14, child: Text('14 days')),
                          DropdownMenuItem(value: 30, child: Text('30 days')),
                          DropdownMenuItem(value: 60, child: Text('60 days')),
                          DropdownMenuItem(value: 90, child: Text('90 days')),
                        ],
                        onChanged: (v) => setState(() => _expirationDays = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Created envelope preview
            if (_createdEnvelope != null) _buildEnvelopePreview(_createdEnvelope!),

            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: _createEnvelope,
              icon: const Icon(Icons.send),
              label: const Text('Create Envelope'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildRecipientEditor(int index) {
    final draft = _recipients[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  child: Text('${index + 1}'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Recipient ${index + 1}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _recipients.length > 1
                      ? () => _removeRecipient(index)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: draft.nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name *',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: draft.emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email *',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<RecipientRole>(
                    initialValue: draft.role,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: RecipientRole.values
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(r.name),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => draft.role = v);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<AuthenticationMethod>(
                    initialValue: draft.authentication,
                    decoration: const InputDecoration(
                      labelText: 'Auth',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: AuthenticationMethod.values
                        .map((a) => DropdownMenuItem(
                              value: a,
                              child: Text(a.name),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => draft.authentication = v);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: DropdownButtonFormField<int>(
                    initialValue: draft.routingOrder,
                    decoration: const InputDecoration(
                      labelText: 'Order',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(10, (i) => i + 1)
                        .map((o) => DropdownMenuItem(
                              value: o,
                              child: Text('$o'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => draft.routingOrder = v);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnvelopePreview(Envelope envelope) {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Envelope Created',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: Colors.green.shade900),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText('ID: ${envelope.id}'),
            Text('Subject: ${envelope.subject}'),
            Text('Status: ${envelope.status.name}'),
            Text('Routing: ${envelope.routingMode.name}'),
            Text('Recipients: ${envelope.recipients.length}'),
            if (envelope.expiresAt != null)
              Text(
                'Expires: ${DateFormat('yyyy-MM-dd').format(
                  DateTime.fromMillisecondsSinceEpoch(
                    envelope.expiresAt! * 1000,
                  ),
                )}',
              ),
            const SizedBox(height: 8),
            const Text(
              'Audit Trail:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final event in envelope.events)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: Text(
                  '• [${event.eventType}] ${event.description}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Mutable state for editing a recipient in the UI.
class _RecipientDraft {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  RecipientRole role = RecipientRole.signer;
  AuthenticationMethod authentication = AuthenticationMethod.none;
  int routingOrder = 1;

  void dispose() {
    nameController.dispose();
    emailController.dispose();
  }
}

/// A numbered step in the help bottom sheet.
class _HelpStep extends StatelessWidget {
  final String number;
  final String title;
  final String description;

  const _HelpStep({
    required this.number,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              number,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
