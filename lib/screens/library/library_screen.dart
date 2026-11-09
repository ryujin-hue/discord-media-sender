import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../providers/config_providers.dart';
import '../../services/archive_service.dart';
import '../../widgets/common.dart';

/// The sort orders offered by the library grid.
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

/// The media library — every file the app has tracked.
///
/// The screen offers a free text search (name *or* path), category filters,
/// a favourites filter, an archived filter, five sort orders and a responsive
/// grid of tiles. Tapping a tile opens a detail sheet with the full metadata
/// of the entry and the actions that can be applied to it.
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
    final ThemeData theme = Theme.of(context);
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
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search by name or path',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Clear search',
                    onPressed: _clearSearch,
                  ),
          ),
        ),
        const SizedBox(height: 12),
        _CategoryChips(
          selected: _category,
          onSelected: (String value) => setState(() => _category = value),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            FilterChip(
              selected: _favoritesOnly,
              avatar: Icon(
                _favoritesOnly ? Icons.star_rounded : Icons.star_border_rounded,
                size: 16,
                color: _favoritesOnly
                    ? AppConstants.colorWarning
                    : theme.colorScheme.onSurfaceVariant,
              ),
              label: const Text('Favorites'),
              onSelected: (bool value) =>
                  setState(() => _favoritesOnly = value),
            ),
            const SizedBox(width: 8),
            FilterChip(
              selected: _archivedOnly,
              avatar: Icon(
                _archivedOnly
                    ? Icons.inventory_2_rounded
                    : Icons.inventory_2_outlined,
                size: 16,
                color: _archivedOnly
                    ? AppConstants.colorPrimary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              label: const Text('Archived'),
              onSelected: (bool value) => setState(() => _archivedOnly = value),
            ),
            const Spacer(),
            PopupMenuButton<_LibrarySort>(
              initialValue: _sort,
              tooltip: 'Sort library',
              onSelected: (_LibrarySort value) => setState(() => _sort = value),
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<_LibrarySort>>[
                    for (final _LibrarySort option in _LibrarySort.values)
                      PopupMenuItem<_LibrarySort>(
                        value: option,
                        child: Text(option.label),
                      ),
                  ],
              child: Chip(
                avatar: const Icon(Icons.sort_rounded, size: 16),
                label: Text(_sort.label),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (all.isEmpty)
          SizedBox(
            height: 320,
            child: EmptyState(
              icon: Icons.perm_media_outlined,
              title: 'Your library is empty',
              message:
                  'Files are added to the library automatically when you send '
                  'them to Discord from the Upload tab.',
              action: FilledButton.tonalIcon(
                onPressed: () => showAppSnack(
                  context,
                  'Open the Upload tab, pick the files you want to send and '
                  'they will appear here.',
                ),
                icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                label: const Text('How to add files'),
              ),
            ),
          )
        else if (visible.isEmpty)
          SizedBox(
            height: 320,
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No files match',
              message:
                  'No library entry matches the current search and filters.',
              action: OutlinedButton.icon(
                onPressed: () {
                  _clearSearch();
                  setState(() {
                    _category = 'all';
                    _favoritesOnly = false;
                    _archivedOnly = false;
                  });
                },
                icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                label: const Text('Clear filters'),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              childAspectRatio: 0.85,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: visible.length,
            itemBuilder: (BuildContext context, int index) {
              final MediaLibraryEntry entry = visible[index];
              return _LibraryTile(
                entry: entry,
                onOpen: () => _openDetails(entry),
                onToggleFavorite: () => _toggleFavorite(entry),
              );
            },
          ),
      ],
    );
  }
}

/// The title of the library screen together with the current item count.
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
    final String subtitle = count == total
        ? '${Formatters.count(count)} items'
        : '${Formatters.count(count)} of ${Formatters.count(total)} items';

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Media library', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 2),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppConstants.colorPrimary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.sd_storage_rounded,
                size: 14,
                color: AppConstants.colorPrimary,
              ),
              const SizedBox(width: 4),
              Text(
                Formatters.bytes(bytes),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppConstants.colorPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
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

/// A single library entry rendered as a grid tile.
class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
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

    return Card(
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    iconForCategory(entry.category),
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onToggleFavorite,
                    tooltip: entry.favorite
                        ? 'Remove from favorites'
                        : 'Add to favorites',
                    icon: Icon(
                      entry.favorite
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 19,
                      color: entry.favorite
                          ? AppConstants.colorWarning
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  entry.name,
                  style: theme.textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                Formatters.bytes(entry.size),
                style: theme.textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(
                  label: status.label,
                  color: status.color,
                  icon: status.icon,
                ),
              ),
            ],
          ),
        ),
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
          Text(_entry.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            MediaCategory.fromKey(_entry.category).label,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              StatusPill(
                label: status.label,
                color: status.color,
                icon: status.icon,
              ),
              const Spacer(),
              TextButton.icon(
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
            ],
          ),
          const SizedBox(height: 16),
          _DetailField(
            label: 'Path',
            value: _entry.path.isEmpty ? '—' : _entry.path,
          ),
          const SizedBox(height: 12),
          _DetailField(label: 'Size', value: Formatters.bytes(_entry.size)),
          const SizedBox(height: 12),
          _DetailField(label: 'MIME type', value: _entry.mimeType ?? '—'),
          const SizedBox(height: 12),
          _DetailField(
            label: 'Category',
            value: MediaCategory.fromKey(_entry.category).label,
          ),
          const SizedBox(height: 12),
          _DetailField(label: 'Status', value: status.label),
          const SizedBox(height: 12),
          _DetailField(
            label: 'Favorite',
            value: _entry.favorite ? 'Yes' : 'No',
          ),
          const SizedBox(height: 12),
          _DetailField(label: 'Added', value: _formatTimestamp(_entry.addedAt)),
          const SizedBox(height: 12),
          _DetailField(
            label: 'Modified',
            value: _formatTimestamp(_entry.modifiedAt),
          ),
          const SizedBox(height: 12),
          _DetailField(
            label: 'Last activity',
            value: _formatTimestamp(_entry.lastActivityAt),
          ),
          const SizedBox(height: 12),
          _DetailField(
            label: 'SHA-256',
            value: _entry.sha256 ?? 'Not calculated yet',
            monospace: true,
            copyable: _entry.sha256 != null,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  showAppSnack(
                    context,
                    'Use the Upload tab to send this file to Discord.',
                  );
                },
                icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                label: const Text('Upload to Discord'),
              ),
              OutlinedButton.icon(
                onPressed: _archive,
                icon: const Icon(Icons.inventory_2_outlined, size: 18),
                label: const Text('Archive'),
              ),
              OutlinedButton.icon(
                onPressed: _delete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppConstants.colorError,
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete from library'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A labelled value row inside the detail sheet.
///
/// Long values (paths, hashes) are selectable and can optionally be copied to
/// the clipboard.
class _DetailField extends StatelessWidget {
  const _DetailField({
    required this.label,
    required this.value,
    this.monospace = false,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool monospace;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? valueStyle = monospace
        ? theme.textTheme.bodyMedium?.copyWith(
            fontFamily: 'monospace',
            fontSize: 12,
          )
        : theme.textTheme.bodyLarge;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: SelectableText(value, style: valueStyle)),
            if (copyable)
              IconButton(
                tooltip: 'Copy $label',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  showAppSnack(
                    context,
                    '$label copied to clipboard',
                    isSuccess: true,
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
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
