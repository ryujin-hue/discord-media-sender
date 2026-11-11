import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/validators.dart';
import '../../data/models.dart';
import '../../providers/config_providers.dart';
import '../../providers/upload_providers.dart';
import '../../services/distribution_service.dart';
import '../../services/quiet_hours_service.dart';
import '../../services/upload_engine.dart';
import '../../widgets/common.dart';

/// The per destination queue statistics of the distribution engine.
final FutureProvider<Map<String, DestinationStats>> _destinationStatsProvider =
    FutureProvider<Map<String, DestinationStats>>((Ref ref) async {
      return DistributionService.instance.stats();
    });

/// The multi-Discord distribution screen.
///
/// Every destination owns an independent queue. The screen owns three
/// surfaces: the routing mode, the destination list and the queue statistics.
class DistributionScreen extends ConsumerWidget {
  const DistributionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Destination> destinations =
        ref.watch(destinationsProvider).value ?? const <Destination>[];
    final DistributionMode mode = ref.watch(distributionModeProvider);
    final AsyncValue<Map<String, DestinationStats>> stats = ref.watch(
      _destinationStatsProvider,
    );

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(destinationsProvider);
            ref.invalidate(_destinationStatsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: <Widget>[
              const _ScreenHeader(),
              const SizedBox(height: 12),
              _RoutingModeSection(mode: mode),
              const SizedBox(height: 12),
              _DestinationsSection(destinations: destinations),
              const SizedBox(height: 12),
              _PerformanceSection(stats: stats),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Header
// -----------------------------------------------------------------------------

/// The title and the subtitle of the screen.
class _ScreenHeader extends StatelessWidget {
  const _ScreenHeader();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Distribution', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          'Routing mode, destinations and queue statistics',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Routing mode
// -----------------------------------------------------------------------------

/// The editor of the routing mode.
///
/// The mode is a global setting, so it lives in this section only. A
/// destination row never carries a mode.
class _RoutingModeSection extends ConsumerWidget {
  const _RoutingModeSection({required this.mode});

  final DistributionMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      title: 'Routing mode',
      subtitle: _modeDescription(mode),
      icon: Icons.alt_route_rounded,
      trailing: StatusPill(label: mode.label, color: AppConstants.colorPrimary),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final DistributionMode option in DistributionMode.values)
                ChoiceChip(
                  label: Text(option.label),
                  selected: option == mode,
                  onSelected: (bool selected) {
                    if (!selected) return;
                    ref.read(distributionModeProvider.notifier).set(option);
                  },
                ),
            ],
          ),
          if (mode == DistributionMode.ruleBased) ...<Widget>[
            const SizedBox(height: 12),
            const _RuleExamples(),
          ],
        ],
      ),
    );
  }
}

/// Explains what the selected routing mode does.
String _modeDescription(DistributionMode mode) => switch (mode) {
  DistributionMode.broadcast =>
    'Every enabled destination receives every file.',
  DistributionMode.manual =>
    'Only the destinations picked on the upload screen.',
  DistributionMode.roundRobin => 'One destination per file, in turn.',
  DistributionMode.sequential =>
    'One destination at a time, in priority order.',
  DistributionMode.ruleBased => 'Destinations whose note matches the file.',
};

// -----------------------------------------------------------------------------
// Destinations
// -----------------------------------------------------------------------------

/// The list of the configured destinations.
///
/// A row carries the type, the name and the enabled switch. Everything else
/// belongs to the destination editor or to the statistics section.
class _DestinationsSection extends ConsumerWidget {
  const _DestinationsSection({required this.destinations});

  final List<Destination> destinations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int enabled = destinations.where((Destination d) => d.enabled).length;

