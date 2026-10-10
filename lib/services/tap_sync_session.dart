import 'dart:math' as math;

import '../models/subtitle_style_model.dart';

/// "ແຕະໃຫ້ຕົງ" (Tap Sync) — pure, UI-free timing logic.
///
/// The user listens to the audio and presses/taps along with each sentence;
/// this class turns those presses (in MEDIA time, i.e. what the player reports)
/// into subtitle start/end times:
///   1. reaction offset   — humans press ~150–250 ms late; the offset is given
///                          in wall-clock ms and scaled by playback [speed]
///                          (180 ms of wall time at 0.5× = 90 ms of media).
///   2. snap (optional)   — move a start to the nearest speech onset and an end
///                          to the nearest speech end within [snapWindowMs].
///   3. rules (finalize)  — min duration, no overlap, min on-screen time.
///
/// Two modes:
///   * [TapMode.hold] — press = sentence starts, release = sentence ends.
///   * [TapMode.tap]  — every tap ends the current sentence and starts the next
///                      one (N sentences need N+1 taps; the last tap ends it).
///
/// Used for sentences (lines) and, in karaoke mode, for single words.
enum TapMode { hold, tap }

class TapLine {
  final String text;

  /// Existing timing (e.g. from AI); kept when the line is skipped/untouched.
  final int? origStartMs;
  final int? origEndMs;

  /// Media time of the press/release, before offset and snap.
  int? rawStartMs;
  int? rawEndMs;

  /// Final times after offset + snap (+ rules once [TapSyncSession.finalize]d).
  int? startMs;
  int? endMs;

  bool snappedStart = false;
  bool snappedEnd = false;
  bool skipped = false;

  TapLine(this.text, {this.origStartMs, this.origEndMs});

  /// Tapped in this session (both ends set).
  bool get isTapped => startMs != null && endMs != null && !skipped;

  /// Has usable timing — tapped, or original timing kept.
  int? get effStartMs => isTapped ? startMs : origStartMs;
  int? get effEndMs => isTapped ? endMs : origEndMs;
  bool get hasTiming => effStartMs != null && effEndMs != null;

  void _clearStart() {
    rawStartMs = null;
    startMs = null;
    snappedStart = false;
  }

  void _clearEnd() {
    rawEndMs = null;
    endMs = null;
    snappedEnd = false;
  }
}

class TapSyncSession {
  final List<TapLine> lines;
  final TapMode mode;

  /// Reaction compensation in wall-clock ms (negative = move earlier).
  final int offsetMs;

  /// Playback speed while recording (0.5 / 0.75 / 1.0).
  final double speed;

  final bool snap;
  final int snapWindowMs;

  /// Snapped starts land this much before the onset, so the text is already on
  /// screen when the first syllable is heard.
  final int snapLeadMs;

  final int minDurMs;
  final int minShowMs;

  /// Characters per second above which a line is flagged as too fast to read.
  final double maxCps;

  final List<int> _onsets;
  final List<int> _speechEnds;

  int _index;
  int get index => _index;

  TapSyncSession({
    required this.lines,
    this.mode = TapMode.hold,
    this.offsetMs = -180,
    this.speed = 1.0,
    this.snap = false,
    List<int> onsets = const [],
    List<int> speechEnds = const [],
    this.snapWindowMs = 300,
    this.snapLeadMs = 60,
    this.minDurMs = 300,
    this.minShowMs = 700,
    this.maxCps = 16,
    int startIndex = 0,
  })  : _onsets = List.of(onsets)..sort(),
        _speechEnds = List.of(speechEnds)..sort(),
        _index = startIndex.clamp(0, lines.length);

  bool get isDone => _index >= lines.length;
  TapLine? get current => isDone ? null : lines[_index];
  TapLine? get next => _index + 1 < lines.length ? lines[_index + 1] : null;
  int get tappedCount => lines.where((l) => l.isTapped).length;

  /// Hold mode: the current line has started and is waiting for release.
  /// Tap mode: the current line has started and the next tap ends it.
  bool get inProgress {
    final c = current;
    return c != null && c.rawStartMs != null && c.rawEndMs == null;
  }

  int _shift(int rawMs) => math.max(0, rawMs + (offsetMs * speed).round());

  void _setStart(TapLine l, int rawMs) {
    l.rawStartMs = rawMs;
    var t = _shift(rawMs);
    l.snappedStart = false;
    if (snap) {
      final n = nearest(_onsets, t, snapWindowMs);
      if (n != null) {
        t = math.max(0, n - snapLeadMs);
        l.snappedStart = true;
      }
    }
    l.startMs = t;
  }

