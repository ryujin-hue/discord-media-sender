import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/secure_store.dart';
import 'data/database.dart';
import 'services/foreground_manager.dart';
import 'services/upload_engine.dart';
import 'services/widget_bridge.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Open the database so that the 1.0 → 2.0 migration runs before the first
  // screen is drawn.
  await AppDatabase.instance.database;

  // Move the flat 1.0 credentials into a named profile so that a single
  // storage mechanism is used from here on.
  await SecureStore.instance.migrateLegacyCredentials();

  // Restore the queue and mirror the engine state to the Android widgets.
  final UploadEngine engine = UploadEngine.instance;
  final int pendingCount = await engine.restore();
  WidgetBridge.instance.attach(engine);

  // Work that a killed process left behind needs the foreground service, or
  // the system stops the app as soon as it goes to the background.
  if (pendingCount > 0) {
    await ForegroundManager.instance.start();
  }

  runApp(
    ProviderScope(
      child: DiscordMediaSenderApp(
        // The safe resume policy decides whether the pending work is started
        // right away or only after the user confirmed it.
        pendingOnColdStart: pendingCount,
      ),
    ),
  );
}
