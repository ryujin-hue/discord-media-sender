import 'dart:convert';

import '../core/constants.dart';

/// Converts a [DateTime] to the integer representation used by SQLite.
int tsToInt(DateTime value) => value.millisecondsSinceEpoch;

/// Converts an integer timestamp back into a [DateTime].
DateTime intToTs(int? value) =>
    value == null ? DateTime.now() : DateTime.fromMillisecondsSinceEpoch(value);

/// A Discord destination: either a webhook or a bot + channel pair.
class Destination {
  const Destination({
    required this.id,
    required this.name,
    required this.type,
    required this.enabled,
    required this.createdAt,
    this.channelId,
    this.channelName,
    this.credentialProfileId,
    this.webhookId,
    this.avatarUrl,
    this.priority = 0,
    this.rateLimitUntil,
    this.lastActivityAt,
    this.totalSent = 0,
    this.totalFailed = 0,
    this.totalPending = 0,
    this.lastError,
    this.note,
  });

  final String id;
  final String name;
  final String type; // 'webhook' | 'bot'
  final bool enabled;
  final DateTime createdAt;
  final String? channelId;
  final String? channelName;
  final String? credentialProfileId;
  final String? webhookId;
  final String? avatarUrl;
  final int priority;
  final DateTime? rateLimitUntil;
  final DateTime? lastActivityAt;
  final int totalSent;
  final int totalFailed;
  final int totalPending;
  final String? lastError;
  final String? note;

  bool get isWebhook => type == 'webhook';

  bool get isRateLimited =>
      rateLimitUntil != null && rateLimitUntil!.isAfter(DateTime.now());

  Destination copyWith({
    String? name,
    bool? enabled,
    String? channelId,
    String? channelName,
    String? credentialProfileId,
    String? webhookId,
    String? avatarUrl,
    int? priority,
    DateTime? rateLimitUntil,
    bool clearRateLimit = false,
    DateTime? lastActivityAt,
    int? totalSent,
    int? totalFailed,
    int? totalPending,
    String? lastError,
    bool clearLastError = false,
    String? note,
  }) {
    return Destination(
      id: id,
      name: name ?? this.name,
      type: type,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      channelId: channelId ?? this.channelId,
      channelName: channelName ?? this.channelName,
      credentialProfileId: credentialProfileId ?? this.credentialProfileId,
      webhookId: webhookId ?? this.webhookId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      priority: priority ?? this.priority,
      rateLimitUntil: clearRateLimit
          ? null
          : (rateLimitUntil ?? this.rateLimitUntil),
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      totalSent: totalSent ?? this.totalSent,
      totalFailed: totalFailed ?? this.totalFailed,
      totalPending: totalPending ?? this.totalPending,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      note: note ?? this.note,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'name': name,
    'type': type,
    'enabled': enabled ? 1 : 0,
    'created_at': tsToInt(createdAt),
    'channel_id': channelId,
    'channel_name': channelName,
    'credential_profile_id': credentialProfileId,
    'webhook_id': webhookId,
    'avatar_url': avatarUrl,
    'priority': priority,
    'rate_limit_until': rateLimitUntil == null
        ? null
        : tsToInt(rateLimitUntil!),
    'last_activity_at': lastActivityAt == null
        ? null
        : tsToInt(lastActivityAt!),
    'total_sent': totalSent,
    'total_failed': totalFailed,
    'total_pending': totalPending,
    'last_error': lastError,
    'note': note,
  };

  factory Destination.fromMap(Map<String, Object?> map) => Destination(
    id: map['id'] as String,
    name: map['name'] as String? ?? '',
    type: map['type'] as String? ?? 'webhook',
    enabled: (map['enabled'] as int? ?? 1) == 1,
    createdAt: intToTs(map['created_at'] as int?),
    channelId: map['channel_id'] as String?,
    channelName: map['channel_name'] as String?,
    credentialProfileId: map['credential_profile_id'] as String?,
    webhookId: map['webhook_id'] as String?,
    avatarUrl: map['avatar_url'] as String?,
    priority: map['priority'] as int? ?? 0,
    rateLimitUntil: map['rate_limit_until'] == null
        ? null
        : intToTs(map['rate_limit_until'] as int?),
    lastActivityAt: map['last_activity_at'] == null
        ? null
        : intToTs(map['last_activity_at'] as int?),
    totalSent: map['total_sent'] as int? ?? 0,
    totalFailed: map['total_failed'] as int? ?? 0,
    totalPending: map['total_pending'] as int? ?? 0,
    lastError: map['last_error'] as String?,
    note: map['note'] as String?,
  );
}

/// A stored Discord credential profile. Secrets live in the secure store; only
/// the reference and status live in SQLite.
class CredentialProfile {
  const CredentialProfile({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    this.botUserId,
    this.botUserName,
    this.avatarUrl,
    this.lastValidatedAt,
    this.isValid,
    this.statusMessage,
    this.hasWebhook = false,
    this.hasBotToken = false,
  });

  final String id;
  final String name;
  final String type; // 'webhook' | 'bot'
  final DateTime createdAt;
  final String? botUserId;
  final String? botUserName;
  final String? avatarUrl;
  final DateTime? lastValidatedAt;
  final bool? isValid;
  final String? statusMessage;
  final bool hasWebhook;
  final bool hasBotToken;