  void _setEnd(TapLine l, int rawMs) {
    l.rawEndMs = rawMs;
    var t = _shift(rawMs);
    l.snappedEnd = false;
    if (snap) {
      final n = nearest(_speechEnds, t, snapWindowMs);
      if (n != null) {
        t = n;
        l.snappedEnd = true;
      }
    }
    final s = l.startMs ?? 0;
    if (t < s + minDurMs) t = s + minDurMs;
    l.endMs = t;
    l.skipped = false;
  }

  // ── Hold mode ────────────────────────────────────────────────────────────

  /// Finger down / volume key down: the current sentence starts now.
  void press(int mediaMs) {
    if (mode != TapMode.hold || isDone || inProgress) return;
    _setStart(lines[_index], mediaMs);
  }

  /// Finger up: the current sentence ends now; move to the next one.
  void release(int mediaMs) {
    if (mode != TapMode.hold || !inProgress) return;
    _setEnd(lines[_index], mediaMs);
    _index++;
  }

  // ── Tap mode ─────────────────────────────────────────────────────────────

  /// One tap: start the current line if it hasn't started, otherwise end it
  /// and start the next line at the same moment.
  void tap(int mediaMs) {
    if (mode != TapMode.tap || isDone) return;
    final c = lines[_index];
    if (c.rawStartMs == null) {
      _setStart(c, mediaMs);
      return;
    }
    _setEnd(c, mediaMs);
    _index++;
    if (!isDone) _setStart(lines[_index], mediaMs);
  }

  // ── Shared ───────────────────────────────────────────────────────────────

  /// Keep the current line's original timing and move on.
  void skip() {
    if (isDone) return;
    if (mode == TapMode.hold && inProgress) return; // finish the hold first
    final c = lines[_index];
    c._clearStart();
    c._clearEnd();
    c.skipped = true;
    _index++;
  }

  /// Go back one sentence. Returns the media time (ms) the player should
  /// rewind to (2 s before the part that has to be redone), or null if there
  /// is nothing to undo.
  int? undo({int prerollMs = 2000}) {
    int back(int? t) => math.max(0, (t ?? 0) - prerollMs);

    if (mode == TapMode.hold) {
      if (inProgress) {
        final c = lines[_index];
        final t = c.rawStartMs;
        c._clearStart();
        return back(t);
      }
      if (_index == 0) return null;
      _index--;
      final p = lines[_index];
      final t = p.rawStartMs ?? p.origStartMs;
      p._clearStart();
      p._clearEnd();
      p.skipped = false;
      return back(t);
    }

    // Tap mode: lines are chained (end of k == start of k+1).
    if (inProgress) {
      final c = lines[_index];
      if (_index == 0 || lines[_index - 1].rawEndMs == null) {
        // Only this line's start exists → clear it.
        final t = c.rawStartMs;
        c._clearStart();
        return back(t);
      }
      // Reopen the previous line: the next tap ends it again.
      c._clearStart();
      _index--;
      final p = lines[_index];
      final t = p.rawEndMs;
      p._clearEnd();
      return back(t);
    }
    if (isDone && _index > 0) {
      _index--;
      final p = lines[_index];
      final t = p.rawEndMs;
      p._clearEnd();
      return back(t);
    }
    if (_index == 0) return null;
    // Current not started (after a skip): step back over the skipped line.
    _index--;
    final p = lines[_index];
    p.skipped = false;
    p._clearStart();
    p._clearEnd();
    return back(p.origStartMs);
  }

  /// Apply the timing rules to every line with timing (tapped lines win over
  /// kept original ones) and return [lines]. Safe to call more than once.
  List<TapLine> finalize() {
    int? prevIdx;
    for (int i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (!l.hasTiming) continue;
      var s = l.effStartMs!;
      var e = l.effEndMs!;
      if (e < s + minDurMs) e = s + minDurMs;
      if (prevIdx != null) {
        final p = lines[prevIdx];
        final ps = p.effStartMs!;
        var pe = p.effEndMs!;
        if (s < ps + minDurMs) s = ps + minDurMs;
        if (pe > s) pe = s;
        _write(p, ps, pe);
        if (e < s + minDurMs) e = s + minDurMs;
      }
      _write(l, s, e);
      prevIdx = i;
    }
    // Minimum on-screen time, without running into the next line.
    for (int i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (!l.hasTiming) continue;
      final s = l.effStartMs!;
      var e = l.effEndMs!;
      if (e - s >= minShowMs) continue;
      int? nextStart;
      for (int j = i + 1; j < lines.length; j++) {
        if (lines[j].hasTiming) {
          nextStart = lines[j].effStartMs;
          break;
        }
      }
      e = s + minShowMs;
      if (nextStart != null && e > nextStart) e = math.max(nextStart, l.effEndMs!);
      _write(l, s, e);
    }
    return lines;
  }

