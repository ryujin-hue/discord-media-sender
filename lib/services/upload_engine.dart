import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/error_translator.dart';
import '../core/security.dart';
import '../core/secure_store.dart';
import '../data/database.dart';
import '../data/models.dart';
import 'discord_api.dart';
import 'media_service.dart';

/// A snapshot of the whole engine state, published on every change.
class EngineSnapshot {
  const EngineSnapshot({
    required this.jobs,
    required this.isRunning,
    required this.isPaused,
    required this.totalBytes,
    required this.sentBytes,
    required this.completedCount,
    required this.failedCount,
    required this.pendingCount,
    this.activeDestinationId,
    this.activeDestinationName,
    this.currentFileName,
    this.currentJobId,
    this.speedBytesPerSecond,
    this.etaSeconds,
    this.events = const <LiveActivityEvent>[],
  });

  final List<DistributionJob> jobs;
  final bool isRunning;
  final bool isPaused;
  final int totalBytes;
  final int sentBytes;
  final int completedCount;
  final int failedCount;
  final int pendingCount;
  final String? activeDestinationId;
  final String? activeDestinationName;
  final String? currentFileName;
  final String? currentJobId;
  final double? speedBytesPerSecond;
  final int? etaSeconds;
  final List<LiveActivityEvent> events;

  double get progress {
    if (totalBytes <= 0) return 0;
    return (sentBytes / totalBytes).clamp(0.0, 1.0);
  }

  EngineSnapshot copyWith({
    List<DistributionJob>? jobs,
    bool? isRunning,
    bool? isPaused,
    int? totalBytes,
    int? sentBytes,
    int? completedCount,
    int? failedCount,
    int? pendingCount,
    String? activeDestinationId,
    String? activeDestinationName,
    String? currentFileName,
    String? currentJobId,
    double? speedBytesPerSecond,
    int? etaSeconds,
    List<LiveActivityEvent>? events,
  }) {
    return EngineSnapshot(
      jobs: jobs ?? this.jobs,
      isRunning: isRunning ?? this.isRunning,
      isPaused: isPaused ?? this.isPaused,
      totalBytes: totalBytes ?? this.totalBytes,
      sentBytes: sentBytes ?? this.sentBytes,
      completedCount: completedCount ?? this.completedCount,
      failedCount: failedCount ?? this.failedCount,
      pendingCount: pendingCount ?? this.pendingCount,
      activeDestinationId: activeDestinationId ?? this.activeDestinationId,
      activeDestinationName:
          activeDestinationName ?? this.activeDestinationName,
      currentFileName: currentFileName ?? this.currentFileName,
      currentJobId: currentJobId ?? this.currentJobId,
      speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      events: events ?? this.events,
    );
  }
}

/// Options applied to a batch of enqueued files.
class EnqueueOptions {
  const EnqueueOptions({
    required this.destinations,
    this.distributionMode = DistributionMode.broadcast,
    this.caption,
    this.duplicatePolicy = DuplicatePolicy.skip,
    this.priority = 0,
    this.maxFileMb = 0,
    this.autoStart = true,
    this.askOnDuplicate = false,
  });

  final List<Destination> destinations;
  final DistributionMode distributionMode;
  final String? caption;
  final DuplicatePolicy duplicatePolicy;
  final int priority;
  final int maxFileMb;
  final bool autoStart;
  final bool askOnDuplicate;
}

/// The single, centralised upload engine.
///
/// Every feature that uploads media (manual send, smart auto upload,
/// multi-Discord distribution, retry from history) goes through this class.
/// There is exactly one engine per isolate, and its state is persisted in
/// SQLite so that it can be recovered after a process restart.
class UploadEngine {
  UploadEngine._({DiscordApiClient? apiClient})
    : _api = apiClient ?? DiscordApiClient();

  static UploadEngine? _instance;

  /// The engine of the current isolate.
  static UploadEngine get instance => _instance ??= UploadEngine._();

  /// Creates an engine with an injected API client.
  ///
  /// The test suite uses this to drive the queue without a network.
  @visibleForTesting
  static UploadEngine createForTesting({DiscordApiClient? apiClient}) =>
      UploadEngine._(apiClient: apiClient);

  final AppDatabase _db = AppDatabase.instance;
  final DiscordApiClient _api;
  final StreamController<EngineSnapshot> _snapshots =
      StreamController<EngineSnapshot>.broadcast();

