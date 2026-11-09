import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../data/database.dart';
import '../data/models.dart';

/// Theme and user preferences.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.onboardingDone = false,
    this.maxFileMb = AppConstants.defaultMaxFileMb,
    this.autoUpdate = true,
    this.batteryAsked = false,
    this.releaseChannel = 'stable',
  });

  final ThemeMode themeMode;
  final bool onboardingDone;
  final int maxFileMb;
  final bool autoUpdate;
  final bool batteryAsked;
  final String releaseChannel;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? onboardingDone,
    int? maxFileMb,
    bool? autoUpdate,
    bool? batteryAsked,
    String? releaseChannel,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      onboardingDone: onboardingDone ?? this.onboardingDone,
      maxFileMb: maxFileMb ?? this.maxFileMb,
      autoUpdate: autoUpdate ?? this.autoUpdate,
      batteryAsked: batteryAsked ?? this.batteryAsked,
      releaseChannel: releaseChannel ?? this.releaseChannel,
    );
  }
}

/// Holds the application preferences in `SharedPreferences`.
///
/// The preference keys are the ones used by the 1.0 build so that user
/// settings survive an in-place upgrade.
class SettingsNotifier extends Notifier<AppSettings> {
  SharedPreferences? _prefs;

  @override
  AppSettings build() {
    _prefs = null;
    unawaited(_load());
    return const AppSettings();
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    final String themeName =
        prefs.getString(AppConstants.prefThemeMode) ?? 'dark';
    state = AppSettings(
      themeMode: _themeFromName(themeName),
      onboardingDone: prefs.getBool(AppConstants.prefOnboardingDone) ?? false,
      maxFileMb:
          prefs.getInt(AppConstants.prefMaxFileMb) ??
          AppConstants.defaultMaxFileMb,
      autoUpdate: prefs.getBool(AppConstants.prefAutoUpdate) ?? true,
      batteryAsked: prefs.getBool(AppConstants.prefBatteryAsked) ?? false,
      releaseChannel: prefs.getString('set_release_channel') ?? 'stable',
    );
  }

  static ThemeMode _themeFromName(String name) {
    switch (name) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final SharedPreferences prefs =
        _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setString(AppConstants.prefThemeMode, mode.name);
  }

  Future<void> setOnboardingDone(bool value) async {
    state = state.copyWith(onboardingDone: value);
    final SharedPreferences prefs =
        _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setBool(AppConstants.prefOnboardingDone, value);
  }

  Future<void> setMaxFileMb(int value) async {
    state = state.copyWith(maxFileMb: value);
    final SharedPreferences prefs =
        _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setInt(AppConstants.prefMaxFileMb, value);
  }

  Future<void> setAutoUpdate(bool value) async {
    state = state.copyWith(autoUpdate: value);
    final SharedPreferences prefs =
        _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setBool(AppConstants.prefAutoUpdate, value);
  }

  Future<void> setBatteryAsked(bool value) async {
    state = state.copyWith(batteryAsked: value);
    final SharedPreferences prefs =
        _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setBool(AppConstants.prefBatteryAsked, value);
  }

  Future<void> setReleaseChannel(String channel) async {
    state = state.copyWith(releaseChannel: channel);
    final SharedPreferences prefs =
        _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setString('set_release_channel', channel);
  }
}

/// The application settings.
final NotifierProvider<SettingsNotifier, AppSettings> settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// The database instance.
final Provider<AppDatabase> databaseProvider = Provider<AppDatabase>(
  (Ref ref) => AppDatabase.instance,
);

/// The list of Discord destinations, refreshed on demand.
final FutureProvider<List<Destination>> destinationsProvider =
    FutureProvider<List<Destination>>((Ref ref) async {
      return AppDatabase.instance.listDestinations();
    });

/// The credential profiles.
final FutureProvider<List<CredentialProfile>> credentialProfilesProvider =
    FutureProvider<List<CredentialProfile>>((Ref ref) async {
      return AppDatabase.instance.listCredentialProfiles();
    });

