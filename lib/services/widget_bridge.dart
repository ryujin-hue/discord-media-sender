import 'dart:async';

import 'package:flutter/services.dart';

import 'upload_engine.dart';

/// The snapshot of the upload engine that is mirrored to the native widgets.
class WidgetState {
  const WidgetState({
    required this.status,
    required this.totalFiles,
    required this.completedFiles,
    required this.failedFiles,
    required this.pendingFiles,
    required this.progress,
    required this.bytesSent,
    required this.bytesTotal,
    required this.speed,
    required this.etaSeconds,
    this.currentFileName,
    this.activeDestinationName,
    this.isPaused = false,
    this.updatedAt = 0,
  });

  final String status;
  final int totalFiles;
  final int completedFiles;
  final int failedFiles;
  final int pendingFiles;
  final double progress;
  final int bytesSent;
  final int bytesTotal;
  final double speed;
  final int? etaSeconds;
  final String? currentFileName;
  final String? activeDestinationName;
  final bool isPaused;
  final int updatedAt;

  Map<String, Object?> toMap() => <String, Object?>{
    'status': status,
    'totalFiles': totalFiles,
    'completedFiles': completedFiles,
    'failedFiles': failedFiles,
    'pendingFiles': pendingFiles,
    'progress': progress,
    'bytesSent': bytesSent,
    'bytesTotal': bytesTotal,
    'speed': speed,
    'etaSeconds': etaSeconds,
    'currentFileName': currentFileName,
    'activeDestinationName': activeDestinationName,
    'isPaused': isPaused,
    'updatedAt': updatedAt,
  };

  factory WidgetState.fromEngine(EngineSnapshot snapshot) {
    final String status = snapshot.isPaused
        ? 'paused'
        : snapshot.isRunning
        ? 'uploading'
        : 'idle';
    return WidgetState(
      status: status,
      totalFiles: snapshot.jobs.length,
      completedFiles: snapshot.completedCount,
      failedFiles: snapshot.failedCount,
      pendingFiles: snapshot.pendingCount,
      progress: snapshot.progress,
      bytesSent: snapshot.sentBytes,
      bytesTotal: snapshot.totalBytes,
      speed: snapshot.speedBytesPerSecond ?? 0,
      etaSeconds: snapshot.etaSeconds,
      currentFileName: snapshot.currentFileName,
      activeDestinationName: snapshot.activeDestinationName,
      isPaused: snapshot.isPaused,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory WidgetState.fromMap(Map<dynamic, dynamic> map) => WidgetState(
    status: map['status'] as String? ?? 'idle',
    totalFiles: (map['totalFiles'] as num?)?.toInt() ?? 0,
    completedFiles: (map['completedFiles'] as num?)?.toInt() ?? 0,
    failedFiles: (map['failedFiles'] as num?)?.toInt() ?? 0,
    pendingFiles: (map['pendingFiles'] as num?)?.toInt() ?? 0,
    progress: (map['progress'] as num?)?.toDouble() ?? 0,
    bytesSent: (map['bytesSent'] as num?)?.toInt() ?? 0,
    bytesTotal: (map['bytesTotal'] as num?)?.toInt() ?? 0,
    speed: (map['speed'] as num?)?.toDouble() ?? 0,
    etaSeconds: (map['etaSeconds'] as num?)?.toInt(),
    currentFileName: map['currentFileName'] as String?,
    activeDestinationName: map['activeDestinationName'] as String?,
    isPaused: map['isPaused'] as bool? ?? false,
    updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
  );
}

/// Bridges the Dart upload engine and the native Android widgets.
///
/// Both the home screen widget and the floating overlay read the very same
/// state, which is published here from the single upload engine. There is no
/// second upload engine behind the widgets.
class WidgetBridge {
  WidgetBridge._();

  static final WidgetBridge instance = WidgetBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.dmsender.discord_media_sender/bridge',
  );

  final StreamController<WidgetState> _states =
      StreamController<WidgetState>.broadcast();

  StreamSubscription<EngineSnapshot>? _engineSubscription;
  bool _initialised = false;

  /// Emits the latest published widget state.
  Stream<WidgetState> get states => _states.stream;

  /// Subscribes to the engine and starts mirroring its state to the platform.
  void attach(UploadEngine engine) {
    if (_initialised) return;
    _initialised = true;
    _engineSubscription = engine.snapshots.listen((EngineSnapshot snapshot) {
      unawaited(publish(WidgetState.fromEngine(snapshot)));
    });
  }

  /// Publishes the current state to the native widgets.
  Future<void> publish(WidgetState state) async {
    if (!_states.isClosed) _states.add(state);
    try {
      await _channel.invokeMethod<void>('publishState', state.toMap());
    } on PlatformException {
      // The platform side is optional (for example in unit tests).
    } on MissingPluginException {
      // No native side registered.
    }
  }

  /// Enables or disables the floating overlay widget.
  Future<bool> setOverlayEnabled(bool enabled) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'setOverlay',
        <String, dynamic>{'enabled': enabled},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Returns the state currently held by the native side.
  Future<WidgetState> readNativeState() async {
    try {
      final Map<dynamic, dynamic>? result = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getState');
      if (result == null) {
        return const WidgetState(
          status: 'idle',
          totalFiles: 0,
          completedFiles: 0,
          failedFiles: 0,
          pendingFiles: 0,
          progress: 0,
          bytesSent: 0,
          bytesTotal: 0,
          speed: 0,
          etaSeconds: null,
        );
      }
      return WidgetState.fromMap(result);
    } on PlatformException {
      return const WidgetState(
        status: 'idle',
        totalFiles: 0,
        completedFiles: 0,
        failedFiles: 0,
        pendingFiles: 0,
        progress: 0,
        bytesSent: 0,
        bytesTotal: 0,
        speed: 0,
        etaSeconds: null,
      );
    } on MissingPluginException {
      return const WidgetState(
        status: 'idle',
        totalFiles: 0,
        completedFiles: 0,
        failedFiles: 0,
        pendingFiles: 0,
        progress: 0,
        bytesSent: 0,
        bytesTotal: 0,
        speed: 0,
        etaSeconds: null,
      );
    }
  }

  /// Requests the floating overlay to be shown or hidden.
  Future<void> requestOverlayRefresh() async {
    try {
      await _channel.invokeMethod<void>('refreshOverlay');
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }

  /// Launches the Android package installer for a downloaded APK.
  ///
  /// The native side validates the package identity and version code before
  /// handing the file to the system installer.
  Future<bool> installApk(String path) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'installApk',
        <String, dynamic>{'path': path},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Checks whether the floating overlay permission has been granted.
  Future<bool> hasOverlayPermission() async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'hasOverlayPermission',
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system settings page for the overlay permission.
  Future<void> openOverlaySettings() async {
    try {
      await _channel.invokeMethod<void>('openOverlaySettings');
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }

  /// Requests the home screen widget to be refreshed.
  Future<void> refreshHomeWidget() async {
    try {
      await _channel.invokeMethod<void>('refreshWidget');
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }

  void dispose() {
    _engineSubscription?.cancel();
    _states.close();
  }
}