  CredentialProfile copyWith({
    String? name,
    String? botUserId,
    String? botUserName,
    String? avatarUrl,
    DateTime? lastValidatedAt,
    bool? isValid,
    String? statusMessage,
    bool clearStatus = false,
    bool? hasWebhook,
    bool? hasBotToken,
  }) {
    return CredentialProfile(
      id: id,
      name: name ?? this.name,
      type: type,
      createdAt: createdAt,
      botUserId: botUserId ?? this.botUserId,
      botUserName: botUserName ?? this.botUserName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastValidatedAt: lastValidatedAt ?? this.lastValidatedAt,
      isValid: isValid ?? this.isValid,
      statusMessage: clearStatus ? null : (statusMessage ?? this.statusMessage),
      hasWebhook: hasWebhook ?? this.hasWebhook,
      hasBotToken: hasBotToken ?? this.hasBotToken,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'name': name,
    'type': type,
    'created_at': tsToInt(createdAt),
    'bot_user_id': botUserId,
    'bot_user_name': botUserName,
    'avatar_url': avatarUrl,
    'last_validated_at': lastValidatedAt == null
        ? null
        : tsToInt(lastValidatedAt!),
    'is_valid': isValid == null ? null : (isValid! ? 1 : 0),
    'status_message': statusMessage,
    'has_webhook': hasWebhook ? 1 : 0,
    'has_bot_token': hasBotToken ? 1 : 0,
  };

  factory CredentialProfile.fromMap(Map<String, Object?> map) =>
      CredentialProfile(
        id: map['id'] as String,
        name: map['name'] as String? ?? '',
        type: map['type'] as String? ?? 'webhook',
        createdAt: intToTs(map['created_at'] as int?),
        botUserId: map['bot_user_id'] as String?,
        botUserName: map['bot_user_name'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        lastValidatedAt: map['last_validated_at'] == null
            ? null
            : intToTs(map['last_validated_at'] as int?),
        isValid: map['is_valid'] == null ? null : (map['is_valid'] as int) == 1,
        statusMessage: map['status_message'] as String?,
        hasWebhook: (map['has_webhook'] as int? ?? 0) == 1,
        hasBotToken: (map['has_bot_token'] as int? ?? 0) == 1,
      );
}

/// A file tracked in the media library.
class MediaLibraryEntry {
  const MediaLibraryEntry({
    required this.id,
    required this.path,
    required this.name,
    required this.size,
    required this.addedAt,
    required this.status,
    this.mimeType,
    this.category = 'other',
    this.sha256,
    this.favorite = false,
    this.collectionId,
    this.modifiedAt,
    this.lastActivityAt,
    this.width,
    this.height,
    this.durationMs,
    this.thumbnailPath,
    this.archivedAt,
    this.sourceFolder,
  });

  final String id;
  final String path;
  final String name;
  final int size;
  final DateTime addedAt;
  final String status;
  final String? mimeType;
  final String category;
  final String? sha256;
  final bool favorite;
  final String? collectionId;
  final DateTime? modifiedAt;
  final DateTime? lastActivityAt;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? thumbnailPath;
  final DateTime? archivedAt;
  final String? sourceFolder;

  bool get isArchived => archivedAt != null;

  MediaLibraryEntry copyWith({
    String? path,
    String? name,
    int? size,
    String? status,
    String? mimeType,
    String? category,
    String? sha256,
    bool? favorite,
    String? collectionId,
    bool clearCollection = false,
    DateTime? modifiedAt,
    DateTime? lastActivityAt,
    int? width,
    int? height,
    int? durationMs,
    String? thumbnailPath,
    DateTime? archivedAt,
    bool clearArchived = false,
    String? sourceFolder,
  }) {
    return MediaLibraryEntry(
      id: id,
      path: path ?? this.path,
      name: name ?? this.name,
      size: size ?? this.size,
      addedAt: addedAt,
      status: status ?? this.status,
      mimeType: mimeType ?? this.mimeType,
      category: category ?? this.category,
      sha256: sha256 ?? this.sha256,
      favorite: favorite ?? this.favorite,
      collectionId: clearCollection
          ? null
          : (collectionId ?? this.collectionId),
      modifiedAt: modifiedAt ?? this.modifiedAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      archivedAt: clearArchived ? null : (archivedAt ?? this.archivedAt),
      sourceFolder: sourceFolder ?? this.sourceFolder,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'path': path,
    'name': name,
    'size': size,
    'added_at': tsToInt(addedAt),
    'status': status,
    'mime_type': mimeType,
    'category': category,
    'sha256': sha256,
    'favorite': favorite ? 1 : 0,
    'collection_id': collectionId,
    'modified_at': modifiedAt == null ? null : tsToInt(modifiedAt!),
    'last_activity_at': lastActivityAt == null
        ? null
        : tsToInt(lastActivityAt!),
    'width': width,
    'height': height,
    'duration_ms': durationMs,
    'thumbnail_path': thumbnailPath,
    'archived_at': archivedAt == null ? null : tsToInt(archivedAt!),
    'source_folder': sourceFolder,
  };

  factory MediaLibraryEntry.fromMap(Map<String, Object?> map) =>
      MediaLibraryEntry(
        id: map['id'] as String,
        path: map['path'] as String? ?? '',
        name: map['name'] as String? ?? '',
        size: map['size'] as int? ?? 0,
        addedAt: intToTs(map['added_at'] as int?),
        status: map['status'] as String? ?? MediaStatus.newFile.key,
        mimeType: map['mime_type'] as String?,
        category: map['category'] as String? ?? 'other',
        sha256: map['sha256'] as String?,
        favorite: (map['favorite'] as int? ?? 0) == 1,
        collectionId: map['collection_id'] as String?,
        modifiedAt: map['modified_at'] == null
            ? null
            : intToTs(map['modified_at'] as int?),
        lastActivityAt: map['last_activity_at'] == null
            ? null
            : intToTs(map['last_activity_at'] as int?),
        width: map['width'] as int?,
        height: map['height'] as int?,
        durationMs: map['duration_ms'] as int?,
        thumbnailPath: map['thumbnail_path'] as String?,
        archivedAt: map['archived_at'] == null
            ? null
            : intToTs(map['archived_at'] as int?),
        sourceFolder: map['source_folder'] as String?,
      );
}

/// A user defined collection of library entries.
class MediaCollection {
  const MediaCollection({
    required this.id,
    required this.name,
    required this.createdAt,
    this.description,
    this.colorValue,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final String? description;
  final int? colorValue;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'name': name,
    'created_at': tsToInt(createdAt),
    'description': description,
    'color_value': colorValue,
  };

  factory MediaCollection.fromMap(Map<String, Object?> map) => MediaCollection(
    id: map['id'] as String,
    name: map['name'] as String? ?? '',
    createdAt: intToTs(map['created_at'] as int?),
    description: map['description'] as String?,
    colorValue: map['color_value'] as int?,
  );
}

/// A folder watched for new media.
class WatchedFolder {
  const WatchedFolder({
    required this.id,
    required this.path,
    required this.enabled,
    required this.createdAt,
    this.name,
    this.lastScanAt,
    this.includePatterns = '',
    this.excludePatterns = '',
    this.maxFileMb = 0,
    this.recursive = true,
  });

  final String id;
  final String path;
  final bool enabled;
  final DateTime createdAt;
  final String? name;
  final DateTime? lastScanAt;
  final String includePatterns;
  final String excludePatterns;
  final int maxFileMb;
  final bool recursive;

  WatchedFolder copyWith({
    bool? enabled,
    DateTime? lastScanAt,
    String? includePatterns,
    String? excludePatterns,
    int? maxFileMb,
    bool? recursive,
    String? name,
  }) {
    return WatchedFolder(
      id: id,
      path: path,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      name: name ?? this.name,
      lastScanAt: lastScanAt ?? this.lastScanAt,
      includePatterns: includePatterns ?? this.includePatterns,
      excludePatterns: excludePatterns ?? this.excludePatterns,
      maxFileMb: maxFileMb ?? this.maxFileMb,
      recursive: recursive ?? this.recursive,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'path': path,
    'enabled': enabled ? 1 : 0,
    'created_at': tsToInt(createdAt),
    'name': name,
    'last_scan_at': lastScanAt == null ? null : tsToInt(lastScanAt!),
    'include_patterns': includePatterns,
    'exclude_patterns': excludePatterns,
    'max_file_mb': maxFileMb,
    'recursive': recursive ? 1 : 0,
  };

  factory WatchedFolder.fromMap(Map<String, Object?> map) => WatchedFolder(
    id: map['id'] as String,
    path: map['path'] as String? ?? '',
    enabled: (map['enabled'] as int? ?? 1) == 1,
    createdAt: intToTs(map['created_at'] as int?),
    name: map['name'] as String?,
    lastScanAt: map['last_scan_at'] == null
        ? null
        : intToTs(map['last_scan_at'] as int?),
    includePatterns: map['include_patterns'] as String? ?? '',
    excludePatterns: map['exclude_patterns'] as String? ?? '',
    maxFileMb: map['max_file_mb'] as int? ?? 0,
    recursive: (map['recursive'] as int? ?? 1) == 1,
  );
}

/// A rule that automates uploads for watched folders.
class AutoUploadRule {
  const AutoUploadRule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.mode,
    required this.destinationIds,
    required this.createdAt,
    this.watchedFolderId,
    this.includePatterns = '',
    this.excludePatterns = '',
    this.maxFileMb = 0,
    this.priority = 0,
    this.duplicatePolicy = 'skip',
    this.retryLimit = 3,
    this.scheduleEnabled = false,
    this.scheduleStartMinutes = 0,
    this.scheduleDurationMinutes = 60,
    this.weekdays = '',
  });

  final String id;
  final String name;
  final bool enabled;
  final String mode;
  final List<String> destinationIds;
  final DateTime createdAt;
  final String? watchedFolderId;
  final String includePatterns;
  final String excludePatterns;
  final int maxFileMb;
  final int priority;
  final String duplicatePolicy;
  final int retryLimit;
  final bool scheduleEnabled;
  final int scheduleStartMinutes;
  final int scheduleDurationMinutes;
  final String weekdays;

  AutoUploadRule copyWith({
    String? name,
    bool? enabled,
    String? mode,
    List<String>? destinationIds,
    String? includePatterns,
    String? excludePatterns,
    int? maxFileMb,
    int? priority,
    String? duplicatePolicy,
    int? retryLimit,
    bool? scheduleEnabled,
    int? scheduleStartMinutes,
    int? scheduleDurationMinutes,
    String? weekdays,
  }) {
    return AutoUploadRule(
      id: id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      destinationIds: destinationIds ?? this.destinationIds,
      createdAt: createdAt,
      watchedFolderId: watchedFolderId,
      includePatterns: includePatterns ?? this.includePatterns,
      excludePatterns: excludePatterns ?? this.excludePatterns,
      maxFileMb: maxFileMb ?? this.maxFileMb,
      priority: priority ?? this.priority,
      duplicatePolicy: duplicatePolicy ?? this.duplicatePolicy,
      retryLimit: retryLimit ?? this.retryLimit,
      scheduleEnabled: scheduleEnabled ?? this.scheduleEnabled,
      scheduleStartMinutes: scheduleStartMinutes ?? this.scheduleStartMinutes,
      scheduleDurationMinutes:
          scheduleDurationMinutes ?? this.scheduleDurationMinutes,
      weekdays: weekdays ?? this.weekdays,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'name': name,
    'enabled': enabled ? 1 : 0,
    'mode': mode,
    'destination_ids': jsonEncode(destinationIds),
    'created_at': tsToInt(createdAt),
    'watched_folder_id': watchedFolderId,
    'include_patterns': includePatterns,
    'exclude_patterns': excludePatterns,
    'max_file_mb': maxFileMb,
    'priority': priority,
    'duplicate_policy': duplicatePolicy,
    'retry_limit': retryLimit,
    'schedule_enabled': scheduleEnabled ? 1 : 0,
    'schedule_start_minutes': scheduleStartMinutes,
    'schedule_duration_minutes': scheduleDurationMinutes,
    'weekdays': weekdays,
  };

  factory AutoUploadRule.fromMap(Map<String, Object?> map) {
    List<String> ids = <String>[];
    try {
      final Object? decoded = jsonDecode(
        map['destination_ids'] as String? ?? '[]',
      );
      if (decoded is List) ids = decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return AutoUploadRule(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      enabled: (map['enabled'] as int? ?? 1) == 1,
      mode: map['mode'] as String? ?? AutoUploadMode.manual.key,
      destinationIds: ids,
      createdAt: intToTs(map['created_at'] as int?),
      watchedFolderId: map['watched_folder_id'] as String?,
      includePatterns: map['include_patterns'] as String? ?? '',
      excludePatterns: map['exclude_patterns'] as String? ?? '',
      maxFileMb: map['max_file_mb'] as int? ?? 0,
      priority: map['priority'] as int? ?? 0,
      duplicatePolicy: map['duplicate_policy'] as String? ?? 'skip',
      retryLimit: map['retry_limit'] as int? ?? 3,
      scheduleEnabled: (map['schedule_enabled'] as int? ?? 0) == 1,
      scheduleStartMinutes: map['schedule_start_minutes'] as int? ?? 0,
      scheduleDurationMinutes: map['schedule_duration_minutes'] as int? ?? 60,
      weekdays: map['weekdays'] as String? ?? '',
    );
  }
}

/// A queued job that distributes one file to one or more destinations.
class DistributionJob {
  const DistributionJob({
    required this.id,
    required this.filePath,
    required this.fileName,
    required this.fileSize,
    required this.status,
    required this.createdAt,
    required this.destinationId,
    this.destinationName,
    this.sha256,
    this.retryCount = 0,
    this.priority = 0,
    this.errorMessage,
    this.httpCode,
    this.discordCode,
    this.messageId,
    this.startedAt,
    this.completedAt,
    this.bytesSent = 0,
    this.totalBytes = 0,
    this.batchIndex = 0,
    this.caption,
  });

  final String id;
  final String filePath;
  final String fileName;
  final int fileSize;
  final String status;
  final DateTime createdAt;
  final String destinationId;
  final String? destinationName;
  final String? sha256;
  final int retryCount;
  final int priority;
  final String? errorMessage;
  final int? httpCode;
  final int? discordCode;
  final String? messageId;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int bytesSent;
  final int totalBytes;
  final int batchIndex;
  final String? caption;

  DistributionJob copyWith({
    String? status,
    int? retryCount,
    String? errorMessage,
    bool clearError = false,
    int? httpCode,
    int? discordCode,
    String? messageId,
    DateTime? startedAt,
    DateTime? completedAt,
    int? bytesSent,
    int? totalBytes,
    int? batchIndex,
    String? caption,
    String? destinationName,
    String? sha256,
    int? priority,
  }) {
    return DistributionJob(
      id: id,
      filePath: filePath,
      fileName: fileName,
      fileSize: fileSize,
      status: status ?? this.status,
      createdAt: createdAt,
      destinationId: destinationId,
      destinationName: destinationName ?? this.destinationName,
      sha256: sha256 ?? this.sha256,
      retryCount: retryCount ?? this.retryCount,
      priority: priority ?? this.priority,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      httpCode: httpCode ?? this.httpCode,
      discordCode: discordCode ?? this.discordCode,
      messageId: messageId ?? this.messageId,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      bytesSent: bytesSent ?? this.bytesSent,
      totalBytes: totalBytes ?? this.totalBytes,
      batchIndex: batchIndex ?? this.batchIndex,
      caption: caption ?? this.caption,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'file_path': filePath,
    'file_name': fileName,
    'file_size': fileSize,
    'status': status,
    'created_at': tsToInt(createdAt),
    'destination_id': destinationId,
    'destination_name': destinationName,
    'sha256': sha256,
    'retry_count': retryCount,
    'priority': priority,
    'error_message': errorMessage,
    'http_code': httpCode,
    'discord_code': discordCode,
    'message_id': messageId,
    'started_at': startedAt == null ? null : tsToInt(startedAt!),
    'completed_at': completedAt == null ? null : tsToInt(completedAt!),
    'bytes_sent': bytesSent,
    'total_bytes': totalBytes,
    'batch_index': batchIndex,
    'caption': caption,
  };

  factory DistributionJob.fromMap(Map<String, Object?> map) => DistributionJob(
    id: map['id'] as String,
    filePath: map['file_path'] as String? ?? '',
    fileName: map['file_name'] as String? ?? '',
    fileSize: map['file_size'] as int? ?? 0,
    status: map['status'] as String? ?? UploadStatus.pending.key,
    createdAt: intToTs(map['created_at'] as int?),
    destinationId: map['destination_id'] as String? ?? '',
    destinationName: map['destination_name'] as String?,
    sha256: map['sha256'] as String?,
    retryCount: map['retry_count'] as int? ?? 0,
    priority: map['priority'] as int? ?? 0,
    errorMessage: map['error_message'] as String?,
    httpCode: map['http_code'] as int?,
    discordCode: map['discord_code'] as int?,
    messageId: map['message_id'] as String?,
    startedAt: map['started_at'] == null
        ? null
        : intToTs(map['started_at'] as int?),
    completedAt: map['completed_at'] == null
        ? null
        : intToTs(map['completed_at'] as int?),
    bytesSent: map['bytes_sent'] as int? ?? 0,
    totalBytes: map['total_bytes'] as int? ?? 0,
    batchIndex: map['batch_index'] as int? ?? 0,
    caption: map['caption'] as String?,
  );
}

/// A record proving that a file was delivered to one specific destination.
class DeliveryRecord {
  const DeliveryRecord({
    required this.id,
    required this.sha256,
    required this.destinationId,
    required this.deliveredAt,
    required this.fileName,
    this.fileSize = 0,
    this.filePath,
    this.messageId,
    this.messageUrl,
    this.jobId,
    this.attachmentUrl,
  });

  final String id;
  final String sha256;
  final String destinationId;
  final DateTime deliveredAt;
  final String fileName;
  final int fileSize;
  final String? filePath;
  final String? messageId;
  final String? messageUrl;
  final String? jobId;
  final String? attachmentUrl;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'sha256': sha256,
    'destination_id': destinationId,
    'delivered_at': tsToInt(deliveredAt),
    'file_name': fileName,
    'file_size': fileSize,
    'file_path': filePath,
    'message_id': messageId,
    'message_url': messageUrl,
    'job_id': jobId,
    'attachment_url': attachmentUrl,
  };

  factory DeliveryRecord.fromMap(Map<String, Object?> map) => DeliveryRecord(
    id: map['id'] as String,
    sha256: map['sha256'] as String? ?? '',
    destinationId: map['destination_id'] as String? ?? '',
    deliveredAt: intToTs(map['delivered_at'] as int?),
    fileName: map['file_name'] as String? ?? '',
    fileSize: map['file_size'] as int? ?? 0,
    filePath: map['file_path'] as String?,
    messageId: map['message_id'] as String?,
    messageUrl: map['message_url'] as String?,
    jobId: map['job_id'] as String?,
    attachmentUrl: map['attachment_url'] as String?,
  );
}

/// A legacy 1.0 session migrated into the 2.0 history table.
class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.mode,
    required this.target,
    required this.totalFiles,
    required this.success,
    required this.failed,
    required this.status,
    this.reason,
    this.heartbeatAt,
  });

  final int id;
  final DateTime startedAt;
  final DateTime endedAt;
  final String mode;
  final String target;
  final int totalFiles;
  final int success;
  final int failed;
  final String status;
  final String? reason;
  final DateTime? heartbeatAt;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'started_at': tsToInt(startedAt),
    'ended_at': tsToInt(endedAt),
    'mode': mode,
    'target': target,
    'total_files': totalFiles,
    'success': success,
    'failed': failed,
    'status': status,
    'reason': reason,
    'heartbeat_at': heartbeatAt == null ? null : tsToInt(heartbeatAt!),
  };

  factory SessionRecord.fromMap(Map<String, Object?> map) => SessionRecord(
    id: map['id'] as int? ?? 0,
    startedAt: intToTs(map['started_at'] as int?),
    endedAt: intToTs(map['ended_at'] as int?),
    mode: map['mode'] as String? ?? '',
    target: map['target'] as String? ?? '',
    totalFiles: map['total_files'] as int? ?? 0,
    success: map['success'] as int? ?? 0,
    failed: map['failed'] as int? ?? 0,
    status: map['status'] as String? ?? '',
    reason: map['reason'] as String?,
    heartbeatAt: map['heartbeat_at'] == null
        ? null
        : intToTs(map['heartbeat_at'] as int?),
  );
}

/// A file inside a legacy 1.0 session.
class SessionFileRecord {
  const SessionFileRecord({
    required this.sessionId,
    required this.idx,
    required this.path,
    required this.name,
    required this.size,
    required this.status,
    this.error,
  });

