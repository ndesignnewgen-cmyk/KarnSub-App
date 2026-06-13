import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Merges several clips into one MP4 via the native MediaMuxer concat
/// (lossless, no re-encode). Best for clips that share the same size/codec
/// (e.g. shot on the same phone).
class VideoMergeService {
  static const _channel = MethodChannel('com.anniekaydee.subtitle_app/audio');

  /// Returns the path of the merged file. Throws [VideoMergeException] with
  /// `incompatible == true` when the clips differ in size/format.
  static Future<String> merge(List<String> paths) async {
    final tempDir = await getTemporaryDirectory();
    final out = p.join(
      tempDir.path,
      'merged_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    try {
      final result = await _channel.invokeMethod<String>('mergeVideos', {
        'paths': paths,
        'outputPath': out,
      });
      if (result == null || result.isEmpty) {
        throw VideoMergeException('merge returned empty path');
      }
      return result;
    } on PlatformException catch (e) {
      throw VideoMergeException(
        e.message ?? 'merge failed',
        incompatible: e.code == 'INCOMPAT',
      );
    }
  }
}

class VideoMergeException implements Exception {
  final String message;
  final bool incompatible;
  VideoMergeException(this.message, {this.incompatible = false});
  @override
  String toString() => message;
}
