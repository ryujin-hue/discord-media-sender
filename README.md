<p align="center">
  <img src="assets/brand/logo_paper_plane.svg" alt="Discord Media Sender — origami paper plane" width="220">
</p>

<p align="center">
  <b>Discord Media Sender</b><br>
  <sub>Smart, multi-destination media delivery for Discord — built on the 1.0 upload engine.</sub>
</p>

<p align="center">
  <a href="https://github.com/ryujin-hue/discord-media-sender/releases/latest">
    <img alt="Latest release" src="https://img.shields.io/github/v/release/ryujin-hue/discord-media-sender?label=release&style=flat-square">
  </a>
  <a href="https://github.com/ryujin-hue/discord-media-sender/actions">
    <img alt="Build status" src="https://img.shields.io/github/actions/workflow/status/ryujin-hue/discord-media-sender/release.yml?branch=main&style=flat-square&label=ci">
  </a>
  <img alt="Android" src="https://img.shields.io/badge/android-7.0%2B-3DDC84?style=flat-square">
  <img alt="Flutter" src="https://img.shields.io/badge/flutter-3.47.9-02569A?style=flat-square">
  <img alt="Discord API" src="https://img.shields.io/badge/discord%20API-v10-5865F2?style=flat-square">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue?style=flat-square">
</p>

---

Discord Media Sender is a production Android application that sends files, folders and ZIP
archives to Discord through webhooks and bot accounts. It adds Smart Auto Upload, a Media
Gallery, an Advanced Analytics Center, Multi-Discord Distribution, a persistent Credential
Manager, an Android home-screen widget, a floating overlay, an anti-duplication system, archive
management and a live progress dashboard — all driven by a single centralised upload engine.

<table>
<tr>
<td width="120"><img src="android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" alt="App icon" width="96"></td>
<td>

