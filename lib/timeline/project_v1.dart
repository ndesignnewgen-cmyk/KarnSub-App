import '../models/subtitle_style_model.dart';
import '../services/storage_service.dart';
import 'timeline_model.dart';

/// v2 [ProjectTimeline] → v1 [SubtitleProject], so the multi-track editor can
/// drive today's preview player and exporter until the unified engine
/// (phase 3) replaces them.
///
/// The main track becomes a v1 multi-clip list (times are then already on the
/// cut timeline, so no removedRanges are needed). A main track with a single
/// clip uses `videoPath` + removedRanges instead (v1 needs ≥ 2 clips for clip
/// mode) and every other time is shifted back by the clip's in-point.
///
/// Things v1 can't express are reported in [V1Projection.lossy] (they keep
/// living in the timeline; only the old preview/export won't show them).
class V1Projection {
  final SubtitleProject project;
  final List<String> lossy;
  const V1Projection(this.project, this.lossy);
}

V1Projection projectToV1(ProjectTimeline t) {
  final lossy = <String>{};
  final s = Map<String, dynamic>.of(t.settings)..remove('v1Dropped');

  // ── Main track ──
  final main = t.mainTrack;
  final mainEls = main?.elements ?? const <TimelineElement>[];
  final clips = <Map<String, dynamic>>[];
  var offset = 0; // added to every non-main time (single-clip mode)
  final removed = <List<int>>[];
  String? videoPath;
  int? videoDurationMs;
  for (final e in mainEls) {
    if (e is! VideoElement) {
      lossy.add('photoInMainTrack');
      continue;
    }
    if (!e.speedSpec.isDefault) lossy.add('speed');
    if (e.reversed) lossy.add('reverse');
    if (e.mask != null || e.blend != LayerBlend.normal) lossy.add('maskBlend');
    clips.add({
      'id': e.id,
      'path': e.src,
      'trimStartMs': e.trimInMs,
      'trimEndMs': e.trimOutMs,
    });
  }
  if (clips.length == 1) {
    final c = clips.single;
    videoPath = c['path'] as String;
    final tin = c['trimStartMs'] as int;
    final tout = c['trimEndMs'] as int;
    if (tin > 0) removed.add([0, tin]);
    videoDurationMs = tout; // the tail after the out-point is simply not there
    offset = tin;
    clips.clear();
  } else if (clips.isNotEmpty) {
    videoPath = clips.first['path'] as String;
    videoDurationMs = t.mainTrack!.endMs;
  }
  int at(int ms) => ms + offset;

  if (t.transitions.isNotEmpty) lossy.add('transitions');
  if (t.tracksOf(TrackKind.text).any((x) => x.elements.isNotEmpty)) lossy.add('text');
  if (t.tracksOf(TrackKind.shape).any((x) => x.elements.isNotEmpty)) lossy.add('shape');

  // ── Everything else ──
  final segments = <Map<String, dynamic>>[];
  final overlays = <Map<String, dynamic>>[];
  final zooms = <Map<String, dynamic>>[];
  final fades = <Map<String, dynamic>>[];
  final shakes = <Map<String, dynamic>>[];
  final sfx = <Map<String, dynamic>>[];
  for (final tr in t.tracks) {
    if (tr.kind == TrackKind.mainVideo || tr.hidden) continue;
    for (final e in tr.elements) {
      switch (e) {
        case SubtitleElement():
          segments.add({
            ...e.data,
            'id': e.id,
            'text': e.text,
            // v1 segment keys (see StorageService.segmentToJson).
            'start': at(e.startMs),
            'end': at(e.endMs),
            if (e.wordStartsMs != null)
              'wordTimings': e.wordStartsMs!.map((w) => at(e.startMs + w)).toList(),
          });
        case ImageElement():
          if (e.mask != null || e.blend != LayerBlend.normal) lossy.add('maskBlend');
          overlays.add(_overlay(e.id, e.src, at(e.startMs), at(e.endMs), e.transform,
              e.keyframes, e.cover, false, at(e.startMs)));
        case VideoElement():
          if (e.mask != null || e.blend != LayerBlend.normal) lossy.add('maskBlend');
          overlays.add(_overlay(e.id, e.src, at(e.startMs), at(e.endMs), e.transform,
              e.keyframes, e.cover, true, at(e.startMs)));
        case EffectElement():
          final base = {'id': e.id, 'startMs': at(e.startMs), 'endMs': at(e.endMs)};
          switch (e.effect) {
            case 'zoom':
              zooms.add({
                ...base,
                'fromScale': e.params['fromScale'] ?? 1.0,
                'toScale': e.params['toScale'] ?? 1.3,
                'focusX': e.params['focusX'] ?? 0.5,
                'focusY': e.params['focusY'] ?? 0.5,
                'keyframes': [
                  for (final k in (e.params['keyframes'] as List? ?? const []))
                    {...(k as Map), 'timeMs': at(e.startMs + (k['timeMs'] as num).toInt())},
                ],
              });
            case 'fade':
              fades.add({...base, 'toBlack': e.params['toBlack'] ?? true});
            case 'shake':
              shakes.add({...base, 'intensity': e.params['intensity'] ?? 0.03});
            default:
              lossy.add('effect:${e.effect}');
          }
        case AudioElement():
          if (tr.kind == TrackKind.music) {
            if (s.containsKey('bgMusicPath')) {
              lossy.add('extraMusic');
              continue;
            }
            s['bgMusicPath'] = e.src;
            s['bgMusicDurationMs'] = e.durationMs;
            s['bgMusicVolume'] = tr.volume;
            s['bgMusicMuted'] = tr.muted;
            s['bgMusicDuck'] = tr.duck;
            continue;
          }
          if (tr.kind == TrackKind.voice && e.id == 'aivoice') {
            s['aiVoicePath'] = e.src;
            s['aiVoiceOffsetMs'] = at(e.startMs);
            s['aiVoiceTrimStartMs'] = e.trimInMs;
            s['aiVoiceTrimEndMs'] = e.trimInMs + (e.durationMs * e.speed).round();
            s['aiVoiceDurationMs'] = s['aiVoiceTrimEndMs'];
            s['aiVoiceSpeed'] = e.speed;
            s['aiVoiceVolume'] = tr.volume;
            s['aiVoiceMuted'] = tr.muted;
            continue;
          }
          final builtIn = e.src.startsWith('sfx:') ? e.src.substring(4) : null;
          final type = SfxType.values.asNameMap()[builtIn] ?? SfxType.pop;
          sfx.add({
            'id': e.id,
            'type': type.index,
            'startMs': at(e.startMs),
            'durationMs': e.durationMs,
            if (e.trimInMs != 0) 'trimStartMs': e.trimInMs,
            'volume': e.volume,
            'isCustom': builtIn == null,
            if (builtIn == null) 'customPath': e.src,
            if (e.label != null) 'customName': e.label,
            'isAiVoice': tr.kind == TrackKind.voice,
          });
          if (tr.kind == TrackKind.sfx) {
            s['sfxVolume'] = tr.volume;
            s['sfxMuted'] = tr.muted;
          }
        case TextElement() || ShapeElement():
          break; // reported above
      }
    }
  }

  final (w, h) = (t.canvas.width, t.canvas.height);
  final aspect = switch ((w, h)) {
    (1080, 1080) => AspectRatioMode.ratio1x1,
    (1920, 1080) => AspectRatioMode.ratio16x9,
    (1080, 1350) => AspectRatioMode.ratio4x5,
    _ => AspectRatioMode.ratio9x16,
  };

  final json = <String, dynamic>{
    'id': 'project',
    'name': 'project',
    'styleType': 0,
    ...s,
    'videoPath': videoPath,
    'videoDurationMs': ?videoDurationMs,
    'aspectRatio': aspect.index,
    'bgBlur': t.canvas.background == 'blur',
    'originalVolume': main?.volume ?? 1.0,
    'originalMuted': main?.muted ?? false,
    'removedRanges': removed,
    'splitPointsMs': <int>[],
    'clips': clips,
    'segments': segments..sort((a, b) => (a['start'] as int).compareTo(b['start'] as int)),
    'imageOverlays': overlays,
    'zoomEffects': zooms,
    'fadeEffects': fades,
    'shakeEffects': shakes,
    'sfxBlocks': sfx,
  };
  return V1Projection(StorageService.projectFromJson(json), lossy.toList()..sort());
}

Map<String, dynamic> _overlay(String id, String src, int a, int b, ElementTransform t,
        List<Keyframe> kfs, bool cover, bool isVideo, int startAbs) =>
    {
      'id': id,
      'path': src,
      'startMs': a,
      'endMs': b,
      'x': t.x,
      'y': t.y,
      'scale': t.scale,
      'rotation': t.rotation,
      'flipH': t.flipH,
      'isVideo': isVideo,
      'cover': cover,
      'opacity': t.opacity,
      'keyframes': [
        for (final k in kfs)
          {
            'timeMs': startAbs + k.timeMs,
            'x': k.t.x,
            'y': k.t.y,
            'scale': k.t.scale,
            'rotation': k.t.rotation,
            'opacity': k.t.opacity,
            'easing': k.easing,
          },
      ],
    };
