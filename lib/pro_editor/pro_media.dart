import 'package:flutter/widgets.dart';

import '../models/subtitle_style_model.dart';
import '../services/tap_sync_media.dart';
import '../timeline/timeline_model.dart';

/// Plays the Pro Editor's main track with today's players (through the v1
/// projection) and speaks TIMELINE milliseconds.
///
/// A multi-clip main track plays on the native gapless player, already on
/// the cut timeline. A single clip plays its source file, so timeline time =
/// source time − the clip's in-point.
class ProMedia {
  final TapSyncMedia Function(SubtitleProject projected) factory;
  ProMedia({TapSyncMedia Function(SubtitleProject)? factory})
      : factory = factory ?? ((p) => TapSyncMedia.forProject(p));

  TapSyncMedia? _m;
  String _signature = '';
  int _offset = 0;
  int _endMs = 0;
  bool _busy = false;

  bool get ready => _m != null;
  bool get isPlaying => _m?.isPlaying ?? false;

  static String signatureOf(ProjectTimeline t) {
    final main = t.mainTrack;
    if (main == null) return '';
    return main.elements
        .whereType<VideoElement>()
        .map((e) => '${e.src}|${e.trimInMs}|${e.durationMs}|${e.speed}')
        .join(';');
  }

  /// (Re)load when the main track's clips changed. Returns true if reloaded.
  Future<bool> sync(ProjectTimeline t, SubtitleProject projected) async {
    final sig = signatureOf(t);
    _endMs = t.mainTrack?.endMs ?? 0;
    if (sig == _signature || _busy) return false;
    _busy = true;
    try {
      final old = _m;
      _m = null;
      await old?.dispose();
      _signature = sig;
      if (sig.isEmpty) return true;
      final hasMedia = projected.clips.length >= 2 || projected.videoPath != null;
      if (!hasMedia) return true;
      final single = t.mainTrack!.elements.whereType<VideoElement>().toList();
      _offset = projected.clips.length >= 2 || single.isEmpty ? 0 : single.first.trimInMs;
      final m = factory(projected);
      await m.init();
      _m = m;
      return true;
    } catch (_) {
      _m = null;
      return true;
    } finally {
      _busy = false;
    }
  }

  Future<int> positionMs() async {
    final m = _m;
    if (m == null) return 0;
    return ((await m.positionMs()) - _offset).clamp(0, _endMs);
  }

  Future<void> seek(int ms) async => _m?.seek(ms.clamp(0, _endMs) + _offset);
  Future<void> play() async => _m?.play();
  Future<void> pause() async => _m?.pause();
  Future<void> setVolume(double v) async => _m?.setVolume(v);
  Widget preview() => _m?.preview() ?? const SizedBox.shrink();
  double get aspectRatio => _m?.aspectRatio ?? 9 / 16;

  Future<void> dispose() async {
    final m = _m;
    _m = null;
    await m?.dispose();
  }
}
