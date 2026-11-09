# Development guide

## Requirements

| Tool | Version |
|---|---|
| Flutter | 3.47.9 stable |
| Dart | 3.13.7 (bundled with Flutter) |
| JDK | 17 |
| Android SDK | platform 36, build-tools 35.0.0 |
| Android Studio | Ladybug or newer (optional) |

```bash
flutter --version
flutter doctor
```

## Getting started

```bash
git clone https://github.com/tukiza7-debug/discord-media-sender.git
cd discord-media-sender
flutter pub get

# Android SDK location
echo "sdk.dir=$ANDROID_HOME" >> android/local.properties

flutter run
```

## Project layout

```
lib/
  main.dart                 entry point: opens the DB, migrates credentials, runs the app
  app.dart                  MaterialApp, theme wiring, onboarding gate
  root_shell.dart           the five primary destinations
  core/
    constants.dart          API base, storage keys, palette, enums
    app_theme.dart          the Material 3 dark and light themes
    formatters.dart         bytes, durations, percentages, masking
    validators.dart         token, webhook URL, channel id, size, repo
    error_translator.dart   Discord / network / filesystem errors → readable text
    secure_store.dart       Keystore-backed credential storage
    security.dart           SHA-256 helpers and the secret redactor
    wait_utils.dart         small async helpers
  data/
    models.dart             every persisted model with its mapping
    database.dart           schema v2, the 1.0 migration and all queries
  providers/                Riverpod providers (state)
  services/                 the functional core (see ARCHITECTURE.md)
  screens/                  one file per destination
  widgets/                  shared components and chart painters

android/app/src/main/
  AndroidManifest.xml       permissions, services, widget receiver, FileProvider
  kotlin/…/MainActivity.kt          platform channels
  kotlin/…/UploadStateStore.kt      shared widget state
  kotlin/…/UploadWidgetProvider.kt  home-screen widget
  kotlin/…/FloatingOverlayService.kt the floating panel
  res/layout/, res/xml/, res/drawable/ widget and overlay resources

test/                       the automated test suite
docs/                       the documentation set
.github/workflows/          release.yml and version.yml
```

## Architecture rules

These are the invariants that keep the app consistent. Please respect them in new code.

1. **One upload engine.** Only `UploadEngine` may talk to `DiscordApiClient`. A widget, a
   screen or a background service must never implement its own upload path.
2. **One state stream.** Every screen derives its view from a provider. Do not add
   `setState` polling of the database where a provider would do.
3. **No secret in SQLite.** Bot tokens and webhook URLs live in `SecureStore` and nowhere
   else. The `credential_profiles` table only stores flags and validation results.
4. **No secret in a log.** Pass every error message through
   `Security.redactSecrets` before storing or displaying it.
5. **No fabricated numbers.** Analytics come from database rows. A chart with no data
   shows an empty state, never a sample value.
6. **No destructive action without confirmation.** Deleting media, clearing history and
   removing credentials all go through `showConfirmDialog`.

## Coding conventions

- `const` constructors everywhere a widget allows it.
- Doc comments on public classes and non-obvious methods; comments explain *why*.
- No `print` — use the activity timeline or `showAppSnack`.
- Immutable models with `copyWith`; the models in `data/models.dart` map to and from
  SQLite explicitly rather than relying on reflection.
- Prefer small, focused services over large files.

## Platform channels

| Channel | Methods | Direction |
|---|---|---|
| `com.dmsender.discord_media_sender/bridge` | `publishState`, `getState`, `setOverlay`, `refreshOverlay`, `refreshWidget`, `hasOverlayPermission`, `openOverlaySettings`, `installApk` | Dart → native |
| `com.dmsender.discord_media_sender/media` | `resolvePath`, `readBytes` | Dart → native |

`resolvePath` turns a Storage Access Framework `content://` URI into a local file path.
When Android does not expose a path, the native side copies the content into the app
cache. The upload engine, the duplicate detector and the thumbnailer all work on local
files, so this resolution always happens first.

## Tests

```bash
flutter test                                   # everything
flutter test test/database_test.dart           # one file
flutter test --coverage                        # with coverage
```

The suite currently covers:

| File | Area |
|---|---|
| `test/security_test.dart` | SHA-256 hashing (including streamed files), secret redaction |
| `test/duplicate_service_test.dart` | Identical, renamed and different files; decisions; destination-scoped delivery; retry idempotency |
| `test/database_test.dart` | Schema, the 1.0 → 2.0 migration, library, archive, history |
| `test/formatters_test.dart` | Formatting and every validator |
| `test/update_service_test.dart` | Version comparison, version codes, release notes |

A database test can point the service at a temporary file:

```dart
AppDatabase.pathOverride = '${tempDir.path}/test.db';
// …
await AppDatabase.instance.close();
AppDatabase.pathOverride = null;
```

## Building

```bash
# Debug
flutter run

# Release APK
flutter build apk --release

# Split per ABI (smaller downloads, same signing identity)
flutter build apk --split-per-abi --release

# App Bundle for Play
flutter build appbundle --release
```

The release build needs the signing configuration — see [`SIGNING.md`](SIGNING.md).

## Adding a feature

1. Add or extend the model in `data/models.dart` and the schema in `data/database.dart`.
   Bump `AppConstants.databaseVersion` and add the statements to `_createV2Tables` so that
   existing installations receive the new table.
2. Put the behaviour in a service under `lib/services/`.
3. Expose it through a provider in `lib/providers/`.
4. Build the screen in `lib/screens/`.
5. Add a test in `test/`.
6. Run `dart format lib test && flutter analyze --fatal-infos && flutter test`.
