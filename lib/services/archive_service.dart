import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../data/database.dart';
import '../data/models.dart';

/// Summary of the archive contents.
class ArchiveSummary {
  const ArchiveSummary({
    required this.totalFiles,
    required this.totalBytes,
    required this.restorableFiles,
    required this.lastArchiveAt,
    required this.byCategory,
  });

  final int totalFiles;
  final int totalBytes;
  final int restorableFiles;
  final DateTime? lastArchiveAt;
  final Map<String, int> byCategory;
}

/// Manages the archive of uploaded media.
///
/// Archiving is a *logical* operation by default: the library entry is
/// flagged as archived and the record is written to `archive_records`. The
/// original file on disk is never deleted. Optionally the file can be moved
/// into an app-managed archive folder, which the user has to opt into.
class ArchiveService {
  ArchiveService._();

  static final ArchiveService instance = ArchiveService._();

  final AppDatabase _db = AppDatabase.instance;

  /// Archives a single library entry.
  Future<void> archiveMedia(
    MediaLibraryEntry entry, {
    String? destinationId,
    bool moveFile = false,
  }) async {
    String? archivePath;
    if (moveFile) {
      archivePath = await _moveToArchive(entry);
    }

    await _db.upsertArchiveRecord(
      ArchiveRecord(
        id: 'arch-${DateTime.now().microsecondsSinceEpoch}',
        mediaId: entry.id,
        archivedAt: DateTime.now(),
        category: entry.category,
        fileName: entry.name,
        fileSize: entry.size,
        originalPath: entry.path,
        archivePath: archivePath,
        destinationId: destinationId,
      ),
    );

    await _db.upsertMedia(
      entry.copyWith(
        status: MediaStatus.archived.key,
        archivedAt: DateTime.now(),
        path: archivePath ?? entry.path,
      ),
    );

    await _db.insertArchiveOperation(
      operation: 'archive',
      itemCount: 1,
      mediaId: entry.id,
      detail: entry.name,
    );

    await _db.insertAnalyticsEvent(
      eventType: 'file_archived',
      destinationId: destinationId,
      fileSize: entry.size,
    );
  }

  /// Archives every media entry that has completed uploading.
  Future<int> archiveAllCompleted({String? destinationId}) async {
    final List<MediaLibraryEntry> completed = await _db.listMedia(
      status: MediaStatus.uploaded.key,
    );
    final List<MediaLibraryEntry> targets = <MediaLibraryEntry>[];
    for (final MediaLibraryEntry entry in completed) {
      if (destinationId == null) {
        targets.add(entry);
        continue;
      }
      final String? hash = entry.sha256;
      if (hash == null) continue;
      final List<DeliveryRecord> deliveries = await _db.deliveriesForHash(hash);
      final bool matches = deliveries.any(
        (DeliveryRecord d) => d.destinationId == destinationId,
      );
      if (matches) targets.add(entry);
    }

    for (final MediaLibraryEntry entry in targets) {
      await archiveMedia(entry, destinationId: destinationId);
    }
    await _db.insertArchiveOperation(
      operation: 'archive_all_completed',
      itemCount: targets.length,
      detail: destinationId ?? 'all destinations',
    );
    return targets.length;
  }

  /// Restores an archived entry.
  Future<void> restore(String archiveRecordId) async {
    final List<ArchiveRecord> records = await _db.listArchiveRecords();
    ArchiveRecord? record;
    for (final ArchiveRecord r in records) {
      if (r.id == archiveRecordId) {
        record = r;
        break;
      }
    }
    if (record == null) return;

    final MediaLibraryEntry? entry = await _db.mediaById(record.mediaId);
    if (entry == null) return;

    String restoredPath = entry.path;
    if (record.archivePath != null && record.originalPath != null) {
      final File archived = File(record.archivePath!);
      final File original = File(record.originalPath!);
      if (archived.existsSync() && !original.existsSync()) {
        await original.parent.create(recursive: true);
        await archived.rename(original.path);
        restoredPath = original.path;
      }
    }

    await _db.upsertArchiveRecord(record.copyWith(restoredAt: DateTime.now()));
    await _db.upsertMedia(
      entry.copyWith(
        status: MediaStatus.uploaded.key,
        clearArchived: true,
        path: restoredPath,
      ),
    );
    await _db.insertArchiveOperation(
      operation: 'restore',
      itemCount: 1,
      mediaId: entry.id,
      detail: entry.name,
    );
    await _db.insertAnalyticsEvent(
      eventType: 'file_restored',
      fileSize: entry.size,
    );
  }

