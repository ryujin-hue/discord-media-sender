import 'package:flutter/material.dart';

/// Global, immutable configuration constants for Discord Media Sender 2.0.
///
/// Values that were verified against the 1.0.a9 build (API base, secure-store
/// keys, setting keys, Discord limits) are preserved verbatim so that data
/// written by 1.0 continues to be read by 2.0.
class AppConstants {
  AppConstants._();

  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------
  static const String appName = 'Discord Media Sender';
  static const String appVersion = '2.1.1';
  static const String applicationId = 'com.dmsender.discord_media_sender';

  /// Official GitHub repository used for update checks and release publishing.
  ///
  /// The 1.0 build pointed at `tukiza7-debug/discord-media-sender`, which no
  /// longer resolves; the repository below is the maintained home of the
  /// project and the one the in-app updater reads.
  static const String githubOwner = 'ryujin-hue';
  static const String githubRepo = 'discord-media-sender';

  /// The repository the 1.0 build used, kept for reference in the settings
  /// screen and the documentation.
  static const String legacyGithubRepo = 'tukiza7-debug/discord-media-sender';
  static const String githubRepoUrl =
      'https://github.com/$githubOwner/$githubRepo';

  static const String latestReleaseApi =
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest';

  /// Name of the release asset that the in-app updater installs.
  static const String releaseAssetName = 'DiscordMediaSender.apk';

  /// Name of the checksum manifest published next to the APK.
  static const String checksumAssetName = 'SHA256SUMS.txt';

  // ---------------------------------------------------------------------------
  // Discord
  // ---------------------------------------------------------------------------
  static const String discordApiBase = 'https://discord.com/api/v10';
  static const String discordWebBase = 'https://discord.com';
  static const String discordUserAgent = 'DiscordMediaSender/2.0 (Android)';

  /// Maximum number of files Discord accepts in a single multipart request.
  static const int discordMaxFilesPerRequest = 10;

  /// Maximum size of a single file accepted by Discord (nitro / boosted).
  static const int discordMaxFileBytes = 100 * 1024 * 1024;

  /// Maximum total request size accepted by Discord.
  static const int discordMaxRequestBytes = 500 * 1024 * 1024;

  /// Hard ceiling enforced by the app itself for ZIP imports.
  static const int maxZipBytes = 5 * 1024 * 1024 * 1024;

  /// Default per-file upload limit used by the 1.0 engine (25 MB).
  static const int defaultMaxFileMb = 25;

  // ---------------------------------------------------------------------------
  // Database
  // ---------------------------------------------------------------------------
  static const String databaseName = 'discord_media_sender.db';
  static const int databaseVersion = 4;

  // ---------------------------------------------------------------------------
  // Secure storage keys (carried over from 1.0 so credentials survive upgrades)
  // ---------------------------------------------------------------------------
  static const String keyBotToken = 'cfg_bot_token';
  static const String keyWebhookUrl = 'cfg_webhook_url';
  static const String keyBotName = 'cfg_bot_name';
  static const String keyAvatarUrl = 'cfg_avatar_url';
  static const String keyChannelId = 'cfg_channel_id';
  static const String keyChannelName = 'cfg_channel_name';
  static const String keyMode = 'cfg_mode';

  // ---------------------------------------------------------------------------
  // SharedPreferences keys (carried over from 1.0)
  // ---------------------------------------------------------------------------
  static const String prefThemeMode = 'set_theme_mode';
  static const String prefOnboardingDone = 'set_onboarding_done';
  static const String prefMaxFileMb = 'set_max_file_mb';
  static const String prefAutoUpdate = 'set_auto_update';
  static const String prefBatteryAsked = 'set_battery_asked';
  static const String prefOrientation = 'set_orientation';
  static const String prefUpdateLastCheckMs = 'set_update_last_check_ms';
  static const String prefUpdateSkippedTag = 'set_update_skipped_tag';

  // ---------------------------------------------------------------------------
  // 2.1 settings
  // ---------------------------------------------------------------------------

  /// Global bandwidth cap in kilobytes per second. `0` disables the cap.
  static const String prefBandwidthCapKb = 'set_bandwidth_cap_kb';