  final int sessionId;
  final int idx;
  final String path;
  final String name;
  final int size;
  final String status;
  final String? error;

  Map<String, Object?> toMap() => <String, Object?>{
    'session_id': sessionId,
    'idx': idx,
    'path': path,
    'name': name,
    'size': size,
    'status': status,
    'error': error,
  };

  factory SessionFileRecord.fromMap(Map<String, Object?> map) =>
      SessionFileRecord(
        sessionId: map['session_id'] as int? ?? 0,
        idx: map['idx'] as int? ?? 0,
        path: map['path'] as String? ?? '',
        name: map['name'] as String? ?? '',
        size: map['size'] as int? ?? 0,
        status: map['status'] as String? ?? 'pending',
        error: map['error'] as String?,
      );
}

/// A legacy 1.0 failure record migrated into the 2.0 history table.
class FailureRecord {
  const FailureRecord({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.sizeBytes,
    required this.batchIndex,
    required this.errorMessage,
    required this.mode,
    required this.target,
    required this.createdAt,
    this.sessionId,
    this.httpCode,
    this.discordCode,
  });

  final int id;
  final String? sessionId;
  final String fileName;
  final String filePath;
  final int sizeBytes;
  final int batchIndex;
  final int? httpCode;
  final int? discordCode;
  final String errorMessage;
  final String mode;
  final String target;
  final DateTime createdAt;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'session_id': sessionId,
    'file_name': fileName,
    'file_path': filePath,
    'size_bytes': sizeBytes,
    'batch_index': batchIndex,
    'http_code': httpCode,
    'discord_code': discordCode,
    'error_message': errorMessage,
    'mode': mode,
    'target': target,
    'created_at': tsToInt(createdAt),
  };

