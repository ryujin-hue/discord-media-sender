# Discord Media Sender 2.0

**Smart, multi-destination media delivery for Discord — built on the 1.0 upload engine.**

Discord Media Sender 2.0 is a production Android application that sends files, folders and
ZIP archives to Discord through webhooks and bot accounts. It adds Smart Auto Upload, a
Media Gallery, an Advanced Analytics Center, Multi-Discord Distribution, a persistent
Credential Manager, an Android home-screen widget, a floating overlay, an anti-duplication
system, archive management and a live progress dashboard — all driven by a single centralised
upload engine.

| | |
|---|---|
| Application id | `com.dmsender.discord_media_sender` |
| Version | 2.0.0 (versionCode 20000) |
| Minimum Android | 7.0 (API 24) |
| Target / compile SDK | 36 |
| Flutter | 3.47.9 stable · Dart 3.13.7 |
| Discord API | REST v10 |
| Official repository | `ryujin-hue/discord-media-sender` |

---

## Table of contents

- [What changed since 1.0](#what-changed-since-10)
- [Feature overview](#feature-overview)
- [Architecture](#architecture)
- [Installation](#installation)
- [Developer setup](#developer-setup)
- [Testing](#testing)
- [Release process](#release-process)
- [Security model](#security-model)
- [Documentation index](#documentation-index)

---

## What changed since 1.0

The 1.0.a9 build was a Flutter application with a working upload engine, a `sessions` /
`session_files` / `failures` database, secure credential storage and GitHub-based update
checking. **2.0 keeps all of that and rebuilds around it:**

- The **application id, label, minimum SDK and database name are unchanged**, so an APK
  built from this source installs over 1.0 without losing data.
- The 1.0 `sessions`, `session_files` and `failures` tables are **kept and migrated** into
  the new unified `upload_history` table on first launch of 2.0.
- The 1.0 secure-store keys (`cfg_bot_token`, `cfg_webhook_url`, …) are **migrated into a
  named credential profile** on first launch, so no credential has to be re-entered.
- The 1.0 upload behaviour (batching, `retry_after` handling, pause-after-batch, a 6 hour
  update check interval, the ZIP 5 GB limit) is preserved.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full comparison and
[`docs/DATABASE.md`](docs/DATABASE.md) for the schema and migration details.

---

## Feature overview

### Smart Auto Upload
Watch one or more folders, filter by file type and size, and send new files automatically.
Three modes — **manual**, **semi-automatic** (confirm before sending) and **fully
automatic**. Rules carry their own destination set, duplicate policy, retry limit, priority
and an optional daily time window.

### Media Gallery & Local Library
Every file that passes through the app is indexed with its size, MIME type, category,
modification date, **SHA-256 hash**, dimensions and thumbnail. Search, sort, filter by
category, star favourites and group files into collections.

> The gallery is a **local media library**. Discord-hosted attachments are referenced by
> message id and URL; Discord CDN links are not permanent and the app never claims
> otherwise. There is no cloud storage backend — the architecture leaves room for one.

### Advanced Analytics Center
All statistics are computed from real database rows. Upload activity over time, daily
volume, success/failure ratio, data transfer, destination performance, duplicate statistics
and archive activity — filterable by the last 24 hours, 7 days, 30 days or all time, and
exportable to **CSV, JSON and PDF**. Exports never contain credentials.

### Multi-Discord Distribution
Any number of webhook and bot destinations, each with an **independent** queue, delivery
history, retry counter, error history and rate-limit state. Distribution modes: broadcast,
manual selection, round robin, rule based and sequential. Rule syntax for per-destination
routing: `ext:jpg`, `cat:image`, `size:25`.

### Credential & Webhook Manager
Add, validate, edit, replace, remove and test bot and webhook profiles. Webhooks can be
created through an authorised bot (server → channel → webhook) with the **Manage Webhooks**
permission. Secrets live in Android Keystore-backed storage, are masked in the UI and never
reach SQLite, logs or analytics.

### Android Screen Widget
A home-screen widget showing the real upload status, queue count, successful and failed
counts, overall progress and the active destination, with Start / Pause / Resume / Open
dashboard actions.

### Floating Overlay
An optional draggable, collapsible panel that shows the current file, progress, speed and
ETA with pause/resume controls. It requires the *Display over other apps* permission and is
never activated without explicit consent.

### Anti-Duplication System
SHA-256 is the only method that proves identical content. Metadata matches are surfaced as
suggestions and perceptual hashes are never treated as proof. Handling modes: skip, ask
before upload, upload anyway, replace library entry, keep both. **Detection is
destination-aware** — a file sent to server A is still considered new for server B. Original
files are never deleted automatically.

### Archive Management
Archive selected files, everything that finished uploading, or whole categories. Restore is
always available. Archiving marks the entry and writes a record; the file on disk is only
moved when the user explicitly allows it, and permanent deletion always requires an
explicit confirmation.

### Live Progress Dashboard
Total files, uploaded, uploading, pending, failed, duplicates, archived and transferred
bytes — plus a live per-task monitor, per-destination monitoring, a timestamped activity
timeline and quick controls. All surfaces share one reactive state stream, so a status
change appears everywhere at once and opening a screen never restarts an upload.

---

## Architecture

```
lib/
  core/          constants, theme, formatters, validators, secure store, hashing
  data/          models and the SQLite layer (schema v2 + 1.0 migration)
  providers/     Riverpod state (settings, destinations, library, history, analytics)
  services/      the functional core
    upload_engine.dart      ← the single, centralised upload engine
    discord_api.dart        ← Discord REST v10 client with 429 handling
    distribution_service.dart, duplicate_service.dart, archive_service.dart,
    analytics_service.dart, auto_upload_service.dart, update_service.dart,
    foreground_manager.dart, widget_bridge.dart, media_service.dart
  screens/       one file per destination (home, upload, library, distribution, more …)
  widgets/       shared UI components and chart painters

android/app/src/main/kotlin/…/
  MainActivity.kt          platform channels (widget state, overlay, APK install, SAF)
  UploadStateStore.kt      shared state between Dart and the widgets
  UploadWidgetProvider.kt  the home-screen widget
  FloatingOverlayService.kt the floating panel
```

**One engine, one state.** `UploadEngine` is the only component that uploads. The
dashboard, the distribution screen, the home-screen widget and the floating overlay all
read the same snapshot stream — there is no second upload path behind the widgets.

Full details: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Installation

Download `DiscordMediaSender.apk` and `SHA256SUMS.txt` from the
[GitHub Releases page](https://github.com/ryujin-hue/discord-media-sender/releases),
verify the checksum and install the APK:

```bash
sha256sum -c SHA256SUMS.txt
adb install -r DiscordMediaSender.apk
```

Installing over an existing 1.0 installation keeps all user data. See
[`docs/INSTALLATION.md`](docs/INSTALLATION.md) for the full guide, including the
`REQUEST_INSTALL_PACKAGES` permission and the "unknown sources" step.

---

## Developer setup

```bash
git clone https://github.com/ryujin-hue/discord-media-sender.git
cd discord-media-sender
flutter pub get
flutter run
```

Requirements: Flutter 3.47.9 stable, Android SDK 36, JDK 17.

Signing, keystore handling and the GitHub secrets are described in
[`docs/SIGNING.md`](docs/SIGNING.md) and [`docs/GITHUB_RELEASES.md`](docs/GITHUB_RELEASES.md).

---

## Testing

```bash
flutter test          # unit and integration tests
flutter analyze       # static analysis (the CI runs this with --fatal-infos)
```

The suite covers SHA-256 hashing (including streamed multi-megabyte files), identical and
renamed duplicate detection, the rule that similar-but-different files are never deleted
automatically, destination-scoped delivery records, retry idempotency, the 1.0 → 2.0
database migration, version comparison, checksum handling and the input validators.

---

## Release process

1. `Version bump` workflow (or a manual `pubspec.yaml` edit) raises the semantic version.
   The Android `versionCode` is derived as `MAJOR×10000 + MINOR×100 + PATCH`, which
   guarantees it always increases — a code is never reused.
2. `Build and Release` validates, tests, builds a **signed** release APK, verifies the
   signature and publishes `DiscordMediaSender.apk` plus `SHA256SUMS.txt` to GitHub
   Releases.
3. The in-app update manager checks the same release endpoint, verifies the SHA-256, checks
   the package id and version code, and hands the APK to the Android installer.

See [`docs/GITHUB_RELEASES.md`](docs/GITHUB_RELEASES.md).

---

## Security model

- Bot tokens and webhook URLs are stored **only** in Android Keystore-backed secure
  storage. They are never written to SQLite, never logged, never exported and never shown
  in a widget.
- The app only talks to `discord.com`, `api.github.com` and (for the bundled fonts) the
  local asset bundle. No credential is transmitted anywhere else.
- Errors and log messages are passed through a secret redactor before they are stored.
- APK updates are verified against the published SHA-256 **and** re-checked natively for
  the application id and a higher version code before the system installer is opened.
- Android always shows its own installation approval dialog; nothing is installed
  silently.

Uninstalling the app or clearing its data removes the stored credentials, because the
Keystore key is destroyed with the application data.

---

## Documentation index

| Document | Contents |
|---|---|
| [`docs/INSTALLATION.md`](docs/INSTALLATION.md) | Installing, updating, permissions, troubleshooting |
| [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) | Local setup, project layout, coding conventions |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Engine, state management, 1.0 → 2.0 comparison |
| [`docs/DATABASE.md`](docs/DATABASE.md) | Every table, indexes and the migration |
| [`docs/DISCORD_SETUP.md`](docs/DISCORD_SETUP.md) | Bot creation, permissions, webhooks |
| [`docs/GITHUB_RELEASES.md`](docs/GITHUB_RELEASES.md) | Workflows, secrets, automatic versioning |
| [`docs/SIGNING.md`](docs/SIGNING.md) | Keystore, secrets, in-place upgrade compatibility |
| [`docs/KNOWN_LIMITATIONS.md`](docs/KNOWN_LIMITATIONS.md) | Android and Discord platform limits |

---

## Licence

Released for the Discord Media Sender project. Discord is a trademark of Discord Inc.;
this project is not affiliated with or endorsed by Discord.
