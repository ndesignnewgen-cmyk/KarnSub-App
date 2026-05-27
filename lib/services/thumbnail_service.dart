import 'package:flutter/services.dart';

/// Extracts evenly-spaced video frame thumbnails (saved as small JPEGs by the
/// native side) for the CapCut-style timeline filmstrip.
class ThumbnailService {
  static const _channel = MethodChannel('com.anniekaydee.subtitle_app/audio');

  /// Returns a list of (ms, path) sorted by time. [] on failure.
  static Future<List<({int ms, String path})>> extract(
    String videoPath, {
    int maxCount = 36,
    int height = 120,
  }) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'extractThumbnails',
        {'videoPath': videoPath, 'maxCount': maxCount, 'height': height},
      );
      final out = <({int ms, String path})>[];
      for (final e in raw ?? const []) {
        final m = (e as Map);
        final ms = (m['ms'] as num?)?.toInt();
        final path = m['path'] as String?;
        if (ms != null && path != null) out.add((ms: ms, path: path));
      }
      out.sort((a, b) => a.ms.compareTo(b.ms));
      return out;
    } catch (_) {
      return const [];
    }
  }
}