  /// Permanently removes the archive record.
  ///
  /// The file on disk is only deleted when [deleteFile] is explicitly true,
  /// which the UI only offers behind an explicit confirmation dialog.
  Future<void> permanentlyDelete(
    String archiveRecordId, {
    bool deleteFile = false,
  }) async {
    final List<ArchiveRecord> records = await _db.listArchiveRecords();
    for (final ArchiveRecord record in records) {
      if (record.id != archiveRecordId) continue;
      if (deleteFile) {
        final String? path = record.archivePath ?? record.originalPath;
        if (path != null) {
          try {
            final File file = File(path);
            if (file.existsSync()) await file.delete();
          } catch (_) {}
        }
      }
      await _db.deleteArchiveRecord(record.id);
      await _db.insertArchiveOperation(
        operation: 'permanent_delete',
        itemCount: 1,
        mediaId: record.mediaId,
        detail: record.fileName,
      );
      return;
    }
  }

  /// Returns the current archive summary.
  Future<ArchiveSummary> summary() async {
    final List<ArchiveRecord> records = await _db.listArchiveRecords();
    int totalBytes = 0;
    int restorable = 0;
    DateTime? last;
    final Map<String, int> byCategory = <String, int>{};
    for (final ArchiveRecord record in records) {
      totalBytes += record.fileSize;
      if (record.restoredAt == null) restorable++;
      byCategory[record.category] = (byCategory[record.category] ?? 0) + 1;
      if (last == null || record.archivedAt.isAfter(last)) {
        last = record.archivedAt;
      }
    }
    return ArchiveSummary(
      totalFiles: records.length,
      totalBytes: totalBytes,
      restorableFiles: restorable,
      lastArchiveAt: last,
      byCategory: byCategory,
    );
  }

  /// Applies the automatic archive rules to the library.
  ///
  /// Returns the number of newly archived entries.
  Future<int> applyAutomaticRules() async {
    final List<ArchiveRule> rules = await _db.listArchiveRules();
    if (rules.isEmpty) return 0;

    final List<MediaLibraryEntry> uploaded = await _db.listMedia(
      status: MediaStatus.uploaded.key,
    );
    int archived = 0;

    for (final ArchiveRule rule in rules) {
      if (!rule.enabled) continue;

      for (final MediaLibraryEntry entry in uploaded) {
        if (entry.isArchived) continue;
        if (rule.excludeFavorites && entry.favorite) continue;
        if (rule.excludePendingReview &&
            entry.status == MediaStatus.pendingReview.key) {
          continue;
        }
        if (rule.categories.trim().isNotEmpty) {
          final List<String> allowed = rule.categories
              .split(',')
              .map((String e) => e.trim())
              .toList();
          if (!allowed.contains(entry.category)) continue;
        }
        if (rule.excludeFolders.trim().isNotEmpty) {
          bool excluded = false;
          for (final String folder
              in rule.excludeFolders.split(',').map((String e) => e.trim())) {
            if (folder.isNotEmpty && entry.path.startsWith(folder)) {
              excluded = true;
              break;
            }
          }
          if (excluded) continue;
        }
        if (rule.archiveAfterUpload) {
          await archiveMedia(entry);
          archived++;
          continue;
        }
        if (rule.archiveAfterDays != null || rule.maxAgeDays != null) {
          final int days = rule.archiveAfterDays ?? rule.maxAgeDays!;
          final DateTime threshold = DateTime.now().subtract(
            Duration(days: days),
          );
          if (entry.addedAt.isBefore(threshold)) {
            await archiveMedia(entry);
            archived++;
          }
        }
      }
    }
    return archived;
  }

  Future<String?> _moveToArchive(MediaLibraryEntry entry) async {
    try {
      final Directory base = await getApplicationSupportDirectory();
      final Directory target = Directory(
        p.join(base.path, 'archive', entry.category),
      );
      if (!target.existsSync()) await target.create(recursive: true);

      final File source = File(entry.path);
      if (!source.existsSync()) return null;

      String name = entry.name;
      String destination = p.join(target.path, name);
      int counter = 1;
      while (File(destination).existsSync()) {
        destination = p.join(
          target.path,
          '${p.basenameWithoutExtension(name)}_$counter${p.extension(name)}',
        );
        counter++;
      }
      await source.rename(destination);
      return destination;
    } catch (_) {
      return null;
    }
  }
}
