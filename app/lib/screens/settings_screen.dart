import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../services/key_service.dart';

/// Settings screen for the Zegel application.
///
/// Provides:
/// - Saved keys management (add, remove, rename)
/// - Default block size configuration
/// - Language picker (English, Dutch)
/// - About section with version and license info
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<String> _keyNames = [];
  bool _isLoadingKeys = true;
  String _selectedBlockSize = '65536';
  String _defaultClassification = 'INTERNAL';
  // ignore: unused_field
  String _tsaUrl = '';
  bool _preserveMediaMetadata = false;
  bool _anonymousMode = false;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    if (!mounted) return;
    final keyService = context.read<KeyService>();
    final names = await keyService.listKeys();
    if (mounted) {
      setState(() {
        _keyNames = names;
        _isLoadingKeys = false;
      });
    }
  }

  Future<void> _addKey() async {
    final nameController = TextEditingController();
    final keyController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Key Name',
                  hintText: 'e.g. My Production Key',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyController,
                decoration: const InputDecoration(
                  labelText: 'Hex Key (64 characters)',
                  hintText: '0a1b2c...',
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                maxLength: 64,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.casino, size: 16),
                  label: const Text('Generate Random'),
                  onPressed: () {
                    if (!mounted) return;
                    final keyService = context.read<KeyService>();
                    keyController.text = keyService.generateKey();
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      final name = nameController.text.trim();
      final key = keyController.text.trim();

      if (name.isEmpty) {
        if (mounted) {
          // ignore: use_build_context_synchronously
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Key name cannot be empty')),
          );
        }
        return;
      }

      if (!mounted) return;
      final keyService = context.read<KeyService>();
      if (!keyService.isValidHexKey(key)) {
        if (mounted) {
          // ignore: use_build_context_synchronously
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid key: must be 64 hex characters'),
            ),
          );
        }
        return;
      }

      await keyService.saveKey(name, key);
      await _loadKeys();
    }

    nameController.dispose();
    keyController.dispose();
  }

  Future<void> _deleteKey(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Key'),
          content: Text('Are you sure you want to delete the key "$name"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      if (!mounted) return;
      final keyService = context.read<KeyService>();
      await keyService.deleteKey(name);
      await _loadKeys();
    }
  }

  Future<void> _renameKey(String oldName) async {
    final controller = TextEditingController(text: oldName);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Key'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'New Name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    if (newName != null && newName.isNotEmpty && newName != oldName) {
      if (!mounted) return;
      final keyService = context.read<KeyService>();
      await keyService.renameKey(oldName, newName);
      await _loadKeys();
    }

    controller.dispose();
  }

  void _changeLanguage(Locale locale) {
    final localeNotifier = context.read<LocaleNotifier>();
    localeNotifier.setLocale(locale);
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final localeNotifier = context.watch<LocaleNotifier>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Saved keys section
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
                        l10n.savedKeysTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        tooltip: 'Add Key',
                        onPressed: _addKey,
                      ),
                    ],
                  ),
                  const Divider(),
                  if (_isLoadingKeys)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_keyNames.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No saved keys. Tap + to add one.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    ..._keyNames.map((name) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.vpn_key, size: 20),
                        title: Text(name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 18),
                              tooltip: 'Rename',
                              onPressed: () => _renameKey(name),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Colors.red,
                              ),
                              tooltip: 'Delete',
                              onPressed: () => _deleteKey(name),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Block size setting
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.view_module, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.blockSizeLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _selectedBlockSize,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        // ignore: deprecated_member_use
                        value: '16384',
                        child: Text('16 KB'),
                      ),
                      DropdownMenuItem(
                        // ignore: deprecated_member_use
                        value: '32768',
                        child: Text('32 KB'),
                      ),
                      DropdownMenuItem(
                        // ignore: deprecated_member_use
                        value: '65536',
                        child: Text('64 KB (default)'),
                      ),
                      DropdownMenuItem(
                        // ignore: deprecated_member_use
                        value: '131072',
                        child: Text('128 KB'),
                      ),
                      DropdownMenuItem(
                        // ignore: deprecated_member_use
                        value: '262144',
                        child: Text('256 KB'),
                      ),
                    ],
                    // ignore: deprecated_member_use
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedBlockSize = value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Language picker
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.language, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.languageLabel,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  RadioListTile<Locale>(
                    title: const Text('English'),
                    // ignore: deprecated_member_use
                    value: const Locale('en'),
                    // ignore: deprecated_member_use
                    groupValue: localeNotifier.locale,
                    // ignore: deprecated_member_use
                    onChanged: (value) {
                      if (value != null) _changeLanguage(value);
                    },
                  ),
                  RadioListTile<Locale>(
                    title: const Text('Nederlands'),
                    // ignore: deprecated_member_use
                    value: const Locale('nl'),
                    // ignore: deprecated_member_use
                    groupValue: localeNotifier.locale,
                    // ignore: deprecated_member_use
                    onChanged: (value) {
                      if (value != null) _changeLanguage(value);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Default classification level
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
                        l10n.settingsDefaultClassification,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _defaultClassification,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        // ignore: deprecated_member_use
                        value: 'PUBLIC',
                        child: Text('PUBLIC'),
                      ),
                      DropdownMenuItem(
                        // ignore: deprecated_member_use
                        value: 'INTERNAL',
                        child: Text('INTERNAL'),
                      ),
                      DropdownMenuItem(
                        // ignore: deprecated_member_use
                        value: 'CONFIDENTIAL',
                        child: Text('CONFIDENTIAL'),
                      ),
                      DropdownMenuItem(
                        // ignore: deprecated_member_use
                        value: 'SECRET',
                        child: Text('SECRET'),
                      ),
                      DropdownMenuItem(
                        // ignore: deprecated_member_use
                        value: 'TOP_SECRET',
                        child: Text('TOP SECRET'),
                      ),
                    ],
                    // ignore: deprecated_member_use
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _defaultClassification = value);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // TSA URL setting
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.access_time, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.settingsTsaUrl,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      hintText: l10n.settingsTsaUrlHint,
                      border: const OutlineInputBorder(),
                    ),
                    // ignore: deprecated_member_use
                    // ignore: deprecated_member_use
                    // ignore: deprecated_member_use
                    // ignore: deprecated_member_use
                    onChanged: (v) => setState(() => _tsaUrl = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Toggles
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        l10n.settingsAdvancedOptions,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: Text(l10n.settingsPreserveMediaMetadata),
                    subtitle: Text(l10n.settingsPreserveMediaMetadataDesc),
                    // ignore: deprecated_member_use
                    value: _preserveMediaMetadata,
                    // ignore: deprecated_member_use
                    onChanged: (v) =>
                        setState(() => _preserveMediaMetadata = v),
                  ),
                  SwitchListTile(
                    title: Text(l10n.settingsAnonymousMode),
                    subtitle: Text(l10n.settingsAnonymousModeDesc),
                    // ignore: deprecated_member_use
                    value: _anonymousMode,
                    // ignore: deprecated_member_use
                    onChanged: (v) => setState(() => _anonymousMode = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // About section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'About',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  const _AboutRow(
                    label: 'Application', // ignore: deprecated_member_use
                    value: 'Zegel',
                  ),
                  const _AboutRow(
                    label: 'Version', // ignore: deprecated_member_use
                    value: '1.3.0',
                  ),
                  const _AboutRow(
                    label: 'Format Version', // ignore: deprecated_member_use
                    value: '1.2',
                  ),
                  const _AboutRow(
                    label: 'File Extension', // ignore: deprecated_member_use
                    value: '.zgl',
                  ),
                  const _AboutRow(
                    label: 'MIME Type', // ignore: deprecated_member_use
                    value: 'application/x-zgl',
                  ),
                  const SizedBox(height: 8),
                  const _AboutRow(
                    label: 'Code License',
                    // ignore: deprecated_member_use
                    value: 'Apache License 2.0',
                  ),
                  const _AboutRow(
                    label: 'Spec License',
                    // ignore: deprecated_member_use
                    value: 'CC BY 4.0',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Zegel ("seal" in Dutch) is a tamper-proof container '
                    'format that makes file content physically unreadable '
                    'if even a single byte is modified.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'v1.3 Features',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '- Batch operations (verify & seal)\n'
                    '- Classification management (PUBLIC to TOP SECRET)\n'
                    '- Manifest creation & verification\n'
                    '- Excerpt proof generation & verification\n'
                    '- Provenance chain viewer\n'
                    '- Credential issuance & verification\n'
                    '- Contract multi-party workflows\n'
                    '- Anonymous mode & TSA timestamps\n'
                    '- Media metadata preservation',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final String label;
  final String value;

  const _AboutRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
