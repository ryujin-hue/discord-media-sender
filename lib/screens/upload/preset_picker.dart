import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../providers/upload_providers.dart';
import '../../services/preset_service.dart';
import '../../widgets/common.dart';

/// A stored preset together with the destinations it currently resolves to.
class ResolvedPreset {
  const ResolvedPreset({
    required this.preset,
    required this.application,
    required this.missingNames,
  });

  /// The stored preset.
  final QueuePreset preset;

  /// The result of resolving the preset against the destinations that exist.
  final PresetApplication application;

  /// The names of the destinations that no longer exist, keyed by id.
  ///
  /// A deleted destination leaves no row behind, so its name is only known
  /// when the app still holds a delivery record for it. Otherwise the id is
  /// shown to the user.
  final Map<String, String?> missingNames;

  /// Whether the preset can still be applied.
  bool get isValid => application.isValid;

  /// The destinations the preset points at that still exist.
  List<Destination> get destinations => application.destinations;

  /// A one line description of what the preset stores.
  String get summary {
    final List<String> parts = <String>[];
    if (destinations.isEmpty) {
      parts.add('no destinations');
    } else {
      parts.add(destinations.map((Destination d) => d.name).join(', '));
    }
    parts.add(preset.duplicatePolicy.label);
    if (preset.maxSizeMb > 0) parts.add('max ${preset.maxSizeMb} MB');
    final String template = preset.captionTemplate ?? '';
    if (template.isNotEmpty) parts.add('caption $template');
    return parts.join(' · ');
  }

  /// The reason why the preset cannot be applied.
  String get missingSummary {
    if (isValid) return '';
    final List<String> names = <String>[];
    for (final String id in application.missingDestinationIds) {
      final String? name = missingNames[id];
      names.add(
        name == null || name.isEmpty ? 'deleted destination $id' : '"$name"',
      );
    }
    return names.length == 1
        ? 'Missing destination: ${names.first}'
        : 'Missing destinations: ${names.join(', ')}';
  }
}

/// The preset section of the upload screen.
///
/// The section lists the stored queue presets, applies a preset to the form
/// and manages presets (create and delete). The list is read from the preset
/// service whenever the screen is rebuilt, so a preset that lost a
/// destination is reported as invalid instead of being applied to fewer
/// destinations than the user expects.
class PresetSection extends ConsumerStatefulWidget {
  const PresetSection({
    super.key,
    required this.maxMb,
    required this.destinations,
    required this.onApply,
  });

  /// The maximum file size currently shown in the form, in megabytes.
  final int maxMb;

  /// The destinations that currently exist.
  final List<Destination> destinations;

  /// Called when the user applies a valid preset.
  final void Function(QueuePreset preset, PresetApplication application)
  onApply;

  @override
  ConsumerState<PresetSection> createState() => _PresetSectionState();
}

class _PresetSectionState extends ConsumerState<PresetSection> {
  Future<List<ResolvedPreset>>? _presets;
  String _destinationSignature = '';

  @override
  void initState() {
    super.initState();
    _destinationSignature = _signature();
    _presets = _load();
  }

  @override
  void didUpdateWidget(covariant PresetSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A destination that was added or removed changes whether a preset can
    // still be applied, so the list is read again.
    final String signature = _signature();
    if (signature == _destinationSignature) return;
    _destinationSignature = signature;
    _reload();
  }

  String _signature() =>
      widget.destinations.map((Destination d) => d.id).join('|');

  void _reload() {
    setState(() {
      _presets = _load();
    });
  }

  Future<List<ResolvedPreset>> _load() async {
    final List<QueuePreset> presets = await PresetService.instance.list();
    final List<ResolvedPreset> resolved = <ResolvedPreset>[];
    for (final QueuePreset preset in presets) {
      final PresetApplication application = await PresetService.instance
          .resolve(preset);
      resolved.add(
        ResolvedPreset(
          preset: preset,
          application: application,
          missingNames: await _missingNames(application.missingDestinationIds),
        ),
      );
    }
    return resolved;
  }

  /// Looks up the names of the destinations that no longer exist.
  ///
  /// The destination row is gone once it was deleted, so the name can only be
  /// recovered from a delivery that was made to it before.
  Future<Map<String, String?>> _missingNames(List<String> ids) async {
    final Map<String, String?> names = <String, String?>{};
    for (final String id in ids) {
      String? name;
      try {
        final List<DistributionJob> jobs = await AppDatabase.instance.listJobs(
          destinationId: id,
          limit: 1,
        );
        if (jobs.isNotEmpty) name = jobs.first.destinationName;
      } on Object {
        name = null;
      }
      names[id] = name;
    }
    return names;
  }