  factory FailureRecord.fromMap(Map<String, Object?> map) => FailureRecord(
    id: map['id'] as int? ?? 0,
    sessionId: map['session_id']?.toString(),
    fileName: map['file_name'] as String? ?? '',
    filePath: map['file_path'] as String? ?? '',
    sizeBytes: map['size_bytes'] as int? ?? 0,
    batchIndex: map['batch_index'] as int? ?? 0,
    httpCode: map['http_code'] as int?,
    discordCode: map['discord_code'] as int?,
    errorMessage: map['error_message'] as String? ?? '',
    mode: map['mode'] as String? ?? '',
    target: map['target'] as String? ?? '',
    createdAt: intToTs(map['created_at'] as int?),
  );
}

/// A detected duplicate relationship between two library entries.
class DuplicateRecord {
  const DuplicateRecord({
    required this.id,
    required this.originalId,
    required this.duplicateId,
    required this.method,
    required this.detectedAt,
    this.decision,
    this.similarity,
    this.originalPath,
    this.duplicatePath,
    this.originalName,
    this.duplicateName,
  });

  final String id;
  final String originalId;
  final String duplicateId;
  final String method;
  final DateTime detectedAt;
  final String? decision;
  final double? similarity;
  final String? originalPath;
  final String? duplicatePath;
  final String? originalName;
  final String? duplicateName;

