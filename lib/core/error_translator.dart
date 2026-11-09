import 'dart:io';

/// Translates raw errors (Discord API, network, filesystem) into short,
/// actionable messages that the user can act on.
class ErrorTranslator {
  ErrorTranslator._();

  /// Discord API error codes that have a well-known meaning.
  static const Map<int, String> _discordCodes = <int, String>{
    50001: 'Missing access to this channel',
    50013: 'Missing permission for this channel',
    50014: 'The bot is not in this server',
    50035: 'Invalid request for this channel type',
    10003: 'Unknown channel',
    10004: 'Unknown server',
    10007: 'Unknown member',
    10013: 'Unknown webhook',
    20001: 'The bot was removed from the server',
    30003: 'Too many channels',
    40001: 'Missing access',
    50001 + 1: 'Channel does not support attachments',
  };

  /// Formats a Discord JSON error payload into a readable sentence.
  static String fromDiscordResponse({
    required int statusCode,
    String? body,
    int? discordCode,
  }) {
    final String? lower = body?.toLowerCase();
    if (statusCode == 401) {
      return 'Authentication failed. The bot token is invalid or was revoked.';
    }
    if (statusCode == 403) {
      return 'Access denied. The bot is missing permissions for this channel.';
    }
    if (statusCode == 404) {
      return 'Not found. The channel, webhook or server no longer exists.';
    }
    if (statusCode == 429) {
      return 'Rate limited by Discord. The request will be retried automatically.';
    }
    if (statusCode >= 500) {
      return 'Discord server error ($statusCode). The upload will be retried.';
    }
    if (statusCode == 413) {
      return 'The file is too large for Discord (max 100 MB per file).';
    }
    if (discordCode != null && _discordCodes.containsKey(discordCode)) {
      return _discordCodes[discordCode]!;
    }
    if (lower != null) {
      if (lower.contains('payload too large')) {
        return 'The total request size exceeds the Discord limit.';
      }
      if (lower.contains('rate limit')) {
        return 'Rate limited by Discord. The request will be retried automatically.';
      }
      if (lower.contains('maximum number of files')) {
        return 'Too many files in one request. Reduce the number of files per batch.';
      }
      if (lower.contains('cannot send')) {
        return 'This channel does not allow attachments.';
      }
    }
    if (statusCode >= 400) {
      return 'Discord rejected the request (HTTP $statusCode).';
    }
    return 'Unexpected Discord response (HTTP $statusCode).';
  }

  /// Maps a [SocketException] / [HttpException] style failure to a message.
  static String fromNetwork(Object error) {
    if (error is SocketException) {
      final String text = error.message.toLowerCase();
      if (text.contains('failed host lookup') ||
          text.contains('nodename nor servname')) {
        return 'No internet connection. Check your network and try again.';
      }
      if (text.contains('connection refused') ||
          text.contains('connection reset')) {
        return 'The connection to Discord was interrupted.';
      }
      if (text.contains('timed out') || text.contains('timeout')) {
        return 'The connection to Discord timed out.';
      }
      return 'Network error: ${error.message}';
    }
    if (error is HttpException) {
      return 'Network error: ${error.message}';
    }
    return 'Network error: $error';
  }

  /// Maps a filesystem failure to a message.
  static String fromFileSystem(Object error) {
    if (error is FileSystemException) {
      final String path = error.path ?? '';
      if (error.osError?.errorCode == 2) {
        return 'File not found${path.isEmpty ? '' : ': $path'}';
      }
      if (error.osError?.errorCode == 13) {
        return 'Permission denied for $path';
      }
      if (error.osError?.errorCode == 28) {
        return 'Not enough storage space to complete the operation';
      }
      if (error.osError?.errorCode == 39) {
        return 'The destination folder does not exist';
      }
      return 'File error: ${error.osError?.message ?? error.message}';
    }
    return 'File error: $error';
  }

  /// Maps an Android permission failure to an actionable message.
  static String fromPermission(Object error) {
    final String text = error.toString().toLowerCase();
    if (text.contains('denied') || text.contains('permanentlydenied')) {
      return 'Permission denied. Enable it in Settings > Apps > Discord Media Sender.';
    }
    if (text.contains('restricted')) {
      return 'This permission is restricted by the system.';
    }
    return 'Permission error: $error';
  }

  /// Best effort translation for any error object.
  static String translate(Object error) {
    if (error is SocketException) return fromNetwork(error);
    if (error is HttpException) return fromNetwork(error);
    if (error is FileSystemException) return fromFileSystem(error);
    return 'Unexpected error: $error';
  }
}
