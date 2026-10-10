import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/subtitle_style_model.dart';
import '../services/storage_service.dart';
import '../timeline/layer_render.dart';
import '../timeline/timeline_model.dart';
import '../timeline/timeline_ops.dart';
import '../timeline/v2_store.dart';

/// State + editing logic of the Pro Editor (multi-track timeline, phase 2).
/// No widgets here — the screen listens to it, tests drive it directly.
class ProEditorController extends ChangeNotifier {
  final SubtitleProject base;
  final TimelineHistory history;
  final String Function() _newId;

  /// Playhead in timeline ms. A separate notifier so playback/scrubbing
  /// repaints only the timeline + preview, not the whole screen.
  final ValueNotifier<int> playhead = ValueNotifier<int>(0);

  /// Timeline zoom (pixels per second).
  double pxPerSec = 80;
  static const double minPxPerSec = 10;
  static const double maxPxPerSec = 600;

  final Set<String> _selected = {};
  bool ripple = false;
  bool snapping = true;
  List<TimelineElement> _clipboard = const [];

  /// Last refused edit (e.g. 'overlap', 'locked', 'tooShort'); the UI shows it.
  String? lastError;

  /// What the classic preview/export can't show (from the last save).
  List<String> lossy = const [];

  /// Project cover chosen in the editor ("ໜ້າປົກ"); null = keep the current one.
  String? coverPath;

  ProEditorController(this.base, {String Function()? newId})
      : _newId = newId ?? _defaultId,
        history = TimelineHistory(timelineFor(base, newId: newId));

  static int _n = 0;
  static String _defaultId() => 'e${DateTime.now().microsecondsSinceEpoch}_${_n++}';

  ProjectTimeline get timeline => history.current;
  int get durationMs => timeline.durationMs;
  Set<String> get selected => Set.unmodifiable(_selected);
  String? get primary => _selected.isEmpty ? null : _selected.last;
  TimelineElement? get primaryElement => primary == null ? null : timeline.find(primary!)?.$2;
  Track? get primaryTrack => primary == null ? null : timeline.find(primary!)?.$1;
  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;
  bool get hasClipboard => _clipboard.isNotEmpty;

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Run an edit; on refusal remember why and change nothing.
  bool _edit(String label, ProjectTimeline Function(ProjectTimeline) f) {
    try {
      // Drags (trim/move) are absolute, so each step restarts from where the
      // drag began — then content cut away mid-drag comes back on drag-back.
      final base = history.batchStart ?? history.current;
      var next = f(base);
      if (!identical(next, base) && _mainChanged(base, next)) {
        next = TimelineOps.relink(base, next); // subtitles/SFX/effects follow
      }
      history.run(label, (_) => next);
      lastError = null;
      _dropMissingSelection();
      notifyListeners();
      return true;
    } on TimelineEditError catch (e) {
      lastError = e.code;
      notifyListeners();
      return false;
    }
  }

  static bool _mainChanged(ProjectTimeline a, ProjectTimeline b) {
    final x = a.mainTrack?.elements ?? const <TimelineElement>[];
    final y = b.mainTrack?.elements ?? const <TimelineElement>[];
    if (identical(x, y)) return false;
    if (x.length != y.length) return true;
    for (var i = 0; i < x.length; i++) {
      final p = x[i], q = y[i];
      if (p.id != q.id || p.startMs != q.startMs || p.durationMs != q.durationMs) return true;
      if (p is VideoElement && q is VideoElement && (p.trimInMs != q.trimInMs || p.src != q.src)) {
        return true;
      }
    }
    return false;
  }

  void _dropMissingSelection() {
    _selected.removeWhere((id) => timeline.find(id) == null);
  }

  void seek(int ms) {
    playhead.value = ms.clamp(0, math.max(0, durationMs));
  }

  void zoom(double factor) {
    pxPerSec = (pxPerSec * factor).clamp(minPxPerSec, maxPxPerSec);
    notifyListeners();
  }

