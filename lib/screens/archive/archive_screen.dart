import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../providers/config_providers.dart';
import '../../services/archive_service.dart';
import '../../widgets/common.dart';

/// The current archive summary.
final FutureProvider<ArchiveSummary> archiveSummaryProvider =
    FutureProvider<ArchiveSummary>(
      (Ref ref) => ArchiveService.instance.summary(),
    );

/// The configured automatic archive rules.
final FutureProvider<List<ArchiveRule>> archiveRulesProvider =
    FutureProvider<List<ArchiveRule>>(
      (Ref ref) => AppDatabase.instance.listArchiveRules(),
    );

/// The archive operation history.
final FutureProvider<List<ArchiveOperation>> archiveOperationsProvider =
    FutureProvider<List<ArchiveOperation>>(
      (Ref ref) => AppDatabase.instance.listArchiveOperations(),
    );

/// The sort order applied to the archived media list.
enum ArchiveSortOrder {
  dateDesc('Newest first'),
  dateAsc('Oldest first'),
  sizeDesc('Largest first'),
  sizeAsc('Smallest first');

  const ArchiveSortOrder(this.label);

  final String label;
}

/// The active filters of the archived media list.
class ArchiveFilter {
  const ArchiveFilter({
    this.search = '',
    this.categories = const <ArchiveCategory>{},
    this.sort = ArchiveSortOrder.dateDesc,
  });

  final String search;
  final Set<ArchiveCategory> categories;
  final ArchiveSortOrder sort;

  ArchiveFilter copyWith({
    String? search,
    Set<ArchiveCategory>? categories,
    ArchiveSortOrder? sort,
  }) {
    return ArchiveFilter(
      search: search ?? this.search,
      categories: categories ?? this.categories,
      sort: sort ?? this.sort,
    );
  }
}

/// Controls the filters of the archived media list.
class ArchiveFilterNotifier extends Notifier<ArchiveFilter> {
  @override
  ArchiveFilter build() => const ArchiveFilter();

  /// Stores the free text search applied to the archived file names.
  void setSearch(String value) => state = state.copyWith(search: value);

  /// Adds or removes a category from the filter.
  void toggleCategory(ArchiveCategory category) {
    final Set<ArchiveCategory> categories = Set<ArchiveCategory>.of(
      state.categories,
    );
    if (!categories.remove(category)) {
      categories.add(category);
    }
    state = state.copyWith(categories: categories);
  }

  /// Applies a new sort order.
  void setSort(ArchiveSortOrder sort) => state = state.copyWith(sort: sort);
}

/// The filter state of the archived media list.
final NotifierProvider<ArchiveFilterNotifier, ArchiveFilter>
archiveFilterProvider = NotifierProvider<ArchiveFilterNotifier, ArchiveFilter>(
  ArchiveFilterNotifier.new,
);

