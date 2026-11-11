import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../providers/config_providers.dart';
import '../../services/archive_service.dart';
import '../../widgets/common.dart';
import '../../widgets/library_helpers.dart';

/// The sort orders offered by the library list.
enum _LibrarySort {
  newest('Newest'),
  name('Name'),
  sizeAsc('Size ↑'),
  sizeDesc('Size ↓'),
  date('Date');

  const _LibrarySort(this.label);

  /// The label shown inside the sort menu.
  final String label;
}

/// The media library — a local index of every file the app has tracked.
///
/// The screen offers a free text search (name *or* path), category filters,
/// a favourites filter, an archived filter, five sort orders and a dense list
/// of entries. Tapping an entry opens a detail sheet with the path, the
/// SHA-256 digest and the actions that can be applied to it.
///
/// The library is a *local* index. It lives in the database of the device, the
/// files stay on the device and no copy of the index exists on a server.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(mediaLibraryProvider);
            await ref.read(mediaLibraryProvider.future);
          },
          child: const _LibraryBody(),
        ),
      ),
    );
  }
}

/// The stateful body of the [LibraryScreen].
///
/// It owns the search query, the active filters and the sort order.
class _LibraryBody extends ConsumerStatefulWidget {
  const _LibraryBody();

  @override
  ConsumerState<_LibraryBody> createState() => _LibraryBodyState();
}

