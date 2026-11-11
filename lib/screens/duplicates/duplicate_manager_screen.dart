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

/// The duplicate manager — reviews every pair the engine found.
///
/// SHA-256 matches are exact; metadata and perceptual matches are only
/// possible matches and are labelled as such. Nothing is ever deleted
/// automatically: the user decides what happens to every pair, one by one.
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
        '${Formatters.count(result.duplicates.length)} pairs found',
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
    int exact = 0;
    int possible = 0;
    for (final DuplicateRecord record in records) {
      final String? decision = record.decision;
      if (decision == null ||
          decision.isEmpty ||
          decision == MediaStatus.pendingReview.key) {
        pending++;
      } else if (decision == DuplicatePolicy.skip.key) {
        skipped++;
      }
      if (record.method == DetectionMethod.sha256.key) {
        exact++;
      } else {
        possible++;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: <Widget>[
        SectionCard(
          title: 'Summary',
          subtitle: '${Formatters.count(records.length)} detected pairs',
          icon: Icons.copy_all_rounded,
          child: Column(
            children: <Widget>[
              MetricRow(
                label: 'Exact matches (SHA-256)',
                value: Formatters.count(exact),
                valueColor: exact > 0
                    ? AppConstants.colorSuccess
                    : AppConstants.colorTextSecondary,
              ),
              MetricRow(
                label: 'Possible matches',
                value: Formatters.count(possible),
                valueColor: possible > 0
                    ? AppConstants.colorWarning
                    : AppConstants.colorTextSecondary,
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
                valueColor: AppConstants.colorTextSecondary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          title: 'Rescan',
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
                'The scan compares the SHA-256 hash of every library file. Only '
                'identical content is reported as an exact match.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _scanning ? null : _rescan,
                  icon: const Icon(Icons.manage_search_rounded, size: 18),
                  label: Text(_scanning ? 'Scanning…' : 'Rescan library'),
                ),
              ),
              if (_scanning) ...<Widget>[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: const LinearProgressIndicator(minHeight: 6),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (records.isEmpty)
          const SizedBox(
            height: 260,
            child: EmptyState(
              icon: Icons.check_circle_outline_rounded,
              title: 'No duplicates found',
              message:
                  'Nothing in the library looks like a duplicate of '
                  'another file. Run a rescan to check again.',
            ),
          )
        else
          SectionCard(
            title: 'Review list',
            subtitle:
                '${Formatters.count(records.length)} pairs · '
                '${Formatters.count(pending)} pending',
            icon: Icons.checklist_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'A SHA-256 match proves that both files have identical '
                  'content. Metadata and perceptual-hash matches are possible '
                  'matches only and are never treated as identical.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                for (int i = 0; i < records.length; i++) ...<Widget>[
                  _DuplicateChecklistItem(
                    record: records[i],
                    onReview: (DuplicatePolicy policy) =>
                        _review(records[i], policy),
                    onShowHistory: () =>
                        _showReviewHistory(context, duplicateId: records[i].id),
                  ),
                  if (i < records.length - 1) const Divider(),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// A single pair of the review list.
///
/// The pair carries the certainty of the detection and the decision that was
/// taken for it.
class _DuplicateChecklistItem extends StatelessWidget {
  const _DuplicateChecklistItem({
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
    final bool isExact = method == DetectionMethod.sha256;
    final DuplicatePolicy? decision = _decisionOf(record);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                decision == null
                    ? Icons.radio_button_unchecked_rounded
                    : Icons.check_circle_rounded,
                size: 18,
                color: decision == null
                    ? theme.colorScheme.onSurfaceVariant
                    : AppConstants.colorSuccess,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatusPill(
                  label: isExact
                      ? 'Identical content · SHA-256'
                      : 'Possible match · ${method.label}',
                  color: isExact
                      ? AppConstants.colorSuccess
                      : AppConstants.colorWarning,
                  icon: isExact
                      ? Icons.fingerprint_rounded
                      : Icons.help_outline_rounded,
                ),
              ),
              const SizedBox(width: 8),
              if (decision != null)
                StatusPill(
                  label: _decisionLabel(decision),
                  color: AppConstants.colorTextSecondary,
                )
              else
                Text('Pending', style: theme.textTheme.bodySmall),
            ],
          ),
          if (!isExact) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'The content of the two files is not proven identical.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          _FileLine(
            label: 'Original',
            name: record.originalName ?? 'Unknown file',
            path: record.originalPath,
          ),
          const SizedBox(height: 6),
          _FileLine(
            label: isExact ? 'Duplicate' : 'Candidate',
            name: record.duplicateName ?? 'Unknown file',
            path: record.duplicatePath,
          ),
          const SizedBox(height: 6),
          Text(
            'Detected ${_formatTimestamp(record.detectedAt)}'
            '${record.similarity == null ? '' : ' · Similarity ${_similarityLabel(record.similarity)}'}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
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
                child: const Text('Upload'),
              ),
              OutlinedButton(
                onPressed: () => onReview(DuplicatePolicy.keepBoth),
                child: const Text('Keep both'),
              ),
              OutlinedButton(
                onPressed: () => onReview(DuplicatePolicy.replace),
                child: const Text('Replace entry'),
              ),
              TextButton(
                onPressed: onShowHistory,
                child: const Text('History'),
              ),
            ],
          ),
        ],
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
          child: Text(label, style: theme.textTheme.bodySmall),
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
                  style: theme.textTheme.bodySmall,
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

/// Returns the policy that was decided for the record, if any.
DuplicatePolicy? _decisionOf(DuplicateRecord record) {
  final String? decision = record.decision;
  if (decision == null || decision.isEmpty) return null;
  if (decision == MediaStatus.pendingReview.key) return null;
  return DuplicatePolicy.fromKey(decision);
}

/// A short label for a decided pair.
String _decisionLabel(DuplicatePolicy policy) {
  switch (policy) {
    case DuplicatePolicy.skip:
      return 'Skipped';
    case DuplicatePolicy.anyway:
      return 'Upload';
    case DuplicatePolicy.keepBoth:
      return 'Kept both';
    case DuplicatePolicy.replace:
      return 'Replaced';
    case DuplicatePolicy.ask:
      return 'Asked';
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
          Text('Review history', style: theme.textTheme.titleMedium),
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
              child: Text(policy.label, style: theme.textTheme.bodyMedium),
            ),
            Text(
              _formatTimestamp(
                reviewedAt == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(reviewedAt),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          duplicateId,
          style: theme.textTheme.bodySmall,
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