/// The archive manager — overview, archived media, rules and history.
///
/// Archiving is a logical operation by default: the library entry is flagged
/// as archived and the original file stays untouched on disk. Moving the file
/// into the app archive folder is an opt-in that the user has to enable.
class ArchiveScreen extends ConsumerWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ArchiveSummary? summary = ref.watch(archiveSummaryProvider).value;
    final List<ArchiveRule> rules =
        ref.watch(archiveRulesProvider).value ?? const <ArchiveRule>[];
    final List<ArchiveOperation> operations =
        ref.watch(archiveOperationsProvider).value ??
        const <ArchiveOperation>[];
    final List<ArchiveRecord> records =
        ref.watch(archiveProvider).value ?? const <ArchiveRecord>[];
    final ArchiveFilter filter = ref.watch(archiveFilterProvider);
    final List<ArchiveRecord> filtered = _applyFilter(records, filter);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Archive manager'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _refresh(ref),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _refresh(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: <Widget>[
              _ArchiveSummaryCard(summary: summary),
              const SizedBox(height: 14),
              const _ArchiveActionsCard(),
              const SizedBox(height: 14),
              _ArchiveRecordsCard(records: filtered, total: records.length),
              const SizedBox(height: 14),
              _ArchiveRulesCard(rules: rules),
              const SizedBox(height: 14),
              _ArchiveOperationsCard(operations: operations),
            ],
          ),
        ),
      ),
    );
  }

  /// Reloads every archive source.
  static void _refresh(WidgetRef ref) {
    ref.invalidate(archiveSummaryProvider);
    ref.invalidate(archiveRulesProvider);
    ref.invalidate(archiveOperationsProvider);
    ref.invalidate(archiveProvider);
    ref.invalidate(mediaLibraryProvider);
  }

  /// Applies the search, category and sort filters to the archive records.
  static List<ArchiveRecord> _applyFilter(
    List<ArchiveRecord> records,
    ArchiveFilter filter,
  ) {
    final String query = filter.search.trim().toLowerCase();
    final List<ArchiveRecord> result = records.where((ArchiveRecord record) {
      if (query.isNotEmpty && !record.fileName.toLowerCase().contains(query)) {
        return false;
      }
      if (filter.categories.isNotEmpty) {
        final bool matches = filter.categories.any(
          (ArchiveCategory category) => _matchesCategory(record, category),
        );
        if (!matches) return false;
      }
      return true;
    }).toList();

    switch (filter.sort) {
      case ArchiveSortOrder.dateDesc:
        result.sort(
          (ArchiveRecord a, ArchiveRecord b) =>
              b.archivedAt.compareTo(a.archivedAt),
        );
        break;
      case ArchiveSortOrder.dateAsc:
        result.sort(
          (ArchiveRecord a, ArchiveRecord b) =>
              a.archivedAt.compareTo(b.archivedAt),
        );
        break;
      case ArchiveSortOrder.sizeDesc:
        result.sort(
          (ArchiveRecord a, ArchiveRecord b) =>
              b.fileSize.compareTo(a.fileSize),
        );
        break;
      case ArchiveSortOrder.sizeAsc:
        result.sort(
          (ArchiveRecord a, ArchiveRecord b) =>
              a.fileSize.compareTo(b.fileSize),
        );
        break;
    }
    return result;
  }
}

/// The overview card with the archive totals and the category breakdown.
class _ArchiveSummaryCard extends StatelessWidget {
  const _ArchiveSummaryCard({required this.summary});

  final ArchiveSummary? summary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ArchiveSummary? data = summary;
    final Map<String, int> byCategory =
        data?.byCategory ?? const <String, int>{};

    return SectionCard(
      title: 'Archive overview',
      subtitle: data == null
          ? 'Loading…'
          : '${Formatters.count(data.totalFiles)} archived files',
      icon: Icons.inventory_2_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MetricRow(
            label: 'Total archived files',
            value: Formatters.count(data?.totalFiles ?? 0),
          ),
          MetricRow(
            label: 'Total archive storage usage',
            value: Formatters.bytes(data?.totalBytes ?? 0),
          ),
          MetricRow(
            label: 'Restorable files',
            value: Formatters.count(data?.restorableFiles ?? 0),
          ),
          MetricRow(
            label: 'Last archive date',
            value: data?.lastArchiveAt == null
                ? '—'
                : _formatDate(data!.lastArchiveAt!),
          ),
          const SizedBox(height: 6),
          const Divider(),
          const SizedBox(height: 6),
          Text('By category', style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          for (final ArchiveCategory category in ArchiveCategory.values)
            MetricRow(
              label: category.label,
              value: Formatters.count(_categoryCount(byCategory, category)),
            ),
        ],
      ),
    );
  }
}

