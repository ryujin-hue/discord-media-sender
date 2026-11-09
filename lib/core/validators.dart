/// Input validators for credentials, URLs and file constraints.
class Validators {
  Validators._();

  static final RegExp _botTokenPattern = RegExp(r'^[\w\-\.]{50,120}$');
  static final RegExp _discordIdPattern = RegExp(r'^\d{17,20}$');
  static final RegExp _webhookPattern = RegExp(
    r'^https://(?:ptb\.|canary\.)?discord(?:app)?\.com/api/webhooks/\d+/[A-Za-z0-9_\-]+$',
  );

  /// Validates a Discord bot token shape.
  ///
  /// The shape check is deliberately permissive about the exact segment count
  /// (Discord has changed the format before) but rejects obvious mistakes such
  /// as an empty value or a URL pasted into the token field.
  static String? botToken(String? value) {
    final String token = (value ?? '').trim();
    if (token.isEmpty) return 'Bot token is required';
    if (token.startsWith('http')) {
      return 'This looks like a URL, not a bot token';
    }
    if (token.length < 40) {
      return 'Bot token is too short (expected at least 40 characters)';
    }
    if (!_botTokenPattern.hasMatch(token)) {
      return 'Bot token contains invalid characters';
    }
    return null;
  }

  /// Validates a Discord webhook URL.
  static String? webhookUrl(String? value) {
    final String url = (value ?? '').trim();
    if (url.isEmpty) return 'Webhook URL is required';
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return 'Webhook URL is not a valid URL';
    if (uri.scheme != 'https') return 'Webhook URL must use HTTPS';
    if (!uri.host.endsWith('discord.com') &&
        !uri.host.endsWith('discordapp.com')) {
      return 'Webhook URL must point to discord.com';
    }
    if (!_webhookPattern.hasMatch(url)) {
      return 'Webhook URL does not match the expected Discord format';
    }
    return null;
  }

  /// Validates a Discord channel id.
  static String? channelId(String? value) {
    final String id = (value ?? '').trim();
    if (id.isEmpty) return 'Channel ID is required';
    if (!_discordIdPattern.hasMatch(id)) {
      return 'Channel ID must be a 17-20 digit snowflake';
    }
    return null;
  }

  /// Validates a numeric maximum file size in megabytes.
  static String? maxFileMb(String? value) {
    final String raw = (value ?? '').trim();
    if (raw.isEmpty) return 'Enter a size in MB';
    final int? parsed = int.tryParse(raw);
    if (parsed == null) return 'Enter a whole number';
    if (parsed < 1) return 'Minimum is 1 MB';
    if (parsed > 500) return 'Maximum is 500 MB';
    return null;
  }

  /// Validates a non-empty profile / destination name.
  static String? requiredName(String? value) {
    final String name = (value ?? '').trim();
    if (name.isEmpty) return 'Name is required';
    if (name.length > 60) return 'Keep the name under 60 characters';
    return null;
  }

  /// Validates an optional https URL (used for release pages and avatars).
  static String? optionalHttpsUrl(String? value) {
    final String url = (value ?? '').trim();
    if (url.isEmpty) return null;
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Enter a valid URL';
    }
    if (uri.scheme != 'https') return 'Only HTTPS URLs are allowed';
    return null;
  }

  /// Validates a GitHub `owner/repo` reference.
  static String? githubRepo(String? value) {
    final String raw = (value ?? '').trim();
    if (raw.isEmpty) return 'Repository is required';
    final RegExp pattern = RegExp(r'^[\w.\-]+/[\w.\-]+$');
    if (!pattern.hasMatch(raw)) return 'Use the owner/repository format';
    return null;
  }
}
