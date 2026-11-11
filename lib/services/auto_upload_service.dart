import 'dart:async';

import '../core/constants.dart';
import '../data/database.dart';
import '../data/models.dart';
import 'media_service.dart';
import 'quiet_hours_service.dart';
import 'upload_engine.dart';

/// The result of scanning the watched folders.
class AutoScanResult {
  const AutoScanResult({
    required this.newFiles,
    required this.duplicates,
    required this.foldersScanned,
  });

  final List<MediaCandidate> newFiles;
  final int duplicates;
  final int foldersScanned;
}

/// Implements Smart Auto Upload: folder monitoring, rules and scheduling.
class AutoUploadService {
  AutoUploadService._();

  static final AutoUploadService instance = AutoUploadService._();

  final AppDatabase _db = AppDatabase.instance;
  final MediaService _media = MediaService.instance;

  /// Scans every enabled watched folder and returns the new files.
  ///
  /// The last scan time of each folder is used so that the same file is not
  /// picked up twice by consecutive scans.
  Future<AutoScanResult> scan({bool dryRun = false}) async {
    final List<WatchedFolder> folders = await _db.listWatchedFolders();
    final List<MediaCandidate> newFiles = <MediaCandidate>[];
    int duplicates = 0;
    int scanned = 0;

    for (final WatchedFolder folder in folders) {
      if (!folder.enabled) continue;
      scanned++;

      final List<MediaCandidate> found = await _media.scanFolder(
        folder.path,
        recursive: folder.recursive,
        include: folder.includePatterns,
        exclude: folder.excludePatterns,
        maxFileMb: folder.maxFileMb,
      );

      for (final MediaCandidate candidate in found) {
        final MediaLibraryEntry? known = await _db.mediaByPath(candidate.path);
        if (known != null) continue;
        newFiles.add(candidate);
      }

      if (!dryRun) {
        await _db.upsertWatchedFolder(
          folder.copyWith(lastScanAt: DateTime.now()),
        );
      }
    }

    return AutoScanResult(
      newFiles: newFiles,
      duplicates: duplicates,
      foldersScanned: scanned,
    );
  }

  /// Runs the enabled automatic rules over the new files found by [scan].
  ///
  /// Fully automatic rules upload immediately, semi-automatic rules wait for
  /// the user to confirm in the app and manual rules are only recorded.
  Future<int> applyRules(AutoScanResult scanResult) async {
    final List<AutoUploadRule> rules = await _db.listAutoUploadRules();
    final List<Destination> destinations = await _db.listDestinations();
    int uploaded = 0;

    for (final AutoUploadRule rule in rules) {
      if (!rule.enabled) continue;
      if (rule.mode != AutoUploadMode.fullyAutomatic.key) continue;
      if (!_isWithinSchedule(rule)) continue;

      final List<String> targetIds = rule.destinationIds;
      // A destination inside its quiet hours is skipped by the automatic
      // upload. The rule still runs for the other destinations.
      final List<String> quiet = await QuietHoursService.instance
          .destinationsInQuietHours();
      final List<Destination> targets = destinations
          .where(
            (Destination d) =>
                targetIds.contains(d.id) && d.enabled && !quiet.contains(d.id),
          )
          .toList();
      if (targets.isEmpty) continue;

      final List<MediaCandidate> candidates = scanResult.newFiles
          .where((MediaCandidate c) => _matchesRule(rule, c))
          .toList();
      if (candidates.isEmpty) continue;

      await UploadEngine.instance.enqueue(
        candidates,
        options: EnqueueOptions(
          destinations: targets,
          distributionMode: DistributionMode.broadcast,
          duplicatePolicy: DuplicatePolicy.fromKey(rule.duplicatePolicy),
          priority: rule.priority,
          maxFileMb: rule.maxFileMb,
        ),
      );
      uploaded += candidates.length;
    }

    return uploaded;
  }

  /// Returns the files that are waiting for user confirmation.
  Future<List<MediaCandidate>> pendingSemiAutomatic() async {
    final List<AutoUploadRule> rules = await _db.listAutoUploadRules();
    if (!rules.any(
      (AutoUploadRule r) =>
          r.enabled && r.mode == AutoUploadMode.semiAutomatic.key,
    )) {
      return <MediaCandidate>[];
    }
    final AutoScanResult pendingScan = await scan(dryRun: true);
    final List<MediaCandidate> result = <MediaCandidate>[];
    for (final AutoUploadRule rule in rules) {
      if (!rule.enabled || rule.mode != AutoUploadMode.semiAutomatic.key) {
        continue;
      }
      if (!_isWithinSchedule(rule)) continue;
      for (final MediaCandidate candidate in pendingScan.newFiles) {
        if (_matchesRule(rule, candidate)) result.add(candidate);
      }
    }
    return result;
  }

  /// Checks whether a rule's schedule window currently allows uploads.
  bool _isWithinSchedule(AutoUploadRule rule) {
    if (!rule.scheduleEnabled) return true;
    final DateTime now = DateTime.now();
    final int minutesNow = now.hour * 60 + now.minute;
    final int start = rule.scheduleStartMinutes;
    final int end = start + rule.scheduleDurationMinutes;
    if (rule.weekdays.trim().isNotEmpty) {
      final Set<int> allowed = rule.weekdays
          .split(',')
          .map((String e) => int.tryParse(e.trim()) ?? -1)
          .where((int e) => e >= 0)
          .toSet();
      if (!allowed.contains(now.weekday)) return false;
    }
    if (end <= 1440) {
      return minutesNow >= start && minutesNow < end;
    }
    // The window wraps around midnight.
    return minutesNow >= start || minutesNow < (end - 1440);
  }

  bool _matchesRule(AutoUploadRule rule, MediaCandidate candidate) {
    if (rule.includePatterns.trim().isNotEmpty) {
      final List<String> includes = rule.includePatterns
          .split(',')
          .map((String e) => e.trim().toLowerCase())
          .where((String e) => e.isNotEmpty)
          .toList();
      final String name = candidate.name.toLowerCase();
      final bool matches = includes.any(
        (String pattern) => pattern.contains('*')
            ? _glob(name, pattern)
            : name.contains(pattern),
      );
      if (!matches) return false;
    }
    if (rule.excludePatterns.trim().isNotEmpty) {
      final List<String> excludes = rule.excludePatterns
          .split(',')
          .map((String e) => e.trim().toLowerCase())
          .where((String e) => e.isNotEmpty)
          .toList();
      final String name = candidate.name.toLowerCase();
      if (excludes.any(
        (String pattern) => pattern.contains('*')
            ? _glob(name, pattern)
            : name.contains(pattern),
      )) {
        return false;
      }
    }
    if (rule.maxFileMb > 0 && candidate.size > rule.maxFileMb * 1024 * 1024) {
      return false;
    }
    return true;
  }

  static bool _glob(String name, String pattern) {
    final String regex = RegExp.escape(pattern).replaceAll(r'\*', '.*');
    return RegExp('^$regex\$').hasMatch(name);
  }
}