/// The archive actions: archive selected and archive all completed.
class _ArchiveActionsCard extends ConsumerWidget {
  const _ArchiveActionsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: 'Actions',
      subtitle: 'Archive uploaded media',
      icon: Icons.archive_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () => _archiveSelected(context, ref),
                icon: const Icon(Icons.checklist_rounded, size: 18),
                label: const Text('Archive selected'),
              ),
              FilledButton.icon(
                onPressed: () => _archiveAllCompleted(context, ref),
                icon: const Icon(Icons.inventory_2_rounded, size: 18),
                label: const Text('Archive all completed'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Archiving is logical: the library entry is flagged as archived and '
            'the file stays where it is. Moving the file into the app archive '
            'folder is opt-in and only applies to the files you pick.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  /// Opens the picker with the uploaded media that is not archived yet.
  Future<void> _archiveSelected(BuildContext context, WidgetRef ref) async {
    final List<MediaLibraryEntry> media =
        ref.read(mediaLibraryProvider).value ?? const <MediaLibraryEntry>[];
    final List<MediaLibraryEntry> candidates = media
        .where(
          (MediaLibraryEntry entry) =>
              entry.status == MediaStatus.uploaded.key && !entry.isArchived,
        )
        .toList();

    if (candidates.isEmpty) {
      showAppSnack(
        context,
        'No uploaded media is waiting to be archived.',
        isError: true,
      );
      return;
    }

    final _ArchiveSelection? selection = await showDialog<_ArchiveSelection>(
      context: context,
      builder: (BuildContext context) =>
          _ArchivePickerDialog(entries: candidates),
    );
    if (selection == null || selection.entries.isEmpty) return;

    int archived = 0;
    int moved = 0;
    for (final MediaLibraryEntry entry in selection.entries) {
      await ArchiveService.instance.archiveMedia(
        entry,
        moveFile: selection.moveFiles,
      );
      archived++;
      if (selection.moveFiles) {
        final MediaLibraryEntry? updated = await AppDatabase.instance.mediaById(
          entry.id,
        );
        if (updated != null && updated.path != entry.path) moved++;
      }
    }
    ArchiveScreen._refresh(ref);
    if (!context.mounted) return;
    showAppSnack(
      context,
      selection.moveFiles
          ? 'Archived ${Formatters.count(archived)} files · '
                '${Formatters.count(moved)} moved'
          : 'Archived ${Formatters.count(archived)} files',
      isSuccess: true,
    );
  }

  /// Archives every media entry that finished uploading.
  Future<void> _archiveAllCompleted(BuildContext context, WidgetRef ref) async {
    final int archived = await ArchiveService.instance.archiveAllCompleted();
    ArchiveScreen._refresh(ref);
    if (!context.mounted) return;
    showAppSnack(
      context,
      'Archived ${Formatters.count(archived)} completed file'
      '${archived == 1 ? '' : 's'}',
      isSuccess: true,
    );
  }
}

/// The search field filtering the archived media by file name.
class _ArchiveSearchField extends ConsumerStatefulWidget {
  const _ArchiveSearchField();

  @override
  ConsumerState<_ArchiveSearchField> createState() =>
      _ArchiveSearchFieldState();
}

class _ArchiveSearchFieldState extends ConsumerState<_ArchiveSearchField> {
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
      onChanged: (String value) =>
          ref.read(archiveFilterProvider.notifier).setSearch(value),
      decoration: InputDecoration(
        hintText: 'Search archived media',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _controller.clear();
                  ref.read(archiveFilterProvider.notifier).setSearch('');
                  setState(() {});
                },
              ),
      ),
    );
  }
}

/// The list of archived files with the filters and the sort menu.
class _ArchiveRecordsCard extends ConsumerWidget {
  const _ArchiveRecordsCard({required this.records, required this.total});

  final List<ArchiveRecord> records;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ArchiveFilter filter = ref.watch(archiveFilterProvider);

