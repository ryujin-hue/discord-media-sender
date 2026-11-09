import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/constants.dart';
import '../core/security.dart';
import '../core/secure_store.dart';
import '../data/database.dart';
import '../data/models.dart';
import 'discord_api.dart';
import 'media_service.dart';

/// Result of a credential validation.
class CredentialValidation {
  const CredentialValidation({
    required this.isValid,
    this.message,
    this.identity,
    this.guilds = const <DiscordGuild>[],
  });

  final bool isValid;
  final String? message;
  final BotIdentity? identity;
  final List<DiscordGuild> guilds;
}

/// Manages Discord destinations and the rules that route files to them.
class DistributionService {
  DistributionService._();

  static final DistributionService instance = DistributionService._();

  final AppDatabase _db = AppDatabase.instance;
  final DiscordApiClient _api = DiscordApiClient();
  final SecureStore _secure = SecureStore.instance;

  // ---------------------------------------------------------------------------
  // Destinations
  // ---------------------------------------------------------------------------

  Future<List<Destination>> listDestinations() => _db.listDestinations();

  /// Creates a webhook destination.
  Future<Destination> addWebhookDestination({
    required String name,
    required String webhookUrl,
    String? channelName,
    String? channelId,
    String? avatarUrl,
    int priority = 0,
  }) async {
    final String id = 'dest-${DateTime.now().microsecondsSinceEpoch}';
    final Destination destination = Destination(
      id: id,
      name: name,
      type: 'webhook',
      enabled: true,
      createdAt: DateTime.now(),
      channelId: channelId,
      channelName: channelName,
      webhookId: webhookUrl,
      avatarUrl: avatarUrl,
      priority: priority,
    );
    await _db.upsertDestination(destination);
    return destination;
  }

  /// Creates a bot destination that posts into [channelId].
  Future<Destination> addBotDestination({
    required String name,
    required String credentialProfileId,
    required String channelId,
    String? channelName,
    int priority = 0,
  }) async {
    final String id = 'dest-${DateTime.now().microsecondsSinceEpoch}';
    final Destination destination = Destination(
      id: id,
      name: name,
      type: 'bot',
      enabled: true,
      createdAt: DateTime.now(),
      channelId: channelId,
      channelName: channelName,
      credentialProfileId: credentialProfileId,
      priority: priority,
    );
    await _db.upsertDestination(destination);
    return destination;
  }

  Future<void> updateDestination(Destination destination) =>
      _db.upsertDestination(destination);

  Future<void> setDestinationEnabled(String id, bool enabled) async {
    final Destination? destination = await _destination(id);
    if (destination == null) return;
    await _db.upsertDestination(destination.copyWith(enabled: enabled));
  }

  Future<void> removeDestination(String id) async {
    final Destination? destination = await _destination(id);
    if (destination != null &&
        destination.isWebhook &&
        destination.webhookId != null) {
      // The webhook itself is only deleted when the user explicitly asked for
      // it in Discord; the app only removes its own reference here.
    }
    await _db.deleteDestination(id);
    final List<DistributionJob> jobs = await _db.listJobs(destinationId: id);
    for (final DistributionJob job in jobs) {
      await _db.deleteJob(job.id);
    }
  }

  Future<Destination?> _destination(String id) async {
    final List<Destination> destinations = await _db.listDestinations();
    for (final Destination destination in destinations) {
      if (destination.id == id) return destination;
    }
    return null;
  }

  /// Per-destination queue statistics.
  Future<Map<String, DestinationStats>> stats() async {
    final List<Destination> destinations = await _db.listDestinations();
    final List<DistributionJob> jobs = await _db.listJobs();
    final Map<String, DestinationStats> result = <String, DestinationStats>{};
    for (final Destination destination in destinations) {
      final List<DistributionJob> mine = jobs
          .where((DistributionJob j) => j.destinationId == destination.id)
          .toList();
      result[destination.id] = DestinationStats(
        name: destination.name,
        type: destination.type,
        sent: mine
            .where(
              (DistributionJob j) => j.status == UploadStatus.completed.key,
            )
            .length,
        failed: mine
            .where((DistributionJob j) => j.status == UploadStatus.failed.key)
            .length,
        pending: mine
            .where((DistributionJob j) => j.status == UploadStatus.pending.key)
            .length,
        uploading: mine
            .where(
              (DistributionJob j) => j.status == UploadStatus.uploading.key,
            )
            .length,
        rateLimited: destination.isRateLimited,
        rateLimitUntil: destination.rateLimitUntil,
        lastActivityAt: destination.lastActivityAt,
        totalBytes: mine
            .where(
              (DistributionJob j) => j.status == UploadStatus.completed.key,
            )
            .fold<int>(0, (int sum, DistributionJob j) => sum + j.fileSize),
      );
    }
    return result;
  }