  /// How a cold start behaves when pending work exists:
  /// `off`, `ask` or `auto`.
  static const String prefSafeResume = 'set_safe_resume';

  /// The density of the home screen widget: `normal` or `compact`.
  static const String prefWidgetDensity = 'set_widget_density';

  /// Seconds the floating overlay stays hidden while the engine is idle.
  static const String prefOverlayAutoHide = 'set_overlay_auto_hide';

  /// Whether the floating overlay is enabled at all.
  static const String prefOverlayEnabled = 'set_overlay_enabled';

  // ---------------------------------------------------------------------------
  // Update behaviour
  // ---------------------------------------------------------------------------
  /// The 1.0 engine checked GitHub at most every 6 hours; preserved.
  static const Duration updateCheckInterval = Duration(hours: 6);

  // ---------------------------------------------------------------------------
  // Background execution
  // ---------------------------------------------------------------------------
  static const String foregroundChannelId = 'discord_media_sender_upload';
  static const String foregroundChannelName = 'Upload progress';
  static const String notificationChannelId =
      'discord_media_sender_notifications';
  static const String notificationChannelName = 'Notifications';

  // ---------------------------------------------------------------------------
  // Widgets
  // ---------------------------------------------------------------------------
  static const String homeWidgetId = 'dms_upload_status_widget';
  static const String widgetChannelName = 'Discord Media Sender Upload Widget';

  // ---------------------------------------------------------------------------
  // Premium palette (from the 2.0 design specification)
  // ---------------------------------------------------------------------------
  static const Color colorBackground = Color(0xFF11131C);
  static const Color colorSurface = Color(0xFF1C2030);
  static const Color colorPrimary = Color(0xFF8B5CF6);
  static const Color colorSuccess = Color(0xFF27C995);
  static const Color colorWarning = Color(0xFFF5B942);
  static const Color colorError = Color(0xFFF87171);

  static const Color colorSurfaceElevated = Color(0xFF242939);
  static const Color colorBorder = Color(0xFF2E3447);
  static const Color colorTextPrimary = Color(0xFFF2F3F7);
  static const Color colorTextSecondary = Color(0xFF9AA1B4);
  static const Color colorLightBackground = Color(0xFFF6F7FB);
  static const Color colorLightSurface = Color(0xFFFFFFFF);
}

/// Upload / destination operating modes.
enum SenderMode {
  webhook('webhook', 'Webhook'),
  bot('bot', 'Bot');

  const SenderMode(this.key, this.label);

  final String key;
  final String label;

  static SenderMode fromKey(String? key) => SenderMode.values.firstWhere(
    (m) => m.key == key,
    orElse: () => SenderMode.webhook,
  );
}

/// How a file is routed to one or more Discord destinations.
enum DistributionMode {
  broadcast('broadcast', 'Broadcast to all'),
  manual('manual', 'Manual selection'),
  roundRobin('round_robin', 'Round robin'),
  ruleBased('rule_based', 'Rule based'),
  sequential('sequential', 'Sequential');

  const DistributionMode(this.key, this.label);

  final String key;
  final String label;

  static DistributionMode fromKey(String? key) =>
      DistributionMode.values.firstWhere(
        (m) => m.key == key,
        orElse: () => DistributionMode.broadcast,
      );
}

/// The lifecycle of a single queued upload job.
enum UploadStatus {
  pending('pending'),
  uploading('uploading'),
  completed('completed'),
  failed('failed'),
  paused('paused'),
  cancelled('cancelled');

  const UploadStatus(this.key);

  final String key;

  /// Const aliases so that `switch` cases can use compile-time constants.
  static const String pendingKey = 'pending';
  static const String uploadingKey = 'uploading';
  static const String completedKey = 'completed';
  static const String failedKey = 'failed';
  static const String pausedKey = 'paused';
  static const String cancelledKey = 'cancelled';

  static UploadStatus fromKey(String? key) => UploadStatus.values.firstWhere(
    (s) => s.key == key,
    orElse: () => UploadStatus.pending,
  );
}

/// Lifecycle of a library entry.
enum MediaStatus {
  newFile('new'),
  duplicateDetected('duplicate_detected'),
  alreadyUploaded('already_uploaded'),
  pendingReview('pending_review'),
  uploading('uploading'),
  uploaded('uploaded'),
  archived('archived'),
  failed('failed');