  final List<DistributionJob> _jobs = <DistributionJob>[];
  final List<LiveActivityEvent> _events = <LiveActivityEvent>[];

  bool _running = false;
  Future<void>? _runFuture;
  bool _paused = false;
  bool _cancelRequested = false;
  String? _activeDestinationId;
  String? _activeDestinationName;
  String? _currentJobId;
  String? _currentFileName;
  int _sentBytes = 0;
  int _totalBytes = 0;
  double _speedBytesPerSecond = 0;
  int? _etaSeconds;
  DateTime? _lastSpeedSample;

  /// Control flags mirrored into SQLite so that a second isolate (the
  /// foreground service) can observe pause / cancel requests issued from the
  /// UI isolate or from a widget.
  static const String controlPauseKey = 'engine_pause';
  static const String controlCancelKey = 'engine_cancel';

  /// Key used by the native widgets to hand a control command to the engine.
  ///
  /// The value is `<timestamp>:<command>`. The timestamp makes the command
  /// idempotent when both Dart isolates observe it.
  static const String nativeControlKey = 'dms_control_command';

  int _lastNativeCommandTimestamp = 0;

  Stream<EngineSnapshot> get snapshots => _snapshots.stream;

  EngineSnapshot get snapshot {
    final int pending = _jobs
        .where((DistributionJob j) => j.status == UploadStatus.pendingKey)
        .length;
    return EngineSnapshot(
      jobs: List<DistributionJob>.unmodifiable(_jobs),
      isRunning: _running,
      isPaused: _paused,
      totalBytes: _totalBytes,
      sentBytes: _sentBytes,
      completedCount: _jobs
          .where((DistributionJob j) => j.status == UploadStatus.completed.key)
          .length,
      failedCount: _jobs
          .where((DistributionJob j) => j.status == UploadStatus.failed.key)
          .length,
      pendingCount: pending,
      activeDestinationId: _activeDestinationId,
      activeDestinationName: _activeDestinationName,
      currentFileName: _currentFileName,
      currentJobId: _currentJobId,
      speedBytesPerSecond: _speedBytesPerSecond,
      etaSeconds: _etaSeconds,
      events: List<LiveActivityEvent>.unmodifiable(_events),
    );
  }

  void _publish() {
    if (_snapshots.isClosed) return;
    _snapshots.add(snapshot);
  }

  /// Restores the pending queue from the database.
  ///
  /// Called on engine start so that work interrupted by a process death is
  /// picked up again instead of being lost.
  Future<void> restore() async {
    final List<DistributionJob> persisted = await _db.listJobs(
      status: UploadStatus.pending.key,
    );
    _jobs
      ..clear()
      ..addAll(persisted);
    for (final DistributionJob job in persisted) {
      _totalBytes += job.fileSize;
    }
    _events.addAll(await _db.listLiveEvents(limit: 50));
    _publish();
  }

  /// Adds files to the queue for the given destinations.
  ///
  /// Duplicate detection runs here: a file whose SHA-256 was already delivered
  /// to the target destination is skipped (or flagged for review) according to
  /// [EnqueueOptions.duplicatePolicy].
  Future<List<String>> enqueue(
    List<MediaCandidate> files, {
    required EnqueueOptions options,
  }) async {
    final List<String> skipped = <String>[];
    if (files.isEmpty) return skipped;
    if (options.destinations.isEmpty) return skipped;

    final List<Destination> targets = _targetsFor(options);
    if (targets.isEmpty) return skipped;

    for (final MediaCandidate file in files) {
      if (!File(file.path).existsSync()) {
        skipped.add(file.name);
        continue;
      }
      if (options.maxFileMb > 0 &&
          file.size > options.maxFileMb * 1024 * 1024) {
        skipped.add(file.name);
        continue;
      }

      final String sha = await Security.sha256File(file.path);

      for (final Destination destination in targets) {
        final bool alreadyDelivered = await _db.hasDelivery(
          sha,
          destination.id,
        );
        if (alreadyDelivered) {
          switch (options.duplicatePolicy) {
            case DuplicatePolicy.skip:
              skipped.add(file.name);
              continue;
            case DuplicatePolicy.ask:
              await _recordDuplicate(
                file: file,
                sha: sha,
                destination: destination,
                decision: 'pending_review',
              );
              skipped.add(file.name);
              continue;
            case DuplicatePolicy.anyway:
            case DuplicatePolicy.keepBoth:
            case DuplicatePolicy.replace:
              break;
          }
        }

        final String jobId =
            'job-${DateTime.now().microsecondsSinceEpoch}-${sha.substring(0, 8)}';
        final DistributionJob job = DistributionJob(
          id: jobId,
          filePath: file.path,
          fileName: file.name,
          fileSize: file.size,
          status: UploadStatus.pending.key,
          createdAt: DateTime.now(),
          destinationId: destination.id,
          destinationName: destination.name,
          sha256: sha,
          priority: options.priority,
          totalBytes: file.size,
          caption: options.caption,
        );
        _jobs.add(job);
        await _db.upsertJob(job);
        _totalBytes += file.size;
      }
    }

    await _persistEvent(
      'queue_updated',
      'Queued ${files.length} file(s) for ${targets.length} destination(s)',
      severity: 'info',
    );

    _publish();

    if (options.autoStart) {
      unawaited(run());
    }
    return skipped;
  }

