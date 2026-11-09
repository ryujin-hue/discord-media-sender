import 'package:discord_media_sender/core/app_theme.dart';
import 'package:discord_media_sender/core/constants.dart';
import 'package:discord_media_sender/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StatusStyle', () {
    test('maps an upload status to a label', () {
      expect(
        StatusStyle.forUploadStatus(UploadStatus.completedKey).label,
        'Uploaded',
      );
      expect(
        StatusStyle.forUploadStatus(UploadStatus.failedKey).label,
        'Failed',
      );
      expect(
        StatusStyle.forUploadStatus(UploadStatus.pendingKey).label,
        'Pending',
      );
    });

    test('maps a media status to a label', () {
      expect(
        StatusStyle.forMediaStatus(MediaStatus.duplicateDetectedKey).label,
        'Duplicate',
      );
      expect(
        StatusStyle.forMediaStatus(MediaStatus.archivedKey).label,
        'Archived',
      );
    });
  });

  group('AppTheme', () {
    test('builds a dark theme with the 2.0 palette', () {
      final ThemeData theme = AppTheme.dark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, AppConstants.colorPrimary);
      expect(theme.colorScheme.secondary, AppConstants.colorSuccess);
      expect(theme.scaffoldBackgroundColor, AppConstants.colorBackground);
    });

    test('builds a light theme', () {
      final ThemeData theme = AppTheme.light();
      expect(theme.brightness, Brightness.light);
      expect(theme.useMaterial3, isTrue);
    });
  });

  testWidgets('StatTile renders its value and label', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatTile(
            label: 'Uploaded',
            value: '42',
            icon: Icons.check_circle_rounded,
          ),
        ),
      ),
    );

    expect(find.text('42'), findsOneWidget);
    expect(find.text('Uploaded'), findsOneWidget);
  });

  testWidgets('EmptyState renders its message', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.inbox_rounded,
            title: 'Nothing here',
            message: 'Add a destination to get started.',
          ),
        ),
      ),
    );

    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('Add a destination to get started.'), findsOneWidget);
  });
}
