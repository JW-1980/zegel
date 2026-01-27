import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../services/file_service.dart';
import '../widgets/drop_zone.dart';
import 'seal_screen.dart';
import 'verify_screen.dart';
import 'extract_screen.dart';
import 'settings_screen.dart';
import 'redact_screen.dart';
import 'split_key_screen.dart';
import 'disclose_screen.dart';

/// The main home screen of the Zegel application.
///
/// Features a large drag-and-drop zone in the center, a bottom navigation
/// bar for primary actions, and a drawer for advanced features.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final List<String> _recentFiles = [];

  void _onFileDropped(DropResult result) {
    setState(() {
      if (!_recentFiles.contains(result.filePath)) {
        _recentFiles.insert(0, result.filePath);
        if (_recentFiles.length > 10) {
          _recentFiles.removeLast();
        }
      }
    });

    switch (result.action) {
      case DropAction.seal:
        _navigateToSeal(result.filePath);
        break;
      case DropAction.verify:
        _navigateToVerify(result.filePath);
        break;
    }
  }

  void _navigateToSeal([String? filePath]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SealScreen(initialFilePath: filePath),
      ),
    );
  }

  void _navigateToVerify([String? filePath]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VerifyScreen(initialFilePath: filePath),
      ),
    );
  }

  void _navigateToExtract() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ExtractScreen()),
    );
  }

  void _navigateToSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  Future<void> _onTapDropZone() async {
    final fileService = context.read<FileService>();
    final path = await fileService.pickFile();
    if (path != null) {
      final isZgl = fileService.isZegelFile(path);
      _onFileDropped(DropResult(
        filePath: path,
        action: isZgl ? DropAction.verify : DropAction.seal,
      ));
    }
  }

  void _onBottomNavTap(int index) {
    setState(() => _selectedIndex = index);

    switch (index) {
      case 0:
        // Home - already here
        break;
      case 1:
        _navigateToSeal();
        break;
      case 2:
        _navigateToVerify();
        break;
      case 3:
        _navigateToExtract();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fileService = context.read<FileService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.homeTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.settingsTitle,
            onPressed: _navigateToSettings,
          ),
        ],
      ),
      drawer: _buildDrawer(context, l10n),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Drag and drop zone
            DropZone(
              onFileDropped: _onFileDropped,
              onTap: _onTapDropZone,
            ),
            const SizedBox(height: 24),
            // Recent files list
            if (_recentFiles.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.history,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Recent Files',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _recentFiles.length,
                  itemBuilder: (context, index) {
                    final path = _recentFiles[index];
                    final name = fileService.getFileName(path);
                    final isZgl = fileService.isZegelFile(path);

                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isZgl ? Icons.verified_user : Icons.description,
                        color: isZgl
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: Icon(
                        isZgl ? Icons.shield : Icons.lock,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      onTap: () {
                        if (isZgl) {
                          _navigateToVerify(path);
                        } else {
                          _navigateToSeal(path);
                        }
                      },
                    );
                  },
                ),
              ),
            ] else
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant
                            .withOpacity(0.3),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Drop a file above to get started',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onBottomNavTap,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.appTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.lock_outline),
            selectedIcon: const Icon(Icons.lock),
            label: l10n.sealAction,
          ),
          NavigationDestination(
            icon: const Icon(Icons.verified_user_outlined),
            selectedIcon: const Icon(Icons.verified_user),
            label: l10n.verifyAction,
          ),
          NavigationDestination(
            icon: const Icon(Icons.file_download_outlined),
            selectedIcon: const Icon(Icons.file_download),
            label: l10n.extractAction,
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(
                  Icons.shield,
                  size: 48,
                  color: theme.colorScheme.onPrimary,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.appTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Tamper-Proof Container Format',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimary.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.lock),
            title: Text(l10n.sealAction),
            onTap: () {
              Navigator.of(context).pop();
              _navigateToSeal();
            },
          ),
          ListTile(
            leading: const Icon(Icons.verified_user),
            title: Text(l10n.verifyAction),
            onTap: () {
              Navigator.of(context).pop();
              _navigateToVerify();
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_download),
            title: Text(l10n.extractAction),
            onTap: () {
              Navigator.of(context).pop();
              _navigateToExtract();
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
            child: Text(
              'Advanced',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.content_cut),
            title: Text(l10n.redactAction),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RedactScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: Text(l10n.splitKeyAction),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SplitKeyScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.visibility),
            title: Text(l10n.disclosureAction),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DiscloseScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: Text(l10n.settingsTitle),
            onTap: () {
              Navigator.of(context).pop();
              _navigateToSettings();
            },
          ),
        ],
      ),
    );
  }
}