  /// Chooses the destinations for a distribution mode.
  List<Destination> _targetsFor(EnqueueOptions options) {
    final List<Destination> enabled = options.destinations
        .where((Destination d) => d.enabled)
        .toList();
    switch (options.distributionMode) {
      case DistributionMode.broadcast:
        return enabled;
      case DistributionMode.manual:
        return enabled;
      case DistributionMode.roundRobin:
      case DistributionMode.sequential:
        // Round robin and sequential are resolved per file when the job list is
        // built; here every enabled destination is kept so the caller can
        // assign one destination per file.
        return enabled;
      case DistributionMode.ruleBased:
        return enabled;
    }
  }

  /// Runs the queue until it is empty, paused or cancelled.
  ///
  /// Calling this while a run is already in progress joins that run instead
  /// of starting a second one.
  Future<void> run() async {
    final Future<void>? existing = _runFuture;
    if (existing != null) return existing;
    final Completer<void> completer = Completer<void>();
    _runFuture = completer.future;
    try {
      await _runLoop();
      completer.complete();
    } catch (error, stack) {
      completer.completeError(error, stack);
      rethrow;
    } finally {
      _runFuture = null;
    }
  }

  Future<void> _runLoop() async {
    if (_running) return;
    _running = true;
    _cancelRequested = false;
    _publish();

    try {
      while (true) {
        await _refreshControlFlags();
        await _pollNativeControl();
        if (_cancelRequested) {
          await _cancelRemaining();
          break;
        }
        if (_paused) break;

        final DistributionJob? next = _nextJob();
        if (next == null) break;

        await _processJob(next);

        await _refreshControlFlags();
        if (_cancelRequested) {
          await _cancelRemaining();
          break;
        }
      }
    } finally {
      _running = false;
      _paused = false;
      _speedBytesPerSecond = 0;
      _etaSeconds = null;
      _currentJobId = null;
      _currentFileName = null;
      _activeDestinationId = null;
      _activeDestinationName = null;
      await _db.setSetting(controlPauseKey, '0');
      _publish();
      await _persistEvent(
        'engine_stopped',
        _failedCount() > 0
            ? 'Upload finished with failures'
            : 'Upload finished',
        severity: _failedCount() > 0 ? 'warning' : 'success',
      );
    }
  }

  DistributionJob? _nextJob() {
    final List<DistributionJob> pending =
        _jobs
            .where((DistributionJob j) => j.status == UploadStatus.pending.key)
            .toList()
          ..sort((DistributionJob a, DistributionJob b) {
            final int byPriority = b.priority.compareTo(a.priority);
            if (byPriority != 0) return byPriority;
            return a.createdAt.compareTo(b.createdAt);
          });
    if (pending.isEmpty) return null;
    return pending.first;
  }

