import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'upload_engine.dart';
import 'widget_bridge.dart';

/// Entry point of the background upload service.
///
/// The service runs the *same* [UploadEngine] as the UI — it does not
/// implement a second upload path. It only keeps the Dart isolate alive and
/// refreshes the foreground notification.
///
/// The service isolate and the UI isolate share the queue through the
/// database. A job is claimed atomically before it is sent, so a file is
/// never uploaded twice, no matter which of the two isolates picks it up.
class UploadTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final UploadEngine engine = UploadEngine.instance;
    await engine.restore();
    // The widget and the overlay are updated from this isolate as well, so
    // they keep showing the real progress while the app is in the background.
    WidgetBridge.instance.attach(engine);
    await engine.run();

    // Nothing left to do: the service stops itself so that it does not keep a
    // notification alive after the last file was sent.
    if (engine.snapshot.pendingCount == 0) {
      try {
        await FlutterForegroundTask.stopService();
      } catch (_) {
        // ignore
      }
    }
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
    // queued work: the next start recovers it.
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
        ? '${snapshot.completedCount}/${snapshot.pendingCount + snapshot.completedCount + snapshot.failedCount} files'
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

  /// The channel id of the upload notification.
  static const String channelId = 'dms_upload';

  bool _running = false;
  bool _initialized = false;

  /// The last error that prevented the service from starting.
  String? _lastError;

  bool get isRunning => _running;

  /// The last error that prevented the service from starting.
  String? get lastError => _lastError;

  /// Prepares the plugin.
  ///
  /// This has to happen before [start] is called. Without it the plugin
  /// refuses to start the service, and the upload would silently stop as soon
  /// as the app goes to the background.
  Future<bool> initialize() async {
    if (_initialized) return true;
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: channelId,
          channelName: 'Background upload',
          channelDescription:
              'Shows the progress of a running background upload.',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          enableVibration: false,
          playSound: false,
          showWhen: false,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          // The notification is refreshed every two seconds.
          eventAction: ForegroundTaskEventAction.repeat(2000),
          // The service comes back after a reboot or an app update.
          autoRunOnBoot: true,
          autoRunOnMyPackageReplaced: true,
          // A wake lock keeps the CPU running while the screen is off.
          allowWakeLock: true,
          allowWifiLock: false,
          // A crashed service is restarted.
          allowAutoRestart: true,
          // The service outlives the task that started it.
          stopWithTask: false,
        ),
      );
      _initialized = true;
      _lastError = null;
      return true;
    } catch (error) {
      _lastError = 'The background service could not be prepared: $error';
      return false;
    }
  }

  /// Starts the foreground service that keeps uploads alive in the background.
  Future<bool> start() async {
    if (_running) return true;
    if (!await initialize()) return false;
    try {
      final ServiceRequestResult result =
          await FlutterForegroundTask.startService(
            notificationTitle: 'Discord Media Sender',
            notificationText: 'Uploading media in the background',
            notificationIcon: const NotificationIcon(
              metaDataName:
                  'com.dmsender.discord_media_sender.notification_icon',
            ),
            callback: startCallback,
          );
      _running = result is ServiceRequestSuccess;
      if (!_running) {
        _lastError = 'The background service did not start: $result';
      } else {
        _lastError = null;
      }
      return _running;
    } on ServiceAlreadyStartedException {
      // The service is already running, which is exactly what we want.
      _running = true;
      _lastError = null;
      return true;
    } catch (error) {
      _lastError = 'The background service could not be started: $error';
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