| | |
|:---|:---|
| **Application id** | `com.dmsender.discord_media_sender` |
| **Version** | 2.1.1 (versionCode 20101) |
| **Minimum Android** | 7.0 (API 24) |
| **Target / compile SDK** | 36 |
| **Flutter** | 3.47.9 stable · Dart 3.13.7 |
| **Discord API** | REST v10 |
| **Repository** | [`ryujin-hue/discord-media-sender`](https://github.com/ryujin-hue/discord-media-sender) |
| **Licence** | MIT — see [Licence](#licence) |

</td>
</tr>
</table>

---

## Contents

- [Quick start](#quick-start)
- [What changed in 2.1.1](#what-changed-in-211)
- [What changed in 2.1](#what-changed-in-21)
- [Migration and mapping](#migration-and-mapping)
- [Features](#features)
- [Architecture](#architecture)
- [Background uploads](#background-uploads)
- [Developer setup](#developer-setup)
- [Testing](#testing)
- [Release process](#release-process)
- [Security model](#security-model)
- [Documentation](#documentation)
- [Licence](#licence)

---

## Quick start

Download `DiscordMediaSender.apk` and `SHA256SUMS.txt` from the
[GitHub Releases page](https://github.com/ryujin-hue/discord-media-sender/releases/latest),
verify the checksum and install the APK:

```bash
sha256sum -c SHA256SUMS.txt
adb install -r DiscordMediaSender.apk
```

Installing over an existing 1.0 installation keeps all user data. The full guide — including
the `REQUEST_INSTALL_PACKAGES` permission and the "unknown sources" step — is in
[`docs/INSTALLATION.md`](docs/INSTALLATION.md).

---

## What changed in 2.1.1

The 2.1.1 release makes the background upload actually work. The audit of the 2.1.0 build found
three defects in the background path, each of them proved by a failing test before it was fixed.

| Defect | Cause | Fix |
|:---|:---|:---|
| **The foreground service was never initialised.** The transfer stopped as soon as the app went to the background. | The plugin refuses to start a service that was not prepared, and the exception was swallowed. | The plugin is prepared before the first upload, with a wake lock, an auto restart, and a restart after a reboot or an app update. |
| **A file could be uploaded twice.** | The app isolate and the service isolate are two engines that share the queue, and both could pick up the same pending job. | A job is claimed atomically before it is sent, so exactly one isolate sends it. |
| **An interrupted upload was lost.** A job that was being sent when the process died stayed in the "uploading" state forever. | Only the `pending` jobs were restored. | Every job carries a heartbeat; interrupted work goes back into the queue instead of disappearing. |

The home screen now says it plainly when work is pending and the background service is not
running, instead of letting the upload die silently.

The whole picture — what keeps a transfer alive, and what the app asks of you — is in
[`docs/BACKGROUND_UPLOADS.md`](docs/BACKGROUND_UPLOADS.md).

---

## What changed in 2.1

### Fixed

- **The foreground service now starts with the queue.** Uploads are no longer killed by the
  system a moment after they begin, and work that a killed process left behind is picked up
  again on the next start.
- **Resume works after a process death.** The old guard skipped the resume when the engine
  was not marked as paused, which is exactly the state a fresh process is in.
- **The "start" command of the widget is no longer inert** — it runs the pending queue.
- **The ETA is an average since the start of the job**, not the speed of the last chunk, so
  it stays stable on a steady transfer.
- **The About screen keeps its labels horizontal** on a 360 dp screen; the label column has
  a fixed width and the value is ellipsised instead of wrapping.

### New

| Feature | What it does |
|:---|:---|
| **Queue presets** | A named set of destinations, caption template, duplicate policy and maximum file size that fills the upload form with one tap. A preset whose destination was deleted is marked invalid instead of silently uploading to fewer places. |
| **Bandwidth cap** | A global limit in KB/s that slows the transfer down for real. Discord rate limits still apply on top of it. |
| **Quiet hours** | A local time window per destination. The automatic upload skips the destination and reports the reason; a manual upload is only refused when the window is marked strict. |
| **Batch retry** | Every failed upload of the current history filter is queued again with one action. |
| **Export jobs CSV** | The visible history as a CSV file, shared through the system sheet. The export is redacted, so a webhook URL or a bot token can never end up in it. |
| **Widget density** | The home screen widget renders three lines or two. |
| **Safe resume** | The cold-start behaviour is configurable: never, ask, or resume automatically. |
| **Overlay auto-hide** | The floating overlay hides itself while the engine is idle and the queue is empty, and comes back as soon as there is work. Dismissing the overlay never cancels an upload. |

### Brand

The origami paper plane is the product mark: folded wing planes, a centre spine and a violet
nose tip. It is used as the launcher icon, on the launch screen, in the About header and in
the onboarding. The four variants live in `assets/brand/`, the rules in
[`docs/BRAND.md`](docs/BRAND.md).

---

## Migration and mapping

The 1.0.a9 build was a Flutter application with a working upload engine, a `sessions` /
`session_files` / `failures` database, secure credential storage and GitHub-based update
checking. **2.x keeps all of that and rebuilds around it.** Nothing has to be re-entered, and
nothing is thrown away: the legacy tables are still written, so a downgrade still finds them.

### Data — `discord_media_sender.db`

| 1.0 | 2.1 | What happens on the first launch |
|:---|:---|:---|
| `sessions` | `upload_history` (`migrated_from = 'sessions'`) | Every session row becomes a history entry with the file count, the byte count and the outcome. |
| `session_files` | `upload_history` (`migrated_from = 'session_files'`) | Every file row becomes a history entry with its name and size. |
| `failures` | `upload_history` (`migrated_from = 'failures'`) | Every failure row becomes a history entry with its HTTP code, Discord code and message. |
| — | `distribution_jobs` | The persistent queue: one row per file per destination, with its status, retry counter and heartbeat. |
| — | `delivery_records` | SHA-256 per destination. The base of the anti-duplication system. |
| — | `destinations`, `credential_profiles` | The webhook and bot targets, with their own queues and counters. |
| — | `media_library`, `media_collections` | The local gallery and its collections. |
| — | `queue_presets`, `destination_quiet_hours` | Added in 2.1. |

The three legacy tables are **kept as they are**. The migration only copies out of them.

### Credentials — Android Keystore

| 1.0 key | 2.1 home |
|:---|:---|
| `cfg_bot_token` | credential profile `legacy_default` → `botToken` |
| `cfg_webhook_url` | credential profile `legacy_default` → `webhookUrl` |
| `cfg_bot_name` | credential profile `legacy_default` → `botName` |
| `cfg_avatar_url` | credential profile `legacy_default` → `avatarUrl` |
| `cfg_channel_id` | credential profile `legacy_default` → `channelId` |
| `cfg_channel_name` | credential profile `legacy_default` → `channelName` |
| `cfg_mode` | credential profile `legacy_default` → `mode` |

The flat keys are cleared once the migration ran, so there is exactly one source of truth and
no secret is left behind in the old place.

### Preferences — `SharedPreferences`

| 1.0 key | 2.1 |
|:---|:---|
| `set_theme_mode` | unchanged |
| `set_onboarding_done` | unchanged |
| `set_max_file_mb` | unchanged |
| `set_auto_update` | unchanged |
| `set_battery_asked` | unchanged |
| `set_orientation` | unchanged |
| `set_update_last_check_ms` | unchanged |
| `set_update_skipped_tag` | unchanged |
| — | `set_bandwidth_cap_kb`, `set_safe_resume`, `set_widget_density`, `set_overlay_auto_hide`, `set_overlay_enabled` (new in 2.1) |

### Behaviour and identity

| 1.0 | 2.1 |
|:---|:---|
| Application id `com.dmsender.discord_media_sender` | unchanged |
| App label `Discord Media Sender` | unchanged |
| Database `discord_media_sender.db` | unchanged, schema v4 |
| Minimum SDK 24 | unchanged |
| ZIP import limit of 5 GB | unchanged |
| Update check every 6 hours | unchanged |
| Batching and `retry_after` handling | unchanged |
| Pause after the current batch | unchanged |

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full comparison and
[`docs/DATABASE.md`](docs/DATABASE.md) for the schema and the migration details.

---

## Features

| Feature | Summary |
|:---|:---|
| **Smart Auto Upload** | Watch one or more folders, filter by file type and size, and send new files automatically. Three modes — **manual**, **semi-automatic** (confirm before sending) and **fully automatic**. Rules carry their own destination set, duplicate policy, retry limit, priority and an optional daily time window. |
| **Media Gallery & Local Library** | Every file that passes through the app is indexed with its size, MIME type, category, modification date, **SHA-256 hash**, dimensions and thumbnail. Search, sort, filter by category, star favourites and group files into collections. |
| **Advanced Analytics Center** | All statistics are computed from real database rows. Upload activity over time, daily volume, success/failure ratio, data transfer, destination performance, duplicate statistics and archive activity — filterable by the last 24 hours, 7 days, 30 days or all time, and exportable to **CSV, JSON and PDF**. Exports never contain credentials. |
| **Multi-Discord Distribution** | Any number of webhook and bot destinations, each with an **independent** queue, delivery history, retry counter, error history and rate-limit state. Distribution modes: broadcast, manual selection, round robin, rule based and sequential. Rule syntax for per-destination routing: `ext:jpg`, `cat:image`, `size:25`. |
| **Credential & Webhook Manager** | Add, validate, edit, replace, remove and test bot and webhook profiles. Webhooks can be created through an authorised bot (server → channel → webhook) with the **Manage Webhooks** permission. Secrets live in Android Keystore-backed storage, are masked in the UI and never reach SQLite, logs or analytics. |
| **Android Screen Widget** | A home-screen widget showing the real upload status, queue count, successful and failed counts, overall progress and the active destination, with Pause / Resume / Open actions. |
| **Floating Overlay** | An optional draggable, collapsible panel that shows the current file, progress, speed and ETA with pause/resume controls. It requires the *Display over other apps* permission and is never activated without explicit consent. |
| **Anti-Duplication System** | SHA-256 is the only method that proves identical content. Metadata matches are surfaced as suggestions and perceptual hashes are never treated as proof. Handling modes: skip, ask before upload, upload anyway, replace library entry, keep both. **Detection is destination-aware** — a file sent to server A is still considered new for server B. Original files are never deleted automatically. |
| **Archive Management** | Archive selected files, everything that finished uploading, or whole categories. Restore is always available. Archiving marks the entry and writes a record; the file on disk is only moved when the user explicitly allows it, and permanent deletion always requires an explicit confirmation. |
| **Live Progress Dashboard** | Total files, uploaded, uploading, pending, failed, duplicates, archived and transferred bytes — plus a live per-task monitor, per-destination monitoring, a timestamped activity timeline and quick controls. All surfaces share one reactive state stream, so a status change appears everywhere at once and opening a screen never restarts an upload. |

> **The gallery is a local media library.** Discord-hosted attachments are referenced by message
> id and URL; Discord CDN links are not permanent and the app never claims otherwise. There is
> no cloud storage backend — the architecture leaves room for one.

---

## Architecture

```
lib/
  core/          constants, theme, formatters, validators, secure store, hashing
  data/          models and the SQLite layer (schema v4 + the 1.0 migration)
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

**One engine, one state.** `UploadEngine` is the only component that uploads. The dashboard,
the distribution screen, the home-screen widget and the floating overlay all read the same
snapshot stream — there is no second upload path behind the widgets.

Full details: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

---

## Background uploads

Leaving the app does not stop a transfer. The upload runs inside an Android foreground service
with a wake lock, and the service shares the queue with the app instead of running a second
upload path.

| | |
|:---|:---|
| **Leaving the app** | The service keeps running; the transfer continues with the screen off. |
| **Swiping the app away** | The process dies. The queue stays on disk and the next start recovers the interrupted work. |
| **Reboot or app update** | The service starts again and recovers the queue. |
| **Two isolates, one queue** | A job is claimed atomically before it is sent, so a file is never uploaded twice. |
| **Interrupted work** | Every job carries a heartbeat; work that was interrupted goes back into the queue. |

Two device settings make this reliable: **Battery optimisation → Unrestricted** and
**Notifications → allowed**. The app asks for both and reports the result in the home screen.

Details: [`docs/BACKGROUND_UPLOADS.md`](docs/BACKGROUND_UPLOADS.md).

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
automatically, destination-scoped delivery records, retry idempotency, the atomic job claim
between two isolates, the heartbeat recovery of an interrupted upload, the 1.0 → 2.x database
migration, version comparison, checksum handling and the input validators.

---

## Release process

1. **`Version bump` workflow** (or a manual `pubspec.yaml` edit) raises the semantic version.
   The Android `versionCode` is derived as `MAJOR×10000 + MINOR×100 + PATCH`, which
   guarantees it always increases — a code is never reused.
2. **`Build and Release`** validates, tests, builds a **signed** release APK, verifies the
   signature and publishes `DiscordMediaSender.apk` plus `SHA256SUMS.txt` to GitHub
   Releases.
3. **The in-app update manager** checks the same release endpoint, verifies the SHA-256,
   checks the package id and version code, and hands the APK to the Android installer.

See [`docs/GITHUB_RELEASES.md`](docs/GITHUB_RELEASES.md).

---

## Security model

- Bot tokens and webhook URLs are stored **only** in Android Keystore-backed secure storage.
  They are never written to SQLite, never logged, never exported and never shown in a widget.
- The app only talks to `discord.com`, `api.github.com` and (for the bundled fonts) the local
  asset bundle. No credential is transmitted anywhere else.
- Errors and log messages are passed through a secret redactor before they are stored.
- APK updates are verified against the published SHA-256 **and** re-checked natively for the
  application id and a higher version code before the system installer is opened.
- Android always shows its own installation approval dialog; nothing is installed silently.

Uninstalling the app or clearing its data removes the stored credentials, because the Keystore
key is destroyed with the application data.

---

## Documentation

| Document | Contents |
|:---|:---|
| [`docs/INSTALLATION.md`](docs/INSTALLATION.md) | Installing, updating, permissions, troubleshooting |
| [`docs/BACKGROUND_UPLOADS.md`](docs/BACKGROUND_UPLOADS.md) | What keeps a transfer alive, and what the app asks of you |
| [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) | Local setup, project layout, coding conventions |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Engine, state management, the 1.0 → 2.x comparison |
| [`docs/DATABASE.md`](docs/DATABASE.md) | Every table, indexes and the migration |
| [`docs/DISCORD_SETUP.md`](docs/DISCORD_SETUP.md) | Bot creation, permissions, webhooks |
| [`docs/GITHUB_RELEASES.md`](docs/GITHUB_RELEASES.md) | Workflows, secrets, automatic versioning |
| [`docs/SIGNING.md`](docs/SIGNING.md) | Keystore, secrets, in-place upgrade compatibility |
| [`docs/BRAND.md`](docs/BRAND.md) | The origami paper plane mark and its rules |
| [`docs/KNOWN_LIMITATIONS.md`](docs/KNOWN_LIMITATIONS.md) | Android and Discord platform limits |

---

## Licence

The source code of Discord Media Sender is released under the **MIT licence**.

| | |
|:---|:---|
| **Licence** | MIT |
| **Full text** | [`LICENSE`](LICENSE) |
| **Copyright** | © 2026 Discord Media Sender contributors |
| **Applies to** | The Dart and Kotlin source, the brand assets, the documentation and the build workflows |

### Third-party components

The project ships third-party code and assets that keep **their own** licences.

| Component | Licence |
|:---|:---|
| **Inter** — bundled typeface in `assets/fonts/` | SIL Open Font License 1.1 · © 2016 The Inter Project Authors |
| **Manrope** — bundled typeface in `assets/fonts/` | SIL Open Font License 1.1 · © 2019 The Manrope Project Authors |
| **Flutter** SDK — the engine binaries inside the APK | BSD-3-Clause · © 2014 The Flutter Authors |
| **MIT packages** — `cupertino_icons`, `flutter_riverpod`, `dio`, `archive`, `android_file_picker`, `file_picker`, `flutter_video_thumbnail_plus`, `flutter_foreground_task`, `flutter_svg`, `image` | MIT |
| **BSD-3-Clause packages** — `path`, `crypto`, `intl`, `convert`, `collection`, `open_filex`, `package_info_plus`, `device_info_plus`, `path_provider`, `shared_preferences`, `flutter_secure_storage` and their Android packages, `share_plus` | BSD-3-Clause |
| **sqflite** | BSD-2-Clause |
| **pdf** | Apache-2.0 |
| **Android Gradle Plugin**, **Gradle**, **Kotlin** — the build toolchain | Apache-2.0 |

Every one of those packages ships its own `LICENSE` file inside the package. `flutter pub
deps` lists every one of them with its source and version.

Both typefaces carry their Open Font License notice inside the font file itself. The Open Font
License requires the copyright notice and the licence text to travel with the fonts: if you
redistribute the APK or the assets folder, ship the Inter and Manrope licence notices next to
`assets/fonts/`.

### Trademarks

Discord is a trademark of Discord Inc. This project is not affiliated with, endorsed by or
sponsored by Discord Inc. The origami paper plane is an original mark of this project; no
Discord brand asset is used.

### The release signing key

The Android release keystore is **not** covered by the MIT licence and is **not** part of this
repository — it is git-ignored. It is the identity that lets a new release install over an
existing installation, so it has to stay private. See
[`docs/SIGNING.md`](docs/SIGNING.md).
