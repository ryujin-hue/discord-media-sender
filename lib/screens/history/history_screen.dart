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
    final List<_HistoryDay> days = _groupByDay(visible);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload history'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(historyProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Export log',
            onPressed: visible.isEmpty
                ? null
                : () {
                    _exportLog(context, visible);
                  },
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
                      itemCount: days.length,
                      itemBuilder: (BuildContext context, int index) {
                        return _DaySection(day: days[index]);
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

/// The uploads of a single day.
class _DaySection extends StatelessWidget {
  const _DaySection({required this.day});

  final _HistoryDay day;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String plural = day.entries.length == 1 ? '' : 's';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _dayLabel(day.date),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                '${day.entries.length} file$plural · '
                '${Formatters.bytes(day.totalBytes)}',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
        SectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < day.entries.length; i++) ...<Widget>[
                if (i > 0) const Divider(height: 1),
                _HistoryRow(entry: day.entries[i]),
              ],
            ],
          ),
        ),
      ],
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

/// The uploads of one day.
class _HistoryDay {
  const _HistoryDay({required this.date, required this.entries});

  final DateTime date;
  final List<UploadHistoryEntry> entries;

  int get totalBytes => entries.fold<int>(
    0,
    (int sum, UploadHistoryEntry entry) => sum + entry.fileSize,
  );
}

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

/// Groups the history by the day the uploads were recorded on.
List<_HistoryDay> _groupByDay(List<UploadHistoryEntry> entries) {
  final Map<DateTime, List<UploadHistoryEntry>> groups =
      <DateTime, List<UploadHistoryEntry>>{};
  for (final UploadHistoryEntry entry in entries) {
    final DateTime created = entry.createdAt.toLocal();
    final DateTime day = DateTime(created.year, created.month, created.day);
    groups.putIfAbsent(day, () => <UploadHistoryEntry>[]).add(entry);
  }
  return <_HistoryDay>[
    for (final MapEntry<DateTime, List<UploadHistoryEntry>> group
        in groups.entries)
      _HistoryDay(date: group.key, entries: group.value),
  ];
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

/// Formats a day as `Today`, `Yesterday` or `yyyy-MM-dd`.
String _dayLabel(DateTime date) {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime target = DateTime(date.year, date.month, date.day);
  final int difference = today.difference(target).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  final String month = date.month.toString().padLeft(2, '0');
  final String day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
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
