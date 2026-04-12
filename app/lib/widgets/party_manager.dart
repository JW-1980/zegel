import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';

/// Represents a party involved in a contract workflow.
class ContractParty {
  final String name;
  final String role;
  final String keyHex;

  const ContractParty({
    required this.name,
    required this.role,
    this.keyHex = '',
  });

  ContractParty copyWith({
    String? name,
    String? role,
    String? keyHex,
  }) {
    return ContractParty(
      name: name ?? this.name,
      role: role ?? this.role,
      keyHex: keyHex ?? this.keyHex,
    );
  }
}

/// Available roles for contract parties.
const contractRoles = [
  'buyer',
  'seller',
  'notary',
  'bank',
  'agent',
  'auditor',
  'reviewer',
];

/// Widget for managing contract parties.
///
/// Displays a list of parties with name, role, and key status.
/// Provides add/remove buttons and role dropdowns.
class PartyManager extends StatelessWidget {
  /// Current list of parties.
  final List<ContractParty> parties;

  /// Called when a new party is added.
  final ValueChanged<ContractParty> onAddParty;

  /// Called when a party is removed by index.
  final ValueChanged<int> onRemoveParty;

  /// Called when a party is updated.
  final void Function(int index, ContractParty party) onUpdateParty;

  /// Whether the widget is interactive.
  final bool enabled;

  const PartyManager({
    super.key,
    required this.parties,
    required this.onAddParty,
    required this.onRemoveParty,
    required this.onUpdateParty,
    this.enabled = true,
  });

  void _showAddPartyDialog(BuildContext context) {
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final nameController = TextEditingController();
    final keyController = TextEditingController();
    String selectedRole = contractRoles.first;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(l10n.contractAddParty),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: l10n.contractPartyName,
                        hintText: l10n.contractPartyNameHint,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: InputDecoration(
                        labelText: l10n.contractPartyRole,
                        border: const OutlineInputBorder(),
                      ),
                      items: contractRoles
                          .map((role) => DropdownMenuItem(
                                // ignore: deprecated_member_use
                                // ignore: deprecated_member_use
                                value: role,
                                child: Text(_roleDisplayName(role)),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => selectedRole = v);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keyController,
                      decoration: InputDecoration(
                        labelText: l10n.contractPartyKey,
                        hintText: l10n.contractPartyKeyHint,
                      ),
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                      maxLength: 64,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9a-fA-F]')),
                        LengthLimitingTextInputFormatter(64),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.cancelAction),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    onAddParty(ContractParty(
                      name: name,
                      role: selectedRole,
                      keyHex: keyController.text.trim(),
                    ));
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(l10n.contractAddPartyAction),
                ),
              ],
            );
          },
        );
      },
    );

    // Controllers will be garbage collected after the dialog closes.
  }

  static String _roleDisplayName(String role) {
    switch (role) {
      case 'buyer':
        return 'Buyer';
      case 'seller':
        return 'Seller';
      case 'notary':
        return 'Notary';
      case 'bank':
        return 'Bank';
      case 'agent':
        return 'Agent';
      case 'auditor':
        return 'Auditor';
      case 'reviewer':
        return 'Reviewer';
      default:
        return role;
    }
  }

  static IconData _roleIcon(String role) {
    switch (role) {
      case 'buyer':
        return Icons.shopping_cart;
      case 'seller':
        return Icons.storefront;
      case 'notary':
        return Icons.gavel;
      case 'bank':
        return Icons.account_balance;
      case 'agent':
        return Icons.person;
      case 'auditor':
        return Icons.search;
      case 'reviewer':
        return Icons.rate_review;
      default:
        return Icons.person_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.group, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              l10n.contractPartiesLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: l10n.contractAddParty,
              onPressed: enabled ? () => _showAddPartyDialog(context) : null,
            ),
          ],
        ),
        if (parties.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              l10n.contractNoParties,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...parties.asMap().entries.map((entry) {
            final index = entry.key;
            final party = entry.value;
            final hasKey = party.keyHex.length == 64;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 18,
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.1),
                child: Icon(
                  _roleIcon(party.role),
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              ),
              title: Text(
                party.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Row(
                children: [
                  Text(
                    _roleDisplayName(party.role),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    hasKey ? Icons.key : Icons.key_off,
                    size: 14,
                    color: hasKey ? Colors.green : Colors.orange,
                  ),
                  Text(
                    hasKey ? ' Key set' : ' No key',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hasKey ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    color: Colors.red, size: 20),
                onPressed: enabled ? () => onRemoveParty(index) : null,
              ),
            );
          }),
      ],
    );
  }
}
