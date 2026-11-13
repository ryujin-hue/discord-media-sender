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

---

## 2.1 changes

### The upload lifecycle

The 2.0 build started the queue without the foreground service and guarded the resume with
`if (!_paused) return`. A fresh process is never marked as paused, so the resume was a no-op
and a killed upload stayed dead. The 2.1 lifecycle is:

```
enqueue ──> run() ──> ForegroundManager.start()
                │
                └── ForegroundService isolate ──> same UploadEngine, same queue
```

- `enqueue()` starts the engine **and** the foreground service together.
- `resume()` always clears the pause flag and starts the queue when work is pending, even
  after a process death.
- The native `start` command does the same, so a widget can revive a queue whose process was
  killed.
- On a cold start `main()` restores the queue and starts the foreground service when
  something is still pending. The *safe resume* policy decides whether the queue is then
  started right away, after a prompt, or not at all.

### The speed and the ETA

The speed is the average since the start of the current job:

```
speed = sentBytes / secondsSinceJobStart
eta   = (totalBytes - sentBytes) / speed
```

An instantaneous sample jumps around on a steady transfer and makes the ETA useless.

### The bandwidth cap

The cap is a global limit in KB/s. It is applied where the file is attached to the request:
the file is streamed through a rate limiter instead of being handed to the HTTP client as a
plain file, so the transfer really is slowed down. The cap never replaces the Discord rate
limits; both apply.

### The control bus

The native side never uploads. It reads the mirrored state from `UploadStateStore` and writes
a command into `dms_control_command`:

```
{epochMs}:{pause|resume|start|cancel}
```

The timestamp makes the command idempotent across the two Dart isolates. `resume` and `start`
both call `run()` when work is pending — that is what makes the widget a real control.

### The overlay

The floating overlay is a view onto the same state store. Two rules matter:

- Dismissing the overlay only removes the panel. It never cancels an upload and never stops
  the foreground service.
- The overlay auto-hides while the engine is idle and the queue is empty, and reappears as
  soon as there is work.

---

## 2.1.1: the background model

### The service is prepared before the first upload

`flutter_foreground_task` refuses to start a service that was not initialised.
The 2.1.0 build never called `init`, so the exception was swallowed and the
foreground service never ran. `ForegroundManager.initialize()` prepares the
plugin in `main()` with a wake lock, an auto restart and a restart after a
reboot or an app update.

### A job is claimed before it is sent

The app isolate and the service isolate are two engines that share the SQLite
queue. A job is claimed with an atomic update that only succeeds while the job
is still pending:

```sql
UPDATE distribution_jobs
   SET status = 'uploading', started_at = ?, heartbeat_at = ?
 WHERE id = ? AND status = 'pending'
```

The isolate that wins the claim sends the file; the other one moves on. A file
is therefore never uploaded twice.

### The heartbeat proves that a job is alive

A claimed job refreshes `heartbeat_at` on every progress callback and every
15 seconds. The recovery uses it:

- The cold start of the app recovers every job that is still marked as
  uploading, because the whole process is new.
- The service isolate recovers only jobs whose heartbeat went stale, because
  the app isolate may be uploading a job right now.

### The shared pause flag

The pause flag lives in the database and is shared by both isolates. It is
cleared by an explicit resume or cancel, never by the end of a run loop — that
would silently continue an upload that the user paused.

### The state comes from the database

The counts in the snapshot are read from the database, so both isolates report
the same numbers and the widget stays correct while the app is in the
background.
