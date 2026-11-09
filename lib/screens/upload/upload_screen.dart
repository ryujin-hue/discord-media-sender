import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/models.dart';
import '../../providers/config_providers.dart';
import '../../providers/upload_providers.dart';
import '../../services/duplicate_service.dart';
import '../../services/media_resolver.dart';
import '../../services/media_service.dart';
import '../../services/upload_engine.dart';
import '../../widgets/common.dart';

/// The upload screen: pick media, choose destinations and send.
class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  final List<MediaCandidate> _files = <MediaCandidate>[];
  final TextEditingController _captionController = TextEditingController();
  bool _busy = false;
  bool _compress = false;
  int _compressQuality = 80;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Picking
  // ---------------------------------------------------------------------------

  Future<void> _pickFiles() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final List<PlatformFile> picked = await FilePicker.pickFiles(
        type: FileType.any,
      );
      if (picked.isEmpty) return;

      final List<MediaCandidate> resolved = <MediaCandidate>[];
      for (final PlatformFile file in picked) {
        final String? path = await _resolvePath(file);
        if (path == null) continue;
        resolved.add(MediaService.instance.describe(path));
      }
      if (!mounted) return;
      setState(() => _files.addAll(resolved));
      if (resolved.isEmpty && picked.isNotEmpty) {
        showAppSnack(
          context,
          'The selected files could not be read.',
          isError: true,
        );
      }
    } catch (error) {
      if (!mounted) return;
      showAppSnack(context, 'File selection failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _resolvePath(PlatformFile file) async {
    final String? direct = file.path;
    if (direct != null && direct.isNotEmpty && File(direct).existsSync()) {
      return direct;
    }
    return MediaResolver.resolvePath(file.uri.toString(), name: file.name);
  }

  Future<void> _pickFolder() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final String? folder = await FilePicker.getDirectoryPath();
      if (folder == null || folder.isEmpty) return;

      // The picker returns either a real path or a Storage Access Framework
      // tree URI; `scanFolder` handles both.
      final List<MediaCandidate> found = await MediaService.instance.scanFolder(
        folder,
        recursive: true,
      );
      if (!mounted) return;
      setState(() => _files.addAll(found));
      if (found.isEmpty && mounted) {
        showAppSnack(context, 'No media files were found in that folder.');
      }
    } catch (error) {
      if (mounted) {
        showAppSnack(context, 'Folder selection failed: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickZip() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final PlatformFile? archive = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: <String>['zip'],
      );
      if (archive == null) return;
      final String? path = await _resolvePath(archive);
      if (path == null) {
        if (mounted) {
          showAppSnack(
            context,
            'The archive could not be read.',
            isError: true,
          );
        }
        return;
      }
      final ZipExtractionResult result = await MediaService.instance.extractZip(
        path,
      );
      if (!mounted) return;
      if (result.error != null) {
        showAppSnack(context, result.error!, isError: true);
      }
      setState(() => _files.addAll(result.extracted));
      if (result.extracted.isEmpty && result.error == null && mounted) {
        showAppSnack(context, 'The archive did not contain any files.');
      }
    } catch (error) {
      if (mounted) {
        showAppSnack(context, 'Archive import failed: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  Future<void> _send() async {
    final List<Destination> destinations =
        ref.watch(destinationsProvider).value ?? const <Destination>[];
    if (_files.isEmpty) {
      showAppSnack(context, 'Select at least one file first.', isError: true);
      return;
    }
    if (destinations.isEmpty) {
      showAppSnack(
        context,
        'Add a destination in the Distribution tab before sending.',
        isError: true,
      );
      return;
    }

    setState(() => _busy = true);
    try {
      List<MediaCandidate> prepared = List<MediaCandidate>.of(_files);
      if (_compress) {
        final List<MediaCandidate> compressed = <MediaCandidate>[];
        for (final MediaCandidate file in prepared) {
          final MediaCandidate? result = await MediaService.instance
              .compressImage(file, quality: _compressQuality);
          compressed.add(result ?? file);
        }
        prepared = compressed;
      }

      // Register the files in the library so that they can be tracked,
      // de-duplicated and archived later.
      final DuplicateScanResult scan = await DuplicateService.instance
          .scanPaths(prepared.map((MediaCandidate f) => f.path).toList());
      if (scan.duplicates.isNotEmpty) {
        // Duplicates are recorded; the policy decides whether they are sent.
        for (final DuplicateRecord record in scan.duplicates) {
          await DuplicateService.instance.review(
            record,
            ref.read(duplicatePolicyProvider),
          );
        }
      }
      ref.invalidate(mediaLibraryProvider);
      ref.invalidate(duplicatesProvider);

      final DistributionMode mode = ref.read(distributionModeProvider);
      final String? caption = _captionController.text.trim().isEmpty
          ? null
          : _captionController.text.trim();

      final List<String> skipped = await UploadEngine.instance.enqueue(
        prepared,
        options: EnqueueOptions(
          destinations: destinations,
          distributionMode: mode,
          caption: caption,
          duplicatePolicy: ref.read(duplicatePolicyProvider),
          maxFileMb: ref.read(settingsProvider).maxFileMb,
        ),
      );

      if (!mounted) return;
      setState(() {
        _files.clear();
        _captionController.clear();
      });
      showAppSnack(
        context,
        skipped.isEmpty
            ? 'Queued ${prepared.length} file(s).'
            : 'Queued ${prepared.length - skipped.length} file(s), skipped ${skipped.length}.',
        isSuccess: skipped.isEmpty,
        isError: skipped.isNotEmpty,
      );
    } catch (error) {
      if (mounted) {
        showAppSnack(
          context,
          'Could not queue the files: $error',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final EngineSnapshot? snapshot = ref.watch(engineSnapshotProvider).value;
    final List<Destination> destinations =
        ref.watch(destinationsProvider).value ?? const <Destination>[];
    final int maxMb = ref.watch(settingsProvider).maxFileMb;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: <Widget>[
            Text('Upload', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 2),
            Text(
              'Send media to one or more Discord destinations',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            _MediaZone(
              busy: _busy,
              onPickFiles: _pickFiles,
              onPickFolder: _pickFolder,
              onPickZip: _pickZip,
            ),
            if (_files.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              _SelectedFiles(
                files: _files,
                onRemove: (int index) => setState(() => _files.removeAt(index)),
                onClear: () => setState(_files.clear),
              ),
            ],
            const SizedBox(height: 14),
            _DestinationSelector(destinations: destinations),
            const SizedBox(height: 14),
            _OptionsCard(
              captionController: _captionController,
              maxMb: maxMb,
              compress: _compress,
              compressQuality: _compressQuality,
              onCompressChanged: (bool value) =>
                  setState(() => _compress = value),
              onQualityChanged: (int value) =>
                  setState(() => _compressQuality = value),
            ),
            const SizedBox(height: 14),
            if (snapshot != null && snapshot.jobs.isNotEmpty) ...<Widget>[
              _QueuePanel(snapshot: snapshot),
              const SizedBox(height: 14),
            ],
            FilledButton.icon(
              onPressed: _busy ? null : _send,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(
                _files.isEmpty
                    ? 'Select media to send'
                    : 'Send ${_files.length} file(s)',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaZone extends StatelessWidget {
  const _MediaZone({
    required this.busy,
    required this.onPickFiles,
    required this.onPickFolder,
    required this.onPickZip,
  });

  final bool busy;
  final VoidCallback onPickFiles;
  final VoidCallback onPickFolder;
  final VoidCallback onPickZip;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: 'Media',
      subtitle: 'Files, folders and ZIP archives up to 5 GB',
      icon: Icons.attach_file_rounded,
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _PickButton(
                  icon: Icons.note_rounded,
                  label: 'Files',
                  onPressed: busy ? null : onPickFiles,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PickButton(
                  icon: Icons.folder_rounded,
                  label: 'Folder',
                  onPressed: busy ? null : onPickFolder,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PickButton(
                  icon: Icons.folder_zip_rounded,
                  label: 'ZIP',
                  onPressed: busy ? null : onPickZip,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Folders are scanned recursively. ZIP archives are extracted into '
            'the app cache before sending.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        foregroundColor: theme.colorScheme.primary,
      ),
    );
  }
}

class _SelectedFiles extends StatelessWidget {
  const _SelectedFiles({
    required this.files,
    required this.onRemove,
    required this.onClear,
  });

  final List<MediaCandidate> files;
  final ValueChanged<int> onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int totalBytes = files.fold<int>(
      0,
      (int s, MediaCandidate f) => s + f.size,
    );

    return SectionCard(
      title: 'Selected',
      subtitle: '${files.length} file(s) · ${Formatters.bytes(totalBytes)}',
      icon: Icons.playlist_add_rounded,
      trailing: TextButton(onPressed: onClear, child: const Text('Clear')),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < files.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: <Widget>[
                  Icon(
                    iconForCategory(files[i].category),
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          Formatters.fileName(files[i].name),
                          style: theme.textTheme.bodyLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          Formatters.bytes(files[i].size),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => onRemove(i),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Remove',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DestinationSelector extends ConsumerWidget {
  const _DestinationSelector({required this.destinations});

  final List<Destination> destinations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    if (destinations.isEmpty) {
      return SectionCard(
        title: 'Destinations',
        subtitle: 'No destination configured',
        icon: Icons.hub_rounded,
        child: Text(
          'Open the Distribution tab to add a webhook or a bot destination.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    final Set<String> selected = ref.watch(selectedDestinationsProvider);

    return SectionCard(
      title: 'Destinations',
      subtitle: '${selected.length} of ${destinations.length} selected',
      icon: Icons.hub_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final Destination destination in destinations)
                FilterChip(
                  selected: selected.contains(destination.id),
                  onSelected: (bool value) {
                    if (value) {
                      ref
                          .read(selectedDestinationsProvider.notifier)
                          .toggle(destination.id);
                    } else {
                      ref
                          .read(selectedDestinationsProvider.notifier)
                          .toggle(destination.id);
                    }
                  },
                  avatar: Icon(
                    destination.isWebhook
                        ? Icons.link_rounded
                        : Icons.smart_toy_rounded,
                    size: 15,
                  ),
                  label: Text(destination.name),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text('Distribution mode', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final DistributionMode mode in DistributionMode.values)
                ChoiceChip(
                  selected: ref.watch(distributionModeProvider) == mode,
                  onSelected: (bool value) =>
                      ref.read(distributionModeProvider.notifier).set(mode),
                  label: Text(mode.label),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text('Duplicate handling', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final DuplicatePolicy policy in DuplicatePolicy.values)
                ChoiceChip(
                  selected: ref.watch(duplicatePolicyProvider) == policy,
                  onSelected: (bool value) =>
                      ref.read(duplicatePolicyProvider.notifier).set(policy),
                  label: Text(policy.label),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OptionsCard extends StatelessWidget {
  const _OptionsCard({
    required this.captionController,
    required this.maxMb,
    required this.compress,
    required this.compressQuality,
    required this.onCompressChanged,
    required this.onQualityChanged,
  });

  final TextEditingController captionController;
  final int maxMb;
  final bool compress;
  final int compressQuality;
  final ValueChanged<bool> onCompressChanged;
  final ValueChanged<int> onQualityChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SectionCard(
      title: 'Options',
      icon: Icons.tune_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: captionController,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Caption',
              hintText: 'Sent with the first file of every batch',
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Maximum file size',
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      '$maxMb MB per file',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const StatusPill(
                label: 'Discord max 100 MB',
                color: AppConstants.colorTextSecondary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            value: compress,
            onChanged: onCompressChanged,
            title: const Text('Compress images'),
            subtitle: const Text(
              'Re-encodes JPEG and PNG files before sending',
            ),
            contentPadding: EdgeInsets.zero,
          ),
          if (compress) ...<Widget>[
            Row(
              children: <Widget>[
                Text('Quality', style: theme.textTheme.titleSmall),
                Expanded(
                  child: Slider(
                    value: compressQuality.toDouble(),
                    min: 30,
                    max: 95,
                    divisions: 13,
                    label: '$compressQuality',
                    onChanged: (double value) =>
                        onQualityChanged(value.round()),
                  ),
                ),
                Text('$compressQuality', style: theme.textTheme.labelMedium),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _QueuePanel extends ConsumerWidget {
  const _QueuePanel({required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final List<DistributionJob> active = snapshot.jobs
        .where(
          (DistributionJob j) =>
              j.status == UploadStatus.uploadingKey ||
              j.status == UploadStatus.pendingKey,
        )
        .toList();

    return SectionCard(
      title: 'Upload queue',
      subtitle:
          '${snapshot.completedCount} done · ${snapshot.failedCount} failed',
      icon: Icons.queue_music_rounded,
      trailing: snapshot.isPaused
          ? const StatusPill(label: 'Paused', color: AppConstants.colorWarning)
          : snapshot.isRunning
          ? const StatusPill(label: 'Running', color: AppConstants.colorSuccess)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: snapshot.progress,
              minHeight: 8,
              backgroundColor: theme.colorScheme.outline.withValues(
                alpha: 0.18,
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final DistributionJob job in active.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          Formatters.fileName(job.fileName),
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${job.destinationName ?? 'destination'} · ${Formatters.bytes(job.fileSize)}',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel',
                    onPressed: () => UploadEngine.instance.cancelJob(job.id),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          if (snapshot.failedCount > 0) ...<Widget>[
            const SizedBox(height: 6),
            FilledButton.tonalIcon(
              onPressed: () {
                for (final DistributionJob job in snapshot.jobs) {
                  if (job.status == UploadStatus.failedKey) {
                    UploadEngine.instance.retryJob(job.id);
                  }
                }
              },
              icon: const Icon(Icons.replay_rounded, size: 18),
              label: Text('Retry ${snapshot.failedCount} failed file(s)'),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: snapshot.isPaused
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

/// Utility used by the upload screen to display the file extension.
String fileExtension(String path) => p.extension(path);