  int msToPx(int ms) => (ms * pxPerSec / 1000).round();
  int pxToMs(double px) => (px * 1000 / pxPerSec).round();

  /// Snap tolerance: ~10 px at the current zoom.
  int get _snapTol => pxToMs(10);

  int _snap(int ms, {String? exclude}) {
    if (!snapping) return ms;
    final pts = TimelineOps.snapPoints(timeline, excludeId: exclude, extra: [playhead.value]);
    return TimelineOps.snap(ms, pts, _snapTol);
  }

  // ── Selection ────────────────────────────────────────────────────────────

  void select(String id, {bool additive = false}) {
    if (!additive) _selected.clear();
    if (additive && _selected.contains(id)) {
      _selected.remove(id);
    } else {
      _selected.add(id);
    }
    notifyListeners();
  }

  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  // ── Edits ────────────────────────────────────────────────────────────────

  /// Split the selected elements (or the main clip under the playhead when
  /// nothing is selected) at the playhead.
  bool splitAtPlayhead() {
    final at = playhead.value;
    var targets = _selected.toList();
    if (targets.isEmpty) {
      final main = timeline.mainTrack;
      final hit = main?.elements.where((e) => at > e.startMs && at < e.endMs);
      if (hit == null || hit.isEmpty) {
        lastError = 'nothingHere';
        notifyListeners();
        return false;
      }
      targets = [hit.first.id];
    }
    final newIds = <String>[];
    final ok = _edit('split', (t) {
      var x = t;
      for (final id in targets) {
        final e = x.find(id)?.$2;
        if (e == null || at <= e.startMs || at >= e.endMs) continue;
        final nid = _newId();
        x = TimelineOps.splitElement(x, id, at, nid);
        newIds.add(nid);
      }
      if (newIds.isEmpty) throw TimelineEditError('nothingHere', 'playhead not inside');
      return x;
    });
    if (ok) {
      _selected
        ..clear()
        ..addAll(newIds);
      notifyListeners();
    }
    return ok;
  }

  bool deleteSelected() {
    if (_selected.isEmpty) return false;
    final ids = _selected.toList();
    final ok = _edit('delete', (t) {
      var x = t;
      for (final id in ids) {
        x = TimelineOps.removeElement(x, id, ripple: ripple);
      }
      return x;
    });
    if (ok) _selected.clear();
    notifyListeners();
    return ok;
  }

  bool duplicateSelected() {
    if (_selected.isEmpty) return false;
    final ids = _selected.toList();
    final newIds = <String>[];
    final ok = _edit('duplicate', (t) {
      var x = t;
      for (final id in ids) {
        final nid = _newId();
        (x, _) = TimelineOps.duplicateElement(x, id, nid);
        newIds.add(nid);
      }
      return x;
    });
    if (ok) {
      _selected
        ..clear()
        ..addAll(newIds);
      notifyListeners();
    }
    return ok;
  }

  void copySelected() {
    _clipboard = [
      for (final id in _selected)
        if (timeline.find(id) != null) timeline.find(id)!.$2,
    ];
    notifyListeners();
  }

  /// Paste the clipboard at the playhead (keeping the gaps between copied
  /// elements), each on a free track of its kind (a new one if needed).
  bool paste() {
    if (_clipboard.isEmpty) return false;
    final first = _clipboard.map((e) => e.startMs).reduce(math.min);
    final at = playhead.value;
    final newIds = <String>[];
    final ok = _edit('paste', (t) {
      var x = t;
      for (final e in _clipboard) {
        final src = x.find(e.id)?.$1 ?? _trackForType(x, e);
        final copy = e.withId(_newId()).withTiming(startMs: at + (e.startMs - first));
        x = _placeOnFreeTrack(x, src?.kind ?? _kindFor(e), copy, preferred: src?.id);
        newIds.add(copy.id);
      }
      return x;
    });
    if (ok) {
      _selected
        ..clear()
        ..addAll(newIds);
      notifyListeners();
    }
    return ok;
  }

