import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../providers/config_providers.dart';
import '../../services/auto_upload_service.dart';
import '../../services/quiet_hours_service.dart';
import '../../widgets/common.dart';

/// Keys of the summary of the last scan.
const String _prefScanFiles = 'set_auto_upload_scan_files';
const String _prefScanFolders = 'set_auto_upload_scan_folders';
const String _prefScanQueued = 'set_auto_upload_scan_queued';
const String _prefScanAt = 'set_auto_upload_scan_at';

/// Auto upload: watched folders, rules and scheduling.
class AutoUploadScreen extends ConsumerStatefulWidget {
  const AutoUploadScreen({super.key});

  @override
  ConsumerState<AutoUploadScreen> createState() => _AutoUploadScreenState();
}

class _AutoUploadScreenState extends ConsumerState<AutoUploadScreen> {
  bool _scanning = false;
  int _lastFiles = 0;
  int _lastFolders = 0;
  int _lastQueued = 0;
  DateTime? _lastScanAt;
  List<QuietHours> _quietHours = const <QuietHours>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Reads the summary of the last scan and the quiet hours.
  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? scannedAt = prefs.getInt(_prefScanAt);
    final List<QuietHours> quiet = await QuietHoursService.instance.list();
    if (!mounted) return;
    setState(() {
      _lastFiles = prefs.getInt(_prefScanFiles) ?? 0;
      _lastFolders = prefs.getInt(_prefScanFolders) ?? 0;
      _lastQueued = prefs.getInt(_prefScanQueued) ?? 0;
      _lastScanAt = scannedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(scannedAt);
      _quietHours = quiet;
    });
  }

  /// Stores the summary of a finished scan.
  Future<void> _storeScan(int folders, int files, int queued) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefScanFolders, folders);
    await prefs.setInt(_prefScanFiles, files);
    await prefs.setInt(_prefScanQueued, queued);
    await prefs.setInt(_prefScanAt, DateTime.now().millisecondsSinceEpoch);
  }

  @override
  Widget build(BuildContext context) {
    final List<WatchedFolder> folders =
        ref.watch(watchedFoldersProvider).value ?? const <WatchedFolder>[];
    final List<AutoUploadRule> rules =
        ref.watch(autoUploadRulesProvider).value ?? const <AutoUploadRule>[];
    final List<Destination> destinations =
        ref.watch(destinationsProvider).value ?? const <Destination>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Auto upload')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: <Widget>[
              _ScanSection(
                files: _lastFiles,
                folders: _lastFolders,
                queued: _lastQueued,
                lastScanAt: _lastScanAt,
                scanning: _scanning,
                onScan: _scan,
              ),
              const SizedBox(height: 12),
              _QuietHoursSection(
                quietHours: _quietHours,
                destinations: destinations,
              ),
              const SizedBox(height: 12),
              _FoldersSection(
                folders: folders,
                onAdd: _addFolder,
                onToggle: _toggleFolder,
                onRemove: _removeFolder,
              ),
              const SizedBox(height: 12),
              _RulesSection(
                rules: rules,
                onAdd: () => _editRule(null),
                onEdit: _editRule,
                onToggle: _toggleRule,
              ),
              const SizedBox(height: 12),
              const _LimitsSection(),
            ],
          ),
        ),
      ),
    );
  }

  /// Polls the watched folders and applies the automatic rules.
  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final AutoScanResult result = await AutoUploadService.instance.scan();
      final int queued = await AutoUploadService.instance.applyRules(result);
      await _storeScan(result.foldersScanned, result.newFiles.length, queued);
      final List<QuietHours> quiet = await QuietHoursService.instance.list();
      if (!mounted) return;
      setState(() {
        _lastFiles = result.newFiles.length;
        _lastFolders = result.foldersScanned;
        _lastQueued = queued;
        _lastScanAt = DateTime.now();
        _quietHours = quiet;
        _scanning = false;
      });
      ref.invalidate(mediaLibraryProvider);
      showAppSnack(
        context,
        'Polled ${result.foldersScanned} ${_plural(result.foldersScanned, 'folder')}, '
        '${result.newFiles.length} new ${_plural(result.newFiles.length, 'file')}, '
        '$queued queued.',
        isSuccess: true,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _scanning = false);
      showAppSnack(context, 'The scan failed: $error', isError: true);
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

  Future<void> _toggleFolder(WatchedFolder folder, bool value) async {
    await AppDatabase.instance.upsertWatchedFolder(
      folder.copyWith(enabled: value),
    );
    ref.invalidate(watchedFoldersProvider);
  }

  Future<void> _removeFolder(WatchedFolder folder) async {
    final bool confirmed = await showConfirmDialog(
      context,
      title: 'Stop watching this folder?',
      message:
          'The folder stays on the device, only the monitoring rule is '
          'removed.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed) return;
    await AppDatabase.instance.deleteWatchedFolder(folder.id);
    ref.invalidate(watchedFoldersProvider);
  }

  Future<void> _toggleRule(AutoUploadRule rule, bool value) async {
    await AppDatabase.instance.upsertAutoUploadRule(
      rule.copyWith(enabled: value),
    );
    ref.invalidate(autoUploadRulesProvider);
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

    final String? result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (BuildContext context) => _RuleSheet(rule: rule),
    );
    if (result != 'saved') return;
    ref.invalidate(autoUploadRulesProvider);
    if (mounted) showAppSnack(context, 'Rule saved.', isSuccess: true);
  }
}

