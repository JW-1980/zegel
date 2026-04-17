import 'package:flutter/material.dart';

/// A text field that masks sensitive content by default with a show/hide toggle.
///
/// Used for master keys, API keys, passwords, and other secrets.
/// Content is hidden behind dots until the user explicitly clicks the
/// visibility toggle, preventing shoulder-surfing attacks.
///
/// Implements item 76 from SUGGESTED_IMPROVEMENTS.md:
/// "Mask sensitive inputs (like API keys) by default until clicked."
class SensitiveField extends StatefulWidget {
  /// Controller for the text field.
  final TextEditingController controller;

  /// Label text displayed above the field.
  final String labelText;

  /// Hint text shown when the field is empty.
  final String? hintText;

  /// Icon shown at the start of the field.
  final IconData? prefixIcon;

  /// Whether the field is read-only.
  final bool readOnly;

  /// Callback when the text changes.
  final ValueChanged<String>? onChanged;

  /// Input validators.
  final String? Function(String?)? validator;

  /// Whether to show a copy button.
  final bool showCopyButton;

  /// Maximum number of lines.
  final int maxLines;

  const SensitiveField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText,
    this.prefixIcon,
    this.readOnly = false,
    this.onChanged,
    this.validator,
    this.showCopyButton = true,
    this.maxLines = 1,
  });

  @override
  State<SensitiveField> createState() => _SensitiveFieldState();
}

class _SensitiveFieldState extends State<SensitiveField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscured && widget.maxLines == 1,
      readOnly: widget.readOnly,
      onChanged: widget.onChanged,
      validator: widget.validator,
      maxLines: _obscured ? 1 : widget.maxLines,
      style: _obscured
          ? const TextStyle(letterSpacing: 2)
          : const TextStyle(fontFamily: 'monospace', fontSize: 13),
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        prefixIcon:
            widget.prefixIcon != null ? Icon(widget.prefixIcon) : null,
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Visibility toggle
            IconButton(
              icon: Icon(
                _obscured ? Icons.visibility_off : Icons.visibility,
                size: 20,
              ),
              tooltip: _obscured ? 'Show content' : 'Hide content',
              onPressed: () {
                setState(() {
                  _obscured = !_obscured;
                });
              },
            ),
            // Copy button
            if (widget.showCopyButton)
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                tooltip: 'Copy to clipboard',
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: widget.controller.text),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
          ],
        ),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// A read-only display of a sensitive value with mask/reveal toggle.
///
/// Used in inspection screens where a key or hash is shown but should
/// be hidden by default.
class SensitiveDisplay extends StatefulWidget {
  /// The sensitive value to display.
  final String value;

  /// Label for the value.
  final String label;

  /// Whether to allow copying.
  final bool allowCopy;

  const SensitiveDisplay({
    super.key,
    required this.value,
    required this.label,
    this.allowCopy = true,
  });

  @override
  State<SensitiveDisplay> createState() => _SensitiveDisplayState();
}

class _SensitiveDisplayState extends State<SensitiveDisplay> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final displayValue = _revealed
        ? widget.value
        : '\u2022' * (widget.value.length.clamp(8, 32));

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                displayValue,
                style: TextStyle(
                  fontFamily: _revealed ? 'monospace' : null,
                  fontSize: _revealed ? 12 : 14,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            _revealed ? Icons.visibility : Icons.visibility_off,
            size: 18,
          ),
          tooltip: _revealed ? 'Hide' : 'Reveal',
          onPressed: () => setState(() => _revealed = !_revealed),
        ),
        if (widget.allowCopy)
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: widget.value));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
      ],
    );
  }
}