    return SectionCard(
      title: 'Archived media',
      subtitle:
          '${Formatters.count(records.length)} of '
          '${Formatters.count(total)} archived files',
      icon: Icons.perm_media_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _ArchiveSearchField(),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final ArchiveCategory category in ArchiveCategory.values)
                FilterChip(
                  label: Text(category.label),
                  selected: filter.categories.contains(category),
                  showCheckmark: false,
                  onSelected: (bool selected) => ref
                      .read(archiveFilterProvider.notifier)
                      .toggleCategory(category),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Text('Sort', style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              PopupMenuButton<ArchiveSortOrder>(
                tooltip: 'Sort archived media',
                initialValue: filter.sort,
                onSelected: (ArchiveSortOrder value) =>
                    ref.read(archiveFilterProvider.notifier).setSort(value),
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<ArchiveSortOrder>>[
                      for (final ArchiveSortOrder order
                          in ArchiveSortOrder.values)
                        PopupMenuItem<ArchiveSortOrder>(
                          value: order,
                          child: Text(order.label),
                        ),
                    ],
                child: Chip(label: Text(filter.sort.label)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (records.isEmpty)
            const SizedBox(
              height: 180,
              child: EmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Nothing archived yet',
                message: 'No archived file matches the current filters.',
              ),
            )
          else
            for (final ArchiveRecord record in records) ...<Widget>[
              _ArchiveRecordTile(record: record),
              const Divider(),
            ],
        ],
      ),
    );
  }
}

/// A single archived file with its actions.
class _ArchiveRecordTile extends ConsumerWidget {
  const _ArchiveRecordTile({required this.record});

  final ArchiveRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final String? openPath = record.originalPath ?? record.archivePath;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  iconForCategory(record.category),
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      Formatters.fileName(record.fileName),
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Formatters.bytes(record.fileSize)} · '
                      'Archived ${_formatDate(record.archivedAt)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      record.archivePath != null &&
                              record.archivePath!.isNotEmpty
                          ? 'File moved into the archive folder'
                          : 'File kept at its original location',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (record.isRestored)
                const StatusPill(
                  label: 'Restored',
                  color: AppConstants.colorSuccess,
                  icon: Icons.undo_rounded,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              TextButton(
                onPressed: record.isRestored
                    ? null
                    : () => _restore(context, ref, record),
                child: const Text('Restore'),
              ),
              TextButton(
                onPressed: () => _delete(context, ref, record),
                style: TextButton.styleFrom(
                  foregroundColor: AppConstants.colorError,
                ),
                child: const Text('Delete permanently'),
              ),
              TextButton(
                onPressed: openPath == null
                    ? null
                    : () => _openOriginal(context, openPath),
                child: const Text('Open original'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Restores the archived entry and brings the file back to the library.
  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    ArchiveRecord record,
  ) async {
    await ArchiveService.instance.restore(record.id);
    ArchiveScreen._refresh(ref);
    if (!context.mounted) return;
    showAppSnack(context, '${record.fileName} was restored', isSuccess: true);
  }

  /// Deletes the archive record after an explicit confirmation.
  ///
  /// The dialog states what is deleted. The file on the device is only
  /// deleted when the user ticks the extra option.
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ArchiveRecord record,
  ) async {
    final bool? deleteFile = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) =>
          _PermanentDeleteDialog(fileName: record.fileName),
    );
    if (deleteFile == null || !context.mounted) return;

    await ArchiveService.instance.permanentlyDelete(
      record.id,
      deleteFile: deleteFile,
    );
    ArchiveScreen._refresh(ref);
    if (!context.mounted) return;
    showAppSnack(
      context,
      deleteFile
          ? 'The archive record and the file were deleted'
          : 'The archive record was deleted',
      isSuccess: true,
    );
  }

  /// Opens the original file with the platform viewer.
  Future<void> _openOriginal(BuildContext context, String path) async {
    final OpenResult result = await OpenFilex.open(path);
    if (!context.mounted) return;
    if (result.type != ResultType.done) {
      showAppSnack(
        context,
        'The file could not be opened: ${result.message}',
        isError: true,
      );
    }
  }
}

/// The automatic archive rules and the dialog used to create them.
class _ArchiveRulesCard extends ConsumerWidget {
  const _ArchiveRulesCard({required this.rules});

