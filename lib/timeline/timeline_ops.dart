import 'dart:math' as math;

import 'timeline_model.dart';

/// Thrown when an edit isn't allowed (overlap, locked track, wrong track…).
class TimelineEditError implements Exception {
  final String code; // overlap, locked, wrongTrack, notFound, tooShort, outside
  final String message;
  TimelineEditError(this.code, this.message);
  @override
  String toString() => 'TimelineEditError($code): $message';
}

/// Smallest element length an edit may leave.
const int kMinElementMs = 100;

/// Pure editing operations on an immutable [ProjectTimeline]. Each returns a
/// NEW timeline (unchanged elements are shared) or throws [TimelineEditError].
///
/// The main video track is always packed: clips sit back to back from 0, so
/// removing/trimming/moving there closes gaps automatically (CapCut style).
class TimelineOps {
  TimelineOps._();

  static bool canHold(TrackKind k, TimelineElement e) => switch (e) {
        VideoElement() => k == TrackKind.mainVideo || k == TrackKind.video,
        ImageElement() =>
          k == TrackKind.mainVideo || k == TrackKind.video || k == TrackKind.sticker,
        TextElement() => k == TrackKind.text,
        SubtitleElement() => k == TrackKind.subtitle,
        ShapeElement() => k == TrackKind.shape,
        AudioElement() => isAudioKind(k),
        EffectElement() => k == TrackKind.effect,
      };

  static Track _track(ProjectTimeline t, String trackId) {
    final tr = t.track(trackId);
    if (tr == null) throw TimelineEditError('notFound', 'track $trackId');
    if (tr.locked) throw TimelineEditError('locked', 'track $trackId is locked');
    return tr;
  }

  static (Track, TimelineElement) _find(ProjectTimeline t, String id) {
    final f = t.find(id);
    if (f == null) throw TimelineEditError('notFound', 'element $id');
    if (f.$1.locked) throw TimelineEditError('locked', 'track ${f.$1.id} is locked');
    return f;
  }

  static List<TimelineElement> _sorted(Iterable<TimelineElement> els) =>
      [...els]..sort((a, b) => a.startMs.compareTo(b.startMs));

  /// Lay main-track clips back to back from 0 in their current order.
  static List<TimelineElement> pack(List<TimelineElement> els) {
    var cursor = 0;
    return [
      for (final e in els)
        () {
          final out = e.startMs == cursor ? e : e.withTiming(startMs: cursor);
          cursor += e.durationMs;
          return out;
        }(),
    ];
  }

  static Track _put(Track tr, List<TimelineElement> els) => tr.copyWith(
      elements: tr.kind == TrackKind.mainVideo ? pack(els) : _sorted(els));

  static void _checkFits(Track tr, TimelineElement e, {String? ignoreId}) {
    if (tr.kind == TrackKind.mainVideo) return; // main track is re-packed
    if (e.startMs < 0) throw TimelineEditError('outside', 'starts before 0');
    if (!tr.fits(e.startMs, e.endMs, ignoreId: ignoreId)) {
      throw TimelineEditError('overlap', '${e.id} overlaps on ${tr.id}');
    }
  }

  // ── Elements ─────────────────────────────────────────────────────────────

  /// Add [e] to [trackId]. On the main track it is inserted where its start
  /// falls (between clips) and the track is re-packed.
  static ProjectTimeline addElement(ProjectTimeline t, String trackId, TimelineElement e) {
    final tr = _track(t, trackId);
    if (!canHold(tr.kind, e)) {
      throw TimelineEditError('wrongTrack', '${e.type} can\'t go on ${tr.kind.name}');
    }
    if (t.find(e.id) != null) throw TimelineEditError('duplicateId', e.id);
    if (e.durationMs < kMinElementMs) throw TimelineEditError('tooShort', e.id);
    if (tr.kind == TrackKind.mainVideo) {
      final els = [...tr.elements];
      var idx = els.indexWhere((x) => e.startMs < x.startMs + x.durationMs / 2);
      if (idx < 0) idx = els.length;
      els.insert(idx, e);
      return t.withTrack(_put(tr, els));
    }
    _checkFits(tr, e);
    return t.withTrack(_put(tr, [...tr.elements, e]));
  }