/// The media library entries.
final FutureProvider<List<MediaLibraryEntry>> mediaLibraryProvider =
    FutureProvider<List<MediaLibraryEntry>>((Ref ref) async {
      return AppDatabase.instance.listMedia();
    });

/// The upload history.
final FutureProvider<List<UploadHistoryEntry>> historyProvider =
    FutureProvider<List<UploadHistoryEntry>>((Ref ref) async {
      return AppDatabase.instance.listHistory(limit: 500);
    });

/// The duplicate records.
final FutureProvider<List<DuplicateRecord>> duplicatesProvider =
    FutureProvider<List<DuplicateRecord>>((Ref ref) async {
      return AppDatabase.instance.listDuplicates();
    });

/// The archive records.
final FutureProvider<List<ArchiveRecord>> archiveProvider =
    FutureProvider<List<ArchiveRecord>>((Ref ref) async {
      return AppDatabase.instance.listArchiveRecords();
    });

/// The watched folders.
final FutureProvider<List<WatchedFolder>> watchedFoldersProvider =
    FutureProvider<List<WatchedFolder>>((Ref ref) async {
      return AppDatabase.instance.listWatchedFolders();
    });

/// The automatic upload rules.
final FutureProvider<List<AutoUploadRule>> autoUploadRulesProvider =
    FutureProvider<List<AutoUploadRule>>((Ref ref) async {
      return AppDatabase.instance.listAutoUploadRules();
    });

/// The live activity timeline.
final FutureProvider<List<LiveActivityEvent>> liveEventsProvider =
    FutureProvider<List<LiveActivityEvent>>((Ref ref) async {
      return AppDatabase.instance.listLiveEvents(limit: 120);
    });

/// The widget settings.
final FutureProvider<WidgetSettings> widgetSettingsProvider =
    FutureProvider<WidgetSettings>((Ref ref) async {
      return AppDatabase.instance.loadWidgetSettings();
    });

/// The dashboard preferences.
final FutureProvider<DashboardPreferences> dashboardPreferencesProvider =
    FutureProvider<DashboardPreferences>((Ref ref) async {
      return AppDatabase.instance.loadDashboardPreferences();
    });

/// Counts used by the dashboard tiles.
class DashboardCounts {
  const DashboardCounts({
    required this.total,
    required this.uploaded,
    required this.uploading,
    required this.pending,
    required this.failed,
    required this.duplicates,
    required this.archived,
    required this.bytesTransferred,
  });

  final int total;
  final int uploaded;
  final int uploading;
  final int pending;
  final int failed;
  final int duplicates;
  final int archived;
  final int bytesTransferred;
}

/// Aggregated dashboard counters.
final FutureProvider<DashboardCounts> dashboardCountsProvider =
    FutureProvider<DashboardCounts>((Ref ref) async {
      final AppDatabase db = AppDatabase.instance;
      final List<UploadHistoryEntry> history = await db.listHistory();
      final List<MediaLibraryEntry> media = await db.listMedia();
      final List<DistributionJob> jobs = await db.listJobs();

      int uploading = 0;
      int pending = 0;
      int failed = 0;
      int uploaded = 0;
      int bytes = 0;
      for (final UploadHistoryEntry entry in history) {
        if (entry.status == UploadStatus.completedKey) {
          bytes += entry.fileSize;
          uploaded++;
        }
        if (entry.status == UploadStatus.failedKey) failed++;
      }
      for (final DistributionJob job in jobs) {
        if (job.status == UploadStatus.uploadingKey) uploading++;
        if (job.status == UploadStatus.pendingKey) pending++;
      }
      final List<DuplicateRecord> duplicates = await db.listDuplicates();

      return DashboardCounts(
        total: media.length,
        uploaded: uploaded,
        uploading: uploading,
        pending: pending,
        failed: failed,
        duplicates: duplicates.length,
        archived: media.where((MediaLibraryEntry m) => m.isArchived).length,
        bytesTransferred: bytes,
      );
    });