  static TrackKind _kindFor(TimelineElement e) => switch (e) {
        VideoElement() => TrackKind.video,
        ImageElement() => TrackKind.sticker,
        TextElement() => TrackKind.text,
        SubtitleElement() => TrackKind.subtitle,
        ShapeElement() => TrackKind.shape,
        AudioElement() => TrackKind.sfx,
        EffectElement() => TrackKind.effect,
      };

  Track? _trackForType(ProjectTimeline t, TimelineElement e) {
    final k = _kindFor(e);
    final l = t.tracksOf(k);
    return l.isEmpty ? null : l.first;
  }

  ProjectTimeline _placeOnFreeTrack(ProjectTimeline t, TrackKind kind, TimelineElement e,
      {String? preferred}) {
    final order = [
      if (preferred != null && t.track(preferred) != null) t.track(preferred)!,
      ...t.tracksOf(kind).where((x) => x.id != preferred),
    ];
    for (final tr in order) {
      if (tr.locked) continue;
      if (tr.kind == TrackKind.mainVideo || tr.fits(e.startMs, e.endMs)) {
        return TimelineOps.addElement(t, tr.id, e);
      }
    }
    final id = '${kind.name}_${_newId()}';
    return TimelineOps.addElement(
        TimelineOps.addTrack(t, Track(id: id, kind: kind)), id, e);
  }

  // Drags (trim/move) are many small edits → one undo step.
  void beginDrag(String label) => history.beginBatch(label);
  void endDrag() {
    history.endBatch();
    notifyListeners();
  }

  void cancelDrag() {
    history.cancelBatch();
    notifyListeners();
  }

  /// Trim one edge of [id] to [ms] (snapped).
  bool trimTo(String id, {required bool leftEdge, required int ms}) {
    final e = timeline.find(id)?.$2;
    if (e == null) return false;
    final s = _snap(ms, exclude: id);
    return _edit('trim', (t) => leftEdge
        ? TimelineOps.trimElement(t, id, newStartMs: s)
        : TimelineOps.trimElement(t, id, newEndMs: s));
  }

  /// Move [id] to [trackId] at [startMs]; the start (or end) snaps.
  bool moveTo(String id, String trackId, int startMs) {
    final e = timeline.find(id)?.$2;
    if (e == null) return false;
    var s = _snap(startMs, exclude: id);
    if (s == startMs) {
      final endSnapped = _snap(startMs + e.durationMs, exclude: id);
      s = endSnapped - e.durationMs;
    }
    return _edit('move', (t) => TimelineOps.moveElement(t, id, trackId, math.max(0, s)));
  }

  bool setTrack(String trackId, {bool? muted, bool? locked, bool? hidden, double? volume}) =>
      _edit('track', (t) => TimelineOps.updateTrack(t, trackId,
          muted: muted, locked: locked, hidden: hidden, volume: volume));

  /// Set clip/sound volume (0–2).
  bool setVolume(String id, double v) {
    final e = timeline.find(id)?.$2;
    final vv = v.clamp(0.0, 2.0);
    return switch (e) {
      VideoElement() => _edit('volume', (t) => TimelineOps.updateElement(t, e.copyWith(volume: vv))),
      AudioElement() => _edit('volume', (t) => TimelineOps.updateElement(t, e.copyWith(volume: vv))),
      _ => false,
    };
  }

  /// Add/remove a bookmark at the playhead.
  void toggleBookmark() {
    final at = playhead.value;
    final near = timeline.bookmarksMs.where((b) => (b - at).abs() <= _snapTol).toList();
    _edit('bookmark', (t) => t.copyWith(
        bookmarksMs: near.isNotEmpty
            ? t.bookmarksMs.where((b) => !near.contains(b)).toList()
            : ([...t.bookmarksMs, at]..sort())));
  }

