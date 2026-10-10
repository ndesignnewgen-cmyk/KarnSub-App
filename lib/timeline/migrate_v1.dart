import 'dart:math' as math;

import '../models/subtitle_style_model.dart';
import '../services/storage_service.dart';
import 'time_map.dart';
import 'timeline_model.dart';

/// Result of converting a v1 project.
class MigrationResult {
  final ProjectTimeline timeline;

  /// Items that were entirely inside a cut (invisible in v1 exports too).
  /// They are also kept in `timeline.settings['v1Dropped']` so nothing is
  /// silently lost.
  final int droppedCount;
  const MigrationResult(this.timeline, this.droppedCount);
}

/// v1 [SubtitleProject] → v2 [ProjectTimeline] (PRO_EDITOR_PLAN phase 1).
///
/// Pure function: reads [p], never mutates it. Mapping:
///   video / clips + removedRanges + splitPoints → mainVideo track
///   segments            → subtitle track(s)
///   imageOverlays       → video (B-roll) / sticker tracks (lanes)
///   zoom / fade / shake → effect track(s)
///   sfxBlocks           → sfx (and voice) tracks (lanes)
///   aiVoicePath         → voice track      bgMusicPath → music track
/// Every time moves from the original timeline onto the cut timeline.
/// [newId] makes ids for split pieces (tests pass a counter).
MigrationResult migrateV1(SubtitleProject p, {String Function()? newId}) {
  var n = 0;
  final id = newId ?? () => 'm${DateTime.now().microsecondsSinceEpoch}_${n++}';
  final dropped = <Map<String, dynamic>>[];

  // ── 1. Original timeline: what plays, from which source ──────────────────
  final pieces = <({int a, int b, String src, int trimIn})>[];
  if (p.clips.length >= 2) {
    var cursor = 0;
    for (final c in p.clips) {
      final dur = c.effectiveMs > 0 ? c.effectiveMs : 1; // same as the editor
      pieces.add((a: cursor, b: cursor + dur, src: c.path, trimIn: c.trimStartMs));
      cursor += dur;
    }
  } else {
    final src = p.videoPath ?? (p.clips.isNotEmpty ? p.clips.first.path : null);
    final total = p.videoDuration?.inMilliseconds ?? _inferDuration(p);
    if (src != null && total > 0) {
      final trim = p.clips.length == 1 && p.videoPath == null ? p.clips.first.trimStartMs : 0;
      pieces.add((a: 0, b: total, src: src, trimIn: trim));
    }
  }
  final originalMs = pieces.isEmpty ? _inferDuration(p) : pieces.last.b;
  final tm = TimeMap.fromRemoved(p.removedRanges, originalMs);

  // ── 2. Main track: kept parts, split at split points ─────────────────────
  final splits = p.splitPointsMs.toSet().toList()..sort();
  final main = <TimelineElement>[];
  for (final pc in pieces) {
    for (final k in tm.kept) {
      final a = math.max(pc.a, k.$1), b = math.min(pc.b, k.$2);
      if (b <= a) continue;
      final cuts = [a, ...splits.where((s) => s > a + 50 && s < b - 50), b];
      for (int i = 0; i + 1 < cuts.length; i++) {
        final s = cuts[i], e = cuts[i + 1];
        main.add(VideoElement(
          id: id(),
          startMs: tm.mapClamp(s),
          durationMs: e - s,
          src: pc.src,
          trimInMs: pc.trimIn + (s - pc.a),
        ));
      }
    }
  }
  final tracks = <Track>[];
  if (main.isNotEmpty) {
    tracks.add(Track(
      id: 'main',
      kind: TrackKind.mainVideo,
      volume: p.originalVolume,
      muted: p.originalMuted,
      elements: main,
    ));
  }

  // ── 3. Effects (zoom / fade / shake) ─────────────────────────────────────
  final effects = <TimelineElement>[];
  for (final z in p.zoomEffects) {
    final r = tm.mapRange(z.startTime.inMilliseconds, z.endTime.inMilliseconds);
    if (r == null) {
      dropped.add({'kind': 'zoom', 'id': z.id});
      continue;
    }
    effects.add(EffectElement(
      id: z.id,
      startMs: r.$1,
      durationMs: r.$2 - r.$1,
      effect: 'zoom',
      params: {
        'fromScale': z.fromScale,
        'toScale': z.toScale,
        'focusX': z.focusX,
        'focusY': z.focusY,
        if (z.keyframes.isNotEmpty)
          'keyframes': [
            for (final k in z.keyframes)
              {
                'timeMs': tm.mapClamp(k.timeMs) - r.$1,
                'scale': k.scale,
                'focusX': k.focusX,
                'focusY': k.focusY,
                if (k.easing != 0) 'easing': k.easing,
              },
          ],
      },
    ));
  }
  for (final f in p.fadeEffects) {
    final r = tm.mapRange(f.startTime.inMilliseconds, f.endTime.inMilliseconds);
    if (r == null) {
      dropped.add({'kind': 'fade', 'id': f.id});
      continue;
    }
    effects.add(EffectElement(
        id: f.id, startMs: r.$1, durationMs: r.$2 - r.$1, effect: 'fade',
        params: {'toBlack': f.toBlack}));
  }
  for (final s in p.shakeEffects) {
    final r = tm.mapRange(s.startTime.inMilliseconds, s.endTime.inMilliseconds);
    if (r == null) {
      dropped.add({'kind': 'shake', 'id': s.id});
      continue;
    }
    effects.add(EffectElement(
        id: s.id, startMs: r.$1, durationMs: r.$2 - r.$1, effect: 'shake',
        params: {'intensity': s.intensity}));
  }
  tracks.addAll(_lanes(effects, TrackKind.effect, 'effect'));

  // ── 4. Overlays (B-roll video / images / stickers) ───────────────────────
  final brolls = <TimelineElement>[];
  final stickers = <TimelineElement>[];
  for (final o in p.imageOverlays) {
    final r = tm.mapRange(o.startTime.inMilliseconds, o.endTime.inMilliseconds);
    if (r == null) {
      dropped.add({'kind': 'overlay', 'id': o.id, 'path': o.path});
      continue;
    }
    final t = ElementTransform(
      x: o.x,
      y: o.y,
      scale: o.scale,
      rotation: o.rotation,
      opacity: o.opacity,
      flipH: o.flipH,
    );
    final kfs = [
      for (final k in o.keyframes)
        Keyframe(
          tm.mapClamp(k.timeMs) - r.$1,
          ElementTransform(
              x: k.x, y: k.y, scale: k.scale, rotation: k.rotation,
              opacity: k.opacity, flipH: o.flipH),
          easing: k.easing,
        ),
    ];
    if (o.isVideo) {
      brolls.add(VideoElement(
        id: o.id,
        startMs: r.$1,
        durationMs: r.$2 - r.$1,
        src: o.path,
        muted: true, // v1 B-roll never played its own audio
        transform: t,
        keyframes: kfs,
        cover: o.cover,
      ));
    } else {
      stickers.add(ImageElement(
        id: o.id,
        startMs: r.$1,
        durationMs: r.$2 - r.$1,
        src: o.path,
        animated: o.path.toLowerCase().endsWith('.gif'),
        transform: t,
        keyframes: kfs,
        cover: o.cover,
      ));
    }
  }
  tracks.addAll(_lanes(brolls, TrackKind.video, 'broll'));
  tracks.addAll(_lanes(stickers, TrackKind.sticker, 'sticker'));

  // ── 5. Subtitles ─────────────────────────────────────────────────────────
  final subs = <TimelineElement>[];
  for (final s in p.segments) {
    final r = tm.mapRange(s.startTime.inMilliseconds, s.endTime.inMilliseconds);
    final data = StorageService.segmentToJson(s);
    if (r == null) {
      dropped.add({'kind': 'subtitle', 'segment': data});
      continue;
    }
    subs.add(SubtitleElement(
      id: s.id,
      startMs: r.$1,
      durationMs: r.$2 - r.$1,
      text: s.text,
      wordStartsMs: s.wordTimings
          ?.map((w) => (tm.mapClamp(w.inMilliseconds) - r.$1).clamp(0, r.$2 - r.$1))
          .toList(),
      data: data,
    ));
  }
  tracks.addAll(_lanes(subs, TrackKind.subtitle, 'sub'));

  // ── 6. Audio: SFX, AI voice, music ───────────────────────────────────────
  final sfx = <TimelineElement>[];
  final voiceClips = <TimelineElement>[];
  for (final b in p.sfxBlocks) {
    final len = (b.duration ?? b.type.defaultDuration).inMilliseconds;
    final start = b.startTime.inMilliseconds;
    final r = tm.mapRange(start, start + len);
    if (r == null) {
      dropped.add({'kind': 'sfx', 'id': b.id});
      continue;
    }
    final el = AudioElement(
      id: b.id,
      startMs: r.$1,
      durationMs: r.$2 - r.$1,
      src: b.isCustom && b.customPath != null ? b.customPath! : 'sfx:${b.type.name}',
      trimInMs: b.trimStart?.inMilliseconds ?? 0,
      volume: b.volume,
      label: b.customName,
    );
    (b.isAiVoice ? voiceClips : sfx).add(el);
  }
  tracks.addAll(_lanes(sfx, TrackKind.sfx, 'sfx',
      volume: p.sfxVolume, muted: p.sfxMuted));

  if (p.aiVoicePath != null) {
    final srcLen = (p.aiVoiceTrimEndMs ?? p.aiVoiceDurationMs ?? 0) - p.aiVoiceTrimStartMs;
    if (srcLen > 0) {
      final speed = p.aiVoiceSpeed > 0 ? p.aiVoiceSpeed : 1.0;
      final start = p.aiVoiceOffsetMs;
      final r = tm.mapRange(start, start + (srcLen / speed).round());
      if (r != null) {
        voiceClips.add(AudioElement(
          id: 'aivoice',
          startMs: r.$1,
          durationMs: r.$2 - r.$1,
          src: p.aiVoicePath!,
          trimInMs: p.aiVoiceTrimStartMs,
          speed: speed,
          label: 'AI voice',
        ));
      }
    }
  }
  tracks.addAll(_lanes(voiceClips, TrackKind.voice, 'voice',
      volume: p.aiVoiceVolume, muted: p.aiVoiceMuted));

  final contentMs = math.max(
      tm.durationMs, tracks.isEmpty ? 0 : tracks.map((t) => t.endMs).reduce(math.max));
  if (p.bgMusicPath != null && contentMs > 0) {
    tracks.add(Track(
      id: 'music',
      kind: TrackKind.music,
      volume: p.bgMusicVolume,
      muted: p.bgMusicMuted,
      duck: p.bgMusicDuck,
      elements: [
        AudioElement(
          id: 'bgmusic',
          startMs: 0,
          durationMs: contentMs,
          src: p.bgMusicPath!,
          loop: true,
          label: 'music',
        ),
      ],
    ));
  }

  // ── 7. Canvas + settings ─────────────────────────────────────────────────
  final (w, h) = switch (p.aspectRatio) {
    AspectRatioMode.ratio9x16 => (1080, 1920),
    AspectRatioMode.ratio1x1 => (1080, 1080),
    AspectRatioMode.ratio16x9 => (1920, 1080),
    AspectRatioMode.ratio4x5 => (1080, 1350),
  };
  final settings = Map<String, dynamic>.of(StorageService.projectToJson(p))
    ..removeWhere((k, _) => _structuralKeys.contains(k) || _keyPrefixes.any(k.startsWith));
  if (dropped.isNotEmpty) settings['v1Dropped'] = dropped;

  return MigrationResult(
    ProjectTimeline(
      tracks: tracks,
      canvas: CanvasSpec(width: w, height: h, background: p.bgBlur ? 'blur' : 'black'),
      settings: settings,
    ),
    dropped.length,
  );
}

