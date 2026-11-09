import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../services/update_service.dart';
import '../../services/widget_bridge.dart';
import '../../widgets/common.dart';

/// Checks, downloads and installs application updates.
class UpdateManagerScreen extends ConsumerStatefulWidget {
  const UpdateManagerScreen({super.key});

  @override
  ConsumerState<UpdateManagerScreen> createState() =>
      _UpdateManagerScreenState();
}

class _UpdateManagerScreenState extends ConsumerState<UpdateManagerScreen> {
  UpdateCheckResult? _result;
  UpdateDownloadResult? _download;
  List<UpdateHistoryEntry> _history = const <UpdateHistoryEntry>[];
  bool _checking = true;
  bool _downloading = false;
  double? _progress;
  String? _installMessage;
  String? _installError;
  String _channel = 'stable';

  @override
  void initState() {
    super.initState();
    unawaited(_check(force: true));
  }

  Future<void> _check({required bool force}) async {
    if (mounted) setState(() => _checking = true);
    final UpdateCheckResult result = await UpdateService.instance.check(
      force: force,
      channel: _channel,
    );
    if (!mounted) return;
    setState(() {
      _result = result;
      _checking = false;
      _download = null;
      _progress = null;
      _installMessage = null;
      _installError = null;
    });
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    final List<UpdateHistoryEntry> entries = await AppDatabase.instance
        .listUpdateHistory(limit: 20);
    if (!mounted) return;
    setState(() => _history = entries);
  }

