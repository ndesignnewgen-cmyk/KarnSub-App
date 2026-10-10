import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/subtitle_style_model.dart';
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
      history.run(label, f);
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
          VideoElement(id: _newId(), startMs: end, durationMs: durationMs, src: path));
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
  SubtitleProject toProject() {
    final (p, l) = saveTimeline(base, timeline);
    lossy = l;
    return p;
  }

  @override
  void dispose() {
    playhead.dispose();
    super.dispose();
  }
}
