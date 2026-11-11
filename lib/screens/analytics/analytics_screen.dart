import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/security.dart';
import '../../data/models.dart';
import '../../providers/config_providers.dart';
import '../../services/analytics_service.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';

/// The analytics centre — upload statistics, charts and exports.
///
/// Every number shown here is derived from the real upload history, duplicate
/// and archive records stored in the database. When the selected range contains
/// no activity the screen shows an empty state instead of inventing values.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

/// The export formats offered by the analytics centre.
enum _ExportFormat {
  csv('CSV'),
  json('JSON'),
  pdf('PDF');

  const _ExportFormat(this.label);

  final String label;
}

/// The patterns that reveal a credential inside an exported file.
final RegExp _webhookUrlPattern = RegExp(
  r"https?://[^\s'<>]*(?:discord(?:app)?\.com|discord\.com)/api/webhooks/[^\s'<>]*",
  caseSensitive: false,
);

/// The pattern of a bot token that is sent as an authorization header.
final RegExp _botTokenPattern = RegExp(r'\bBot\s+[A-Za-z0-9_\-\.]{20,}');

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  AnalyticsRange _range = AnalyticsRange.day7;
  String? _destinationId;
  AnalyticsSummary? _summary;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads the summary for the current range and destination filter.
  Future<void> _load() async {
    final AnalyticsSummary summary = await AnalyticsService.instance.summary(
      _range,
      destinationId: _destinationId,
    );
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _loading = false;
    });
  }

  /// Reloads the summary and shows the loading state again.
  Future<void> _refresh() async {
    setState(() => _loading = true);
    await _load();
  }

  void _selectRange(AnalyticsRange range) {
    if (range == _range) return;
    setState(() {
      _range = range;
      _loading = true;
    });
    _load();
  }

  void _selectDestination(String? destinationId) {
    setState(() {
      _destinationId = destinationId;
      _loading = true;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final List<Destination> destinations =
        ref.watch(destinationsProvider).value ?? const <Destination>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics center'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: <Widget>[
            _buildFilters(destinations),
            const SizedBox(height: 14),
            ..._buildContent(),
          ],
        ),
      ),
    );
  }

  /// The statistic and chart body, or the empty state when nothing happened.
  List<Widget> _buildContent() {
    if (_loading) {
      return <Widget>[
        SectionCard(
          title: 'Loading analytics',
          icon: Icons.hourglass_top_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const LoadingSkeleton(height: 96),
              const SizedBox(height: 12),
              const LoadingSkeleton(height: 150),
            ],
          ),
        ),
      ];
    }

    final AnalyticsSummary? summary = _summary;
    if (summary == null) return const <Widget>[];

    if (summary.totalFiles == 0) {
      return <Widget>[
        const SizedBox(
          height: 280,
          child: EmptyState(
            icon: Icons.insights_rounded,
            title: 'No activity recorded',
            message:
                'No activity was recorded in the selected range. Pick a wider '
                'range or upload some media to populate the analytics.',
          ),
        ),
        const SizedBox(height: 14),
        _buildExportSection(summary),
      ];
    }

    return <Widget>[
      _buildKeyFigures(summary),
      const SizedBox(height: 14),
      _buildActivityChart(summary),
      const SizedBox(height: 14),
      _buildRatioCard(summary),
      const SizedBox(height: 14),
      _buildVolumeChart(summary),
      const SizedBox(height: 14),
      _buildDestinationPerformance(summary),
      const SizedBox(height: 14),
      _buildDuplicateCard(summary),
      const SizedBox(height: 14),
      _buildArchiveCard(summary),
      const SizedBox(height: 14),
      _buildExportSection(summary),
    ];
  }

  /// The range and the destination filter of the report.
  Widget _buildFilters(List<Destination> destinations) {
    return SectionCard(
      title: 'Filters',
      subtitle: _range.label,
      icon: Icons.filter_alt_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final AnalyticsRange range in AnalyticsRange.values)
                FilterChip(
                  label: Text(range.label),
                  selected: _range == range,
                  showCheckmark: false,
                  onSelected: (bool selected) {
                    if (selected) _selectRange(range);
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _destinationId,
            isExpanded: true,
            hint: const Text('All destinations'),
            decoration: const InputDecoration(labelText: 'Destination'),
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All destinations'),
              ),
              for (final Destination destination in destinations)
                DropdownMenuItem<String?>(
                  value: destination.id,
                  child: Text(
                    destination.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _loading ? null : _selectDestination,
          ),
        ],
      ),
    );
  }

  /// The headline numbers of the report.
  Widget _buildKeyFigures(AnalyticsSummary summary) {
    return SectionCard(
      title: 'Key figures',
      icon: Icons.insights_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: <Widget>[
              StatTile(
                label: 'Files processed',
                value: Formatters.count(summary.totalFiles),
                icon: Icons.folder_open_rounded,
              ),
              StatTile(
                label: 'Successful uploads',
                value: Formatters.count(summary.successfulUploads),
                icon: Icons.check_circle_rounded,
                color: AppConstants.colorSuccess,
              ),
              StatTile(
                label: 'Failed uploads',
                value: Formatters.count(summary.failedUploads),
                icon: Icons.error_rounded,
                color: AppConstants.colorError,
              ),
              StatTile(
                label: 'Pending uploads',
                value: Formatters.count(summary.pendingUploads),
                icon: Icons.schedule_rounded,
                color: AppConstants.colorWarning,
              ),
            ],
          ),
          const SizedBox(height: 12),
          MetricRow(
            label: 'Data transferred',
            value: Formatters.bytes(summary.totalBytesTransferred),
          ),
          MetricRow(
            label: 'Success rate',
            value: Formatters.percent(summary.successRate),
          ),
          MetricRow(
            label: 'Average upload time',
            value: summary.averageUploadSeconds == null
                ? '—'
                : Formatters.duration(summary.averageUploadSeconds!.round()),
          ),
          MetricRow(
            label: 'Duplicate files detected',
            value: Formatters.count(summary.duplicatesDetected),
          ),
          MetricRow(
            label: 'Archived files',
            value: Formatters.count(summary.archivedFiles),
          ),
          MetricRow(
            label: 'Active destinations',
            value: Formatters.count(summary.activeDestinations),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityChart(AnalyticsSummary summary) {
    final List<BarChartValue> values = <BarChartValue>[];
    final List<String> labels = <String>[];
    for (final ActivityPoint point in summary.activityPerDay) {
      values.add(
        BarChartValue(succeeded: point.succeeded, failed: point.failed),
      );
      labels.add('${point.day.month}/${point.day.day}');
    }

    return SectionCard(
      title: 'Upload activity',
      subtitle: 'Successful and failed uploads per day',
      icon: Icons.bar_chart_rounded,
      child: ActivityBarChart(values: values, labels: labels),
    );
  }

  Widget _buildRatioCard(AnalyticsSummary summary) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: 'Success ratio',
      subtitle: 'Completed versus failed uploads',
      icon: Icons.pie_chart_rounded,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SuccessFailureDonut(
            succeeded: summary.successfulUploads,
            failed: summary.failedUploads,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MetricRow(
                  label: 'Successful',
                  value: Formatters.count(summary.successfulUploads),
                  valueColor: AppConstants.colorSuccess,
                ),
                MetricRow(
                  label: 'Failed',
                  value: Formatters.count(summary.failedUploads),
                  valueColor: AppConstants.colorError,
                ),
                const SizedBox(height: 4),
                Text(
                  'Pending uploads are not part of the success rate.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVolumeChart(AnalyticsSummary summary) {
    final List<BarChartValue> values = <BarChartValue>[];
    final List<String> labels = <String>[];
    for (final ActivityPoint point in summary.activityPerDay) {
      values.add(BarChartValue(succeeded: point.bytes, failed: 0));
      labels.add('${point.day.month}/${point.day.day}');
    }

    return SectionCard(
      title: 'Daily upload volume',
      subtitle: 'Transferred bytes per day',
      icon: Icons.stacked_line_chart_rounded,
      child: ActivityBarChart(values: values, labels: labels),
    );
  }

  Widget _buildDestinationPerformance(AnalyticsSummary summary) {
    final ThemeData theme = Theme.of(context);
    if (summary.destinationPerformance.isEmpty) {
      return SectionCard(
        title: 'Destination performance',
        icon: Icons.hub_rounded,
        child: Text(
          'No destination recorded any upload in this range.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final int maxSent = summary.destinationPerformance
        .map((DestinationPerformance d) => d.sent)
        .reduce((int a, int b) => a > b ? a : b);

    return SectionCard(
      title: 'Destination performance',
      subtitle: '${summary.destinationPerformance.length} destinations',
      icon: Icons.hub_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final DestinationPerformance destination
              in summary.destinationPerformance) ...<Widget>[
            Text(
              destination.name,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            ProportionBar(
              value: destination.sent.toDouble(),
              max: maxSent.toDouble(),
              color: AppConstants.colorPrimary,
            ),
            const SizedBox(height: 4),
            MetricRow(label: 'Sent', value: Formatters.count(destination.sent)),
            MetricRow(
              label: 'Failed',
              value: Formatters.count(destination.failed),
              valueColor: destination.failed > 0
                  ? AppConstants.colorError
                  : AppConstants.colorSuccess,
            ),
            MetricRow(
              label: 'Data transferred',
              value: Formatters.bytes(destination.bytes),
            ),
            const SizedBox(height: 6),
            const Divider(),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildDuplicateCard(AnalyticsSummary summary) {
    final ThemeData theme = Theme.of(context);
    final List<DuplicateRecord> duplicates =
        ref.watch(duplicatesProvider).value ?? const <DuplicateRecord>[];
    final DateTime? since = _range.since;
    final List<DuplicateRecord> ranged = since == null
        ? duplicates
        : duplicates
              .where((DuplicateRecord d) => d.detectedAt.isAfter(since))
              .toList();

    final Map<String, int> byMethod = <String, int>{};
    for (final DuplicateRecord duplicate in ranged) {
      byMethod[duplicate.method] = (byMethod[duplicate.method] ?? 0) + 1;
    }

    return SectionCard(
      title: 'Duplicate detection statistics',
      subtitle:
          '${Formatters.count(summary.duplicatesDetected)} duplicates detected',
      icon: Icons.copy_all_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (byMethod.isEmpty)
            Text(
              'No duplicate was detected with a specific method in this range.',
              style: theme.textTheme.bodySmall,
            )
          else ...<Widget>[
            for (final MapEntry<String, int> entry in byMethod.entries)
              MetricRow(
                label: DetectionMethod.fromKey(entry.key).label,
                value: Formatters.count(entry.value),
              ),
            const SizedBox(height: 6),
            Text(
              'SHA-256 is an exact match. Metadata and perceptual hash are '
              'possible matches.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildArchiveCard(AnalyticsSummary summary) {
    final List<ArchiveRecord> archives =
        ref.watch(archiveProvider).value ?? const <ArchiveRecord>[];
    final DateTime? since = _range.since;
    final List<ArchiveRecord> ranged = since == null
        ? archives
        : archives
              .where((ArchiveRecord a) => a.archivedAt.isAfter(since))
              .toList();
    final int archiveBytes = ranged.fold<int>(
      0,
      (int sum, ArchiveRecord record) => sum + record.fileSize,
    );

    return SectionCard(
      title: 'Archive activity',
      subtitle: '${Formatters.count(summary.archivedFiles)} files archived',
      icon: Icons.inventory_2_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MetricRow(
            label: 'Archive storage',
            value: Formatters.bytes(archiveBytes),
          ),
        ],
      ),
    );
  }

  Widget _buildExportSection(AnalyticsSummary summary) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: 'Export',
      subtitle: 'Save the current report to a file',
      icon: Icons.ios_share_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final _ExportFormat format in _ExportFormat.values)
                OutlinedButton(
                  onPressed: _exporting ? null : () => _export(summary, format),
                  child: Text(format.label),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Metrics and destination names only. An export that contains a '
            'token or a webhook URL is discarded instead of being offered.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// Writes the report to a file and offers to open it.
  ///
  /// The report is checked before and after it is written: a report that
  /// carries a credential never reaches the user.
  Future<void> _export(AnalyticsSummary summary, _ExportFormat format) async {
    if (_summaryHoldsSecret(summary)) {
      showAppSnack(
        context,
        'The export was cancelled: a destination name contains a token or a '
        'webhook URL.',
        isError: true,
      );
      return;
    }

    setState(() => _exporting = true);
    try {
      final File file;
      switch (format) {
        case _ExportFormat.csv:
          file = await AnalyticsService.instance.exportCsv(summary);
          break;
        case _ExportFormat.json:
          file = await AnalyticsService.instance.exportJson(summary);
          break;
        case _ExportFormat.pdf:
          file = await AnalyticsService.instance.exportPdf(summary);
          break;
      }
      if (format != _ExportFormat.pdf && await _fileHoldsSecret(file)) {
        await file.delete();
        if (!mounted) return;
        showAppSnack(
          context,
          'The export file was deleted: it contained a token or a webhook URL.',
          isError: true,
        );
        return;
      }
      if (!mounted) return;
      await _showExportResult(file);
    } catch (error) {
      if (!mounted) return;
      showAppSnack(
        context,
        'Export failed: ${Security.redactSecrets(error.toString())}',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Checks whether the report holds a credential.
  ///
  /// The report is built from the destination names, so a name that contains
  /// a webhook URL would end up in the file.
  bool _summaryHoldsSecret(AnalyticsSummary summary) {
    for (final DestinationPerformance destination
        in summary.destinationPerformance) {
      if (_holdsSecret(destination.name)) return true;
      if (_holdsSecret(destination.destinationId)) return true;
    }
    return false;
  }

  /// Checks whether the written file holds a credential.
  ///
  /// The PDF export compresses its pages, so only the readable formats are
  /// checked here; the PDF is covered by the check of the report itself, which
  /// runs before the file is written.
  Future<bool> _fileHoldsSecret(File file) async {
    final List<int> bytes = await file.readAsBytes();
    return _holdsSecret(String.fromCharCodes(bytes));
  }

  /// Returns true when the text holds something that looks like a credential.
  bool _holdsSecret(String content) {
    if (content.isEmpty) return false;
    if (_webhookUrlPattern.hasMatch(content)) return true;
    if (_botTokenPattern.hasMatch(content)) return true;
    return Security.redactSecrets(content) != content;
  }

  /// Shows the path of the generated export and lets the user open it.
  Future<void> _showExportResult(File file) async {
    final ThemeData theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Export ready'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'The ${file.uri.pathSegments.last} file was saved to:',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SelectableText(file.path, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              Text(
                'The report was checked: it holds no token and no webhook URL.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await OpenFilex.open(file.path);
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Open'),
            ),
          ],
        );
      },
    );
  }
}
