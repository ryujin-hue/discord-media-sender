import 'package:discord_media_sender/core/formatters.dart';
import 'package:discord_media_sender/core/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Formatters.bytes', () {
    test('formats zero and small values', () {
      expect(Formatters.bytes(0), '0 B');
      expect(Formatters.bytes(512), '512 B');
      expect(Formatters.bytes(1024), '1.0 KB');
    });

    test('formats megabytes and gigabytes', () {
      expect(Formatters.bytes(1024 * 1024), '1.0 MB');
      expect(Formatters.bytes(1024 * 1024 * 1024), '1.0 GB');
    });

    test('does not produce a negative value', () {
      expect(Formatters.bytes(-10), '0 B');
    });
  });

  group('Formatters.duration', () {
    test('formats seconds, minutes and hours', () {
      expect(Formatters.duration(45), '45s');
      expect(Formatters.duration(90), '1m 30s');
      expect(Formatters.duration(3725), '1h 02m 05s');
    });

    test('shows an unavailable state for null', () {
      expect(Formatters.duration(null), '—');
    });
  });

  group('Formatters.maskSecret', () {
    test('masks the middle of a token', () {
      final String masked = Formatters.maskSecret('MTIzNDU2Nzg5MDEyMzQ1Njc4');
      expect(masked, isNot(contains('NDU2Nzg5')));
      expect(masked, contains('••••••••'));
    });

    test('reports a missing secret', () {
      expect(Formatters.maskSecret(null), 'Not set');
      expect(Formatters.maskSecret(''), 'Not set');
    });
  });

  group('Formatters.maskWebhook', () {
    test('keeps only the host and the webhook id', () {
      final String masked = Formatters.maskWebhook(
        'https://discord.com/api/webhooks/123456789012345678/abcdefGHIJKL',
      );
      expect(masked, contains('discord.com'));
      expect(masked, contains('123456789012345678'));
      expect(masked, isNot(contains('abcdefGHIJKL')));
    });
  });

  group('Formatters.fileName', () {
    test('keeps short names unchanged', () {
      expect(Formatters.fileName('photo.jpg'), 'photo.jpg');
    });

    test('truncates long names but keeps the extension', () {
      final String name =
          'a-very-long-file-name-that-should-be-truncated-for-display.jpg';
      final String formatted = Formatters.fileName(name);
      expect(formatted.length, lessThan(name.length));
      expect(formatted, endsWith('.jpg'));
    });
  });

  group('Formatters.count', () {
    test('adds thousands separators', () {
      expect(Formatters.count(1234), '1,234');
      expect(Formatters.count(1234567), '1,234,567');
      expect(Formatters.count(999), '999');
    });
  });

  group('Validators', () {
    test('rejects an empty bot token', () {
      expect(Validators.botToken(''), isNotNull);
      expect(Validators.botToken(null), isNotNull);
    });

    test('rejects a url pasted into the token field', () {
      expect(
        Validators.botToken('https://discord.com/api/v10/users/@me'),
        contains('URL'),
      );
    });

    test('rejects a token with invalid characters', () {
      expect(Validators.botToken('short token with spaces'), isNotNull);
    });

    test('accepts a plausible bot token', () {
      // Built from parts so that the repository never contains a literal that
      // looks like a real Discord bot token.
      final String token = List<String>.filled(3, 'x' * 30).join('.');
      expect(Validators.botToken(token), isNull);
    });

    test('validates webhook urls', () {
      expect(Validators.webhookUrl(''), isNotNull);
      expect(
        Validators.webhookUrl('http://discord.com/api/webhooks/1/a'),
        contains('HTTPS'),
      );
      expect(
        Validators.webhookUrl('https://example.com/api/webhooks/1/a'),
        contains('discord.com'),
      );
      expect(
        Validators.webhookUrl(
          'https://discord.com/api/webhooks/123456789012345678/abcdefGHIJKL',
        ),
        isNull,
      );
    });

    test('validates channel ids', () {
      expect(Validators.channelId(''), isNotNull);
      expect(Validators.channelId('123'), isNotNull);
      expect(Validators.channelId('123456789012345678'), isNull);
    });

    test('validates the maximum file size', () {
      expect(Validators.maxFileMb(''), isNotNull);
      expect(Validators.maxFileMb('0'), isNotNull);
      expect(Validators.maxFileMb('600'), isNotNull);
      expect(Validators.maxFileMb('100'), isNull);
    });

    test('validates github repositories', () {
      expect(
        Validators.githubRepo('tukiza7-debug/discord-media-sender'),
        isNull,
      );
      expect(Validators.githubRepo('not-a-repo'), isNotNull);
    });
  });
}
