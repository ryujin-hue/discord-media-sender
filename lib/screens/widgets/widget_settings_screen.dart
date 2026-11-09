import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/models.dart';
import '../../providers/config_providers.dart';
import '../../services/widget_bridge.dart';
import '../../widgets/common.dart';

/// Configures the home screen widget and the floating overlay widget.
class WidgetSettingsScreen extends ConsumerWidget {
  const WidgetSettingsScreen({super.key});

  /// The values used before the database answered with the stored settings.
  static final WidgetSettings _fallback = WidgetSettings(
    homeWidgetEnabled: false,
    floatingWidgetEnabled: false,
    floatingX: 0,
    floatingY: 0,
    showSpeed: true,
    compactMode: false,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WidgetSettings settings =
        ref.watch(widgetSettingsProvider).value ?? _fallback;

    return Scaffold(
      appBar: AppBar(title: const Text('Screen widgets')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: <Widget>[
            _HomeWidgetSection(settings: settings),
            const SizedBox(height: 14),
            _FloatingWidgetSection(settings: settings),
            const SizedBox(height: 14),
            _OptionsSection(settings: settings),
            const SizedBox(height: 14),
            const _WidgetNoteCard(),
          ],
        ),
      ),
    );
  }
}

/// The home screen widget section.
class _HomeWidgetSection extends ConsumerWidget {
  const _HomeWidgetSection({required this.settings});

  final WidgetSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return SectionCard(
      title: 'Home screen widget',
      subtitle: 'Live upload state on the launcher',
      icon: Icons.widgets_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable home screen widget'),
            subtitle: const Text(
              'Shows the real upload state of the running engine',
            ),
            value: settings.homeWidgetEnabled,
            onChanged: (bool value) {
              _save(
                context,
                ref,
                settings.copyWith(
                  homeWidgetEnabled: value,
                  updatedAt: DateTime.now(),
                ),
                value
                    ? 'Home screen widget enabled'
                    : 'Home screen widget disabled',
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            'The widget mirrors the live upload state: the current file, the '
            'progress, the transfer speed and the number of finished files. '
            'It also offers Start, Pause, Resume and Open dashboard buttons.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'The widget itself has to be added from the launcher: long press '
            'the home screen, open the widget picker and choose '
            '"Discord Media Sender Upload Widget".',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The floating overlay section.
class _FloatingWidgetSection extends ConsumerWidget {
  const _FloatingWidgetSection({required this.settings});

  final WidgetSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return SectionCard(
      title: 'Floating overlay',
      subtitle: 'A small window above every other app',
      icon: Icons.picture_in_picture_alt_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable floating overlay'),
            subtitle: const Text(
              'Requires the "Display over other apps" permission',
            ),
            value: settings.floatingWidgetEnabled,
            onChanged: (bool value) => _toggle(context, ref, value),
          ),
          const SizedBox(height: 8),
          Text(
            'The overlay follows the same upload state as the home screen '
            'widget and can be stopped again from this screen.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool value) async {
    if (value) {
      final bool granted = await WidgetBridge.instance.hasOverlayPermission();
      if (!context.mounted) return;
      if (!granted) {
        final bool openSettings = await _showPermissionDialog(context);
        if (openSettings) {
          await WidgetBridge.instance.openOverlaySettings();
        }
        if (!context.mounted) return;
        showAppSnack(
          context,
          'Grant the "Display over other apps" permission to use the overlay',
          isError: true,
        );
        return;
      }
    }

    final bool applied = await WidgetBridge.instance.setOverlayEnabled(value);
    if (!context.mounted) return;
    if (!applied) {
      showAppSnack(
        context,
        'The floating overlay could not be updated',
        isError: true,
      );
      return;
    }
    await AppDatabase.instance.saveWidgetSettings(
      settings.copyWith(
        floatingWidgetEnabled: value,
        updatedAt: DateTime.now(),
      ),
    );
    ref.invalidate(widgetSettingsProvider);
    if (!context.mounted) return;
    showAppSnack(
      context,
      value ? 'Floating overlay enabled' : 'Floating overlay disabled',
      isSuccess: true,
    );
  }

  Future<bool> _showPermissionDialog(BuildContext context) async {
    final bool? open = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Overlay permission needed'),
          content: const Text(
            'The floating overlay is drawn above every other application. '
            'Android therefore asks for the "Display over other apps" '
            'permission before the overlay can be shown.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Open settings'),
            ),
          ],
        );
      },
    );
    return open ?? false;
  }
}

/// The appearance options shared by both widgets.
class _OptionsSection extends ConsumerWidget {
  const _OptionsSection({required this.settings});

  final WidgetSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      title: 'Options',
      subtitle: 'Applied to the widget and the overlay',
      icon: Icons.tune_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show upload speed'),
            subtitle: const Text('Displays the current transfer rate'),
            value: settings.showSpeed,
            onChanged: (bool value) {
              _save(
                context,
                ref,
                settings.copyWith(showSpeed: value, updatedAt: DateTime.now()),
                null,
              );
            },
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Compact mode'),
            subtitle: const Text('Uses a smaller layout with fewer details'),
            value: settings.compactMode,
            onChanged: (bool value) {
              _save(
                context,
                ref,
                settings.copyWith(
                  compactMode: value,
                  updatedAt: DateTime.now(),
                ),
                null,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The safety note below the widget options.
class _WidgetNoteCard extends StatelessWidget {
  const _WidgetNoteCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SectionCard(
      title: 'Before you enable the overlay',
      icon: Icons.shield_outlined,
      child: Text(
        'The floating overlay requires the "Display over other apps" '
        'permission in the Android system settings. It can always be stopped '
        'again from this screen. Credentials are never shown in a widget: bot '
        'tokens and webhook URLs stay in the secure store.',
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

/// Persists the widget settings and refreshes the provider.
Future<void> _save(
  BuildContext context,
  WidgetRef ref,
  WidgetSettings settings,
  String? message,
) async {
  await AppDatabase.instance.saveWidgetSettings(settings);
  ref.invalidate(widgetSettingsProvider);
  if (!context.mounted) return;
  if (message != null) {
    showAppSnack(context, message, isSuccess: true);
  }
}
