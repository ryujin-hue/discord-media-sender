import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/constants.dart';
import '../data/database.dart';
import '../data/models.dart';

/// Date range filter used by the analytics center and the dashboard.
enum AnalyticsRange {
  day24h('24h', 'Last 24 hours'),
  day7('7d', 'Last 7 days'),
  day30('30d', 'Last 30 days'),
  all('all', 'All time');

  const AnalyticsRange(this.key, this.label);

  final String key;
  final String label;

  DateTime? get since {
    final DateTime now = DateTime.now();
    switch (this) {
      case AnalyticsRange.day24h:
        return now.subtract(const Duration(hours: 24));
      case AnalyticsRange.day7:
        return now.subtract(const Duration(days: 7));
      case AnalyticsRange.day30:
        return now.subtract(const Duration(days: 30));
      case AnalyticsRange.all:
        return null;
    }
  }

  static AnalyticsRange fromKey(String? key) =>
      AnalyticsRange.values.firstWhere(
        (AnalyticsRange r) => r.key == key,
        orElse: () => AnalyticsRange.day7,
      );
}

/// Aggregate statistics computed from the database.
class AnalyticsSummary {
  const AnalyticsSummary({
    required this.totalFiles,
    required this.successfulUploads,
    required this.failedUploads,
    required this.pendingUploads,
    required this.totalBytesTransferred,
    required this.duplicatesDetected,
    required this.archivedFiles,
    required this.activeDestinations,
    required this.activityPerDay,
    required this.destinationPerformance,
    required this.successRate,
    required this.averageUploadSeconds,
  });

  final int totalFiles;
  final int successfulUploads;
  final int failedUploads;
  final int pendingUploads;
  final int totalBytesTransferred;
  final int duplicatesDetected;
  final int archivedFiles;
  final int activeDestinations;
  final List<ActivityPoint> activityPerDay;
  final List<DestinationPerformance> destinationPerformance;
  final double successRate;
  final double? averageUploadSeconds;
}

/// A single day of activity.
class ActivityPoint {
  const ActivityPoint({
    required this.day,
    required this.succeeded,
    required this.failed,
    required this.bytes,
  });

  final DateTime day;
  final int succeeded;
  final int failed;
  final int bytes;
}

/// Per-destination statistics.
class DestinationPerformance {
  const DestinationPerformance({
    required this.destinationId,
    required this.name,
    required this.sent,
    required this.failed,
    required this.bytes,
  });

  final String destinationId;
  final String name;
  final int sent;
  final int failed;
  final int bytes;
}