    return SectionCard(
      title: 'Destinations',
      subtitle: destinations.isEmpty
          ? 'None configured'
          : '$enabled of ${destinations.length} enabled',
      icon: Icons.hub_rounded,
      trailing: IconButton(
        onPressed: () => _openDestinationSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        tooltip: 'Add destination',
      ),
      child: destinations.isEmpty
          ? EmptyState(
              icon: Icons.hub_outlined,
              title: 'No destinations',
              message: 'Add a webhook URL or a bot and a channel.',
              action: FilledButton(
                onPressed: () => _openDestinationSheet(context, ref),
                child: const Text('Add destination'),
              ),
            )
          : Column(
              children: <Widget>[
                for (final Destination destination in destinations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _DestinationRow(
                      destination: destination,
                      onToggle: (bool value) =>
                          _setEnabled(context, ref, destination, value),
                      onEdit: () => _openDestinationSheet(
                        context,
                        ref,
                        destination: destination,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// A single destination row: type, name and enabled switch.
class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.destination,
    required this.onToggle,
    required this.onEdit,
  });

  final Destination destination;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: <Widget>[
              StatusPill(
                label: destination.isWebhook ? 'Webhook' : 'Bot',
                color: AppConstants.colorTextSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  destination.name,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Switch(value: destination.enabled, onChanged: onToggle),
            ],
          ),
        ),
      ),
    );
  }
}

/// Enables or disables a destination.
Future<void> _setEnabled(
  BuildContext context,
  WidgetRef ref,
  Destination destination,
  bool value,
) async {
  await DistributionService.instance.setDestinationEnabled(
    destination.id,
    value,
  );
  ref.invalidate(destinationsProvider);
  if (!context.mounted) return;
  showAppSnack(
    context,
    value
        ? '"${destination.name}" is enabled'
        : '"${destination.name}" is disabled',
  );
}

/// Opens the editor of a destination.
///
/// Without [destination] the sheet creates a new one.
Future<void> _openDestinationSheet(
  BuildContext context,
  WidgetRef ref, {
  Destination? destination,
}) async {
  final String? result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (BuildContext context) =>
        _DestinationSheet(destination: destination),
  );
  if (result == null) return;
  ref.invalidate(destinationsProvider);
  ref.invalidate(_destinationStatsProvider);
  if (!context.mounted) return;
  final String message = switch (result) {
    'added' => 'Destination added',
    'removed' => 'Destination removed',
    _ => 'Destination saved',
  };
  showAppSnack(context, message, isSuccess: true);
}

// -----------------------------------------------------------------------------
// Performance
// -----------------------------------------------------------------------------

/// The section that shows the queue statistics of every destination.
class _PerformanceSection extends StatelessWidget {
  const _PerformanceSection({required this.stats});

  final AsyncValue<Map<String, DestinationStats>> stats;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Map<String, DestinationStats> values =
        stats.value ?? const <String, DestinationStats>{};