  /// Append a clip at the end of the main track (creates it if missing).
  bool addMainClip(String path, int durationMs) {
    if (durationMs < kMinElementMs) {
      lastError = 'tooShort';
      notifyListeners();
      return false;
    }
    return _edit('addClip', (t) {
      var x = t;
      if (x.mainTrack == null) {
        x = TimelineOps.addTrack(x, const Track(id: 'main', kind: TrackKind.mainVideo));
      }
      final end = x.mainTrack!.endMs;
      return TimelineOps.addElement(x, x.mainTrack!.id,
          VideoElement(
              id: _newId(), startMs: end, durationMs: durationMs, src: path, sourceMs: durationMs));
    });
  }

  /// Picture-in-picture video or a photo/sticker at the playhead.
  bool addOverlay(String path, int durationMs, {required bool isVideo}) {
    final id = _newId();
    final el = isVideo
        ? VideoElement(
            id: id,
            startMs: playhead.value,
            durationMs: durationMs,
            src: path,
            transform: const ElementTransform(scale: 0.5),
          )
        : ImageElement(id: id, startMs: playhead.value, durationMs: durationMs, src: path,
            animated: path.toLowerCase().endsWith('.gif')) as TimelineElement;
    final ok = _edit('addOverlay', (t) =>
        _placeOnFreeTrack(t, isVideo ? TrackKind.video : TrackKind.sticker, el));
    if (ok) {
      _selected
        ..clear()
        ..add(id);
      notifyListeners();
    }
    return ok;
  }

  /// Music / a sound file at the playhead on a free music track.
  bool addAudio(String path, int durationMs, {String? label}) {
    final id = _newId();
    final el = AudioElement(
        id: id, startMs: playhead.value, durationMs: durationMs, src: path, label: label);
    final ok = _edit('addAudio', (t) => _placeOnFreeTrack(t, TrackKind.music, el));
    if (ok) {
      _selected
        ..clear()
        ..add(id);
      notifyListeners();
    }
    return ok;
  }

  /// Put AI subtitles (already on the TIMELINE clock) on the subtitle track,
  /// replacing the existing ones — one undo step.
  bool replaceSubtitles(List<SubtitleSegment> segs) {
    return _edit('aiSubtitles', (t) {
      var x = t;
      for (final tr in x.tracksOf(TrackKind.subtitle)) {
        x = TimelineOps.removeTrack(x, tr.id);
      }
      final els = <TimelineElement>[];
      for (final s in [...segs]..sort((a, b) => a.startTime.compareTo(b.startTime))) {
        final a = s.startTime.inMilliseconds;
        var b = s.endTime.inMilliseconds;
        if (els.isNotEmpty && a < els.last.endMs) continue; // keep one lane
        if (b - a < kMinElementMs) b = a + kMinElementMs;
        els.add(SubtitleElement(
          id: s.id,
          startMs: a,
          durationMs: b - a,
          text: s.text,
          wordStartsMs: s.wordTimings
              ?.map((w) => (w.inMilliseconds - a).clamp(0, b - a))
              .toList(),
          data: StorageService.segmentToJson(s),
        ));
      }
      return x.copyWith(tracks: [
        ...x.tracks,
        Track(id: 'sub', kind: TrackKind.subtitle, elements: els),
      ]);
    });
  }

  /// Change project-level settings (language, translate mode, font…).
  void updateSettings(Map<String, dynamic> changes) {
    _edit('settings', (t) => t.copyWith(settings: {...t.settings, ...changes}));
  }

  // ── Text & shapes (design 05) ────────────────────────────────────────────

  static const defaultTextStyle = <String, dynamic>{
    'font': 'NotoSansLao',
    'color': 0xFFFFFFFF,
    'align': 'center',
    'bold': true,
    'shadow': true,
    'size': 64,
  };