/// Keys represented by tracks/elements/canvas (not copied into settings).
const _structuralKeys = {
  'segments', 'sfxBlocks', 'clips', 'imageOverlays', 'zoomEffects',
  'fadeEffects', 'shakeEffects', 'removedRanges', 'splitPointsMs',
  'videoPath', 'originalVolume', 'originalMuted', 'sfxVolume', 'sfxMuted',
  'bgBlur', 'aspectRatio', 'timelineV2', 'timelineV2Base',
};
const _keyPrefixes = ['aiVoice', 'bgMusic'];

/// Put elements on as few tracks of [kind] as possible without overlaps
/// (first track where it fits, like v1's lane layout).
List<Track> _lanes(List<TimelineElement> els, TrackKind kind, String prefix,
    {double volume = 1, bool muted = false}) {
  if (els.isEmpty) return const [];
  final sorted = [...els]..sort((a, b) => a.startMs.compareTo(b.startMs));
  final lanes = <List<TimelineElement>>[];
  for (final e in sorted) {
    var placed = false;
    for (final lane in lanes) {
      if (lane.last.endMs <= e.startMs) {
        lane.add(e);
        placed = true;
        break;
      }
    }
    if (!placed) lanes.add([e]);
  }
  return [
    for (int i = 0; i < lanes.length; i++)
      Track(
        id: i == 0 ? prefix : '$prefix${i + 1}',
        kind: kind,
        volume: volume,
        muted: muted,
        elements: lanes[i],
      ),
  ];
}

/// Fallback when the video duration wasn't saved: the end of the last thing.
int _inferDuration(SubtitleProject p) {
  var m = 0;
  for (final s in p.segments) {
    m = math.max(m, s.endTime.inMilliseconds);
  }
  for (final o in p.imageOverlays) {
    m = math.max(m, o.endTime.inMilliseconds);
  }
  for (final r in p.removedRanges) {
    if (r.length == 2) m = math.max(m, r[1]);
  }
  return m;
}
