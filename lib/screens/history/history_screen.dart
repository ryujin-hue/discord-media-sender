import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../providers/config_providers.dart';
import '../../services/job_export_service.dart';
import '../../services/upload_engine.dart';
import '../../widgets/common.dart';

/// The upload history with search, status filters and log export.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final _HistoryFilter filter = ref.watch(_historyFilterProvider);
    final AsyncValue<List<UploadHistoryEntry>> historyAsync = ref.watch(
      historyProvider,
    );
    final List<UploadHistoryEntry> entries =
        historyAsync.value ?? const <UploadHistoryEntry>[];
    final List<UploadHistoryEntry> visible = _applyFilter(entries, filter);
    final int failedInView = visible
        .where(
          (UploadHistoryEntry entry) => entry.status == UploadStatus.failedKey,
        )
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload history'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(historyProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Export',
            enabled: visible.isNotEmpty,
            onSelected: (String value) {
              if (value == 'csv') {
                _exportCsv(context, visible, filter);
              } else {
                _exportLog(context, visible);
              }
            },
            itemBuilder: (BuildContext context) =>
                const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'csv',
                    child: Text('Export jobs CSV'),
                  ),
                  PopupMenuItem<String>(
                    value: 'json',
                    child: Text('Export log as JSON and text'),
                  ),
                ],
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: 'Clear history',
            onPressed: entries.isEmpty
                ? null
                : () {
                    _clearHistory(context, ref);
                  },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: _HistorySearchField(
                onChanged: (String value) {
                  ref.read(_historyFilterProvider.notifier).setQuery(value);
                },
              ),
            ),
            _StatusFilterChips(
              selected: filter.status,
              onChanged: (_HistoryStatus value) {
                ref.read(_historyFilterProvider.notifier).setStatus(value);
              },
            ),
            const SizedBox(height: 6),
            if (failedInView > 0)
              _BatchRetryBar(
                count: failedInView,
                onRetry: () => _retryFailed(context, ref, failedInView),
              ),
            Expanded(
              child: historyAsync.isLoading && entries.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                  ? EmptyState(
                      icon: Icons.history_rounded,
                      title: entries.isEmpty
                          ? 'No uploads recorded yet'
                          : 'Nothing matches the filter',
                      message: entries.isEmpty
                          ? 'Every upload is recorded here as soon as it '
                                'is delivered to Discord.'
                          : 'Change the search term or pick another status '
                                'to see more uploads.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                      itemCount: visible.length,
                      itemBuilder: (BuildContext context, int index) {
                        return _HistoryRow(entry: visible[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearHistory(BuildContext context, WidgetRef ref) async {
    final bool confirmed = await showConfirmDialog(
      context,
      title: 'Clear upload history',
      message:
          'All recorded uploads will be deleted from this device. This cannot '
          'be undone.',
      confirmLabel: 'Clear',
      destructive: true,
    );
    if (!confirmed) return;
    await AppDatabase.instance.clearHistory();
    ref.invalidate(historyProvider);
    if (!context.mounted) return;
    showAppSnack(context, 'Upload history cleared', isSuccess: true);
  }

  /// Retries every failed upload of the current filter.
  Future<void> _retryFailed(
    BuildContext context,
    WidgetRef ref,
    int count,
  ) async {
    final List<UploadHistoryEntry> entries =
        ref.read(historyProvider).value ?? const <UploadHistoryEntry>[];
    final List<UploadHistoryEntry> failed =
        _applyFilter(entries, ref.read(_historyFilterProvider))
            .where(
              (UploadHistoryEntry entry) =>
                  entry.status == UploadStatus.failedKey,
            )
            .toList();

    if (failed.isEmpty) {
      if (context.mounted) {
        showAppSnack(context, 'No failed uploads to retry', isError: true);
      }
      return;
    }

    final UploadEngine engine = UploadEngine.instance;
    int retried = 0;
    for (final UploadHistoryEntry entry in failed) {
      final String? jobId = entry.sessionId;
      if (jobId == null || jobId.isEmpty) continue;
      await engine.retryJob(jobId);
      retried++;
    }

    ref.invalidate(historyProvider);
    if (!context.mounted) return;
    showAppSnack(
      context,
      '$retried of $count failed uploads queued for retry',
      isSuccess: true,
    );
  }

  /// Exports the visible history as a CSV file and opens the share sheet.
  Future<void> _exportCsv(
    BuildContext context,
    List<UploadHistoryEntry> entries,
    _HistoryFilter filter,
  ) async {
    try {
      final String filterLabel = filter.status == _HistoryStatus.all
          ? 'all'
          : filter.status.name;
      final File file = await JobExportService.instance.writeHistoryCsv(
        entries,
        name: 'upload-jobs',
        filter: filterLabel,
      );
      if (!context.mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'text/csv')],
          subject: 'Discord Media Sender upload jobs',
          text: 'Upload jobs exported from Discord Media Sender.',
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      showAppSnack(
        context,
        'The jobs could not be exported: $error',
        isError: true,
      );
    }
  }

  Future<void> _exportLog(
    BuildContext context,
    List<UploadHistoryEntry> entries,
  ) async {
    try {
      final Directory directory = await getApplicationDocumentsDirectory();
      final String stamp = DateTime.now().toIso8601String().replaceAll(
        ':',
        '-',
      );
      final File jsonFile = File(
        p.join(directory.path, 'upload-history-$stamp.json'),
      );
      final File textFile = File(
        p.join(directory.path, 'upload-history-$stamp.txt'),
      );
      await jsonFile.writeAsString(_historyJson(entries));
      await textFile.writeAsString(_historyText(entries));
      if (!context.mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile(jsonFile.path, mimeType: 'application/json'),
            XFile(textFile.path, mimeType: 'text/plain'),
          ],
          subject: 'Discord Media Sender upload history',
          text: 'Upload history exported from Discord Media Sender.',
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      showAppSnack(
        context,
        'The log could not be exported: $error',
        isError: true,
      );
    }
  }
}

/// The bar that offers a batch retry of the failed uploads in view.
class _BatchRetryBar extends StatelessWidget {
  const _BatchRetryBar({required this.count, required this.onRetry});

  final int count;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppConstants.colorError.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: AppConstants.colorError,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('$count failed', style: theme.textTheme.bodyMedium),
            ),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.replay_rounded, size: 16),
              label: const Text('Retry all'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The search field that filters the history by file name.
class _HistorySearchField extends StatefulWidget {
  const _HistorySearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  State<_HistorySearchField> createState() => _HistorySearchFieldState();
}

class _HistorySearchFieldState extends State<_HistorySearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search by file name',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder:
              (BuildContext context, TextEditingValue value, Widget? child) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                  },
                  icon: const Icon(Icons.close_rounded),
                );
              },
        ),
      ),
    );
  }
}