  /// New text layer at the playhead (3 s), sized to its nominal font size.
  String? addText(String text, {Map<String, dynamic>? style}) {
    final id = _newId();
    var e = TextElement(
      id: id,
      startMs: playhead.value,
      durationMs: 3000,
      text: text,
      style: {...defaultTextStyle, ...?style},
      transform: const ElementTransform(y: 0.3),
    );
    e = e.copyWith(transform: e.transform.copyWith(scale: TextLayer(e).naturalFraction()));
    final ok = _edit('addText', (t) => _placeOnFreeTrack(t, TrackKind.text, e));
    if (!ok) return null;
    _selected
      ..clear()
      ..add(id);
    notifyListeners();
    return id;
  }

  /// Change text and/or style; the on-screen font size stays the same.
  bool updateText(String id, {String? text, Map<String, dynamic>? style}) {
    final e = timeline.find(id)?.$2;
    if (e is! TextElement) return false;
    final next = e.copyWith(text: text, style: style == null ? null : {...e.style, ...style});
    final k = TextLayer(next).size.width / TextLayer(e).size.width;
    final scaled = next.copyWith(
      transform: next.transform.copyWith(scale: (e.transform.scale * k).clamp(0.03, 3.0)),
      keyframes: [
        for (final f in next.keyframes)
          Keyframe(f.timeMs, f.t.copyWith(scale: (f.t.scale * k).clamp(0.03, 3.0)),
              easing: f.easing, bezier: f.bezier),
      ],
    );
    return _edit('text', (t) => TimelineOps.updateElement(t, scaled));
  }

  String? addShape(String kind) {
    final id = _newId();
    final e = ShapeElement(
      id: id,
      startMs: playhead.value,
      durationMs: 3000,
      shape: kind,
      fillColor: 0xFFFFB300,
      transform: const ElementTransform(y: 0.4, scale: 0.3),
    );
    final ok = _edit('addShape', (t) => _placeOnFreeTrack(t, TrackKind.shape, e));
    if (!ok) return null;
    _selected
      ..clear()
      ..add(id);
    notifyListeners();
    return id;
  }

  bool updateShape(String id, {int? fill, int? stroke, double? strokeWidth}) {
    final e = timeline.find(id)?.$2;
    if (e is! ShapeElement) return false;
    return _edit('shape', (t) => TimelineOps.updateElement(
        t, e.copyWith(fillColor: fill, strokeColor: stroke, strokeWidth: strokeWidth)));
  }

  // ── Mask (design 04; images — the exporter bakes it into the picture) ────

  bool setMask(String id, MaskSpec? mask) {
    final e = timeline.find(id)?.$2;
    if (e is! ImageElement) return false;
    final m = mask == null || mask.shape == 'none' ? null : mask;
    return _edit('mask', (t) => TimelineOps.updateElement(
        t, m == null ? e.copyWith(clearMask: true) : e.copyWith(mask: m)));
  }

  // ── Position / keyframes (design 06) ─────────────────────────────────────

  static const int _kfTolMs = 80;

  /// Transform of [id] at the playhead (keyframes applied).
  ElementTransform? transformNow(String id) {
    final e = timeline.find(id)?.$2;
    if (e == null || e is! VisualElement) return null;
    final v = e as VisualElement;
    return transformAt(v.transform, v.keyframes, playhead.value - e.startMs);
  }

  TimelineElement _withVisual(TimelineElement e,
          {ElementTransform? transform, List<Keyframe>? keyframes}) =>
      switch (e) {
        VideoElement() => e.copyWith(transform: transform, keyframes: keyframes),
        ImageElement() => e.copyWith(transform: transform, keyframes: keyframes),
        TextElement() => e.copyWith(transform: transform, keyframes: keyframes),
        ShapeElement() => e.copyWith(transform: transform, keyframes: keyframes),
        _ => e,
      };

