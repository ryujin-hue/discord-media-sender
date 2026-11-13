import 'dart:io';

import 'package:discord_media_sender/core/constants.dart';
import 'package:discord_media_sender/data/database.dart';
import 'package:discord_media_sender/data/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Creates a database that behaves like the 1.0 schema so that the migration
/// path can be exercised.
Future<Database> createLegacyDatabase(String path) async {
  final Database db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
        CREATE TABLE sessions (
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
        CREATE TABLE session_files (
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
        CREATE TABLE failures (
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
      },
    ),
  );
  return db;
}

void main() {
  sqfliteFfiInit();

  late Directory tempDir;
  late String dbPath;

  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dms_db_test');
    dbPath = '${tempDir.path}/test.db';
    AppDatabase.pathOverride = dbPath;
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('Schema', () {
    test('adds the heartbeat column to an existing 2.1 database', () async {
      // A database that was created by the 2.1.0 build has no heartbeat
      // column. Opening it with 2.1.1 adds the column without touching a
      // single row.
      final String path = '${tempDir.path}/upgrade.db';
      final Database legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (Database db, int version) async {
            await db.execute('''
              CREATE TABLE distribution_jobs (
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
                message_id INTEGER,
                started_at INTEGER,
                completed_at INTEGER,
                bytes_sent INTEGER NOT NULL DEFAULT 0,
                total_bytes INTEGER NOT NULL DEFAULT 0,
                batch_index INTEGER NOT NULL DEFAULT 0,
                caption TEXT
              )
            ''');
            await db.insert('distribution_jobs', <String, Object?>{
              'id': 'job-keep',
              'file_path': '/tmp/keep.jpg',
              'file_name': 'keep.jpg',
              'file_size': 10,
              'status': 'pending',
              'created_at': 1700000000000,
              'destination_id': 'dest-a',
            });
          },
        ),
      );
      await legacy.close();

      AppDatabase.pathOverride = path;
      final AppDatabase database = AppDatabase.instance;
      final Database db = await database.database;

      final List<Map<String, Object?>> columns = await db.rawQuery(
        'PRAGMA table_info(distribution_jobs)',
      );
      expect(
        columns.any((Map<String, Object?> c) => c['name'] == 'heartbeat_at'),
        isTrue,
      );

      final List<Map<String, Object?>> rows = await db.query(
        'distribution_jobs',
      );
      expect(rows.length, 1);
      expect(
        rows.first['file_name'],
        'keep.jpg',
        reason: 'the existing row survives the upgrade',
      );
    });

    test('creates every 2.0 table on a fresh install', () async {
      final AppDatabase database = AppDatabase.instance;
      final Database db = await database.database;

      final List<String> expected = <String>[
        'sessions',
        'session_files',
        'failures',
        'app_settings',
        'media_library',
        'media_collections',
        'collection_items',
        'watched_folders',
        'auto_upload_rules',
        'destinations',
        'credential_profiles',
        'distribution_jobs',
        'delivery_records',
        'upload_history',
        'analytics_events',
        'update_history',
        'file_hashes',
        'duplicate_records',
        'duplicate_review_history',
        'archive_records',
        'archive_rules',
        'archive_operations',
        'upload_progress',
        'live_activity_events',
        'widget_settings',
        'dashboard_preferences',
      ];

      final List<Map<String, Object?>> tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final Set<String> names = tables
          .map((Map<String, Object?> row) => row['name'] as String)
          .toSet();

      for (final String table in expected) {
        expect(names, contains(table), reason: 'missing table $table');
      }
    });

    test('migrates 1.0 session data into the 2.0 history', () async {
      final Database legacy = await createLegacyDatabase(dbPath);
      await legacy.insert('sessions', <String, Object?>{
        'id': 7,
        'started_at': 1700000000000,
        'ended_at': 1700000060000,
        'mode': 'webhook',
        'target': 'my-webhook',
        'total_files': 2,
        'success': 1,
        'failed': 1,
        'status': 'completed',
        'reason': 'one failure',
      });
      await legacy.insert('session_files', <String, Object?>{
        'session_id': 7,
        'idx': 0,
        'path': '/storage/a.jpg',
        'name': 'a.jpg',
        'size': 1024,
        'status': 'sent',
      });
      await legacy.insert('failures', <String, Object?>{
        'session_id': 7,
        'file_name': 'b.mp4',
        'file_path': '/storage/b.mp4',
        'size_bytes': 2048,
        'batch_index': 1,
        'http_code': 400,
        'discord_code': 50013,
        'error_message': 'Missing permissions',
        'mode': 'webhook',
        'target': 'my-webhook',
        'created_at': 1700000030000,
      });
      await legacy.close();

      // Open with the 2.0 service, which performs the migration.
      final AppDatabase database = AppDatabase.instance;
      final Database db = await database.database;

      // The legacy tables are preserved.
      final List<Map<String, Object?>> sessions = await db.query('sessions');
      expect(sessions.length, 1);

      // The rows are copied into the unified history.
      final List<UploadHistoryEntry> history = await database.listHistory();
      expect(history, isNotEmpty);

      final UploadHistoryEntry migratedSession = history.firstWhere(
        (UploadHistoryEntry e) => e.migratedFrom == 'sessions',
      );
      expect(migratedSession.sessionId, '7');
      expect(migratedSession.destinationName, 'my-webhook');

      final UploadHistoryEntry migratedFile = history.firstWhere(
        (UploadHistoryEntry e) => e.migratedFrom == 'session_files',
      );
      expect(migratedFile.fileName, 'a.jpg');
      expect(migratedFile.fileSize, 1024);

      final UploadHistoryEntry migratedFailure = history.firstWhere(
        (UploadHistoryEntry e) => e.migratedFrom == 'failures',
      );
      expect(migratedFailure.fileName, 'b.mp4');
      expect(migratedFailure.status, 'failed');
      expect(migratedFailure.errorMessage, 'Missing permissions');
      expect(migratedFailure.httpCode, 400);
      expect(migratedFailure.discordCode, 50013);
    });
  });

  group('Destination scoped delivery records', () {
    test('a file delivered to one destination is new for another', () async {
      final AppDatabase database = AppDatabase.instance;
      final Database db = await database.database;

      await database.insertDelivery(
        DeliveryRecord(
          id: 'delivery-1',
          sha256: 'abc123',
          destinationId: 'dest-a',
          deliveredAt: DateTime.now(),
          fileName: 'a.jpg',
          fileSize: 100,
        ),
      );

      expect(await database.hasDelivery('abc123', 'dest-a'), isTrue);
      expect(await database.hasDelivery('abc123', 'dest-b'), isFalse);

      final List<DeliveryRecord> forHash = await database.deliveriesForHash(
        'abc123',
      );
      expect(forHash.length, 1);
      expect(forHash.first.destinationId, 'dest-a');

      // The delivery history is independent per destination.
      await database.insertDelivery(
        DeliveryRecord(
          id: 'delivery-2',
          sha256: 'abc123',
          destinationId: 'dest-b',
          deliveredAt: DateTime.now(),
          fileName: 'a.jpg',
          fileSize: 100,
        ),
      );
      expect((await database.deliveriesForHash('abc123')).length, 2);

      await db.close();
    });
  });

  group('Media library', () {
    test('stores, updates and filters library entries', () async {
      final AppDatabase database = AppDatabase.instance;
      await database.database;

      final MediaLibraryEntry entry = MediaLibraryEntry(
        id: 'media-1',
        path: '/storage/DCIM/photo.jpg',
        name: 'photo.jpg',
        size: 2048,
        addedAt: DateTime.now(),
        status: MediaStatus.newFile.key,
        mimeType: 'image/jpeg',
        category: 'image',
        sha256: 'hash-1',
      );
      await database.upsertMedia(entry);

      final MediaLibraryEntry? stored = await database.mediaById('media-1');
      expect(stored, isNotNull);
      expect(stored!.sha256, 'hash-1');
      expect(stored.favorite, isFalse);

      await database.upsertMedia(stored.copyWith(favorite: true));
      expect((await database.mediaById('media-1'))!.favorite, isTrue);

      final List<MediaLibraryEntry> images = await database.listMedia(
        category: 'image',
      );
      expect(images.length, 1);

      final List<MediaLibraryEntry> favourites = await database.listMedia(
        favoritesOnly: true,
      );
      expect(favourites.length, 1);

      await database.deleteMedia('media-1');
      expect(await database.mediaById('media-1'), isNull);
    });

    test('archives an entry without deleting the original row', () async {
      final AppDatabase database = AppDatabase.instance;
      await database.database;

      final MediaLibraryEntry entry = MediaLibraryEntry(
        id: 'media-2',
        path: '/storage/movies/clip.mp4',
        name: 'clip.mp4',
        size: 4096,
        addedAt: DateTime.now(),
        status: MediaStatus.uploaded.key,
        category: 'video',
      );
      await database.upsertMedia(entry);

      await database.upsertMedia(
        entry.copyWith(
          status: MediaStatus.archived.key,
          archivedAt: DateTime.now(),
        ),
      );

      final List<MediaLibraryEntry> archived = await database.listMedia(
        archivedOnly: true,
      );
      expect(archived.length, 1);
      expect(archived.first.name, 'clip.mp4');
      // The original record is still there — archiving never deletes media.
      expect(await database.mediaById('media-2'), isNotNull);
    });
  });

  group('Upload history', () {
    test('records successes and failures separately', () async {
      final AppDatabase database = AppDatabase.instance;
      await database.database;

      await database.insertHistory(
        UploadHistoryEntry(
          id: 'h1',
          fileName: 'ok.jpg',
          filePath: '/ok.jpg',
          fileSize: 10,
          status: UploadStatus.completed.key,
          createdAt: DateTime.now(),
        ),
      );
      await database.insertHistory(
        UploadHistoryEntry(
          id: 'h2',
          fileName: 'bad.jpg',
          filePath: '/bad.jpg',
          fileSize: 10,
          status: UploadStatus.failed.key,
          createdAt: DateTime.now(),
          errorMessage: 'nope',
        ),
      );

      expect(await database.historyCount(status: 'completed'), 1);
      expect(await database.historyCount(status: 'failed'), 1);
      expect(await database.historyCount(), 2);
    });
  });
}
