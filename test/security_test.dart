import 'dart:io';

import 'package:discord_media_sender/core/security.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Security.sha256File', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dms_hash_test');
    });

    tearDown(() async {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('produces the well known digest of "abc"', () async {
      final File file = File('${tempDir.path}/abc.bin');
      await file.writeAsString('abc');

      final String hash = await Security.sha256File(file.path);

      expect(
        hash,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('identical content produces identical hashes', () async {
      final File first = File('${tempDir.path}/first.bin');
      final File second = File('${tempDir.path}/second.bin');
      await first.writeAsString('identical content');
      await second.writeAsString('identical content');

      expect(
        await Security.sha256File(first.path),
        await Security.sha256File(second.path),
      );
    });

    test('a renamed file keeps the same hash', () async {
      final File original = File('${tempDir.path}/original.jpg');
      final File renamed = File('${tempDir.path}/renamed.png');
      await original.writeAsString('binary-ish payload');
      await renamed.writeAsString('binary-ish payload');

      expect(
        await Security.sha256File(original.path),
        await Security.sha256File(renamed.path),
      );
    });

    test('different content produces different hashes', () async {
      final File first = File('${tempDir.path}/a.bin');
      final File second = File('${tempDir.path}/b.bin');
      await first.writeAsString('content A');
      await second.writeAsString('content B');

      expect(
        await Security.sha256File(first.path),
        isNot(await Security.sha256File(second.path)),
      );
    });

    test('streams files larger than a single chunk', () async {
      final File file = File('${tempDir.path}/large.bin');
      final List<int> payload = List<int>.generate(
        1024 * 1024 * 3,
        (int i) => i % 251,
      );
      await file.writeAsBytes(payload);

      final String hash = await Security.sha256File(
        file.path,
        chunkSize: 64 * 1024,
      );

      expect(hash, hasLength(64));
      expect(hash, Security.sha256Bytes(payload));
    });

    test('reports progress while hashing', () async {
      final File file = File('${tempDir.path}/progress.bin');
      await file.writeAsBytes(List<int>.filled(200 * 1024, 7));

      final List<int> seen = <int>[];
      await Security.sha256File(
        file.path,
        chunkSize: 64 * 1024,
        onProgress: seen.add,
      );

      expect(seen, isNotEmpty);
      expect(seen.last, 200 * 1024);
    });
  });

  group('Security.redactSecrets', () {
    test('removes a webhook url', () {
      const String input =
          'failed to post to https://discord.com/api/webhooks/123456789/abcdefToken';
      final String output = Security.redactSecrets(input);

      expect(output, isNot(contains('abcdefToken')));
      expect(output, contains('webhook-redacted'));
    });

    test('removes a bot token', () {
      // Built at runtime so that the repository never contains a literal that
      // looks like a real Discord bot token.
      final String token = List<String>.filled(3, 'x' * 30).join('.');
      final String output = Security.redactSecrets('token is $token');

      expect(output, isNot(contains(token)));
      expect(output, contains('token-redacted'));
    });

    test('leaves ordinary messages untouched', () {
      const String input = 'Upload finished with 3 failures';
      expect(Security.redactSecrets(input), input);
    });
  });

  test('pathFingerprint is stable and does not contain the path', () {
    final String fingerprint = Security.pathFingerprint(
      '/storage/emulated/0/DCIM/a.jpg',
    );

    expect(fingerprint, hasLength(16));
    expect(fingerprint, isNot(contains('DCIM')));
    expect(
      fingerprint,
      Security.pathFingerprint('/storage/emulated/0/DCIM/a.jpg'),
    );
  });
}
