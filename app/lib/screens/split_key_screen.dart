import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zegel_app/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/zegel_service.dart';
import '../widgets/key_input.dart';

/// Screen for splitting and reconstructing keys using Shamir's Secret Sharing.
///
/// Has two tabs:
/// - Split: enter a key, set M-of-N parameters, generate shares
/// - Reconstruct: enter M shares, reconstruct the original key
class SplitKeyScreen extends StatefulWidget {
  const SplitKeyScreen({super.key});

  @override
  State<SplitKeyScreen> createState() => _SplitKeyScreenState();
}

class _SplitKeyScreenState extends State<SplitKeyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Split tab state
  String _splitHexKey = '';
  int _threshold = 3;
  int _totalShares = 5;
  List<String>? _generatedShares;
  bool _isSplitting = false;
  String? _splitError;

  // Reconstruct tab state
  final List<TextEditingController> _shareControllers = [];
  String? _reconstructedKey;
  bool _isReconstructing = false;
  String? _reconstructError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _addShareInput();
    _addShareInput();
    _addShareInput();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _shareControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _addShareInput() {
    setState(() {
      _shareControllers.add(TextEditingController());
    });
  }

  void _removeShareInput(int index) {
    if (_shareControllers.length > 2) {
      setState(() {
        _shareControllers[index].dispose();
        _shareControllers.removeAt(index);
      });
    }
  }

  Future<void> _splitKey() async {
    if (_splitHexKey.length != 64) {
      setState(() {
        _splitError = 'Please enter a valid 64-character hex key.';
      });
      return;
    }

    if (_threshold < 2 || _threshold > _totalShares || _totalShares > 255) {
      setState(() {
        _splitError =
            'Invalid parameters: threshold must be 2 <= M <= N <= 255.';
      });
      return;
    }

    setState(() {
      _isSplitting = true;
      _generatedShares = null;
      _splitError = null;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final shares = await zegelService.splitKey(
        _splitHexKey,
        _threshold,
        _totalShares,
      );

      if (mounted) {
        setState(() {
          _generatedShares = shares;
          _isSplitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _splitError = e.toString();
          _isSplitting = false;
        });
      }
    }
  }

  Future<void> _reconstructKey() async {
    final shares = _shareControllers
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (shares.length < 2) {
      setState(() {
        _reconstructError = 'At least 2 shares are required.';
      });
      return;
    }

    setState(() {
      _isReconstructing = true;
      _reconstructedKey = null;
      _reconstructError = null;
    });

    try {
      final zegelService = context.read<ZegelService>();
      final key = await zegelService.reconstructKey(shares);

      if (mounted) {
        setState(() {
          _reconstructedKey = key;
          _isReconstructing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _reconstructError = e.toString();
          _isReconstructing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    // ignore: unused_local_variable
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.splitKeyAction),
        bottom: TabBar(
          controller: _tabController,
          labelColor: theme.colorScheme.onPrimary,
          unselectedLabelColor: theme.colorScheme.onPrimary.withValues(alpha: 0.6),
          indicatorColor: theme.colorScheme.onPrimary,
          tabs: const [
            Tab(text: 'Split Key'),
            Tab(text: 'Reconstruct'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSplitTab(context, l10n, theme),
          _buildReconstructTab(context, l10n, theme),
        ],
      ),
    );
  }

  Widget _buildSplitTab(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Key input
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: KeyInput(
                onKeyChanged: (key) => setState(() => _splitHexKey = key),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // M-of-N parameters
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Split Parameters',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The key will be split into N shares. Any M shares can reconstruct the key.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            labelText: l10n.thresholdLabel,
                            hintText: '3',
                            helperText: 'Minimum shares needed',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          controller:
                              TextEditingController(text: '$_threshold'),
                          onChanged: (v) => setState(
                            () => _threshold = int.tryParse(v) ?? 3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            labelText: l10n.totalSharesLabel,
                            hintText: '5',
                            helperText: 'Total shares to generate',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          controller:
                              TextEditingController(text: '$_totalShares'),
                          onChanged: (v) => setState(
                            () => _totalShares = int.tryParse(v) ?? 5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Split button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isSplitting ? null : _splitKey,
              icon: _isSplitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.call_split),
              label: Text(
                _isSplitting ? 'Splitting...' : l10n.splitKeyAction,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Error
          if (_splitError != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _splitError!,
                style: TextStyle(color: Colors.red.shade900),
              ),
            ),

          // Generated shares
          if (_generatedShares != null) ...[
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
                          'Generated Shares',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$_threshold of $_totalShares shares needed to reconstruct',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Divider(),
                    ..._generatedShares!.asMap().entries.map((entry) {
                      final index = entry.key;
                      final share = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor:
                                  theme.colorScheme.primary.withValues(alpha: 0.1),
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                share.length > 24
                                    ? '${share.substring(0, 24)}...'
                                    : share,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              tooltip: 'Copy share',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: share));
                                if (mounted) {
                                  // ignore: use_build_context_synchronously
      // ignore: use_build_context_synchronously
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Share ${index + 1} copied to clipboard',
                                    ),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.share, size: 18),
                              tooltip: 'Share',
                              onPressed: () {
                                Share.share(
                                  share,
                                  subject:
                                      'Zegel Key Share ${index + 1} of $_totalShares',
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber,
                            color: Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Distribute each share to a different party via a secure channel. '
                              'Never store all shares together.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildReconstructTab(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.merge, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Enter Shares',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        tooltip: 'Add share input',
                        onPressed: _addShareInput,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Enter at least M shares to reconstruct the original key.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Divider(),
                  ..._shareControllers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final controller = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor:
                                theme.colorScheme.primary.withValues(alpha: 0.1),
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: controller,
                              decoration: InputDecoration(
                                hintText: 'Share ${index + 1} (hex)',
                                isDense: true,
                              ),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (_shareControllers.length > 2)
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 18,
                              ),
                              onPressed: () => _removeShareInput(index),
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

          // Reconstruct button
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isReconstructing ? null : _reconstructKey,
              icon: _isReconstructing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.merge_type),
              label: Text(
                _isReconstructing
                    ? 'Reconstructing...'
                    : 'Reconstruct Key',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Error
          if (_reconstructError != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _reconstructError!,
                style: TextStyle(color: Colors.red.shade900),
              ),
            ),

          // Reconstructed key
          if (_reconstructedKey != null)
            Card(
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
                          'Reconstructed Key',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    SelectableText(
                      _reconstructedKey!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Copy'),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: _reconstructedKey!),
                            );
                            if (mounted) {
                              // ignore: use_build_context_synchronously
      // ignore: use_build_context_synchronously
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Key copied to clipboard'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
