import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/constants.dart';
import '../core/security.dart';
import '../data/database.dart';
import '../data/models.dart';

/// The outcome of a duplicate scan.
class DuplicateScanResult {
  const DuplicateScanResult({
    required this.scanned,
    required this.duplicates,
    required this.newFiles,
  });

  final int scanned;
  final List<DuplicateRecord> duplicates;
  final List<MediaLibraryEntry> newFiles;
}

/// The engine that detects duplicate media.
///
/// SHA-256 is the only method that proves two files have identical content.
/// Metadata and perceptual hashes are used to *surface* possible duplicates for
/// review, never to silently drop or delete a file.
class DuplicateService {
  DuplicateService._();

  static final DuplicateService instance = DuplicateService._();

  final AppDatabase _db = AppDatabase.instance;

  /// Scans a set of paths and stores the results in the library.
  ///
  /// Files whose SHA-256 is already known are linked to the original entry and
  /// flagged as [MediaStatus.duplicateDetected].
  Future<DuplicateScanResult> scanPaths(
    List<String> paths, {
    String? sourceFolder,
  }) async {
    int scanned = 0;
    final List<DuplicateRecord> duplicates = <DuplicateRecord>[];
    final List<MediaLibraryEntry> newFiles = <MediaLibraryEntry>[];

    for (final String path in paths) {
      final File file = File(path);
      if (!file.existsSync()) continue;
      scanned++;

      final int size = file.lengthSync();
      final String sha = await Security.sha256File(path);
      final MediaLibraryEntry? existing = await _db.mediaByPath(path);

      // Known hash of a *different* path means identical content.
      final List<FileHashRecord> known = await _db.hashesForDigest(sha);
      final FileHashRecord? otherPath = known
          .where((FileHashRecord h) => h.path != path)
          .cast<FileHashRecord?>()
          .firstWhere((FileHashRecord? h) => h != null, orElse: () => null);

      final String? originalMediaId = otherPath?.mediaId;
      final MediaLibraryEntry? originalEntry = originalMediaId == null
          ? null
          : await _db.mediaById(originalMediaId);

      final bool isDuplicate = otherPath != null;

      final MediaLibraryEntry entry = MediaLibraryEntry(
        id: existing?.id ?? 'media-${DateTime.now().microsecondsSinceEpoch}',
        path: path,
        name: p.basename(path),
        size: size,
        addedAt: existing?.addedAt ?? DateTime.now(),
        status: isDuplicate
            ? MediaStatus.duplicateDetected.key
            : (existing?.status ?? MediaStatus.newFile.key),
        mimeType: MediaCategoryX.mimeFor(path),
        category: MediaCategoryX.categoryFor(path),
        sha256: sha,
        favorite: existing?.favorite ?? false,
        collectionId: existing?.collectionId,
        modifiedAt: DateTime.now(),
        lastActivityAt: DateTime.now(),
        sourceFolder: sourceFolder ?? existing?.sourceFolder,
      );
      await _db.upsertMedia(entry);

      await _db.upsertHash(
        FileHashRecord(
          sha256: sha,
          path: path,
          size: size,
          firstSeenAt: existing?.addedAt ?? DateTime.now(),
          mediaId: entry.id,
          lastSeenAt: DateTime.now(),
        ),
      );

      if (isDuplicate) {
        final DuplicateRecord record = DuplicateRecord(
          id: 'dup-${DateTime.now().microsecondsSinceEpoch}',
          originalId: originalEntry?.id ?? originalMediaId ?? '',
          duplicateId: entry.id,
          method: DetectionMethod.sha256.key,
          detectedAt: DateTime.now(),
          decision: 'pending_review',
          similarity: 1.0,
          originalPath: otherPath.path,
          duplicatePath: path,
          originalName: originalEntry?.name ?? p.basename(otherPath.path),
          duplicateName: entry.name,
        );
        await _db.upsertDuplicate(record);
        duplicates.add(record);
      } else if (existing == null) {
        newFiles.add(entry);
      }
    }

    return DuplicateScanResult(
      scanned: scanned,
      duplicates: duplicates,
      newFiles: newFiles,
    );
  }