// -----------------------------------------------------------------------------
// Last scan
// -----------------------------------------------------------------------------

/// The summary of the last scan and the button that starts a new one.
class _ScanSection extends StatelessWidget {
  const _ScanSection({
    required this.files,
    required this.folders,
    required this.queued,
    required this.lastScanAt,
    required this.scanning,
    required this.onScan,
  });

  final int files;
  final int folders;
  final int queued;
  final DateTime? lastScanAt;
  final bool scanning;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: 'Last scan',
      subtitle: lastScanAt == null
          ? 'No scan yet'
          : 'Polled ${_formatRelative(lastScanAt!)} ago',
      icon: Icons.radar_rounded,
      trailing: scanning
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
            'Folders are polled when the app is open and on the scheduled '
            'scan. Files that are not in the library yet are queued by the '
            'automatic rules.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          MetricRow(label: 'Files found', value: Formatters.count(files)),
          MetricRow(label: 'Folders polled', value: Formatters.count(folders)),
          MetricRow(
            label: 'Queued automatically',
            value: Formatters.count(queued),
          ),
          MetricRow(
            label: 'Last scan',
            value: lastScanAt == null ? 'never' : _formatDateTime(lastScanAt!),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: scanning ? null : onScan,
              child: Text(scanning ? 'Scanning…' : 'Scan now'),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Quiet hours
// -----------------------------------------------------------------------------

/// The destinations that the automatic upload has to skip.
class _QuietHoursSection extends StatelessWidget {
  const _QuietHoursSection({
    required this.quietHours,
    required this.destinations,
  });

  final List<QuietHours> quietHours;
  final List<Destination> destinations;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime now = DateTime.now();
    final List<QuietHours> enabled = quietHours
        .where((QuietHours hours) => hours.enabled)
        .toList();
    final int skipped = enabled
        .where((QuietHours hours) => hours.contains(now))
        .length;

    return SectionCard(
      title: 'Quiet hours',
      subtitle: enabled.isEmpty
          ? 'No quiet hours configured'
          : skipped == 0
          ? 'No destination skipped right now'
          : '$skipped ${_plural(skipped, 'destination')} skipped right now',
      icon: Icons.bedtime_outlined,
      child: enabled.isEmpty
          ? Text(
              'Quiet hours are configured per destination in the distribution '
              'screen.',
              style: theme.textTheme.bodySmall,
            )
          : Column(
              children: <Widget>[
                for (final QuietHours hours in enabled)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _QuietHoursRow(
                      hours: hours,
                      name: _destinationName(hours.destinationId),
                      active: hours.contains(now),
                    ),
                  ),
              ],
            ),
    );
  }

  /// The name of a destination, or a placeholder for a removed one.
  String _destinationName(String destinationId) {
    for (final Destination destination in destinations) {
      if (destination.id == destinationId) return destination.name;
    }
    return 'Removed destination';
  }
}

/// One destination with its quiet hours window.
class _QuietHoursRow extends StatelessWidget {
  const _QuietHoursRow({
    required this.hours,
    required this.name,
    required this.active,
  });

