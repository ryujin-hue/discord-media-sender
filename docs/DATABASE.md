# Database architecture

The app stores everything in a single SQLite database called **`discord_media_sender.db`**
inside the app's private data directory. The file name is unchanged from 1.0, so an
in-place upgrade keeps the existing database.

- Schema version: **2**
- Engine: `sqflite` (Android's SQLite)
- Foreign keys are enabled on every connection (`PRAGMA foreign_keys = ON`)

---

## Legacy tables (1.0)

These three tables are created verbatim so that data written by 1.0 keeps its exact shape.
They are never dropped — a downgrade would still find them.

### `sessions`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER | Primary key, autoincrement |
| `started_at` | INTEGER | Epoch milliseconds |
| `ended_at` | INTEGER | Epoch milliseconds |
| `mode` | TEXT | `webhook` or `bot` |
| `target` | TEXT | Destination label |
| `total_files` | INTEGER | |
| `success` | INTEGER | |
| `failed` | INTEGER | |
| `status` | TEXT | |
| `reason` | TEXT | Added by a 1.0 migration |
| `heartbeat_at` | INTEGER | Added by a 1.0 migration |

Index: `idx_sessions_started (started_at DESC)`

### `session_files`

| Column | Type | Notes |
|---|---|---|
| `session_id` | INTEGER | FK → `sessions(id)` ON DELETE CASCADE |
| `idx` | INTEGER | Position in the session |
| `path` | TEXT | Absolute path |
| `name` | TEXT | File name |
| `size` | INTEGER | Bytes |
| `status` | TEXT | Defaults to `pending` |
| `error` | TEXT | |

Primary key: `(session_id, idx)` · Index: `idx_session_files_path (session_id, path)`

### `failures`

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER | Primary key, autoincrement |
| `session_id` | INTEGER | FK → `sessions(id)` ON DELETE CASCADE |
| `file_name` | TEXT | |
| `file_path` | TEXT | |
| `size_bytes` | INTEGER | |
| `batch_index` | INTEGER | |
| `http_code` | INTEGER | |
| `discord_code` | INTEGER | Added by a 1.0 migration |
| `error_message` | TEXT | |
| `mode` | TEXT | |
| `target` | TEXT | |
| `created_at` | INTEGER | Epoch milliseconds |

Indexes: `idx_failures_session`, `idx_failures_created (created_at DESC)`, `idx_failures_path`

---

## 2.0 tables

### `app_settings`
Key/value store for engine state that has to survive a restart.

| Column | Type |
|---|---|
| `key` | TEXT — primary key |
| `value` | TEXT |
| `updated_at` | INTEGER |

### `media_library`
The local media gallery. One row per known file.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT | Primary key |
| `path` | TEXT | Absolute path on the device |
| `name` | TEXT | |
| `size` | INTEGER | Bytes |
| `added_at` | INTEGER | |
| `status` | TEXT | `new`, `duplicate_detected`, `already_uploaded`, `pending_review`, `uploading`, `uploaded`, `archived`, `failed` |
| `mime_type` | TEXT | |
| `category` | TEXT | `image`, `video`, `audio`, `document`, `other` |
| `sha256` | TEXT | Hex digest, indexed |
| `favorite` | INTEGER | 0/1 |
| `collection_id` | TEXT | FK to `media_collections` (soft reference) |
| `modified_at` | INTEGER | |
| `last_activity_at` | INTEGER | |
| `width` / `height` | INTEGER | Pixel dimensions when known |
| `duration_ms` | INTEGER | Media duration when known |
| `thumbnail_path` | TEXT | Local thumbnail file |
| `archived_at` | INTEGER | Non-null when archived |
| `source_folder` | TEXT | The watched folder the file came from |

Indexes: `idx_media_sha`, `idx_media_status`, `idx_media_added`, `idx_media_category`

### `media_collections` / `collection_items`
User-defined groups. `collection_items` has the composite primary key
`(collection_id, media_id)` and a foreign key to `media_collections` with
`ON DELETE CASCADE`.

### `watched_folders`
Folders monitored by Smart Auto Upload.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT | Primary key |
| `path` | TEXT | |
| `enabled` | INTEGER | 0/1 |
| `created_at` | INTEGER | |
| `name` | TEXT | Display name |
| `last_scan_at` | INTEGER | |
| `include_patterns` | TEXT | Comma separated globs |
| `exclude_patterns` | TEXT | Comma separated globs |
| `max_file_mb` | INTEGER | 0 = no limit |
| `recursive` | INTEGER | 0/1 |

### `auto_upload_rules`
Binds a watched folder to destinations.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT | Primary key |
| `name` | TEXT | |
| `enabled` | INTEGER | 0/1 |
| `mode` | TEXT | `manual`, `semi_automatic`, `fully_automatic` |
| `destination_ids` | TEXT | JSON array of destination ids |
| `created_at` | INTEGER | |
| `watched_folder_id` | TEXT | Null = all folders |
| `include_patterns` / `exclude_patterns` | TEXT | |
| `max_file_mb` | INTEGER | |
| `priority` | INTEGER | Higher runs first |
| `duplicate_policy` | TEXT | `skip`, `ask`, `anyway`, `replace`, `keep_both` |
| `retry_limit` | INTEGER | |
| `schedule_enabled` | INTEGER | 0/1 |
| `schedule_start_minutes` | INTEGER | Minutes after midnight |
| `schedule_duration_minutes` | INTEGER | |
| `weekdays` | TEXT | Comma separated 1–7 |

### `destinations`
A Discord target. **No secret is stored here** — only the reference to the credential
profile and the webhook id.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT | Primary key |
| `name` | TEXT | |
| `type` | TEXT | `webhook` or `bot` |
| `enabled` | INTEGER | 0/1 |
| `created_at` | INTEGER | |
| `channel_id` / `channel_name` | TEXT | Bot target |
| `credential_profile_id` | TEXT | FK to `credential_profiles` |
| `webhook_id` | TEXT | The webhook URL for webhook targets |
| `avatar_url` | TEXT | |
| `priority` | INTEGER | |
| `rate_limit_until` | INTEGER | Set when Discord returns 429 |
| `last_activity_at` | INTEGER | |
| `total_sent` / `total_failed` / `total_pending` | INTEGER | |
| `last_error` | TEXT | Redacted |
| `note` | TEXT | Optional routing rule (`ext:jpg`, `size:25`) |

### `credential_profiles`
The non-secret part of a credential. The token and the webhook URL live in
`flutter_secure_storage` under `profile_<id>_bot` and `profile_<id>_hook`.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT | Primary key |
| `name` | TEXT | |
| `type` | TEXT | `webhook` or `bot` |
| `created_at` | INTEGER | |
| `bot_user_id` / `bot_user_name` / `avatar_url` | TEXT | Filled during validation |
| `last_validated_at` | INTEGER | |
| `is_valid` | INTEGER | Nullable 0/1 |
| `status_message` | TEXT | e.g. `Bot valid: MyBot` |
| `has_webhook` / `has_bot_token` | INTEGER | 0/1 — a flag, never the secret |

### `distribution_jobs`
The queue. One row per (file, destination) pair, which is what gives every destination an
independent queue.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT | Primary key, unique per job |
| `file_path` / `file_name` | TEXT | |
| `file_size` | INTEGER | |
| `status` | TEXT | `pending`, `uploading`, `completed`, `failed`, `paused`, `cancelled` |
| `created_at` | INTEGER | |
| `destination_id` | TEXT | |
| `destination_name` | TEXT | Denormalised for display |
| `sha256` | TEXT | |
| `retry_count` | INTEGER | |
| `priority` | INTEGER | |
| `error_message` | TEXT | Redacted |
| `http_code` / `discord_code` | INTEGER | |
| `message_id` | TEXT | Discord message id |
| `started_at` / `completed_at` | INTEGER | |
| `bytes_sent` / `total_bytes` | INTEGER | |
| `batch_index` | INTEGER | |
| `caption` | TEXT | |

Indexes: `idx_jobs_status`, `idx_jobs_dest`, `idx_jobs_created`

### `delivery_records`
Proof that a specific file was delivered to a specific destination. This is what makes
duplicate detection destination-aware.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT | Primary key |
| `sha256` | TEXT | The delivered content |
| `destination_id` | TEXT | |
| `delivered_at` | INTEGER | |
| `file_name` / `file_size` / `file_path` | | |
| `message_id` / `message_url` / `attachment_url` | TEXT | Discord references |
| `job_id` | TEXT | |

Index: `idx_delivery_sha_dest (sha256, destination_id)`

### `upload_history`
The unified history. New uploads are written here directly; 1.0 rows are migrated into it.

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT | Primary key |
| `file_name` / `file_path` / `file_size` | | |
| `status` | TEXT | |
| `created_at` / `completed_at` | INTEGER | |
| `sha256` | TEXT | |
| `destination_id` / `destination_name` | TEXT | |
| `mode` / `target` | TEXT | Legacy-compatible |
| `error_message` | TEXT | |
| `http_code` / `discord_code` | INTEGER | |
| `retry_count` | INTEGER | |
| `message_id` / `message_url` | TEXT | |
| `session_id` | TEXT | Groups the files of one session |
| `migrated_from` | TEXT | `sessions`, `session_files`, `failures` or empty |

### `analytics_events`
One row per meaningful event, used to build the statistics.

| Column | Type |
|---|---|
| `id` | TEXT — primary key |
| `event_type` | TEXT — `upload_completed`, `upload_failed`, `file_archived`, `file_restored`, … |
| `created_at` | INTEGER |
| `destination_id` | TEXT |
| `file_size` | INTEGER |
| `duration_ms` | INTEGER |
| `success` | INTEGER — 0/1 |
| `metadata` | TEXT |

Indexes: `idx_analytics_created`, `idx_analytics_type`

### `update_history`
Every update check and installation attempt: `id`, `version`, `checked_at`, `installed_at`,
`status`, `release_url`, `notes`, `sha256`, `error`.

### `file_hashes`
SHA-256 registry. Primary key `(sha256, path)` with `first_seen_at`, `last_seen_at`,
`size` and `media_id`. Index `idx_hashes_sha` supports the lookup that turns a new file
into a duplicate candidate.

### `duplicate_records` / `duplicate_review_history`
`duplicate_records` stores the relationship: `original_id`, `duplicate_id`, `method`
(`sha256`, `metadata`, `perceptual`), `detected_at`, `decision`, `similarity` and the file
names/paths for display.

`duplicate_review_history` is the audit trail: `duplicate_id`, `reviewed_at`, `decision`
and an optional `note`.

### `archive_records` / `archive_rules` / `archive_operations`
`archive_records` holds one row per archived item (`media_id`, `archived_at`, `category`,
`file_size`, `restored_at`, `original_path`, `archive_path`, `destination_id`).

`archive_rules` holds the automatic rules (`archive_after_upload`, `archive_after_days`,
`categories`, `exclude_favorites`, `exclude_folders`, `exclude_pending_review`,
`max_age_days`).

`archive_operations` is the log: `operation`, `created_at`, `item_count`, `media_id`,
`detail`.

### `upload_progress`
The last known byte count for every running job, plus the measured speed and ETA. This
survives a process restart so the UI can show where an interrupted upload stopped.

### `live_activity_events`
The timeline: `id`, `type`, `created_at`, `message`, `file_name`, `destination_id`,
`destination_name`, `detail`, `severity` (`info`, `success`, `warning`, `error`).

### `widget_settings` / `dashboard_preferences`
Single-row tables (id = `default`) that hold the home-widget and floating-overlay flags,
the overlay position, the speed/compact toggles, the dashboard date range and the
destination filter.

---

## Migration

`AppDatabase` runs at `version 2`. On upgrade from version 1:

1. The three legacy tables are created if they are missing.
2. All 23 new tables are created with their indexes.
3. `_migrateLegacyData` copies the rows:
   - every `sessions` row → one `upload_history` row with `migrated_from = 'sessions'`
   - every `session_files` row → one `upload_history` row with `migrated_from = 'session_files'`
   - every `failures` row → one `upload_history` row with `migrated_from = 'failures'`
4. The legacy tables are **left in place**.

A migration failure never prevents the app from starting: the legacy tables remain
readable and the copy can be retried on the next launch.

The migration is covered by `test/database_test.dart`, which builds a real 1.0 schema,
writes sessions, files and failures into it and asserts that all of them appear in the
2.0 history table with their error codes intact.

## Credential storage

Credentials are **not** in this database.

| Key | Content |
|---|---|
| `profile_<id>_bot` | Bot token (Keystore-encrypted) |
| `profile_<id>_hook` | Webhook URL (Keystore-encrypted) |
| `profile_<id>_name` | Bot display name |
| `profile_<id>_channel` | Last selected channel |

The 1.0 flat keys `cfg_bot_token`, `cfg_webhook_url`, `cfg_bot_name`, `cfg_avatar_url`,
`cfg_channel_id`, `cfg_channel_name` and `cfg_mode` are migrated into the
`legacy_default` profile on the first launch of 2.0 and then deleted, so there is exactly
one storage mechanism.
