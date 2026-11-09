import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/database.dart';
import '../../data/models.dart';
import '../../providers/config_providers.dart';
import '../../services/duplicate_service.dart';
import '../../widgets/common.dart';

/// The duplicate manager — reviews every duplicate pair the engine found.
///
/// SHA-256 matches are exact; metadata and perceptual matches are only
/// suggestions. Nothing is ever deleted automatically: the user decides what
/// happens to every pair.
class DuplicateManagerScreen extends ConsumerWidget {
  const DuplicateManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duplicate manager'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Review history',
            onPressed: () => _showReviewHistory(context),
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(duplicatesProvider);
            await ref.read(duplicatesProvider.future);
          },
          child: const _DuplicateBody(),
        ),
      ),
    );
  }
}

/// The stateful body of the [DuplicateManagerScreen].
///
/// It owns the state of the rescan action and the review callbacks.
class _DuplicateBody extends ConsumerStatefulWidget {
  const _DuplicateBody();

  @override
  ConsumerState<_DuplicateBody> createState() => _DuplicateBodyState();
}

class _DuplicateBodyState extends ConsumerState<_DuplicateBody> {
  bool _scanning = false;

  /// Re-scans every file that is already in the library.
  ///
  /// The numbers shown to the user come straight from [DuplicateScanResult] —
  /// nothing is estimated or invented.
  Future<void> _rescan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final List<MediaLibraryEntry> entries = await AppDatabase.instance
          .listMedia();
      final List<String> paths = entries
          .map((MediaLibraryEntry entry) => entry.path)
          .where((String path) => path.trim().isNotEmpty)
          .toList();
      final DuplicateScanResult result = await DuplicateService.instance
          .scanPaths(paths);
      ref.invalidate(duplicatesProvider);
      ref.invalidate(mediaLibraryProvider);
      if (!mounted) return;
      showAppSnack(
        context,
        'Scanned ${Formatters.count(result.scanned)} files · '
        '${Formatters.count(result.duplicates.length)} duplicates found',
        isSuccess: true,
      );
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, 'Rescan failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// Applies a review decision to a duplicate pair.
  Future<void> _review(DuplicateRecord record, DuplicatePolicy policy) async {
    await DuplicateService.instance.review(record, policy);
    ref.invalidate(duplicatesProvider);
    ref.invalidate(mediaLibraryProvider);
    if (!mounted) return;
    showAppSnack(
      context,
      '${record.duplicateName ?? 'File'} · ${policy.label}',
      isSuccess: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<DuplicateRecord> records =
        ref.watch(duplicatesProvider).value ?? const <DuplicateRecord>[];

    int pending = 0;
    int skipped = 0;
    for (final DuplicateRecord record in records) {
      final String? decision = record.decision;
      if (decision == null ||
          decision.isEmpty ||
          decision == MediaStatus.pendingReview.key) {
        pending++;
      } else if (decision == DuplicatePolicy.skip.key) {
        skipped++;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        SectionCard(
          title: 'Duplicate summary',
          subtitle: 'Detected pairs and their current state',
          icon: Icons.copy_all_rounded,
          child: Column(
            children: <Widget>[
              MetricRow(
                label: 'Total duplicates detected',
                value: Formatters.count(records.length),
              ),
              MetricRow(
                label: 'Pending review',
                value: Formatters.count(pending),
                valueColor: pending > 0
                    ? AppConstants.colorWarning
                    : AppConstants.colorTextSecondary,
              ),
              MetricRow(
                label: 'Files skipped',
                value: Formatters.count(skipped),
                valueColor: skipped > 0
                    ? AppConstants.colorTextSecondary
                    : AppConstants.colorTextSecondary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Rescan library',
          subtitle: _scanning
              ? 'Scanning in progress…'
              : 'Re-hash every file that is already in the library',
          icon: Icons.refresh_rounded,
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
                'The scan compares the SHA-256 hash of every library file. '
                'Files with identical content are reported as duplicates.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _scanning ? null : _rescan,
                  icon: const Icon(Icons.manage_search_rounded, size: 18),
                  label: Text(_scanning ? 'Scanning…' : 'Rescan library'),
                ),
              ),
              if (_scanning) ...<Widget>[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const LinearProgressIndicator(minHeight: 6),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        const _ExplanationCard(),
        const SizedBox(height: 14),
        if (records.isEmpty)
          const SizedBox(
            height: 280,
            child: EmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'No duplicates found',
              message:
                  'Nothing in the library looks like a duplicate of '
                  'another file. Run a rescan to check again.',
            ),
          )
        else
          for (final DuplicateRecord record in records) ...<Widget>[
            _DuplicateCard(
              record: record,
              onReview: (DuplicatePolicy policy) => _review(record, policy),
              onShowHistory: () =>
                  _showReviewHistory(context, duplicateId: record.id),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

/// Explains how duplicates are detected and what the engine never does.
class _ExplanationCard extends StatelessWidget {
  const _ExplanationCard();

  @override
  Widget build(BuildContext context) {
    return const SectionCard(
      title: 'How duplicates are detected',
      subtitle: 'What the engine proves and what it only suggests',
      icon: Icons.info_outline_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _NoteLine(
            icon: Icons.fingerprint_rounded,
            color: AppConstants.colorSuccess,
            text:
                'A SHA-256 match proves that both files have identical '
                'content — byte for byte.',
          ),
          SizedBox(height: 10),
          _NoteLine(
            icon: Icons.tune_rounded,
            color: AppConstants.colorWarning,
            text:
                'Metadata and perceptual-hash matches are only suggestions. '
                'They are never treated as identical and always need your '
                'review.',
          ),
          SizedBox(height: 10),
          _NoteLine(
            icon: Icons.shield_rounded,
            color: AppConstants.colorPrimary,
            text:
                'No file is ever deleted automatically — neither the '
                'duplicate nor the original. Every decision is yours.',
          ),
        ],
      ),
    );
  }
}

/// A single icon + sentence inside the explanation card.
class _NoteLine extends StatelessWidget {
  const _NoteLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
      ],
    );
  }
}

/// A single duplicate pair with the available review actions.
class _DuplicateCard extends StatelessWidget {
  const _DuplicateCard({
    required this.record,
    required this.onReview,
    required this.onShowHistory,
  });

  final DuplicateRecord record;
  final ValueChanged<DuplicatePolicy> onReview;
  final VoidCallback onShowHistory;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DetectionMethod method = DetectionMethod.fromKey(record.method);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.copy_all_rounded,
                  size: 18,
                  color: AppConstants.colorWarning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Duplicate pair',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                StatusPill(
                  label: method.label,
                  color: method == DetectionMethod.sha256
                      ? AppConstants.colorSuccess
                      : AppConstants.colorWarning,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _FileLine(
              label: 'Original',
              name: record.originalName ?? 'Unknown file',
              path: record.originalPath,
            ),
            const SizedBox(height: 10),
            _FileLine(
              label: 'Duplicate',
              name: record.duplicateName ?? 'Unknown file',
              path: record.duplicatePath,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Icon(
                  Icons.schedule_rounded,
                  size: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Text(
                  'Detected ${_formatTimestamp(record.detectedAt)}',
                  style: theme.textTheme.labelSmall,
                ),
                const Spacer(),
                if (record.similarity != null) ...<Widget>[
                  Icon(
                    Icons.percent_rounded,
                    size: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Similarity ${_similarityLabel(record.similarity)}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton(
                  onPressed: () => onReview(DuplicatePolicy.skip),
                  child: const Text('Skip'),
                ),
                OutlinedButton(
                  onPressed: () => onReview(DuplicatePolicy.anyway),
                  child: const Text('Upload anyway'),
                ),
                OutlinedButton(
                  onPressed: () => onReview(DuplicatePolicy.keepBoth),
                  child: const Text('Keep both'),
                ),
                OutlinedButton(
                  onPressed: () => onReview(DuplicatePolicy.replace),
                  child: const Text('Replace entry'),
                ),
                TextButton.icon(
                  onPressed: onShowHistory,
                  icon: const Icon(Icons.history_rounded, size: 16),
                  label: const Text('Review history'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of a duplicate pair: the role, the file name and the path.
class _FileLine extends StatelessWidget {
  const _FileLine({
    required this.label,
    required this.name,
    required this.path,
  });

  final String label;
  final String name;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 74,
          child: Text(label, style: theme.textTheme.labelSmall),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                name,
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (path != null && path!.isNotEmpty)
                Text(
                  path!,
                  style: theme.textTheme.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shows the recorded review decisions of the duplicate engine.
Future<void> _showReviewHistory(
  BuildContext context, {
  String? duplicateId,
}) async {
  final List<Map<String, Object?>> rows = await _loadReviewHistory(duplicateId);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (BuildContext sheetContext) => _ReviewHistorySheet(rows: rows),
  );
}

/// Reads the `duplicate_review_history` table.
Future<List<Map<String, Object?>>> _loadReviewHistory(
  String? duplicateId,
) async {
  final Database db = await AppDatabase.instance.database;
  return db.query(
    'duplicate_review_history',
    where: duplicateId == null ? null : 'duplicate_id = ?',
    whereArgs: duplicateId == null ? null : <Object?>[duplicateId],
    orderBy: 'reviewed_at DESC',
  );
}

/// The bottom sheet that lists the recorded review decisions.
class _ReviewHistorySheet extends StatelessWidget {
  const _ReviewHistorySheet({required this.rows});

  final List<Map<String, Object?>> rows;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (rows.isEmpty) {
      return const SizedBox(
        height: 220,
        child: EmptyState(
          icon: Icons.history_rounded,
          title: 'No review history',
          message: 'No duplicate has been reviewed yet.',
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('Review history', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${Formatters.count(rows.length)} recorded decisions',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          for (final Map<String, Object?> row in rows) ...<Widget>[
            _HistoryRow(row: row),
            const Divider(height: 18),
          ],
        ],
      ),
    );
  }
}

/// A single row of the review history sheet.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.row});

  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String decision = row['decision'] as String? ?? '';
    final DuplicatePolicy policy = DuplicatePolicy.fromKey(decision);
    final String? note = row['note'] as String?;
    final int? reviewedAt = row['reviewed_at'] as int?;
    final String duplicateId = row['duplicate_id'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(policy.label, style: theme.textTheme.titleSmall),
            ),
            Text(
              _formatTimestamp(
                reviewedAt == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(reviewedAt),
              ),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          duplicateId,
          style: theme.textTheme.labelSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (note != null && note.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(note, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// Formats a similarity ratio as a percentage.
String _similarityLabel(double? similarity) {
  if (similarity == null) return '—';
  final double percent = similarity > 1 ? similarity : similarity * 100;
  return '${percent.toStringAsFixed(0)}%';
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