  DuplicateRecord copyWith({String? decision, double? similarity}) =>
      DuplicateRecord(
        id: id,
        originalId: originalId,
        duplicateId: duplicateId,
        method: method,
        detectedAt: detectedAt,
        decision: decision ?? this.decision,
        similarity: similarity ?? this.similarity,
        originalPath: originalPath,
        duplicatePath: duplicatePath,
        originalName: originalName,
        duplicateName: duplicateName,
      );

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'original_id': originalId,
    'duplicate_id': duplicateId,
    'method': method,
    'detected_at': tsToInt(detectedAt),
    'decision': decision,
    'similarity': similarity,
    'original_path': originalPath,
    'duplicate_path': duplicatePath,
    'original_name': originalName,
    'duplicate_name': duplicateName,
  };

  factory DuplicateRecord.fromMap(Map<String, Object?> map) => DuplicateRecord(
    id: map['id'] as String,
    originalId: map['original_id'] as String? ?? '',
    duplicateId: map['duplicate_id'] as String? ?? '',
    method: map['method'] as String? ?? DetectionMethod.sha256.key,
    detectedAt: intToTs(map['detected_at'] as int?),
    decision: map['decision'] as String?,
    similarity: (map['similarity'] as num?)?.toDouble(),
    originalPath: map['original_path'] as String?,
    duplicatePath: map['duplicate_path'] as String?,
    originalName: map['original_name'] as String?,
    duplicateName: map['duplicate_name'] as String?,
  );
}

