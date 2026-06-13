import 'package:flutter/services.dart';

/// Dart wrapper around the native ExoPlayer-backed gapless multi-clip player
/// (see ClipPlayer.kt). Renders into a Flutter [Texture] (use [textureId]).
class ClipPlayerController {
  static const _ch = MethodChannel('com.anniekaydee.subtitle_app/clipplayer');
  int? textureId;
  int videoW = 0;
  int videoH = 0;

  Future<int?> create() async {
    textureId = await _ch.invokeMethod<int>('create');
    return textureId;
  }

  Future<void> setClips(
    List<String> paths, {
    List<int>? trimStarts,
    List<int>? trimEnds,
  }) =>
      _ch.invokeMethod('setClips', {
        'paths': paths,
        if (trimStarts != null) 'trimStarts': trimStarts,
        if (trimEnds != null) 'trimEnds': trimEnds,
      });

  Future<void> play() => _ch.invokeMethod('play');
  Future<void> pause() => _ch.invokeMethod('pause');
  Future<void> seek(int index, int ms) =>
      _ch.invokeMethod('seek', {'index': index, 'ms': ms});
  Future<void> setVolume(double v) => _ch.invokeMethod('setVolume', {'v': v});

  /// {index, posMs, playing, ended}
  Future<Map<String, dynamic>> position() async {
    final r = await _ch.invokeMethod('position');
    return Map<String, dynamic>.from(r as Map);
  }

  Future<void> refreshSize() async {
    try {
      final r = await _ch.invokeMethod('size') as Map;
      videoW = (r['w'] as num?)?.toInt() ?? 0;
      videoH = (r['h'] as num?)?.toInt() ?? 0;
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      await _ch.invokeMethod('dispose');
    } catch (_) {}
    textureId = null;
  }
}
