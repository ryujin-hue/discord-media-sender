import 'dart:io';

import 'package:discord_media_sender/core/constants.dart';
import 'package:discord_media_sender/data/database.dart';
import 'package:discord_media_sender/data/models.dart';
import 'package:discord_media_sender/services/discord_api.dart';
import 'package:discord_media_sender/services/media_service.dart';
import 'package:discord_media_sender/services/upload_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A Discord client that records the calls instead of sending them.
class _FakeDiscordApi extends DiscordApiClient {
  _FakeDiscordApi(this.result);

  final DiscordSendResult result;
  final List<String> sentFiles = <String>[];
  final List<int?> receivedBandwidthCaps = <int?>[];
  int callCount = 0;

  @override
  Future<DiscordSendResult> sendWebhook(
    String webhookUrl, {
    required List<File> files,
    String? content,
    String? username,
    String? avatarUrl,
    void Function(int sent, int total)? onProgress,
    int? bandwidthBytesPerSecond,
  }) async {
    callCount++;
    receivedBandwidthCaps.add(bandwidthBytesPerSecond);
    for (final File file in files) {
      sentFiles.add(file.path);
      onProgress?.call(file.lengthSync(), file.lengthSync());
    }
    return result;
  }

  @override
  Future<DiscordSendResult> sendBotMessage(
    String token,
    String channelId, {
    required List<File> files,
    String? content,
    void Function(int sent, int total)? onProgress,
    int? bandwidthBytesPerSecond,
  }) async {
    callCount++;
    receivedBandwidthCaps.add(bandwidthBytesPerSecond);
    for (final File file in files) {
      sentFiles.add(file.path);
      onProgress?.call(file.lengthSync(), file.lengthSync());
    }
    return result;
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late Destination destination;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dms_engine_test');
    AppDatabase.pathOverride = '${tempDir.path}/engine.db';
    await AppDatabase.instance.database;

    destination = Destination(
      id: 'dest-test',
      name: 'Test webhook',
      type: 'webhook',
      enabled: true,
      createdAt: DateTime.now(),
      webhookId:
          'https://discord.com/api/webhooks/123456789012345678/testtoken',
    );
    await AppDatabase.instance.upsertDestination(destination);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    AppDatabase.pathOverride = null;
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<File> createFile(String name, String content) async {
    final File file = File('${tempDir.path}/$name');
    await file.writeAsString(content);
    return file;
  }

  group('Upload engine', () {
    test(
      'uploads a file, records the delivery and writes the history',
      () async {
        final File file = await createFile('photo.jpg', 'image bytes');
        final _FakeDiscordApi api = _FakeDiscordApi(
          const DiscordSendResult(
            success: true,
            messageId: 'message-1',
            messageUrl: 'https://discord.com/channels/1/2/message-1',
          ),
        );
        final UploadEngine engine = UploadEngine.createForTesting(
          apiClient: api,
        );

        await engine.enqueue(
          <MediaCandidate>[MediaService.instance.describe(file.path)],
          options: EnqueueOptions(
            destinations: <Destination>[destination],
            autoStart: false,
          ),
        );
        await engine.run();

        expect(api.callCount, 1, reason: 'the file is sent exactly once');

        final List<DistributionJob> jobs = await AppDatabase.instance
            .listJobs();
        expect(jobs.length, 1);
        expect(jobs.first.status, UploadStatus.completedKey);

        final List<DeliveryRecord> deliveries = await AppDatabase.instance
            .deliveriesForHash(jobs.first.sha256!);
        expect(deliveries.length, 1);
        expect(deliveries.first.destinationId, 'dest-test');
        expect(deliveries.first.messageId, 'message-1');

        final List<UploadHistoryEntry> history = await AppDatabase.instance
            .listHistory();
        expect(history.length, 1);
        expect(history.first.status, UploadStatus.completedKey);
        expect(history.first.destinationId, 'dest-test');
      },
    );

    test(
      'records a failure and retries without duplicating the delivery',
      () async {
        final File file = await createFile('clip.mp4', 'video bytes');
        final _FakeDiscordApi api = _FakeDiscordApi(
          const DiscordSendResult(
            success: false,
            errorMessage: 'Missing permission for this channel',
            httpCode: 403,
            discordCode: 50013,
          ),
        );
        final UploadEngine engine = UploadEngine.createForTesting(
          apiClient: api,
        );

        await engine.enqueue(
          <MediaCandidate>[MediaService.instance.describe(file.path)],
          options: EnqueueOptions(
            destinations: <Destination>[destination],
            autoStart: false,
          ),
        );
        await engine.run();

        final List<DistributionJob> jobs = await AppDatabase.instance
            .listJobs();
        expect(jobs.length, 1);
        expect(jobs.first.status, UploadStatus.failedKey);
        expect(jobs.first.errorMessage, contains('Missing permission'));
        expect(jobs.first.httpCode, 403);
        expect(jobs.first.retryCount, 1);

        final List<UploadHistoryEntry> history = await AppDatabase.instance
            .listHistory();
        expect(
          history.any(
            (UploadHistoryEntry e) => e.status == UploadStatus.failedKey,
          ),
          isTrue,
        );

        // Nothing was delivered, so there is no delivery record yet.
        final List<DeliveryRecord> deliveries = await AppDatabase.instance
            .listDeliveries();
        expect(deliveries, isEmpty);

        // Now let the retry succeed.
        final _FakeDiscordApi succeeding = _FakeDiscordApi(
          const DiscordSendResult(success: true, messageId: 'message-2'),
        );
        final UploadEngine retryEngine = UploadEngine.createForTesting(
          apiClient: succeeding,
        );
        final List<DistributionJob> failed = await AppDatabase.instance
            .listJobs(status: UploadStatus.failedKey);
        expect(failed.length, 1);

        // The retry is issued by a fresh engine, exactly like a retry from the
        // history screen after the app was restarted.
        await retryEngine.restore();
        await retryEngine.retryJob(failed.first.id);
        await retryEngine.run();

        expect(succeeding.callCount, 1);
        final List<DeliveryRecord> afterRetry = await AppDatabase.instance
            .listDeliveries();
        expect(
          afterRetry.length,
          1,
          reason: 'a retry creates exactly one delivery record',
        );
      },
    );

    test(
      'skips a file that was already delivered to the destination',
      () async {
        final File file = await createFile('dup.jpg', 'duplicate bytes');
        final _FakeDiscordApi api = _FakeDiscordApi(
          const DiscordSendResult(success: true, messageId: 'message-3'),
        );
        final UploadEngine engine = UploadEngine.createForTesting(
          apiClient: api,
        );

        await engine.enqueue(
          <MediaCandidate>[MediaService.instance.describe(file.path)],
          options: EnqueueOptions(
            destinations: <Destination>[destination],
            autoStart: false,
          ),
        );
        await engine.run();
        expect(api.callCount, 1);

        // A second attempt with the "skip" policy must not send the file again.
        final List<String> skipped = await engine.enqueue(
          <MediaCandidate>[MediaService.instance.describe(file.path)],
          options: EnqueueOptions(
            destinations: <Destination>[destination],
            duplicatePolicy: DuplicatePolicy.skip,
            autoStart: false,
          ),
        );

        expect(skipped, isNotEmpty);
        expect(api.callCount, 1, reason: 'the duplicate was not sent again');

        final List<DeliveryRecord> deliveries = await AppDatabase.instance
            .listDeliveries();
        expect(deliveries.length, 1);
      },
    );

    test(
      'sends to a second destination when the first already has it',
      () async {
        final File file = await createFile('shared.jpg', 'shared bytes');
        final Destination second = Destination(
          id: 'dest-second',
          name: 'Second webhook',
          type: 'webhook',
          enabled: true,
          createdAt: DateTime.now(),
          webhookId:
              'https://discord.com/api/webhooks/987654321098765432/othertoken',
        );
        await AppDatabase.instance.upsertDestination(second);

        final _FakeDiscordApi api = _FakeDiscordApi(
          const DiscordSendResult(success: true, messageId: 'message-4'),
        );
        final UploadEngine engine = UploadEngine.createForTesting(
          apiClient: api,
        );

        await engine.enqueue(
          <MediaCandidate>[MediaService.instance.describe(file.path)],
          options: EnqueueOptions(
            destinations: <Destination>[destination],
            duplicatePolicy: DuplicatePolicy.skip,
            autoStart: false,
          ),
        );
        await engine.run();

        await engine.enqueue(
          <MediaCandidate>[MediaService.instance.describe(file.path)],
          options: EnqueueOptions(
            destinations: <Destination>[second],
            duplicatePolicy: DuplicatePolicy.skip,
            autoStart: false,
          ),
        );
        await engine.run();

        expect(
          api.callCount,
          2,
          reason: 'a different destination is still a new delivery',
        );

        final List<DeliveryRecord> deliveries = await AppDatabase.instance
            .listDeliveries();
        expect(deliveries.length, 2);
        expect(
          deliveries.map((DeliveryRecord d) => d.destinationId).toSet(),
          <String>{'dest-test', 'dest-second'},
        );
      },
    );

    test('passes the bandwidth cap to the API client', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppConstants.prefBandwidthCapKb: 512,
      });
      final File file = await createFile('capped.bin', 'capped bytes');
      final _FakeDiscordApi api = _FakeDiscordApi(
        const DiscordSendResult(success: true, messageId: 'message-6'),
      );
      final UploadEngine engine = UploadEngine.createForTesting(apiClient: api);

      await engine.enqueue(
        <MediaCandidate>[MediaService.instance.describe(file.path)],
        options: EnqueueOptions(
          destinations: <Destination>[destination],
          autoStart: false,
        ),
      );
      await engine.run();

      expect(api.receivedBandwidthCaps, hasLength(1));
      expect(api.receivedBandwidthCaps.first, 512 * 1024);
    });