/// An archived library entry.
class ArchiveRecord {
  const ArchiveRecord({
    required this.id,
    required this.mediaId,
    required this.archivedAt,
    required this.category,
    required this.fileName,
    required this.fileSize,
    this.restoredAt,
    this.originalPath,
    this.archivePath,
    this.destinationId,
    this.note,
  });

  final String id;
  final String mediaId;
  final DateTime archivedAt;
  final String category;
  final String fileName;
  final int fileSize;
  final DateTime? restoredAt;
  final String? originalPath;
  final String? archivePath;
  final String? destinationId;
  final String? note;

  bool get isRestored => restoredAt != null;

  ArchiveRecord copyWith({DateTime? restoredAt, bool clearRestored = false}) =>
      ArchiveRecord(
        id: id,
        mediaId: mediaId,
        archivedAt: archivedAt,
        category: category,
        fileName: fileName,
        fileSize: fileSize,
        restoredAt: clearRestored ? null : (restoredAt ?? this.restoredAt),
        originalPath: originalPath,
        archivePath: archivePath,
        destinationId: destinationId,
        note: note,
      );

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'media_id': mediaId,
    'archived_at': tsToInt(archivedAt),
    'category': category,
    'file_name': fileName,
    'file_size': fileSize,
    'restored_at': restoredAt == null ? null : tsToInt(restoredAt!),
    'original_path': originalPath,
    'archive_path': archivePath,
    'destination_id': destinationId,
    'note': note,
  };

  factory ArchiveRecord.fromMap(Map<String, Object?> map) => ArchiveRecord(
    id: map['id'] as String,
    mediaId: map['media_id'] as String? ?? '',
    archivedAt: intToTs(map['archived_at'] as int?),
    category: map['category'] as String? ?? 'other',
    fileName: map['file_name'] as String? ?? '',
    fileSize: map['file_size'] as int? ?? 0,
    restoredAt: map['restored_at'] == null
        ? null
        : intToTs(map['restored_at'] as int?),
    originalPath: map['original_path'] as String?,
    archivePath: map['archive_path'] as String?,
    destinationId: map['destination_id'] as String?,
    note: map['note'] as String?,
  );
}

/// An automatic archiving rule.
class ArchiveRule {
  const ArchiveRule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.createdAt,
    this.archiveAfterUpload = false,
    this.archiveAfterDays,
    this.categories = '',
    this.excludeFavorites = true,
    this.excludeFolders = '',
    this.excludePendingReview = true,
    this.maxAgeDays,
  });

  final String id;
  final String name;
  final bool enabled;
  final DateTime createdAt;
  final bool archiveAfterUpload;
  final int? archiveAfterDays;
  final String categories;
  final bool excludeFavorites;
  final String excludeFolders;
  final bool excludePendingReview;
  final int? maxAgeDays;

  ArchiveRule copyWith({
    String? name,
    bool? enabled,
    bool? archiveAfterUpload,
    int? archiveAfterDays,
    bool clearArchiveAfterDays = false,
    String? categories,
    bool? excludeFavorites,
    String? excludeFolders,
    bool? excludePendingReview,
    int? maxAgeDays,
    bool clearMaxAgeDays = false,
  }) {
    return ArchiveRule(
      id: id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt,
      archiveAfterUpload: archiveAfterUpload ?? this.archiveAfterUpload,
      archiveAfterDays: clearArchiveAfterDays
          ? null
          : (archiveAfterDays ?? this.archiveAfterDays),
      categories: categories ?? this.categories,
      excludeFavorites: excludeFavorites ?? this.excludeFavorites,
      excludeFolders: excludeFolders ?? this.excludeFolders,
      excludePendingReview: excludePendingReview ?? this.excludePendingReview,
      maxAgeDays: clearMaxAgeDays ? null : (maxAgeDays ?? this.maxAgeDays),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'name': name,
    'enabled': enabled ? 1 : 0,
    'created_at': tsToInt(createdAt),
    'archive_after_upload': archiveAfterUpload ? 1 : 0,
    'archive_after_days': archiveAfterDays,
    'categories': categories,
    'exclude_favorites': excludeFavorites ? 1 : 0,
    'exclude_folders': excludeFolders,
    'exclude_pending_review': excludePendingReview ? 1 : 0,
    'max_age_days': maxAgeDays,
  };

  factory ArchiveRule.fromMap(Map<String, Object?> map) => ArchiveRule(
    id: map['id'] as String,
    name: map['name'] as String? ?? '',
    enabled: (map['enabled'] as int? ?? 0) == 1,
    createdAt: intToTs(map['created_at'] as int?),
    archiveAfterUpload: (map['archive_after_upload'] as int? ?? 0) == 1,
    archiveAfterDays: map['archive_after_days'] as int?,
    categories: map['categories'] as String? ?? '',
    excludeFavorites: (map['exclude_favorites'] as int? ?? 1) == 1,
    excludeFolders: map['exclude_folders'] as String? ?? '',
    excludePendingReview: (map['exclude_pending_review'] as int? ?? 1) == 1,
    maxAgeDays: map['max_age_days'] as int?,
  );
}

