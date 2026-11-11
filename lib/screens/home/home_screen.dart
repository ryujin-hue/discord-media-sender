import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/models.dart';
import '../../providers/config_providers.dart';
import '../../providers/upload_providers.dart';
import '../../services/upload_engine.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';

/// The live progress dashboard — the central monitoring screen.
///
/// The snapshot stream of the upload engine is the only source of truth here.
/// The screen shows exactly one monitor and one set of counts; the quick
/// actions of the 2.0 build were removed because they duplicated the controls
/// of the monitor.
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
              const SizedBox(height: 14),
              _LiveMonitorCard(snapshot: snapshot),
              const SizedBox(height: 14),
              const _StatsGrid(),
              const SizedBox(height: 14),
              const _DestinationMonitor(),
              const SizedBox(height: 14),
              _ActivityTimeline(events: events),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const BrandLockup(size: 36, subtitle: 'Live dashboard'),
        const SizedBox(height: 8),
        Text(
          'Uploads, destinations and activity',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// The four numbers that describe the queue.
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

    return SectionCard(
      title: 'Queue counts',
      icon: Icons.stacked_bar_chart_rounded,
      child: Row(
        children: <Widget>[
          Expanded(
            child: _CountCell(
              label: 'Total',
              value: Formatters.count(counts.total),
            ),
          ),
          Expanded(
            child: _CountCell(
              label: 'Successful',
              value: Formatters.count(counts.uploaded),
              color: AppConstants.colorSuccess,
            ),
          ),
          Expanded(
            child: _CountCell(
              label: 'Failed',
              value: Formatters.count(counts.failed),
              color: AppConstants.colorError,
            ),
          ),
          Expanded(
            child: _CountCell(
              label: 'Pending',
              value: Formatters.count(counts.pending),
              color: AppConstants.colorWarning,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountCell extends StatelessWidget {
  const _CountCell({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

/// The single upload monitor.
///
/// It shows the status, the current file, the progress bar, the speed, the
/// estimated time left and the three controls.
class _LiveMonitorCard extends ConsumerWidget {
  const _LiveMonitorCard({required this.snapshot});

  final EngineSnapshot? snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final EngineSnapshot state = snapshot ?? UploadEngine.instance.snapshot;
    final bool paused = state.isPaused;
    final bool running = state.isRunning;
    final bool hasWork = state.jobs.isNotEmpty;

    final String status = paused
        ? 'Paused'
        : running
        ? 'Uploading'
        : hasWork
        ? 'Idle'
        : 'No uploads';

    return SectionCard(
      title: 'Upload monitor',
      subtitle: state.activeDestinationName == null
          ? 'No active destination'
          : 'Destination: ${state.activeDestinationName}',
      icon: paused ? Icons.pause_circle_rounded : Icons.podcasts_rounded,
      trailing: StatusPill(
        label: status,
        color: paused
            ? AppConstants.colorWarning
            : running
            ? AppConstants.colorSuccess
            : AppConstants.colorTextSecondary,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: state.progress,
              minHeight: 8,
              backgroundColor: theme.colorScheme.outline.withValues(
                alpha: 0.18,
              ),
              valueColor: AlwaysStoppedAnimation<Color>(
                paused ? AppConstants.colorWarning : AppConstants.colorPrimary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  state.currentFileName == null
                      ? 'Waiting for the next file'
                      : Formatters.fileName(state.currentFileName!),
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                Formatters.percent(state.progress * 100),
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: _MiniMetric(
                  label: 'Speed',
                  value:
                      state.speedBytesPerSecond == null ||
                          state.speedBytesPerSecond! <= 0
                      ? '—'
                      : Formatters.speed(state.speedBytesPerSecond!),
                ),
              ),
              Expanded(
                child: _MiniMetric(
                  label: 'ETA',
                  value: state.etaSeconds == null
                      ? '—'
                      : Formatters.duration(state.etaSeconds),
                ),
              ),
              Expanded(
                child: _MiniMetric(
                  label: 'Done',
                  value: '${state.completedCount}/${state.jobs.length}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                        onPressed: hasWork
                            ? () => UploadEngine.instance.pause()
                            : null,
                        icon: const Icon(Icons.pause_rounded, size: 18),
                        label: const Text('Pause'),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hasWork
                      ? () => UploadEngine.instance.cancel()
                      : null,
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
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
              padding: const EdgeInsets.only(bottom: 8),
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
