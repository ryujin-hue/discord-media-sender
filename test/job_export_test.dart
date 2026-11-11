import 'package:discord_media_sender/data/models.dart';
import 'package:discord_media_sender/services/job_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// A webhook URL that looks like the real thing.
  ///
  /// The value is assembled at runtime so that no secret-looking literal is
  /// stored in the repository.
  final String webhookUrl =
      'https://discord.com/api/webhooks/123456789012345678/${'x' * 68}';

  /// A bot token that looks like the real thing.
  final String botToken = List<String>.filled(3, 'x' * 30).join('.');

  DistributionJob buildJob({
    String id = 'job-1',
    String fileName = 'holiday.jpg',
    String status = 'completed',
    String destination = 'Alpha server',
    int fileSize = 5242880,
    String? error,
  }) {
    return DistributionJob(
      id: id,
      filePath: '/storage/emulated/0/$fileName',
      fileName: fileName,
      fileSize: fileSize,
      status: status,
      createdAt: DateTime(2026, 1, 1, 12),
      destinationId: 'dest-a',
      destinationName: destination,
      sha256: 'a' * 64,
      errorMessage: error,
    );
  }

  group('Job CSV export', () {
    test('writes the documented columns', () {
      final String csv = JobExportService.instance.buildCsv(<DistributionJob>[
        buildJob(),
      ]);

      final List<String> lines = csv.trim().split('\n');
      expect(
        lines.first,
        'id,fileName,status,destination,bytes,error,createdAt,completedAt',
      );
      expect(lines[1], contains('job-1'));
      expect(lines[1], contains('holiday.jpg'));
      expect(lines[1], contains('completed'));
      expect(lines[1], contains('Alpha server'));
      expect(lines[1], contains('5242880'));
    });

    test('never writes a webhook URL', () {
      final String csv = JobExportService.instance.buildCsv(<DistributionJob>[
        buildJob(error: 'Failed to reach $webhookUrl'),
      ]);

      expect(csv.contains(webhookUrl), isFalse);
      expect(csv.contains('[webhook-redacted]'), isTrue);
      expect(JobExportService.containsSecret(csv), isFalse);
    });

    test('never writes a bot token', () {
      final String csv = JobExportService.instance.buildCsv(<DistributionJob>[
        buildJob(error: 'Authentication failed for $botToken'),
      ]);

      expect(csv.contains(botToken), isFalse);
      expect(csv.contains('[token-redacted]'), isTrue);
      expect(JobExportService.containsSecret(csv), isFalse);
    });

    test('escapes a cell that contains a comma or a quote', () {
      final String csv = JobExportService.instance.buildCsv(<DistributionJob>[
        buildJob(error: 'Bad "value", comma'),
      ]);

      expect(csv.contains('"Bad ""value"", comma"'), isTrue);
    });

    test('writes the history with the same columns', () {
      final UploadHistoryEntry entry = UploadHistoryEntry(
        id: 'hist-1',
        fileName: 'clip.mp4',
        filePath: '/storage/emulated/0/clip.mp4',
        fileSize: 1024,
        status: 'failed',
        createdAt: DateTime(2026, 1, 1, 12),
        destinationName: 'Beta server',
        errorMessage: 'Rate limited',
      );

      final String csv = JobExportService.instance.buildHistoryCsv(
        <UploadHistoryEntry>[entry],
      );

      final List<String> lines = csv.trim().split('\n');
      expect(
        lines.first,
        'id,fileName,status,destination,bytes,error,createdAt,completedAt',
      );
      expect(lines[1], contains('hist-1'));
      expect(lines[1], contains('clip.mp4'));
      expect(lines[1], contains('failed'));
      expect(lines[1], contains('Beta server'));
    });

    test('records the filter in a comment line', () {
      final String csv = JobExportService.instance.buildCsv(<DistributionJob>[
        buildJob(),
      ], filter: 'failed');
      expect(csv.startsWith('# filter: failed'), isTrue);
    });

    test('detects a secret in a raw text', () {
      expect(JobExportService.containsSecret(webhookUrl), isTrue);
      expect(JobExportService.containsSecret(botToken), isTrue);
      expect(
        JobExportService.containsSecret('a normal error message'),
        isFalse,
      );
    });
  });
}