  final List<ArchiveRule> rules;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: 'Archive rules',
      subtitle: rules.isEmpty ? 'No rule configured' : '${rules.length} rules',
      icon: Icons.rule_rounded,
      trailing: IconButton(
        tooltip: 'Add rule',
        icon: const Icon(Icons.add_rounded),
        onPressed: () => _openRuleDialog(context, ref),
      ),
      child: rules.isEmpty
          ? Text(
              'Add a rule to archive media automatically once it was uploaded.',
              style: theme.textTheme.bodySmall,
            )
          : Column(
              children: <Widget>[
                for (final ArchiveRule rule in rules)
                  _ruleTile(context, ref, rule),
              ],
            ),
    );
  }

  Widget _ruleTile(BuildContext context, WidgetRef ref, ArchiveRule rule) {
    final ThemeData theme = Theme.of(context);
    final List<String> conditions = <String>[
      if (rule.archiveAfterUpload) 'Archive right after a successful upload',
      if (rule.archiveAfterDays != null)
        'Archive ${rule.archiveAfterDays} days after the upload',
      if (rule.maxAgeDays != null) 'Maximum age of ${rule.maxAgeDays} days',
      if (rule.categories.trim().isNotEmpty)
        'Categories: ${rule.categories.split(',').join(', ')}',
      if (rule.excludeFavorites) 'Skip favourites',
      if (rule.excludePendingReview) 'Skip entries pending review',
      if (rule.excludeFolders.trim().isNotEmpty)
        'Excluded folders: ${rule.excludeFolders}',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(rule.name, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  conditions.isEmpty
                      ? 'No condition set'
                      : conditions.join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => _openRuleDialog(context, ref, rule: rule),
                    child: const Text('Edit'),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: rule.enabled,
            onChanged: (bool value) async {
              await AppDatabase.instance.upsertArchiveRule(
                rule.copyWith(enabled: value),
              );
              ref.invalidate(archiveRulesProvider);
            },
          ),
        ],
      ),
    );
  }

  /// Opens the rule dialog in create or in edit mode.
  Future<void> _openRuleDialog(
    BuildContext context,
    WidgetRef ref, {
    ArchiveRule? rule,
  }) async {
    final ArchiveRule? updated = await showDialog<ArchiveRule>(
      context: context,
      builder: (BuildContext context) => _ArchiveRuleDialog(rule: rule),
    );
    if (updated == null) return;
    await AppDatabase.instance.upsertArchiveRule(updated);
    ref.invalidate(archiveRulesProvider);
  }
}

/// The history of the archive operations.
class _ArchiveOperationsCard extends StatelessWidget {
  const _ArchiveOperationsCard({required this.operations});