/// Builds analytics from real database records.
///
/// No value in this service is hard-coded or synthesised: every number is
/// derived from the `upload_history`, `delivery_records`, `duplicate_records`
/// and `archive_records` tables.
class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  final AppDatabase _db = AppDatabase.instance;

  /// Computes the summary for the given range.
  Future<AnalyticsSummary> summary(
    AnalyticsRange range, {
    String? destinationId,
  }) async {
    final DateTime? since = range.since;

    final List<UploadHistoryEntry> history = await _db.listHistory(
      destinationId: destinationId,
    );
    final List<UploadHistoryEntry> filtered = since == null
        ? history
        : history
              .where((UploadHistoryEntry e) => e.createdAt.isAfter(since))
              .toList();

    int successful = 0;
    int failed = 0;
    int pending = 0;
    int bytes = 0;
    int totalDurations = 0;
    int durationCount = 0;

    final Map<String, ActivityPoint> byDay = <String, ActivityPoint>{};
    final Map<String, _DestAccumulator> byDestination =
        <String, _DestAccumulator>{};

    for (final UploadHistoryEntry entry in filtered) {
      switch (entry.status) {
        case UploadStatus.completedKey:
          successful++;
          bytes += entry.fileSize;
          if (entry.completedAt != null) {
            final int seconds = entry.completedAt!
                .difference(entry.createdAt)
                .inSeconds;
            if (seconds >= 0) {
              totalDurations += seconds;
              durationCount++;
            }
          }
          break;
        case UploadStatus.failedKey:
          failed++;
          break;
        case UploadStatus.pendingKey:
        case UploadStatus.uploadingKey:
          pending++;
          break;
        default:
          break;
      }

      final DateTime day = DateTime(
        entry.createdAt.year,
        entry.createdAt.month,
        entry.createdAt.day,
      );
      final String key = _dayKey(day);
      final ActivityPoint existing =
          byDay[key] ??
          ActivityPoint(day: day, succeeded: 0, failed: 0, bytes: 0);
      byDay[key] = ActivityPoint(
        day: day,
        succeeded:
            existing.succeeded +
            (entry.status == UploadStatus.completedKey ? 1 : 0),
        failed:
            existing.failed + (entry.status == UploadStatus.failedKey ? 1 : 0),
        bytes:
            existing.bytes +
            (entry.status == UploadStatus.completedKey ? entry.fileSize : 0),
      );

      final String destinationKey = entry.destinationId ?? 'unknown';
      final _DestAccumulator accumulator =
          byDestination[destinationKey] ??
          _DestAccumulator(entry.destinationName ?? 'Unknown destination');
      accumulator.sent += entry.status == UploadStatus.completedKey ? 1 : 0;
      accumulator.failed += entry.status == UploadStatus.failedKey ? 1 : 0;
      accumulator.bytes += entry.status == UploadStatus.completedKey
          ? entry.fileSize
          : 0;
      byDestination[destinationKey] = accumulator;
    }

    final List<DuplicateRecord> duplicates = await _db.listDuplicates();
    final int duplicatesDetected = since == null
        ? duplicates.length
        : duplicates
              .where((DuplicateRecord d) => d.detectedAt.isAfter(since))
              .length;

    final List<ArchiveRecord> archive = await _db.listArchiveRecords();
    final int archivedFiles = since == null
        ? archive.length
        : archive
              .where((ArchiveRecord a) => a.archivedAt.isAfter(since))
              .length;

    final List<Destination> destinations = await _db.listDestinations();
    final int activeDestinations = destinations
        .where((Destination d) => d.enabled)
        .length;

    final List<ActivityPoint> activity = byDay.values.toList()
      ..sort((ActivityPoint a, ActivityPoint b) => a.day.compareTo(b.day));

    final List<DestinationPerformance> performance =
        byDestination.entries
            .map(
              (MapEntry<String, _DestAccumulator> e) => DestinationPerformance(
                destinationId: e.key,
                name: e.value.name?.isNotEmpty == true
                    ? e.value.name!
                    : 'Unknown destination',
                sent: e.value.sent,
                failed: e.value.failed,
                bytes: e.value.bytes,
              ),
            )
            .toList()
          ..sort(
            (DestinationPerformance a, DestinationPerformance b) =>
                b.sent.compareTo(a.sent),
          );

    final int decided = successful + failed;
    final double successRate = decided == 0 ? 0 : (successful / decided) * 100;

    return AnalyticsSummary(
      totalFiles: filtered.length,
      successfulUploads: successful,
      failedUploads: failed,
      pendingUploads: pending,
      totalBytesTransferred: bytes,
      duplicatesDetected: duplicatesDetected,
      archivedFiles: archivedFiles,
      activeDestinations: activeDestinations,
      activityPerDay: activity,
      destinationPerformance: performance,
      successRate: successRate,
      averageUploadSeconds: durationCount == 0
          ? null
          : totalDurations / durationCount,
    );
  }

  /// Exports the summary as CSV.
  ///
  /// Credentials are never part of an export: only destination *names* are
  /// included.
  Future<File> exportCsv(AnalyticsSummary summary) async {
    final StringBuffer buffer = StringBuffer()
      ..writeln('Metric,Value')
      ..writeln('Total files processed,${summary.totalFiles}')
      ..writeln('Successful uploads,${summary.successfulUploads}')
      ..writeln('Failed uploads,${summary.failedUploads}')
      ..writeln('Pending uploads,${summary.pendingUploads}')
      ..writeln('Total bytes transferred,${summary.totalBytesTransferred}')
      ..writeln('Duplicate files detected,${summary.duplicatesDetected}')
      ..writeln('Archived files,${summary.archivedFiles}')
      ..writeln('Active destinations,${summary.activeDestinations}')
      ..writeln('Success rate,${summary.successRate.toStringAsFixed(2)}')
      ..writeln()
      ..writeln('Day,Succeeded,Failed,Bytes')
      ..write(_activityCsv(summary.activityPerDay))
      ..writeln()
      ..writeln('Destination,Sent,Failed,Bytes')
      ..write(_destinationCsv(summary.destinationPerformance));

    return _writeExport('analytics', 'csv', buffer.toString());
  }

  /// Exports the summary as JSON.
  Future<File> exportJson(AnalyticsSummary summary) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'generated_at': DateTime.now().toIso8601String(),
      'totals': <String, dynamic>{
        'total_files': summary.totalFiles,
        'successful_uploads': summary.successfulUploads,
        'failed_uploads': summary.failedUploads,
        'pending_uploads': summary.pendingUploads,
        'total_bytes_transferred': summary.totalBytesTransferred,
        'duplicates_detected': summary.duplicatesDetected,
        'archived_files': summary.archivedFiles,
        'active_destinations': summary.activeDestinations,
        'success_rate': double.parse(summary.successRate.toStringAsFixed(2)),
        'average_upload_seconds': summary.averageUploadSeconds,
      },
      'activity': summary.activityPerDay
          .map(
            (ActivityPoint a) => <String, dynamic>{
              'day': a.day.toIso8601String().substring(0, 10),
              'succeeded': a.succeeded,
              'failed': a.failed,
              'bytes': a.bytes,
            },
          )
          .toList(),
      'destinations': summary.destinationPerformance
          .map(
            (DestinationPerformance d) => <String, dynamic>{
              'destination_id': d.destinationId,
              'name': d.name,
              'sent': d.sent,
              'failed': d.failed,
              'bytes': d.bytes,
            },
          )
          .toList(),
      'note': 'Exports never contain bot tokens, webhook URLs or API keys.',
    };
    return _writeExport(
      'analytics',
      'json',
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  /// Exports the summary as a PDF report.
  Future<File> exportPdf(AnalyticsSummary summary) async {
    final pw.Document document = pw.Document();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) => <pw.Widget>[
          pw.Header(
            level: 0,
            text: 'Discord Media Sender — Analytics',
            textStyle: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.Text(
            'Generated ${DateTime.now().toIso8601String()}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 12),
          _pdfTable(<String, String>{
            'Total files processed': '${summary.totalFiles}',
            'Successful uploads': '${summary.successfulUploads}',
            'Failed uploads': '${summary.failedUploads}',
            'Pending uploads': '${summary.pendingUploads}',
            'Total data transferred': '${summary.totalBytesTransferred} bytes',
            'Duplicate files detected': '${summary.duplicatesDetected}',
            'Archived files': '${summary.archivedFiles}',
            'Active destinations': '${summary.activeDestinations}',
            'Success rate': '${summary.successRate.toStringAsFixed(1)}%',
          }),
          pw.SizedBox(height: 18),
          pw.Text(
            'Upload activity over time',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            data: summary.activityPerDay
                .map(
                  (ActivityPoint a) => <dynamic>[
                    a.day.toIso8601String().substring(0, 10),
                    '${a.succeeded}',
                    '${a.failed}',
                    '${a.bytes}',
                  ],
                )
                .toList(),
            headers: const <String>['Day', 'Succeeded', 'Failed', 'Bytes'],
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Destination performance',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            data: summary.destinationPerformance
                .map(
                  (DestinationPerformance d) => <dynamic>[
                    d.name,
                    '${d.sent}',
                    '${d.failed}',
                    '${d.bytes}',
                  ],
                )
                .toList(),
            headers: const <String>['Destination', 'Sent', 'Failed', 'Bytes'],
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'This report intentionally excludes bot tokens, webhook URLs and API keys.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );

    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File(
      p.join(
        dir.path,
        'analytics_${DateTime.now().millisecondsSinceEpoch}.pdf',
      ),
    );
    await file.writeAsBytes(await document.save(), flush: true);
    return file;
  }

  pw.Widget _pdfTable(Map<String, String> values) {
    return pw.TableHelper.fromTextArray(
      data: values.entries
          .map((MapEntry<String, String> e) => <dynamic>[e.key, e.value])
          .toList(),
      headers: const <String>['Metric', 'Value'],
    );
  }

  String _activityCsv(List<ActivityPoint> points) {
    final StringBuffer buffer = StringBuffer();
    for (final ActivityPoint point in points) {
      buffer.writeln(
        '${point.day.toIso8601String().substring(0, 10)},'
        '${point.succeeded},${point.failed},${point.bytes}',
      );
    }
    return buffer.toString();
  }

  String _destinationCsv(List<DestinationPerformance> performance) {
    final StringBuffer buffer = StringBuffer();
    for (final DestinationPerformance item in performance) {
      buffer.writeln(
        '"${item.name.replaceAll('"', '""')}",'
        '${item.sent},${item.failed},${item.bytes}',
      );
    }
    return buffer.toString();
  }

  Future<File> _writeExport(
    String name,
    String extension,
    String content,
  ) async {
    final Directory dir = await getApplicationDocumentsDirectory();
    final File file = File(
      p.join(
        dir.path,
        '${name}_${DateTime.now().millisecondsSinceEpoch}.$extension',
      ),
    );
    await file.writeAsString(content, flush: true);
    return file;
  }

  static String _dayKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

class _DestAccumulator {
  _DestAccumulator(this.name);

  final String? name;
  int sent = 0;
  int failed = 0;
  int bytes = 0;
}