  /// Remove element [id]. [ripple] also pulls later elements on the same
  /// track left by its length (always on for the main track).
  static ProjectTimeline removeElement(ProjectTimeline t, String id, {bool ripple = false}) {
    final (tr, e) = _find(t, id);
    var els = tr.elements.where((x) => x.id != id).toList();
    if (ripple && tr.kind != TrackKind.mainVideo) {
      els = [
        for (final x in els)
          x.startMs >= e.endMs ? x.withTiming(startMs: x.startMs - e.durationMs) : x,
      ];
    }
    final transitions =
        t.transitions.where((x) => x.fromId != id && x.toId != id).toList();
    return t.withTrack(_put(tr, els)).copyWith(transitions: transitions);
  }

  /// Move element [id] to [toTrackId] at [startMs] (main track: to the slot
  /// where [startMs] lands).
  static ProjectTimeline moveElement(
      ProjectTimeline t, String id, String toTrackId, int startMs) {
    final (from, e) = _find(t, id);
    final to = _track(t, toTrackId);
    if (!canHold(to.kind, e)) {
      throw TimelineEditError('wrongTrack', '${e.type} can\'t go on ${to.kind.name}');
    }
    final moved = e.withTiming(startMs: math.max(0, startMs));
    if (from.id == to.id) {
      if (to.kind == TrackKind.mainVideo) {
        final rest = to.elements.where((x) => x.id != id).toList();
        // Compare against positions as if the moved clip were gone.
        final packed = pack(rest);
        var idx = packed.indexWhere((x) => moved.startMs < x.startMs + x.durationMs / 2);
        if (idx < 0) idx = rest.length;
        rest.insert(idx, moved);
        return t.withTrack(_put(to, rest));
      }
      _checkFits(to, moved, ignoreId: id);
      return t.withTrack(
          _put(to, [for (final x in to.elements) x.id == id ? moved : x]));
    }
    final t1 = t.withTrack(_put(from, from.elements.where((x) => x.id != id).toList()));
    return addElement(t1, toTrackId, moved);
  }

  /// Change start and/or end of [id] on the timeline. Trimming the LEFT edge
  /// of media also advances its source in-point.
  static ProjectTimeline trimElement(ProjectTimeline t, String id,
      {int? newStartMs, int? newEndMs}) {
    final (tr, e) = _find(t, id);
    final s = newStartMs ?? e.startMs;
    final end = newEndMs ?? e.endMs;
    if (end - s < kMinElementMs) throw TimelineEditError('tooShort', id);
    if (s < 0) throw TimelineEditError('outside', 'starts before 0');
    final leftDelta = s - e.startMs;
    TimelineElement out = e.withTiming(startMs: s, durationMs: end - s);
    if (leftDelta != 0) out = _shiftContent(out, leftDelta);
    if (out is VideoElement && out.trimInMs < 0) {
      throw TimelineEditError('outside', 'before the start of the source');
    }
    _checkFits(tr, out, ignoreId: id);
    return t.withTrack(_put(tr, [for (final x in tr.elements) x.id == id ? out : x]));
  }

  /// After the element's start moved by [deltaMs] on the timeline, shift what
  /// plays inside it so the content stays where it was in time.
  static TimelineElement _shiftContent(TimelineElement e, int deltaMs) {
    List<Keyframe> kf(List<Keyframe> ks) =>
        [for (final k in ks) Keyframe(k.timeMs - deltaMs, k.t, easing: k.easing, bezier: k.bezier)];
    return switch (e) {
      VideoElement() => e.copyWith(
          trimInMs: e.trimInMs + (deltaMs * e.speed).round(),
          keyframes: kf(e.keyframes)),
      AudioElement() => e.copyWith(trimInMs: e.trimInMs + (deltaMs * e.speed).round()),
      ImageElement() => e.copyWith(keyframes: kf(e.keyframes)),
      SubtitleElement() => e.copyWith(
          wordStartsMs: e.wordStartsMs?.map((w) => math.max(0, w - deltaMs)).toList()),
      _ => e,
    };
  }

