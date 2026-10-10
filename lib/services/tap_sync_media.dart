import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../models/subtitle_style_model.dart';
import 'audio_sync_service.dart';
import 'clip_player_controller.dart';

/// Native helpers for Tap Sync (volume keys as a button, Bluetooth check).
class TapSyncNative {
  TapSyncNative._();
  static const _ch = MethodChannel('com.anniekaydee.subtitle_app/tapsync');

  /// Called with `true` on volume-key down and `false` on key up.
  static void Function(bool down)? onVolumeKey;
  static bool _wired = false;

  static void _wire() {
    if (_wired) return;
    _wired = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'volumeKey') {
        final down = (call.arguments as Map)['down'] == true;
        onVolumeKey?.call(down);
      }
    });
  }

  static Future<void> setVolumeKeyCapture(bool enabled) async {
    _wire();
    try {
      await _ch.invokeMethod('setVolumeKeyCapture', {'enabled': enabled});
    } catch (_) {}
  }

  static Future<bool> isBluetoothOutput() async {
    try {
      return await _ch.invokeMethod<bool>('isBluetoothOutput') ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Speech analysis on the subtitle timeline (ms).
class TapSyncAnalysis {
  final List<int> onsets;
  final List<int> speechEnds;

  /// Normalised amplitude every [AudioSyncService.waveformStepMs].
  final List<double> waveform;

  const TapSyncAnalysis(this.onsets, this.speechEnds, this.waveform);
  static const empty = TapSyncAnalysis([], [], []);
}

/// Plays a project's media on the SAME timeline its subtitles use:
///  * single video → the source video's own time;
///  * 2+ clips     → the global multi-clip timeline (sum of trimmed clips).
abstract class TapSyncMedia {
  /// [sharedClipPlayer]: the editor's native multi-clip player. There is only
  /// ONE native instance (create() disposes the previous one), so Tap Sync
  /// must borrow it instead of creating its own.
  static TapSyncMedia forProject(SubtitleProject p,
          {ClipPlayerController? sharedClipPlayer}) =>
      p.clips.length >= 2
          ? _ClipsMedia(p, sharedClipPlayer)
          : _SingleMedia(p);

  int get durationMs;
  bool get isPlaying;
  double get aspectRatio;

  Future<void> init();

  /// Fresh position from the player (not a cached value).
  Future<int> positionMs();

  Future<void> seek(int ms);
  Future<void> play();
  Future<void> pause();
  Future<void> setSpeed(double speed);
  Future<void> setVolume(double v);
  Widget preview();
  Future<void> dispose();

  /// Speech onsets / ends / waveform mapped onto the timeline.
  Future<TapSyncAnalysis> analyze();
}

class _SingleMedia extends TapSyncMedia {
  final SubtitleProject project;
  VideoPlayerController? _vc;
  _SingleMedia(this.project);

  @override
  int get durationMs => _vc?.value.duration.inMilliseconds ?? 0;
  @override
  bool get isPlaying => _vc?.value.isPlaying ?? false;
  @override
  double get aspectRatio {
    final a = _vc?.value.aspectRatio ?? 0;
    return a > 0 ? a : 9 / 16;
  }

  @override
  Future<void> init() async {
    final c = VideoPlayerController.file(
      File(project.videoPath!),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    await c.initialize();
    _vc = c;
  }

  @override
  Future<int> positionMs() async {
    final p = await _vc?.position;
    return p?.inMilliseconds ?? 0;
  }

  @override
  Future<void> seek(int ms) async =>
      _vc?.seekTo(Duration(milliseconds: ms.clamp(0, durationMs)));
  @override
  Future<void> play() async => _vc?.play();
  @override
  Future<void> pause() async => _vc?.pause();
  @override
  Future<void> setSpeed(double speed) async => _vc?.setPlaybackSpeed(speed);
  @override
  Future<void> setVolume(double v) async => _vc?.setVolume(v);

  @override
  Widget preview() {
    final c = _vc;
    if (c == null || !c.value.isInitialized) return const SizedBox.shrink();
    return AspectRatio(aspectRatio: aspectRatio, child: VideoPlayer(c));
  }

  @override
  Future<void> dispose() async {
    await _vc?.dispose();
    _vc = null;
  }

  @override
  Future<TapSyncAnalysis> analyze() async {
    final path = project.videoPath!;
    final r = await Future.wait([
      AudioSyncService.detectSpeechOnsets(path),
      AudioSyncService.detectSpeechRegions(path),
      AudioSyncService.waveform(path),
    ]);
    final regions = r[1] as List<List<int>>;
    return TapSyncAnalysis(
      r[0] as List<int>,
      regions.map((e) => e[1]).toList(),
      r[2] as List<double>,
    );
  }
}

class _ClipsMedia extends TapSyncMedia {
  final SubtitleProject project;
  final ClipPlayerController _cp;
  final bool _borrowed;
  bool _playing = false;
  _ClipsMedia(this.project, ClipPlayerController? shared)
      : _cp = shared ?? ClipPlayerController(),
        _borrowed = shared != null;

  List<({int start, int end, int trimStart, int trimEnd})> get _bounds {
    final out = <({int start, int end, int trimStart, int trimEnd})>[];
    int cursor = 0;
    for (final c in project.clips) {
      final dur = c.effectiveMs > 0 ? c.effectiveMs : 1;
      out.add((
        start: cursor,
        end: cursor + dur,
        trimStart: c.trimStartMs,
        trimEnd: c.trimStartMs + dur,
      ));
      cursor += dur;
    }
    return out;
  }

  @override
  int get durationMs => _bounds.isEmpty ? 0 : _bounds.last.end;
  @override
  bool get isPlaying => _playing;
  @override
  double get aspectRatio =>
      _cp.videoW > 0 && _cp.videoH > 0 ? _cp.videoW / _cp.videoH : 9 / 16;

  @override
  Future<void> init() async {
    if (_borrowed && _cp.textureId != null) {
      await _cp.pause();
      await _cp.refreshSize();
      return;
    }
    await _cp.create();
    await _cp.setClips(
      project.clips.map((c) => c.path).toList(),
      trimStarts: project.clips.map((c) => c.trimStartMs).toList(),
      trimEnds: project.clips.map((c) => c.trimEndMs ?? -1).toList(),
    );
    await _cp.refreshSize();
  }

  @override
  Future<int> positionMs() async {
    final p = await _cp.position();
    final idx = (p['index'] as num?)?.toInt() ?? 0;
    final pos = (p['posMs'] as num?)?.toInt() ?? 0;
    _playing = p['playing'] == true && p['ended'] != true;
    if (_cp.videoW == 0) await _cp.refreshSize();
    final b = _bounds;
    return ((idx < b.length ? b[idx].start : 0) + pos).clamp(0, durationMs);
  }

  @override
  Future<void> seek(int ms) async {
    final b = _bounds;
    if (b.isEmpty) return;
    final g = ms.clamp(0, durationMs);
    var idx = b.indexWhere((x) => g >= x.start && g < x.end);
    if (idx < 0) idx = b.length - 1;
    await _cp.seek(idx, g - b[idx].start);
  }

  @override
  Future<void> play() async {
    _playing = true;
    await _cp.play();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    await _cp.pause();
  }

  @override
  Future<void> setSpeed(double speed) => _cp.setSpeed(speed);
  @override
  Future<void> setVolume(double v) => _cp.setVolume(v);

  @override
  Widget preview() {
    final id = _cp.textureId;
    if (id == null) return const SizedBox.shrink();
    return AspectRatio(aspectRatio: aspectRatio, child: Texture(textureId: id));
  }

  @override
  Future<void> dispose() async {
    if (_borrowed) {
      // Hand the editor's player back as we found it.
      await _cp.pause();
      await _cp.setSpeed(1.0);
      return;
    }
    await _cp.dispose();
  }

  @override
  Future<TapSyncAnalysis> analyze() async {
    final onsets = <int>[];
    final ends = <int>[];
    final wave = <double>[];
    const step = AudioSyncService.waveformStepMs;
    final b = _bounds;
    for (int i = 0; i < project.clips.length; i++) {
      final path = project.clips[i].path;
      final x = b[i];
      int map(int t) => x.start + (t - x.trimStart);
      bool inside(int t) => t >= x.trimStart && t <= x.trimEnd;
      final r = await Future.wait([
        AudioSyncService.detectSpeechOnsets(path),
        AudioSyncService.detectSpeechRegions(path),
        AudioSyncService.waveform(path),
      ]);
      onsets.addAll((r[0] as List<int>).where(inside).map(map));
      ends.addAll((r[1] as List<List<int>>)
          .map((e) => e[1])
          .where(inside)
          .map(map));
      final w = r[2] as List<double>;
      final from = (x.trimStart ~/ step).clamp(0, w.length);
      final want = (x.end - x.start) ~/ step;
      final slice = w.sublist(from, (from + want).clamp(from, w.length));
      wave.addAll(slice);
      // Pad so later clips stay aligned even if the waveform came up short.
      for (int k = slice.length; k < want; k++) {
        wave.add(0);
      }
    }
    return TapSyncAnalysis(onsets..sort(), ends..sort(), wave);
  }
}
