import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/secure_store.dart';
import '../../data/database.dart';
import '../../providers/config_providers.dart';
import '../../widgets/common.dart';

/// The application preferences plus the destructive data maintenance actions.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: <Widget>[
            _ThemeSection(settings: settings),
            const SizedBox(height: 14),
            _UploadSection(settings: settings),
            const SizedBox(height: 14),
            _RecoverySection(settings: settings),
            const SizedBox(height: 14),
            _WidgetSection(settings: settings),
            const SizedBox(height: 14),
            const _DataSection(),
            const SizedBox(height: 14),
            const _AboutSection(),
          ],
        ),
      ),
    );
  }
}

/// The appearance preferences.
class _ThemeSection extends ConsumerWidget {
  const _ThemeSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      title: 'Appearance',
      subtitle: 'Choose how the interface is rendered',
      icon: Icons.palette_rounded,
      child: SegmentedButton<ThemeMode>(
        segments: const <ButtonSegment<ThemeMode>>[
          ButtonSegment<ThemeMode>(
            value: ThemeMode.system,
            label: Text('System'),
          ),
          ButtonSegment<ThemeMode>(
            value: ThemeMode.light,
            label: Text('Light'),
          ),
          ButtonSegment<ThemeMode>(value: ThemeMode.dark, label: Text('Dark')),
        ],
        selected: <ThemeMode>{settings.themeMode},
        showSelectedIcon: false,
        onSelectionChanged: (Set<ThemeMode> selection) {
          ref.read(settingsProvider.notifier).setThemeMode(selection.first);
        },
      ),
    );
  }
}

/// The upload related preferences.
class _UploadSection extends ConsumerWidget {
  const _UploadSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final int maxFileMb = settings.maxFileMb.clamp(1, 500);

