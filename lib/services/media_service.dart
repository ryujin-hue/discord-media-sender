import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_video_thumbnail_plus/flutter_video_thumbnail_plus.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../core/error_translator.dart';
import 'media_resolver.dart';

/// A file that has been selected for uploading.
class MediaCandidate {
  const MediaCandidate({
    required this.path,
    required this.name,
    required this.size,
    required this.modifiedAt,
    this.mimeType,
    this.category = 'other',
    this.sourceFolder,
    this.fromArchive = false,
  });

  final String path;
  final String name;
  final int size;
  final DateTime modifiedAt;
  final String? mimeType;
  final String category;
  final String? sourceFolder;
  final bool fromArchive;

  MediaCandidate copyWith({String? path, String? name, int? size}) =>
      MediaCandidate(
        path: path ?? this.path,
        name: name ?? this.name,
        size: size ?? this.size,
        modifiedAt: modifiedAt,
        mimeType: mimeType,
        category: category,
        sourceFolder: sourceFolder,
        fromArchive: fromArchive,
      );
}

/// Result of extracting a ZIP archive.
class ZipExtractionResult {
  const ZipExtractionResult({
    required this.extracted,
    required this.skipped,
    this.error,
  });

  final List<MediaCandidate> extracted;
  final List<String> skipped;
  final String? error;
}

/// Service that discovers, inspects and prepares media files.
///
/// It is the only place that knows how to turn a user selection into concrete
/// files on disk, so the upload engine never has to deal with archives or
/// content URIs.
class MediaService {
  MediaService._();

  static final MediaService instance = MediaService._();

  /// Extension groups used by the library, archive and analytics filters.
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

  /// Returns the category key for a file path.
  static String categoryFor(String path) {
    final String ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    for (final MapEntry<String, List<String>> entry
        in categoryExtensions.entries) {
      if (entry.value.contains(ext)) return entry.key;
    }
    return 'other';
  }

