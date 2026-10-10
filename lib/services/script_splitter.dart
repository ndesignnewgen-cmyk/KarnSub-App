import 'lao_word_service.dart';

/// Splits a pasted script (lyrics, a written script…) into subtitle lines for
/// Tap Sync:
///   1. new lines,
///   2. sentence punctuation (. ? ! … ໆ ฯ + a space) and long runs of spaces,
///   3. lines still longer than [maxChars] are wrapped at WORD boundaries.
///
/// Lao/Thai text has no spaces between words, so step 3 needs a word
/// segmenter (ICU via [LaoWordService] in the app, a fake in tests). It never
/// cuts inside a word; a single word longer than [maxChars] stays whole.
class ScriptSplitter {
  ScriptSplitter._();

  // Punctuation only ends a sentence when whitespace follows — keeps "25.000"
  // and "ໄວໆນີ້" intact.
  static final _sentenceEnd = RegExp(r'(?<=[.?!…ໆฯ。？！])\s+');
  static final _bigGap = RegExp(r'\s{3,}|\t+');

  /// Steps 1–2 (sync, no segmenter needed).
  static List<String> roughChunks(String text) {
    final out = <String>[];
    for (final line in text.replaceAll('\r\n', '\n').split('\n')) {
      for (final part in line.split(_bigGap)) {
        for (final s in part.split(_sentenceEnd)) {
          final t = s.trim();
          if (t.isNotEmpty) out.add(t);
        }
      }
    }
    return out;
  }

  /// Visible character count (combining Lao/Thai vowel & tone marks don't add
  /// width, so they're not counted).
  static int visibleLength(String s) {
    var n = 0;
    for (final r in s.runes) {
      if (_isCombining(r) || r == 0x20) continue;
      n++;
    }
    return n;
  }

  static bool _isCombining(int r) =>
      // Lao
      r == 0x0EB1 ||
      (r >= 0x0EB4 && r <= 0x0EBC) ||
      (r >= 0x0EC8 && r <= 0x0ECE) ||
      // Thai
      r == 0x0E31 ||
      (r >= 0x0E34 && r <= 0x0E3A) ||
      (r >= 0x0E47 && r <= 0x0E4E);

  /// Step 3: greedily pack [words] into lines of at most [maxChars] visible
  /// characters. Words are joined as-is (spaces inside a word unit are kept).
  /// A tiny last line (≤ 3 chars) is avoided by pulling words down from the
  /// line before it, or — if that can't fit — by merging when the result is
  /// at most 3 chars over the limit.
  static List<String> wrapWords(List<String> words, int maxChars) {
    final lines = <List<String>>[];
    var cur = <String>[];
    var curLen = 0;
    for (final w in words) {
      final wl = visibleLength(w);
      if (curLen > 0 && curLen + wl > maxChars) {
        lines.add(cur);
        cur = [];
        curLen = 0;
      }
      cur.add(w);
      curLen += wl;
    }
    if (cur.isNotEmpty) lines.add(cur);

    int len(List<String> l) => visibleLength(l.join());
    if (lines.length >= 2 && len(lines.last) <= 3) {
      final prev = lines[lines.length - 2];
      final last = lines.last;
      while (prev.length >= 2 &&
          len(last) <= 3 &&
          len([prev.last, ...last]) <= maxChars) {
        last.insert(0, prev.removeLast());
      }
      if (len(last) <= 3 && len(prev) + len(last) <= maxChars + 3) {
        prev.addAll(last);
        lines.removeLast();
      }
    }
    return lines
        .map((l) => l.join().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Full split. [segmenter] turns texts into word lists (defaults to the
  /// native ICU segmenter).
  static Future<List<String>> split(
    String text, {
    int maxChars = 28,
    String locale = 'lo',
    Future<List<List<String>>> Function(List<String> texts, String locale)?
        segmenter,
  }) async {
    final seg = segmenter ?? LaoWordService.segment;
    final chunks = roughChunks(text);
    final longIdx = <int>[];
    for (int i = 0; i < chunks.length; i++) {
      if (visibleLength(chunks[i]) > maxChars) longIdx.add(i);
    }
    if (longIdx.isEmpty) return chunks;
    final words = await seg(longIdx.map((i) => chunks[i]).toList(), locale);
    final out = <String>[];
    var k = 0;
    for (int i = 0; i < chunks.length; i++) {
      if (k < longIdx.length && longIdx[k] == i) {
        final w = k < words.length ? words[k] : [chunks[i]];
        out.addAll(wrapWords(_keepSpaces(chunks[i], w), maxChars));
        k++;
      } else {
        out.add(chunks[i]);
      }
    }
    return out;
  }

  /// Segmenters drop whitespace; re-attach the original spaces to the word
  /// before them so "ສະບາຍດີ ທຸກຄົນ" doesn't become "ສະບາຍດີທຸກຄົນ".
  static List<String> _keepSpaces(String original, List<String> words) {
    final out = <String>[];
    var pos = 0;
    for (final w in words) {
      final at = original.indexOf(w, pos);
      if (at < 0) {
        out.add(w);
        continue;
      }
      var end = at + w.length;
      while (end < original.length && original[end] == ' ') {
        end++;
      }
      out.add(original.substring(at, end));
      pos = end;
    }
    return out;
  }

  /// Merge line [i] with the one after it (review screen).
  static List<String> mergeWithNext(List<String> lines, int i) {
    if (i < 0 || i + 1 >= lines.length) return lines;
    final a = lines[i];
    final b = lines[i + 1];
    final needsSpace = RegExp(r'[A-Za-z0-9]$').hasMatch(a) &&
        RegExp(r'^[A-Za-z0-9]').hasMatch(b);
    return [
      ...lines.sublist(0, i),
      needsSpace ? '$a $b' : '$a$b',
      ...lines.sublist(i + 2),
    ];
  }

  /// Split line [i] at character offset [at] (review screen).
  static List<String> splitAt(List<String> lines, int i, int at) {
    if (i < 0 || i >= lines.length) return lines;
    final s = lines[i];
    if (at <= 0 || at >= s.length) return lines;
    final a = s.substring(0, at).trim();
    final b = s.substring(at).trim();
    if (a.isEmpty || b.isEmpty) return lines;
    return [...lines.sublist(0, i), a, b, ...lines.sublist(i + 1)];
  }
}