    test('runs without a bandwidth cap when none is configured', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final File file = await createFile('free.bin', 'free bytes');
      final _FakeDiscordApi api = _FakeDiscordApi(
        const DiscordSendResult(success: true, messageId: 'message-7'),
      );
      final UploadEngine engine = UploadEngine.createForTesting(apiClient: api);

      await engine.enqueue(
        <MediaCandidate>[MediaService.instance.describe(file.path)],
        options: EnqueueOptions(
          destinations: <Destination>[destination],
          autoStart: false,
        ),
      );
      await engine.run();

      expect(api.receivedBandwidthCaps.first, isNull);
    });

    test(
      'a fresh engine continues a queue that a dead process left behind',
      () async {
        final File file = await createFile(
          'interrupted.bin',
          'interrupted bytes',
        );
        final _FakeDiscordApi first = _FakeDiscordApi(
          const DiscordSendResult(success: true, messageId: 'message-8'),
        );
        final UploadEngine original = UploadEngine.createForTesting(
          apiClient: first,
        );

        await original.enqueue(
          <MediaCandidate>[MediaService.instance.describe(file.path)],
          options: EnqueueOptions(
            destinations: <Destination>[destination],
            autoStart: false,
          ),
        );
        await original.run();
        expect(first.callCount, 1);

        // A new job is queued but the process dies before it is sent.
        final File second = await createFile(
          'interrupted2.bin',
          'second bytes',
        );
        await original.enqueue(
          <MediaCandidate>[MediaService.instance.describe(second.path)],
          options: EnqueueOptions(
            destinations: <Destination>[destination],
            autoStart: false,
          ),
        );

        // A brand new engine stands in for the restarted process. It restores
        // the pending job from the database.
        final _FakeDiscordApi second2 = _FakeDiscordApi(
          const DiscordSendResult(success: true, messageId: 'message-9'),
        );
        final UploadEngine restarted = UploadEngine.createForTesting(
          apiClient: second2,
        );
        final int pending = await restarted.restore();
        expect(pending, 1);

        // Resume has to start the queue, even though the fresh engine was never
        // paused.
        await restarted.resume();
        await restarted.run();

        expect(
          second2.callCount,
          1,
          reason: 'the pending job is sent after the restart',
        );
      },
    );

    test('the native start command starts the queue', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final File file = await createFile('native.bin', 'native bytes');
      final _FakeDiscordApi api = _FakeDiscordApi(
        const DiscordSendResult(success: true, messageId: 'message-10'),
      );
      final UploadEngine engine = UploadEngine.createForTesting(apiClient: api);

      await engine.enqueue(
        <MediaCandidate>[MediaService.instance.describe(file.path)],
        options: EnqueueOptions(
          destinations: <Destination>[destination],
          autoStart: false,
        ),
      );

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        UploadEngine.nativeControlKey,
        '${DateTime.now().millisecondsSinceEpoch}:start',
      );

      await engine.run();
      expect(
        api.callCount,
        1,
        reason: 'the start command runs the pending work',
      );
    });

    test('publishes live activity events for the timeline', () async {
      final File file = await createFile('event.jpg', 'event bytes');
      final _FakeDiscordApi api = _FakeDiscordApi(
        const DiscordSendResult(success: true, messageId: 'message-5'),
      );
      final UploadEngine engine = UploadEngine.createForTesting(apiClient: api);

      await engine.enqueue(
        <MediaCandidate>[MediaService.instance.describe(file.path)],
        options: EnqueueOptions(
          destinations: <Destination>[destination],
          autoStart: false,
        ),
      );
      await engine.run();

      final List<LiveActivityEvent> events = await AppDatabase.instance
          .listLiveEvents();
      final List<String> types = events
          .map((LiveActivityEvent e) => e.type)
          .toList();
      expect(types, contains('upload_started'));
      expect(types, contains('delivery_succeeded'));
    });
  });
}
