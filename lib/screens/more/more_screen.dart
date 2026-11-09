import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers/config_providers.dart';
import '../../root_shell.dart';
import '../../widgets/common.dart';
import '../analytics/analytics_screen.dart';
import '../archive/archive_screen.dart';
import '../auto_upload/auto_upload_screen.dart';
import '../credentials/credentials_screen.dart';
import '../duplicates/duplicate_manager_screen.dart';
import '../history/history_screen.dart';
import '../settings/settings_screen.dart';
import '../update/update_manager_screen.dart';
import '../widgets/widget_settings_screen.dart';

/// The hub screen that links to every secondary feature of the application.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final int historyCount = ref.watch(historyProvider).value?.length ?? 0;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: <Widget>[
            Text('More', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 2),
            Text(
              'Everything that does not fit in the main tabs',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SectionCard(
              title: 'Insights',
              icon: Icons.insights_rounded,
              child: Column(
                children: <Widget>[
                  _MoreTile(
                    icon: Icons.query_stats_rounded,
                    title: 'Analytics Center',
                    subtitle:
                        'Upload trends, success rates and destination health',
                    onTap: () => openPage(context, const AnalyticsScreen()),
                  ),
                  const _MoreDivider(),
                  _MoreTile(
                    icon: Icons.schedule_send_rounded,
                    title: 'Auto Upload',
                    subtitle: 'Watched folders and automatic upload rules',
                    onTap: () => openPage(context, const AutoUploadScreen()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Library management',
              icon: Icons.folder_special_rounded,
              child: Column(
                children: <Widget>[
                  _MoreTile(
                    icon: Icons.key_rounded,
                    title: 'Credential Manager',
                    subtitle: 'Bot tokens, webhooks and channel profiles',
                    onTap: () => openPage(context, const CredentialsScreen()),
                  ),
                  const _MoreDivider(),
                  _MoreTile(
                    icon: Icons.copy_all_rounded,
                    title: 'Duplicate Manager',
                    subtitle: 'Review detected duplicates and their hashes',
                    onTap: () =>
                        openPage(context, const DuplicateManagerScreen()),
                  ),
                  const _MoreDivider(),
                  _MoreTile(
                    icon: Icons.inventory_2_rounded,
                    title: 'Archive Manager',
                    subtitle: 'Archived files, categories and restore actions',
                    onTap: () => openPage(context, const ArchiveScreen()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Tools',
              icon: Icons.build_rounded,
              child: Column(
                children: <Widget>[
                  _MoreTile(
                    icon: Icons.widgets_rounded,
                    title: 'Screen Widgets',
                    subtitle: 'Home screen widget and floating overlay',
                    onTap: () =>
                        openPage(context, const WidgetSettingsScreen()),
                  ),
                  const _MoreDivider(),
                  _MoreTile(
                    icon: Icons.system_update_rounded,
                    title: 'Update Manager',
                    subtitle: 'Check, download and install new releases',
                    onTap: () => openPage(context, const UpdateManagerScreen()),
                  ),
                  const _MoreDivider(),
                  _MoreTile(
                    icon: Icons.history_rounded,
                    title: 'Upload History',
                    subtitle: historyCount == 0
                        ? 'No uploads recorded yet'
                        : '$historyCount recorded upload${historyCount == 1 ? '' : 's'}',
                    onTap: () => openPage(context, const HistoryScreen()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Preferences',
              icon: Icons.tune_rounded,
              child: Column(
                children: <Widget>[
                  _MoreTile(
                    icon: Icons.settings_rounded,
                    title: 'Settings',
                    subtitle: 'Theme, upload limits, release channel and data',
                    onTap: () => openPage(context, const SettingsScreen()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'About',
              icon: Icons.info_outline_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  MetricRow(label: 'Version', value: AppConstants.appVersion),
                  MetricRow(
                    label: 'Application id',
                    value: AppConstants.applicationId,
                  ),
                  MetricRow(
                    label: 'Repository',
                    value: AppConstants.githubRepoUrl,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single navigation entry of the "More" screen.
class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 19, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

/// A thin separator between two navigation entries.
class _MoreDivider extends StatelessWidget {
  const _MoreDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.35),
    );
  }
}