  /// Split [id] at timeline [atMs] into two elements; the right half gets
  /// [newId]. Keyframes are divided between the halves.
  static ProjectTimeline splitElement(ProjectTimeline t, String id, int atMs, String newId) {
    final (tr, e) = _find(t, id);
    if (atMs - e.startMs < kMinElementMs || e.endMs - atMs < kMinElementMs) {
      throw TimelineEditError('tooShort', 'split too close to an edge');
    }
    if (e is SubtitleElement) {
      throw TimelineEditError('wrongTrack', 'subtitles are split by words in the editor');
    }
    final leftLen = atMs - e.startMs;
    var left = e.withTiming(durationMs: leftLen);
    var right = _shiftContent(
        e.withId(newId).withTiming(startMs: atMs, durationMs: e.endMs - atMs), leftLen);
    List<Keyframe> keep(List<Keyframe> ks, bool l) =>
        ks.where((k) => l ? k.timeMs <= leftLen : k.timeMs >= 0).toList();
    left = switch (left) {
      VideoElement() => left.copyWith(keyframes: keep(left.keyframes, true)),
      ImageElement() => left.copyWith(keyframes: keep(left.keyframes, true)),
      _ => left,
    };
    right = switch (right) {
      VideoElement() => right.copyWith(keyframes: keep(right.keyframes, false)),
      ImageElement() => right.copyWith(keyframes: keep(right.keyframes, false)),
      _ => right,
    };
    final els = <TimelineElement>[
      for (final x in tr.elements) ...(x.id == id ? [left, right] : [x]),
    ];
    // A transition that left this element now leaves the right half.
    final transitions = [
      for (final x in t.transitions)
        x.fromId == id ? Transition(fromId: newId, toId: x.toId, kind: x.kind, durationMs: x.durationMs) : x,
    ];
    return t.withTrack(_put(tr, els)).copyWith(transitions: transitions);
  }

  /// Replace element [e] (same id) — e.g. after changing volume, transform…
  static ProjectTimeline updateElement(ProjectTimeline t, TimelineElement e) {
    final (tr, old) = _find(t, e.id);
    if (old.runtimeType != e.runtimeType) {
      throw TimelineEditError('wrongTrack', 'type change ${old.type} → ${e.type}');
    }
    if (e.durationMs < kMinElementMs) throw TimelineEditError('tooShort', e.id);
    _checkFits(tr, e, ignoreId: e.id);
    return t.withTrack(_put(tr, [for (final x in tr.elements) x.id == e.id ? e : x]));
  }

  /// Copy [id] right after itself; if there's no room, onto another (or a new)
  /// track of the same kind. Returns the new timeline and the track used.
  static (ProjectTimeline, String) duplicateElement(
      ProjectTimeline t, String id, String newId) {
    final (tr, e) = _find(t, id);
    final copy = e.withId(newId).withTiming(startMs: e.endMs);
    if (tr.kind == TrackKind.mainVideo || tr.fits(copy.startMs, copy.endMs)) {
      if (tr.kind == TrackKind.mainVideo) {
        final els = [...tr.elements];
        els.insert(els.indexWhere((x) => x.id == id) + 1, copy);
        return (t.withTrack(_put(tr, els)), tr.id);
      }
      return (addElement(t, tr.id, copy), tr.id);
    }
    final same = e.withId(newId);
    for (final other in t.tracksOf(tr.kind)) {
      if (other.id != tr.id && !other.locked && other.fits(same.startMs, same.endMs)) {
        return (addElement(t, other.id, same), other.id);
      }
    }
    final newTrackId = '${tr.kind.name}_$newId';
    final t1 = addTrack(t, Track(id: newTrackId, kind: tr.kind), above: tr.id);
    return (addElement(t1, newTrackId, same), newTrackId);
  }

  // ── Tracks ───────────────────────────────────────────────────────────────

  static ProjectTimeline addTrack(ProjectTimeline t, Track track, {String? above}) {
    if (t.track(track.id) != null) throw TimelineEditError('duplicateId', track.id);
    if (track.kind == TrackKind.mainVideo && t.mainTrack != null) {
      throw TimelineEditError('wrongTrack', 'only one main video track');
    }
    final tracks = [...t.tracks];
    final i = above == null ? -1 : tracks.indexWhere((x) => x.id == above);
    tracks.insert(i < 0 ? tracks.length : i + 1, track);
    return t.copyWith(tracks: tracks);
  }

  static ProjectTimeline removeTrack(ProjectTimeline t, String trackId) {
    final tr = _track(t, trackId);
    if (tr.kind == TrackKind.mainVideo) {
      throw TimelineEditError('wrongTrack', 'the main video track can\'t be removed');
    }
    final ids = tr.elements.map((e) => e.id).toSet();
    return t.copyWith(
      tracks: t.tracks.where((x) => x.id != trackId).toList(),
      transitions: t.transitions
          .where((x) => !ids.contains(x.fromId) && !ids.contains(x.toId))
          .toList(),
    );
  }