  /// Processes one job, sending it to its destination.
  Future<void> _processJob(DistributionJob job) async {
    final File file = File(job.filePath);
    if (!file.existsSync()) {
      await _failJob(job, 'File not found: ${job.fileName}', httpCode: null);
      return;
    }

    final Destination? destination = await _destinationFor(job.destinationId);
    if (destination == null) {
      await _failJob(job, 'Destination no longer exists');
      return;
    }
    if (!destination.enabled) {
      await _skipJob(job, 'Destination is disabled');
      return;
    }

    _activeDestinationId = destination.id;
    _activeDestinationName = destination.name;
    _currentJobId = job.id;
    _currentFileName = job.fileName;
    _sentBytes = 0;
    _totalBytes = job.fileSize;
    _lastSpeedSample = DateTime.now();

    final DistributionJob started = job.copyWith(
      status: UploadStatus.uploading.key,
      startedAt: DateTime.now(),
    );
    _replaceJob(started);
    await _db.upsertJob(started);
    await _persistEvent(
      'upload_started',
      'Uploading ${job.fileName}',
      fileName: job.fileName,
      destinationId: destination.id,
      destinationName: destination.name,
    );
    _publish();

    final DiscordSendResult result;
    try {
      result = await _sendTo(destination, file, job);
    } catch (error) {
      await _failJob(job, ErrorTranslator.translate(error));
      return;
    }

    if (result.success) {
      await _completeJob(job, destination, result);
    } else {
      await _failJob(
        job,
        result.errorMessage ?? 'Upload failed',
        httpCode: result.httpCode,
        discordCode: result.discordCode,
      );
    }
  }

  Future<DiscordSendResult> _sendTo(
    Destination destination,
    File file,
    DistributionJob job,
  ) async {
    // Resolve the credential for this destination.
    final String? profileId = destination.credentialProfileId;
    String? botToken;
    String? webhookUrl;

    if (destination.isWebhook) {
      webhookUrl = destination.webhookId;
      if (webhookUrl == null || webhookUrl.isEmpty) {
        // Fall back to the legacy flat storage key for destinations created
        // before profiles existed.
        webhookUrl = await _legacyWebhook();
      }
    } else {
      botToken = profileId == null
          ? await _legacyBotToken()
          : await _readProfileToken(profileId);
    }

    if (destination.isWebhook) {
      if (webhookUrl == null || webhookUrl.isEmpty) {
        throw DiscordException(
          'No webhook URL is configured for ${destination.name}',
        );
      }
      return _api.sendWebhook(
        webhookUrl,
        files: <File>[file],
        content: job.caption,
        onProgress: (int sent, int total) => _onProgress(job, sent, total),
      );
    }

    if (botToken == null || botToken.isEmpty) {
      throw DiscordException(
        'No bot token is configured for ${destination.name}',
      );
    }
    if (destination.channelId == null || destination.channelId!.isEmpty) {
      throw DiscordException('No channel is selected for ${destination.name}');
    }
    return _api.sendBotMessage(
      botToken,
      destination.channelId!,
      files: <File>[file],
      content: job.caption,
      onProgress: (int sent, int total) => _onProgress(job, sent, total),
    );
  }

  void _onProgress(DistributionJob job, int sent, int total) {
    _sentBytes = sent;
    final DateTime now = DateTime.now();
    final DateTime? previous = _lastSpeedSample;
    if (previous != null) {
      final int elapsedMs = now.difference(previous).inMilliseconds;
      if (elapsedMs > 0) {
        _speedBytesPerSecond = sent / (elapsedMs / 1000);
        if (_speedBytesPerSecond > 0 && total > sent) {
          _etaSeconds = ((total - sent) / _speedBytesPerSecond).round();
        } else if (total <= sent) {
          _etaSeconds = 0;
        }
      }
    }
    _lastSpeedSample = now;

    unawaited(
      _db.upsertUploadProgress(
        jobId: job.id,
        bytesSent: sent,
        totalBytes: total,
        speed: _speedBytesPerSecond,
        etaSeconds: _etaSeconds,
      ),
    );
    _publish();
  }