/// A log entry describing an archive operation.
class ArchiveOperation {
  const ArchiveOperation({
    required this.id,
    required this.operation,
    required this.createdAt,
    required this.itemCount,
    this.mediaId,
    this.detail,
  });

  final String id;
  final String operation;
  final DateTime createdAt;
  final int itemCount;
  final String? mediaId;
  final String? detail;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'operation': operation,
    'created_at': tsToInt(createdAt),
    'item_count': itemCount,
    'media_id': mediaId,
    'detail': detail,
  };

  factory ArchiveOperation.fromMap(Map<String, Object?> map) =>
      ArchiveOperation(
        id: map['id'] as String,
        operation: map['operation'] as String? ?? '',
        createdAt: intToTs(map['created_at'] as int?),
        itemCount: map['item_count'] as int? ?? 0,
        mediaId: map['media_id'] as String?,
        detail: map['detail'] as String?,
      );
}

/// A live timeline event.
class LiveActivityEvent {
  const LiveActivityEvent({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.message,
    this.fileName,
    this.destinationId,
    this.destinationName,
    this.detail,
    this.severity = 'info',
  });

  final String id;
  final String type;
  final DateTime createdAt;
  final String message;
  final String? fileName;
  final String? destinationId;
  final String? destinationName;
  final String? detail;
  final String severity;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'type': type,
    'created_at': tsToInt(createdAt),
    'message': message,
    'file_name': fileName,
    'destination_id': destinationId,
    'destination_name': destinationName,
    'detail': detail,
    'severity': severity,
  };

  factory LiveActivityEvent.fromMap(Map<String, Object?> map) =>
      LiveActivityEvent(
        id: map['id'] as String,
        type: map['type'] as String? ?? 'info',
        createdAt: intToTs(map['created_at'] as int?),
        message: map['message'] as String? ?? '',
        fileName: map['file_name'] as String?,
        destinationId: map['destination_id'] as String?,
        destinationName: map['destination_name'] as String?,
        detail: map['detail'] as String?,
        severity: map['severity'] as String? ?? 'info',
      );
}

/// A row in the upload history table.
class UploadHistoryEntry {
  const UploadHistoryEntry({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.sha256,
    this.destinationId,
    this.destinationName,
    this.mode,
    this.target,
    this.errorMessage,
    this.httpCode,
    this.discordCode,
    this.retryCount = 0,
    this.messageId,
    this.messageUrl,
    this.sessionId,
    this.migratedFrom = '',
  });

  final String id;
  final String fileName;
  final String filePath;
  final int fileSize;
  final String status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? sha256;
  final String? destinationId;
  final String? destinationName;
  final String? mode;
  final String? target;
  final String? errorMessage;
  final int? httpCode;
  final int? discordCode;
  final int retryCount;
  final String? messageId;
  final String? messageUrl;
  final String? sessionId;
  final String migratedFrom;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'file_name': fileName,
    'file_path': filePath,
    'file_size': fileSize,
    'status': status,
    'created_at': tsToInt(createdAt),
    'completed_at': completedAt == null ? null : tsToInt(completedAt!),
    'sha256': sha256,
    'destination_id': destinationId,
    'destination_name': destinationName,
    'mode': mode,
    'target': target,
    'error_message': errorMessage,
    'http_code': httpCode,
    'discord_code': discordCode,
    'retry_count': retryCount,
    'message_id': messageId,
    'message_url': messageUrl,
    'session_id': sessionId,
    'migrated_from': migratedFrom,
  };

  factory UploadHistoryEntry.fromMap(Map<String, Object?> map) =>
      UploadHistoryEntry(
        id: map['id'] as String,
        fileName: map['file_name'] as String? ?? '',
        filePath: map['file_path'] as String? ?? '',
        fileSize: map['file_size'] as int? ?? 0,
        status: map['status'] as String? ?? 'completed',
        createdAt: intToTs(map['created_at'] as int?),
        completedAt: map['completed_at'] == null
            ? null
            : intToTs(map['completed_at'] as int?),
        sha256: map['sha256'] as String?,
        destinationId: map['destination_id'] as String?,
        destinationName: map['destination_name'] as String?,
        mode: map['mode'] as String?,
        target: map['target'] as String?,
        errorMessage: map['error_message'] as String?,
        httpCode: map['http_code'] as int?,
        discordCode: map['discord_code'] as int?,
        retryCount: map['retry_count'] as int? ?? 0,
        messageId: map['message_id'] as String?,
        messageUrl: map['message_url'] as String?,
        sessionId: map['session_id'] as String?,
        migratedFrom: map['migrated_from'] as String? ?? '',
      );
}

/// A stored SHA-256 hash record.
class FileHashRecord {
  const FileHashRecord({
    required this.sha256,
    required this.path,
    required this.size,
    required this.firstSeenAt,
    this.mediaId,
    this.lastSeenAt,
  });

