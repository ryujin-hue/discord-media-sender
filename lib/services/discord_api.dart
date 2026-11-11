import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../core/constants.dart';
import '../core/error_translator.dart';
import '../core/security.dart';

/// Result of a Discord send operation.
class DiscordSendResult {
  const DiscordSendResult({
    required this.success,
    this.messageId,
    this.messageUrl,
    this.httpCode,
    this.discordCode,
    this.errorMessage,
    this.attachmentUrls = const <String>[],
    this.rateLimitRetries = 0,
  });

  final bool success;
  final String? messageId;
  final String? messageUrl;
  final int? httpCode;
  final int? discordCode;
  final String? errorMessage;
  final List<String> attachmentUrls;
  final int rateLimitRetries;
}

/// A validated webhook descriptor.
class WebhookInfo {
  const WebhookInfo({
    required this.id,
    required this.name,
    required this.channelId,
    this.guildId,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String? channelId;
  final String? guildId;
  final String? avatarUrl;
}

/// Identity information returned by `GET /users/@me`.
class BotIdentity {
  const BotIdentity({
    required this.id,
    required this.username,
    this.discriminator,
    this.avatar,
    this.bot = true,
  });

  final String id;
  final String username;
  final String? discriminator;
  final String? avatar;
  final bool bot;
}

/// A Discord guild (server) the bot has joined.
class DiscordGuild {
  const DiscordGuild({
    required this.id,
    required this.name,
    this.icon,
    this.owner = false,
  });

  final String id;
  final String name;
  final String? icon;
  final bool owner;
}

/// A Discord channel.
class DiscordChannel {
  const DiscordChannel({
    required this.id,
    required this.name,
    required this.type,
    this.parentId,
    this.guildId,
  });

  final String id;
  final String name;
  final int type;
  final String? parentId;
  final String? guildId;

  /// Channel types that accept file uploads.
  bool get supportsFiles {
    // 0 guild text, 5 announcement, 10/11/12 threads, 13/14 media channels.
    return const <int>{0, 5, 10, 11, 12, 13, 14, 15, 16}.contains(type);
  }
}

/// Raised when Discord refuses a request.
class DiscordException implements Exception {
  DiscordException(
    this.message, {
    this.statusCode,
    this.discordCode,
    this.retryAfter,
  });

  final String message;
  final int? statusCode;
  final int? discordCode;
  final Duration? retryAfter;

  @override
  String toString() => message;
}

/// Low level Discord REST API v10 client.
///
/// Implements the rate-limit contract of the Discord API: `429` responses are
/// retried after the delay requested by Discord (`retry_after` body field or
/// the `x-ratelimit-reset-after` header) and the shared per-bucket /
/// per-route limiter is respected before every request.
class DiscordApiClient {
  DiscordApiClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(minutes: 10),
              sendTimeout: const Duration(minutes: 30),
              responseType: ResponseType.json,
              headers: <String, dynamic>{
                'User-Agent': AppConstants.discordUserAgent,
              },
            ),
          ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          options.headers['User-Agent'] = AppConstants.discordUserAgent;
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;

  /// Per-route buckets: key -> time when the bucket becomes usable again.
  final Map<String, DateTime> _buckets = <String, DateTime>{};

  /// Per-route remaining request count, used to short-circuit known-empty
  /// buckets instead of burning a request to learn it is empty.
  final Map<String, int> _remaining = <String, int>{};

  /// Global cooldown applied after a global rate limit was hit.
  DateTime? _globalCooldownUntil;

  /// Maximum number of automatic retries for a single request.
  static const int maxRetries = 5;

  void _resetBuckets() {
    _buckets.clear();
    _remaining.clear();
    _globalCooldownUntil = null;
  }

  /// Waits until the route bucket allows another request.
  Future<void> _awaitBucket(String key) async {
    final DateTime? globalUntil = _globalCooldownUntil;
    if (globalUntil != null && globalUntil.isAfter(DateTime.now())) {
      await Future<void>.delayed(globalUntil.difference(DateTime.now()));
      _globalCooldownUntil = null;
    }
    final DateTime? ready = _buckets[key];
    if (ready != null && ready.isAfter(DateTime.now())) {
      await Future<void>.delayed(ready.difference(DateTime.now()));
    }
  }

  void _recordBucket(String key, Response<dynamic>? response) {
    final Headers? headers = response?.headers;
    if (headers == null) return;
    final String? remaining = headers.value('x-ratelimit-remaining');
    final String? resetAfter = headers.value('x-ratelimit-reset-after');
    final bool isGlobal = headers.value('x-ratelimit-global') == 'true';
    if (remaining != null) {
      _remaining[key] = int.tryParse(remaining) ?? 0;
    }
    if (resetAfter != null) {
      final double seconds = double.tryParse(resetAfter) ?? 1;
      final DateTime ready = DateTime.now().add(
        Duration(milliseconds: (seconds * 1000).round()),
      );
      if (isGlobal) {
        _globalCooldownUntil = ready;
      } else {
        _buckets[key] = ready;
      }
    }
  }

  /// Performs a request with Discord-compliant retry behaviour.
  Future<Response<dynamic>> _request(
    String method,
    String path, {
    Object? body,
    Options? options,
    Map<String, dynamic>? query,
    String? bearerToken,
    bool authenticated = true,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    final String url = path.startsWith('http')
        ? path
        : '${AppConstants.discordApiBase}$path';
    final String bucketKey = '$method $url';

    int attempt = 0;
    while (true) {
      attempt++;
      await _awaitBucket(bucketKey);

      final Options base = options ?? Options();
      final RequestOptions request = RequestOptions(
        path: url,
        method: method,
        headers: <String, dynamic>{
          'User-Agent': AppConstants.discordUserAgent,
          if (authenticated && bearerToken != null)
            'Authorization': 'Bot $bearerToken',
          ...?base.headers,
        },
        data: body,
        contentType: base.contentType,
        responseType: base.responseType,
        sendTimeout: base.sendTimeout,
        receiveTimeout: base.receiveTimeout,
        connectTimeout: base.connectTimeout,
        followRedirects: base.followRedirects,
        maxRedirects: base.maxRedirects,
        validateStatus: base.validateStatus,
        queryParameters: query,
        onSendProgress: onSendProgress,
      );

      try {
        final Response<dynamic> response = await _dio.fetch<dynamic>(request);
        _recordBucket(bucketKey, response);
        return response;
      } on DioException catch (error) {
        final Response<dynamic>? response = error.response;
        _recordBucket(bucketKey, response);

        final int status = response?.statusCode ?? 0;
        if (status == 429) {
          Duration retryAfter = _retryAfterFrom(response);
          if (attempt >= maxRetries) {
            throw DiscordException(
              'Rate limited by Discord. The request will be retried automatically.',
              statusCode: 429,
              retryAfter: retryAfter,
            );
          }
          await Future<void>.delayed(retryAfter);
          continue;
        }

        if (status >= 500 && attempt < maxRetries) {
          // Discord edge failures are transient; back off and try again.
          await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
          continue;
        }

        throw _toDiscordException(error);
      }
    }
  }

  Duration _retryAfterFrom(Response<dynamic>? response) {
    if (response == null) return const Duration(seconds: 1);
    final dynamic body = response.data;
    if (body is Map<String, dynamic>) {
      final double? retryAfter = body['retry_after'] is num
          ? (body['retry_after'] as num).toDouble()
          : null;
      if (retryAfter != null) {
        return Duration(milliseconds: (retryAfter * 1000).ceil());
      }
    }
    final String? header = response.headers.value('retry-after');
    if (header != null) {
      final double? seconds = double.tryParse(header);
      if (seconds != null) {
        return Duration(milliseconds: (seconds * 1000).ceil());
      }
    }
    final String? resetAfter = response.headers.value(
      'x-ratelimit-reset-after',
    );
    if (resetAfter != null) {
      final double? seconds = double.tryParse(resetAfter);
      if (seconds != null) {
        return Duration(milliseconds: (seconds * 1000).ceil());
      }
    }
    return const Duration(seconds: 1);
  }

  DiscordException _toDiscordException(DioException error) {
    final Response<dynamic>? response = error.response;
    final int status = response?.statusCode ?? 0;
    dynamic data = response?.data;

    int? discordCode;
    String? rawBody;
    if (data is Map<String, dynamic>) {
      discordCode = data['code'] as int?;
      rawBody = jsonEncode(data);
    } else if (data is String) {
      rawBody = data;
    }

    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return DiscordException(
        ErrorTranslator.fromNetwork(error.error ?? error),
      );
    }

    return DiscordException(
      ErrorTranslator.fromDiscordResponse(
        statusCode: status,
        body: rawBody,
        discordCode: discordCode,
      ),
      statusCode: status == 0 ? null : status,
      discordCode: discordCode,
    );
  }

  // ---------------------------------------------------------------------------
  // Bot endpoints
  // ---------------------------------------------------------------------------

  /// Validates a bot token and returns the bot identity.
  Future<BotIdentity> validateBot(String token) async {
    final Response<dynamic> response = await _request(
      'GET',
      '/users/@me',
      bearerToken: token,
    );
    final Map<String, dynamic> data = response.data as Map<String, dynamic>;
    return BotIdentity(
      id: data['id'] as String? ?? '',
      username: data['username'] as String? ?? 'Unknown',
      discriminator: data['discriminator'] as String?,
      avatar: data['avatar'] as String?,
      bot: data['bot'] as bool? ?? true,
    );
  }

  /// Lists the servers the bot has joined.
  Future<List<DiscordGuild>> listGuilds(String token, {String? after}) async {
    final Response<dynamic> response = await _request(
      'GET',
      '/users/@me/guilds',
      bearerToken: token,
      query: <String, dynamic>{
        'with_counts': 'false',
        'limit': 100,
        if (after != null && after.isNotEmpty) 'after': after,
      },
    );
    final dynamic data = response.data;
    if (data is! List) return <DiscordGuild>[];
    return data
        .cast<Map<String, dynamic>>()
        .map(
          (Map<String, dynamic> guild) => DiscordGuild(
            id: guild['id'] as String? ?? '',
            name: guild['name'] as String? ?? '',
            icon: guild['icon'] as String?,
            owner: guild['owner'] as bool? ?? false,
          ),
        )
        .toList();
  }

  /// Lists the channels of a guild.
  Future<List<DiscordChannel>> listChannels(
    String token,
    String guildId,
  ) async {
    final Response<dynamic> response = await _request(
      'GET',
      '/guilds/$guildId/channels',
      bearerToken: token,
    );
    final dynamic data = response.data;
    if (data is! List) return <DiscordChannel>[];
    return data.cast<Map<String, dynamic>>().map((
      Map<String, dynamic> channel,
    ) {
      final Map<String, dynamic>? parent = channel['parent_id'] is String
          ? <String, dynamic>{'id': channel['parent_id']}
          : null;
      return DiscordChannel(
        id: channel['id'] as String? ?? '',
        name: channel['name'] as String? ?? '',
        type: channel['type'] as int? ?? 0,
        parentId: parent?['id'] as String?,
        guildId: guildId,
      );
    }).toList();
  }

  /// Creates a text channel inside a guild.
  Future<DiscordChannel> createChannel(
    String token,
    String guildId,
    String name, {
    int type = 0,
  }) async {
    final Response<dynamic> response = await _request(
      'POST',
      '/guilds/$guildId/channels',
      bearerToken: token,
      body: <String, dynamic>{'name': name, 'type': type},
    );
    final Map<String, dynamic> data = response.data as Map<String, dynamic>;
    return DiscordChannel(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? name,
      type: data['type'] as int? ?? type,
      guildId: guildId,
    );
  }

  /// Creates a webhook in a channel.
  ///
  /// Requires the bot to have the *Manage Webhooks* permission in the target
  /// channel; Discord returns 403 otherwise.
  Future<WebhookInfo> createWebhook(
    String token,
    String channelId,
    String name, {
    String? avatarBase64,
  }) async {
    final Response<dynamic> response = await _request(
      'POST',
      '/channels/$channelId/webhooks',
      bearerToken: token,
      body: <String, dynamic>{'name': name, 'avatar': ?avatarBase64},
    );
    final Map<String, dynamic> data = response.data as Map<String, dynamic>;
    return WebhookInfo(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? name,
      channelId: data['channel_id'] as String?,
      guildId: data['guild_id'] as String?,
    );
  }

  /// Fetches the metadata of an existing webhook.
  Future<WebhookInfo> fetchWebhook(String webhookUrl) async {
    final Uri uri = Uri.parse(webhookUrl);
    final Response<dynamic> response = await _request(
      'GET',
      '$uri?with_counts=false',
      authenticated: false,
    );
    final Map<String, dynamic> data = response.data as Map<String, dynamic>;
    return WebhookInfo(
      id: data['id'] as String? ?? '',
      name: data['name'] as String? ?? '',
      channelId: data['channel_id'] as String?,
      guildId: data['guild_id'] as String?,
      avatarUrl: data['avatar'] as String?,
    );
  }

  /// Deletes a webhook (requires ownership of the webhook).
  Future<void> deleteWebhook(String webhookUrl) async {
    final Uri uri = Uri.parse(webhookUrl);
    await _request('DELETE', '$uri', authenticated: false);
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  /// Sends files through a webhook.
  Future<DiscordSendResult> sendWebhook(
    String webhookUrl, {
    required List<File> files,
    String? content,
    String? username,
    String? avatarUrl,
    void Function(int sent, int total)? onProgress,
    int? bandwidthBytesPerSecond,
  }) async {
    final FormData form = FormData();
    if (content != null && content.isNotEmpty) {
      form.fields.add(
        MapEntry<String, String>(
          'payload_json',
          jsonEncode(<String, dynamic>{
            'content': content,
            if (username != null && username.isNotEmpty) 'username': username,
            if (avatarUrl != null && avatarUrl.isNotEmpty)
              'avatar_url': avatarUrl,
          }),
        ),
      );
    }

    int index = 0;
    for (final File file in files) {
      form.files.add(
        MapEntry<String, MultipartFile>(
          'files[$index]',
          _multipartFor(file, bandwidthBytesPerSecond),
        ),
      );
      index++;
    }

    return _sendMultipart(
      webhookUrl,
      form,
      files: files,
      onProgress: onProgress,
      authenticated: false,
    );
  }

  /// Sends files as a bot message into a channel.
  Future<DiscordSendResult> sendBotMessage(
    String token,
    String channelId, {
    required List<File> files,
    String? content,
    void Function(int sent, int total)? onProgress,
    int? bandwidthBytesPerSecond,
  }) async {
    final FormData form = FormData();
    if (content != null && content.isNotEmpty) {
      form.fields.add(
        MapEntry<String, String>(
          'payload_json',
          jsonEncode(<String, dynamic>{'content': content}),
        ),
      );
    }

    int index = 0;
    for (final File file in files) {
      form.files.add(
        MapEntry<String, MultipartFile>(
          'files[$index]',
          _multipartFor(file, bandwidthBytesPerSecond),
        ),
      );
      index++;
    }

    return _sendMultipart(
      '/channels/$channelId/messages',
      form,
      files: files,
      onProgress: onProgress,
      bearerToken: token,
    );
  }

  Future<DiscordSendResult> _sendMultipart(
    String path,
    FormData form, {
    required List<File> files,
    void Function(int sent, int total)? onProgress,
    String? bearerToken,
    bool authenticated = true,
  }) async {
    final Options options = Options(
      method: 'POST',
      contentType: 'multipart/form-data',
      sendTimeout: const Duration(minutes: 30),
      receiveTimeout: const Duration(minutes: 10),
    );

    // Dio reports the bytes of the multipart body that were flushed to the
    // socket. The body is slightly larger than the raw file bytes because of
    // the multipart framing, so the raw byte figure is derived from the
    // ratio between the two.
    final int rawTotal = _totalFileBytes(files);
    void Function(int, int)? progressAdapter;
    if (onProgress != null) {
      progressAdapter = (int sent, int total) {
        if (total <= 0) return;
        final double ratio = sent / total;
        onProgress((ratio * rawTotal).round(), rawTotal);
      };
    }

    try {
      final Response<dynamic> response = await _request(
        'POST',
        path,
        body: form,
        options: options,
        bearerToken: bearerToken,
        authenticated: authenticated,
        onSendProgress: progressAdapter,
      );
      return _parseSendResponse(response);
    } on DiscordException catch (error) {
      return DiscordSendResult(
        success: false,
        httpCode: error.statusCode,
        discordCode: error.discordCode,
        errorMessage: error.message,
      );
    } catch (error) {
      return DiscordSendResult(
        success: false,
        errorMessage: ErrorTranslator.translate(error),
      );
    }
  }

  /// Builds the multipart entry of a file.
  ///
  /// Without a bandwidth cap the file is attached directly, which lets dio
  /// stream it from the disk. With a cap the file is streamed through a
  /// rate limiter, so the upload really is slowed down instead of only
  /// reporting a lower speed.
  static MultipartFile _multipartFor(File file, int? bandwidthBytesPerSecond) {
    final String filename = _fileName(file.path);
    final int? cap = bandwidthBytesPerSecond;
    if (cap == null || cap <= 0) {
      return MultipartFile.fromFileSync(file.path, filename: filename);
    }
    int length;
    try {
      length = file.lengthSync();
    } catch (_) {
      return MultipartFile.fromFileSync(file.path, filename: filename);
    }
    return MultipartFile.fromStream(
      () => _throttledStream(file, cap),
      length,
      filename: filename,
    );
  }

  /// Streams a file while holding the transfer down to [bytesPerSecond].
  static Stream<List<int>> _throttledStream(
    File file,
    int bytesPerSecond,
  ) async* {
    final DateTime start = DateTime.now();
    int sent = 0;
    await for (final List<int> chunk in file.openRead()) {
      yield chunk;
      sent += chunk.length;
      final int expectedMs = sent * 1000 ~/ bytesPerSecond;
      final int elapsedMs = DateTime.now().difference(start).inMilliseconds;
      final int delayMs = expectedMs - elapsedMs;
      if (delayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }
  }

  static int _totalFileBytes(List<File> files) {
    int total = 0;
    for (final File file in files) {
      try {
        total += file.lengthSync();
      } catch (_) {}
    }
    return total;
  }

  DiscordSendResult _parseSendResponse(Response<dynamic> response) {
    final dynamic data = response.data;
    String? messageId;
    String? messageUrl;
    final List<String> attachments = <String>[];

    if (data is Map<String, dynamic>) {
      messageId = data['id'] as String?;
      if (messageId != null) {
        final String? channelId = data['channel_id'] as String?;
        final String? guildId = data['guild_id'] as String?;
        if (guildId != null && channelId != null) {
          messageUrl =
              'https://discord.com/channels/$guildId/$channelId/$messageId';
        } else if (channelId != null) {
          messageUrl = 'https://discord.com/channels/@me/$channelId/$messageId';
        }
      }
      final dynamic rawAttachments = data['attachments'];
      if (rawAttachments is List) {
        for (final dynamic attachment in rawAttachments) {
          if (attachment is Map<String, dynamic>) {
            final String? url = attachment['url'] as String?;
            if (url != null) attachments.add(url);
          }
        }
      }
    }

    return DiscordSendResult(
      success: true,
      messageId: messageId,
      messageUrl: messageUrl,
      httpCode: response.statusCode,
      attachmentUrls: attachments,
    );
  }

  static String _fileName(String path) {
    final int index = path.lastIndexOf('/');
    return index >= 0 ? path.substring(index + 1) : path;
  }

  /// Clears the cached rate-limit buckets.
  ///
  /// Called when the user switches profiles so a stale bucket cannot delay an
  /// unrelated request.
  void invalidateBuckets() => _resetBuckets();

  /// Redacts any secret that may be present in a diagnostic string.
  static String redact(String value) => Security.redactSecrets(value);
}