  void _write(TapLine l, int s, int e) {
    if (l.isTapped) {
      l.startMs = s;
      l.endMs = e;
    } else {
      // Kept original timing is final for this run; store it as a tap result
      // only when it changed, so untouched lines stay "untouched".
      if (s != l.origStartMs || e != l.origEndMs) {
        l.startMs = s;
        l.endMs = e;
        l.skipped = false;
      }
    }
  }

  /// Too many characters per second to read comfortably.
  bool isTooFast(TapLine l) {
    if (!l.hasTiming) return false;
    final dur = (l.effEndMs! - l.effStartMs!) / 1000.0;
    if (dur <= 0) return true;
    final chars = l.text.replaceAll(RegExp(r'\s'), '').runes.length;
    return chars / dur > maxCps;
  }

  /// Give lines that still have no timing (pasted script, not tapped) a
  /// sequential default slot after the previous timed line.
  void fillUntimed({int defaultMs = 2000, int gapMs = 100}) {
    int cursor = 0;
    for (final l in lines) {
      if (l.hasTiming) {
        cursor = l.effEndMs! + gapMs;
        continue;
      }
      l.startMs = cursor;
      l.endMs = cursor + defaultMs;
      l.skipped = false;
      cursor += defaultMs + gapMs;
    }
  }

  /// Nearest value in sorted [sorted] to [t] within ±[window], else null.
  static int? nearest(List<int> sorted, int t, int window) {
    if (sorted.isEmpty) return null;
    int lo = 0, hi = sorted.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sorted[mid] < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    int best = sorted[lo];
    if (lo > 0 && (t - sorted[lo - 1]).abs() <= (best - t).abs()) {
      best = sorted[lo - 1];
    }
    return (best - t).abs() <= window ? best : null;
  }
}

/// Writes Tap Sync results back onto [SubtitleSegment]s.
class TapSyncApply {
  TapSyncApply._();

  /// Move [s] to [startMs, endMs]. Existing word timings are stretched
  /// proportionally into the new span so karaoke stays in step.
  static void retime(SubtitleSegment s, int startMs, int endMs) {
    final oa = s.startTime.inMilliseconds;
    final ob = s.endTime.inMilliseconds;
    final wt = s.wordTimings;
    if (wt != null && wt.isNotEmpty) {
      final span = ob - oa;
      s.wordTimings = wt.map((t) {
        final f = span > 0 ? (t.inMilliseconds - oa) / span : 0.0;
        final ms = startMs + (f.clamp(0.0, 1.0) * (endMs - startMs)).round();
        return Duration(milliseconds: ms);
      }).toList();
    }
    s.startTime = Duration(milliseconds: startMs);
    s.endTime = Duration(milliseconds: endMs);
  }

  /// Karaoke: [wordLines] are the tapped word units of segment [s], in order.
  /// Sets `words`, `wordTimings`, and the segment's start/end from them.
  /// In tap mode the last word of a sentence ends on the tap that starts the
  /// next sentence, which can include a pause — so its tail is capped at
  /// [maxTailMs].
  static void applyWords(SubtitleSegment s, List<TapLine> wordLines,
      {int maxTailMs = 1500}) {
    final timed = wordLines.where((w) => w.hasTiming).toList();
    if (timed.isEmpty) return;
    s.words = wordLines.map((w) => w.text).toList();
    final starts = <Duration>[];
    int last = timed.first.effStartMs!;
    for (final w in wordLines) {
      final t = w.effStartMs ?? last;
      last = math.max(last, t);
      starts.add(Duration(milliseconds: last));
    }
    s.wordTimings = starts;
    s.startTime = starts.first;
    final lastStart = starts.last.inMilliseconds;
    s.endTime = Duration(
        milliseconds: math.min(timed.last.effEndMs!, lastStart + maxTailMs));
  }
}