  Future<void> _completeJob(
    DistributionJob job,
    Destination destination,
    DiscordSendResult result,
  ) async {
    final DistributionJob completed = job.copyWith(
      status: UploadStatus.completed.key,
      completedAt: DateTime.now(),
      bytesSent: job.fileSize,
      errorMessage: null,
      clearError: true,
      messageId: result.messageId,
    );
    _replaceJob(completed);
    await _db.upsertJob(completed);

    if (job.sha256 != null) {
      await _db.insertDelivery(
        DeliveryRecord(
          id: 'delivery-${DateTime.now().microsecondsSinceEpoch}',
          sha256: job.sha256!,
          destinationId: destination.id,
          deliveredAt: DateTime.now(),
          fileName: job.fileName,
          fileSize: job.fileSize,
          filePath: job.filePath,
          messageId: result.messageId,
          messageUrl: result.messageUrl,
          jobId: job.id,
          attachmentUrl: result.attachmentUrls.isEmpty
              ? null
              : result.attachmentUrls.first,
        ),
      );
    }

    await _db.insertHistory(
      UploadHistoryEntry(
        id: 'hist-${DateTime.now().microsecondsSinceEpoch}',
        fileName: job.fileName,
        filePath: job.filePath,
        fileSize: job.fileSize,
        status: UploadStatus.completed.key,
        createdAt: job.createdAt,
        completedAt: DateTime.now(),
        sha256: job.sha256,
        destinationId: destination.id,
        destinationName: destination.name,
        mode: destination.type,
        target: destination.name,
        messageId: result.messageId,
        messageUrl: result.messageUrl,
        sessionId: job.id,
      ),
    );

    await _db.insertAnalyticsEvent(
      eventType: 'upload_completed',
      destinationId: destination.id,
      fileSize: job.fileSize,
      success: true,
    );

    await _db.upsertDestination(
      destination.copyWith(
        totalSent: destination.totalSent + 1,
        lastActivityAt: DateTime.now(),
        clearLastError: true,
        clearRateLimit: true,
      ),
    );

    await _markMediaUploaded(job);

    await _persistEvent(
      'delivery_succeeded',
      'Delivered ${job.fileName} to ${destination.name}',
      fileName: job.fileName,
      destinationId: destination.id,
      destinationName: destination.name,
      severity: 'success',
    );
    _publish();
  }

  Future<void> _failJob(
    DistributionJob job,
    String message, {
    int? httpCode,
    int? discordCode,
  }) async {
    final String safeMessage = Security.redactSecrets(message);
    final DistributionJob failed = job.copyWith(
      status: UploadStatus.failed.key,
      completedAt: DateTime.now(),
      errorMessage: safeMessage,
      httpCode: httpCode,
      discordCode: discordCode,
      retryCount: job.retryCount + 1,
    );
    _replaceJob(failed);
    await _db.upsertJob(failed);

    await _db.insertHistory(
      UploadHistoryEntry(
        id: 'hist-${DateTime.now().microsecondsSinceEpoch}',
        fileName: job.fileName,
        filePath: job.filePath,
        fileSize: job.fileSize,
        status: UploadStatus.failed.key,
        createdAt: job.createdAt,
        completedAt: DateTime.now(),
        sha256: job.sha256,
        destinationId: job.destinationId,
        destinationName: job.destinationName,
        mode: job.destinationId,
        target: job.destinationName ?? '',
        errorMessage: safeMessage,
        httpCode: httpCode,
        discordCode: discordCode,
        retryCount: failed.retryCount,
        sessionId: job.id,
      ),
    );

    await _db.insertAnalyticsEvent(
      eventType: 'upload_failed',
      destinationId: job.destinationId,
      fileSize: job.fileSize,
      success: false,
    );

    final Destination? destination = await _destinationFor(job.destinationId);
    if (destination != null) {
      await _db.upsertDestination(
        destination.copyWith(
          totalFailed: destination.totalFailed + 1,
          lastActivityAt: DateTime.now(),
          lastError: safeMessage,
        ),
      );
    }

    await _persistEvent(
      'upload_failed',
      'Failed ${job.fileName}: $safeMessage',
      fileName: job.fileName,
      destinationId: job.destinationId,
      destinationName: job.destinationName,
      severity: 'error',
      detail: safeMessage,
    );
    _publish();
  }

  Future<void> _skipJob(DistributionJob job, String reason) async {
    final DistributionJob skipped = job.copyWith(
      status: UploadStatus.cancelled.key,
      completedAt: DateTime.now(),
      errorMessage: reason,
    );
    _replaceJob(skipped);
    await _db.upsertJob(skipped);
    await _persistEvent(
      'upload_skipped',
      'Skipped ${job.fileName}: $reason',
      fileName: job.fileName,
      destinationId: job.destinationId,
      destinationName: job.destinationName,
      severity: 'warning',
    );
    _publish();
  }

  Future<void> _markMediaUploaded(DistributionJob job) async {
    final MediaLibraryEntry? entry = await _db.mediaByPath(job.filePath);
    if (entry == null) return;
    await _db.upsertMedia(
      entry.copyWith(
        status: MediaStatus.uploaded.key,
        lastActivityAt: DateTime.now(),
      ),
    );
  }