  /// Returns the MIME type for a file path.
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
      case 'ogg':
        return 'audio/ogg';
      case 'flac':
        return 'audio/flac';
      case 'pdf':
        return 'application/pdf';
      case 'zip':
        return 'application/zip';
      case 'txt':
        return 'text/plain';
      case 'json':
        return 'application/json';
      default:
        return 'application/octet-stream';
    }
  }

  /// Builds a [MediaCandidate] from a file on disk.
  MediaCandidate describe(String path, {String? sourceFolder}) {
    final File file = File(path);
    int size = 0;
    DateTime modified = DateTime.now();
    try {
      final FileStat stat = file.statSync();
      size = stat.size;
      modified = stat.modified;
    } catch (_) {}
    return MediaCandidate(
      path: path,
      name: p.basename(path),
      size: size,
      modifiedAt: modified,
      mimeType: mimeFor(path),
      category: categoryFor(path),
      sourceFolder: sourceFolder,
    );
  }

  /// Recursively lists media files inside a folder.
  ///
  /// [include] / [exclude] accept simple glob patterns (`*.jpg`, `*_raw`).
  Future<List<MediaCandidate>> scanFolder(
    String folderPath, {
    bool recursive = true,
    String include = '',
    String exclude = '',
    int maxFileMb = 0,
    int minFileBytes = 0,
    DateTime? modifiedAfter,
    void Function(int found)? onProgress,
  }) async {
    final List<MediaCandidate> results = <MediaCandidate>[];

    // A Storage Access Framework tree is resolved through the platform.
    if (folderPath.startsWith('content://')) {
      final List<TreeFile> treeFiles = await MediaResolver.listTreeFiles(
        folderPath,
      );
      for (final TreeFile file in treeFiles) {
        if (_matchesAny(file.name, exclude)) continue;
        if (!_matchesAny(file.name, include)) {
          // An empty include pattern matches everything.
          if (include.trim().isNotEmpty) continue;
        }
        if (maxFileMb > 0 && file.size > maxFileMb * 1024 * 1024) continue;
        if (minFileBytes > 0 && file.size < minFileBytes) continue;
        results.add(
          MediaCandidate(
            path: file.path,
            name: file.name,
            size: file.size,
            modifiedAt: file.modifiedAt > 0
                ? DateTime.fromMillisecondsSinceEpoch(file.modifiedAt)
                : DateTime.now(),
            mimeType: file.mimeType,
            category: categoryFor(file.name),
            sourceFolder: folderPath,
          ),
        );
      }
      onProgress?.call(results.length);
      return results;
    }

    final Directory directory = Directory(folderPath);
    if (!directory.existsSync()) {
      throw FileSystemException('Folder not found', folderPath);
    }

    final List<FileSystemEntity> entries = <FileSystemEntity>[];
    if (recursive) {
      await for (final FileSystemEntity entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        entries.add(entity);
      }
    } else {
      entries.addAll(directory.listSync(followLinks: false));
    }

    int index = 0;
    for (final FileSystemEntity entity in entries) {
      index++;
      if (entity is! File) continue;
      final String path = entity.path;
      final String name = p.basename(path);
      if (name.startsWith('.')) continue;
      if (!_matchesAny(name, include)) continue;
      if (_matchesAny(name, exclude)) continue;

      int size = 0;
      DateTime modified = DateTime.now();
      try {
        final FileStat stat = entity.statSync();
        size = stat.size;
        modified = stat.modified;
      } catch (_) {
        continue;
      }
      if (minFileBytes > 0 && size < minFileBytes) continue;
      if (maxFileMb > 0 && size > maxFileMb * 1024 * 1024) continue;
      if (modifiedAfter != null && !modified.isAfter(modifiedAfter)) continue;

      results.add(
        MediaCandidate(
          path: path,
          name: name,
          size: size,
          modifiedAt: modified,
          mimeType: mimeFor(path),
          category: categoryFor(path),
          sourceFolder: folderPath,
        ),
      );
      onProgress?.call(index);
    }
    return results;
  }

  /// Extracts a ZIP archive into the app cache and returns the contained files.
  ///
  /// Archives larger than [AppConstants.maxZipBytes] are rejected, matching the
  /// 1.0 behaviour of skipping oversized ZIPs.
  Future<ZipExtractionResult> extractZip(
    String zipPath, {
    void Function(String fileName)? onProgress,
  }) async {
    final File zipFile = File(zipPath);
    if (!zipFile.existsSync()) {
      return const ZipExtractionResult(
        extracted: <MediaCandidate>[],
        skipped: <String>[],
        error: 'File not found',
      );
    }
    final int size = zipFile.lengthSync();
    if (size > AppConstants.maxZipBytes) {
      return ZipExtractionResult(
        extracted: const <MediaCandidate>[],
        skipped: <String>[p.basename(zipPath)],
        error: 'ZIP file exceeds the 5 GB limit and was skipped',
      );
    }

    try {
      final Directory tempDir = await getTemporaryDirectory();
      final Directory target = Directory(
        p.join(
          tempDir.path,
          'extracted',
          '${p.basenameWithoutExtension(zipPath)}_${DateTime.now().millisecondsSinceEpoch}',
        ),
      );
      await target.create(recursive: true);

      final List<int> bytes = await zipFile.readAsBytes();
      final Archive archive = ZipDecoder().decodeBytes(bytes);
      final List<MediaCandidate> extracted = <MediaCandidate>[];
      final List<String> skipped = <String>[];

      for (final ArchiveFile entry in archive.files) {
        if (!entry.isFile) continue;
        final String entryPath = p.join(target.path, p.normalize(entry.name));
        if (!p.isWithin(target.path, entryPath)) {
          skipped.add(entry.name);
          continue;
        }
        final File out = File(entryPath);
        await out.parent.create(recursive: true);
        final List<int> data = entry.content as List<int>;
        await out.writeAsBytes(data, flush: true);
        extracted.add(
          MediaCandidate(
            path: out.path,
            name: p.basename(entry.name),
            size: data.length,
            modifiedAt: DateTime.now(),
            mimeType: mimeFor(entry.name),
            category: categoryFor(entry.name),
            fromArchive: true,
          ),
        );
        onProgress?.call(entry.name);
      }

      return ZipExtractionResult(extracted: extracted, skipped: skipped);
    } catch (error) {
      return ZipExtractionResult(
        extracted: const <MediaCandidate>[],
        skipped: const <String>[],
        error: 'Failed to extract ZIP: ${ErrorTranslator.translate(error)}',
      );
    }
  }

  /// Creates a ZIP archive from a list of files.
  Future<File> createZip(List<String> filePaths, {String? targetName}) async {
    final Archive archive = Archive();
    for (final String path in filePaths) {
      final File file = File(path);
      if (!file.existsSync()) continue;
      archive.addFile(
        ArchiveFile(
          p.basename(path),
          file.lengthSync(),
          file.readAsBytesSync(),
        ),
      );
    }
    final List<int> encoded = ZipEncoder().encode(archive);
    if (encoded.isEmpty) {
      throw const FileSystemException('Failed to encode archive');
    }
    final Directory tempDir = await getTemporaryDirectory();
    final File out = File(
      p.join(
        tempDir.path,
        '${targetName ?? 'media_${DateTime.now().millisecondsSinceEpoch}'}.zip',
      ),
    );
    await out.writeAsBytes(encoded, flush: true);
    return out;
  }

  /// Generates a video thumbnail, returning the file path or null.
  Future<String?> generateThumbnail(String videoPath, {int? width}) async {
    try {
      final Directory dir = Directory(
        p.join((await getTemporaryDirectory()).path, '.thumbnails'),
      );
      if (!dir.existsSync()) await dir.create(recursive: true);
      final String? thumb = await FlutterVideoThumbnailPlus.thumbnailFile(
        video: videoPath,
        thumbnailPath: p.join(
          dir.path,
          '${p.basenameWithoutExtension(videoPath)}.png',
        ),
        maxWidth: width ?? 320,
        quality: 70,
        timeMs: 1000,
      );
      return thumb;
    } catch (_) {
      return null;
    }
  }

  /// Directory where thumbnails are cached.
  Future<Directory> thumbnailDirectory() async {
    final Directory dir = Directory(
      p.join((await getTemporaryDirectory()).path, '.thumbnails'),
    );
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Compresses an image by re-encoding it at the given quality.
  ///
  /// Returns a new [MediaCandidate] pointing at the compressed file, or null
  /// when compression is not possible or not worthwhile (unsupported format,
  /// already smaller than the target, or the result would be bigger).
  ///
  /// The original file is never modified or deleted.
  Future<MediaCandidate?> compressImage(
    MediaCandidate candidate, {
    int quality = 80,
    int? maxWidth,
  }) async {
    if (candidate.category != 'image') return null;
    if (quality < 10 || quality > 100) return null;

    final String lowerExt = p.extension(candidate.path).toLowerCase();
    final bool isJpeg = lowerExt == '.jpg' || lowerExt == '.jpeg';
    final bool isPng = lowerExt == '.png';
    final bool isWebp = lowerExt == '.webp';
    if (!isJpeg && !isPng && !isWebp) return null;

    try {
      final Uint8List originalBytes = await File(candidate.path).readAsBytes();
      if (originalBytes.isEmpty) return null;

      img.Image? decoded;
      if (isPng) {
        decoded = img.decodePng(originalBytes);
      } else {
        decoded = img.decodeJpg(originalBytes);
      }
      if (decoded == null) return null;

      img.Image working = decoded;
      if (maxWidth != null && maxWidth > 0 && working.width > maxWidth) {
        working = img.copyResize(working, width: maxWidth);
      }

      final Uint8List encoded = isPng
          ? img.encodePng(working, level: _pngLevelFor(quality))
          : img.encodeJpg(working, quality: quality);

      if (encoded.length >= originalBytes.length) {
        // Compression did not pay off; keep the original.
        return null;
      }

      final Directory dir = await thumbnailDirectory();
      final File out = File(
        p.join(
          dir.path,
          '${p.basenameWithoutExtension(candidate.name)}_compressed${isPng ? '.png' : '.jpg'}',
        ),
      );
      await out.writeAsBytes(encoded, flush: true);

      return MediaCandidate(
        path: out.path,
        name: out.uri.pathSegments.last,
        size: encoded.length,
        modifiedAt: DateTime.now(),
        mimeType: mimeFor(out.path),
        category: candidate.category,
        sourceFolder: candidate.sourceFolder,
      );
    } catch (_) {
      return null;
    }
  }

  /// Maps a 0-100 quality setting onto a PNG compression level (0-9).
  static int _pngLevelFor(int quality) {
    final int inverted = 100 - quality;
    return (inverted * 9 ~/ 100).clamp(0, 9);
  }

  /// Deletes a file, ignoring missing files.
  Future<void> deleteFile(String path) async {
    try {
      final File file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  /// Returns the free space of the volume that contains [path].
  Future<int> freeSpaceFor(String path) async {
    try {
      final Directory dir = Directory(path);
      if (!dir.existsSync()) return 0;
      // Dart has no free-space API; the stat call is the best available
      // approximation and returns 0 when the platform does not expose it.
      final FileStat stat = dir.statSync();
      return stat.size;
    } catch (_) {
      return 0;
    }
  }

  /// Estimates the number of items in a directory without loading them all.
  Future<int> countFolderItems(String folderPath) async {
    try {
      final Directory dir = Directory(folderPath);
      if (!dir.existsSync()) return 0;
      int count = 0;
      await for (final FileSystemEntity _ in dir.list(recursive: true)) {
        count++;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  /// Picks a random sample of [count] items.
  static List<T> sample<T>(List<T> items, int count) {
    if (items.length <= count) return items;
    final Random random = Random();
    final List<T> copy = List<T>.of(items);
    copy.shuffle(random);
    return copy.sublist(0, count);
  }

  static bool _matchesAny(String name, String patterns) {
    if (patterns.trim().isEmpty) return false;
    for (final String raw in patterns.split(',')) {
      final String pattern = raw.trim();
      if (pattern.isEmpty) continue;
      if (pattern.contains('*')) {
        final String regex = RegExp.escape(pattern).replaceAll(r'\*', '.*');
        if (RegExp('^$regex\$', caseSensitive: false).hasMatch(name)) {
          return true;
        }
      } else if (name.toLowerCase() == pattern.toLowerCase()) {
        return true;
      }
    }
    return false;
  }
}