  final QuietHours hours;
  final String name;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(name, style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                '${hours.label} · '
                '${hours.strict ? 'manual uploads blocked' : 'auto upload only'}',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        StatusPill(
          label: active ? 'Skipped · quiet hours' : 'Quiet hours',
          color: active
              ? AppConstants.colorWarning
              : AppConstants.colorTextSecondary,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Watched folders
// -----------------------------------------------------------------------------

/// The folders that are polled by the scan.
class _FoldersSection extends StatelessWidget {
  const _FoldersSection({
    required this.folders,
    required this.onAdd,
    required this.onToggle,
    required this.onRemove,
  });

  final List<WatchedFolder> folders;
  final VoidCallback onAdd;
  final void Function(WatchedFolder folder, bool value) onToggle;
  final void Function(WatchedFolder folder) onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: 'Watched folders',
      subtitle: '${folders.length} ${_plural(folders.length, 'folder')}',
      icon: Icons.folder_special_rounded,
      trailing: IconButton(
        tooltip: 'Add folder',
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded),
      ),
      child: folders.isEmpty
          ? Text(
              'No folder is watched. Add one to poll it for new media.',
              style: theme.textTheme.bodySmall,
            )
          : Column(
              children: <Widget>[
                for (final WatchedFolder folder in folders)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                folder.name ?? folder.path,
                                style: theme.textTheme.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                folder.lastScanAt == null
                                    ? 'Never polled'
                                    : 'Polled ${_formatRelative(folder.lastScanAt!)} ago',
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: folder.enabled,
                          onChanged: (bool value) => onToggle(folder, value),
                        ),
                        TextButton(
                          onPressed: () => onRemove(folder),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// Rules
// -----------------------------------------------------------------------------

/// The rules that decide which files are uploaded automatically.
class _RulesSection extends StatelessWidget {
  const _RulesSection({
    required this.rules,
    required this.onAdd,
    required this.onEdit,
    required this.onToggle,
  });

  final List<AutoUploadRule> rules;
  final VoidCallback onAdd;
  final void Function(AutoUploadRule rule) onEdit;
  final void Function(AutoUploadRule rule, bool value) onToggle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: 'Upload rules',
      subtitle: '${rules.length} ${_plural(rules.length, 'rule')}',
      icon: Icons.auto_awesome_rounded,
      trailing: IconButton(
        tooltip: 'Add rule',
        onPressed: onAdd,
        icon: const Icon(Icons.add_rounded),
      ),
      child: rules.isEmpty
          ? Text(
              'No rule yet. A rule binds a folder to one or more destinations.',
              style: theme.textTheme.bodySmall,
            )
          : Column(
              children: <Widget>[
                for (final AutoUploadRule rule in rules)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                rule.name,
                                style: theme.textTheme.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${AutoUploadMode.fromKey(rule.mode).label} · '
                                '${rule.destinationIds.length} '
                                '${_plural(rule.destinationIds.length, 'destination')}'
                                '${rule.scheduleEnabled ? ' · scheduled' : ''}',
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: rule.enabled,
                          onChanged: (bool value) => onToggle(rule, value),
                        ),
                        TextButton(
                          onPressed: () => onEdit(rule),
                          child: const Text('Edit'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// Background limits
// -----------------------------------------------------------------------------

/// The limits of the Android background execution.
class _LimitsSection extends StatelessWidget {
  const _LimitsSection();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: 'Background limits',
      icon: Icons.info_outline_rounded,
      child: Text(
        'Android limits how long an app runs in the background. Transfers '
        'run in a foreground service. Folders are polled when the app runs '
        'and on the scheduled scan. The battery optimisation exemption keeps '
        'long transfers alive.',
        style: theme.textTheme.bodySmall,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Rule editor
// -----------------------------------------------------------------------------

/// The editor of one upload rule.
class _RuleSheet extends ConsumerStatefulWidget {
  const _RuleSheet({this.rule});

  final AutoUploadRule? rule;

  @override
  ConsumerState<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends ConsumerState<_RuleSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _includeController = TextEditingController();
  final TextEditingController _excludeController = TextEditingController();
  final TextEditingController _maxSizeController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();

  late String _mode;
  late String _duplicatePolicy;
  String? _watchedFolderId;
  late Set<String> _selected;
  bool _scheduleEnabled = false;
  int _scheduleStart = 0;
  int _scheduleDuration = 60;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final AutoUploadRule? rule = widget.rule;
    _mode = rule?.mode ?? AutoUploadMode.fullyAutomatic.key;
    _duplicatePolicy = rule?.duplicatePolicy ?? DuplicatePolicy.skip.key;
    _watchedFolderId = rule?.watchedFolderId;
    _selected = Set<String>.of(rule?.destinationIds ?? const <String>[]);
    _scheduleEnabled = rule?.scheduleEnabled ?? false;
    _scheduleStart = rule?.scheduleStartMinutes ?? 0;
    _scheduleDuration = rule?.scheduleDurationMinutes ?? 60;
    _nameController.text = rule?.name ?? '';
    _includeController.text = rule?.includePatterns ?? '';
    _excludeController.text = rule?.excludePatterns ?? '';
    final int maxFileMb = rule?.maxFileMb ?? 0;
    _maxSizeController.text = maxFileMb == 0 ? '' : '$maxFileMb';
    _durationController.text = '$_scheduleDuration';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _includeController.dispose();
    _excludeController.dispose();
    _maxSizeController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (_scheduleStart ~/ 60) % 24,
        minute: _scheduleStart % 60,
      ),
      helpText: 'Schedule start',
    );
    if (picked == null) return;
    setState(() => _scheduleStart = picked.hour * 60 + picked.minute);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selected.isEmpty) {
      setState(() => _error = 'Pick at least one destination.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final AutoUploadRule? rule = widget.rule;
    final int maxFileMb = int.tryParse(_maxSizeController.text.trim()) ?? 0;
    final int duration =
        int.tryParse(_durationController.text.trim()) ?? _scheduleDuration;

    await AppDatabase.instance.upsertAutoUploadRule(
      AutoUploadRule(
        id: rule?.id ?? 'rule-${DateTime.now().microsecondsSinceEpoch}',
        name: _nameController.text.trim().isEmpty
            ? 'Untitled rule'
            : _nameController.text.trim(),
        enabled: rule?.enabled ?? true,
        mode: _mode,
        destinationIds: _selected.toList(),
        createdAt: rule?.createdAt ?? DateTime.now(),
        watchedFolderId: _watchedFolderId,
        includePatterns: _includeController.text.trim(),
        excludePatterns: _excludeController.text.trim(),
        maxFileMb: maxFileMb,
        priority: rule?.priority ?? 0,
        duplicatePolicy: _duplicatePolicy,
        retryLimit: rule?.retryLimit ?? 3,
        scheduleEnabled: _scheduleEnabled,
        scheduleStartMinutes: _scheduleStart,
        scheduleDurationMinutes: duration,
        weekdays: rule?.weekdays ?? '',
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop('saved');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<WatchedFolder> folders =
        ref.watch(watchedFoldersProvider).value ?? const <WatchedFolder>[];
    final List<Destination> destinations =
        ref.watch(destinationsProvider).value ?? const <Destination>[];
    final List<DropdownMenuItem<String?>> folderItems =
        <DropdownMenuItem<String?>>[
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('All folders'),
          ),
          for (final WatchedFolder folder in folders)
            DropdownMenuItem<String?>(
              value: folder.id,
              child: Text(folder.name ?? folder.path),
            ),
        ];
    if (_watchedFolderId != null &&
        !folders.any((WatchedFolder folder) => folder.id == _watchedFolderId)) {
      folderItems.add(
        DropdownMenuItem<String?>(
          value: _watchedFolderId,
          child: const Text('Removed folder'),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                widget.rule == null ? 'New rule' : 'Edit rule',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Rule name'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _mode,
                decoration: const InputDecoration(labelText: 'Upload mode'),
                items: AutoUploadMode.values
                    .map(
                      (AutoUploadMode m) => DropdownMenuItem<String>(
                        value: m.key,
                        child: Text(m.label),
                      ),
                    )
                    .toList(),
                onChanged: (String? value) =>
                    setState(() => _mode = value ?? _mode),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _duplicatePolicy,
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
                onChanged: (String? value) => setState(
                  () => _duplicatePolicy = value ?? _duplicatePolicy,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _watchedFolderId,
                decoration: const InputDecoration(labelText: 'Watched folder'),
                items: folderItems,
                onChanged: (String? value) =>
                    setState(() => _watchedFolderId = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _includeController,
                decoration: const InputDecoration(
                  labelText: 'Include patterns',
                  hintText: '*.jpg, *.mp4',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _excludeController,
                decoration: const InputDecoration(
                  labelText: 'Exclude patterns',
                  hintText: '*.tmp, *_raw',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _maxSizeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Maximum file size in MB',
                  hintText: '0 = no limit',
                ),
              ),
              const SizedBox(height: 16),
              Text('Destinations', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final Destination destination in destinations)
                    FilterChip(
                      selected: _selected.contains(destination.id),
                      onSelected: (bool value) => setState(() {
                        if (value) {
                          _selected.add(destination.id);
                        } else {
                          _selected.remove(destination.id);
                        }
                      }),
                      label: Text(destination.name),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _scheduleEnabled,
                onChanged: (bool value) =>
                    setState(() => _scheduleEnabled = value),
                title: const Text('Restrict to a time window'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              if (_scheduleEnabled) ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Start', style: theme.textTheme.labelSmall),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: _pickStart,
                              child: Text(_formatMinute(_scheduleStart)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _durationController,
                        keyboardType: TextInputType.number,
                        onChanged: (String value) => setState(
                          () => _scheduleDuration =
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
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppConstants.colorError,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Saving…' : 'Save rule'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

/// The plural form of a count, for example `1 destination` or `2 destinations`.
String _plural(int count, String noun) => count == 1 ? noun : '${noun}s';

/// Formats a minute after midnight as `HH:MM`.
String _formatMinute(int minute) {
  final String hour = ((minute ~/ 60) % 24).toString().padLeft(2, '0');
  final String rest = (minute % 60).toString().padLeft(2, '0');
  return '$hour:$rest';
}

/// Formats a timestamp as a short relative duration.
String _formatRelative(DateTime time) {
  final Duration difference = DateTime.now().difference(time);
  if (difference.inSeconds < 60) return '${difference.inSeconds}s';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m';
  if (difference.inHours < 24) return '${difference.inHours}h';
  return '${difference.inDays}d';
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
