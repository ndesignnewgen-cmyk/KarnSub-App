import '../models/subtitle_style_model.dart';
import '../services/storage_service.dart';
import 'export_plan.dart';
import 'timeline_model.dart';

/// v2 [ProjectTimeline] → v1 [SubtitleProject], so today's preview player and
/// exporter can render what the multi-track editor made.
///
/// Two layouts:
///  * default (preview / classic editor): the main track becomes a v1
///    multi-clip list on the cut timeline (a single clip uses `videoPath` +
///    a removed head instead, since v1 clip mode needs ≥ 2 clips);
///  * [plan] (save / export): ONE file + `removedRanges` on that file's clock
///    (see [ExportPlan]); every other time is mapped onto that clock. This is
///    the only layout the exporter renders correctly.
///
/// [rendered] maps element ids to PNGs drawn in Flutter (text layers, shapes,
/// masked images — see layer_render.dart); those export as image overlays.
/// Transitions are expressed with the exporter's effects (fade / zoom /
/// shake). Whatever still can't be shown is listed in [V1Projection.lossy].
class V1Projection {
  final SubtitleProject project;
  final List<String> lossy;
  const V1Projection(this.project, this.lossy);
}

/// Transition kinds the current exporter can render (via its effects).
const exportableTransitions = {'fade', 'zoom', 'shake'};

V1Projection projectToV1(ProjectTimeline t,
    {ExportPlan? plan, Map<String, String> rendered = const {}}) {
  final lossy = <String>{};
  final s = Map<String, dynamic>.of(t.settings)..remove('v1Dropped');

  // ── Main track ──
  final main = t.mainTrack;
  final mainEls = main?.elements ?? const <TimelineElement>[];
  final clips = <Map<String, dynamic>>[];
  var offset = 0; // single-clip default layout: added to every other time
  var removed = <List<int>>[];
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

  int Function(int) atS;
  int Function(int) atE;
  if (plan != null && clips.isNotEmpty) {
    videoPath = plan.videoPath;
    removed = plan.removed.map((r) => List<int>.of(r)).toList();
    videoDurationMs = plan.originalMs;
    clips.clear();
    atS = plan.toOriginal;
    atE = plan.toOriginalEnd;
  } else {
    if (clips.length == 1) {
      final c = clips.single;
      videoPath = c['path'] as String;
      final tin = c['trimStartMs'] as int;
      if (tin > 0) removed.add([0, tin]);
      videoDurationMs = c['trimEndMs'] as int; // nothing after the out-point
      offset = tin;
      clips.clear();
    } else if (clips.isNotEmpty) {
      videoPath = clips.first['path'] as String;
      videoDurationMs = t.mainTrack!.endMs;
    }
    atS = (ms) => ms + offset;
    atE = atS;
  }

  // ── Everything else ──
  final segments = <Map<String, dynamic>>[];
  final overlays = <Map<String, dynamic>>[];
  final zooms = <Map<String, dynamic>>[];
  final fades = <Map<String, dynamic>>[];
  final shakes = <Map<String, dynamic>>[];
  final sfx = <Map<String, dynamic>>[];

  Map<String, dynamic> overlay(TimelineElement e, String path, ElementTransform tr,
          List<Keyframe> kfs, bool cover, bool isVideo) =>
      {
        'id': e.id,
        'path': path,
        'startMs': atS(e.startMs),
        'endMs': atE(e.endMs),
        'x': tr.x,
        'y': tr.y,
        'scale': tr.scale,
        'rotation': tr.rotation,
        'flipH': tr.flipH,
        'isVideo': isVideo,
        'cover': cover,
        'opacity': tr.opacity,
        'keyframes': [
          for (final k in kfs)
            {
              'timeMs': atS(e.startMs + k.timeMs),
              'x': k.t.x,
              'y': k.t.y,
              'scale': k.t.scale,
              'rotation': k.t.rotation,
              'opacity': k.t.opacity,
              // The exporter knows easings 0–5; a custom bezier is closest
              // to ease-in-out.
              'easing': k.easing == 6 ? 3 : k.easing,
            },
        ],
      };

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
            'start': atS(e.startMs),
            'end': atE(e.endMs),
            if (e.wordStartsMs != null)
              'wordTimings': e.wordStartsMs!.map((w) => atS(e.startMs + w)).toList(),
          });
        case ImageElement():
          if (e.blend != LayerBlend.normal) lossy.add('maskBlend');
          final png = rendered[e.id];
          if (e.mask != null && png == null) lossy.add('maskBlend');
          overlays.add(overlay(e, png ?? e.src, e.transform, e.keyframes, e.cover, false));
        case VideoElement():
          if (e.mask != null || e.blend != LayerBlend.normal) lossy.add('maskBlend');
          overlays.add(overlay(e, e.src, e.transform, e.keyframes, e.cover, true));
        case TextElement():
          final png = rendered[e.id];
          if (png == null) {
            lossy.add('text');
          } else {
            overlays.add(overlay(e, png, e.transform, e.keyframes, false, false));
          }
        case ShapeElement():
          final png = rendered[e.id];
          if (png == null) {
            lossy.add('shape');
          } else {
            overlays.add(overlay(e, png, e.transform, e.keyframes, false, false));
          }
        case EffectElement():
          final base = {'id': e.id, 'startMs': atS(e.startMs), 'endMs': atE(e.endMs)};
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
                    {...(k as Map), 'timeMs': atS(e.startMs + (k['timeMs'] as num).toInt())},
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
            s['aiVoiceOffsetMs'] = atS(e.startMs);
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
            'startMs': atS(e.startMs),
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
      }
    }
  }

  // ── Transitions → the exporter's own effects ──
  for (final x in t.transitions) {
    final at = main?.elements.where((e) => e.id == x.fromId).firstOrNull?.endMs;
    if (at == null) continue;
    final half = x.durationMs ~/ 2;
    if (half <= 0) continue;
    final a = atS((at - half).clamp(0, at)), b = atE(at), c = atS(at), d = atE(at + half);
    switch (x.kind) {
      case 'fade':
        fades.add({'id': '${x.fromId}_tout', 'startMs': a, 'endMs': b, 'toBlack': true});
        fades.add({'id': '${x.fromId}_tin', 'startMs': c, 'endMs': d, 'toBlack': false});
      case 'zoom':
        zooms.add({'id': '${x.fromId}_zout', 'startMs': a, 'endMs': b, 'fromScale': 1.0, 'toScale': 1.35,
            'focusX': 0.5, 'focusY': 0.5, 'keyframes': <Map>[]});
        zooms.add({'id': '${x.fromId}_zin', 'startMs': c, 'endMs': d, 'fromScale': 1.35, 'toScale': 1.0,
            'focusX': 0.5, 'focusY': 0.5, 'keyframes': <Map>[]});
      case 'shake':
        shakes.add({'id': '${x.fromId}_shk', 'startMs': a, 'endMs': d, 'intensity': 0.05});
      default:
        lossy.add('transitions');
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
