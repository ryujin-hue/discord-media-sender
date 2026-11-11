import 'dart:convert';

import '../core/constants.dart';
import '../data/database.dart';
import '../data/models.dart';

/// A preset that cannot be applied any more.
///
/// This happens when a destination the preset points at was deleted. The
/// preset is kept so that the user can repair it instead of losing it.
class InvalidPreset {
  const InvalidPreset({
    required this.preset,
    required this.missingDestinationIds,
  });

  final QueuePreset preset;

  /// The destination ids that no longer exist.
  final List<String> missingDestinationIds;

  bool get isInvalid => missingDestinationIds.isNotEmpty;
}

/// The result of applying a preset.
class PresetApplication {
  const PresetApplication({
    required this.preset,
    required this.destinations,
    required this.missingDestinationIds,
  });

  final QueuePreset preset;

  /// The destinations that still exist.
  final List<Destination> destinations;

  /// The destination ids that no longer exist.
  final List<String> missingDestinationIds;

  bool get isValid => missingDestinationIds.isEmpty;
}

/// Stores and resolves the named upload presets.
///
/// A preset only ever holds identifiers and plain text. It never holds a bot
/// token or a webhook URL, so a preset can be exported safely.
class PresetService {
  PresetService._();

  static final PresetService instance = PresetService._();

  /// Every stored preset.
  Future<List<QueuePreset>> list() => AppDatabase.instance.listPresets();

  /// Stores a new preset and returns it.
  Future<QueuePreset> create({
    required String name,
    required List<String> destinationIds,
    String? captionTemplate,
    DuplicatePolicy duplicatePolicy = DuplicatePolicy.skip,
    int maxSizeMb = 0,
  }) async {
    final DateTime now = DateTime.now();
    final QueuePreset preset = QueuePreset(
      id: 'preset-${now.microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Preset' : name.trim(),
      destinationIds: destinationIds,
      captionTemplate: captionTemplate,
      duplicatePolicy: duplicatePolicy,
      maxSizeMb: maxSizeMb,
      createdAt: now,
      updatedAt: now,
    );
    await AppDatabase.instance.upsertPreset(preset);
    return preset;
  }

  /// Updates an existing preset.
  Future<void> update(QueuePreset preset) =>
      AppDatabase.instance.upsertPreset(preset);

  /// Removes a preset.
  Future<void> delete(String id) => AppDatabase.instance.deletePreset(id);

  /// Resolves a preset against the destinations that currently exist.
  ///
  /// A preset that points at a deleted destination is reported as invalid
  /// instead of silently uploading to fewer places than the user expects.
  Future<PresetApplication> resolve(QueuePreset preset) async {
    final List<Destination> all = await AppDatabase.instance.listDestinations();
    final Map<String, Destination> byId = <String, Destination>{
      for (final Destination destination in all) destination.id: destination,
    };

    final List<Destination> resolved = <Destination>[];
    final List<String> missing = <String>[];
    for (final String id in preset.destinationIds) {
      final Destination? destination = byId[id];
      if (destination == null) {
        missing.add(id);
      } else {
        resolved.add(destination);
      }
    }

    return PresetApplication(
      preset: preset,
      destinations: resolved,
      missingDestinationIds: missing,
    );
  }

  /// The presets that can no longer be applied.
  Future<List<InvalidPreset>> listInvalid() async {
    final List<QueuePreset> presets = await list();
    final List<InvalidPreset> invalid = <InvalidPreset>[];
    for (final QueuePreset preset in presets) {
      final PresetApplication application = await resolve(preset);
      if (application.isValid) continue;
      invalid.add(
        InvalidPreset(
          preset: preset,
          missingDestinationIds: application.missingDestinationIds,
        ),
      );
    }
    return invalid;
  }

  /// Exports the presets as JSON.
  ///
  /// The payload holds identifiers and text only.
  String exportJson(List<QueuePreset> presets) {
    final List<Object?> payload = presets
        .map(
          (QueuePreset preset) => <String, Object?>{
            'name': preset.name,
            'destination_ids': preset.destinationIds,
            'caption_template': preset.captionTemplate,
            'duplicate_policy': preset.duplicatePolicy.key,
            'max_size_mb': preset.maxSizeMb,
          },
        )
        .toList();
    return const JsonEncoder.withIndent('  ').convert(payload);
  }
}
