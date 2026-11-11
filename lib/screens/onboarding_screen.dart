import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../providers/config_providers.dart';
import '../widgets/brand.dart';

/// The first-run wizard that introduces the app and collects the minimum
/// configuration needed to start sending.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<Widget> _pages = <Widget>[
    _OnboardingPage(
      icon: Icons.cloud_upload_rounded,
      title: 'Send media to Discord',
      body:
          'Upload files, folders and ZIP archives straight to a Discord webhook '
          'or bot, with resumable queues and live progress.',
    ),
    _OnboardingPage(
      icon: Icons.copy_all_rounded,
      title: 'Never upload the same file twice',
      body:
          'Every file is hashed with SHA-256. Duplicates are detected per '
          'destination, so a file sent to one server is still tracked as new '
          'for another one.',
    ),
    _OnboardingPage(
      icon: Icons.widgets_rounded,
      title: 'Monitor without opening the app',
      body:
          'Add the home screen widget or the floating overlay to watch uploads '
          'and pause or resume them from anywhere.',
    ),
    _OnboardingPage(
      icon: Icons.lock_rounded,
      title: 'Your credentials stay on the device',
      body:
          'Bot tokens and webhook URLs are stored in Android Keystore-backed '
          'secure storage. They are never written to the database, never '
          'included in analytics exports and never shown in widgets.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(settingsProvider.notifier).setOnboardingDone(true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isLast = _page == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: BrandLockup(size: 34, title: 'Discord Media Sender'),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (int index) => setState(() => _page = index),
                itemBuilder: (BuildContext context, int index) => _pages[index],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (int i = 0; i < _pages.length; i++)
                  Container(
                    width: i == _page ? 20 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == _page
                          ? AppConstants.colorPrimary
                          : AppConstants.colorBorder,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Row(
                children: <Widget>[
                  if (_page > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _controller.previousPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                  if (_page > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () async {
                        if (isLast) {
                          await _finish();
                        } else {
                          await _controller.nextPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                          );
                        }
                      },
                      child: Text(isLast ? 'Get started' : 'Next'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                'Version ${AppConstants.appVersion}',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[
                  AppConstants.colorPrimary,
                  AppConstants.colorSuccess,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(icon, size: 44, color: Colors.white),
          ),
          const SizedBox(height: 28),
          Text(
            title,
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 26),
          const _FeatureLine(
            icon: Icons.check_circle_rounded,
            text: 'Independent queues per destination',
          ),
          const _FeatureLine(
            icon: Icons.check_circle_rounded,
            text: 'HTTP 429 handling with automatic retry',
          ),
          const _FeatureLine(
            icon: Icons.check_circle_rounded,
            text: 'Real analytics, no sample data',
          ),
        ],
      ),
    );
  }
}

class _FeatureLine extends StatelessWidget {
  const _FeatureLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 16, color: AppConstants.colorSuccess),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// Formats a byte count for the onboarding summary.
String onboardingBytes(int bytes) => Formatters.bytes(bytes);
