import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../services/upload_engine.dart';

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