  const MediaStatus(this.key);

  final String key;

  /// Const aliases so that `switch` cases can use compile-time constants.
  static const String newFileKey = 'new';
  static const String duplicateDetectedKey = 'duplicate_detected';
  static const String alreadyUploadedKey = 'already_uploaded';
  static const String pendingReviewKey = 'pending_review';
  static const String uploadingKey = 'uploading';
  static const String uploadedKey = 'uploaded';
  static const String archivedKey = 'archived';
  static const String failedKey = 'failed';

  static MediaStatus fromKey(String? key) => MediaStatus.values.firstWhere(
    (s) => s.key == key,
    orElse: () => MediaStatus.newFile,
  );
}

/// Duplicate handling policy.
enum DuplicatePolicy {
  skip('skip', 'Skip duplicate'),
  ask('ask', 'Ask before upload'),
  anyway('anyway', 'Upload anyway'),
  replace('replace', 'Replace library entry'),
  keepBoth('keep_both', 'Keep both');

  const DuplicatePolicy(this.key, this.label);

  final String key;
  final String label;

  static DuplicatePolicy fromKey(String? key) => DuplicatePolicy.values
      .firstWhere((p) => p.key == key, orElse: () => DuplicatePolicy.skip);
}

/// How a duplicate was detected.
enum DetectionMethod {
  sha256('sha256', 'SHA-256'),
  metadata('metadata', 'Metadata'),
  perceptual('perceptual', 'Perceptual hash');

  const DetectionMethod(this.key, this.label);

  final String key;
  final String label;

  static DetectionMethod fromKey(String? key) => DetectionMethod.values
      .firstWhere((m) => m.key == key, orElse: () => DetectionMethod.sha256);
}

/// Automatic-upload trigger.
enum AutoUploadMode {
  manual('manual', 'Manual upload'),
  semiAutomatic('semi_automatic', 'Semi-automatic'),
  fullyAutomatic('fully_automatic', 'Fully automatic');

  const AutoUploadMode(this.key, this.label);

  final String key;
  final String label;

  static AutoUploadMode fromKey(String? key) => AutoUploadMode.values
      .firstWhere((m) => m.key == key, orElse: () => AutoUploadMode.manual);
}

/// Archive categories.
enum ArchiveCategory {
  images('images', 'Images'),
  videos('videos', 'Videos'),
  audio('audio', 'Audio'),
  documents('documents', 'Documents'),
  other('other', 'Other files');

  const ArchiveCategory(this.key, this.label);

  final String key;
  final String label;

  static ArchiveCategory fromKey(String? key) => ArchiveCategory.values
      .firstWhere((c) => c.key == key, orElse: () => ArchiveCategory.other);
}

/// Media type buckets used across library, archive and analytics.
enum MediaCategory {
  image('image', 'Image'),
  video('video', 'Video'),
  audio('audio', 'Audio'),
  document('document', 'Document'),
  other('other', 'Other');

  const MediaCategory(this.key, this.label);

  final String key;
  final String label;

  static MediaCategory fromKey(String? key) => MediaCategory.values.firstWhere(
    (c) => c.key == key,
    orElse: () => MediaCategory.other,
  );
}

/// How a cold start behaves when the queue still holds pending work.
///
/// The 2.0 behaviour was to leave the queue untouched, which meant a killed
/// upload never continued on its own.
enum SafeResumePolicy {
  off('off', 'Never resume automatically'),
  ask('ask', 'Ask before resuming'),
  auto('auto', 'Resume automatically');

  const SafeResumePolicy(this.key, this.label);

  final String key;
  final String label;

  static SafeResumePolicy fromKey(String? key) => SafeResumePolicy.values
      .firstWhere((p) => p.key == key, orElse: () => SafeResumePolicy.ask);
}

/// The density of the home screen widget.
enum WidgetDensity {
  normal('normal', 'Normal'),
  compact('compact', 'Compact');

  const WidgetDensity(this.key, this.label);

  final String key;
  final String label;

  static WidgetDensity fromKey(String? key) => WidgetDensity.values.firstWhere(
    (d) => d.key == key,
    orElse: () => WidgetDensity.normal,
  );
}