  /// Mute / lock / hide / volume / duck (allowed on locked tracks — that's
  /// how you unlock them).
  static ProjectTimeline updateTrack(ProjectTimeline t, String trackId,
      {bool? muted, bool? locked, bool? hidden, double? volume, bool? duck}) {
    final tr = t.track(trackId);
    if (tr == null) throw TimelineEditError('notFound', 'track $trackId');
    return t.withTrack(tr.copyWith(
        muted: muted, locked: locked, hidden: hidden, volume: volume, duck: duck));
  }

  // ── Transitions ──────────────────────────────────────────────────────────

  /// Transition between two ADJACENT main-track clips (replaces an existing
  /// one). Its length is capped to half of the shorter clip.
  static ProjectTimeline setTransition(
      ProjectTimeline t, String fromId, String toId, String kind, int durationMs) {
    final main = t.mainTrack;
    final i = main?.elements.indexWhere((e) => e.id == fromId) ?? -1;
    if (main == null || i < 0 || i + 1 >= main.elements.length ||
        main.elements[i + 1].id != toId) {
      throw TimelineEditError('notFound', 'clips are not adjacent on the main track');
    }
    final cap = math.min(main.elements[i].durationMs, main.elements[i + 1].durationMs) ~/ 2;
    final tr = Transition(
        fromId: fromId, toId: toId, kind: kind, durationMs: durationMs.clamp(0, cap));
    return t.copyWith(transitions: [
      ...t.transitions.where((x) => !(x.fromId == fromId && x.toId == toId)),
      tr,
    ]);
  }

  static ProjectTimeline removeTransition(ProjectTimeline t, String fromId, String toId) =>
      t.copyWith(
          transitions: t.transitions
              .where((x) => !(x.fromId == fromId && x.toId == toId))
              .toList());

  // ── Keep linked tracks on their content ──────────────────────────────────

  /// Tracks whose elements belong to the video content under them (speech
  /// subtitles, sound effects, effects) and so follow main-track edits.
  static const linkedKinds = {TrackKind.subtitle, TrackKind.sfx, TrackKind.effect};

  /// After a main-track edit ([before] → [after]), move every element on a
  /// linked track so it stays over the same moment of the SOURCE video:
  /// trimming or deleting a clip shifts what follows; content that was cut
  /// away takes its elements with it (partly cut → shortened).
  static ProjectTimeline relink(ProjectTimeline before, ProjectTimeline after) {
    final oldMain = before.mainTrack?.elements.whereType<VideoElement>().toList() ?? const [];
    final newMain = after.mainTrack?.elements.whereType<VideoElement>().toList() ?? const [];
    if (oldMain.isEmpty) return after;

    int? mapPoint(int t, {required bool isEnd}) {
      VideoElement? m;
      for (final c in oldMain) {
        if (isEnd ? (t > c.startMs && t <= c.endMs) : (t >= c.startMs && t < c.endMs)) {
          m = c;
          break;
        }
      }
      if (m == null) return null;
      final src = m.trimInMs + ((t - m.startMs) * m.speed).round();
      bool covers(VideoElement c) =>
          c.src == m!.src && (isEnd ? (src > c.trimInMs && src <= c.trimOutMs) : (src >= c.trimInMs && src < c.trimOutMs));
      final same = newMain.where((c) => c.id == m!.id && covers(c));
      final any = same.isNotEmpty ? same.first : newMain.where(covers).firstOrNull;
      if (any == null) return null;
      return any.startMs + ((src - any.trimInMs) / any.speed).round();
    }

    // The new clip(s) that a cut-away start/end should snap to.
    int? snapInto(TimelineElement e, int? s, int? end) {
      if (s != null || end == null) return s;
      // Start was cut away: begin at the start of the clip that holds the end.
      for (final c in newMain) {
        if (end > c.startMs && end <= c.endMs) return c.startMs;
      }
      return null;
    }

    final tracks = <Track>[];
    for (final tr in after.tracks) {
      if (!linkedKinds.contains(tr.kind) || tr.locked) {
        tracks.add(tr);
        continue;
      }
      final els = <TimelineElement>[];
      for (final e in tr.elements) {
        var s = mapPoint(e.startMs, isEnd: false);
        var end = mapPoint(e.endMs, isEnd: true);
        s = snapInto(e, s, end);
        if (s != null && end == null) {
          // End was cut away: stop at the end of the clip that holds the start.
          for (final c in newMain) {
            if (s >= c.startMs && s < c.endMs) {
              end = c.endMs;
              break;
            }
          }
        }
        if (s == null || end == null || end - s < kMinElementMs) continue; // content gone
        final s0 = s, e0 = end;
        var moved = e.startMs == s ? e : e.withTiming(startMs: s);
        if (moved.durationMs != end - s) moved = moved.withTiming(durationMs: end - s);
        if (moved is SubtitleElement && moved.wordStartsMs != null) {
          final shift = s - e.startMs;
          moved = moved.copyWith(
            wordStartsMs: [
              for (final w in moved.wordStartsMs!)
                (mapPoint(e.startMs + w, isEnd: false) ?? (e.startMs + w + shift)) - s0,
            ].map((w) => w.clamp(0, e0 - s0)).toList(),
          );
        }
        els.add(moved);
      }
      els.sort((a, b) => a.startMs.compareTo(b.startMs));
      // Never leave overlaps behind on one track.
      final clean = <TimelineElement>[];
      for (final e in els) {
        if (clean.isNotEmpty && e.startMs < clean.last.endMs) {
          final room = clean.last.endMs - e.startMs;
          if (e.durationMs - room < kMinElementMs) continue;
          clean.add(e.withTiming(startMs: clean.last.endMs, durationMs: e.durationMs - room));
        } else {
          clean.add(e);
        }
      }
      tracks.add(tr.copyWith(elements: clean));
    }
    return after.copyWith(tracks: tracks);
  }

