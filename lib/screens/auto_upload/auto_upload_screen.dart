import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/models.dart';
import '../../providers/config_providers.dart';
import '../../data/database.dart';
import '../../services/auto_upload_service.dart';
import '../../widgets/common.dart';

/// Smart Auto Upload: watched folders, rules and scheduling.
class AutoUploadScreen extends ConsumerStatefulWidget {
  const AutoUploadScreen({super.key});

  @override
  ConsumerState<AutoUploadScreen> createState() => _AutoUploadScreenState();
}

class _AutoUploadScreenState extends ConsumerState<AutoUploadScreen> {
  bool _scanning = false;
  int _lastScanned = 0;
  int _lastFound = 0;

  @override
  Widget build(BuildContext context) {
    final List<WatchedFolder> folders =
        ref.watch(watchedFoldersProvider).value ?? const <WatchedFolder>[];
    final List<AutoUploadRule> rules =
        ref.watch(autoUploadRulesProvider).value ?? const <AutoUploadRule>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Smart Auto Upload')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: <Widget>[
            SectionCard(
              title: 'Scan now',
              subtitle: _lastScanned == 0
                  ? 'No scan has run yet'
                  : 'Last scan found $_lastFound new file(s)',
              icon: Icons.radar_rounded,
              trailing: _scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Scanning looks for files that are not in the library yet. '
                    'Fully automatic rules send them immediately, semi-automatic '
                    'rules ask you first.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _scanning ? null : _scan,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Scan watched folders'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Watched folders',
              subtitle: '${folders.length} folder(s)',
              icon: Icons.folder_special_rounded,
              trailing: IconButton(
                tooltip: 'Add folder',
                onPressed: _addFolder,
                icon: const Icon(Icons.add_rounded),
              ),
              child: folders.isEmpty
                  ? Text(
                      'No folder is being watched. Add one to detect new media '
                      'automatically.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : Column(
                      children: <Widget>[
                        for (final WatchedFolder folder in folders)
                          _FolderRow(folder: folder),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Automatic upload rules',
              subtitle: '${rules.length} rule(s)',
              icon: Icons.auto_awesome_rounded,
              trailing: IconButton(
                tooltip: 'Add rule',
                onPressed: () => _editRule(null),
                icon: const Icon(Icons.add_rounded),
              ),
              child: rules.isEmpty
                  ? Text(
                      'No rule yet. A rule binds a watched folder to one or '
                      'more destinations and decides how new files are sent.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  : Column(
                      children: <Widget>[
                        for (final AutoUploadRule rule in rules)
                          _RuleRow(rule: rule),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            const SectionCard(
              title: 'Background limits',
              icon: Icons.info_outline_rounded,
              child: Text(
                'Android limits how long an app may run in the background. The '
                'app keeps uploads alive with a foreground service while a '
                'transfer is running, and it asks for the battery optimisation '
                'exemption so that long transfers are not killed. Folders are '
                'polled when the app runs and when the periodic scan is '
                'triggered — no promise of unlimited background scanning is '
                'made.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final AutoScanResult result = await AutoUploadService.instance.scan();
      final int uploaded = await AutoUploadService.instance.applyRules(result);
      if (!mounted) return;
      setState(() {
        _lastScanned = result.foldersScanned;
        _lastFound = result.newFiles.length;
      });
      ref.invalidate(mediaLibraryProvider);
      showAppSnack(
        context,
        'Scanned ${result.foldersScanned} folder(s), found ${result.newFiles.length} new file(s), '
        'sent $uploaded automatically.',
        isSuccess: true,
      );
    } catch (error) {
      if (mounted) {
        showAppSnack(context, 'Scan failed: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _addFolder() async {
    try {
      final String? folder = await FilePicker.getDirectoryPath();
      if (folder == null || folder.isEmpty) return;

      // A Storage Access Framework tree URI is stored as-is so that the
      // folder keeps being watched across app restarts.
      final String label = folder.startsWith('/')
          ? folder.split('/').last
          : 'Selected folder';

      await AppDatabase.instance.upsertWatchedFolder(
        WatchedFolder(
          id: 'folder-${DateTime.now().microsecondsSinceEpoch}',
          path: folder,
          enabled: true,
          createdAt: DateTime.now(),
          name: label,
        ),
      );
      ref.invalidate(watchedFoldersProvider);
    } catch (error) {
      if (mounted) {
        showAppSnack(
          context,
          'Could not add the folder: $error',
          isError: true,
        );
      }
    }
  }

  Future<void> _editRule(AutoUploadRule? rule) async {
    final List<Destination> destinations =
        ref.watch(destinationsProvider).value ?? const <Destination>[];
    if (destinations.isEmpty) {
      showAppSnack(
        context,
        'Add a destination in the Distribution tab before creating a rule.',
        isError: true,
      );
      return;
    }

    final List<WatchedFolder> folders =
        ref.watch(watchedFoldersProvider).value ?? const <WatchedFolder>[];

    String name = rule?.name ?? '';
    String mode = rule?.mode ?? AutoUploadMode.fullyAutomatic.key;
    String duplicatePolicy = rule?.duplicatePolicy ?? DuplicatePolicy.skip.key;
    int maxFileMb = rule?.maxFileMb ?? 0;
    String includePatterns = rule?.includePatterns ?? '';
    String excludePatterns = rule?.excludePatterns ?? '';
    bool scheduleEnabled = rule?.scheduleEnabled ?? false;
    int scheduleStart = rule?.scheduleStartMinutes ?? 0;
    int scheduleDuration = rule?.scheduleDurationMinutes ?? 60;
    String? watchedFolderId = rule?.watchedFolderId;
    Set<String> selected = Set<String>.of(rule?.destinationIds ?? <String>[]);
    if (selected.isEmpty && destinations.isNotEmpty) {
      selected = <String>{destinations.first.id};
    }

    final bool? saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 18,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      rule == null ? 'New rule' : 'Edit rule',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: TextEditingController(text: name),
                      onChanged: (String value) => name = value,
                      decoration: const InputDecoration(labelText: 'Rule name'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: mode,
                      decoration: const InputDecoration(
                        labelText: 'Upload mode',
                      ),
                      items: AutoUploadMode.values
                          .map(
                            (AutoUploadMode m) => DropdownMenuItem<String>(
                              value: m.key,
                              child: Text(m.label),
                            ),
                          )
                          .toList(),
                      onChanged: (String? value) =>
                          setSheetState(() => mode = value ?? mode),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: duplicatePolicy,
                      decoration: const InputDecoration(
                        labelText: 'Duplicate handling',
                      ),
                      items: DuplicatePolicy.values
                          .map(
                            (DuplicatePolicy p) => DropdownMenuItem<String>(
                              value: p.key,
                              child: Text(p.label),
                            ),
                          )
                          .toList(),
                      onChanged: (String? value) => setSheetState(
                        () => duplicatePolicy = value ?? duplicatePolicy,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      initialValue: watchedFolderId,
                      decoration: const InputDecoration(
                        labelText: 'Watched folder',
                      ),
                      items: <DropdownMenuItem<String?>>[
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All folders'),
                        ),
                        for (final WatchedFolder folder in folders)
                          DropdownMenuItem<String?>(
                            value: folder.id,
                            child: Text(folder.name ?? folder.path),
                          ),
                      ],
                      onChanged: (String? value) =>
                          setSheetState(() => watchedFolderId = value),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: TextEditingController(text: includePatterns),
                      onChanged: (String value) => includePatterns = value,
                      decoration: const InputDecoration(
                        labelText: 'Include patterns',
                        hintText: '*.jpg, *.mp4',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: TextEditingController(text: excludePatterns),
                      onChanged: (String value) => excludePatterns = value,
                      decoration: const InputDecoration(
                        labelText: 'Exclude patterns',
                        hintText: '*.tmp, *_raw',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: TextEditingController(
                        text: maxFileMb == 0 ? '' : '$maxFileMb',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (String value) =>
                          maxFileMb = int.tryParse(value.trim()) ?? 0,
                      decoration: const InputDecoration(
                        labelText: 'Maximum file size in MB',
                        hintText: '0 = no limit',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Destinations',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final Destination destination in destinations)
                          FilterChip(
                            selected: selected.contains(destination.id),
                            onSelected: (bool value) => setSheetState(() {
                              if (value) {
                                selected.add(destination.id);
                              } else {
                                selected.remove(destination.id);
                              }
                            }),
                            label: Text(destination.name),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      value: scheduleEnabled,
                      onChanged: (bool value) =>
                          setSheetState(() => scheduleEnabled = value),
                      title: const Text('Restrict to a time window'),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (scheduleEnabled) ...<Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(
                                text: '$scheduleStart',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (String value) => setSheetState(
                                () => scheduleStart =
                                    int.tryParse(value.trim()) ?? 0,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Start (minutes after midnight)',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: TextEditingController(
                                text: '$scheduleDuration',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (String value) => setSheetState(
                                () => scheduleDuration =
                                    int.tryParse(value.trim()) ?? 60,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Duration (min)',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              Navigator.of(context).pop(true);
                            },
                            child: const Text('Save rule'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (saved != true) return;

    await AppDatabase.instance.upsertAutoUploadRule(
      AutoUploadRule(
        id: rule?.id ?? 'rule-${DateTime.now().microsecondsSinceEpoch}',
        name: name.trim().isEmpty ? 'Untitled rule' : name.trim(),
        enabled: rule?.enabled ?? true,
        mode: mode,
        destinationIds: selected.toList(),
        createdAt: rule?.createdAt ?? DateTime.now(),
        watchedFolderId: watchedFolderId,
        includePatterns: includePatterns,
        excludePatterns: excludePatterns,
        maxFileMb: maxFileMb,
        priority: rule?.priority ?? 0,
        duplicatePolicy: duplicatePolicy,
        retryLimit: rule?.retryLimit ?? 3,
        scheduleEnabled: scheduleEnabled,
        scheduleStartMinutes: scheduleStart,
        scheduleDurationMinutes: scheduleDuration,
        weekdays: rule?.weekdays ?? '',
      ),
    );
    ref.invalidate(autoUploadRulesProvider);
    if (mounted) showAppSnack(context, 'Rule saved.', isSuccess: true);
  }
}

class _FolderRow extends ConsumerWidget {
  const _FolderRow({required this.folder});

  final WatchedFolder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.folder_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  folder.name ?? folder.path,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  folder.lastScanAt == null
                      ? 'Never scanned'
                      : 'Last scanned ${_ago(folder.lastScanAt!)}',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          Switch(
            value: folder.enabled,
            onChanged: (bool value) async {
              await AppDatabase.instance.upsertWatchedFolder(
                folder.copyWith(enabled: value),
              );
              ref.invalidate(watchedFoldersProvider);
            },
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: () async {
              final bool confirmed = await showConfirmDialog(
                context,
                title: 'Stop watching this folder?',
                message:
                    'The folder stays on the device, only the monitoring '
                    'rule is removed.',
                confirmLabel: 'Remove',
                destructive: true,
              );
              if (!confirmed) return;
              await AppDatabase.instance.deleteWatchedFolder(folder.id);
              ref.invalidate(watchedFoldersProvider);
            },
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime time) {
    final Duration difference = DateTime.now().difference(time);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}

class _RuleRow extends ConsumerWidget {
  const _RuleRow({required this.rule});

  final AutoUploadRule rule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.auto_awesome_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(rule.name, style: theme.textTheme.bodyLarge),
                Text(
                  '${AutoUploadMode.fromKey(rule.mode).label} · '
                  '${rule.destinationIds.length} destination(s)',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          Switch(
            value: rule.enabled,
            onChanged: (bool value) async {
              await AppDatabase.instance.upsertAutoUploadRule(
                rule.copyWith(enabled: value),
              );
              ref.invalidate(autoUploadRulesProvider);
            },
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: () {
              // Editing is handled by the parent screen through the callback
              // registered in the build method.
              final _AutoUploadScreenState? state = context
                  .findAncestorStateOfType<_AutoUploadScreenState>();
              state?._editRule(rule);
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