  final String sha256;
  final String path;
  final int size;
  final DateTime firstSeenAt;
  final String? mediaId;
  final DateTime? lastSeenAt;

  Map<String, Object?> toMap() => <String, Object?>{
    'sha256': sha256,
    'path': path,
    'size': size,
    'first_seen_at': tsToInt(firstSeenAt),
    'media_id': mediaId,
    'last_seen_at': lastSeenAt == null ? null : tsToInt(lastSeenAt!),
  };

  factory FileHashRecord.fromMap(Map<String, Object?> map) => FileHashRecord(
    sha256: map['sha256'] as String? ?? '',
    path: map['path'] as String? ?? '',
    size: map['size'] as int? ?? 0,
    firstSeenAt: intToTs(map['first_seen_at'] as int?),
    mediaId: map['media_id'] as String?,
    lastSeenAt: map['last_seen_at'] == null
        ? null
        : intToTs(map['last_seen_at'] as int?),
  );
}

/// A recorded update check / installation attempt.
class UpdateHistoryEntry {
  const UpdateHistoryEntry({
    required this.id,
    required this.version,
    required this.checkedAt,
    this.installedAt,
    this.status = 'available',
    this.releaseUrl,
    this.notes,
    this.sha256,
    this.error,
  });

  final String id;
  final String version;
  final DateTime checkedAt;
  final DateTime? installedAt;
  final String status;
  final String? releaseUrl;
  final String? notes;
  final String? sha256;
  final String? error;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'version': version,
    'checked_at': tsToInt(checkedAt),
    'installed_at': installedAt == null ? null : tsToInt(installedAt!),
    'status': status,
    'release_url': releaseUrl,
    'notes': notes,
    'sha256': sha256,
    'error': error,
  };

  factory UpdateHistoryEntry.fromMap(Map<String, Object?> map) =>
      UpdateHistoryEntry(
        id: map['id'] as String,
        version: map['version'] as String? ?? '',
        checkedAt: intToTs(map['checked_at'] as int?),
        installedAt: map['installed_at'] == null
            ? null
            : intToTs(map['installed_at'] as int?),
        status: map['status'] as String? ?? 'available',
        releaseUrl: map['release_url'] as String?,
        notes: map['notes'] as String?,
        sha256: map['sha256'] as String?,
        error: map['error'] as String?,
      );
}

/// Widget configuration persisted outside the Flutter widget tree.
class WidgetSettings {
  const WidgetSettings({
    required this.homeWidgetEnabled,
    required this.floatingWidgetEnabled,
    required this.floatingX,
    required this.floatingY,
    required this.showSpeed,
    required this.compactMode,
    required this.updatedAt,
  });

  final bool homeWidgetEnabled;
  final bool floatingWidgetEnabled;
  final double floatingX;
  final double floatingY;
  final bool showSpeed;
  final bool compactMode;
  final DateTime updatedAt;

  WidgetSettings copyWith({
    bool? homeWidgetEnabled,
    bool? floatingWidgetEnabled,
    double? floatingX,
    double? floatingY,
    bool? showSpeed,
    bool? compactMode,
    DateTime? updatedAt,
  }) {
    return WidgetSettings(
      homeWidgetEnabled: homeWidgetEnabled ?? this.homeWidgetEnabled,
      floatingWidgetEnabled:
          floatingWidgetEnabled ?? this.floatingWidgetEnabled,
      floatingX: floatingX ?? this.floatingX,
      floatingY: floatingY ?? this.floatingY,
      showSpeed: showSpeed ?? this.showSpeed,
      compactMode: compactMode ?? this.compactMode,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': 'default',
    'home_widget_enabled': homeWidgetEnabled ? 1 : 0,
    'floating_widget_enabled': floatingWidgetEnabled ? 1 : 0,
    'floating_x': floatingX,
    'floating_y': floatingY,
    'show_speed': showSpeed ? 1 : 0,
    'compact_mode': compactMode ? 1 : 0,
    'updated_at': tsToInt(updatedAt),
  };

  factory WidgetSettings.fromMap(Map<String, Object?> map) => WidgetSettings(
    homeWidgetEnabled: (map['home_widget_enabled'] as int? ?? 0) == 1,
    floatingWidgetEnabled: (map['floating_widget_enabled'] as int? ?? 0) == 1,
    floatingX: (map['floating_x'] as num?)?.toDouble() ?? 0,
    floatingY: (map['floating_y'] as num?)?.toDouble() ?? 0,
    showSpeed: (map['show_speed'] as int? ?? 1) == 1,
    compactMode: (map['compact_mode'] as int? ?? 0) == 1,
    updatedAt: intToTs(map['updated_at'] as int?),
  );
}

/// Dashboard preferences (filters, selected destination, chart range).
class DashboardPreferences {
  const DashboardPreferences({
    required this.rangeKey,
    required this.destinationFilter,
    required this.updatedAt,
  });

  final String rangeKey;
  final String? destinationFilter;
  final DateTime updatedAt;

  DashboardPreferences copyWith({
    String? rangeKey,
    String? destinationFilter,
    bool clearDestination = false,
    DateTime? updatedAt,
  }) {
    return DashboardPreferences(
      rangeKey: rangeKey ?? this.rangeKey,
      destinationFilter: clearDestination
          ? null
          : (destinationFilter ?? this.destinationFilter),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': 'default',
    'range_key': rangeKey,
    'destination_filter': destinationFilter,
    'updated_at': tsToInt(updatedAt),
  };

  factory DashboardPreferences.fromMap(Map<String, Object?> map) =>
      DashboardPreferences(
        rangeKey: map['range_key'] as String? ?? '7d',
        destinationFilter: map['destination_filter'] as String?,
        updatedAt: intToTs(map['updated_at'] as int?),
      );
}
