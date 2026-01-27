import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../services/key_service.dart';

/// A reusable widget for entering, loading, or generating a cryptographic key.
///
/// Supports:
/// - Manual hex key entry with validation
/// - Loading key from a file
/// - Generating a new random key
/// - Loading from saved keys (keychain)
/// - Obscure text toggle
class KeyInput extends StatefulWidget {
  /// Called when the key value changes (valid or invalid).
  final ValueChanged<String> onKeyChanged;

  /// Optional initial key value.
  final String? initialKey;

  /// Whether the field is read-only.
  final bool readOnly;

  const KeyInput({
    super.key,
    required this.onKeyChanged,
    this.initialKey,
    this.readOnly = false,
  });

  @override
  State<KeyInput> createState() => _KeyInputState();
}

class _KeyInputState extends State<KeyInput> {
  late final TextEditingController _controller;
  bool _obscureText = true;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialKey ?? '');
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final value = _controller.text.trim();
    _validate(value);
    widget.onKeyChanged(value);
  }

  void _validate(String value) {
    if (value.isEmpty) {
      setState(() => _errorText = null);
      return;
    }
    if (value.length != 64) {
      setState(() => _errorText = 'Key must be 64 hex characters (${value.length}/64)');
      return;
    }
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
      setState(() => _errorText = 'Key must contain only hexadecimal characters (0-9, a-f)');
      return;
    }
    setState(() => _errorText = null);
  }

  bool get _isValid {
    final value = _controller.text.trim();
    return value.length == 64 && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);
  }

  Future<void> _loadFromFile() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickFile();
    if (path == null) return;

    try {
      final file = File(path);
      final content = await file.readAsString();
      final trimmed = content.trim();

      // Accept raw hex key from file
      if (trimmed.length == 64 &&
          RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(trimmed)) {
        _controller.text = trimmed;
        return;
      }

      // Accept raw 32 bytes as hex
      final bytes = await file.readAsBytes();
      if (bytes.length == 32) {
        final hex =
            bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        _controller.text = hex;
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Invalid key file. Expected 64 hex characters or 32 raw bytes.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load key file: $e')),
        );
      }
    }
  }

  void _generateNew() {
    final keyService = context.read<KeyService>();
    final newKey = keyService.generateKey();
    _controller.text = newKey;
  }

  Future<void> _loadFromSaved() async {
    final keyService = context.read<KeyService>();
    final names = await keyService.listKeys();

    if (names.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No saved keys found')),
        );
      }
      return;
    }

    if (!mounted) return;

    final selected = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Select Saved Key'),
          children: names.map((name) {
            return SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(name),
              child: Text(name),
            );
          }).toList(),
        );
      },
    );

    if (selected != null) {
      final key = await keyService.getKey(selected);
      if (key != null) {
        _controller.text = key;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.keyLabel,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          readOnly: widget.readOnly,
          obscureText: _obscureText,
          maxLength: 64,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
          ),
          decoration: InputDecoration(
            hintText: l10n.keyHint,
            errorText: _errorText,
            counterText: '${_controller.text.trim().length}/64',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    _obscureText ? Icons.visibility : Icons.visibility_off,
                  ),
                  tooltip: _obscureText ? 'Show key' : 'Hide key',
                  onPressed: () {
                    setState(() => _obscureText = !_obscureText);
                  },
                ),
                if (_isValid)
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy key',
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: _controller.text.trim()),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Key copied to clipboard'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
            LengthLimitingTextInputFormatter(64),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: widget.readOnly ? null : _loadFromFile,
              icon: const Icon(Icons.file_open, size: 18),
              label: const Text('Load from File'),
            ),
            OutlinedButton.icon(
              onPressed: widget.readOnly ? null : _generateNew,
              icon: const Icon(Icons.casino, size: 18),
              label: Text(l10n.generateKeyAction),
            ),
            OutlinedButton.icon(
              onPressed: widget.readOnly ? null : _loadFromSaved,
              icon: const Icon(Icons.key, size: 18),
              label: const Text('Load Saved'),
            ),
          ],
        ),
      ],
    );
  }
}
