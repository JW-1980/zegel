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
import 'batch_screen.dart';
import 'classification_screen.dart';
import 'manifest_screen.dart';
import 'excerpt_screen.dart';
import 'provenance_screen.dart';
import 'credential_screen.dart';
import 'contract_screen.dart';

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
                            .withValues(alpha:0.3),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Drop a file above to get started',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha:0.5),
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

  void _navigateTo(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Widget _buildDrawer(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);

    Widget sectionHeader(String title) {
      return Padding(
        padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
        child: Text(
          title,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );
    }

    Widget drawerItem(IconData icon, String title, VoidCallback onTap) {
      return ListTile(
        leading: Icon(icon),
        title: Text(title),
        dense: true,
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
      );
    }

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
                    color: theme.colorScheme.onPrimary.withValues(alpha:0.8),
                  ),
                ),
              ],
            ),
          ),

          // Core
          sectionHeader(l10n.drawerCoreSection),
          drawerItem(Icons.lock, l10n.sealAction, _navigateToSeal),
          drawerItem(
              Icons.verified_user, l10n.verifyAction, _navigateToVerify),
          drawerItem(
              Icons.file_download, l10n.extractAction, _navigateToExtract),

          const Divider(),

          // Security
          sectionHeader(l10n.drawerSecuritySection),
          drawerItem(Icons.content_cut, l10n.redactAction,
              () => _navigateTo(const RedactScreen())),
          drawerItem(Icons.key, l10n.splitKeyAction,
              () => _navigateTo(const SplitKeyScreen())),
          drawerItem(Icons.security, l10n.classificationTitle,
              () => _navigateTo(const ClassificationScreen())),

          const Divider(),

          // Disclosure
          sectionHeader(l10n.drawerDisclosureSection),
          drawerItem(Icons.visibility, l10n.disclosureAction,
              () => _navigateTo(const DiscloseScreen())),
          drawerItem(Icons.receipt_long, l10n.excerptTitle,
              () => _navigateTo(const ExcerptScreen())),

          const Divider(),

          // Advanced
          sectionHeader(l10n.drawerAdvancedSection),
          drawerItem(Icons.batch_prediction, l10n.batchOperationsTitle,
              () => _navigateTo(const BatchScreen())),
          drawerItem(Icons.list_alt, l10n.manifestTitle,
              () => _navigateTo(const ManifestScreen())),
          drawerItem(Icons.description, l10n.contractTitle,
              () => _navigateTo(const ContractScreen())),
          drawerItem(Icons.school, l10n.credentialTitle,
              () => _navigateTo(const CredentialScreen())),
          drawerItem(Icons.history, l10n.provenanceTitle,
              () => _navigateTo(const ProvenanceScreen())),

          const Divider(),

          // Settings
          drawerItem(
              Icons.settings, l10n.settingsTitle, _navigateToSettings),
        ],
      ),
    );
  }
}