  final List<ArchiveOperation> operations;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: 'Archive operation history',
      subtitle: operations.isEmpty
          ? 'No operation yet'
          : '${operations.length} recent operations',
      icon: Icons.history_rounded,
      child: operations.isEmpty
          ? Text(
              'Every archive, restore or deletion is listed here.',
              style: theme.textTheme.bodySmall,
            )
          : Column(
              children: <Widget>[
                for (final ArchiveOperation operation in operations)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _operationLabel(operation.operation),
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          '${Formatters.count(operation.itemCount)} item'
                          '${operation.itemCount == 1 ? '' : 's'} · '
                          '${_formatDate(operation.createdAt)}'
                          '${operation.detail == null || operation.detail!.isEmpty ? '' : ' · ${operation.detail!}'}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The files that the user picked in the archive picker.
class _ArchiveSelection {
  const _ArchiveSelection({required this.entries, required this.moveFiles});

  final List<MediaLibraryEntry> entries;

  /// Whether the files are moved into the app archive folder.
  final bool moveFiles;
}

/// The picker used to select the media that must be archived.
class _ArchivePickerDialog extends StatefulWidget {
  const _ArchivePickerDialog({required this.entries});

  final List<MediaLibraryEntry> entries;

  @override
  State<_ArchivePickerDialog> createState() => _ArchivePickerDialogState();
}

class _ArchivePickerDialogState extends State<_ArchivePickerDialog> {
  final Set<String> _selected = <String>{};
  bool _moveFiles = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Archive selected media'),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView.builder(
                itemCount: widget.entries.length,
                itemBuilder: (BuildContext context, int index) {
                  final MediaLibraryEntry entry = widget.entries[index];
                  return CheckboxListTile(
                    value: _selected.contains(entry.id),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    secondary: Icon(iconForCategory(entry.category)),
                    title: Text(
                      Formatters.fileName(entry.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${Formatters.bytes(entry.size)} · ${entry.category}',
                      style: theme.textTheme.bodySmall,
                    ),
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          _selected.add(entry.id);
                        } else {
                          _selected.remove(entry.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _moveFiles,
              title: const Text('Move the file to the archive folder'),
              subtitle: const Text(
                'Off by default: archiving only flags the library entry',
                style: TextStyle(fontSize: 12),
              ),
              onChanged: (bool value) => setState(() => _moveFiles = value),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _ArchiveSelection(
                    entries: widget.entries
                        .where(
                          (MediaLibraryEntry entry) =>
                              _selected.contains(entry.id),
                        )
                        .toList(),
                    moveFiles: _moveFiles,
                  ),
                ),
          child: Text('Archive ${_selected.length}'),
        ),
      ],
    );
  }
}

/// The dialog used to create or to edit an archive rule.
class _ArchiveRuleDialog extends StatefulWidget {
  const _ArchiveRuleDialog({this.rule});

  final ArchiveRule? rule;

  @override
  State<_ArchiveRuleDialog> createState() => _ArchiveRuleDialogState();
}

class _ArchiveRuleDialogState extends State<_ArchiveRuleDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _daysController;
  late final TextEditingController _foldersController;
  late bool _enabled;
  late bool _archiveAfterUpload;
  late bool _excludeFavorites;
  late bool _excludePendingReview;
  late final Set<ArchiveCategory> _categories;

  @override
  void initState() {
    super.initState();
    final ArchiveRule? rule = widget.rule;
    _nameController = TextEditingController(text: rule?.name ?? '');
    _daysController = TextEditingController(
      text: rule?.archiveAfterDays == null ? '' : '${rule!.archiveAfterDays}',
    );
    _foldersController = TextEditingController(
      text: rule?.excludeFolders ?? '',
    );
    _enabled = rule?.enabled ?? true;
    _archiveAfterUpload = rule?.archiveAfterUpload ?? true;
    _excludeFavorites = rule?.excludeFavorites ?? true;
    _excludePendingReview = rule?.excludePendingReview ?? true;
    _categories = <ArchiveCategory>{};
    final String stored = rule?.categories ?? '';
    if (stored.trim().isNotEmpty) {
      for (final String key in stored.split(',')) {
        final String trimmed = key.trim();
        if (trimmed.isEmpty) continue;
        for (final ArchiveCategory category in ArchiveCategory.values) {
          if (category.key == trimmed ||
              _mediaCategoryKey(category) == trimmed) {
            _categories.add(category);
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _daysController.dispose();
    _foldersController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        widget.rule == null ? 'Add archive rule' : 'Edit archive rule',
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Rule name'),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Archive after upload'),
                subtitle: const Text(
                  'Archive the file as soon as it is uploaded',
                ),
                value: _archiveAfterUpload,
                onChanged: (bool value) =>
                    setState(() => _archiveAfterUpload = value),
              ),
              TextField(
                controller: _daysController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Archive after days',
                  hintText: 'Leave empty to disable',
                ),
              ),
              const SizedBox(height: 14),
              Text('Categories', style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final ArchiveCategory category in ArchiveCategory.values)
                    FilterChip(
                      label: Text(category.label),
                      selected: _categories.contains(category),
                      showCheckmark: false,
                      onSelected: (bool selected) {
                        setState(() {
                          if (selected) {
                            _categories.add(category);
                          } else {
                            _categories.remove(category);
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Exclude favourites'),
                value: _excludeFavorites,
                onChanged: (bool value) =>
                    setState(() => _excludeFavorites = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Exclude pending review'),
                value: _excludePendingReview,
                onChanged: (bool value) =>
                    setState(() => _excludePendingReview = value),
              ),
              TextField(
                controller: _foldersController,
                decoration: const InputDecoration(
                  labelText: 'Exclude folders',
                  hintText: 'Comma separated folder paths',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => _save(context),
          child: Text(widget.rule == null ? 'Add rule' : 'Save'),
        ),
      ],
    );
  }

  /// Builds the rule from the dialog fields and closes the dialog.
  void _save(BuildContext context) {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      showAppSnack(context, 'The rule needs a name', isError: true);
      return;
    }

    final int? days = int.tryParse(_daysController.text.trim());
    final String categories = _categories
        .map((ArchiveCategory category) => _mediaCategoryKey(category))
        .join(',');
    final ArchiveRule? existing = widget.rule;

    final ArchiveRule rule = existing == null
        ? ArchiveRule(
            id: 'rule-${DateTime.now().microsecondsSinceEpoch}',
            name: name,
            enabled: _enabled,
            createdAt: DateTime.now(),
            archiveAfterUpload: _archiveAfterUpload,
            archiveAfterDays: days,
            categories: categories,
            excludeFavorites: _excludeFavorites,
            excludeFolders: _foldersController.text.trim(),
            excludePendingReview: _excludePendingReview,
          )
        : existing.copyWith(
            name: name,
            enabled: _enabled,
            archiveAfterUpload: _archiveAfterUpload,
            archiveAfterDays: days,
            clearArchiveAfterDays: days == null,
            categories: categories,
            excludeFavorites: _excludeFavorites,
            excludeFolders: _foldersController.text.trim(),
            excludePendingReview: _excludePendingReview,
          );

    Navigator.of(context).pop(rule);
  }
}

/// The explicit confirmation of a permanent deletion.
class _PermanentDeleteDialog extends StatefulWidget {
  const _PermanentDeleteDialog({required this.fileName});

  final String fileName;

  @override
  State<_PermanentDeleteDialog> createState() => _PermanentDeleteDialogState();
}

class _PermanentDeleteDialogState extends State<_PermanentDeleteDialog> {
  bool _deleteFile = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Delete permanently?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'The archive record of "${widget.fileName}" is deleted. The file on '
            'the device is kept unless you tick the box below. A deleted file '
            'cannot be restored.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _deleteFile,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Also delete the file from the device'),
            onChanged: (bool? value) =>
                setState(() => _deleteFile = value ?? false),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppConstants.colorError,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(_deleteFile),
          child: const Text('Delete permanently'),
        ),
      ],
    );
  }
}