class _LibraryBodyState extends ConsumerState<_LibraryBody> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  String _query = '';
  List<MediaLibraryEntry>? _searchResults;
  String _category = 'all';
  bool _favoritesOnly = false;
  bool _archivedOnly = false;
  _LibrarySort _sort = _LibrarySort.newest;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  /// Runs the search query against the database and stores the result.
  Future<void> _runSearch(String value) async {
    final String query = value.trim();
    if (query.isEmpty) {
      if (mounted) setState(() => _searchResults = null);
      return;
    }
    final List<MediaLibraryEntry> results = await AppDatabase.instance
        .listMedia(search: query);
    if (!mounted) return;
    if (_searchController.text.trim() != query) return;
    setState(() => _searchResults = results);
  }

  /// Applies the active filters and the sort order to the given entries.
  List<MediaLibraryEntry> _applyFilters(List<MediaLibraryEntry> entries) {
    final List<MediaLibraryEntry> filtered = <MediaLibraryEntry>[];
    for (final MediaLibraryEntry entry in entries) {
      if (_category != 'all' && entry.category != _category) continue;
      if (_favoritesOnly && !entry.favorite) continue;
      if (_archivedOnly != entry.isArchived) continue;
      filtered.add(entry);
    }

    switch (_sort) {
      case _LibrarySort.newest:
        filtered.sort(
          (MediaLibraryEntry a, MediaLibraryEntry b) =>
              b.addedAt.compareTo(a.addedAt),
        );
      case _LibrarySort.name:
        filtered.sort(
          (MediaLibraryEntry a, MediaLibraryEntry b) =>
              a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case _LibrarySort.sizeAsc:
        filtered.sort(
          (MediaLibraryEntry a, MediaLibraryEntry b) =>
              a.size.compareTo(b.size),
        );
      case _LibrarySort.sizeDesc:
        filtered.sort(
          (MediaLibraryEntry a, MediaLibraryEntry b) =>
              b.size.compareTo(a.size),
        );
      case _LibrarySort.date:
        filtered.sort((MediaLibraryEntry a, MediaLibraryEntry b) {
          final DateTime aDate = a.modifiedAt ?? a.addedAt;
          final DateTime bDate = b.modifiedAt ?? b.addedAt;
          return bDate.compareTo(aDate);
        });
    }
    return filtered;
  }

  /// Reloads the library (and re-runs an active search) after a mutation.
  Future<void> _reload() async {
    ref.invalidate(mediaLibraryProvider);
    await _runSearch(_searchController.text);
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _searchResults = null);
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 250),
      () => _runSearch(value),
    );
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _query = '';
      _searchResults = null;
    });
  }

  /// Removes every filter, including the search query.
  void _resetFilters() {
    _clearSearch();
    setState(() {
      _category = 'all';
      _favoritesOnly = false;
      _archivedOnly = false;
    });
  }

  Future<void> _toggleFavorite(MediaLibraryEntry entry) async {
    await AppDatabase.instance.upsertMedia(
      entry.copyWith(favorite: !entry.favorite),
    );
    await _reload();
  }

  Future<void> _openDetails(MediaLibraryEntry entry) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (BuildContext sheetContext) => _LibraryDetails(
        entry: entry,
        onChanged: (MediaLibraryEntry updated) async {
          await AppDatabase.instance.upsertMedia(updated);
          await _reload();
        },
        onArchive: (MediaLibraryEntry target) async {
          await ArchiveService.instance.archiveMedia(target);
          await _reload();
        },
        onDelete: (MediaLibraryEntry target) async {
          await AppDatabase.instance.deleteMedia(target.id);
          await _reload();
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final List<MediaLibraryEntry> all =
        ref.watch(mediaLibraryProvider).value ?? const <MediaLibraryEntry>[];
    final List<MediaLibraryEntry> source = _searchResults ?? all;
    final List<MediaLibraryEntry> visible = _applyFilters(source);

    int totalBytes = 0;
    for (final MediaLibraryEntry entry in visible) {
      totalBytes += entry.size;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        _LibraryHeader(
          count: visible.length,
          total: all.length,
          bytes: totalBytes,
        ),
        const SizedBox(height: 14),
        _LibraryFilters(
          query: _query,
          controller: _searchController,
          category: _category,
          favoritesOnly: _favoritesOnly,
          archivedOnly: _archivedOnly,
          sort: _sort,
          onSearchChanged: _onSearchChanged,
          onClearSearch: _clearSearch,
          onCategoryChanged: (String value) =>
              setState(() => _category = value),
          onFavoritesChanged: (bool value) =>
              setState(() => _favoritesOnly = value),
          onArchivedChanged: (bool value) =>
              setState(() => _archivedOnly = value),
          onSortChanged: (_LibrarySort value) => setState(() => _sort = value),
        ),
        const SizedBox(height: 14),
        if (all.isEmpty)
          SizedBox(
            height: 300,
            child: EmptyState(
              icon: Icons.perm_media_outlined,
              title: 'No files tracked yet',
              message:
                  'Files enter this local index when they are sent to Discord '
                  'from the Upload tab.',
              action: FilledButton(
                onPressed: () => showAppSnack(
                  context,
                  'Open the Upload tab and pick the files to send. Every sent '
                  'file is added to this local index.',
                ),
                child: const Text('Add files'),
              ),
            ),
          )
        else if (visible.isEmpty)
          SizedBox(
            height: 300,
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No file matches',
              message: 'No file matches the current search and filters.',
              action: OutlinedButton(
                onPressed: _resetFilters,
                child: const Text('Clear filters'),
              ),
            ),
          )
        else
          for (final MediaLibraryEntry entry in visible)
            _LibraryEntryRow(
              entry: entry,
              onOpen: () => _openDetails(entry),
              onToggleFavorite: () => _toggleFavorite(entry),
            ),
      ],
    );
  }
}

/// The title of the library screen together with the size of the index.
class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({
    required this.count,
    required this.total,
    required this.bytes,
  });

  final int count;
  final int total;
  final int bytes;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String files = count == total
        ? '${Formatters.count(count)} files'
        : '${Formatters.count(count)} of ${Formatters.count(total)} files';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Media library', style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(
          'Local index · $files · ${Formatters.bytes(bytes)}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// The search field, the category filter and the sort order.