  // ── Snapping (for drag/trim in the UI) ───────────────────────────────────

  /// Edges of every element (except [excludeId]), bookmarks, 0 and [extra].
  static List<int> snapPoints(ProjectTimeline t, {String? excludeId, List<int> extra = const []}) {
    final s = <int>{0, ...t.bookmarksMs, ...extra};
    for (final tr in t.tracks) {
      for (final e in tr.elements) {
        if (e.id == excludeId) continue;
        s..add(e.startMs)..add(e.endMs);
      }
    }
    return s.toList()..sort();
  }

  /// [ms] pulled to the nearest point within [toleranceMs], else unchanged.
  static int snap(int ms, List<int> points, int toleranceMs) {
    int best = ms;
    int bestD = toleranceMs + 1;
    for (final p in points) {
      final d = (p - ms).abs();
      if (d < bestD) {
        best = p;
        bestD = d;
      }
    }
    return bestD <= toleranceMs ? best : ms;
  }
}

/// Undo/redo over immutable timelines. Each step keeps a reference to the
/// previous [ProjectTimeline] — elements are shared, so a step costs a few
/// lists of pointers, not a copy of the project.
class TimelineHistory {
  ProjectTimeline _current;
  final List<(ProjectTimeline, String)> _undo = [];
  final List<(ProjectTimeline, String)> _redo = [];
  final int limit;

  ProjectTimeline? _batchStart;
  String _batchLabel = '';

  TimelineHistory(this._current, {this.limit = 100});

  ProjectTimeline get current => _current;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.$2;
  String? get redoLabel => _redo.isEmpty ? null : _redo.last.$2;
  bool get inBatch => _batchStart != null;

  /// Timeline when the current batch began (null outside a batch).
  ProjectTimeline? get batchStart => _batchStart;

  /// Apply [edit] (a pure function, usually a [TimelineOps] call). If it
  /// throws, nothing changes. Returns the new timeline.
  ProjectTimeline run(String label, ProjectTimeline Function(ProjectTimeline) edit) {
    final next = edit(_current);
    if (identical(next, _current)) return _current;
    if (_batchStart == null) _push(label);
    _current = next;
    return _current;
  }

  void _push(String label) {
    _undo.add((_current, label));
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  /// Group several edits (e.g. a whole drag, or "Auto edit") into ONE undo
  /// step. Nested calls are flattened into the outer batch.
  void beginBatch(String label) {
    if (_batchStart != null) return;
    _batchStart = _current;
    _batchLabel = label;
  }

  void endBatch() {
    final start = _batchStart;
    if (start == null) return;
    _batchStart = null;
    if (identical(start, _current)) return; // nothing changed
    _undo.add((start, _batchLabel));
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  /// Abandon the current batch and go back to where it began.
  void cancelBatch() {
    final start = _batchStart;
    if (start == null) return;
    _batchStart = null;
    _current = start;
  }

  bool undo() {
    if (_batchStart != null) endBatch();
    if (_undo.isEmpty) return false;
    final (prev, label) = _undo.removeLast();
    _redo.add((_current, label));
    _current = prev;
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    final (next, label) = _redo.removeLast();
    _undo.add((_current, label));
    _current = next;
    return true;
  }
}