  /// Finds library entries that look similar by metadata only.
  ///
  /// These are returned for user review; they are never treated as identical.
  Future<List<DuplicateRecord>> findSimilarByMetadata(
    MediaLibraryEntry entry,
  ) async {
    final List<MediaLibraryEntry> all = await _db.listMedia(
      notArchivedOnly: true,
    );
    final List<DuplicateRecord> similar = <DuplicateRecord>[];
    for (final MediaLibraryEntry other in all) {
      if (other.id == entry.id) continue;
      if (other.sha256 != null && other.sha256 == entry.sha256) continue;
      if (other.size != entry.size) continue;
      if (other.category != entry.category) continue;
      final bool sameName =
          other.name.toLowerCase() == entry.name.toLowerCase();
      if (!sameName) continue;
      similar.add(
        DuplicateRecord(
          id: 'meta-${DateTime.now().microsecondsSinceEpoch}-${other.id}',
          originalId: entry.id,
          duplicateId: other.id,
          method: DetectionMethod.metadata.key,
          detectedAt: DateTime.now(),
          decision: 'pending_review',
          similarity: null,
          originalPath: entry.path,
          duplicatePath: other.path,
          originalName: entry.name,
          duplicateName: other.name,
        ),
      );
    }
    return similar;
  }

  /// Records the user decision for a detected duplicate.
  Future<void> review(
    DuplicateRecord record,
    DuplicatePolicy decision, {
    String? note,
  }) async {
    await _db.upsertDuplicate(record.copyWith(decision: decision.key));
    await _db.insertDuplicateReview(
      duplicateId: record.id,
      decision: decision.key,
      note: note,
    );

    final MediaLibraryEntry? duplicate = await _db.mediaById(
      record.duplicateId,
    );
    if (duplicate == null) return;

    switch (decision) {
      case DuplicatePolicy.skip:
        await _db.upsertMedia(
          duplicate.copyWith(status: MediaStatus.duplicateDetected.key),
        );
        break;
      case DuplicatePolicy.anyway:
      case DuplicatePolicy.keepBoth:
        await _db.upsertMedia(
          duplicate.copyWith(status: MediaStatus.newFile.key),
        );
        break;
      case DuplicatePolicy.replace:
        // The library entry is replaced by the duplicate's content, but the
        // original file on disk is never deleted automatically.
        await _db.upsertMedia(
          duplicate.copyWith(status: MediaStatus.newFile.key),
        );
        if (record.originalId.isNotEmpty) {
          final MediaLibraryEntry? original = await _db.mediaById(
            record.originalId,
          );
          if (original != null) {
            await _db.upsertMedia(
              original.copyWith(status: MediaStatus.newFile.key),
            );
          }
        }
        break;
      case DuplicatePolicy.ask:
        await _db.upsertMedia(
          duplicate.copyWith(status: MediaStatus.pendingReview.key),
        );
        break;
    }
  }

  /// Returns true when the given content hash was already delivered to the
  /// destination.
  Future<bool> wasDeliveredTo(String sha256, String destinationId) =>
      _db.hasDelivery(sha256, destinationId);

  /// Returns the destinations the content has already been delivered to.
  Future<List<String>> deliveredDestinations(String sha256) async {
    final List<DeliveryRecord> records = await _db.deliveriesForHash(sha256);
    return records.map((DeliveryRecord r) => r.destinationId).toSet().toList();
  }
}

/// Helpers shared by the duplicate engine and the library screens.
class MediaCategoryX {
  MediaCategoryX._();

  static const Map<String, List<String>> categoryExtensions =
      <String, List<String>>{
        'image': <String>[
          'jpg',
          'jpeg',
          'png',
          'gif',
          'webp',
          'bmp',
          'heic',
          'heif',
          'tiff',
        ],
        'video': <String>[
          'mp4',
          'mkv',
          'mov',
          'webm',
          'avi',
          'flv',
          'wmv',
          'm4v',
          '3gp',
        ],
        'audio': <String>[
          'mp3',
          'wav',
          'ogg',
          'flac',
          'm4a',
          'aac',
          'opus',
          'wma',
        ],
        'document': <String>[
          'pdf',
          'txt',
          'md',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'csv',
          'json',
          'xml',
          'html',
          'rtf',
          'odt',
        ],
      };

  static String categoryFor(String path) {
    final String ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    for (final MapEntry<String, List<String>> entry
        in categoryExtensions.entries) {
      if (entry.value.contains(ext)) return entry.key;
    }
    return 'other';
  }

  static String mimeFor(String path) {
    final String ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'pdf':
        return 'application/pdf';
      case 'zip':
        return 'application/zip';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }
}
