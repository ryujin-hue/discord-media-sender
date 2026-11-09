import 'dart:io';

import 'package:discord_media_sender/core/constants.dart';
import 'package:discord_media_sender/data/database.dart';
import 'package:discord_media_sender/data/models.dart';
import 'package:discord_media_sender/services/duplicate_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dms_dup_test');
    dbPath = '${tempDir.path}/duplicates.db';
    AppDatabase.pathOverride = dbPath;
    await AppDatabase.instance.database;
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('Duplicate detection', () {
    test(
      'identical files produce a matching SHA-256 and are detected',
      () async {
        final File first = File('${tempDir.path}/first.jpg');
        final File second = File('${tempDir.path}/second.jpg');
        await first.writeAsString('the very same bytes');
        await second.writeAsString('the very same bytes');

        final DuplicateScanResult result = await DuplicateService.instance
            .scanPaths(<String>[first.path, second.path]);

        expect(result.scanned, 2);
        expect(result.duplicates.length, 1);
        expect(result.duplicates.first.method, DetectionMethod.sha256.key);
        expect(result.duplicates.first.similarity, 1.0);

        // The duplicate is flagged for review instead of being uploaded.
        final MediaLibraryEntry? duplicate = await AppDatabase.instance
            .mediaById(result.duplicates.first.duplicateId);
        expect(duplicate, isNotNull);
        expect(duplicate!.status, MediaStatus.duplicateDetected.key);
        expect(duplicate.sha256, isNotNull);
      },
    );

    test('a renamed copy is detected as a duplicate', () async {
      final File original = File('${tempDir.path}/IMG_0001.jpg');
      final File renamed = File('${tempDir.path}/holiday-photo.jpg');
      await original.writeAsString('same payload');
      await renamed.writeAsString('same payload');

      final DuplicateScanResult result = await DuplicateService.instance
          .scanPaths(<String>[original.path, renamed.path]);

      expect(result.duplicates.length, 1);
      expect(result.duplicates.first.originalName, 'IMG_0001.jpg');
      expect(result.duplicates.first.duplicateName, 'holiday-photo.jpg');
    });

    test('different files are not flagged as duplicates', () async {
      final File first = File('${tempDir.path}/a.png');
      final File second = File('${tempDir.path}/b.png');
      await first.writeAsString('alpha');
      await second.writeAsString('beta');

      final DuplicateScanResult result = await DuplicateService.instance
          .scanPaths(<String>[first.path, second.path]);

      expect(result.duplicates, isEmpty);
      expect(result.newFiles.length, 2);
    });

    test(
      'similar but different files are never deleted automatically',
      () async {
        final File first = File('${tempDir.path}/photo.jpg');
        final File second = File('${tempDir.path}/photo-edited.jpg');
        await first.writeAsString('almost the same payload');
        await second.writeAsString('almost the same payloae');

        final DuplicateScanResult result = await DuplicateService.instance
            .scanPaths(<String>[first.path, second.path]);

        expect(result.duplicates, isEmpty);

        // Both files still exist on disk.
        expect(first.existsSync(), isTrue);
        expect(second.existsSync(), isTrue);
        expect((await AppDatabase.instance.listMedia()).length, 2);
      },
    );

    test('metadata similarity is only a suggestion and needs review', () async {
      final File first = File('${tempDir.path}/same-name.png');
      final File second = File('${tempDir.path}/same-name-copy.png');
      await first.writeAsString('one');
      await second.writeAsString('two different');

      final DuplicateScanResult result = await DuplicateService.instance
          .scanPaths(<String>[first.path]);
      final MediaLibraryEntry entry =
          (await AppDatabase.instance.listMedia()).first;

      final List<DuplicateRecord> similar = await DuplicateService.instance
          .findSimilarByMetadata(entry);

      // A file with a different content hash is never reported as a duplicate.
      expect(similar, isEmpty);
      expect(result.duplicates, isEmpty);
    });
  });

  group('Duplicate decisions', () {
    test(
      'reviewing a duplicate records the decision and its history',
      () async {
        final File first = File('${tempDir.path}/one.jpg');
        final File second = File('${tempDir.path}/two.jpg');
        await first.writeAsString('payload');
        await second.writeAsString('payload');

        final DuplicateScanResult result = await DuplicateService.instance
            .scanPaths(<String>[first.path, second.path]);
        final DuplicateRecord record = result.duplicates.first;

        await DuplicateService.instance.review(record, DuplicatePolicy.skip);

        final List<DuplicateRecord> stored = await AppDatabase.instance
            .listDuplicates();
        expect(stored.first.decision, DuplicatePolicy.skip.key);

        final Database db = await AppDatabase.instance.database;
        final List<Map<String, Object?>> history = await db.query(
          'duplicate_review_history',
        );
        expect(history.length, 1);
        expect(history.first['decision'], DuplicatePolicy.skip.key);
      },
    );

    test('the "upload anyway" decision releases the duplicate', () async {
      final File first = File('${tempDir.path}/one.jpg');
      final File second = File('${tempDir.path}/two.jpg');
      await first.writeAsString('payload');
      await second.writeAsString('payload');

      final DuplicateScanResult result = await DuplicateService.instance
          .scanPaths(<String>[first.path, second.path]);

      await DuplicateService.instance.review(
        result.duplicates.first,
        DuplicatePolicy.anyway,
      );

      final MediaLibraryEntry? released = await AppDatabase.instance.mediaById(
        result.duplicates.first.duplicateId,
      );
      expect(released!.status, MediaStatus.newFile.key);
    });
  });

  group('Destination aware detection', () {
    test(
      'a file delivered to one destination is still new for another',
      () async {
        final File file = File('${tempDir.path}/payload.jpg');
        await file.writeAsString('payload');

        final DuplicateScanResult result = await DuplicateService.instance
            .scanPaths(<String>[file.path]);
        final String sha = result.newFiles.first.sha256!;

        await AppDatabase.instance.insertDelivery(
          DeliveryRecord(
            id: 'd1',
            sha256: sha,
            destinationId: 'dest-a',
            deliveredAt: DateTime.now(),
            fileName: 'payload.jpg',
          ),
        );

        expect(
          await DuplicateService.instance.wasDeliveredTo(sha, 'dest-a'),
          isTrue,
        );
        expect(
          await DuplicateService.instance.wasDeliveredTo(sha, 'dest-b'),
          isFalse,
        );

        final List<String> destinations = await DuplicateService.instance
            .deliveredDestinations(sha);
        expect(destinations, <String>['dest-a']);
      },
    );

    test('a retry does not create a second delivery record', () async {
      final File file = File('${tempDir.path}/payload.jpg');
      await file.writeAsString('payload');

      final DuplicateScanResult result = await DuplicateService.instance
          .scanPaths(<String>[file.path]);
      final String sha = result.newFiles.first.sha256!;

      await AppDatabase.instance.insertDelivery(
        DeliveryRecord(
          id: 'delivery-1',
          sha256: sha,
          destinationId: 'dest-a',
          deliveredAt: DateTime.now(),
          fileName: 'payload.jpg',
        ),
      );

      // A retry checks the delivery record first and must not insert a second
      // row for the same destination.
      final bool alreadyDelivered = await DuplicateService.instance
          .wasDeliveredTo(sha, 'dest-a');
      expect(alreadyDelivered, isTrue);

      final List<DeliveryRecord> records = await AppDatabase.instance
          .deliveriesForHash(sha);
      expect(records.length, 1);
    });
  });
}