  /// Resolves the destinations for a given distribution mode and file.
  List<Destination> resolveTargets({
    required List<Destination> destinations,
    required DistributionMode mode,
    required String? destinationIds,
    MediaCandidate? file,
    int roundRobinIndex = 0,
  }) {
    final List<Destination> enabled = destinations
        .where((Destination d) => d.enabled)
        .toList();
    switch (mode) {
      case DistributionMode.broadcast:
        return enabled;
      case DistributionMode.manual:
        if (destinationIds == null) return const <Destination>[];
        final Set<String> ids = destinationIds.split(',').toSet();
        return enabled.where((Destination d) => ids.contains(d.id)).toList();
      case DistributionMode.roundRobin:
        if (enabled.isEmpty) return const <Destination>[];
        return <Destination>[enabled[roundRobinIndex % enabled.length]];
      case DistributionMode.sequential:
        if (enabled.isEmpty) return const <Destination>[];
        return <Destination>[enabled.first];
      case DistributionMode.ruleBased:
        return enabled.where((Destination d) => _matchesRule(d, file)).toList();
    }
  }

  bool _matchesRule(Destination destination, MediaCandidate? file) {
    if (destination.note == null || destination.note!.trim().isEmpty) {
      return true;
    }
    if (file == null) return true;
    // A destination note acts as a simple rule: `ext:jpg` or `size:<10MB`.
    for (final String rawRule in destination.note!.split(',')) {
      final String rule = rawRule.trim().toLowerCase();
      if (rule.isEmpty) continue;
      if (rule.startsWith('ext:')) {
        final String ext = rule.substring(4).replaceFirst('.', '');
        if (p.extension(file.name).toLowerCase().replaceFirst('.', '') == ext) {
          return true;
        }
      } else if (rule.startsWith('size:')) {
        final String limit = rule.substring(5).replaceAll('mb', '').trim();
        final int? megabytes = int.tryParse(limit);
        if (megabytes != null) {
          if (file.size <= megabytes * 1024 * 1024) return true;
        }
      } else if (rule.startsWith('cat:')) {
        if (file.category == rule.substring(4)) return true;
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Credential profiles
  // ---------------------------------------------------------------------------

  Future<List<CredentialProfile>> listProfiles() =>
      _db.listCredentialProfiles();

  /// Adds a bot credential profile and stores the token in the secure store.
  Future<CredentialProfile> addBotProfile({
    required String name,
    required String botToken,
  }) async {
    final String id = 'prof-${DateTime.now().microsecondsSinceEpoch}';
    await _secure.writeProfile(profileId: id, botToken: botToken);
    final CredentialProfile profile = CredentialProfile(
      id: id,
      name: name,
      type: 'bot',
      createdAt: DateTime.now(),
      hasBotToken: true,
    );
    await _db.upsertCredentialProfile(profile);
    return profile;
  }

  /// Adds a webhook credential profile.
  Future<CredentialProfile> addWebhookProfile({
    required String name,
    required String webhookUrl,
  }) async {
    final String id = 'prof-${DateTime.now().microsecondsSinceEpoch}';
    await _secure.writeProfile(
      profileId: id,
      botToken: '',
      webhookUrl: webhookUrl,
    );
    final CredentialProfile profile = CredentialProfile(
      id: id,
      name: name,
      type: 'webhook',
      createdAt: DateTime.now(),
      hasWebhook: true,
    );
    await _db.upsertCredentialProfile(profile);
    return profile;
  }

  /// Validates a bot token and stores the result on the profile.
  Future<CredentialValidation> validateBotProfile(String profileId) async {
    final String? token = await _secure.readProfileBot(profileId);
    if (token == null || token.isEmpty) {
      return const CredentialValidation(
        isValid: false,
        message: 'No bot token is stored for this profile.',
      );
    }
    try {
      final BotIdentity identity = await _api.validateBot(token);
      final List<DiscordGuild> guilds = await _api.listGuilds(token);
      final CredentialProfile? profile = await _profile(profileId);
      if (profile != null) {
        await _db.upsertCredentialProfile(
          profile.copyWith(
            botUserId: identity.id,
            botUserName: identity.username,
            avatarUrl: identity.avatar,
            lastValidatedAt: DateTime.now(),
            isValid: true,
            statusMessage: 'Bot valid: ${identity.username}',
            clearStatus: false,
          ),
        );
      }
      return CredentialValidation(
        isValid: true,
        message: 'Bot valid: ${identity.username}',
        identity: identity,
        guilds: guilds,
      );
    } on DiscordException catch (error) {
      final CredentialProfile? profile = await _profile(profileId);
      if (profile != null) {
        await _db.upsertCredentialProfile(
          profile.copyWith(
            lastValidatedAt: DateTime.now(),
            isValid: false,
            statusMessage: error.message,
          ),
        );
      }
      return CredentialValidation(isValid: false, message: error.message);
    } catch (error) {
      return CredentialValidation(
        isValid: false,
        message: 'Bot valid: check failed',
      );
    }
  }

  /// Validates a webhook URL.
  Future<CredentialValidation> validateWebhookProfile(String profileId) async {
    final String? url = await _secure.readProfileWebhook(profileId);
    if (url == null || url.isEmpty) {
      return const CredentialValidation(
        isValid: false,
        message: 'No webhook URL is stored for this profile.',
      );
    }
    try {
      final WebhookInfo info = await _api.fetchWebhook(url);
      final CredentialProfile? profile = await _profile(profileId);
      if (profile != null) {
        await _db.upsertCredentialProfile(
          profile.copyWith(
            botUserName: info.name,
            lastValidatedAt: DateTime.now(),
            isValid: true,
            statusMessage: 'Webhook valid: ${info.name}',
          ),
        );
      }
      return CredentialValidation(
        isValid: true,
        message: 'Webhook valid: ${info.name}',
      );
    } on DiscordException catch (error) {
      final CredentialProfile? profile = await _profile(profileId);
      if (profile != null) {
        await _db.upsertCredentialProfile(
          profile.copyWith(
            lastValidatedAt: DateTime.now(),
            isValid: false,
            statusMessage: error.message,
          ),
        );
      }
      return CredentialValidation(isValid: false, message: error.message);
    }
  }

  /// Sends a test message through a profile.
  Future<bool> testProfile(String profileId, {String? channelId}) async {
    final CredentialProfile? profile = await _profile(profileId);
    if (profile == null) return false;
    try {
      if (profile.type == 'bot') {
        final String? token = await _secure.readProfileBot(profileId);
        if (token == null || token.isEmpty) return false;
        final String? channel = channelId;
        if (channel == null || channel.isEmpty) return false;
        final DiscordSendResult result = await _api.sendBotMessage(
          token,
          channel,
          files: <File>[],
          content: 'Discord Media Sender test message.',
        );
        return result.success;
      }
      final String? url = await _secure.readProfileWebhook(profileId);
      if (url == null || url.isEmpty) return false;
      final DiscordSendResult result = await _api.sendWebhook(
        url,
        files: <File>[],
        content: 'Discord Media Sender test message.',
      );
      return result.success;
    } catch (_) {
      return false;
    }
  }

  /// Replaces the secret of an existing profile.
  Future<void> replaceSecret(
    String profileId, {
    String? botToken,
    String? webhookUrl,
  }) async {
    final CredentialProfile? profile = await _profile(profileId);
    if (profile == null) return;
    if (botToken != null) {
      await _secure.write('profile_${profileId}_bot', botToken);
    }
    if (webhookUrl != null) {
      await _secure.write('profile_${profileId}_hook', webhookUrl);
    }
    await _db.upsertCredentialProfile(
      profile.copyWith(
        hasBotToken: profile.hasBotToken || botToken != null,
        hasWebhook: profile.hasWebhook || webhookUrl != null,
        isValid: null,
        clearStatus: true,
      ),
    );
  }

  /// Removes a profile and its stored secret.
  Future<void> removeProfile(String profileId) async {
    await _secure.deleteProfile(profileId);
    await _db.deleteCredentialProfile(profileId);
    final List<Destination> destinations = await _db.listDestinations();
    for (final Destination destination in destinations) {
      if (destination.credentialProfileId == profileId) {
        await _db.upsertDestination(
          destination.copyWith(
            credentialProfileId: null,
            lastError: 'Credential profile removed',
          ),
        );
      }
    }
  }

  Future<CredentialProfile?> _profile(String id) async {
    final List<CredentialProfile> profiles = await _db.listCredentialProfiles();
    for (final CredentialProfile profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  /// Creates a webhook in a Discord channel using a bot profile.
  ///
  /// The bot needs the *Manage Webhooks* permission in that channel.
  Future<WebhookInfo> createWebhook({
    required String profileId,
    required String channelId,
    required String name,
  }) async {
    final String? token = await _secure.readProfileBot(profileId);
    if (token == null || token.isEmpty) {
      throw DiscordException('The selected bot profile has no token stored.');
    }
    final WebhookInfo info = await _api.createWebhook(token, channelId, name);
    return info;
  }

  /// Lists the servers and channels visible to a bot profile.
  Future<List<DiscordGuild>> listGuilds(String profileId) async {
    final String? token = await _secure.readProfileBot(profileId);
    if (token == null || token.isEmpty) return <DiscordGuild>[];
    return _api.listGuilds(token);
  }

  Future<List<DiscordChannel>> listChannels(
    String profileId,
    String guildId,
  ) async {
    final String? token = await _secure.readProfileBot(profileId);
    if (token == null || token.isEmpty) return <DiscordChannel>[];
    return _api.listChannels(token, guildId);
  }

  /// Masks a secret for display.
  String mask(String? secret) => Security.redactSecrets(secret ?? '');
}

/// Per-destination statistics shown on the distribution screen.
class DestinationStats {
  const DestinationStats({
    required this.name,
    required this.type,
    required this.sent,
    required this.failed,
    required this.pending,
    required this.uploading,
    required this.rateLimited,
    required this.rateLimitUntil,
    required this.lastActivityAt,
    required this.totalBytes,
  });

  final String name;
  final String type;
  final int sent;
  final int failed;
  final int pending;
  final int uploading;
  final bool rateLimited;
  final DateTime? rateLimitUntil;
  final DateTime? lastActivityAt;
  final int totalBytes;
}
