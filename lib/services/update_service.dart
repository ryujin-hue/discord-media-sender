import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/security.dart';
import '../data/database.dart';
import '../data/models.dart';

/// A release published on GitHub.
class GithubRelease {
  const GithubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.htmlUrl,
    required this.prerelease,
    required this.assets,
  });

  final String tagName;
  final String name;
  final String body;
  final DateTime? publishedAt;
  final String htmlUrl;
  final bool prerelease;
  final List<GithubAsset> assets;

  /// The APK asset, if the release contains one.
  GithubAsset? get apkAsset {
    for (final GithubAsset asset in assets) {
      if (asset.name.toLowerCase().endsWith('.apk')) return asset;
    }
    return null;
  }

  GithubAsset? get checksumAsset {
    for (final GithubAsset asset in assets) {
      if (asset.name.toLowerCase() ==
          AppConstants.checksumAssetName.toLowerCase()) {
        return asset;
      }
    }
    return null;
  }

  /// The version without a leading `v`.
  String get version => tagName.replaceFirst(RegExp('^v'), '');

  /// The release channel derived from the tag / prerelease flag.
  String get channel =>
      prerelease || tagName.contains('-beta') ? 'beta' : 'stable';
}

/// A downloadable asset of a release.
class GithubAsset {
  const GithubAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  final String name;
  final String downloadUrl;
  final int size;
}

/// The result of an update check.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.updateAvailable,
    required this.channel,
    this.release,
    this.releaseDate,
    this.releaseNotes,
    this.error,
    this.skipped = false,
  });

  final String currentVersion;
  final String latestVersion;
  final bool updateAvailable;
  final String channel;
  final GithubRelease? release;
  final DateTime? releaseDate;
  final String? releaseNotes;
  final String? error;
  final bool skipped;
}

/// The result of downloading the update APK.
class UpdateDownloadResult {
  const UpdateDownloadResult({
    required this.success,
    this.file,
    this.sha256,
    this.bytesDownloaded = 0,
    this.error,
  });

  final bool success;
  final File? file;
  final String? sha256;
  final int bytesDownloaded;
  final String? error;
}

