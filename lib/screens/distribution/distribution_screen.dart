import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/validators.dart';
import '../../data/models.dart';
import '../../providers/config_providers.dart';
import '../../providers/upload_providers.dart';
import '../../services/distribution_service.dart';
import '../../services/upload_engine.dart';
import '../../widgets/common.dart';

/// The per destination queue statistics of the distribution engine.
final FutureProvider<Map<String, DestinationStats>> _destinationStatsProvider =
    FutureProvider<Map<String, DestinationStats>>((Ref ref) async {
      return DistributionService.instance.stats();
    });

/// The multi-Discord distribution screen.
///
/// Every destination owns an independent queue, so a slow or rate limited
/// server never blocks the other destinations. This screen configures the
/// destinations, the routing mode and the per destination performance.
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: <Widget>[
              const _DistributionHeader(),
              const SizedBox(height: 18),
              _DistributionModeSection(mode: mode),
              const SizedBox(height: 14),
              _DestinationsSection(destinations: destinations),
              const SizedBox(height: 14),
              _PerformanceSection(stats: stats),
              const SizedBox(height: 14),
              const _RuleHintCard(),
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
class _DistributionHeader extends StatelessWidget {
  const _DistributionHeader();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Multi-Discord distribution',
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Every destination keeps its own queue. A file is routed to the '
          'destinations that match the current mode, and a slow or rate limited '
          'server never blocks the others.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Distribution mode
// -----------------------------------------------------------------------------

/// The section that selects the routing mode.
class _DistributionModeSection extends ConsumerWidget {
  const _DistributionModeSection({required this.mode});

  final DistributionMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      title: 'Distribution mode',
      subtitle: _modeDescription(mode),
      icon: Icons.alt_route_rounded,
      trailing: StatusPill(
        label: mode.label,
        color: AppConstants.colorPrimary,
        icon: Icons.check_rounded,
      ),
      child: Wrap(
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
    );
  }
}

/// Explains what the selected routing mode does.
String _modeDescription(DistributionMode mode) => switch (mode) {
  DistributionMode.broadcast =>
    'Every enabled destination receives a copy of each file.',
  DistributionMode.manual =>
    'Only the destinations picked in the upload screen receive the file.',
  DistributionMode.roundRobin =>
    'The files are spread one by one over the enabled destinations.',
  DistributionMode.sequential =>
    'The files are queued to the enabled destinations one after the other.',
  DistributionMode.ruleBased =>
    'A destination receives a file when its note matches the file rules.',
};

// -----------------------------------------------------------------------------
// Destinations
// -----------------------------------------------------------------------------

/// The section that lists the configured destinations.
class _DestinationsSection extends ConsumerWidget {
  const _DestinationsSection({required this.destinations});

  final List<Destination> destinations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final int enabled = destinations.where((Destination d) => d.enabled).length;

    return SectionCard(
      title: 'Destinations',
      subtitle: destinations.isEmpty
          ? 'No destination configured yet'
          : '$enabled of ${destinations.length} enabled',
      icon: Icons.hub_rounded,
      trailing: IconButton(
        onPressed: () => _openAddDestinationSheet(context, ref),
        icon: const Icon(Icons.add_rounded),
        tooltip: 'Add destination',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (destinations.isEmpty)
            Text(
              'Add a webhook URL or a bot and a channel to start sending media '
              'to several servers at once.',
              style: theme.textTheme.bodySmall,
            )
          else
            for (final Destination destination in destinations) ...<Widget>[
              _DestinationCard(
                destination: destination,
                onToggle: (bool value) =>
                    _setEnabled(context, ref, destination, value),
                onRetry: () => _retryFailed(context, ref, destination),
                onRemove: () => _removeDestination(context, ref, destination),
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openAddDestinationSheet(context, ref),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add destination'),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single destination with its state and its actions.
class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.destination,
    required this.onToggle,
    required this.onRetry,
    required this.onRemove,
  });

  final Destination destination;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isWebhook = destination.isWebhook;
    final String channel =
        destination.channelName ??
        destination.channelId ??
        (isWebhook ? 'Webhook channel' : 'No channel');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.35,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                isWebhook ? Icons.link_rounded : Icons.smart_toy_rounded,
                size: 20,
                color: destination.enabled
                    ? AppConstants.colorSuccess
                    : AppConstants.colorTextSecondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      destination.name,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(channel, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Switch(value: destination.enabled, onChanged: onToggle),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              StatusPill(
                label: isWebhook ? 'Webhook' : 'Bot',
                color: isWebhook
                    ? AppConstants.colorSuccess
                    : AppConstants.colorPrimary,
              ),
              StatusPill(
                label: 'Priority ${destination.priority}',
                color: AppConstants.colorTextSecondary,
                icon: Icons.low_priority_rounded,
              ),
              StatusPill(
                label: '${Formatters.count(destination.totalSent)} sent',
                color: AppConstants.colorSuccess,
                icon: Icons.check_circle_rounded,
              ),
              StatusPill(
                label: '${Formatters.count(destination.totalFailed)} failed',
                color: destination.totalFailed > 0
                    ? AppConstants.colorError
                    : AppConstants.colorTextSecondary,
                icon: Icons.error_rounded,
              ),
              if (destination.totalPending > 0)
                StatusPill(
                  label:
                      '${Formatters.count(destination.totalPending)} pending',
                  color: AppConstants.colorWarning,
                  icon: Icons.schedule_rounded,
                ),
              if (destination.isRateLimited)
                const StatusPill(
                  label: 'Rate limited',
                  color: AppConstants.colorWarning,
                  icon: Icons.speed_rounded,
                ),
            ],
          ),
          if (destination.lastError != null &&
              destination.lastError!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              destination.lastError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppConstants.colorError,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: const Text('Retry failed'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: AppConstants.colorError,
                  ),
                  label: const Text(
                    'Remove',
                    style: TextStyle(color: AppConstants.colorError),
                  ),
                ),
              ),
            ],
          ),
        ],
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

