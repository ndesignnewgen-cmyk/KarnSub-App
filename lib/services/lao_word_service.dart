import 'package:flutter/services.dart';
import '../models/subtitle_style_model.dart';

/// Dictionary-based Lao/Thai word segmentation (groups syllables into real
/// words) via the native ICU BreakIterator. Used to give karaoke a proper
/// word-by-word sweep when a segment's stored units are missing or too coarse.
class LaoWordService {
  static const _channel = MethodChannel('com.anniekaydee.subtitle_app/audio');

  static Future<List<List<String>>> _segment(
      List<String> texts, String locale) async {
    if (texts.isEmpty) return [];
    try {
      final raw = await _channel.invokeMethod(
          'segmentWords', {'texts': texts, 'locale': locale});
      return (raw as List)
          .map((e) => (e as List)
              .map((w) => w.toString())
              .where((w) => w.trim().isNotEmpty)
              .toList())
          .toList();
    } catch (_) {
      return texts.map((t) => [t]).toList();
    }
  }

  /// Fill `words` (word-level) + evenly-spread `wordTimings` for any segment
  /// that doesn't already have ≥2 real word units. Segments that already carry
  /// proper word units (with their accurate timings) are left untouched.
  static Future<void> ensureWordUnits(
    List<SubtitleSegment> segs, {
    String locale = 'lo',
  }) async {
    final idx = <int>[];
    final texts = <String>[];
    for (int i = 0; i < segs.length; i++) {
      final w = segs[i].words;
      final count = w == null ? 0 : w.where((x) => x.trim().isNotEmpty).length;
      if (count < 2) {
        idx.add(i);
        texts.add(segs[i].text);
      }
    }
    if (texts.isEmpty) return;

    final lists = await _segment(texts, locale);
    if (lists.length != texts.length) return;
    for (int k = 0; k < idx.length; k++) {
      final w = lists[k];
      if (w.length < 2) continue; // still one unit → leave (render falls back)
      final s = segs[idx[k]];
      s.words = w;
      final a = s.startTime.inMilliseconds;
      final b = s.endTime.inMilliseconds;
      final span = (b - a).clamp(1, 1 << 31);
      s.wordTimings = List.generate(
          w.length, (j) => Duration(milliseconds: a + span * j ~/ w.length));
    }
  }

  /// Re-segment EVERY segment's existing word units into real dictionary words
  /// (fixes older projects whose words were cut mid-word, e.g. "ໂຫຼ"+"ດ"). The
  /// existing per-word start times are carried across so karaoke timing stays
  /// accurate, then the caller can re-cut subtitles on the corrected words.
  static Future<void> refineToRealWords(
    List<SubtitleSegment> segs, {
    String locale = 'lo',
  }) async {
    if (locale == 'en') return; // spaced script — Gemini units are already fine
    final segLocale = locale == 'th' ? 'th' : 'lo';

    final idx = <int>[];
    final texts = <String>[];
    for (int i = 0; i < segs.length; i++) {
      if (segs[i].text.trim().isEmpty) continue;
      idx.add(i);
      texts.add(segs[i].text);
    }
    if (texts.isEmpty) return;

    final lists = await _segment(texts, segLocale);
    if (lists.length != texts.length) return;
    for (int k = 0; k < idx.length; k++) {
      final realWords = lists[k].where((w) => w.trim().isNotEmpty).toList();
      if (realWords.length < 2) continue;
      final s = segs[idx[k]];
      final hasUnits =
          (s.words?.where((w) => w.trim().isNotEmpty).length ?? 0) >= 1;
      if (hasUnits) {
        _remapSegment(s, realWords); // carry the existing per-word timing
      } else {
        // No prior units → take ICU words and spread timing across the segment.
        final a = s.startTime.inMilliseconds;
        final b = s.endTime.inMilliseconds;
        final span = (b - a).clamp(1, 1 << 31);
        s.words = realWords;
        s.wordTimings = List.generate(realWords.length,
            (j) => Duration(milliseconds: a + span * j ~/ realWords.length));
      }
    }
  }

  /// Replace [s].words with [realWords], carrying each new word's start time
  /// from whichever existing unit covers its first character (positional walk).
  static void _remapSegment(SubtitleSegment s, List<String> realWords) {
    final units = s.words!.where((w) => w.trim().isNotEmpty).toList();
    if (units.isEmpty) return;
    final a = s.startTime.inMilliseconds;
    final b = s.endTime.inMilliseconds;
    final span = (b - a).clamp(1, 1 << 31);

    // Start time for each existing unit (use real timings when they line up).
    final List<int> unitStart =
        (s.wordTimings != null && s.wordTimings!.length == units.length)
            ? s.wordTimings!.map((d) => d.inMilliseconds).toList()
            : List.generate(units.length, (i) => a + span * i ~/ units.length);

    // Map every character (raw, no separators) back to its source unit.
    final charToUnit = <int>[];
    for (int u = 0; u < units.length; u++) {
      for (int c = 0; c < units[u].length; c++) {
        charToUnit.add(u);
      }
    }
    if (charToUnit.isEmpty) return;

    final newTimings = <Duration>[];
    int cursor = 0;
    for (final rw in realWords) {
      final ci = cursor.clamp(0, charToUnit.length - 1);
      final u = charToUnit[ci].clamp(0, unitStart.length - 1);
      newTimings.add(Duration(milliseconds: unitStart[u]));
      cursor += rw.length;
    }
    s.words = realWords;
    s.wordTimings = newTimings;
  }
}
