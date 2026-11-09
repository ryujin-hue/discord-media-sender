import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'upload_engine.dart';

/// Entry point of the background upload service.
///
/// The service runs the *same* [UploadEngine] as the UI — it does not
/// implement a second upload path. It only keeps the Dart isolate alive and
/// refreshes the foreground notification.
class UploadTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final UploadEngine engine = UploadEngine.instance;
    await engine.restore();
    await engine.run();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // The notification is refreshed from the engine snapshot so that the text
    // always reflects real measurements.
    unawaited(refreshNotification());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // The engine persists its state, so a destroyed service does not lose
    // queued work.
  }
}

/// Refreshes the foreground notification with the current engine state.
Future<void> refreshNotification() async {
  try {
    final EngineSnapshot snapshot = UploadEngine.instance.snapshot;
    final String title = snapshot.isPaused
        ? 'Upload paused'
        : snapshot.isRunning
        ? 'Uploading media'
        : 'Upload service';
    final String content = snapshot.isRunning
        ? '${snapshot.completedCount}/${snapshot.jobs.length} files'
              '${snapshot.currentFileName == null ? '' : ' · ${snapshot.currentFileName}'}'
        : 'Waiting for work';
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: content,
    );
  } catch (_) {
    // Never let a notification refresh break the upload.
  }
}

/// Starts and stops the foreground upload service.
class ForegroundManager {
  ForegroundManager._();

  static final ForegroundManager instance = ForegroundManager._();

  bool _running = false;

  bool get isRunning => _running;

  /// Starts the foreground service that keeps uploads alive in the background.
  Future<bool> start() async {
    if (_running) return true;
    try {
      final ServiceRequestResult result =
          await FlutterForegroundTask.startService(
            notificationTitle: 'Discord Media Sender',
            notificationText: 'Uploading media in the background',
            callback: startCallback,
          );
      _running = result is ServiceRequestSuccess;
      return _running;
    } catch (_) {
      return false;
    }
  }

  /// Stops the foreground service.
  Future<bool> stop() async {
    try {
      await FlutterForegroundTask.stopService();
      _running = false;
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// The callback used by `flutter_foreground_task` to start the isolate.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(UploadTaskHandler());
}