/// Requeues every failed job of a destination.
Future<void> _retryFailed(
  BuildContext context,
  WidgetRef ref,
  Destination destination,
) async {
  await UploadEngine.instance.retryFailedForDestination(destination.id);
  if (!context.mounted) return;
  showAppSnack(
    context,
    'The failed uploads of "${destination.name}" are queued again',
    isSuccess: true,
  );
}

/// Removes a destination after a confirmation.
Future<void> _removeDestination(
  BuildContext context,
  WidgetRef ref,
  Destination destination,
) async {
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
  ref.invalidate(destinationsProvider);
  ref.invalidate(_destinationStatsProvider);
  if (!context.mounted) return;
  showAppSnack(context, 'Destination removed', isSuccess: true);
}

/// Opens the bottom sheet that adds a destination.
Future<void> _openAddDestinationSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final bool? added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (BuildContext context) => const _AddDestinationSheet(),
  );
  if (added != true) return;
  ref.invalidate(destinationsProvider);
  ref.invalidate(_destinationStatsProvider);
  if (!context.mounted) return;
  showAppSnack(context, 'Destination added', isSuccess: true);
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
      title: 'Destination performance',
      subtitle: values.isEmpty
          ? 'No queue activity recorded yet'
          : '${values.length} destination(s) tracked',
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
                    padding: const EdgeInsets.only(bottom: 14),
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
                              color: entry.type == 'webhook'
                                  ? AppConstants.colorSuccess
                                  : AppConstants.colorPrimary,
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
                              icon: Icons.speed_rounded,
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
// Rule hint
// -----------------------------------------------------------------------------

/// Explains the destination note syntax used by the rule based routing.
class _RuleHintCard extends StatelessWidget {
  const _RuleHintCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: 'Rule based routing',
      subtitle: 'Write the rules in the note of a destination',
      icon: Icons.rule_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'The note of a destination acts as a filter. When the distribution '
            'mode is "Rule based", a file is only sent to a destination when '
            'one of its rules matches. Several rules are separated by commas '
            'and a file matches as soon as a single rule matches.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          const _RuleExample(
            rule: 'ext:jpg',
            description: 'Only the files whose extension is jpg.',
          ),
          const _RuleExample(
            rule: 'cat:image',
            description:
                'Only the images: image, video, audio, document or other.',
          ),
          const _RuleExample(
            rule: 'size:25',
            description: 'Only the files of 25 MB or less.',
          ),
          const SizedBox(height: 6),
          Text(
            'A destination without a note receives every file.',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
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
              color: AppConstants.colorPrimary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              rule,
              style: const TextStyle(
                color: AppConstants.colorPrimary,
                fontSize: 12,
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
// Add destination sheet
// -----------------------------------------------------------------------------

/// The bottom sheet that adds a webhook or a bot destination.
class _AddDestinationSheet extends ConsumerStatefulWidget {
  const _AddDestinationSheet();

  @override
  ConsumerState<_AddDestinationSheet> createState() =>
      _AddDestinationSheetState();
}

class _AddDestinationSheetState extends ConsumerState<_AddDestinationSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _channelIdController = TextEditingController();
  final TextEditingController _channelNameController = TextEditingController();
  bool _isBot = false;
  String? _profileId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _channelIdController.dispose();
    _channelNameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isBot && (_profileId == null || _profileId!.isEmpty)) {
      setState(() => _error = 'Pick the bot profile that posts the files.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final String name = _nameController.text.trim();
    final String channelName = _channelNameController.text.trim();
    try {
      if (_isBot) {
        await DistributionService.instance.addBotDestination(
          name: name,
          credentialProfileId: _profileId!,
          channelId: _channelIdController.text.trim(),
          channelName: channelName.isEmpty ? null : channelName,
        );
      } else {
        await DistributionService.instance.addWebhookDestination(
          name: name,
          webhookUrl: _urlController.text.trim(),
          channelName: channelName.isEmpty ? null : channelName,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'The destination could not be created.';
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<CredentialProfile> bots =
        (ref.watch(credentialProfilesProvider).value ??
                const <CredentialProfile>[])
            .where((CredentialProfile profile) => profile.type == 'bot')
            .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Add destination', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'A destination receives a copy of every routed file.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Webhook URL'),
                    icon: Icon(Icons.link_rounded, size: 18),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Bot + channel'),
                    icon: Icon(Icons.smart_toy_rounded, size: 18),
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
                if (bots.isEmpty)
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
                    items: <DropdownMenuItem<String>>[
                      for (final CredentialProfile profile in bots)
                        DropdownMenuItem<String>(
                          value: profile.id,
                          child: Text(
                            profile.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (String? value) =>
                        setState(() => _profileId = value),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _channelIdController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Channel ID',
                    hintText: '17-20 digit snowflake',
                  ),
                  validator: Validators.channelId,
                ),
                const SizedBox(height: 12),
              ] else
                TextFormField(
                  controller: _urlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Webhook URL',
                    hintText: 'https://discord.com/api/webhooks/…',
                  ),
                  validator: Validators.webhookUrl,
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _channelNameController,
                decoration: const InputDecoration(
                  labelText: 'Channel name (optional)',
                  hintText: 'general',
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppConstants.colorError,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Adding…' : 'Add destination'),
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