  /// Whether the form currently holds the values of the preset.
  bool _isApplied(ResolvedPreset entry) {
    final Set<String> selection = ref.watch(selectedDestinationsProvider);
    final bool sameDestinations =
        selection.length == entry.destinations.length &&
        entry.destinations.every((Destination d) => selection.contains(d.id));
    final bool samePolicy =
        ref.watch(duplicatePolicyProvider) == entry.preset.duplicatePolicy;
    final bool sameCaption =
        ref.watch(captionProvider).trim() ==
        (entry.preset.captionTemplate ?? '').trim();
    final bool sameMax =
        entry.preset.maxSizeMb == 0 || entry.preset.maxSizeMb == widget.maxMb;
    return sameDestinations && samePolicy && sameCaption && sameMax;
  }

  void _apply(ResolvedPreset entry) {
    if (!entry.isValid) {
      _explain(entry);
      return;
    }
    widget.onApply(entry.preset, entry.application);
  }

  void _explain(ResolvedPreset entry) {
    showAppSnack(
      context,
      '${entry.preset.name}: ${entry.missingSummary}',
      isError: true,
    );
  }

  Future<void> _createPreset() async {
    final Set<String> selected = ref.read(selectedDestinationsProvider);
    if (selected.isEmpty) {
      showAppSnack(
        context,
        'Select at least one destination to save a preset.',
        isError: true,
      );
      return;
    }
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) =>
          _PresetNameDialog(destinationCount: selected.length),
    );
    if (name == null || name.isEmpty || !mounted) return;

    final String caption = ref.read(captionProvider).trim();
    await PresetService.instance.create(
      name: name,
      destinationIds: selected.toList(),
      captionTemplate: caption.isEmpty ? null : caption,
      duplicatePolicy: ref.read(duplicatePolicyProvider),
      maxSizeMb: widget.maxMb,
    );
    if (!mounted) return;
    _reload();
    showAppSnack(context, 'Preset saved: $name');
  }

  Future<void> _deletePreset(ResolvedPreset entry) async {
    final bool confirmed = await showConfirmDialog(
      context,
      title: 'Delete preset',
      message:
          'The preset "${entry.preset.name}" will be removed from this device.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await PresetService.instance.delete(entry.preset.id);
    if (!mounted) return;
    _reload();
    showAppSnack(context, 'Preset deleted');
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Presets',
      subtitle: 'Apply a saved destination set, policy and caption',
      icon: Icons.bookmarks_rounded,
      trailing: IconButton(
        onPressed: _createPreset,
        icon: const Icon(Icons.add_rounded, size: 20),
        tooltip: 'New preset',
        visualDensity: VisualDensity.compact,
      ),
      child: FutureBuilder<List<ResolvedPreset>>(
        future: _presets,
        builder:
            (
              BuildContext context,
              AsyncSnapshot<List<ResolvedPreset>> snapshot,
            ) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: LinearProgressIndicator(minHeight: 4),
                );
              }
              final List<ResolvedPreset> presets =
                  snapshot.data ?? const <ResolvedPreset>[];
              if (presets.isEmpty) {
                return const EmptyState(
                  icon: Icons.bookmark_outline_rounded,
                  title: 'No presets yet',
                  message:
                      'Save the current destinations, policy and caption to '
                      'apply them later.',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int i = 0; i < presets.length; i++) ...<Widget>[
                    if (i > 0) const Divider(height: 16),
                    _PresetRow(
                      entry: presets[i],
                      applied: _isApplied(presets[i]),
                      onApply: () => _apply(presets[i]),
                      onExplain: () => _explain(presets[i]),
                      onDelete: () => _deletePreset(presets[i]),
                    ),
                  ],
                ],
              );
            },
      ),
    );
  }
}

/// A single preset in the list.
class _PresetRow extends StatelessWidget {
  const _PresetRow({
    required this.entry,
    required this.applied,
    required this.onApply,
    required this.onExplain,
    required this.onDelete,
  });

  final ResolvedPreset entry;
  final bool applied;
  final VoidCallback onApply;
  final VoidCallback onExplain;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: InkWell(
            onTap: entry.isValid ? onApply : onExplain,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          entry.preset.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: applied
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!entry.isValid) ...<Widget>[
                        const SizedBox(width: 8),
                        const StatusPill(
                          label: 'Invalid',
                          color: AppConstants.colorError,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.summary,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!entry.isValid) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      entry.missingSummary,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppConstants.colorError,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          tooltip: 'Delete preset',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

/// The dialog that asks for the name of a new preset.
class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog({required this.destinationCount});

  /// The number of destinations that are saved with the preset.
  final int destinationCount;

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _valid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: const Text('New preset'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Public feed',
            ),
            onChanged: (String value) =>
                setState(() => _valid = value.trim().isNotEmpty),
            onSubmitted: (String value) {
              if (value.trim().isEmpty) return;
              Navigator.of(context).pop(value.trim());
            },
          ),
          const SizedBox(height: 12),
          Text(
            '${widget.destinationCount} destination(s), the current policy, '
            'caption and size limit are saved with the preset.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.of(context).pop(_controller.text.trim())
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
