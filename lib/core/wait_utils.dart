import 'dart:async';

/// Small helpers around waiting, used by the upload engine and the update
/// service.
class WaitUtils {
  WaitUtils._();

  /// Waits for [duration].
  static Future<void> sleep(Duration duration) =>
      Future<void>.delayed(duration);

  /// Waits until [condition] returns true, polling every [interval].
  ///
  /// Returns false when [timeout] elapses first. The 1.0 engine used the same
  /// pattern to wait for Discord rate-limit buckets to drain.
  static Future<bool> until(
    bool Function() condition, {
    Duration timeout = const Duration(minutes: 5),
    Duration interval = const Duration(milliseconds: 500),
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (condition()) return true;
      await sleep(interval);
    }
    return condition();
  }

  /// A completer that can be completed from outside the asynchronous flow.
  static DeferredCompleter<T> deferred<T>() => DeferredCompleter<T>();
}

/// A simple one-shot completer wrapper.
class DeferredCompleter<T> {
  final Completer<T> _completer = Completer<T>();

  bool get isCompleted => _completer.isCompleted;

  Future<T> get future => _completer.future;

  void complete(T value) {
    if (!_completer.isCompleted) _completer.complete(value);
  }

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (!_completer.isCompleted) _completer.completeError(error, stackTrace);
  }
}
