import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'constants.dart';

/// Persistent, Keystore-backed storage for Discord credentials.
///
/// Bot tokens and webhook URLs are never written to SQLite, logs or analytics
/// exports — they only ever live here, encrypted by the Android Keystore via
/// `flutter_secure_storage`.
///
/// Note: the underlying Keystore key is destroyed when the app is uninstalled
/// or its data is cleared, so credentials cannot survive that.
class SecureStore {
  const SecureStore._();

  static const SecureStore instance = SecureStore._();

  static final FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: true,
      migrateOnAlgorithmChange: true,
    ),
  );

  /// Legacy keys written by 1.0 that are migrated into named profiles on
  /// first launch of 2.0.
  static const List<String> legacyKeys = <String>[
    AppConstants.keyBotToken,
    AppConstants.keyWebhookUrl,
    AppConstants.keyBotName,
    AppConstants.keyAvatarUrl,
    AppConstants.keyChannelId,
    AppConstants.keyChannelName,
    AppConstants.keyMode,
  ];

  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, String? value) async {
    try {
      if (value == null || value.isEmpty) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } catch (_) {
      // Secure storage failures must never crash the upload flow; the caller
      // treats a missing credential as "not configured".
    }
  }

  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }

  Future<void> deleteAll() async {
    try {
      await _storage.deleteAll();
    } catch (_) {}
  }

  /// Stores a credential profile under a namespaced key.
  Future<void> writeProfile({
    required String profileId,
    required String botToken,
    String? webhookUrl,
  }) async {
    await write('profile_${profileId}_bot', botToken);
    if (webhookUrl != null && webhookUrl.isNotEmpty) {
      await write('profile_${profileId}_hook', webhookUrl);
    }
  }

  Future<String?> readProfileBot(String profileId) =>
      read('profile_${profileId}_bot');

  Future<String?> readProfileWebhook(String profileId) =>
      read('profile_${profileId}_hook');

  Future<void> deleteProfile(String profileId) async {
    await delete('profile_${profileId}_bot');
    await delete('profile_${profileId}_hook');
  }

  /// Reads every stored credential profile as a map.
  ///
  /// The returned map never leaves the device: callers must not log it or
  /// include it in analytics exports.
  Future<Map<String, Map<String, String>>> readAllProfiles() async {
    final Map<String, Map<String, String>> result =
        <String, Map<String, String>>{};
    try {
      final Map<String, String> all = await _storage.readAll();
      final Map<String, String> grouped = <String, String>{};
      for (final MapEntry<String, String> entry in all.entries) {
        if (entry.key.startsWith('profile_')) {
          grouped[entry.key] = entry.value;
        }
      }
      grouped.forEach((String key, String value) {
        final List<String> parts = key.split('_');
        if (parts.length < 3) return;
        final String profileId = parts[1];
        final bool isBot = parts.last == 'bot';
        final Map<String, String> bucket = result.putIfAbsent(
          profileId,
          () => <String, String>{},
        );
        bucket[isBot ? 'botToken' : 'webhookUrl'] = value;
      });
    } catch (_) {}
    return result;
  }

  /// Migrates the flat 1.0 credential layout into a single named profile.
  ///
  /// Returns the migrated profile id, or null when there was nothing to
  /// migrate.
  Future<String?> migrateLegacyCredentials() async {
    final Map<String, String?> legacy = <String, String?>{};
    for (final String key in legacyKeys) {
      legacy[key] = await read(key);
    }
    final String? token = legacy[AppConstants.keyBotToken];
    final String? webhook = legacy[AppConstants.keyWebhookUrl];
    if ((token == null || token.isEmpty) &&
        (webhook == null || webhook.isEmpty)) {
      return null;
    }

    const String profileId = 'legacy_default';
    final bool profileExists =
        await readProfileBot(profileId) != null ||
        await readProfileWebhook(profileId) != null;

    if (!profileExists) {
      await writeProfile(
        profileId: profileId,
        botToken: token ?? '',
        webhookUrl: webhook,
      );
      final String? botName = legacy[AppConstants.keyBotName];
      if (botName != null && botName.isNotEmpty) {
        await write('profile_${profileId}_name', botName);
      }
      final String? channelId = legacy[AppConstants.keyChannelId];
      if (channelId != null && channelId.isNotEmpty) {
        await write('profile_${profileId}_channel', channelId);
      }
      final String? mode = legacy[AppConstants.keyMode];
      if (mode != null && mode.isNotEmpty) {
        await write('profile_${profileId}_mode', mode);
      }
    }

    // The legacy flat keys are cleared once migrated so that a single source
    // of truth exists for credentials.
    for (final String key in legacyKeys) {
      await delete(key);
    }
    return profileId;
  }

  /// Encodes a JSON payload for storage in a secure field.
  String encodeJson(Map<String, dynamic> value) => jsonEncode(value);

  /// Decodes a JSON payload previously stored with [encodeJson].
  Map<String, dynamic>? decodeJson(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }
}
