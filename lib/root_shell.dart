import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants.dart';
import 'screens/distribution/distribution_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/library/library_screen.dart';
import 'screens/more/more_screen.dart';
import 'screens/upload/upload_screen.dart';

/// The five primary destinations of the application.
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _index = 0;

  static const List<Widget> _screens = <Widget>[
    HomeScreen(),
    UploadScreen(),
    LibraryScreen(),
    DistributionScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outline
                  .withValues(alpha: 0.35),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (int value) => setState(() => _index = value),
          destinations: const <NavigationDestination>[
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.cloud_upload_outlined),
              selectedIcon: Icon(Icons.cloud_upload_rounded),
              label: 'Upload',
            ),
            NavigationDestination(
              icon: Icon(Icons.perm_media_outlined),
              selectedIcon: Icon(Icons.perm_media_rounded),
              label: 'Library',
            ),
            NavigationDestination(
              icon: Icon(Icons.hub_outlined),
              selectedIcon: Icon(Icons.hub_rounded),
              label: 'Distribution',
            ),
            NavigationDestination(
              icon: Icon(Icons.more_horiz_rounded),
              selectedIcon: Icon(Icons.more_horiz_rounded),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}

/// Convenience helper used by the screens to open a sub page.
Future<void> openPage(BuildContext context, Widget page) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (BuildContext context) => page),
  );
}

/// Shows a page as a modal bottom sheet.
Future<void> openSheet(BuildContext context, Widget sheet) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (BuildContext context) => sheet,
  );
}

/// The accent colours used across the navigation.
const List<Color> kNavAccents = <Color>[
  AppConstants.colorPrimary,
  AppConstants.colorSuccess,
  AppConstants.colorWarning,
  AppConstants.colorError,
];