  Future<void> _recordDuplicate({
    required MediaCandidate file,
    required String sha,
    required Destination destination,
    required String decision,
  }) async {
    final DuplicateRecord record = DuplicateRecord(
      id: 'dup-${DateTime.now().microsecondsSinceEpoch}',
      originalId: '',
      duplicateId: '',
      method: DetectionMethod.sha256.key,
      detectedAt: DateTime.now(),
      decision: decision,
      originalPath: file.path,
      duplicatePath: file.path,
      originalName: file.name,
      duplicateName: file.name,
    );
    await _db.upsertDuplicate(record);
  }

  // ---------------------------------------------------------------------------
  // Control
  // ---------------------------------------------------------------------------

  /// Requests a pause. The current batch finishes first.
  Future<void> pause() async {
    if (_paused) return;
    _paused = true;
    await _db.setSetting(controlPauseKey, '1');
    await _persistEvent('engine_paused', 'Pausing after current batch…');
    _publish();
  }

  /// Resumes a paused engine.
  Future<void> resume() async {
    if (!_paused) return;
    _paused = false;
    await _db.setSetting(controlPauseKey, '0');
    await _persistEvent('engine_resumed', 'Upload resumed');
    _publish();
    unawaited(run());
  }

  /// Cancels every pending job.
  Future<void> cancel() async {
    _cancelRequested = true;
    await _db.setSetting(
      controlCancelKey,
      DateTime.now().millisecondsSinceEpoch.toString(),
    );
    await _persistEvent('engine_cancelled', 'Upload cancelled by user');
    _publish();
  }

  /// Finds a job in memory and falls back to the database.
  ///
  /// A retry issued after the app was restarted must find the persisted job.
  Future<DistributionJob?> _findJob(String jobId) async {
    final int index = _jobs.indexWhere((DistributionJob j) => j.id == jobId);
    if (index >= 0) return _jobs[index];
    final List<DistributionJob> stored = await _db.listJobs();
    for (final DistributionJob job in stored) {
      if (job.id == jobId) {
        _jobs.add(job);
        return job;
      }
    }
    return null;
  }

  /// Cancels a single job.
  Future<void> cancelJob(String jobId) async {
    final DistributionJob? job = await _findJob(jobId);
    if (job == null) return;
    if (job.status == UploadStatus.completed.key ||
        job.status == UploadStatus.failed.key) {
      return;
    }
    final DistributionJob cancelled = job.copyWith(
      status: UploadStatus.cancelled.key,
      completedAt: DateTime.now(),
      errorMessage: 'Cancelled by user',
    );
    _replaceJob(cancelled);
    await _db.upsertJob(cancelled);
    await _persistEvent(
      'upload_cancelled',
      'Cancelled ${job.fileName}',
      fileName: job.fileName,
      destinationId: job.destinationId,
      destinationName: job.destinationName,
      severity: 'warning',
    );
    _publish();
  }

  /// Retries a failed job.
  Future<void> retryJob(String jobId) async {
    final DistributionJob? job = await _findJob(jobId);
    if (job == null) return;
    if (job.status != UploadStatus.failed.key &&
        job.status != UploadStatus.cancelled.key) {
      return;
    }
    final DistributionJob retried = job.copyWith(
      status: UploadStatus.pending.key,
      clearError: true,
      completedAt: null,
    );
    _replaceJob(retried);
    await _db.upsertJob(retried);
    await _persistEvent(
      'retry_scheduled',
      'Retry scheduled for ${job.fileName}',
      fileName: job.fileName,
      destinationId: job.destinationId,
      destinationName: job.destinationName,
    );
    _publish();
    unawaited(run());
  }

  /// Retries every failed job of a destination.
  Future<void> retryFailedForDestination(String destinationId) async {
    final List<DistributionJob> failed = _jobs
        .where(
          (DistributionJob j) =>
              j.destinationId == destinationId &&
              j.status == UploadStatus.failed.key,
        )
        .toList();
    for (final DistributionJob job in failed) {
      await retryJob(job.id);
    }
  }

  /// Clears finished jobs from the in-memory list.
  void clearFinished() {
    _jobs.removeWhere(
      (DistributionJob j) =>
          j.status == UploadStatus.completed.key ||
          j.status == UploadStatus.cancelled.key,
    );
    _publish();
  }

