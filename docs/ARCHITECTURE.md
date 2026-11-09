# Architecture

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│ Presentation                                                  │
│  root_shell (5 tabs) · screens/* · widgets/*                 │
└───────────────┬──────────────────────────────────────────────┘
                │ Riverpod providers (reactive, shared state)
┌───────────────▼──────────────────────────────────────────────┐
│ State                                                          │
│  config_providers · upload_providers · engineSnapshotProvider │
└───────────────┬──────────────────────────────────────────────┘
                │
┌───────────────▼──────────────────────────────────────────────┐
│ Services (the functional core)                                │
│                                                              │
│  UploadEngine  ◄── the only component that uploads           │
│   ├── DiscordApiClient   REST v10, 429 handling, multipart   │
│   ├── DuplicateService    SHA-256 + delivery records         │
│   ├── ArchiveService      archive / restore / rules          │
│   ├── MediaService        scan, ZIP, thumbnails, compression │
│   ├── DistributionService destinations + credential profiles │
│   ├── AnalyticsService    real statistics + CSV/JSON/PDF      │
│   ├── AutoUploadService   folder monitoring + rules          │
│   ├── UpdateService       GitHub releases + checksum verify  │
│   ├── ForegroundManager   background service (same engine)    │
│   └── WidgetBridge        platform channel to the widgets    │
└───────────────┬──────────────────────────────────────────────┘
                │
┌───────────────▼──────────────────────────────────────────────┐
│ Data                                                          │
│  AppDatabase (SQLite, schema v2 + 1.0 migration)              │
│  SecureStore (Android Keystore backed)                       │
└──────────────────────────────────────────────────────────────┘
```

## The centralised upload engine

`lib/services/upload_engine.dart` owns the whole transfer lifecycle:

| Responsibility | Implementation |
|---|---|
| File validation | Existence, size limit, destination enabled state |
| File hashing | SHA-256 via `Security.sha256File`, streamed in 1 MB chunks |
| Duplicate detection | `file_hashes` + `delivery_records`, checked per destination |
| Queue management | One `distribution_jobs` row per (file, destination) pair |
| Upload execution | `DiscordApiClient.sendWebhook` / `sendBotMessage` |
| Destination routing | Resolved by `DistributionService.resolveTargets` |
| Progress reporting | Bytes sent / total, speed, ETA |
| Retry management | Retry counter per job, manual retry, automatic backoff |
| Rate-limit handling | `retry_after`, `x-ratelimit-remaining`, `x-ratelimit-reset-after` |
| Delivery verification | A `delivery_records` row is written only after a 2xx response |
| History recording | `upload_history`, `analytics_events`, `live_activity_events` |
| Archive integration | The media entry is flagged as uploaded after a success |
| Live event publishing | A broadcast `Stream<EngineSnapshot>` |

Every job id is unique and every job is persisted **before** it runs, so a restart resumes
rather than repeats. After the process is killed mid-request, the job stays `uploading` in
the database; on the next launch it is returned to `pending` and retried. Discord cannot
guarantee exactly-once delivery for a request that was interrupted after the server
received it, so the app reconciles through `delivery_records` (a file already delivered to
a destination is not sent to that destination again) instead of claiming perfect
exactly-once semantics.

## Shared state

`engineSnapshotProvider` is a `StreamProvider` over `UploadEngine.snapshots`. Every
surface — the dashboard, the distribution screen, the home-screen widget, the floating
overlay — derives its view from that one stream. There is no manual refresh anywhere and
opening a screen never restarts or duplicates an upload.

The native widgets cannot subscribe to a Dart stream, so the engine state is mirrored into
`UploadStateStore` (a `SharedPreferences` file) through `WidgetBridge.publishState` on
every change. Widget actions travel back the other way as a timestamped control command
(`dms_control_command`) which the engine polls — the same mechanism works in the UI
isolate and in the background isolate, and the timestamp makes the command idempotent.

## The background service

`flutter_foreground_task` keeps a second Dart isolate alive with a foreground
notification while uploads run. That isolate runs the **same** `UploadEngine`; it is not a
second upload path. The two isolates coordinate through the database (`engine_pause`,
`engine_cancel`) and through `SharedPreferences` (the widget control command).

## 1.0 → 2.0 changes

| Area | 1.0.a9 | 2.0.0 |
|---|---|---|
| Application id | `com.dmsender.discord_media_sender` | **unchanged** |
| Version | 1.0.9 (code 15) | 2.0.0 (code 20000) |
| min / target SDK | 24 / 36 | **unchanged** |
| Database | `sessions`, `session_files`, `failures` | the same three **plus 23 new tables**; legacy rows copied into `upload_history` |
| Secure store | flat keys `cfg_*` | namespaced profiles `profile_<id>_*`; the flat keys are migrated on first launch and removed |
| Destinations | one webhook **or** one bot | any number, each with an independent queue |
| Uploads | one queue, batch retries | per-destination queues, per-job retries, duplicate-aware enqueue |
| UI | 4 screens | 5 tabs + 14 screens, Material 3 premium dark theme |
| Widgets | none | home-screen widget + floating overlay |
| Analytics | none | real statistics with CSV / JSON / PDF export |
| Duplicate detection | none | SHA-256, destination aware, reviewable |
| Archive | none | logical archive, rules, restore, operation history |
| Updates | GitHub release check | + SHA-256 verification, package id and version code validation |
| Fonts | `google_fonts` (runtime download) | bundled Inter + Manrope (offline, no runtime fetch) |

## Why `google_fonts` was replaced

`google_fonts` 9.x targets the split-out `material_ui` package and does not compile against
Flutter 3.47.9. Bundling the fonts is also the better production choice: the app renders
correctly offline and never contacts `fonts.gstatic.com` at runtime.