/// Counts the archived files of a category.
int _categoryCount(Map<String, int> byCategory, ArchiveCategory category) {
  int total = 0;
  for (final MapEntry<String, int> entry in byCategory.entries) {
    if (entry.key == category.key || entry.key == _mediaCategoryKey(category)) {
      total += entry.value;
    }
  }
  return total;
}

/// Checks whether an archived record belongs to a category.
bool _matchesCategory(ArchiveRecord record, ArchiveCategory category) {
  return record.category == category.key ||
      record.category == _mediaCategoryKey(category);
}

/// Maps an archive category to the category key used by the media library.
String _mediaCategoryKey(ArchiveCategory category) {
  switch (category) {
    case ArchiveCategory.images:
      return 'image';
    case ArchiveCategory.videos:
      return 'video';
    case ArchiveCategory.audio:
      return 'audio';
    case ArchiveCategory.documents:
      return 'document';
    case ArchiveCategory.other:
      return 'other';
  }
}

/// Formats a date as `yyyy-MM-dd HH:mm`.
String _formatDate(DateTime date) {
  final String month = date.month.toString().padLeft(2, '0');
  final String day = date.day.toString().padLeft(2, '0');
  final String hour = date.hour.toString().padLeft(2, '0');
  final String minute = date.minute.toString().padLeft(2, '0');
  return '${date.year}-$month-$day $hour:$minute';
}

/// Maps an archive operation to a readable label.
String _operationLabel(String operation) {
  switch (operation) {
    case 'archive':
      return 'Archived';
    case 'archive_all_completed':
      return 'Archived all completed';
    case 'restore':
      return 'Restored';
    case 'permanent_delete':
      return 'Deleted permanently';
    default:
      return operation;
  }
}
