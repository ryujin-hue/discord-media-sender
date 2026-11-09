import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

/// Cryptographic helpers used by the duplicate detection engine.
class Security {
  Security._();

  /// Computes the SHA-256 digest of a file as a lowercase hex string.
  ///
  /// The file is streamed in [chunkSize] blocks so that multi-gigabyte files
  /// never have to be held in memory.
  static Future<String> sha256File(
    String path, {
    int chunkSize = 1024 * 1024,
    void Function(int bytesRead)? onProgress,
  }) async {
    final RandomAccessFile handle = await File(path).open();
    try {
      final AccumulatorSink<Digest> sink = AccumulatorSink<Digest>();
      final ByteConversionSink input = sha256.startChunkedConversion(sink);
      int bytesRead = 0;
      while (true) {
        final Uint8List chunk = await handle.read(chunkSize);
        if (chunk.isEmpty) break;
        input.add(chunk);
        bytesRead += chunk.length;
        onProgress?.call(bytesRead);
      }
      input.close();
      return sink.events.single.toString();
    } finally {
      await handle.close();
    }
  }

  /// Computes the SHA-256 digest of an in-memory buffer.
  static String sha256Bytes(List<int> bytes) =>
      sha256.convert(bytes).toString();

  /// Computes a SHA-256 digest of a string payload.
  static String sha256String(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  /// A stable, non-reversible short identifier for a path.
  ///
  /// Used to correlate records without leaking the path itself.
  static String pathFingerprint(String path) {
    final String digest = sha256String(path);
    return digest.substring(0, 16);
  }

  /// Generates a random URL-safe identifier.
  static String randomId([int length = 16]) {
    const String alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final Random random = Random.secure();
    return List<String>.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  /// Best-effort masking of any secret-looking substring inside free text.
  ///
  /// Used before writing error messages to logs or the activity timeline so
  /// that a token accidentally embedded in an exception cannot leak.
  static String redactSecrets(String input) {
    String output = input;
    output = output.replaceAllMapped(
      RegExp(
        r'https://(?:ptb\.|canary\.)?discord(?:app)?\.com/api/webhooks/\d+/[A-Za-z0-9_\-]+',
      ),
      (_) => '[webhook-redacted]',
    );
    output = output.replaceAllMapped(
      RegExp(
        r'\b[A-Za-z0-9_\-]{24,}\.[A-Za-z0-9_\-]{6,}\.[A-Za-z0-9_\-]{20,}\b',
      ),
      (_) => '[token-redacted]',
    );
    return output;
  }
}
