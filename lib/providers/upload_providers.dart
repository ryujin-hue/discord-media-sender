import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../services/upload_engine.dart';
import 'config_providers.dart';

/// The live snapshot of the centralised upload engine.
///
/// Every surface (dashboard, widgets, distribution screen) listens to this
/// single stream, so an upload status change is reflected everywhere without
/// a manual refresh.
final StreamProvider<EngineSnapshot> engineSnapshotProvider =
    StreamProvider<EngineSnapshot>((Ref ref) {
      final UploadEngine engine = UploadEngine.instance;
      final StreamController<EngineSnapshot> controller =
          StreamController<EngineSnapshot>();
      StreamSubscription<EngineSnapshot>? subscription;

      controller.onListen = () {
        controller.add(engine.snapshot);
        subscription = engine.snapshots.listen(controller.add);
      };
      controller.onCancel = () {
        subscription?.cancel();
      };

      ref.onDispose(() {
        controller.close();
      });

      return controller.stream;
    });

/// The distribution mode currently selected in the upload screen.
final NotifierProvider<DistributionModeNotifier, DistributionMode>
distributionModeProvider =
    NotifierProvider<DistributionModeNotifier, DistributionMode>(
      DistributionModeNotifier.new,
    );

/// Holds the selected distribution mode.
class DistributionModeNotifier extends Notifier<DistributionMode> {
  @override
  DistributionMode build() => DistributionMode.broadcast;

  void set(DistributionMode mode) => state = mode;
}

/// The duplicate policy currently selected in the upload screen.
final NotifierProvider<DuplicatePolicyNotifier, DuplicatePolicy>
duplicatePolicyProvider =
    NotifierProvider<DuplicatePolicyNotifier, DuplicatePolicy>(
      DuplicatePolicyNotifier.new,
    );

/// Holds the selected duplicate handling policy.
class DuplicatePolicyNotifier extends Notifier<DuplicatePolicy> {
  @override
  DuplicatePolicy build() => DuplicatePolicy.skip;

  void set(DuplicatePolicy policy) => state = policy;
}

/// The destinations that are currently enabled for uploading.
final NotifierProvider<SelectedDestinationsNotifier, Set<String>>
selectedDestinationsProvider =
    NotifierProvider<SelectedDestinationsNotifier, Set<String>>(
      SelectedDestinationsNotifier.new,
    );

/// Holds the set of destination ids selected by the user.
class SelectedDestinationsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void toggle(String id) {
    final Set<String> next = Set<String>.of(state);
    if (!next.remove(id)) next.add(id);
    state = next;
  }

  void selectAll(Iterable<String> ids) => state = ids.toSet();

  void clear() => state = <String>{};
}

/// The caption attached to the next upload.
final NotifierProvider<CaptionNotifier, String> captionProvider =
    NotifierProvider<CaptionNotifier, String>(CaptionNotifier.new);

/// Holds the message caption.
class CaptionNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

/// The state of the safe resume prompt.
///
/// After a cold start the engine may find work that a killed process left
/// behind. The [SafeResumePolicy] decides what happens then: nothing, a
/// prompt, or an automatic restart of the queue.
class SafeResumeState {
  const SafeResumeState({this.pendingCount = 0, this.promptVisible = false});

  /// The number of jobs that were pending when the app started.
  final int pendingCount;

  /// Whether the "continue the upload?" prompt is shown.
  final bool promptVisible;

  bool get hasPendingWork => pendingCount > 0;

  SafeResumeState copyWith({int? pendingCount, bool? promptVisible}) {
    return SafeResumeState(
      pendingCount: pendingCount ?? this.pendingCount,
      promptVisible: promptVisible ?? this.promptVisible,
    );
  }
}

/// Holds the safe resume state and the actions that act on it.
class SafeResumeNotifier extends Notifier<SafeResumeState> {
  @override
  SafeResumeState build() => const SafeResumeState();

  /// Registers the pending work that a cold start found.
  ///
  /// When the policy is [SafeResumePolicy.auto] the queue is restarted right
  /// away, otherwise the prompt is shown for [SafeResumePolicy.ask].
  Future<void> registerColdStart(int pendingCount) async {
    if (pendingCount <= 0) {
      state = const SafeResumeState();
      return;
    }
    state = state.copyWith(pendingCount: pendingCount);
    final SafeResumePolicy policy = _policy();
    if (policy == SafeResumePolicy.auto) {
      await UploadEngine.instance.resume();
      state = state.copyWith(promptVisible: false);
    } else if (policy == SafeResumePolicy.ask) {
      state = state.copyWith(promptVisible: true);
    }
  }

  /// Continues the pending work.
  Future<void> resumeNow() async {
    state = state.copyWith(promptVisible: false);
    await UploadEngine.instance.resume();
  }

  /// Leaves the pending work in the queue for later.
  void dismiss() {
    state = state.copyWith(promptVisible: false);
  }

  SafeResumePolicy _policy() => ref.read(settingsProvider).safeResume;
}

/// The safe resume state.
final NotifierProvider<SafeResumeNotifier, SafeResumeState> safeResumeProvider =
    NotifierProvider<SafeResumeNotifier, SafeResumeState>(
      SafeResumeNotifier.new,
    );
