import 'package:flutter/material.dart';

/// A command palette (Ctrl+K / Cmd+K) for quick navigation and actions.
///
/// Provides a searchable list of all available actions, screens, and tools.
/// Similar to VS Code's command palette or Spotlight on macOS.
///
/// Usage: Wrap your root widget with [CommandPaletteShortcut] to enable
/// the Ctrl+K keyboard shortcut globally.
class CommandPalette extends StatefulWidget {
  /// List of available commands.
  final List<CommandItem> commands;

  const CommandPalette({super.key, required this.commands});

  /// Shows the command palette as a dialog.
  static Future<CommandItem?> show(
    BuildContext context,
    List<CommandItem> commands,
  ) {
    return showDialog<CommandItem>(
      context: context,
      builder: (_) => CommandPalette(commands: commands),
    );
  }

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  List<CommandItem> _filteredCommands = [];
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _filteredCommands = widget.commands;
    _searchController.addListener(_onSearchChanged);
    // Auto-focus the search field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCommands = widget.commands;
      } else {
        _filteredCommands = widget.commands.where((cmd) {
          return cmd.label.toLowerCase().contains(query) ||
              cmd.category.toLowerCase().contains(query) ||
              (cmd.description?.toLowerCase().contains(query) ?? false);
        }).toList();
      }
      _selectedIndex = 0;
    });
  }

  void _executeCommand(CommandItem command) {
    Navigator.of(context).pop(command);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search input
            Padding(
              padding: const EdgeInsets.all(12),
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      setState(() {
                        _selectedIndex = (_selectedIndex + 1).clamp(
                          0,
                          _filteredCommands.length - 1,
                        );
                      });
                    } else if (event.logicalKey ==
                        LogicalKeyboardKey.arrowUp) {
                      setState(() {
                        _selectedIndex = (_selectedIndex - 1).clamp(
                          0,
                          _filteredCommands.length - 1,
                        );
                      });
                    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                      if (_filteredCommands.isNotEmpty) {
                        _executeCommand(_filteredCommands[_selectedIndex]);
                      }
                    } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                      Navigator.of(context).pop();
                    }
                  }
                },
                child: TextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: 'Type a command or search...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    filled: true,
                  ),
                ),
              ),
            ),

            const Divider(height: 1),

            // Command list
            Flexible(
              child: _filteredCommands.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No matching commands'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filteredCommands.length,
                      itemBuilder: (context, index) {
                        final command = _filteredCommands[index];
                        final isSelected = index == _selectedIndex;

                        return Container(
                          color: isSelected
                              ? theme.colorScheme.primaryContainer
                              : null,
                          child: ListTile(
                            leading: Icon(
                              command.icon,
                              color: isSelected
                                  ? theme.colorScheme.onPrimaryContainer
                                  : null,
                            ),
                            title: Text(
                              command.label,
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: command.description != null
                                ? Text(
                                    command.description!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  )
                                : null,
                            trailing: Text(
                              command.category,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                            dense: true,
                            onTap: () => _executeCommand(command),
                          ),
                        );
                      },
                    ),
            ),

            // Footer with keyboard hints
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _shortcutHint(context, 'Enter', 'select'),
                  const SizedBox(width: 16),
                  _shortcutHint(context, 'Esc', 'close'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shortcutHint(BuildContext context, String key, String action) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Text(
            key,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 4),
        Text(action, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// A single command item in the command palette.
class CommandItem {
  /// Display label.
  final String label;

  /// Category for grouping (e.g., "Core", "Security", "Tools").
  final String category;

  /// Optional description shown below the label.
  final String? description;

  /// Icon displayed alongside the label.
  final IconData icon;

  /// Callback to execute when selected.
  final VoidCallback onExecute;

  const CommandItem({
    required this.label,
    required this.category,
    required this.icon,
    required this.onExecute,
    this.description,
  });
}

/// Wrapper widget that adds Ctrl+K / Cmd+K shortcut to open the command palette.
///
/// Wrap your root scaffold or home screen with this widget.
class CommandPaletteShortcut extends StatelessWidget {
  final Widget child;
  final List<CommandItem> commands;

  const CommandPaletteShortcut({
    super.key,
    required this.child,
    required this.commands,
  });

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          CommandPalette.show(context, commands);
        },
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
          CommandPalette.show(context, commands);
        },
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
