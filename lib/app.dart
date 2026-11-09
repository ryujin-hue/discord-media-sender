import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_theme.dart';
import 'core/constants.dart';
import 'providers/config_providers.dart';
import 'root_shell.dart';
import 'screens/onboarding_screen.dart';

/// The root widget of Discord Media Sender 2.0.
class DiscordMediaSenderApp extends ConsumerWidget {
  const DiscordMediaSenderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsProvider);

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      builder: (BuildContext context, Widget? child) {
        // Keep the layout readable on very large system font scales.
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.3,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: settings.onboardingDone
          ? const RootShell()
          : const OnboardingScreen(),
    );
  }
}
