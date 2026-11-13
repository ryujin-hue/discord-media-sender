import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import 'models.dart';

/// The persistent SQLite store for Discord Media Sender.
///
/// Version 1 was the schema shipped with the 1.0.a9 build (`sessions`,
/// `session_files`, `failures`). Version 2 adds the 2.0 feature tables and
/// migrates the 1.0 rows into the unified `upload_history` table so that no
/// user data is lost when the app is updated in place.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  Completer<Database>? _opening;

  /// Overrides the database file location.
  ///
  /// The production app never sets this; the test suite uses it to run each
  /// case against an isolated database file.
  static String? pathOverride;

  /// Opens (or returns the already open) database.
  Future<Database> get database async {
    final Database? existing = _db;
    if (existing != null && existing.isOpen) return existing;
    if (_opening != null) return _opening!.future;
    final Completer<Database> completer = Completer<Database>();
    _opening = completer;
    try {
      final String path =
          pathOverride ??
          '${await getDatabasesPath()}/${AppConstants.databaseName}';
      final Database db = await openDatabase(
        path,
        version: AppConstants.databaseVersion,
        onConfigure: (Database db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (Database db, int version) async {
          await _createLegacyTables(db);
          await _createV2Tables(db);
          await _createV3Tables(db);
          await _createV4Tables(db);
        },
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
          if (oldVersion < 2) {
            await _createLegacyTables(db);
            await _createV2Tables(db);
            await _migrateLegacyData(db);
          }
          if (oldVersion < 3) {
            await _createV3Tables(db);
          }
          if (oldVersion < 4) {
            await _createV4Tables(db);
          }
        },
      );
      _db = db;
      completer.complete(db);
    } catch (error, stack) {
      completer.completeError(error, stack);
      _opening = null;
      rethrow;
    }
    _opening = null;
    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // Schema
  // ---------------------------------------------------------------------------

  /// Tables carried over from the 1.0 schema, created verbatim so that data
  /// written by 1.0 keeps its exact shape.
  static Future<void> _createLegacyTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at INTEGER NOT NULL,
        ended_at INTEGER NOT NULL,
        mode TEXT NOT NULL,
        target TEXT NOT NULL,
        total_files INTEGER NOT NULL,
        success INTEGER NOT NULL,
        failed INTEGER NOT NULL,
        status TEXT NOT NULL,
        reason TEXT,
        heartbeat_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sessions_started ON sessions(started_at DESC)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS session_files (
        session_id INTEGER NOT NULL,
        idx INTEGER NOT NULL,
        path TEXT NOT NULL,
        name TEXT NOT NULL,
        size INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        error TEXT,
        PRIMARY KEY (session_id, idx),
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_session_files_path ON session_files(session_id, path)',
    );

    await db.execute('''
      CREATE TABLE IF NOT EXISTS failures (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER,
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        batch_index INTEGER NOT NULL,
        http_code INTEGER,
        discord_code INTEGER,
        error_message TEXT NOT NULL,
        mode TEXT NOT NULL,
        target TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_failures_session ON failures(session_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_failures_created ON failures(created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_failures_path ON failures(file_path)',
    );
  }

  /// All tables introduced by 2.0.
  static Future<void> _createV2Tables(Database db) async {
    final List<String> statements = <String>[
      '''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS media_library (
        id TEXT PRIMARY KEY,
        path TEXT NOT NULL,
        name TEXT NOT NULL,
        size INTEGER NOT NULL DEFAULT 0,
        added_at INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'new',
        mime_type TEXT,
        category TEXT NOT NULL DEFAULT 'other',
        sha256 TEXT,
        favorite INTEGER NOT NULL DEFAULT 0,
        collection_id TEXT,
        modified_at INTEGER,
        last_activity_at INTEGER,
        width INTEGER,
        height INTEGER,
        duration_ms INTEGER,
        thumbnail_path TEXT,
        archived_at INTEGER,
        source_folder TEXT
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_media_sha ON media_library(sha256)',
      'CREATE INDEX IF NOT EXISTS idx_media_status ON media_library(status)',
      'CREATE INDEX IF NOT EXISTS idx_media_added ON media_library(added_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_media_category ON media_library(category)',
      '''
      CREATE TABLE IF NOT EXISTS media_collections (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        description TEXT,
        color_value INTEGER
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS collection_items (
        collection_id TEXT NOT NULL,
        media_id TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        PRIMARY KEY (collection_id, media_id),
        FOREIGN KEY (collection_id) REFERENCES media_collections(id) ON DELETE CASCADE
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS watched_folders (
        id TEXT PRIMARY KEY,
        path TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        name TEXT,
        last_scan_at INTEGER,
        include_patterns TEXT DEFAULT '',
        exclude_patterns TEXT DEFAULT '',
        max_file_mb INTEGER NOT NULL DEFAULT 0,
        recursive INTEGER NOT NULL DEFAULT 1
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS auto_upload_rules (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        mode TEXT NOT NULL DEFAULT 'manual',
        destination_ids TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL,
        watched_folder_id TEXT,
        include_patterns TEXT DEFAULT '',
        exclude_patterns TEXT DEFAULT '',
        max_file_mb INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 0,
        duplicate_policy TEXT NOT NULL DEFAULT 'skip',
        retry_limit INTEGER NOT NULL DEFAULT 3,
        schedule_enabled INTEGER NOT NULL DEFAULT 0,
        schedule_start_minutes INTEGER NOT NULL DEFAULT 0,
        schedule_duration_minutes INTEGER NOT NULL DEFAULT 60,
        weekdays TEXT DEFAULT ''
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS destinations (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'webhook',
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        channel_id TEXT,
        channel_name TEXT,
        credential_profile_id TEXT,
        webhook_id TEXT,
        avatar_url TEXT,
        priority INTEGER NOT NULL DEFAULT 0,
        rate_limit_until INTEGER,
        last_activity_at INTEGER,
        total_sent INTEGER NOT NULL DEFAULT 0,
        total_failed INTEGER NOT NULL DEFAULT 0,
        total_pending INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        note TEXT
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS credential_profiles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'webhook',
        created_at INTEGER NOT NULL,
        bot_user_id TEXT,
        bot_user_name TEXT,
        avatar_url TEXT,
        last_validated_at INTEGER,
        is_valid INTEGER,
        status_message TEXT,
        has_webhook INTEGER NOT NULL DEFAULT 0,
        has_bot_token INTEGER NOT NULL DEFAULT 0
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS distribution_jobs (
        id TEXT PRIMARY KEY,
        file_path TEXT NOT NULL,
        file_name TEXT NOT NULL,
        file_size INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at INTEGER NOT NULL,
        destination_id TEXT NOT NULL,
        destination_name TEXT,
        sha256 TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0,
        priority INTEGER NOT NULL DEFAULT 0,
        error_message TEXT,
        http_code INTEGER,
        discord_code INTEGER,
        message_id TEXT,
        started_at INTEGER,
        completed_at INTEGER,
        bytes_sent INTEGER NOT NULL DEFAULT 0,
        total_bytes INTEGER NOT NULL DEFAULT 0,
        batch_index INTEGER NOT NULL DEFAULT 0,
        caption TEXT,
        heartbeat_at INTEGER
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_jobs_status ON distribution_jobs(status)',
      'CREATE INDEX IF NOT EXISTS idx_jobs_dest ON distribution_jobs(destination_id)',
      'CREATE INDEX IF NOT EXISTS idx_jobs_created ON distribution_jobs(created_at DESC)',
      '''
      CREATE TABLE IF NOT EXISTS delivery_records (
        id TEXT PRIMARY KEY,
        sha256 TEXT NOT NULL,
        destination_id TEXT NOT NULL,
        delivered_at INTEGER NOT NULL,
        file_name TEXT NOT NULL DEFAULT '',
        file_size INTEGER NOT NULL DEFAULT 0,
        file_path TEXT,
        message_id TEXT,
        message_url TEXT,
        job_id TEXT,
        attachment_url TEXT
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_delivery_sha_dest ON delivery_records(sha256, destination_id)',
      'CREATE INDEX IF NOT EXISTS idx_delivery_time ON delivery_records(delivered_at DESC)',
      '''
      CREATE TABLE IF NOT EXISTS upload_history (
        id TEXT PRIMARY KEY,
        file_name TEXT NOT NULL,
        file_path TEXT NOT NULL DEFAULT '',
        file_size INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        completed_at INTEGER,
        sha256 TEXT,
        destination_id TEXT,
        destination_name TEXT,
        mode TEXT,
        target TEXT,
        error_message TEXT,
        http_code INTEGER,
        discord_code INTEGER,
        retry_count INTEGER NOT NULL DEFAULT 0,
        message_id TEXT,
        message_url TEXT,
        session_id TEXT,
        migrated_from TEXT DEFAULT ''
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_history_created ON upload_history(created_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_history_status ON upload_history(status)',
      'CREATE INDEX IF NOT EXISTS idx_history_session ON upload_history(session_id)',
      '''
      CREATE TABLE IF NOT EXISTS analytics_events (
        id TEXT PRIMARY KEY,
        event_type TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        destination_id TEXT,
        file_size INTEGER NOT NULL DEFAULT 0,
        duration_ms INTEGER,
        success INTEGER NOT NULL DEFAULT 1,
        metadata TEXT
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_analytics_created ON analytics_events(created_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_analytics_type ON analytics_events(event_type)',
      '''
      CREATE TABLE IF NOT EXISTS update_history (
        id TEXT PRIMARY KEY,
        version TEXT NOT NULL,
        checked_at INTEGER NOT NULL,
        installed_at INTEGER,
        status TEXT NOT NULL DEFAULT 'available',
        release_url TEXT,
        notes TEXT,
        sha256 TEXT,
        error TEXT
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS file_hashes (
        sha256 TEXT NOT NULL,
        path TEXT NOT NULL,
        size INTEGER NOT NULL DEFAULT 0,
        first_seen_at INTEGER NOT NULL,
        media_id TEXT,
        last_seen_at INTEGER,
        PRIMARY KEY (sha256, path)
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_hashes_sha ON file_hashes(sha256)',
      '''
      CREATE TABLE IF NOT EXISTS duplicate_records (
        id TEXT PRIMARY KEY,
        original_id TEXT NOT NULL,
        duplicate_id TEXT NOT NULL,
        method TEXT NOT NULL DEFAULT 'sha256',
        detected_at INTEGER NOT NULL,
        decision TEXT,
        similarity REAL,
        original_path TEXT,
        duplicate_path TEXT,
        original_name TEXT,
        duplicate_name TEXT
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_duplicates_time ON duplicate_records(detected_at DESC)',
      '''
      CREATE TABLE IF NOT EXISTS duplicate_review_history (
        id TEXT PRIMARY KEY,
        duplicate_id TEXT NOT NULL,
        reviewed_at INTEGER NOT NULL,
        decision TEXT NOT NULL,
        note TEXT
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS archive_records (
        id TEXT PRIMARY KEY,
        media_id TEXT NOT NULL,
        archived_at INTEGER NOT NULL,
        category TEXT NOT NULL DEFAULT 'other',
        file_name TEXT NOT NULL DEFAULT '',
        file_size INTEGER NOT NULL DEFAULT 0,
        restored_at INTEGER,
        original_path TEXT,
        archive_path TEXT,
        destination_id TEXT,
        note TEXT
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_archive_time ON archive_records(archived_at DESC)',
      '''
      CREATE TABLE IF NOT EXISTS archive_rules (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        archive_after_upload INTEGER NOT NULL DEFAULT 0,
        archive_after_days INTEGER,
        categories TEXT DEFAULT '',
        exclude_favorites INTEGER NOT NULL DEFAULT 1,
        exclude_folders TEXT DEFAULT '',
        exclude_pending_review INTEGER NOT NULL DEFAULT 1,
        max_age_days INTEGER
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS archive_operations (
        id TEXT PRIMARY KEY,
        operation TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        item_count INTEGER NOT NULL DEFAULT 0,
        media_id TEXT,
        detail TEXT
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS upload_progress (
        job_id TEXT PRIMARY KEY,
        bytes_sent INTEGER NOT NULL DEFAULT 0,
        total_bytes INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        speed REAL,
        eta_seconds INTEGER
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS live_activity_events (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        message TEXT NOT NULL,
        file_name TEXT,
        destination_id TEXT,
        destination_name TEXT,
        detail TEXT,
        severity TEXT NOT NULL DEFAULT 'info'
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_events_time ON live_activity_events(created_at DESC)',
      '''
      CREATE TABLE IF NOT EXISTS widget_settings (
        id TEXT PRIMARY KEY,
        home_widget_enabled INTEGER NOT NULL DEFAULT 0,
        floating_widget_enabled INTEGER NOT NULL DEFAULT 0,
        floating_x REAL NOT NULL DEFAULT 0,
        floating_y REAL NOT NULL DEFAULT 0,
        show_speed INTEGER NOT NULL DEFAULT 1,
        compact_mode INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
      ''',
      '''
      CREATE TABLE IF NOT EXISTS dashboard_preferences (
        id TEXT PRIMARY KEY,
        range_key TEXT NOT NULL DEFAULT '7d',
        destination_filter TEXT,
        updated_at INTEGER NOT NULL
      )
      ''',
    ];

    for (final String statement in statements) {
      await db.execute(statement);
    }
  }

  /// The columns added by the 2.1.1 release.
  ///
  /// The heartbeat proves that a job is still being worked on. A job whose
  /// heartbeat is stale belongs to a process that died, and its work is
  /// returned to the queue instead of being lost.
  static Future<void> _createV4Tables(Database db) async {
    final List<Map<String, Object?>> columns = await db.rawQuery(
      'PRAGMA table_info(distribution_jobs)',
    );
    final bool hasHeartbeat = columns.any(
      (Map<String, Object?> column) => column['name'] == 'heartbeat_at',
    );
    if (!hasHeartbeat) {
      await db.execute(
        'ALTER TABLE distribution_jobs ADD COLUMN heartbeat_at INTEGER',
      );
    }
  }

  /// Tables added by the 2.1 release.
  ///
  /// The schema is additive: no existing table is altered, so opening a 2.0
  /// database never rewrites or drops a row that is already there.
  static Future<void> _createV3Tables(Database db) async {
    final List<String> statements = <String>[
      '''
      CREATE TABLE IF NOT EXISTS queue_presets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        destination_ids TEXT NOT NULL DEFAULT '[]',
        caption_template TEXT,
        duplicate_policy TEXT NOT NULL DEFAULT 'skip',
        max_size_mb INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
      ''',
      'CREATE INDEX IF NOT EXISTS idx_presets_name ON queue_presets(name)',
      '''
      CREATE TABLE IF NOT EXISTS destination_quiet_hours (
        destination_id TEXT PRIMARY KEY,
        enabled INTEGER NOT NULL DEFAULT 0,
        start_minute INTEGER NOT NULL DEFAULT 0,
        end_minute INTEGER NOT NULL DEFAULT 0,
        strict INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      )
      ''',
    ];

    for (final String statement in statements) {
      await db.execute(statement);
    }
  }

  /// Copies 1.0 `sessions` / `failures` rows into `upload_history`.
  ///
  /// The legacy tables are intentionally left in place so that a downgrade
  /// does not destroy the original records.
  static Future<void> _migrateLegacyData(Database db) async {
    try {
      final List<Map<String, Object?>> sessions = await db.query('sessions');
      for (final Map<String, Object?> row in sessions) {
        final SessionRecord record = SessionRecord.fromMap(row);
        final String id = 'legacy-session-${record.id}';
        final bool exists = await db
            .query(
              'upload_history',
              columns: <String>['id'],
              where: 'id = ?',
              whereArgs: <Object?>[id],
              limit: 1,
            )
            .then((List<Map<String, Object?>> rows) => rows.isNotEmpty);
        if (exists) continue;

        await db.insert('upload_history', <String, Object?>{
          'id': id,
          'file_name': 'Session #${record.id}',
          'file_path': '',
          'file_size': 0,
          'status': record.status,
          'created_at': tsToInt(record.startedAt),
          'completed_at': tsToInt(record.endedAt),
          'destination_id': null,
          'destination_name': record.target,
          'mode': record.mode,
          'target': record.target,
          'error_message': record.reason,
          'retry_count': 0,
          'session_id': record.id.toString(),
          'migrated_from': 'sessions',
        });

        final List<Map<String, Object?>> files = await db.query(
          'session_files',
          where: 'session_id = ?',
          whereArgs: <Object?>[record.id],
        );
        int index = 0;
        for (final Map<String, Object?> fileRow in files) {
          final SessionFileRecord file = SessionFileRecord.fromMap(fileRow);
          await db.insert('upload_history', <String, Object?>{
            'id': 'legacy-file-${record.id}-$index',
            'file_name': file.name,
            'file_path': file.path,
            'file_size': file.size,
            'status': file.status,
            'created_at': tsToInt(record.startedAt),
            'completed_at': tsToInt(record.endedAt),
            'destination_name': record.target,
            'mode': record.mode,
            'target': record.target,
            'error_message': file.error,
            'retry_count': 0,
            'session_id': record.id.toString(),
            'migrated_from': 'session_files',
          });
          index++;
        }
      }

      final List<Map<String, Object?>> failures = await db.query('failures');
      for (final Map<String, Object?> row in failures) {
        final FailureRecord failure = FailureRecord.fromMap(row);
        await db.insert('upload_history', <String, Object?>{
          'id': 'legacy-failure-${failure.id}',
          'file_name': failure.fileName,
          'file_path': failure.filePath,
          'file_size': failure.sizeBytes,
          'status': 'failed',
          'created_at': tsToInt(failure.createdAt),
          'completed_at': tsToInt(failure.createdAt),
          'destination_name': failure.target,
          'mode': failure.mode,
          'target': failure.target,
          'error_message': failure.errorMessage,
          'http_code': failure.httpCode,
          'discord_code': failure.discordCode,
          'retry_count': 0,
          'session_id': failure.sessionId,
          'migrated_from': 'failures',
        });
      }
    } catch (_) {
      // A migration failure must never prevent the app from starting; the
      // legacy tables remain intact and can be re-read by the UI.
    }
  }

  Future<void> close() async {
    final Database? db = _db;
    _db = null;
    if (db != null && db.isOpen) await db.close();
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  Future<String?> getSetting(String key) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String value) async {
    final Database db = await database;
    await db.insert('app_settings', <String, Object?>{
      'key': key,
      'value': value,
      'updated_at': tsToInt(DateTime.now()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>> allSettings() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query('app_settings');
    final Map<String, String> result = <String, String>{};
    for (final Map<String, Object?> row in rows) {
      result[row['key'] as String] = row['value'] as String? ?? '';
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Destinations
  // ---------------------------------------------------------------------------

  Future<List<Destination>> listDestinations() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'destinations',
      orderBy: 'priority ASC, created_at ASC',
    );
    return rows.map(Destination.fromMap).toList();
  }

  Future<void> upsertDestination(Destination destination) async {
    final Database db = await database;
    await db.insert(
      'destinations',
      destination.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteDestination(String id) async {
    final Database db = await database;
    await db.delete('destinations', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  // ---------------------------------------------------------------------------
  // Queue presets (2.1)
  // ---------------------------------------------------------------------------

  /// Every stored preset, ordered by name.
  Future<List<QueuePreset>> listPresets() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'queue_presets',
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(QueuePreset.fromMap).toList();
  }

  /// A single preset by id.
  Future<QueuePreset?> presetById(String id) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'queue_presets',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return QueuePreset.fromMap(rows.first);
  }

  /// Stores a preset, replacing an existing one with the same id.
  Future<void> upsertPreset(QueuePreset preset) async {
    final Database db = await database;
    await db.insert(
      'queue_presets',
      preset.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Removes a preset.
  Future<void> deletePreset(String id) async {
    final Database db = await database;
    await db.delete('queue_presets', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  // ---------------------------------------------------------------------------
  // Quiet hours (2.1)
  // ---------------------------------------------------------------------------

  /// Every quiet hours entry, keyed by destination id.
  Future<List<QuietHours>> listQuietHours() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'destination_quiet_hours',
    );
    return rows.map(QuietHours.fromMap).toList();
  }

  /// The quiet hours of one destination, or `null` when it has none.
  Future<QuietHours?> quietHoursFor(String destinationId) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'destination_quiet_hours',
      where: 'destination_id = ?',
      whereArgs: <Object?>[destinationId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return QuietHours.fromMap(rows.first);
  }

  /// Stores the quiet hours of one destination.
  Future<void> upsertQuietHours(QuietHours hours) async {
    final Database db = await database;
    await db.insert(
      'destination_quiet_hours',
      hours.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Removes the quiet hours of one destination.
  Future<void> deleteQuietHours(String destinationId) async {
    final Database db = await database;
    await db.delete(
      'destination_quiet_hours',
      where: 'destination_id = ?',
      whereArgs: <Object?>[destinationId],
    );
  }

  // ---------------------------------------------------------------------------
  // Credential profiles
  // ---------------------------------------------------------------------------

  Future<List<CredentialProfile>> listCredentialProfiles() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'credential_profiles',
      orderBy: 'created_at ASC',
    );
    return rows.map(CredentialProfile.fromMap).toList();
  }

  Future<void> upsertCredentialProfile(CredentialProfile profile) async {
    final Database db = await database;
    await db.insert(
      'credential_profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteCredentialProfile(String id) async {
    final Database db = await database;
    await db.delete(
      'credential_profiles',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  // ---------------------------------------------------------------------------
  // Media library
  // ---------------------------------------------------------------------------

  Future<List<MediaLibraryEntry>> listMedia({
    String? status,
    String? category,
    String? collectionId,
    bool favoritesOnly = false,
    bool archivedOnly = false,
    bool notArchivedOnly = false,
    String? search,
    int? limit,
    int? offset,
  }) async {
    final Database db = await database;
    final List<String> where = <String>[];
    final List<Object?> args = <Object?>[];
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    if (category != null) {
      where.add('category = ?');
      args.add(category);
    }
    if (collectionId != null) {
      where.add('collection_id = ?');
      args.add(collectionId);
    }
    if (favoritesOnly) where.add('favorite = 1');
    if (archivedOnly) where.add('archived_at IS NOT NULL');
    if (notArchivedOnly) where.add('archived_at IS NULL');
    if (search != null && search.trim().isNotEmpty) {
      where.add('(name LIKE ? OR path LIKE ?)');
      final String pattern = '%${search.trim()}%';
      args.add(pattern);
      args.add(pattern);
    }
    final List<Map<String, Object?>> rows = await db.query(
      'media_library',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'added_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(MediaLibraryEntry.fromMap).toList();
  }

  Future<MediaLibraryEntry?> mediaById(String id) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'media_library',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MediaLibraryEntry.fromMap(rows.first);
  }

  Future<MediaLibraryEntry?> mediaByPath(String path) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'media_library',
      where: 'path = ?',
      whereArgs: <Object?>[path],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MediaLibraryEntry.fromMap(rows.first);
  }

  Future<void> upsertMedia(MediaLibraryEntry entry) async {
    final Database db = await database;
    await db.insert(
      'media_library',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteMedia(String id) async {
    final Database db = await database;
    await db.delete('media_library', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<int> mediaCount({bool archivedOnly = false}) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM media_library${archivedOnly ? ' WHERE archived_at IS NOT NULL' : ''}',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Collections
  // ---------------------------------------------------------------------------

  Future<List<MediaCollection>> listCollections() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'media_collections',
      orderBy: 'created_at ASC',
    );
    return rows.map(MediaCollection.fromMap).toList();
  }

  Future<void> upsertCollection(MediaCollection collection) async {
    final Database db = await database;
    await db.insert(
      'media_collections',
      collection.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteCollection(String id) async {
    final Database db = await database;
    await db.delete(
      'media_collections',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> addToCollection(String collectionId, String mediaId) async {
    final Database db = await database;
    await db.insert('collection_items', <String, Object?>{
      'collection_id': collectionId,
      'media_id': mediaId,
      'added_at': tsToInt(DateTime.now()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await db.update(
      'media_library',
      <String, Object?>{'collection_id': collectionId},
      where: 'id = ?',
      whereArgs: <Object?>[mediaId],
    );
  }

  Future<void> removeFromCollection(String collectionId, String mediaId) async {
    final Database db = await database;
    await db.delete(
      'collection_items',
      where: 'collection_id = ? AND media_id = ?',
      whereArgs: <Object?>[collectionId, mediaId],
    );
    await db.update(
      'media_library',
      <String, Object?>{'collection_id': null},
      where: 'id = ? AND collection_id = ?',
      whereArgs: <Object?>[mediaId, collectionId],
    );
  }

  Future<List<String>> collectionItemIds(String collectionId) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'collection_items',
      columns: <String>['media_id'],
      where: 'collection_id = ?',
      whereArgs: <Object?>[collectionId],
    );
    return rows
        .map((Map<String, Object?> row) => row['media_id'] as String)
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Watched folders and auto upload rules
  // ---------------------------------------------------------------------------

  Future<List<WatchedFolder>> listWatchedFolders() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'watched_folders',
      orderBy: 'created_at ASC',
    );
    return rows.map(WatchedFolder.fromMap).toList();
  }

  Future<void> upsertWatchedFolder(WatchedFolder folder) async {
    final Database db = await database;
    await db.insert(
      'watched_folders',
      folder.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteWatchedFolder(String id) async {
    final Database db = await database;
    await db.delete(
      'watched_folders',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<List<AutoUploadRule>> listAutoUploadRules() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'auto_upload_rules',
      orderBy: 'priority DESC, created_at ASC',
    );
    return rows.map(AutoUploadRule.fromMap).toList();
  }

  Future<void> upsertAutoUploadRule(AutoUploadRule rule) async {
    final Database db = await database;
    await db.insert(
      'auto_upload_rules',
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteAutoUploadRule(String id) async {
    final Database db = await database;
    await db.delete(
      'auto_upload_rules',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  // ---------------------------------------------------------------------------
  // Distribution jobs
  // ---------------------------------------------------------------------------

  /// A single job by id.
  Future<DistributionJob?> jobById(String id) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'distribution_jobs',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DistributionJob.fromMap(rows.first);
  }

  /// Claims a pending job for processing.
  ///
  /// The update only succeeds while the job is still pending, so exactly one
  /// isolate can take a job. The UI isolate and the foreground service isolate
  /// are two separate engines that share this database; without the claim
  /// both of them would send the same file.
  Future<bool> claimJob(String jobId) async {
    final Database db = await database;
    final int changed = await db.update(
      'distribution_jobs',
      <String, Object?>{
        'status': UploadStatus.uploading.key,
        'started_at': tsToInt(DateTime.now()),
        'heartbeat_at': tsToInt(DateTime.now()),
      },
      where: 'id = ? AND status = ?',
      whereArgs: <Object?>[jobId, UploadStatus.pending.key],
    );
    return changed > 0;
  }

  /// Returns jobs that were left in the "uploading" state.
  ///
  /// A process that was killed while it was uploading leaves the row behind.
  /// The work is not lost: the next start picks it up again.
  Future<List<DistributionJob>> listInterruptedJobs() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'distribution_jobs',
      where: 'status = ?',
      whereArgs: <Object?>[UploadStatus.uploading.key],
    );
    return rows.map(DistributionJob.fromMap).toList();
  }

  /// Puts the interrupted jobs back into the queue.
  ///
  /// A job that is still being worked on keeps a fresh heartbeat, so it is
  /// never touched. Only a job whose heartbeat went stale — which means the
  /// process that owned it died — is returned to the queue.
  ///
  /// [recoverAll] is used by the cold start of the app: there the whole
  /// process is new, so no other isolate can own a job.
  Future<int> requeueInterruptedJobs({
    Duration staleAfter = const Duration(seconds: 90),
    bool recoverAll = false,
  }) async {
    final Database db = await database;
    final DateTime threshold = DateTime.now().subtract(staleAfter);
    if (recoverAll) {
      return db.update(
        'distribution_jobs',
        <String, Object?>{'status': UploadStatus.pending.key},
        where: 'status = ?',
        whereArgs: <Object?>[UploadStatus.uploading.key],
      );
    }
    return db.update(
      'distribution_jobs',
      <String, Object?>{'status': UploadStatus.pending.key},
      where: 'status = ? AND (heartbeat_at IS NULL OR heartbeat_at < ?)',
      whereArgs: <Object?>[UploadStatus.uploading.key, tsToInt(threshold)],
    );
  }

  /// Records that a job is still being worked on.
  Future<void> heartbeatJob(String jobId) async {
    final Database db = await database;
    await db.update(
      'distribution_jobs',
      <String, Object?>{'heartbeat_at': tsToInt(DateTime.now())},
      where: 'id = ?',
      whereArgs: <Object?>[jobId],
    );
  }

  /// The number of jobs per status.
  ///
  /// The counts come from the database so that both isolates report the same
  /// truth, even when only one of them is alive.
  Future<Map<String, int>> jobCounts() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT status, COUNT(*) AS total FROM distribution_jobs GROUP BY status',
    );
    final Map<String, int> counts = <String, int>{};
    for (final Map<String, Object?> row in rows) {
      counts[row['status'] as String? ?? ''] = (row['total'] as int?) ?? 0;
    }
    return counts;
  }

  Future<List<DistributionJob>> listJobs({
    String? status,
    String? destinationId,
    int? limit,
  }) async {
    final Database db = await database;
    final List<String> where = <String>[];
    final List<Object?> args = <Object?>[];
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    if (destinationId != null) {
      where.add('destination_id = ?');
      args.add(destinationId);
    }
    final List<Map<String, Object?>> rows = await db.query(
      'distribution_jobs',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'priority DESC, created_at ASC',
      limit: limit,
    );
    return rows.map(DistributionJob.fromMap).toList();
  }

  Future<void> upsertJob(DistributionJob job) async {
    final Database db = await database;
    await db.insert(
      'distribution_jobs',
      job.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteJob(String id) async {
    final Database db = await database;
    await db.delete(
      'distribution_jobs',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> clearJobs({String? status}) async {
    final Database db = await database;
    if (status == null) {
      await db.delete('distribution_jobs');
    } else {
      await db.delete(
        'distribution_jobs',
        where: 'status = ?',
        whereArgs: <Object?>[status],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Delivery records
  // ---------------------------------------------------------------------------

  Future<void> insertDelivery(DeliveryRecord record) async {
    final Database db = await database;
    await db.insert(
      'delivery_records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<DeliveryRecord>> deliveriesForHash(String sha256) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'delivery_records',
      where: 'sha256 = ?',
      whereArgs: <Object?>[sha256],
      orderBy: 'delivered_at DESC',
    );
    return rows.map(DeliveryRecord.fromMap).toList();
  }

  Future<bool> hasDelivery(String sha256, String destinationId) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'delivery_records',
      columns: <String>['id'],
      where: 'sha256 = ? AND destination_id = ?',
      whereArgs: <Object?>[sha256, destinationId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<DeliveryRecord>> listDeliveries({int? limit}) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'delivery_records',
      orderBy: 'delivered_at DESC',
      limit: limit,
    );
    return rows.map(DeliveryRecord.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Hashes and duplicates
  // ---------------------------------------------------------------------------

  Future<void> upsertHash(FileHashRecord record) async {
    final Database db = await database;
    await db.insert(
      'file_hashes',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<FileHashRecord>> hashesForDigest(String sha256) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'file_hashes',
      where: 'sha256 = ?',
      whereArgs: <Object?>[sha256],
      orderBy: 'first_seen_at ASC',
    );
    return rows.map(FileHashRecord.fromMap).toList();
  }

  Future<List<DuplicateRecord>> listDuplicates({
    String? decision,
    int? limit,
  }) async {
    final Database db = await database;
    final List<String> where = <String>[];
    final List<Object?> args = <Object?>[];
    if (decision != null) {
      where.add('decision = ?');
      args.add(decision);
    }
    final List<Map<String, Object?>> rows = await db.query(
      'duplicate_records',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'detected_at DESC',
      limit: limit,
    );
    return rows.map(DuplicateRecord.fromMap).toList();
  }

  Future<void> upsertDuplicate(DuplicateRecord record) async {
    final Database db = await database;
    await db.insert(
      'duplicate_records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteDuplicate(String id) async {
    final Database db = await database;
    await db.delete(
      'duplicate_records',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> insertDuplicateReview({
    required String duplicateId,
    required String decision,
    String? note,
  }) async {
    final Database db = await database;
    await db.insert('duplicate_review_history', <String, Object?>{
      'id': 'review-${DateTime.now().microsecondsSinceEpoch}',
      'duplicate_id': duplicateId,
      'reviewed_at': tsToInt(DateTime.now()),
      'decision': decision,
      'note': note,
    });
  }

  // ---------------------------------------------------------------------------
  // Archive
  // ---------------------------------------------------------------------------

  Future<List<ArchiveRecord>> listArchiveRecords({
    bool restoredOnly = false,
  }) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'archive_records',
      where: restoredOnly ? 'restored_at IS NOT NULL' : null,
      orderBy: 'archived_at DESC',
    );
    return rows.map(ArchiveRecord.fromMap).toList();
  }

  Future<void> upsertArchiveRecord(ArchiveRecord record) async {
    final Database db = await database;
    await db.insert(
      'archive_records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteArchiveRecord(String id) async {
    final Database db = await database;
    await db.delete(
      'archive_records',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<List<ArchiveRule>> listArchiveRules() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'archive_rules',
      orderBy: 'created_at ASC',
    );
    return rows.map(ArchiveRule.fromMap).toList();
  }

  Future<void> upsertArchiveRule(ArchiveRule rule) async {
    final Database db = await database;
    await db.insert(
      'archive_rules',
      rule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteArchiveRule(String id) async {
    final Database db = await database;
    await db.delete('archive_rules', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> insertArchiveOperation({
    required String operation,
    required int itemCount,
    String? mediaId,
    String? detail,
  }) async {
    final Database db = await database;
    await db.insert('archive_operations', <String, Object?>{
      'id': 'op-${DateTime.now().microsecondsSinceEpoch}',
      'operation': operation,
      'created_at': tsToInt(DateTime.now()),
      'item_count': itemCount,
      'media_id': mediaId,
      'detail': detail,
    });
  }

  Future<List<ArchiveOperation>> listArchiveOperations({
    int? limit = 50,
  }) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'archive_operations',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(ArchiveOperation.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------------

  Future<void> insertHistory(UploadHistoryEntry entry) async {
    final Database db = await database;
    await db.insert(
      'upload_history',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<UploadHistoryEntry>> listHistory({
    String? status,
    String? destinationId,
    String? search,
    int? limit,
    int? offset,
  }) async {
    final Database db = await database;
    final List<String> where = <String>[];
    final List<Object?> args = <Object?>[];
    if (status != null) {
      where.add('status = ?');
      args.add(status);
    }
    if (destinationId != null) {
      where.add('destination_id = ?');
      args.add(destinationId);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('file_name LIKE ?');
      args.add('%${search.trim()}%');
    }
    final List<Map<String, Object?>> rows = await db.query(
      'upload_history',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(UploadHistoryEntry.fromMap).toList();
  }

  Future<int> historyCount({String? status}) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM upload_history${status != null ? ' WHERE status = ?' : ''}',
      status != null ? <Object?>[status] : null,
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> clearHistory() async {
    final Database db = await database;
    await db.delete('upload_history');
  }

  // ---------------------------------------------------------------------------
  // Analytics events
  // ---------------------------------------------------------------------------

  Future<void> insertAnalyticsEvent({
    required String eventType,
    String? destinationId,
    int fileSize = 0,
    int? durationMs,
    bool success = true,
    Map<String, dynamic>? metadata,
  }) async {
    final Database db = await database;
    await db.insert('analytics_events', <String, Object?>{
      'id':
          'evt-${DateTime.now().microsecondsSinceEpoch}-${eventType.hashCode}',
      'event_type': eventType,
      'created_at': tsToInt(DateTime.now()),
      'destination_id': destinationId,
      'file_size': fileSize,
      'duration_ms': durationMs,
      'success': success ? 1 : 0,
      'metadata': metadata == null ? null : _encodeMetadata(metadata),
    });
  }

  Future<List<Map<String, Object?>>> analyticsEvents({
    DateTime? since,
    String? eventType,
  }) async {
    final Database db = await database;
    final List<String> where = <String>[];
    final List<Object?> args = <Object?>[];
    if (since != null) {
      where.add('created_at >= ?');
      args.add(tsToInt(since));
    }
    if (eventType != null) {
      where.add('event_type = ?');
      args.add(eventType);
    }
    return db.query(
      'analytics_events',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at ASC',
    );
  }

  // ---------------------------------------------------------------------------
  // Upload progress
  // ---------------------------------------------------------------------------

  Future<void> upsertUploadProgress({
    required String jobId,
    required int bytesSent,
    required int totalBytes,
    double? speed,
    int? etaSeconds,
  }) async {
    final Database db = await database;
    await db.insert('upload_progress', <String, Object?>{
      'job_id': jobId,
      'bytes_sent': bytesSent,
      'total_bytes': totalBytes,
      'updated_at': tsToInt(DateTime.now()),
      'speed': speed,
      'eta_seconds': etaSeconds,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> listUploadProgress() async {
    final Database db = await database;
    return db.query('upload_progress');
  }

  // ---------------------------------------------------------------------------
  // Live activity events
  // ---------------------------------------------------------------------------

  Future<void> insertLiveEvent(LiveActivityEvent event) async {
    final Database db = await database;
    await db.insert(
      'live_activity_events',
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<LiveActivityEvent>> listLiveEvents({int? limit = 200}) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'live_activity_events',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(LiveActivityEvent.fromMap).toList();
  }

  Future<void> clearLiveEvents() async {
    final Database db = await database;
    await db.delete('live_activity_events');
  }

  // ---------------------------------------------------------------------------
  // Update history
  // ---------------------------------------------------------------------------

  Future<void> insertUpdateHistory(UpdateHistoryEntry entry) async {
    final Database db = await database;
    await db.insert(
      'update_history',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<UpdateHistoryEntry>> listUpdateHistory({int? limit = 20}) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'update_history',
      orderBy: 'checked_at DESC',
      limit: limit,
    );
    return rows.map(UpdateHistoryEntry.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Widget settings / dashboard preferences
  // ---------------------------------------------------------------------------

  Future<WidgetSettings> loadWidgetSettings() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'widget_settings',
      where: 'id = ?',
      whereArgs: <Object?>['default'],
      limit: 1,
    );
    if (rows.isEmpty) {
      return WidgetSettings(
        homeWidgetEnabled: false,
        floatingWidgetEnabled: false,
        floatingX: 0,
        floatingY: 0,
        showSpeed: true,
        compactMode: false,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }
    return WidgetSettings.fromMap(rows.first);
  }

  Future<void> saveWidgetSettings(WidgetSettings settings) async {
    final Database db = await database;
    await db.insert(
      'widget_settings',
      settings.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DashboardPreferences> loadDashboardPreferences() async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'dashboard_preferences',
      where: 'id = ?',
      whereArgs: <Object?>['default'],
      limit: 1,
    );
    if (rows.isEmpty) {
      return DashboardPreferences(
        rangeKey: '7d',
        destinationFilter: null,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
    }
    return DashboardPreferences.fromMap(rows.first);
  }

  Future<void> saveDashboardPreferences(
    DashboardPreferences preferences,
  ) async {
    final Database db = await database;
    await db.insert(
      'dashboard_preferences',
      preferences.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static String _encodeMetadata(Map<String, dynamic> metadata) {
    final List<String> parts = metadata.entries
        .map((MapEntry<String, dynamic> e) => '${e.key}=${e.value}')
        .toList();
    return parts.join('&');
  }
}
