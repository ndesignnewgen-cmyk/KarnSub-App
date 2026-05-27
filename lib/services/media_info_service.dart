import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Extracts a video thumbnail + duration via native MediaMetadataRetriever.
class MediaInfoService {
  static const _channel = MethodChannel('com.anniekaydee.subtitle_app/audio');

  /// Returns (thumbPath, durationMs). Thumbnail is cached under app support
  /// using [cacheKey] (e.g. the project id) so it's stable across launches.
  static Future<({String? thumb, int durationMs})> meta(
    String videoPath,
    String cacheKey,
  ) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final thumbDir = Directory('${dir.path}/thumbs');
      if (!thumbDir.existsSync()) thumbDir.createSync(recursive: true);
      final thumbPath = '${thumbDir.path}/$cacheKey.jpg';

      final res = await _channel.invokeMethod('videoMeta', {
        'videoPath': videoPath,
        'thumbPath': thumbPath,
      });
      final map = (res as Map);
      final dur = (map['durationMs'] as num?)?.toInt() ?? -1;
      final thumb = map['thumb'] as String?;
      return (thumb: thumb, durationMs: dur);
    } catch (_) {
      return (thumb: null, durationMs: -1);
    }
  }
}
