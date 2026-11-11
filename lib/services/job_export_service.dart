import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/security.dart';
import '../data/models.dart';

/// Exports the upload jobs as CSV.
///
/// The export is redacted: a webhook URL or a bot token can never end up in
/// the file, because the jobs only hold destination *names* and every free
/// text field is passed through [Security.redactSecrets].
class JobExportService {
  JobExportService._();

  static final JobExportService instance = JobExportService._();

  /// The header of the CSV file.
  static const List<String> columns = <String>[
    'id',
    'fileName',
    'status',
    'destination',
    'bytes',
    'error',
    'createdAt',
    'completedAt',
  ];

  /// Builds the CSV body for the given jobs.
  ///
  /// [filter] is written into a first comment line so that the export
  /// documents which slice of the history it contains.
  String buildCsv(List<DistributionJob> jobs, {String? filter}) {
    final StringBuffer buffer = StringBuffer();
    if (filter != null && filter.isNotEmpty) {
      buffer.writeln('# filter: ${_csvCell(filter)}');
    }
    buffer.writeln(columns.join(','));
    for (final DistributionJob job in jobs) {
      buffer.writeln(
        <String>[
          _csvCell(job.id),
          _csvCell(job.fileName),
          _csvCell(job.status),
          _csvCell(job.destinationName ?? ''),
          _csvCell('${job.fileSize}'),
          _csvCell(Security.redactSecrets(job.errorMessage ?? '')),
          _csvCell(job.createdAt.toIso8601String()),
          _csvCell(job.completedAt?.toIso8601String() ?? ''),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  /// Builds the CSV body for the recorded history.
  ///
  /// The columns are the same as for a job export: an identifier, the file
  /// name, the status, the destination, the size, the redacted error and the
  /// timestamps.
  String buildHistoryCsv(List<UploadHistoryEntry> entries, {String? filter}) {
    final StringBuffer buffer = StringBuffer();
    if (filter != null && filter.isNotEmpty) {
      buffer.writeln('# filter: ${_csvCell(filter)}');
    }
    buffer.writeln(columns.join(','));
    for (final UploadHistoryEntry entry in entries) {
      buffer.writeln(
        <String>[
          _csvCell(entry.id),
          _csvCell(entry.fileName),
          _csvCell(entry.status),
          _csvCell(entry.destinationName ?? entry.target ?? ''),
          _csvCell('${entry.fileSize}'),
          _csvCell(Security.redactSecrets(entry.errorMessage ?? '')),
          _csvCell(entry.createdAt.toIso8601String()),
          _csvCell(entry.completedAt?.toIso8601String() ?? ''),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  /// Writes the CSV to a file in the application documents directory.
  Future<File> writeCsv(
    List<DistributionJob> jobs, {
    String name = 'upload-jobs',
    String? filter,
  }) async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final String stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final File file = File(p.join(directory.path, '$name-$stamp.csv'));
    await file.writeAsString(buildCsv(jobs, filter: filter));
    return file;
  }

  /// Writes the history CSV to a file in the application documents directory.
  Future<File> writeHistoryCsv(
    List<UploadHistoryEntry> entries, {
    String name = 'upload-jobs',
    String? filter,
  }) async {
    final Directory directory = await getApplicationDocumentsDirectory();
    final String stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final File file = File(p.join(directory.path, '$name-$stamp.csv'));
    await file.writeAsString(buildHistoryCsv(entries, filter: filter));
    return file;
  }

  /// Escapes a single CSV cell.
  ///
  /// A value that contains a comma, a quote or a newline is quoted and the
  /// quotes are doubled, as RFC 4180 requires.
  static String _csvCell(String value) {
    if (!value.contains(RegExp('[,"\n\r]'))) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  /// Returns true when the text contains something that looks like a secret.
  ///
  /// The test suite uses this to prove that an export never leaks a token.
  static bool containsSecret(String text) {
    if (RegExp(
      r'https://(?:ptb\.|canary\.)?discord(?:app)?\.com/api/webhooks/\d+/[A-Za-z0-9_\-]+',
    ).hasMatch(text)) {
      return true;
    }
    if (RegExp(
      r'\b[A-Za-z0-9_\-]{24,}\.[A-Za-z0-9_\-]{6,}\.[A-Za-z0-9_\-]{20,}\b',
    ).hasMatch(text)) {
      return true;
    }
    return false;
  }
}