    return SectionCard(
      title: 'Uploads',
      subtitle: 'Limits applied before anything is sent to Discord',
      icon: Icons.cloud_upload_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Maximum file size',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text('$maxFileMb MB', style: theme.textTheme.titleSmall),
            ],
          ),
          Slider(
            value: maxFileMb.toDouble(),
            min: 1,
            max: 500,
            divisions: 499,
            label: '$maxFileMb MB',
            onChanged: (double value) {
              ref.read(settingsProvider.notifier).setMaxFileMb(value.round());
            },
          ),
          Text(
            'Files larger than this limit are skipped instead of being uploaded.',
            style: theme.textTheme.bodySmall,
          ),
          const Divider(height: 26),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Check for updates automatically'),
            subtitle: const Text('Look for new releases when the app starts'),
            value: settings.autoUpdate,
            onChanged: (bool value) {
              ref.read(settingsProvider.notifier).setAutoUpdate(value);
            },
          ),
          const SizedBox(height: 10),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Release channel'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: settings.releaseChannel == 'beta' ? 'beta' : 'stable',
                isExpanded: true,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                    value: 'stable',
                    child: Text('Stable'),
                  ),
                  DropdownMenuItem<String>(value: 'beta', child: Text('Beta')),
                ],
                onChanged: (String? value) {
                  if (value == null) return;
                  ref.read(settingsProvider.notifier).setReleaseChannel(value);
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Beta builds are published as GitHub pre-releases and may be '
            'less stable than the stable channel.',
            style: theme.textTheme.bodySmall,
          ),
          const Divider(height: 26),
          Row(
            children: <Widget>[
              Expanded(
                child: Text('Bandwidth cap', style: theme.textTheme.bodyMedium),
              ),
              Text(
                settings.bandwidthCapKb <= 0
                    ? 'Unlimited'
                    : '${settings.bandwidthCapKb} KB/s',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          Slider(
            value: settings.bandwidthCapKb.clamp(0, 2048).toDouble(),
            min: 0,
            max: 2048,
            divisions: 64,
            label: settings.bandwidthCapKb <= 0
                ? 'Unlimited'
                : '${settings.bandwidthCapKb} KB/s',
            onChanged: (double value) {
              // The slider works in steps of 32 KB/s so that the value stays
              // readable; zero means unlimited.
              final int kilobytes = (value / 32).round() * 32;
              ref.read(settingsProvider.notifier).setBandwidthCapKb(kilobytes);
            },
          ),
          Text(
            'Limits the transfer rate of every upload. Discord rate limits '
            'still apply on top of this.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The behaviour of a cold start that finds pending work.
class _RecoverySection extends ConsumerWidget {
  const _RecoverySection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return SectionCard(
      title: 'Recovery',
      subtitle: 'What happens to a queue that was interrupted',
      icon: Icons.restore_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Safe resume', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(
            'Applies when the app is opened while uploads are still pending.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final SafeResumePolicy policy in SafeResumePolicy.values)
                ChoiceChip(
                  label: Text(policy.label),
                  selected: settings.safeResume == policy,
                  onSelected: (bool selected) {
                    if (!selected) return;
                    ref.read(settingsProvider.notifier).setSafeResume(policy);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The appearance of the home screen widget and the floating overlay.
class _WidgetSection extends ConsumerWidget {
  const _WidgetSection({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return SectionCard(
      title: 'Widgets',
      subtitle: 'Home screen widget and floating overlay',
      icon: Icons.widgets_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Widget density', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final WidgetDensity density in WidgetDensity.values)
                ChoiceChip(
                  label: Text(density.label),
                  selected: settings.widgetDensity == density,
                  onSelected: (bool selected) {
                    if (!selected) return;
                    ref
                        .read(settingsProvider.notifier)
                        .setWidgetDensity(density);
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Normal shows three lines, compact shows two.',
            style: theme.textTheme.bodySmall,
          ),
          const Divider(height: 26),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Overlay auto-hide',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                settings.overlayAutoHideSeconds <= 0
                    ? 'Always visible'
                    : '${settings.overlayAutoHideSeconds}s',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          Slider(
            value: settings.overlayAutoHideSeconds.clamp(0, 300).toDouble(),
            min: 0,
            max: 300,
            divisions: 60,
            label: settings.overlayAutoHideSeconds <= 0
                ? 'Always visible'
                : '${settings.overlayAutoHideSeconds}s',
            onChanged: (double value) {
              ref
                  .read(settingsProvider.notifier)
                  .setOverlayAutoHideSeconds(value.round());
            },
          ),
          Text(
            'Hides the overlay while the engine is idle. A running upload is '
            'never cancelled by the overlay.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The destructive data maintenance actions.
class _DataSection extends ConsumerWidget {
  const _DataSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return SectionCard(
      title: 'Data',
      subtitle: 'These actions cannot be undone',
      icon: Icons.storage_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _DataAction(
            icon: Icons.history_rounded,
            title: 'Clear upload history',
            subtitle: 'Deletes every upload record from the database',
            onTap: () => _clearHistory(context, ref),
          ),
          const Divider(height: 20),
          _DataAction(
            icon: Icons.timeline_rounded,
            title: 'Clear activity log',
            subtitle: 'Removes the live activity timeline',
            onTap: () => _clearActivityLog(context, ref),
          ),
          const Divider(height: 20),
          _DataAction(
            icon: Icons.receipt_long_rounded,
            title: 'Clear response log',
            subtitle: 'Removes the recorded Discord delivery responses',
            onTap: () => _clearResponseLog(context, ref),
          ),
          const Divider(height: 20),
          _DataAction(
            icon: Icons.key_off_rounded,
            title: 'Clear saved credentials',
            subtitle: 'Every destination has to be configured again',
            danger: true,
            onTap: () => _clearCredentials(context, ref),
          ),
          const SizedBox(height: 10),
          Text(
            'Credentials are stored in the Android Keystore. Clearing them '
            'removes every bot token and webhook URL from the device.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _clearHistory(BuildContext context, WidgetRef ref) async {
    final bool confirmed = await showConfirmDialog(
      context,
      title: 'Clear upload history',
      message:
          'All recorded uploads will be deleted from this device. This cannot '
          'be undone.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!confirmed) return;
    await AppDatabase.instance.clearHistory();
    ref.invalidate(historyProvider);
    if (!context.mounted) return;
    showAppSnack(context, 'Upload history cleared', isSuccess: true);
  }

  Future<void> _clearActivityLog(BuildContext context, WidgetRef ref) async {
    final bool confirmed = await showConfirmDialog(
      context,
      title: 'Clear activity log',
      message:
          'The live activity timeline will be deleted. This cannot be undone.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!confirmed) return;
    await AppDatabase.instance.clearLiveEvents();
    ref.invalidate(liveEventsProvider);
    if (!context.mounted) return;
    showAppSnack(context, 'Activity log cleared', isSuccess: true);
  }

  Future<void> _clearResponseLog(BuildContext context, WidgetRef ref) async {
    final bool confirmed = await showConfirmDialog(
      context,
      title: 'Clear response log',
      message:
          'The recorded Discord delivery responses will be deleted from the '
          'activity log. This cannot be undone.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!confirmed) return;
    final db = await AppDatabase.instance.database;
    await db.delete(
      'live_activity_events',
      where: 'type IN (?, ?, ?)',
      whereArgs: <Object?>[
        'delivery_succeeded',
        'upload_failed',
        'retry_scheduled',
      ],
    );
    ref.invalidate(liveEventsProvider);
    if (!context.mounted) return;
    showAppSnack(context, 'Response log cleared', isSuccess: true);
  }

  Future<void> _clearCredentials(BuildContext context, WidgetRef ref) async {
    final bool confirmed = await showConfirmDialog(
      context,
      title: 'Clear saved credentials',
      message:
          'Every bot token and webhook URL will be removed from the secure '
          'store. All destinations have to be configured again before files '
          'can be uploaded.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!confirmed) return;
    await SecureStore.instance.deleteAll();
    ref.invalidate(credentialProfilesProvider);
    ref.invalidate(destinationsProvider);
    if (!context.mounted) return;
    showAppSnack(
      context,
      'Credentials cleared — reconfigure your destinations',
      isSuccess: true,
    );
  }
}

/// A single destructive action of the data section.
class _DataAction extends StatelessWidget {
  const _DataAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = danger
        ? AppConstants.colorError
        : theme.colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: theme.textTheme.bodySmall),
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

/// The build information of the running application.
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SectionCard(
      title: 'About',
      subtitle: AppConstants.appName,
      icon: Icons.info_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MetricRow(label: 'Version', value: AppConstants.appVersion),
          MetricRow(label: 'Application id', value: AppConstants.applicationId),
          MetricRow(label: 'Repository', value: AppConstants.githubRepoUrl),
          const SizedBox(height: 10),
          Text(
            'Updates are published on GitHub and verified against the SHA-256 '
            'checksum of the release. A new build is only offered when it '
            'carries the same application id and a higher version code.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Local database: ${AppConstants.databaseName} '
            '(schema version ${AppConstants.databaseVersion}). It is stored '
            'in the private application folder and never leaves the device.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
