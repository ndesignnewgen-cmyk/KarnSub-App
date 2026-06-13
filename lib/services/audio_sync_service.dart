import 'package:flutter/services.dart';
import '../models/subtitle_style_model.dart';

/// Aligns subtitle timing to the actual speech in the audio using a native
/// energy-based VAD (voice activity detection). Used both automatically right
/// after transcription and from the manual "auto-sync" button in the editor.
class AudioSyncService {
  static const _channel = MethodChannel('com.anniekaydee.subtitle_app/audio');

  /// Small lead so the subtitle appears just before the word is spoken.
  static const int _leadMs = 80;

  /// Detect speech-onset times (ms), sorted. Returns [] on failure / no speech.
  static Future<List<int>> detectSpeechOnsets(String videoPath) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
          'detectSpeechOnsets', {'videoPath': videoPath});
      final list = (raw ?? []).map((e) => (e as num).toInt()).toList()..sort();
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Nearest onset (ms) to [t] via binary search over sorted [onsets].
  static int _nearest(List<int> onsets, int t) {
    if (t <= onsets.first) return onsets.first;
    if (t >= onsets.last) return onsets.last;
    int lo = 0, hi = onsets.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (onsets[mid] == t) return t;
      if (onsets[mid] < t) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    final a = onsets[hi], b = onsets[lo];
    return (t - a) <= (b - t) ? a : b;
  }

  /// Align [segs] (mutated in place) to speech [onsets] across the WHOLE
  /// timeline, not just the start:
  /// 1) fit a linear time-warp  realTime = a*geminiTime + b  (corrects drift
  ///    that grows over time, not only a constant offset; scale clamped),
  /// 2) snap each segment start to a nearby onset (minus a small lead),
  /// 3) keep order and prevent overlap.
  /// Returns number of segments snapped. Reports the median delta via [outDelta].
  static int alignToOnsets(
    List<SubtitleSegment> segs,
    List<int> onsets, {
    void Function(int globalDeltaMs)? outDelta,
  }) {
    if (segs.isEmpty || onsets.length < 2) {
      outDelta?.call(0);
      return 0;
    }
    int clampMs(int v) => v < 0 ? 0 : v;

    void applyMap(double a, double b) {
      int m(int t) => clampMs((a * t + b).round());
      for (final s in segs) {
        s.startTime = Duration(milliseconds: m(s.startTime.inMilliseconds));
        s.endTime = Duration(milliseconds: m(s.endTime.inMilliseconds));
        if (s.wordTimings != null) {
          s.wordTimings =
              s.wordTimings!.map((t) => Duration(milliseconds: m(t.inMilliseconds))).toList();
        }
      }
    }

    // Anchor pairs: gemini start (x) ↔ nearest speech onset (y), within 900ms.
    var xs = <int>[];
    var ys = <int>[];
    final deltas = <int>[];
    for (final s in segs) {
      final st = s.startTime.inMilliseconds;
      final n = _nearest(onsets, st);
      if ((n - st).abs() <= 900) {
        xs.add(st);
        ys.add(n);
        deltas.add(n - st);
      }
    }

    int medianDelta = 0;
    if (deltas.isNotEmpty) {
      final d = [...deltas]..sort();
      medianDelta = d[d.length ~/ 2];
    }

    if (xs.length >= 4) {
      // Least-squares line fit with one outlier-rejection pass.
      double a = 1, b = medianDelta.toDouble();
      for (int pass = 0; pass < 2; pass++) {
        final n = xs.length;
        if (n < 2) break;
        double sx = 0, sy = 0, sxy = 0, sxx = 0;
        for (int i = 0; i < n; i++) {
          sx += xs[i];
          sy += ys[i];
          sxy += xs[i].toDouble() * ys[i];
          sxx += xs[i].toDouble() * xs[i];
        }
        final denom = n * sxx - sx * sx;
        if (denom.abs() < 1e-6) {
          a = 1;
          b = (sy - sx) / n;
          break;
        }
        a = (n * sxy - sx * sy) / denom;
        if (a < 0.9) a = 0.9;
        if (a > 1.1) a = 1.1;
        b = (sy - a * sx) / n; // offset given (clamped) scale
        if (pass == 0) {
          final nx = <int>[];
          final ny = <int>[];
          for (int i = 0; i < n; i++) {
            if ((ys[i] - (a * xs[i] + b)).abs() <= 250) {
              nx.add(xs[i]);
              ny.add(ys[i]);
            }
          }
          if (nx.length >= 2) {
            xs = nx;
            ys = ny;
          } else {
            break;
          }
        }
      }
      applyMap(a, b);
    } else if (deltas.isNotEmpty) {
      applyMap(1.0, medianDelta.toDouble());
    }

    // Refine: snap each segment start to its nearest onset (±350ms), keep order.
    int snapped = 0;
    for (int i = 0; i < segs.length; i++) {
      final s = segs[i];
      final st = s.startTime.inMilliseconds;
      final n = _nearest(onsets, st);
      if ((n - st).abs() > 350) continue;
      final newStart = clampMs(n - _leadMs);
      final prevStart = i > 0 ? segs[i - 1].startTime.inMilliseconds : 0;
      if (newStart <= prevStart) continue; // would break ordering
      final d = newStart - st;
      if (d == 0) continue;
      final dur = s.endTime.inMilliseconds - st;
      s.startTime = Duration(milliseconds: newStart);
      s.endTime = Duration(milliseconds: newStart + dur);
      if (s.wordTimings != null) {
        s.wordTimings = s.wordTimings!
            .map((t) => Duration(milliseconds: clampMs(t.inMilliseconds + d)))
            .toList();
      }
      snapped++;
    }

    // Prevent overlap
    for (int i = 0; i < segs.length - 1; i++) {
      if (segs[i].endTime > segs[i + 1].startTime) {
        segs[i].endTime = segs[i + 1].startTime;
      }
    }

    outDelta?.call(medianDelta);
    return snapped;
  }

  /// Convenience: detect onsets then align [segs] in place. Safe (no-op on failure).
  static Future<int> autoAlign(String videoPath, List<SubtitleSegment> segs) async {
    final onsets = await detectSpeechOnsets(videoPath);
    return alignToOnsets(segs, onsets);
  }

  /// Forced alignment using a real ASR word timeline (e.g. Whisper).
  ///
  /// Keeps the Gemini TEXT and word grouping, but replaces every segment's
  /// start/end and word timings by laying the words onto [whisperStartsMs] (the
  /// accurate per-word onsets from Whisper) IN ORDER. Each word is positioned
  /// proportionally and then SNAPPED to the nearest real Whisper onset (within a
  /// window) so it starts exactly when the voice does — far tighter than a plain
  /// interpolation, and still immune to Gemini's timestamp drift.
  /// [whisperEndMs] is the end of the last spoken word. Mutates [segs] in place.
  static void forcedAlignToWhisper(
    List<SubtitleSegment> segs,
    List<int> whisperStartsMs,
    int whisperEndMs,
  ) {
    if (segs.isEmpty || whisperStartsMs.length < 2) return;
    int clampMs(int v) => v < 0 ? 0 : v;
    final w = whisperStartsMs.length;

    // Word count per segment (≥1 each) and the running total.
    final segWordCount = <int>[];
    int totalWords = 0;
    for (final s in segs) {
      final n = (s.words != null && s.words!.isNotEmpty)
          ? s.words!.where((x) => x.trim().isNotEmpty).length
          : 1;
      final c = n < 1 ? 1 : n;
      segWordCount.add(c);
      totalWords += c;
    }
    if (totalWords < 1) return;

    // Interpolate the Whisper onset timeline at fractional index f ∈ [0, w-1].
    double interp(double f) {
      if (f <= 0) return whisperStartsMs.first.toDouble();
      if (f >= w - 1) return whisperStartsMs.last.toDouble();
      final i = f.floor();
      final frac = f - i;
      return whisperStartsMs[i] +
          (whisperStartsMs[i + 1] - whisperStartsMs[i]) * frac;
    }

    // Nearest real Whisper onset to time [t] (binary search; list is sorted).
    int nearestOnset(int t) {
      if (t <= whisperStartsMs.first) return whisperStartsMs.first;
      if (t >= whisperStartsMs.last) return whisperStartsMs.last;
      int lo = 0, hi = w - 1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        if (whisperStartsMs[mid] == t) return t;
        if (whisperStartsMs[mid] < t) {
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      final a = whisperStartsMs[hi], b = whisperStartsMs[lo];
      return (t - a) <= (b - t) ? a : b;
    }

    // Pre-compute a monotonic start time for every word boundary g (0..totalWords).
    // Snap to a real onset when one is within [snapWindow]; otherwise keep the
    // interpolated value. Monotonic so a snap never pulls a word before its prev.
    const snapWindow = 160; // ms
    final wordStart = List<int>.filled(totalWords + 1, 0);
    int prev = 0;
    for (int gi = 0; gi <= totalWords; gi++) {
      int t;
      if (gi >= totalWords) {
        t = whisperEndMs;
      } else {
        final base = interp(gi * (w - 1) / totalWords).round();
        final near = nearestOnset(base);
        t = (near - base).abs() <= snapWindow ? near : base;
      }
      if (t < prev) t = prev;
      wordStart[gi] = t;
      prev = t;
    }

    int g = 0;
    for (int si = 0; si < segs.length; si++) {
      final s = segs[si];
      final n = segWordCount[si];
      final startMs = wordStart[g];
      int endMs = (si == segs.length - 1) ? whisperEndMs : wordStart[g + n];
      if (endMs < startMs + 200) endMs = startMs + 200;

      if (s.words != null && s.words!.isNotEmpty) {
        final units = s.words!.where((x) => x.trim().isNotEmpty).toList();
        s.wordTimings = List.generate(
          units.length,
          (k) => Duration(milliseconds: clampMs(wordStart[g + k])),
        );
      }
      s.startTime = Duration(milliseconds: clampMs(startMs));
      s.endTime = Duration(milliseconds: clampMs(endMs));
      g += n;
    }

    // Keep order / no overlap.
    for (int i = 0; i < segs.length - 1; i++) {
      if (segs[i].endTime > segs[i + 1].startTime) {
        segs[i].endTime = segs[i + 1].startTime;
      }
    }
  }

  /// DTW (Dynamic Time Warping) forced alignment — the accurate aligner.
  ///
  /// Instead of mapping "Gemini's Nth word → Whisper's Nth onset" proportionally
  /// (which drifts when the two engines split words differently), this aligns
  /// Gemini's word-TIME sequence to Whisper's real onsets with DTW, so each word
  /// lands on the correct onset. Then it sets every block's END to the next
  /// word's real onset (B) so block length matches the actual speech span.
  /// Falls back to [forcedAlignToWhisper] for very long inputs. Mutates [segs].
  static void dtwAlignToWhisper(
    List<SubtitleSegment> segs,
    List<int> whisperStartsMs,
    int whisperEndMs,
  ) {
    if (segs.isEmpty || whisperStartsMs.length < 2) return;
    final w = [...whisperStartsMs]..sort();
    final m = w.length;

    // 1. Flatten Gemini word-start times G (per word), and word-count per segment.
    final segWordCount = <int>[];
    final g = <int>[];
    for (final s in segs) {
      final units = (s.words != null && s.words!.isNotEmpty)
          ? s.words!.where((x) => x.trim().isNotEmpty).toList()
          : <String>[s.text];
      final n = units.isEmpty ? 1 : units.length;
      segWordCount.add(n);
      final st = s.startTime.inMilliseconds;
      final en = s.endTime.inMilliseconds > st
          ? s.endTime.inMilliseconds
          : st + n * 250;
      final hasT = s.wordTimings != null && s.wordTimings!.length == n;
      for (int k = 0; k < n; k++) {
        g.add(hasT ? s.wordTimings![k].inMilliseconds : st + (en - st) * k ~/ n);
      }
    }
    final nWords = g.length;
    if (nWords < 1) return;
    for (int i = 1; i < nWords; i++) {
      if (g[i] < g[i - 1]) g[i] = g[i - 1]; // monotonic
    }

    // Guard: huge DP → fall back to the proportional aligner.
    if (nWords * m > 400000) {
      forcedAlignToWhisper(segs, whisperStartsMs, whisperEndMs);
      return;
    }

    int nearest(int t) {
      if (t <= w.first) return w.first;
      if (t >= w.last) return w.last;
      int lo = 0, hi = m - 1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        if (w[mid] == t) return t;
        if (w[mid] < t) {
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      final a = w[hi], b = w[lo];
      return (t - a) <= (b - t) ? a : b;
    }

    // 2. Remove global median shift so DTW cost is meaningful.
    final deltas = <int>[];
    for (final t in g) {
      final nn = nearest(t);
      if ((nn - t).abs() <= 4000) deltas.add(nn - t);
    }
    int shift = 0;
    if (deltas.isNotEmpty) {
      deltas.sort();
      shift = deltas[deltas.length ~/ 2];
    }
    final gs = [for (final t in g) t + shift];

    int min3(int a, int b, int c) {
      final ab = a < b ? a : b;
      return ab < c ? ab : c;
    }

    // 3. DTW cost matrix.
    final d = List.generate(nWords, (_) => List<int>.filled(m, 0));
    for (int i = 0; i < nWords; i++) {
      for (int j = 0; j < m; j++) {
        final c = (gs[i] - w[j]).abs();
        if (i == 0 && j == 0) {
          d[i][j] = c;
        } else if (i == 0) {
          d[i][j] = c + d[i][j - 1];
        } else if (j == 0) {
          d[i][j] = c + d[i - 1][j];
        } else {
          d[i][j] = c + min3(d[i - 1][j], d[i - 1][j - 1], d[i][j - 1]);
        }
      }
    }

    // 4. Backtrack → each word's mapped onset (earliest onset on its path cell).
    final mapped = List<int>.filled(nWords, 0);
    int ii = nWords - 1, jj = m - 1;
    while (ii >= 0 && jj >= 0) {
      mapped[ii] = w[jj];
      if (ii == 0 && jj == 0) break;
      if (ii == 0) {
        jj--;
      } else if (jj == 0) {
        ii--;
      } else {
        final diag = d[ii - 1][jj - 1], up = d[ii - 1][jj], left = d[ii][jj - 1];
        final mn = min3(diag, up, left);
        if (mn == diag) {
          ii--;
          jj--;
        } else if (mn == up) {
          ii--;
        } else {
          jj--;
        }
      }
    }
    // 5. Monotonic non-decreasing.
    for (int k = 1; k < nWords; k++) {
      if (mapped[k] < mapped[k - 1]) mapped[k] = mapped[k - 1];
    }

    // 6. Assign back + set block ends to the next real onset (B).
    int gi = 0;
    for (int si = 0; si < segs.length; si++) {
      final s = segs[si];
      final n = segWordCount[si];
      final startMs = mapped[gi];
      if (s.words != null && s.words!.isNotEmpty) {
        final units = s.words!.where((x) => x.trim().isNotEmpty).toList();
        s.wordTimings = List.generate(units.length,
            (k) => Duration(milliseconds: (gi + k < nWords ? mapped[gi + k] : startMs)));
      }
      final lastWord = mapped[(gi + n - 1).clamp(0, nWords - 1)];
      int endMs;
      if (si == segs.length - 1) {
        endMs = whisperEndMs > lastWord ? whisperEndMs : lastWord + 600;
      } else {
        endMs = mapped[(gi + n).clamp(0, nWords - 1)]; // next word's onset
        final cap = lastWord + 1800; // don't linger across long silence
        if (endMs > cap) endMs = cap;
      }
      if (endMs < startMs + 250) endMs = startMs + 250;
      s.startTime = Duration(milliseconds: startMs < 0 ? 0 : startMs);
      s.endTime = Duration(milliseconds: endMs);
      gi += n;
    }
    // No overlap.
    for (int k = 0; k < segs.length - 1; k++) {
      if (segs[k].endTime > segs[k + 1].startTime) {
        segs[k].endTime = segs[k + 1].startTime;
      }
    }
  }

  /// Normalised audio amplitude (0..1) sampled every [waveformStepMs] ms.
  static const int waveformStepMs = 20;
  static Future<List<double>> waveform(String videoPath) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
          'audioWaveform', {'videoPath': videoPath});
      return (raw ?? []).map((e) => (e as num).toDouble()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Detect speech regions [startMs, endMs], sorted by start. [] on failure.
  static Future<List<List<int>>> detectSpeechRegions(String videoPath) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
          'detectSpeechRegions', {'videoPath': videoPath});
      final flat = (raw ?? []).map((e) => (e as num).toInt()).toList();
      final regions = <List<int>>[];
      for (int i = 0; i + 1 < flat.length; i += 2) {
        regions.add([flat[i], flat[i + 1]]);
      }
      regions.sort((a, b) => a[0].compareTo(b[0]));
      return regions;
    } catch (_) {
      return [];
    }
  }

  /// Strong AI sync: fit each subtitle's START and END to the spoken phrase's
  /// real boundaries (front + back), stretching/shrinking automatically. When
  /// several subtitles map to one speech region they share it proportionally.
  /// Returns number of segments aligned.
  static int alignToRegions(List<SubtitleSegment> segs, List<List<int>> regions) {
    if (segs.isEmpty || regions.isEmpty) return 0;
    int clampMs(int v) => v < 0 ? 0 : v;
    const leadMs = 60;
    const lingerMs = 120;
    final rStart = regions.map((r) => r[0]).toList();

    void redistributeWordTimings(SubtitleSegment s) {
      final n = s.wordTimings?.length ?? 0;
      if (n == 0) return;
      final a = s.startTime.inMilliseconds;
      final b = s.endTime.inMilliseconds;
      final span = (b - a).clamp(1, 1 << 31);
      // Preserve Gemini's RELATIVE word spacing (some words are spoken faster,
      // some slower) by linearly remapping the existing word timings into the
      // new [a, b] range — this keeps karaoke highlight on-beat. Only fall back
      // to uniform spacing when the original timings are flat/degenerate.
      final old = s.wordTimings!.map((d) => d.inMilliseconds).toList();
      final oldSpan = old.last - old.first;
      if (oldSpan > 50) {
        final first = old.first;
        s.wordTimings = List.generate(n, (i) {
          final f = ((old[i] - first) / oldSpan).clamp(0.0, 1.0);
          return Duration(milliseconds: a + (span * f).round());
        });
      } else {
        s.wordTimings = List.generate(
            n, (i) => Duration(milliseconds: a + (span * i ~/ n)));
      }
    }

    // 1. Correct drift with a linear time-warp  realTime = a*t + b  fitted from
    //    (gemini start ↔ nearest region start) anchor pairs. Unlike a constant
    //    offset, this also corrects drift that GROWS over a long video (so the
    //    END of the clip stays synced, not just the start). Scale is clamped to
    //    ±10% and there's one outlier-rejection pass; falls back to a constant
    //    median shift when too few clean anchors are available.
    var xs = <int>[];
    var ys = <int>[];
    final deltas = <int>[];
    for (final s in segs) {
      final st = s.startTime.inMilliseconds;
      final n = _nearest(rStart, st);
      if ((n - st).abs() <= 1000) {
        xs.add(st);
        ys.add(n);
        deltas.add(n - st);
      }
    }
    int medianDelta = 0;
    if (deltas.isNotEmpty) {
      final d = [...deltas]..sort();
      medianDelta = d[d.length ~/ 2];
    }
    double wa = 1.0, wb = medianDelta.toDouble();
    if (xs.length >= 4) {
      for (int pass = 0; pass < 2; pass++) {
        final n = xs.length;
        if (n < 2) break;
        double sx = 0, sy = 0, sxy = 0, sxx = 0;
        for (int i = 0; i < n; i++) {
          sx += xs[i];
          sy += ys[i];
          sxy += xs[i].toDouble() * ys[i];
          sxx += xs[i].toDouble() * xs[i];
        }
        final denom = n * sxx - sx * sx;
        if (denom.abs() < 1e-6) {
          wa = 1;
          wb = (sy - sx) / n;
          break;
        }
        wa = (n * sxy - sx * sy) / denom;
        if (wa < 0.9) wa = 0.9;
        if (wa > 1.1) wa = 1.1;
        wb = (sy - wa * sx) / n;
        if (pass == 0) {
          final nx = <int>[];
          final ny = <int>[];
          for (int i = 0; i < n; i++) {
            if ((ys[i] - (wa * xs[i] + wb)).abs() <= 250) {
              nx.add(xs[i]);
              ny.add(ys[i]);
            }
          }
          if (nx.length >= 2) {
            xs = nx;
            ys = ny;
          } else {
            break;
          }
        }
      }
    }
    if (wa != 1.0 || wb != 0.0) {
      int m(int t) => clampMs((wa * t + wb).round());
      for (final s in segs) {
        s.startTime = Duration(milliseconds: m(s.startTime.inMilliseconds));
        s.endTime = Duration(milliseconds: m(s.endTime.inMilliseconds));
        if (s.wordTimings != null) {
          s.wordTimings = s.wordTimings!
              .map((t) => Duration(milliseconds: m(t.inMilliseconds)))
              .toList();
        }
      }
    }

    // 2. Assign each segment to its best speech region (nearest by start).
    final assign = List<int>.filled(segs.length, -1);
    for (int i = 0; i < segs.length; i++) {
      final st = segs[i].startTime.inMilliseconds;
      int best = -1;
      int bestD = 1 << 30;
      for (int r = 0; r < regions.length; r++) {
        final rs = regions[r][0], re = regions[r][1];
        final d = (st < rs) ? rs - st : (st > re ? st - re : 0); // 0 if inside
        if (d < bestD) { bestD = d; best = r; }
      }
      if (best != -1 && bestD <= 800) assign[i] = best;
    }

    // 3. For each region with assigned segments, stretch them to fill [S,E].
    int aligned = 0;
    int i = 0;
    while (i < segs.length) {
      final r = assign[i];
      if (r == -1) { i++; continue; }
      int j = i;
      while (j + 1 < segs.length && assign[j + 1] == r) {
        j++;
      }
      final S = regions[r][0];
      final E = regions[r][1];
      // weights = text length (≈ speech duration share)
      final weights = <int>[];
      var totalW = 0;
      for (int k = i; k <= j; k++) {
        final w = segs[k].text.replaceAll(' ', '').length.clamp(1, 1000);
        weights.add(w);
        totalW += w;
      }
      var cursor = S.toDouble();
      final span = (E - S).toDouble();
      for (int k = i; k <= j; k++) {
        final frac = weights[k - i] / totalW;
        var a = cursor.round();
        var b = (cursor + span * frac).round();
        if (k == i) a = clampMs(S - leadMs);
        if (k == j) b = E + lingerMs;
        if (b < a + 120) b = a + 120;
        segs[k].startTime = Duration(milliseconds: clampMs(a));
        segs[k].endTime = Duration(milliseconds: clampMs(b));
        redistributeWordTimings(segs[k]);
        aligned++;
        cursor += span * frac;
      }
      i = j + 1;
    }

    // 4. Snap each subtitle's END to the nearest real silence boundary (speech-
    //    region end) within ±250ms so it disappears exactly when the voice stops
    //    instead of lingering into the next phrase or cutting off early.
    final rEnd = regions.map((r) => r[1]).toList();
    for (final s in segs) {
      final e = s.endTime.inMilliseconds;
      final ne = _nearest(rEnd, e);
      if ((ne - e).abs() <= 250) {
        final newEnd = ne + lingerMs;
        if (newEnd > s.startTime.inMilliseconds + 150) {
          s.endTime = Duration(milliseconds: clampMs(newEnd));
        }
      }
    }

    // 5. Keep order / no overlap.
    for (int k = 0; k < segs.length - 1; k++) {
      if (segs[k].endTime > segs[k + 1].startTime) {
        final mid = segs[k + 1].startTime;
        if (mid > segs[k].startTime + const Duration(milliseconds: 120)) {
          segs[k].endTime = mid;
        }
      }
    }
    return aligned;
  }

  /// Re-cut subtitles using the WORD timestamps' own gaps (robust even when the
  /// video has background music, where energy VAD fails). A new subtitle starts
  /// at every pause (gap >= [pauseMs]) or after [maxWords] words. Each subtitle's
  /// start/end come from the real word times (front + back of the phrase).
  static List<SubtitleSegment> resegmentByWordGaps(
    List<SubtitleSegment> segs, {
    int maxWords = 8,
    int pauseMs = 350,
  }) {
    if (segs.isEmpty) return segs;
    int clampMs(int v) => v < 0 ? 0 : v;
    const lead = 60;
    const linger = 120;

    final words = <String>[];
    final starts = <int>[];
    var globalEnd = 0;
    for (final s in segs) {
      globalEnd = globalEnd > s.endTime.inMilliseconds ? globalEnd : s.endTime.inMilliseconds;
      final sw = (s.words != null && s.words!.isNotEmpty)
          ? s.words!.where((w) => w.isNotEmpty).toList()
          : splitLaoHighlightUnits(s.text).where((w) => w.trim().isNotEmpty).toList();
      if (sw.isEmpty) continue;
      final hasT = s.wordTimings != null && s.wordTimings!.length == sw.length;
      final st = s.startTime.inMilliseconds;
      final dur = (s.endTime.inMilliseconds - st).clamp(1, 1 << 31);
      for (int i = 0; i < sw.length; i++) {
        words.add(sw[i]);
        starts.add(hasT ? s.wordTimings![i].inMilliseconds : st + dur * i ~/ sw.length);
      }
    }
    if (words.isEmpty) return segs;

    final out = <SubtitleSegment>[];
    int idc = 0;
    String mkId() => '${DateTime.now().microsecondsSinceEpoch}_${idc++}';
    var group = <int>[];

    void flush(int lastIdx) {
      if (group.isEmpty) return;
      final gw = [for (final k in group) words[k]];
      final gs = [for (final k in group) starts[k]];
      final segStart = clampMs(starts[group.first] - lead);
      final wordEnd = (lastIdx + 1 < words.length) ? starts[lastIdx + 1] : globalEnd;
      var segEnd = wordEnd + linger;
      if (segEnd < segStart + 200) segEnd = segStart + 200;
      out.add(SubtitleSegment(
        id: mkId(),
        text: joinWordsSmart(gw),
        startTime: Duration(milliseconds: segStart),
        endTime: Duration(milliseconds: segEnd),
        wordTimings: gs.map((m) => Duration(milliseconds: clampMs(m))).toList(),
        words: List.of(gw),
      ));
      group = [];
    }

    for (int i = 0; i < words.length; i++) {
      group.add(i);
      final isLast = i == words.length - 1;
      final gap = isLast ? 1 << 30 : starts[i + 1] - starts[i];
      if (group.length >= maxWords || gap >= pauseMs || isLast) {
        flush(i);
      }
    }

    for (int i = 0; i < out.length - 1; i++) {
      if (out[i].endTime > out[i + 1].startTime) {
        out[i].endTime = out[i + 1].startTime;
      }
    }
    return out;
  }

  /// Re-cut the subtitles so each one matches a real spoken phrase: take all the
  /// words (with their timings) and re-group them by detected speech [regions].
  /// Each region becomes one (or more, capped by [maxWords]) subtitle whose
  /// start/end equal the spoken phrase boundaries. Returns the new segment list.
  static List<SubtitleSegment> resegmentByRegions(
    List<SubtitleSegment> segs,
    List<List<int>> regions, {
    int maxWords = 8,
  }) {
    if (segs.isEmpty || regions.isEmpty) return segs;
    int clampMs(int v) => v < 0 ? 0 : v;
    const lead = 60;
    const linger = 120;

    // Flatten all words + absolute start times.
    final words = <String>[];
    final starts = <int>[];
    for (final s in segs) {
      final sw = (s.words != null && s.words!.isNotEmpty)
          ? s.words!.where((w) => w.isNotEmpty).toList()
          : splitLaoHighlightUnits(s.text).where((w) => w.trim().isNotEmpty).toList();
      if (sw.isEmpty) continue;
      final hasT = s.wordTimings != null && s.wordTimings!.length == sw.length;
      final st = s.startTime.inMilliseconds;
      final dur = (s.endTime.inMilliseconds - st).clamp(1, 1 << 31);
      for (int i = 0; i < sw.length; i++) {
        words.add(sw[i]);
        starts.add(hasT ? s.wordTimings![i].inMilliseconds : st + dur * i ~/ sw.length);
      }
    }
    if (words.isEmpty) return segs;

    // Calculate the global median shift between word starts and their nearest region starts.
    // This aligns the timelines globally first and prevents local feedback loops or runaway drift.
    final deltas = <int>[];
    for (final t in starts) {
      int nearestStart = regions[0][0];
      int minDist = (t - nearestStart).abs();
      for (final r in regions) {
        final d = (t - r[0]).abs();
        if (d < minDist) {
          minDist = d;
          nearestStart = r[0];
        }
      }
      if (minDist <= 3000) {
        deltas.add(nearestStart - t);
      }
    }
    int medianShift = 0;
    if (deltas.isNotEmpty) {
      final d = [...deltas]..sort();
      medianShift = d[d.length ~/ 2];
    }

    // Assign each word to its best matching actual speech region sequentially.
    // Monotonic matching guarantees that words remain in chronological order.
    final wr = List<int>.filled(words.length, 0);
    int lastRegion = 0;
    for (int i = 0; i < words.length; i++) {
      final t = starts[i];
      final correctedT = t + medianShift;
      int best = lastRegion;
      double bestD = 1e30;
      for (int r = lastRegion; r < regions.length; r++) {
        final rs = regions[r][0], re = regions[r][1];
        final d = (correctedT < rs) ? rs - correctedT : (correctedT > re ? correctedT - re : 0.0);
        if (d < bestD) {
          bestD = d.toDouble();
          best = r;
        }
      }
      wr[i] = best;
      lastRegion = best;
    }


    int charLen(String s) => s.replaceAll(' ', '').length.clamp(1, 1000);
    final out = <SubtitleSegment>[];
    int idc = 0;
    String mkId() => '${DateTime.now().microsecondsSinceEpoch}_${idc++}';

    int w = 0;
    while (w < words.length) {
      final r = wr[w];
      int e = w;
      while (e + 1 < words.length && wr[e + 1] == r) {
        e++;
      }
      final S = regions[r][0];
      final E = regions[r][1];
      final span = (E - S).clamp(1, 1 << 31).toDouble();
      var regTotal = 0;
      for (int k = w; k <= e; k++) regTotal += charLen(words[k]);
      if (regTotal <= 0) regTotal = 1;

      var cursor = S.toDouble();
      var idx = w;
      var firstChunk = true;
      while (idx <= e) {
        final cEnd = (idx + maxWords - 1).clamp(idx, e);
        final gw = words.sublist(idx, cEnd + 1);
        var weight = 0;
        for (final g in gw) weight += charLen(g);
        final frac = weight / regTotal;
        final lastChunk = cEnd == e;
        final a = firstChunk ? clampMs(S - lead) : cursor.round();
        final b = lastChunk ? E + linger : (cursor + span * frac).round();
        final segStart = clampMs(a);
        final segEnd = (b < segStart + 150) ? segStart + 150 : b;
        final n = gw.length;
        final wt = List.generate(n,
            (i) => Duration(milliseconds: segStart + ((segEnd - segStart) * i ~/ n)));
        out.add(SubtitleSegment(
          id: mkId(),
          text: joinWordsSmart(gw),
          startTime: Duration(milliseconds: segStart),
          endTime: Duration(milliseconds: segEnd),
          wordTimings: wt,
          words: List.of(gw),
        ));
        cursor += span * frac;
        idx = cEnd + 1;
        firstChunk = false;
      }
      w = e + 1;
    }

    out.sort((a, b) => a.startTime.compareTo(b.startTime));
    for (int i = 0; i < out.length - 1; i++) {
      if (out[i].endTime > out[i + 1].startTime) {
        out[i].endTime = out[i + 1].startTime;
      }
    }
    return out;
  }

  /// Snap every subtitle START and every karaoke WORD timing to the nearest
  /// REAL Whisper word onset ([onsets], acoustically exact) within [window] ms,
  /// keeping order monotonic. This corrects the within-region *proportional*
  /// estimates from [resegmentByRegions] so each subtitle — and each highlighted
  /// word — appears exactly when the voice starts, not on a character-count guess.
  /// Only snaps when a real onset is close (≤ window); otherwise the original
  /// estimate is kept. Mutates [segs] in place. Safe no-op without enough onsets.
  static void snapToOnsets(
    List<SubtitleSegment> segs,
    List<int> onsets, {
    int window = 220,
  }) {
    if (segs.isEmpty || onsets.length < 2) return;
    final o = [...onsets]..sort();
    final n = o.length;

    int nearest(int t) {
      if (t <= o.first) return o.first;
      if (t >= o.last) return o.last;
      int lo = 0, hi = n - 1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        if (o[mid] == t) return t;
        if (o[mid] < t) {
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      final a = o[hi], b = o[lo];
      return (t - a) <= (b - t) ? a : b;
    }

    int prevStart = 0;
    for (int si = 0; si < segs.length; si++) {
      final s = segs[si];
      int st = s.startTime.inMilliseconds;
      final ns = nearest(st);
      if ((ns - st).abs() <= window && ns >= prevStart) st = ns;
      if (st < prevStart) st = prevStart;

      if (s.wordTimings != null && s.wordTimings!.isNotEmpty) {
        final wt = <Duration>[];
        int wprev = st;
        for (int k = 0; k < s.wordTimings!.length; k++) {
          int t = k == 0 ? st : s.wordTimings![k].inMilliseconds;
          final nt = nearest(t);
          if ((nt - t).abs() <= window && nt >= wprev) t = nt;
          if (t < wprev) t = wprev;
          wt.add(Duration(milliseconds: t));
          wprev = t;
        }
        s.wordTimings = wt;
        st = wt.first.inMilliseconds;
      }

      int en = s.endTime.inMilliseconds;
      if (en < st + 150) en = st + 150;
      s.startTime = Duration(milliseconds: st < 0 ? 0 : st);
      s.endTime = Duration(milliseconds: en);
      prevStart = st;
    }

    // Keep order / no overlap.
    for (int i = 0; i < segs.length - 1; i++) {
      if (segs[i].endTime > segs[i + 1].startTime) {
        segs[i].endTime = segs[i + 1].startTime;
      }
    }
  }
}