    return SectionCard(
      title: 'Queue statistics',
      subtitle: values.isEmpty
          ? 'No queue activity recorded yet'
          : '${values.length} ${_plural(values.length, 'destination')} tracked',
      icon: Icons.insights_rounded,
      child: values.isEmpty
          ? Text(
              'The statistics appear once a file has been queued to a '
              'destination.',
              style: theme.textTheme.bodySmall,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final DestinationStats entry in values.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                entry.name,
                                style: theme.textTheme.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            StatusPill(
                              label: entry.type == 'webhook'
                                  ? 'Webhook'
                                  : 'Bot',
                              color: AppConstants.colorTextSecondary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        MetricRow(
                          label: 'Sent',
                          value: Formatters.count(entry.sent),
                          valueColor: AppConstants.colorSuccess,
                        ),
                        MetricRow(
                          label: 'Failed',
                          value: Formatters.count(entry.failed),
                          valueColor: entry.failed > 0
                              ? AppConstants.colorError
                              : null,
                        ),
                        MetricRow(
                          label: 'Pending',
                          value: Formatters.count(entry.pending),
                        ),
                        MetricRow(
                          label: 'Uploading',
                          value: Formatters.count(entry.uploading),
                        ),
                        MetricRow(
                          label: 'Transferred',
                          value: Formatters.bytes(entry.totalBytes),
                        ),
                        MetricRow(
                          label: 'Last activity',
                          value: _formatRelative(entry.lastActivityAt),
                        ),
                        if (entry.rateLimited)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: StatusPill(
                              label: entry.rateLimitUntil == null
                                  ? 'Rate limited'
                                  : 'Rate limited until '
                                        '${_formatClock(entry.rateLimitUntil!)}',
                              color: AppConstants.colorWarning,
                            ),
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
// Rule examples
// -----------------------------------------------------------------------------

/// The destination note syntax of the rule based routing.
class _RuleExamples extends StatelessWidget {
  const _RuleExamples();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Note syntax', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        const _RuleExample(
          rule: 'ext:jpg',
          description: 'Files with the extension jpg.',
        ),
        const _RuleExample(
          rule: 'cat:image',
          description: 'Images, video, audio, document or other.',
        ),
        const _RuleExample(
          rule: 'size:25',
          description: 'Files of 25 MB or less.',
        ),
        const SizedBox(height: 4),
        Text(
          'Rules are separated by commas. A destination without a note receives '
          'every file.',
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}

/// A single rule with its explanation.
class _RuleExample extends StatelessWidget {
  const _RuleExample({required this.rule, required this.description});

  final String rule;
  final String description;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.6,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              rule,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(description, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Destination editor
// -----------------------------------------------------------------------------

/// The editor of one destination.
///
/// Without a [destination] the sheet creates a new one. The sheet owns the
/// quiet hours of the destination, because those are keyed by its id.
class _DestinationSheet extends ConsumerStatefulWidget {
  const _DestinationSheet({this.destination});

  final Destination? destination;

  @override
  ConsumerState<_DestinationSheet> createState() => _DestinationSheetState();
}

class _DestinationSheetState extends ConsumerState<_DestinationSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _channelIdController = TextEditingController();
  final TextEditingController _channelNameController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _priorityController = TextEditingController();

  bool _isBot = false;
  String? _profileId;
  bool _saving = false;
  bool _showUrl = false;
  String? _error;

  // Quiet hours of the destination.
  bool _quietEnabled = false;
  int _startMinute = 22 * 60;
  int _endMinute = 7 * 60;
  bool _strict = false;

  @override
  void initState() {
    super.initState();
    final Destination? destination = widget.destination;
    if (destination == null) return;
    _isBot = !destination.isWebhook;
    _profileId = destination.credentialProfileId;
    _nameController.text = destination.name;
    _channelIdController.text = destination.channelId ?? '';
    _channelNameController.text = destination.channelName ?? '';
    _noteController.text = destination.note ?? '';
    _priorityController.text = '${destination.priority}';
    unawaited(_loadQuietHours(destination.id));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _channelIdController.dispose();
    _channelNameController.dispose();
    _noteController.dispose();
    _priorityController.dispose();
    super.dispose();
  }

  /// Reads the stored quiet hours of the edited destination.
  Future<void> _loadQuietHours(String destinationId) async {
    final QuietHours? hours = await QuietHoursService.instance.forDestination(
      destinationId,
    );
    if (!mounted) return;
    setState(() {
      _quietEnabled = hours?.enabled ?? false;
      _startMinute = hours?.startMinute ?? _startMinute;
      _endMinute = hours?.endMinute ?? _endMinute;
      _strict = hours?.strict ?? false;
    });
  }

  /// Stores the quiet hours of the destination.
  Future<void> _saveQuietHours(String destinationId) async {
    if (!_quietEnabled) {
      await QuietHoursService.instance.remove(destinationId);
      return;
    }
    await QuietHoursService.instance.save(
      QuietHours(
        destinationId: destinationId,
        enabled: true,
        startMinute: _startMinute,
        endMinute: _endMinute,
        strict: _strict,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final Destination? existing = widget.destination;
    if (existing == null &&
        _isBot &&
        (_profileId == null || _profileId!.isEmpty)) {
      setState(() => _error = 'Pick the bot profile that posts the files.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final String name = _nameController.text.trim();
    final String channelId = _channelIdController.text.trim();
    final String channelName = _channelNameController.text.trim();
    final String url = _urlController.text.trim();
    final String note = _noteController.text.trim();
    final int priority = int.tryParse(_priorityController.text.trim()) ?? 0;

    try {
      final Destination destination;
      if (existing == null) {
        if (_isBot) {
          destination = await DistributionService.instance.addBotDestination(
            name: name,
            credentialProfileId: _profileId!,
            channelId: channelId,
            channelName: channelName.isEmpty ? null : channelName,
            priority: priority,
          );
        } else {
          destination = await DistributionService.instance
              .addWebhookDestination(
                name: name,
                webhookUrl: url,
                channelName: channelName.isEmpty ? null : channelName,
                priority: priority,
              );
        }
      } else {
        destination = existing.copyWith(
          name: name,
          channelId: channelId.isEmpty ? existing.channelId : channelId,
          channelName: channelName.isEmpty ? existing.channelName : channelName,
          // An empty field keeps the stored webhook URL, which is never
          // rendered in plain text.
          webhookId: url.isEmpty ? existing.webhookId : url,
          priority: priority,
          note: note,
        );
        await DistributionService.instance.updateDestination(destination);
      }
      await _saveQuietHours(destination.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'The destination could not be saved.';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(existing == null ? 'added' : 'saved');
  }

  /// Requeues every failed job of the edited destination.
  Future<void> _retryFailed() async {
    final Destination? destination = widget.destination;
    if (destination == null) return;
    await UploadEngine.instance.retryFailedForDestination(destination.id);
    if (!mounted) return;
    showAppSnack(
      context,
      'The failed uploads of "${destination.name}" are queued again',
      isSuccess: true,
    );
  }

  /// Removes the edited destination after a confirmation.
  Future<void> _remove() async {
    final Destination? destination = widget.destination;
    if (destination == null) return;
    final bool confirmed = await showConfirmDialog(
      context,
      title: 'Remove destination',
      message:
          'Remove "${destination.name}"? Its queued uploads are deleted as well.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed) return;
    await DistributionService.instance.removeDestination(destination.id);
    await QuietHoursService.instance.remove(destination.id);
    if (!mounted) return;
    Navigator.of(context).pop('removed');
  }

  Future<void> _pickTime({required bool isStart}) async {
    final int current = isStart ? _startMinute : _endMinute;
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: isStart ? 'Quiet hours start' : 'Quiet hours end',
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startMinute = picked.hour * 60 + picked.minute;
      } else {
        _endMinute = picked.hour * 60 + picked.minute;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isNew = widget.destination == null;
    final List<CredentialProfile> bots =
        (ref.watch(credentialProfilesProvider).value ??
                const <CredentialProfile>[])
            .where((CredentialProfile profile) => profile.type == 'bot')
            .toList();
    final List<DropdownMenuItem<String>> profileItems =
        <DropdownMenuItem<String>>[
          for (final CredentialProfile profile in bots)
            DropdownMenuItem<String>(
              value: profile.id,
              child: Text(profile.name, overflow: TextOverflow.ellipsis),
            ),
        ];
    if (_profileId != null &&
        !bots.any((CredentialProfile profile) => profile.id == _profileId)) {
      profileItems.add(
        DropdownMenuItem<String>(
          value: _profileId,
          child: const Text('Removed profile'),
        ),
      );
    }
    final QuietHours preview = QuietHours(
      destinationId: widget.destination?.id ?? '',
      enabled: true,
      startMinute: _startMinute,
      endMinute: _endMinute,
      strict: _strict,
      updatedAt: DateTime.now(),
    );
    final bool activeNow = preview.contains(DateTime.now());

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
                isNew ? 'Add destination' : 'Destination',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                _isBot ? 'Bot and channel' : 'Webhook URL',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (isNew) ...<Widget>[
                SegmentedButton<bool>(
                  segments: const <ButtonSegment<bool>>[
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Webhook URL'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Bot + channel'),
                    ),
                  ],
                  selected: <bool>{_isBot},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<bool> selection) {
                    setState(() {
                      _isBot = selection.first;
                      _error = null;
                    });
                  },
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Destination name',
                  hintText: 'Media channel',
                ),
                validator: Validators.requiredName,
              ),
              const SizedBox(height: 12),
              if (_isBot) ...<Widget>[
                if (bots.isEmpty && isNew)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'No bot profile is available. Add one in the credential '
                      'manager first.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppConstants.colorWarning,
                      ),
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    initialValue: _profileId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Bot profile'),
                    items: profileItems,
                    onChanged: (String? value) =>
                        setState(() => _profileId = value),
                    validator: (String? value) =>
                        _isBot && (value == null || value.isEmpty)
                        ? 'Pick the bot profile'
                        : null,
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _channelIdController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Channel ID',
                    hintText: '17-20 digit snowflake',
                  ),
                  validator: _isBot ? Validators.channelId : null,
                ),
                const SizedBox(height: 12),
              ] else
                TextFormField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  obscureText: !_showUrl,
                  decoration: InputDecoration(
                    labelText: 'Webhook URL',
                    hintText: isNew
                        ? 'https://discord.com/api/webhooks/…'
                        : 'Stored — leave empty to keep it',
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _showUrl = !_showUrl),
                      icon: Icon(
                        _showUrl
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 18,
                      ),
                      tooltip: _showUrl ? 'Hide' : 'Show',
                    ),
                  ),
                  validator: isNew
                      ? Validators.webhookUrl
                      : (String? value) => (value ?? '').trim().isEmpty
                            ? null
                            : Validators.webhookUrl(value),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _channelNameController,
                decoration: const InputDecoration(
                  labelText: 'Channel name (optional)',
                  hintText: 'general',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      controller: _priorityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Priority',
                        hintText: '0',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: 'Rule note (optional)',
                        hintText: 'ext:jpg, size:25',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Quiet hours', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Auto upload skips the destination inside the window',
                style: theme.textTheme.bodySmall,
              ),
              SwitchListTile(
                value: _quietEnabled,
                onChanged: (bool value) =>
                    setState(() => _quietEnabled = value),
                title: const Text('Enable quiet hours'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              if (_quietEnabled) ...<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _TimeField(
                        label: 'Start',
                        minute: _startMinute,
                        onPick: () => _pickTime(isStart: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TimeField(
                        label: 'End',
                        minute: _endMinute,
                        onPick: () => _pickTime(isStart: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _strict,
                  onChanged: (bool value) => setState(() => _strict = value),
                  title: const Text('Also block manual uploads'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                Text(
                  '${preview.label} · ${activeNow ? 'active now' : 'inactive now'}',
                  style: theme.textTheme.labelSmall,
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
                      child: Text(_saving ? 'Saving…' : 'Save'),
                    ),
                  ),
                ],
              ),
              if (!isNew) ...<Widget>[
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextButton(
                        onPressed: _retryFailed,
                        child: const Text('Retry failed'),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: _remove,
                        child: Text(
                          'Remove',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: AppConstants.colorError,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A time button that opens the time picker.
class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.minute,
    required this.onPick,
  });

  final String label;
  final int minute;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: onPick,
            child: Text(_formatMinute(minute)),
          ),
        ),
      ],
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
String _formatRelative(DateTime? time) {
  if (time == null) return 'never';
  final Duration difference = DateTime.now().difference(time);
  if (difference.inSeconds < 60) return '${difference.inSeconds}s ago';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  return '${difference.inDays}d ago';
}

/// Formats a timestamp as a wall clock time.
String _formatClock(DateTime time) {
  final String hour = time.hour.toString().padLeft(2, '0');
  final String minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
