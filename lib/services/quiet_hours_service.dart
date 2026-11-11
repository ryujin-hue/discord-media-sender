import '../data/database.dart';
import '../data/models.dart';

/// The quiet hours of the destinations.
///
/// A quiet hours window is a local time range in which a destination is
/// skipped by the automatic upload. A manual upload is only refused when the
/// window is marked as strict.
class QuietHoursService {
  QuietHoursService._();

  static final QuietHoursService instance = QuietHoursService._();

  /// Every quiet hours entry, keyed by destination id.
  Future<List<QuietHours>> list() => AppDatabase.instance.listQuietHours();

  /// The quiet hours of one destination, or `null` when it has none.
  Future<QuietHours?> forDestination(String destinationId) =>
      AppDatabase.instance.quietHoursFor(destinationId);

  /// Stores the quiet hours of one destination.
  Future<void> save(QuietHours hours) =>
      AppDatabase.instance.upsertQuietHours(hours);

  /// Removes the quiet hours of one destination.
  Future<void> remove(String destinationId) =>
      AppDatabase.instance.deleteQuietHours(destinationId);

  /// Whether the automatic upload has to skip [destinationId] right now.
  ///
  /// The reason is returned so that the caller can report it honestly.
  Future<String?> skipReason(
    String destinationId, {
    DateTime? now,
    bool manual = false,
  }) async {
    final QuietHours? hours = await forDestination(destinationId);
    if (hours == null) return null;
    final DateTime moment = now ?? DateTime.now();
    if (!hours.contains(moment)) return null;
    if (manual && !hours.strict) return null;
    return 'quiet_hours';
  }

  /// The destinations that are currently inside their quiet hours.
  Future<List<String>> destinationsInQuietHours({DateTime? now}) async {
    final DateTime moment = now ?? DateTime.now();
    final List<QuietHours> all = await list();
    return all
        .where((QuietHours hours) => hours.contains(moment))
        .map((QuietHours hours) => hours.destinationId)
        .toList();
  }
}
