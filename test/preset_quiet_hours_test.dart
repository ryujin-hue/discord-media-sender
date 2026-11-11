import 'dart:io';

import 'package:discord_media_sender/core/constants.dart';
import 'package:discord_media_sender/data/database.dart';
import 'package:discord_media_sender/data/models.dart';
import 'package:discord_media_sender/services/preset_service.dart';
import 'package:discord_media_sender/services/quiet_hours_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dms_preset_test');
    AppDatabase.pathOverride = '${tempDir.path}/preset.db';
    await AppDatabase.instance.database;
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<Destination> addDestination(String id, String name) async {
    final Destination destination = Destination(
      id: id,
      name: name,
      type: 'webhook',
      enabled: true,
      createdAt: DateTime.now(),
      webhookId: 'https://discord.com/api/webhooks/1/$id',
    );
    await AppDatabase.instance.upsertDestination(destination);
    return destination;
  }

  group('Queue presets', () {
    test('stores and lists a preset', () async {
      await addDestination('dest-a', 'Alpha');
      final QueuePreset preset = await PresetService.instance.create(
        name: 'Album',
        destinationIds: <String>['dest-a'],
        captionTemplate: '{name} · {size} MB',
        duplicatePolicy: DuplicatePolicy.keepBoth,
        maxSizeMb: 250,
      );

      final List<QueuePreset> presets = await PresetService.instance.list();
      expect(presets.length, 1);
      expect(presets.first.name, 'Album');
      expect(presets.first.destinationIds, <String>['dest-a']);
      expect(presets.first.duplicatePolicy, DuplicatePolicy.keepBoth);
      expect(presets.first.maxSizeMb, 250);
      expect(preset.id, isNotEmpty);
    });

    test('resolves the destinations of a preset', () async {
      await addDestination('dest-a', 'Alpha');
      await addDestination('dest-b', 'Beta');
      final QueuePreset preset = await PresetService.instance.create(
        name: 'Both',
        destinationIds: <String>['dest-a', 'dest-b'],
      );

      final PresetApplication application = await PresetService.instance
          .resolve(preset);
      expect(application.isValid, isTrue);
      expect(application.destinations.length, 2);
      expect(application.missingDestinationIds, isEmpty);
    });

    test(
      'reports a preset as invalid when a destination was deleted',
      () async {
        await addDestination('dest-a', 'Alpha');
        final QueuePreset preset = await PresetService.instance.create(
          name: 'Broken',
          destinationIds: <String>['dest-a', 'dest-gone'],
        );

        await AppDatabase.instance.deleteDestination('dest-gone');

        final PresetApplication application = await PresetService.instance
            .resolve(preset);
        expect(application.isValid, isFalse);
        expect(application.missingDestinationIds, <String>['dest-gone']);
        expect(application.destinations.length, 1);

        final List<InvalidPreset> invalid = await PresetService.instance
            .listInvalid();
        expect(invalid.length, 1);
        expect(invalid.first.preset.name, 'Broken');
      },
    );

    test('renders the caption template', () async {
      final QueuePreset preset = QueuePreset(
        id: 'p',
        name: 'Caption',
        captionTemplate: '{name} · {size} MB · #{index}',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(
        preset.renderCaption(
          fileName: 'holiday.jpg',
          sizeBytes: 5242880,
          index: 3,
        ),
        'holiday · 5 MB · #3',
      );
    });

    test('deletes a preset', () async {
      final QueuePreset preset = await PresetService.instance.create(
        name: 'Temp',
        destinationIds: const <String>[],
      );
      expect(await PresetService.instance.list(), hasLength(1));
      await PresetService.instance.delete(preset.id);
      expect(await PresetService.instance.list(), isEmpty);
    });
  });

  group('Quiet hours', () {
    test('detects a window inside the day', () {
      final QuietHours hours = QuietHours(
        destinationId: 'dest-a',
        enabled: true,
        startMinute: 9 * 60,
        endMinute: 17 * 60,
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(hours.contains(DateTime(2026, 1, 1, 12)), isTrue);
      expect(hours.contains(DateTime(2026, 1, 1, 8)), isFalse);
      expect(hours.contains(DateTime(2026, 1, 1, 18)), isFalse);
    });

    test('detects a window that wraps around midnight', () {
      final QuietHours hours = QuietHours(
        destinationId: 'dest-a',
        enabled: true,
        startMinute: 23 * 60,
        endMinute: 7 * 60,
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(hours.contains(DateTime(2026, 1, 1, 2)), isTrue);
      expect(hours.contains(DateTime(2026, 1, 1, 23, 30)), isTrue);
      expect(hours.contains(DateTime(2026, 1, 1, 12)), isFalse);
    });

    test('a disabled window never matches', () {
      final QuietHours hours = QuietHours(
        destinationId: 'dest-a',
        enabled: false,
        startMinute: 0,
        endMinute: 1439,
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(hours.contains(DateTime(2026, 1, 1, 12)), isFalse);
    });

    test('stores and reads the quiet hours of a destination', () async {
      await QuietHoursService.instance.save(
        QuietHours(
          destinationId: 'dest-a',
          enabled: true,
          startMinute: 60,
          endMinute: 120,
          strict: true,
          updatedAt: DateTime.now(),
        ),
      );

      final QuietHours? stored = await QuietHoursService.instance
          .forDestination('dest-a');
      expect(stored, isNotNull);
      expect(stored!.enabled, isTrue);
      expect(stored.startMinute, 60);
      expect(stored.endMinute, 120);
      expect(stored.strict, isTrue);
      expect(stored.label, '01:00 – 02:00');
    });

    test(
      'the automatic upload skips a destination inside its window',
      () async {
        await QuietHoursService.instance.save(
          QuietHours(
            destinationId: 'dest-a',
            enabled: true,
            startMinute: 0,
            endMinute: 1439,
            updatedAt: DateTime.now(),
          ),
        );

        final String? reason = await QuietHoursService.instance.skipReason(
          'dest-a',
          now: DateTime(2026, 1, 1, 12),
        );
        expect(reason, 'quiet_hours');

        final List<String> skipped = await QuietHoursService.instance
            .destinationsInQuietHours(now: DateTime(2026, 1, 1, 12));
        expect(skipped, <String>['dest-a']);
      },
    );

    test('a manual upload is only blocked by a strict window', () async {
      await QuietHoursService.instance.save(
        QuietHours(
          destinationId: 'dest-lenient',
          enabled: true,
          startMinute: 0,
          endMinute: 1439,
          updatedAt: DateTime.now(),
        ),
      );
      await QuietHoursService.instance.save(
        QuietHours(
          destinationId: 'dest-strict',
          enabled: true,
          startMinute: 0,
          endMinute: 1439,
          strict: true,
          updatedAt: DateTime.now(),
        ),
      );

      final DateTime now = DateTime(2026, 1, 1, 12);
      expect(
        await QuietHoursService.instance.skipReason(
          'dest-lenient',
          now: now,
          manual: true,
        ),
        isNull,
      );
      expect(
        await QuietHoursService.instance.skipReason(
          'dest-strict',
          now: now,
          manual: true,
        ),
        'quiet_hours',
      );
    });
  });
}