class _LibraryFilters extends StatelessWidget {
  const _LibraryFilters({
    required this.query,
    required this.controller,
    required this.category,
    required this.favoritesOnly,
    required this.archivedOnly,
    required this.sort,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onCategoryChanged,
    required this.onFavoritesChanged,
    required this.onArchivedChanged,
    required this.onSortChanged,
  });

  final String query;
  final TextEditingController controller;
  final String category;
  final bool favoritesOnly;
  final bool archivedOnly;
  final _LibrarySort sort;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<bool> onFavoritesChanged;
  final ValueChanged<bool> onArchivedChanged;
  final ValueChanged<_LibrarySort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SectionCard(
      title: 'Filters',
      subtitle: category == 'all'
          ? 'All categories'
          : MediaCategory.fromKey(category).label,
      icon: Icons.filter_alt_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: controller,
            onChanged: onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search by name or path',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: 'Clear search',
                      onPressed: onClearSearch,
                    ),
            ),
          ),
          const SizedBox(height: 12),
          _CategoryChips(selected: category, onSelected: onCategoryChanged),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilterChip(
                selected: favoritesOnly,
                label: const Text('Favorites'),
                onSelected: onFavoritesChanged,
              ),
              FilterChip(
                selected: archivedOnly,
                label: const Text('Archived'),
                onSelected: onArchivedChanged,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Text('Sort', style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              PopupMenuButton<_LibrarySort>(
                tooltip: 'Sort library',
                initialValue: sort,
                onSelected: onSortChanged,
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<_LibrarySort>>[
                      for (final _LibrarySort option in _LibrarySort.values)
                        PopupMenuItem<_LibrarySort>(
                          value: option,
                          child: Text(option.label),
                        ),
                    ],
                child: Chip(label: Text(sort.label)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The horizontal list of category filter chips.
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.selected, required this.onSelected});

  final String selected;
  final ValueChanged<String> onSelected;

  static final List<String> _categories = <String>[
    'all',
    MediaCategory.image.key,
    MediaCategory.video.key,
    MediaCategory.audio.key,
    MediaCategory.document.key,
    MediaCategory.other.key,
  ];

  String _labelFor(String category) {
    if (category == 'all') return 'All';
    return MediaCategory.fromKey(category).label;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final String category in _categories) ...<Widget>[
            FilterChip(
              selected: selected == category,
              label: Text(_labelFor(category)),
              onSelected: (bool value) {
                if (value) onSelected(category);
              },
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// A single library entry: thumbnail or type icon, name, size and status.
class _LibraryEntryRow extends StatelessWidget {
  const _LibraryEntryRow({
    required this.entry,
    required this.onOpen,
    required this.onToggleFavorite,
  });

  final MediaLibraryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final StatusStyle status = StatusStyle.forMediaStatus(entry.status);

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            _LibraryThumb(entry: entry),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.name,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Text(
                        Formatters.bytes(entry.size),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(width: 8),
                      StatusPill(label: status.label, color: status.color),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onToggleFavorite,
              tooltip: entry.favorite
                  ? 'Remove from favorites'
                  : 'Add to favorites',
              icon: Icon(
                entry.favorite ? Icons.star_rounded : Icons.star_border_rounded,
                size: 18,
                color: entry.favorite
                    ? AppConstants.colorWarning
                    : theme.colorScheme.onSurfaceVariant,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

/// The preview of a library entry.
///
/// The stored thumbnail is used when the entry has one, every other entry
/// falls back to the icon of its file type.
class _LibraryThumb extends StatelessWidget {
  const _LibraryThumb({required this.entry});

  final MediaLibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget placeholder = Icon(
      iconForCategory(entry.category),
      size: 20,
      color: theme.colorScheme.primary,
    );
    final String? thumbnail = entry.thumbnailPath;

    return Container(
      width: 40,
      height: 40,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: thumbnail == null || thumbnail.isEmpty
          ? placeholder
          : Image.file(
              File(thumbnail),
              fit: BoxFit.cover,
              errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stackTrace,
              ) => placeholder,
            ),
    );
  }
}

/// The detail sheet of a single library entry.
class _LibraryDetails extends StatefulWidget {
  const _LibraryDetails({
    required this.entry,
    required this.onChanged,
    required this.onArchive,
    required this.onDelete,
  });

  final MediaLibraryEntry entry;
  final Future<void> Function(MediaLibraryEntry entry) onChanged;
  final Future<void> Function(MediaLibraryEntry entry) onArchive;
  final Future<void> Function(MediaLibraryEntry entry) onDelete;

  @override
  State<_LibraryDetails> createState() => _LibraryDetailsState();
}

class _LibraryDetailsState extends State<_LibraryDetails> {
  late MediaLibraryEntry _entry = widget.entry;

  Future<void> _toggleFavorite() async {
    final MediaLibraryEntry updated = _entry.copyWith(
      favorite: !_entry.favorite,
    );
    setState(() => _entry = updated);
    await widget.onChanged(updated);
  }

  Future<void> _archive() async {
    await widget.onArchive(_entry);
    if (!mounted) return;
    showAppSnack(
      context,
      '"${_entry.name}" moved to the archive',
      isSuccess: true,
    );
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final bool confirmed = await showConfirmDialog(
      context,
      title: 'Delete from library',
      message:
          'Remove "${_entry.name}" from the library? The file itself is '
          'not deleted from the device.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    await widget.onDelete(_entry);
    if (!mounted) return;
    showAppSnack(
      context,
      '"${_entry.name}" removed from the library',
      isSuccess: true,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final StatusStyle status = StatusStyle.forMediaStatus(_entry.status);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(_entry.name, style: theme.textTheme.titleMedium),
              ),
              const SizedBox(width: 8),
              StatusPill(label: status.label, color: status.color),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${MediaCategory.fromKey(_entry.category).label} · '
            '${Formatters.bytes(_entry.size)}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _toggleFavorite,
              icon: Icon(
                _entry.favorite
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                size: 16,
                color: _entry.favorite
                    ? AppConstants.colorWarning
                    : theme.colorScheme.onSurfaceVariant,
              ),
              label: Text(_entry.favorite ? 'Favorited' : 'Add to favorites'),
            ),
          ),
          const SizedBox(height: 4),
          MetricRow(label: 'MIME type', value: _entry.mimeType ?? '—'),
          MetricRow(label: 'Added', value: _formatTimestamp(_entry.addedAt)),
          MetricRow(
            label: 'Modified',
            value: _formatTimestamp(_entry.modifiedAt),
          ),
          MetricRow(
            label: 'Last activity',
            value: _formatTimestamp(_entry.lastActivityAt),
          ),
          const SizedBox(height: 12),
          Text('Location', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          DetailValueRow(
            label: 'Path',
            value: _entry.path.isEmpty ? '—' : _entry.path,
          ),
          const SizedBox(height: 12),
          Text('Integrity', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          DetailValueRow(
            label: 'SHA-256',
            value: _entry.sha256 ?? 'Not calculated yet',
            monospace: true,
            copyable: _entry.sha256 != null,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton(
                onPressed: () {
                  showAppSnack(
                    context,
                    'Use the Upload tab to send this file to Discord.',
                  );
                  Navigator.of(context).pop();
                },
                child: const Text('Upload to Discord'),
              ),
              OutlinedButton(onPressed: _archive, child: const Text('Archive')),
              OutlinedButton(
                onPressed: _delete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppConstants.colorError,
                ),
                child: const Text('Delete from library'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Formats a timestamp as `yyyy-MM-dd HH:mm`.
String _formatTimestamp(DateTime? time) {
  if (time == null) return '—';
  final DateTime local = time.toLocal();
  final String month = local.month.toString().padLeft(2, '0');
  final String day = local.day.toString().padLeft(2, '0');
  final String hour = local.hour.toString().padLeft(2, '0');
  final String minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
