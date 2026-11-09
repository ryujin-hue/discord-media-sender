import 'dart:async';

import 'package:flutter/services.dart';

/// Resolves Storage Access Framework URIs into local files.
///
/// Android hands the app a `content://` URI when the user picks a document.
/// The upload engine, the duplicate detector and the thumbnailer all work on
/// real files, so every picked item is resolved to a readable local path
/// first. When Android does not expose a path, the content is copied into the
/// app cache.
class MediaResolver {
  MediaResolver._();

  static const MethodChannel _channel = MethodChannel(
    'com.dmsender.discord_media_sender/media',
  );

  /// Resolves [uri] into a local path.
  ///
  /// Returns null when the content cannot be read.
  static Future<String?> resolvePath(String uri, {String? name}) async {
    try {
      final String? path = await _channel.invokeMethod<String>(
        'resolvePath',
        <String, dynamic>{'uri': uri, 'name': name},
      );
      return path;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Reads the raw bytes behind [uri].
  ///
  /// Only used for small payloads; large files are resolved to a path instead.
  static Future<List<int>?> readBytes(String uri) async {
    try {
      final Uint8List? bytes = await _channel.invokeMethod<Uint8List>(
        'readBytes',
        <String, dynamic>{'uri': uri},
      );
      return bytes;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Lists every file inside a Storage Access Framework tree.
  ///
  /// Returns an empty list when the tree cannot be read.
  static Future<List<TreeFile>> listTreeFiles(String uri) async {
    try {
      final List<dynamic>? payload = await _channel.invokeMethod<List<dynamic>>(
        'listTreeFiles',
        <String, dynamic>{'uri': uri},
      );
      if (payload == null) return const <TreeFile>[];
      return payload
          .whereType<Map<dynamic, dynamic>>()
          .map(TreeFile.fromMap)
          .toList();
    } on PlatformException {
      return const <TreeFile>[];
    } on MissingPluginException {
      return const <TreeFile>[];
    }
  }
}

/// A file discovered inside a Storage Access Framework tree.
class TreeFile {
  const TreeFile({
    required this.path,
    required this.name,
    required this.size,
    required this.mimeType,
    required this.modifiedAt,
  });

  final String path;
  final String name;
  final int size;
  final String mimeType;
  final int modifiedAt;

  factory TreeFile.fromMap(Map<dynamic, dynamic> map) => TreeFile(
    path: map['path'] as String? ?? '',
    name: map['name'] as String? ?? '',
    size: (map['size'] as num?)?.toInt() ?? 0,
    mimeType: map['mimeType'] as String? ?? 'application/octet-stream',
    modifiedAt: (map['modifiedAt'] as num?)?.toInt() ?? 0,
  );
}