  /// Move/scale/rotate from the preview. With keyframes, it sets (or adds)
  /// the keyframe at the playhead; otherwise it changes the layer itself.
  bool setTransform(String id, ElementTransform tr) {
    final e = timeline.find(id)?.$2;
    if (e == null || e is! VisualElement) return false;
    final kfs = (e as VisualElement).keyframes;
    if (kfs.isEmpty) {
      return _edit('transform', (t) => TimelineOps.updateElement(t, _withVisual(e, transform: tr)));
    }
    final rel = (playhead.value - e.startMs).clamp(0, e.durationMs);
    final list = [...kfs];
    final i = list.indexWhere((k) => (k.timeMs - rel).abs() <= _kfTolMs);
    if (i >= 0) {
      list[i] = Keyframe(list[i].timeMs, tr, easing: list[i].easing, bezier: list[i].bezier);
    } else {
      list
        ..add(Keyframe(rel, tr))
        ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    }
    return _edit('transform', (t) => TimelineOps.updateElement(t, _withVisual(e, keyframes: list)));
  }

  /// Is there a keyframe of [id] at the playhead?
  bool hasKeyframeNow(String id) {
    final e = timeline.find(id)?.$2;
    if (e == null || e is! VisualElement) return false;
    final rel = playhead.value - e.startMs;
    return (e as VisualElement).keyframes.any((k) => (k.timeMs - rel).abs() <= _kfTolMs);
  }

  /// ◆: add a keyframe at the playhead (current look), or remove the one there.
  bool toggleKeyframe(String id) {
    final e = timeline.find(id)?.$2;
    if (e == null || e is! VisualElement) {
      lastError = 'wrongTrack';
      notifyListeners();
      return false;
    }
    final v = e as VisualElement;
    final rel = playhead.value - e.startMs;
    if (rel < 0 || rel > e.durationMs) {
      lastError = 'nothingHere';
      notifyListeners();
      return false;
    }
    final list = [...v.keyframes];
    final i = list.indexWhere((k) => (k.timeMs - rel).abs() <= _kfTolMs);
    if (i >= 0) {
      list.removeAt(i);
    } else {
      // The first keyframe also pins the starting look at time 0.
      if (list.isEmpty && rel > _kfTolMs) list.add(Keyframe(0, v.transform));
      list
        ..add(Keyframe(rel, transformAt(v.transform, v.keyframes, rel)))
        ..sort((a, b) => a.timeMs.compareTo(b.timeMs));
    }
    return _edit('keyframe', (t) => TimelineOps.updateElement(t, _withVisual(e, keyframes: list)));
  }

  /// Easing of the keyframe at/before the playhead (its outgoing curve).
  bool setEasing(String id, int easing, {List<double>? bezier}) {
    final e = timeline.find(id)?.$2;
    if (e == null || e is! VisualElement) return false;
    final rel = playhead.value - e.startMs;
    final list = [...(e as VisualElement).keyframes];
    var i = easingIndex(list, rel);
    if (i < 0) i = 0;
    if (list.isEmpty) return false;
    list[i] = Keyframe(list[i].timeMs, list[i].t, easing: easing, bezier: easing == 6 ? bezier : null);
    return _edit('easing', (t) => TimelineOps.updateElement(t, _withVisual(e, keyframes: list)));
  }

  /// The keyframe whose OUTGOING curve covers [rel]: the last one at/before
  /// it — but on the final keyframe (nothing after it) the segment leading in.
  static int easingIndex(List<Keyframe> kfs, int rel) {
    var i = kfs.lastIndexWhere((k) => k.timeMs <= rel + _kfTolMs);
    if (i < 0) i = 0;
    if (i == kfs.length - 1 && i > 0) i--;
    return i;
  }

  List<Keyframe> _kfClipboard = const [];
  bool get hasKeyframeClipboard => _kfClipboard.isNotEmpty;

  void copyKeyframes(String id) {
    final e = timeline.find(id)?.$2;
    if (e != null && e is VisualElement) _kfClipboard = List.of((e as VisualElement).keyframes);
    notifyListeners();
  }

