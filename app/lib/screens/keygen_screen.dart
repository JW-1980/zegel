import 'package:flutter/services.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/key_service.dart';

/// Screen for generating cryptographically secure keys.
///
/// Features:
/// - Generate new 32-byte (256-bit) keys using secure random
/// - Display key in hex and base64 formats
/// - Copy key to clipboard
/// - Save key to file
/// - Save key to secure storage with a name
/// - Security warnings about key storage
class KeygenScreen extends StatefulWidget {
  const KeygenScreen({super.key});

  @override
  State<KeygenScreen> createState() => _KeygenScreenState();
}

class _KeygenScreenState extends State<KeygenScreen> {
  String? _generatedKeyHex;
  String? _generatedKeyBase64;
  bool _obscureKey = true;
  bool _isSaving = false;
  String? _statusMessage;
  bool _isError = false;

  final TextEditingController _keyNameController = TextEditingController();

  @override
  void dispose() {
    _keyNameController.dispose();
    super.dispose();
  }

  void _generateKey() {
    final keyService = context.read<KeyService>();
    final hexKey = keyService.generateKey();
    final bytes = keyService.hexToBytes(hexKey);
    final base64Key = base64Encode(bytes);

    setState(() {
      _generatedKeyHex = hexKey;
      _generatedKeyBase64 = base64Key;
      _statusMessage = null;
      _isError = false;
    });
  }

  Future<void> _copyToClipboard(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label copied to clipboard'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveToFile() async {
    if (_generatedKeyHex == null) return;

    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });

    try {
      final fileService = context.read<FileService>();
      final keyService = context.read<KeyService>();

      // Save as raw 32 bytes
      final bytes = Uint8List.fromList(
        keyService.hexToBytes(_generatedKeyHex!),
      );
      final savedPath = await fileService.saveFile(bytes, 'zegel_key.bin');

      if (savedPath != null && mounted) {
        setState(() {
          _statusMessage = 'Key saved to file successfully';
          _isError = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Failed to save key: $e';
          _isError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveToSecureStorage() async {
    if (_generatedKeyHex == null) return;

    final name = _keyNameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _statusMessage = 'Please enter a name for the key';
        _isError = true;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _statusMessage = null;
    });

    try {
      final keyService = context.read<KeyService>();
      await keyService.saveKey(name, _generatedKeyHex!);

      if (mounted) {
        setState(() {
          _statusMessage = 'Key "$name" saved to secure storage';
          _isError = false;
          _keyNameController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Failed to save key: $e';
          _isError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.generateKeyAction)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Security warning card
            Card(
              color: Colors.orange.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.warning_amber,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Security Warning',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This key is the ONLY way to access your sealed files. '
                      'If you lose it, your data is permanently unrecoverable.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.orange.shade900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Recommendations:',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const _SecurityTip(
                      icon: Icons.backup,
                      text: 'Store multiple backups in secure locations',
                    ),
                    const _SecurityTip(
                      icon: Icons.lock,
                      text: 'Use a password manager for digital backup',
                    ),
                    const _SecurityTip(
                      icon: Icons.print,
                      text: 'Consider printing and storing in a safe',
                    ),
                    const _SecurityTip(
                      icon: Icons.security,
                      text: 'Never share your key via email or messaging',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Generate button
            SizedBox(
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _generateKey,
                icon: const Icon(Icons.casino, size: 28),
                label: Text(
                  _generatedKeyHex == null
                      ? 'Generate New Key'
                      : 'Generate Another Key',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Generated key display
            if (_generatedKeyHex != null) ...[
              // Key info card
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
                            'Generated Key',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(
                              _obscureKey
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            tooltip: _obscureKey ? 'Show key' : 'Hide key',
                            onPressed: () {
                              setState(() => _obscureKey = !_obscureKey);
                            },
                          ),
                        ],
                      ),
                      const Divider(),

                      // Key properties
                      const _KeyProperty(
                        label: 'Algorithm',
                        value: 'AES-256-GCM',
                        icon: Icons.security,
                      ),
                      const _KeyProperty(
                        label: 'Key Size',
                        value: '256 bits (32 bytes)',
                        icon: Icons.straighten,
                      ),
                      const _KeyProperty(
                        label: 'Source',
                        value: 'Cryptographically Secure RNG',
                        icon: Icons.shuffle,
                      ),
                      const SizedBox(height: 16),

                      // Hex format
                      Text(
                        'Hexadecimal Format (64 characters)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.outline.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                _obscureKey ? '*' * 64 : _generatedKeyHex!,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  letterSpacing: 1,
                                  color: _obscureKey
                                      ? theme.colorScheme.onSurfaceVariant
                                      : null,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 20),
                              tooltip: 'Copy hex key',
                              onPressed: () => _copyToClipboard(
                                _generatedKeyHex!,
                                'Hex key',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Base64 format
                      Text(
                        'Base64 Format (44 characters)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.outline.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                _obscureKey ? '*' * 44 : _generatedKeyBase64!,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  letterSpacing: 1,
                                  color: _obscureKey
                                      ? theme.colorScheme.onSurfaceVariant
                                      : null,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 20),
                              tooltip: 'Copy base64 key',
                              onPressed: () => _copyToClipboard(
                                _generatedKeyBase64!,
                                'Base64 key',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Save options card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.save, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Save Key',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const Divider(),

                      // Save to file
                      ListTile(
                        leading: const Icon(Icons.file_download),
                        title: const Text('Save to File'),
                        subtitle: const Text(
                          'Export as raw 32-byte binary file',
                        ),
                        trailing: ElevatedButton(
                          onPressed: _isSaving ? null : _saveToFile,
                          child: const Text('Save'),
                        ),
                      ),
                      const Divider(),

                      // Save to secure storage
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.shield),
                                const SizedBox(width: 8),
                                Text(
                                  'Save to Secure Storage',
                                  style: theme.textTheme.titleSmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Store in platform keychain (Keychain/Credential Manager)',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _keyNameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Key Name',
                                      hintText: 'e.g. Work Documents Key',
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed:
                                      _isSaving ? null : _saveToSecureStorage,
                                  child: const Text('Save'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Status message
            if (_statusMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
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
            const SizedBox(height: 24),

            // Info card about key usage
            Card(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
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
                          'About Zegel Keys',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Zegel uses 256-bit AES-GCM encryption with per-block key '
                      'derivation. The master key is used with HKDF to derive '
                      'unique keys for each block, ensuring that compromising '
                      'one block does not compromise others.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Keys generated here use your platform\'s cryptographically '
                      'secure random number generator (CSPRNG).',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
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

/// A security tip with an icon.
class _SecurityTip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SecurityTip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
            ),
          ),
        ],
      ),
    );
  }
}

/// A key property row.
class _KeyProperty extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _KeyProperty({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
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
