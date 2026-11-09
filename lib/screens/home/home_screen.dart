import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/models.dart';
import '../../providers/config_providers.dart';
import '../../providers/upload_providers.dart';
import '../../services/upload_engine.dart';
import '../../widgets/common.dart';

/// The live progress dashboard — the central monitoring screen.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final EngineSnapshot? snapshot = ref.watch(engineSnapshotProvider).value;
    final List<LiveActivityEvent> events =
        ref.watch(liveEventsProvider).value ?? const <LiveActivityEvent>[];

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardCountsProvider);
            ref.invalidate(liveEventsProvider);
            ref.invalidate(destinationsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: <Widget>[
              const _HomeHeader(),
              const SizedBox(height: 18),
              if (snapshot != null && snapshot.jobs.isNotEmpty) ...<Widget>[
                _LiveMonitorCard(snapshot: snapshot),
                const SizedBox(height: 14),
              ],
              const _StatsGrid(),
              const SizedBox(height: 14),
              const _DestinationMonitor(),
              const SizedBox(height: 14),
              _ActivityTimeline(events: events),
              const SizedBox(height: 14),
              const _QuickActions(),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Discord Media Sender',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 2),
              Text('Live dashboard', style: theme.textTheme.bodySmall),
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
            children: <Widget>[
              const Icon(
                Icons.bolt_rounded,
                size: 14,
                color: AppConstants.colorPrimary,
              ),
              const SizedBox(width: 4),
              Text(
                'v${AppConstants.appVersion}',
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

class _StatsGrid extends ConsumerWidget {
  const _StatsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DashboardCounts counts =
        ref.watch(dashboardCountsProvider).value ??
        const DashboardCounts(
          total: 0,
          uploaded: 0,
          uploading: 0,
          pending: 0,
          failed: 0,
          duplicates: 0,
          archived: 0,
          bytesTransferred: 0,
        );

    final List<Widget> tiles = <Widget>[
      StatTile(
        label: 'Total files',
        value: Formatters.count(counts.total),
        icon: Icons.folder_open_rounded,
      ),
      StatTile(
        label: 'Uploaded',
        value: Formatters.count(counts.uploaded),
        icon: Icons.check_circle_rounded,
        color: AppConstants.colorSuccess,
      ),
      StatTile(
        label: 'Uploading',
        value: Formatters.count(counts.uploading),
        icon: Icons.cloud_upload_rounded,
        color: AppConstants.colorPrimary,
      ),
      StatTile(
        label: 'Pending queue',
        value: Formatters.count(counts.pending),
        icon: Icons.schedule_rounded,
        color: AppConstants.colorWarning,
      ),
      StatTile(
        label: 'Failed',
        value: Formatters.count(counts.failed),
        icon: Icons.error_rounded,
        color: AppConstants.colorError,
      ),
      StatTile(
        label: 'Duplicates',
        value: Formatters.count(counts.duplicates),
        icon: Icons.copy_all_rounded,
        color: AppConstants.colorWarning,
      ),
      StatTile(
        label: 'Archived',
        value: Formatters.count(counts.archived),
        icon: Icons.inventory_2_rounded,
      ),
      StatTile(
        label: 'Data sent',
        value: Formatters.bytes(counts.bytesTransferred),
        icon: Icons.data_usage_rounded,
        color: AppConstants.colorSuccess,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: tiles,
    );
  }
}

class _LiveMonitorCard extends ConsumerWidget {
  const _LiveMonitorCard({required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool paused = snapshot.isPaused;

    return SectionCard(
      title: paused ? 'Upload paused' : 'Live upload monitor',
      subtitle: snapshot.activeDestinationName == null
          ? 'No active destination'
          : 'Destination: ${snapshot.activeDestinationName}',
      icon: paused ? Icons.pause_circle_rounded : Icons.podcasts_rounded,
      trailing: StatusPill(
        label: paused
            ? 'Paused'
            : snapshot.isRunning
            ? 'Running'
            : 'Idle',
        color: paused
            ? AppConstants.colorWarning
            : snapshot.isRunning
            ? AppConstants.colorSuccess
            : AppConstants.colorTextSecondary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: snapshot.progress,
              minHeight: 10,
              backgroundColor: theme.colorScheme.outline.withValues(
                alpha: 0.18,
              ),
              valueColor: AlwaysStoppedAnimation<Color>(
                paused ? AppConstants.colorWarning : AppConstants.colorPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  snapshot.currentFileName == null
                      ? 'Waiting for the next file'
                      : Formatters.fileName(snapshot.currentFileName!),
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                Formatters.percent(snapshot.progress * 100),
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: <Widget>[
              _MiniMetric(
                icon: Icons.speed_rounded,
                label: 'Speed',
                value:
                    snapshot.speedBytesPerSecond == null ||
                        snapshot.speedBytesPerSecond! <= 0
                    ? '—'
                    : Formatters.speed(snapshot.speedBytesPerSecond!),
              ),
              _MiniMetric(
                icon: Icons.timer_outlined,
                label: 'ETA',
                value: snapshot.etaSeconds == null
                    ? '—'
                    : Formatters.duration(snapshot.etaSeconds),
              ),
              _MiniMetric(
                icon: Icons.sentiment_satisfied_alt_rounded,
                label: 'Done',
                value: '${snapshot.completedCount}/${snapshot.jobs.length}',
              ),
              _MiniMetric(
                icon: Icons.replay_rounded,
                label: 'Retries',
                value: Formatters.count(
                  snapshot.jobs
                      .where((DistributionJob j) => j.retryCount > 0)
                      .length,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: paused
                    ? OutlinedButton.icon(
                        onPressed: () => UploadEngine.instance.resume(),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Resume'),
                      )
                    : FilledButton.icon(
                        onPressed: () => UploadEngine.instance.pause(),
                        icon: const Icon(Icons.pause_rounded, size: 18),
                        label: const Text('Pause'),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => UploadEngine.instance.cancel(),
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: theme.colorScheme.primary),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 4),
        Text(value, style: theme.textTheme.labelMedium),
      ],
    );
  }
}

class _DestinationMonitor extends ConsumerWidget {
  const _DestinationMonitor();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Destination> destinations =
        ref.watch(destinationsProvider).value ?? const <Destination>[];
    final ThemeData theme = Theme.of(context);

    if (destinations.isEmpty) {
      return const SectionCard(
        title: 'Discord destinations',
        subtitle: 'No destination configured yet',
        icon: Icons.hub_rounded,
        child: Text(
          'Add a webhook or bot destination in the Distribution tab to start '
          'sending media.',
        ),
      );
    }

    return SectionCard(
      title: 'Discord destinations',
      subtitle:
          '${destinations.where((Destination d) => d.enabled).length} active',
      icon: Icons.hub_rounded,
      child: Column(
        children: <Widget>[
          for (final Destination destination in destinations)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: <Widget>[
                  Icon(
                    destination.isWebhook
                        ? Icons.link_rounded
                        : Icons.smart_toy_rounded,
                    size: 18,
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
                          style: theme.textTheme.bodyLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          destination.isWebhook
                              ? 'Webhook'
                              : 'Bot · ${destination.channelName ?? destination.channelId ?? 'no channel'}',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  if (destination.isRateLimited)
                    const StatusPill(
                      label: 'Rate limited',
                      color: AppConstants.colorWarning,
                      icon: Icons.speed_rounded,
                    )
                  else
                    Text(
                      '${destination.totalSent} sent',
                      style: theme.textTheme.labelSmall,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityTimeline extends StatelessWidget {
  const _ActivityTimeline({required this.events});

  final List<LiveActivityEvent> events;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SectionCard(
      title: 'Live activity',
      subtitle: events.isEmpty
          ? 'No events yet'
          : '${events.length} recent events',
      icon: Icons.timeline_rounded,
      child: events.isEmpty
          ? Text(
              'Uploads, duplicates, deliveries and errors appear here in real time.',
              style: theme.textTheme.bodySmall,
            )
          : Column(
              children: <Widget>[
                for (int i = 0; i < events.length && i < 12; i++)
                  _TimelineRow(
                    event: events[i],
                    isLast: i == events.length - 1,
                  ),
              ],
            ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.event, required this.isLast});

  final LiveActivityEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = switch (event.severity) {
      'success' => AppConstants.colorSuccess,
      'error' => AppConstants.colorError,
      'warning' => AppConstants.colorWarning,
      _ => theme.colorScheme.primary,
    };

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: theme.colorScheme.outline.withValues(alpha: 0.35),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(event.message, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    _formatTime(event.createdAt),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime time) {
    final DateTime now = DateTime.now();
    final Duration difference = now.difference(time);
    if (difference.inSeconds < 60) return '${difference.inSeconds}s ago';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionCard(
      title: 'Quick actions',
      icon: Icons.bolt_rounded,
      child: Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                UploadEngine.instance.pause();
                showAppSnack(context, 'Pausing after the current file…');
              },
              icon: const Icon(Icons.pause_rounded, size: 18),
              label: const Text('Pause'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                UploadEngine.instance.resume();
                showAppSnack(context, 'Upload resumed');
              },
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Resume'),
            ),
          ),
        ],
      ),
    );
  }
}