/// The row of status filter chips.
class _StatusFilterChips extends StatelessWidget {
  const _StatusFilterChips({required this.selected, required this.onChanged});

  final _HistoryStatus selected;
  final ValueChanged<_HistoryStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: <Widget>[
          _chip(context, _HistoryStatus.all, 'All'),
          _chip(context, _HistoryStatus.completed, 'Completed'),
          _chip(context, _HistoryStatus.failed, 'Failed'),
          _chip(context, _HistoryStatus.pending, 'Pending'),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, _HistoryStatus status, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected == status,
        onSelected: (bool value) {
          if (value) onChanged(status);
        },
      ),
    );
  }
}

/// A single upload of the history.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final UploadHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final StatusStyle style = StatusStyle.forUploadStatus(entry.status);
    final String destination =
        entry.destinationName ?? entry.target ?? 'Unknown destination';
    final String? error = entry.errorMessage;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      Formatters.fileName(entry.fileName),
                      style: theme.textTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      destination,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              StatusPill(
                label: style.label,
                color: style.color,
                icon: style.icon,
              ),
              if (entry.status == UploadStatus.failedKey &&
                  (entry.sessionId ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Retry',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  onPressed: () => _retryOne(context, entry),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Icon(
                Icons.data_usage_rounded,
                size: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                Formatters.bytes(entry.fileSize),
                style: theme.textTheme.labelSmall,
              ),
              const SizedBox(width: 14),
              Icon(
                Icons.schedule_rounded,
                size: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                _formatDateTime(entry.createdAt),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          if (error != null && error.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              error,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppConstants.colorError,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Retries a single failed upload.
Future<void> _retryOne(BuildContext context, UploadHistoryEntry entry) async {
  final String? jobId = entry.sessionId;
  if (jobId == null || jobId.isEmpty) {
    if (context.mounted) {
      showAppSnack(context, 'This upload cannot be retried', isError: true);
    }
    return;
  }
  await UploadEngine.instance.retryJob(jobId);
  if (!context.mounted) return;
  showAppSnack(context, '${entry.fileName} queued for retry', isSuccess: true);
}

/// The status filter applied to the visible history.
enum _HistoryStatus { all, completed, failed, pending }

/// The search term and the status filter of the history screen.
class _HistoryFilter {
  const _HistoryFilter({this.query = '', this.status = _HistoryStatus.all});

  final String query;
  final _HistoryStatus status;

  _HistoryFilter copyWith({String? query, _HistoryStatus? status}) {
    return _HistoryFilter(
      query: query ?? this.query,
      status: status ?? this.status,
    );
  }
}

/// Holds the search term and the status filter of the history screen.
class _HistoryFilterNotifier extends Notifier<_HistoryFilter> {
  @override
  _HistoryFilter build() => const _HistoryFilter();

  void setQuery(String value) {
    state = state.copyWith(query: value);
  }

  void setStatus(_HistoryStatus value) {
    state = state.copyWith(status: value);
  }
}

/// The filter state of the history screen.
final NotifierProvider<_HistoryFilterNotifier, _HistoryFilter>
_historyFilterProvider =
    NotifierProvider<_HistoryFilterNotifier, _HistoryFilter>(
      _HistoryFilterNotifier.new,
    );

/// Applies the search term and the status filter to the history.
List<UploadHistoryEntry> _applyFilter(
  List<UploadHistoryEntry> entries,
  _HistoryFilter filter,
) {
  final String query = filter.query.trim().toLowerCase();

  return entries.where((UploadHistoryEntry entry) {
    if (query.isNotEmpty && !entry.fileName.toLowerCase().contains(query)) {
      return false;
    }
    final bool matchesStatus = switch (filter.status) {
      _HistoryStatus.all => true,
      _HistoryStatus.completed => entry.status == UploadStatus.completedKey,
      _HistoryStatus.failed => entry.status == UploadStatus.failedKey,
      _HistoryStatus.pending =>
        entry.status == UploadStatus.pendingKey ||
            entry.status == UploadStatus.uploadingKey,
    };
    return matchesStatus;
  }).toList();
}

/// Builds the JSON representation of the visible history.
String _historyJson(List<UploadHistoryEntry> entries) {
  final List<Map<String, Object?>> rows = <Map<String, Object?>>[
    for (final UploadHistoryEntry entry in entries)
      <String, Object?>{
        'file_name': entry.fileName,
        'file_path': entry.filePath,
        'destination': entry.destinationName ?? entry.target,
        'mode': entry.mode,
        'status': entry.status,
        'size_bytes': entry.fileSize,
        'created_at': entry.createdAt.toIso8601String(),
        'completed_at': entry.completedAt?.toIso8601String(),
        'error': entry.errorMessage,
        'message_id': entry.messageId,
        'message_url': entry.messageUrl,
      },
  ];
  return const JsonEncoder.withIndent('  ').convert(rows);
}

/// Builds the plain text representation of the visible history.
String _historyText(List<UploadHistoryEntry> entries) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('Discord Media Sender — upload history')
    ..writeln('Generated: ${DateTime.now().toIso8601String()}')
    ..writeln('Entries: ${entries.length}')
    ..writeln();
  for (final UploadHistoryEntry entry in entries) {
    buffer.writeln(
      '- ${entry.createdAt.toIso8601String()}  '
      '[${entry.status}]  ${entry.fileName}  '
      '${Formatters.bytes(entry.fileSize)}  '
      '${entry.destinationName ?? entry.target ?? 'unknown destination'}',
    );
    final String? error = entry.errorMessage;
    if (error != null && error.isNotEmpty) {
      buffer.writeln('    error: $error');
    }
  }
  return buffer.toString();
}

/// Formats a timestamp as `yyyy-MM-dd HH:mm`.
String _formatDateTime(DateTime value) {
  final DateTime local = value.toLocal();
  final String month = local.month.toString().padLeft(2, '0');
  final String day = local.day.toString().padLeft(2, '0');
  final String hour = local.hour.toString().padLeft(2, '0');
  final String minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