  bool pasteKeyframes(String id) {
    final e = timeline.find(id)?.$2;
    if (e == null || e is! VisualElement || _kfClipboard.isEmpty) return false;
    final list = [
      for (final k in _kfClipboard)
        if (k.timeMs <= e.durationMs) k,
    ];
    return _edit('pasteKeyframes', (t) => TimelineOps.updateElement(t, _withVisual(e, keyframes: list)));
  }

  // ── In/out animations (as keyframes, so the exporter renders them) ───────

  static const animationKinds = ['none', 'fade', 'slideUp', 'slideLeft', 'pop'];

  /// Replace [id]'s keyframes with an in- and/or out-animation of [ms] each
  /// around its resting look.
  bool applyAnimation(String id, {String inKind = 'none', String outKind = 'none', int ms = 400}) {
    final e = timeline.find(id)?.$2;
    if (e == null || e is! VisualElement) return false;
    final base = (e as VisualElement).transform;
    final d = math.min(ms, e.durationMs ~/ 2);
    ElementTransform from(String kind) => switch (kind) {
          'fade' => base.copyWith(opacity: 0),
          'slideUp' => base.copyWith(y: base.y + 0.08, opacity: 0),
          'slideLeft' => base.copyWith(x: base.x + 0.15, opacity: 0),
          'pop' => base.copyWith(scale: base.scale * 0.6, opacity: 0),
          _ => base,
        };
    final kfs = <Keyframe>[
      if (inKind != 'none') ...[Keyframe(0, from(inKind), easing: 2), Keyframe(d, base)],
      if (outKind != 'none') ...[
        Keyframe(e.durationMs - d, base, easing: 1),
        Keyframe(e.durationMs, from(outKind)),
      ],
    ];
    return _edit('animation', (t) => TimelineOps.updateElement(t, _withVisual(e, keyframes: kfs)));
  }

  // ── Transitions (design 07) ──────────────────────────────────────────────

  bool setTransition(String fromId, String toId, String? kind, int durationMs) => _edit(
      'transition',
      (t) => kind == null || kind == 'none'
          ? TimelineOps.removeTransition(t, fromId, toId)
          : TimelineOps.setTransition(t, fromId, toId, kind, durationMs));

  /// Same transition between every pair of clips on the main track.
  bool setTransitionAll(String? kind, int durationMs) => _edit('transitionAll', (t) {
        var x = t;
        final els = x.mainTrack?.elements ?? const <TimelineElement>[];
        for (var i = 0; i + 1 < els.length; i++) {
          x = kind == null || kind == 'none'
              ? TimelineOps.removeTransition(x, els[i].id, els[i + 1].id)
              : TimelineOps.setTransition(x, els[i].id, els[i + 1].id, kind, durationMs);
        }
        return x;
      });

  Transition? transitionBetween(String fromId, String toId) =>
      timeline.transitions.where((x) => x.fromId == fromId && x.toId == toId).firstOrNull;

  /// How many PiP video layers overlap [ms] (the plan caps PRO at 2, Free 1).
  int pipLayersAt(int ms) => timeline
      .tracksOf(TrackKind.video)
      .where((t) => t.elements.any((e) => ms >= e.startMs && ms < e.endMs))
      .length;

  void undo() {
    if (history.undo()) {
      _dropMissingSelection();
      notifyListeners();
    }
  }

  void redo() {
    if (history.redo()) {
      _dropMissingSelection();
      notifyListeners();
    }
  }

  /// The project to persist (v1 + v2 JSON). Updates [lossy].
  SubtitleProject toProject({Map<String, String> rendered = const {}}) {
    final (p, l) = saveTimeline(base, timeline, rendered: rendered);
    if (coverPath != null) p.thumbnailPath = coverPath;
    lossy = l;
    return p;
  }

  @override
  void dispose() {
    playhead.dispose();
    super.dispose();
  }
}