  Future<void> _downloadUpdate() async {
    final GithubRelease? release = _result?.release;
    if (release == null) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _download = null;
      _installMessage = null;
      _installError = null;
    });
    final UpdateDownloadResult result = await UpdateService.instance.download(
      release,
      onProgress: (int received, int total) {
        if (!mounted) return;
        setState(() {
          _progress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _downloading = false;
      _download = result;
      _progress = null;
    });
  }

  Future<void> _installUpdate() async {
    final UpdateDownloadResult? download = _download;
    if (download == null || download.file == null) return;
    final bool installed = await WidgetBridge.instance.installApk(
      download.file!.path,
    );
    if (!mounted) return;
    setState(() {
      if (installed) {
        _installMessage =
            'The Android installer was opened. Approve the installation to '
            'finish the update.';
        _installError = null;
      } else {
        _installMessage = null;
        _installError =
            'The installation could not be started. The downloaded file was '
            'rejected by the system installer.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final UpdateCheckResult? result = _result;
    final bool available = result?.updateAvailable ?? false;
    final UpdateDownloadResult? download = _download;

    return Scaffold(
      appBar: AppBar(title: const Text('Update manager')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: <Widget>[
            SectionCard(
              title: 'Update status',
              subtitle: 'Checks GitHub releases for a newer build',
              icon: Icons.system_update_rounded,
              trailing: available
                  ? const StatusPill(
                      label: 'Update available',
                      color: AppConstants.colorSuccess,
                      icon: Icons.new_releases_rounded,
                    )
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  MetricRow(
                    label: 'Installed version',
                    value: result?.currentVersion ?? AppConstants.appVersion,
                  ),
                  MetricRow(
                    label: 'Latest version',
                    value: result?.latestVersion ?? '—',
                  ),
                  MetricRow(
                    label: 'Release channel',
                    value: result?.channel ?? _channel,
                  ),
                  MetricRow(
                    label: 'Release date',
                    value: _formatDateTime(result?.releaseDate),
                  ),
                  if (result?.error != null) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      result!.error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppConstants.colorError,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _checking
                          ? null
                          : () {
                              unawaited(_check(force: true));
                            },
                      icon: _checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(
                        _checking ? 'Checking…' : 'Check for updates',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Release channel',
              subtitle: 'Beta builds are published as pre-releases',
              icon: Icons.tune_rounded,
              child: SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'stable', label: Text('Stable')),
                  ButtonSegment<String>(value: 'beta', label: Text('Beta')),
                ],
                selected: <String>{_channel},
                showSelectedIcon: false,
                onSelectionChanged: (Set<String> selection) {
                  setState(() => _channel = selection.first);
                  unawaited(_check(force: true));
                },
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Release notes',
              icon: Icons.description_rounded,
              child: Text(
                result?.releaseNotes ??
                    UpdateService.formatNotes(result?.release?.body),
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (available && result?.release != null) ...<Widget>[
              const SizedBox(height: 14),
              SectionCard(
                title: 'Download',
                subtitle: 'The APK is verified against the published checksum',
                icon: Icons.download_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (_downloading) ...<Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _progress,
                          minHeight: 10,
                          backgroundColor: theme.colorScheme.outline.withValues(
                            alpha: 0.18,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${Formatters.percent((_progress ?? 0) * 100)} downloaded',
                        style: theme.textTheme.labelSmall,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (download != null && !download.success) ...<Widget>[
                      Text(
                        download.error ?? 'The update could not be downloaded.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppConstants.colorError,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _downloading
                            ? null
                            : () {
                                unawaited(_downloadUpdate());
                              },
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(
                          _downloading ? 'Downloading…' : 'Download update',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (download != null && download.success) ...<Widget>[
              const SizedBox(height: 14),
              SectionCard(
                title: 'Install',
                subtitle: 'The checksum of the downloaded APK matched',
                icon: Icons.install_mobile_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Verified SHA-256',
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      download.sha256 ?? '—',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${Formatters.bytes(download.bytesDownloaded)} downloaded to '
                      'the temporary folder.',
                      style: theme.textTheme.labelSmall,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          unawaited(_installUpdate());
                        },
                        icon: const Icon(
                          Icons.install_mobile_rounded,
                          size: 18,
                        ),
                        label: const Text('Install update'),
                      ),
                    ),
                    if (_installMessage != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        _installMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppConstants.colorSuccess,
                        ),
                      ),
                    ],
                    if (_installError != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        _installError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppConstants.colorError,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            SectionCard(
              title: 'Update history',
              subtitle: _history.isEmpty
                  ? 'No checks recorded yet'
                  : '${_history.length} recorded checks',
              icon: Icons.history_rounded,
              child: _history.isEmpty
                  ? Text(
                      'Every update check is stored locally so that you can '
                      'review what happened.',
                      style: theme.textTheme.bodySmall,
                    )
                  : Column(
                      children: <Widget>[
                        for (final UpdateHistoryEntry entry in _history)
                          _UpdateHistoryRow(entry: entry),
                      ],
                    ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: 'Safe updates',
              icon: Icons.shield_rounded,
              child: Text(
                'Updates are verified against the published SHA-256 checksum '
                'and must have the same application id and a higher version '
                'code. Android always asks the user to approve the '
                'installation.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single recorded update check.
class _UpdateHistoryRow extends StatelessWidget {
  const _UpdateHistoryRow({required this.entry});

  final UpdateHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = switch (entry.status) {
      'error' => AppConstants.colorError,
      'installed' => AppConstants.colorSuccess,
      'available' => AppConstants.colorPrimary,
      _ => AppConstants.colorTextSecondary,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'v${entry.version}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              StatusPill(label: entry.status, color: color),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            _formatDateTime(entry.checkedAt),
            style: theme.textTheme.labelSmall,
          ),
          if (entry.error != null && entry.error!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              entry.error!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppConstants.colorError,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Formats a timestamp as `yyyy-MM-dd HH:mm`.
String _formatDateTime(DateTime? value) {
  if (value == null) return '—';
  final DateTime local = value.toLocal();
  final String month = local.month.toString().padLeft(2, '0');
  final String day = local.day.toString().padLeft(2, '0');
  final String hour = local.hour.toString().padLeft(2, '0');
  final String minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