/// Checks GitHub Releases for a newer version and downloads it safely.
///
/// The downloaded APK is only offered for installation after its SHA-256
/// matches the published `SHA256SUMS.txt`, and after its package name and
/// version code have been validated against the installed application.
class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  final AppDatabase _db = AppDatabase.instance;
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(minutes: 5),
      headers: <String, dynamic>{
        'Accept': 'application/vnd.github+json',
        'User-Agent': AppConstants.discordUserAgent,
      },
    ),
  );

  /// Checks the latest release, honouring the 6 hour check interval that the
  /// 1.0 build used.
  Future<UpdateCheckResult> check({bool force = false, String? channel}) async {
    final String installedVersion = await currentVersion();
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    if (!force) {
      final int lastCheck =
          prefs.getInt(AppConstants.prefUpdateLastCheckMs) ?? 0;
      final int elapsed = DateTime.now().millisecondsSinceEpoch - lastCheck;
      if (elapsed < AppConstants.updateCheckInterval.inMilliseconds) {
        return UpdateCheckResult(
          currentVersion: installedVersion,
          latestVersion: installedVersion,
          updateAvailable: false,
          channel: channel ?? 'stable',
          skipped: true,
        );
      }
    }

    try {
      final Response<dynamic> response = await _dio.get<dynamic>(
        AppConstants.latestReleaseApi,
      );
      final dynamic data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Unexpected release payload');
      }
      final GithubRelease release = _parseRelease(data);
      await prefs.setInt(
        AppConstants.prefUpdateLastCheckMs,
        DateTime.now().millisecondsSinceEpoch,
      );

      if (channel == 'stable' && release.channel != 'stable') {
        return UpdateCheckResult(
          currentVersion: installedVersion,
          latestVersion: installedVersion,
          updateAvailable: false,
          channel: release.channel,
          release: release,
        );
      }

      final bool available =
          compareVersions(release.version, installedVersion) > 0;

      await _db.insertUpdateHistory(
        UpdateHistoryEntry(
          id: 'upd-${DateTime.now().microsecondsSinceEpoch}',
          version: release.version,
          checkedAt: DateTime.now(),
          status: available ? 'available' : 'up_to_date',
          releaseUrl: release.htmlUrl,
          notes: release.body,
        ),
      );

      return UpdateCheckResult(
        currentVersion: installedVersion,
        latestVersion: release.version,
        updateAvailable: available,
        channel: release.channel,
        release: release,
        releaseDate: release.publishedAt,
        releaseNotes: release.body.isEmpty ? 'No release notes.' : release.body,
      );
    } catch (error) {
      await _db.insertUpdateHistory(
        UpdateHistoryEntry(
          id: 'upd-${DateTime.now().microsecondsSinceEpoch}',
          version: installedVersion,
          checkedAt: DateTime.now(),
          status: 'error',
          error: Security.redactSecrets(error.toString()),
        ),
      );
      return UpdateCheckResult(
        currentVersion: installedVersion,
        latestVersion: installedVersion,
        updateAvailable: false,
        channel: channel ?? 'stable',
        error:
            'Update check failed: ${Security.redactSecrets(error.toString())}',
      );
    }
  }

  GithubRelease _parseRelease(Map<String, dynamic> data) {
    final List<GithubAsset> assets = <GithubAsset>[];
    final dynamic rawAssets = data['assets'];
    if (rawAssets is List) {
      for (final dynamic asset in rawAssets) {
        if (asset is Map<String, dynamic>) {
          assets.add(
            GithubAsset(
              name: asset['name'] as String? ?? '',
              downloadUrl: asset['browser_download_url'] as String? ?? '',
              size: asset['size'] as int? ?? 0,
            ),
          );
        }
      }
    }
    return GithubRelease(
      tagName: data['tag_name'] as String? ?? '0.0.0',
      name: data['name'] as String? ?? '',
      body: data['body'] as String? ?? '',
      publishedAt: data['published_at'] == null
          ? null
          : DateTime.tryParse(data['published_at'] as String),
      htmlUrl: data['html_url'] as String? ?? AppConstants.githubRepoUrl,
      prerelease: data['prerelease'] as bool? ?? false,
      assets: assets,
    );
  }

  /// Downloads the release APK and verifies its checksum.
  Future<UpdateDownloadResult> download(
    GithubRelease release, {
    void Function(int received, int total)? onProgress,
  }) async {
    final GithubAsset? apk = release.apkAsset;
    if (apk == null) {
      return const UpdateDownloadResult(
        success: false,
        error: 'No suitable APK asset found in this release.',
      );
    }

    try {
      final Directory dir = await getTemporaryDirectory();
      final File target = File(p.join(dir.path, apk.name));
      await _dio.download(
        apk.downloadUrl,
        target.path,
        onReceiveProgress: onProgress,
        options: Options(
          followRedirects: true,
          headers: <String, dynamic>{
            'User-Agent': AppConstants.discordUserAgent,
          },
        ),
      );

      final String actualHash = await Security.sha256File(target.path);

      final String? expectedHash = await _expectedChecksum(release, apk.name);
      if (expectedHash == null) {
        return UpdateDownloadResult(
          success: false,
          file: target,
          sha256: actualHash,
          error:
              'The checksum for ${apk.name} is missing in ${AppConstants.checksumAssetName}.',
        );
      }
      if (expectedHash.toLowerCase() != actualHash.toLowerCase()) {
        await target.delete();
        return UpdateDownloadResult(
          success: false,
          sha256: actualHash,
          error: 'Checksum mismatch: the downloaded APK does not match the published SHA-256.',
        );
      }

      return UpdateDownloadResult(
        success: true,
        file: target,
        sha256: actualHash,
        bytesDownloaded: await target.length(),
      );
    } catch (error) {
      return UpdateDownloadResult(
        success: false,
        error: 'Download failed: ${Security.redactSecrets(error.toString())}',
      );
    }
  }

  Future<String?> _expectedChecksum(
    GithubRelease release,
    String assetName,
  ) async {
    final GithubAsset? checksumAsset = release.checksumAsset;
    if (checksumAsset == null) return null;
    try {
      final Response<String> response = await _dio.get<String>(
        checksumAsset.downloadUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: <String, dynamic>{
            'User-Agent': AppConstants.discordUserAgent,
          },
        ),
      );
      final String body = response.data ?? '';
      for (final String line in body.split('\n')) {
        final String trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final List<String> parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length < 2) continue;
        final String name = parts.last.replaceFirst('*', '');
        if (name == assetName) return parts.first;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// The installed application version name.
  Future<String> currentVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return AppConstants.appVersion;
    }
  }

  /// The installed Android version code.
  Future<int> currentVersionCode() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Compares two semantic versions.
  ///
  /// Follows the SemVer precedence rules: build metadata is ignored, a
  /// pre-release version is lower than the matching release version
  /// (`2.0.0-beta.1` < `2.0.0`) and numeric identifiers compare numerically
  /// while alphanumeric identifiers compare lexically.
  ///
  /// Returns a negative number when [a] is older, zero when equal and a
  /// positive number when [a] is newer.
  static int compareVersions(String a, String b) {
    final _SemVer left = _SemVer.parse(a);
    final _SemVer right = _SemVer.parse(b);

    for (int i = 0; i < 3; i++) {
      final int result = left.core[i].compareTo(right.core[i]);
      if (result != 0) return result;
    }

    // A version without a pre-release tag is greater than one with it.
    if (left.preRelease.isEmpty && right.preRelease.isEmpty) return 0;
    if (left.preRelease.isEmpty) return 1;
    if (right.preRelease.isEmpty) return -1;

    final int length = left.preRelease.length > right.preRelease.length
        ? left.preRelease.length
        : right.preRelease.length;
    for (int i = 0; i < length; i++) {
      if (i >= left.preRelease.length) return -1;
      if (i >= right.preRelease.length) return 1;
      final String leftPart = left.preRelease[i];
      final String rightPart = right.preRelease[i];
      final int? leftNumber = int.tryParse(leftPart);
      final int? rightNumber = int.tryParse(rightPart);
      if (leftNumber != null && rightNumber != null) {
        final int result = leftNumber.compareTo(rightNumber);
        if (result != 0) return result;
      } else if (leftNumber != null) {
        return -1;
      } else if (rightNumber != null) {
        return 1;
      } else {
        final int result = leftPart.compareTo(rightPart);
        if (result != 0) return result;
      }
    }
    return 0;
  }

  /// Extracts the version code from an APK file name or release tag.
  ///
  /// Used to double-check that the published build is newer than the installed
  /// one before an install is offered.
  static int versionCodeFromTag(String tag) {
    final List<String> parts = tag.replaceFirst(RegExp('^v'), '').split('.');
    if (parts.length < 3) return 0;
    final int major = int.tryParse(parts[0]) ?? 0;
    final int minor = int.tryParse(parts[1]) ?? 0;
    final int patch = int.tryParse(parts[2].split('-').first) ?? 0;
    return major * 10000 + minor * 100 + patch;
  }

  /// Formats a release body for display.
  static String formatNotes(String? body) {
    if (body == null || body.trim().isEmpty) return 'No release notes.';
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map && decoded['notes'] is String) {
        return decoded['notes'] as String;
      }
    } catch (_) {}
    return body.trim();
  }
}

/// A parsed semantic version.
class _SemVer {
  const _SemVer(this.core, this.preRelease);

  final List<int> core;
  final List<String> preRelease;

  static _SemVer parse(String value) {
    String working = value.trim();
    if (working.startsWith('v')) working = working.substring(1);

    // Build metadata does not participate in precedence.
    final int plus = working.indexOf('+');
    if (plus >= 0) working = working.substring(0, plus);

    final List<String> preRelease = <String>[];
    final int dash = working.indexOf('-');
    if (dash >= 0) {
      final String tag = working.substring(dash + 1);
      working = working.substring(0, dash);
      preRelease.addAll(tag.split('.').where((String part) => part.isNotEmpty));
    }

    final List<String> parts = working.split('.');
    final List<int> core = List<int>.generate(
      3,
      (int index) =>
          index < parts.length ? (int.tryParse(parts[index]) ?? 0) : 0,
    );
    return _SemVer(core, preRelease);
  }
}