  Future<void> _cancelRemaining() async {
    for (final DistributionJob job in _jobs) {
      if (job.status == UploadStatus.pending.key) {
        final DistributionJob cancelled = job.copyWith(
          status: UploadStatus.cancelled.key,
          completedAt: DateTime.now(),
          errorMessage: 'Cancelled by user',
        );
        _replaceJob(cancelled);
        await _db.upsertJob(cancelled);
      }
    }
    await _persistEvent(
      'upload_cancelled',
      'Remaining uploads cancelled',
      severity: 'warning',
    );
    _publish();
  }

  /// Applies a control command issued by an Android widget.
  ///
  /// The command is consumed exactly once; both isolates may read it but only
  /// the one that sees the newest timestamp acts on it.
  Future<void> _pollNativeControl() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(nativeControlKey);
      if (raw == null || raw.isEmpty) return;
      final List<String> parts = raw.split(':');
      final int timestamp = int.tryParse(parts.first) ?? 0;
      if (timestamp <= _lastNativeCommandTimestamp) return;
      _lastNativeCommandTimestamp = timestamp;
      await prefs.remove(nativeControlKey);

      final String command = parts.length > 1 ? parts[1] : '';
      switch (command) {
        case 'pause':
          await pause();
          break;
        case 'resume':
          await resume();
          break;
        case 'cancel':
          await cancel();
          break;
        case 'start':
          // The engine is already running, so a "start" command only means
          // "continue with the queued work".
          _paused = false;
          await _db.setSetting(controlPauseKey, '0');
          _publish();
          break;
        default:
          break;
      }
    } catch (_) {
      // A missing shared preferences file must not break the upload.
    }
  }

  /// Reads the control flags written by another isolate.
  Future<void> _refreshControlFlags() async {
    final String? pauseFlag = await _db.getSetting(controlPauseKey);
    if (pauseFlag == '1' && !_paused) {
      _paused = true;
      _publish();
    } else if (pauseFlag == '0' && _paused) {
      _paused = false;
      _publish();
    }
  }

  void _replaceJob(DistributionJob job) {
    final int index = _jobs.indexWhere((DistributionJob j) => j.id == job.id);
    if (index >= 0) {
      _jobs[index] = job;
    } else {
      _jobs.add(job);
    }
  }

  int _failedCount() => _jobs
      .where((DistributionJob j) => j.status == UploadStatus.failed.key)
      .length;

  Future<Destination?> _destinationFor(String id) async {
    final List<Destination> destinations = await _db.listDestinations();
    for (final Destination destination in destinations) {
      if (destination.id == id) return destination;
    }
    return null;
  }

  Future<String?> _readProfileToken(String profileId) async {
    // The secure store is intentionally not cached so a replaced token takes
    // effect immediately.
    final Map<String, Map<String, String>> profiles = await _readProfiles();
    return profiles[profileId]?['botToken'];
  }

  Future<String?> _legacyBotToken() async {
    final Map<String, Map<String, String>> profiles = await _readProfiles();
    return profiles['legacy_default']?['botToken'];
  }

  Future<String?> _legacyWebhook() async {
    final Map<String, Map<String, String>> profiles = await _readProfiles();
    return profiles['legacy_default']?['webhookUrl'];
  }

  Future<Map<String, Map<String, String>>> _readProfiles() async {
    return SecureStore.instance.readAllProfiles();
  }

  Future<void> _persistEvent(
    String type,
    String message, {
    String? fileName,
    String? destinationId,
    String? destinationName,
    String? detail,
    String severity = 'info',
  }) async {
    final LiveActivityEvent event = LiveActivityEvent(
      id: 'evt-${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      createdAt: DateTime.now(),
      message: Security.redactSecrets(message),
      fileName: fileName,
      destinationId: destinationId,
      destinationName: destinationName,
      detail: detail == null ? null : Security.redactSecrets(detail),
      severity: severity,
    );
    _events.insert(0, event);
    if (_events.length > 200) _events.removeLast();
    try {
      await _db.insertLiveEvent(event);
    } catch (_) {}
    _publish();
  }

  /// Exposes the API client so callers can validate credentials.
  DiscordApiClient get api => _api;

  /// Releases the snapshot stream.
  void dispose() {
    _snapshots.close();
  }
}

/// Builds the display name shown in the UI for a job.
String jobDisplayName(DistributionJob job) =>
    p.basename(job.filePath.isEmpty ? job.fileName : job.filePath);
