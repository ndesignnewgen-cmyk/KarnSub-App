import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/subtitle_style_model.dart';
import 'audio_sync_service.dart';
import 'audio_preprocess.dart';

class GeminiSpeechException implements Exception {
  final String message;
  GeminiSpeechException(this.message);
  @override
  String toString() => message;
}

class GeminiSpeechService {
  static const _channel = MethodChannel('com.anniekaydee.subtitle_app/audio');

  // Primary model = gemini-3.5-flash: BEST Lao spelling/accuracy. It can return
  // 503 when overloaded, but that's transient — so we retry it several times
  // first, and only switch to the more-available (but lower Lao quality)
  // fallback as a LAST resort so transcription never hard-fails.
  static const _primaryModel = 'gemini-3.5-flash';
  static const _fallbackModel = 'gemini-2.5-flash';
  static String _endpointFor(String model) =>
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';
  static final _endpoint = _endpointFor(_primaryModel);

  // Long audio is split into chunks of ~this length so Gemini's timestamps stay
  // accurate (its drift grows with duration). Each chunk is cut at a silence and
  // its words are offset by the chunk's exact start time.
  // Bigger chunks = far fewer Gemini requests (free tier is only ~20/day for
  // 3.5). Timing is corrected afterwards by Groq/Whisper forced-align or energy
  // VAD, so Gemini only needs accurate TEXT here — larger chunks even give it
  // more context. ~30s keeps a 5-min video well under the daily request cap
  // while limiting Gemini's own timestamp drift before alignment.
  static const int _chunkTargetMs = 30000;

  final String apiKey;
  final _uuid = const Uuid();

  GeminiSpeechService({required this.apiKey});

  Future<List<SubtitleSegment>> transcribe(
    String videoPath, {
    String language = 'lo',
    WordSplit wordSplit = WordSplit.none,
    String hint = '',
    void Function(String)? onProgress,
  }) async {
    onProgress?.call('ດຶງສຽງຈາກວິດີໂອ...');
    final tempDir = await getTemporaryDirectory();
    final wavPath =
        '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav';

    try {
      await _channel.invokeMethod('extractAudio', {
        'videoPath': videoPath,
        'outputPath': wavPath,
      });
    } on PlatformException catch (e) {
      throw GeminiSpeechException('ດຶງສຽງບໍ່ສໍາເລັດ: ${e.message}');
    }

    final wavFile = File(wavPath);
    if (!wavFile.existsSync()) {
      throw GeminiSpeechException('ໄຟລ໌ audio ສ້າງບໍ່ສໍາເລັດ');
    }
    final rawBytes = await wavFile.readAsBytes();
    wavFile.deleteSync();
    if (rawBytes.length <= 44) return [];
    // Clean up the recognizer's copy: high-pass + loudness normalize.
    final wavBytes = AudioPreprocess.processBytes(rawBytes);

    // Parse the WAV header → bytes-per-millisecond (extractAudio outputs
    // 16 kHz mono 16-bit, but read the header to stay correct if that changes).
    int le16(int o) => wavBytes[o] | (wavBytes[o + 1] << 8);
    int le32(int o) =>
        wavBytes[o] |
        (wavBytes[o + 1] << 8) |
        (wavBytes[o + 2] << 16) |
        (wavBytes[o + 3] << 24);
    final channels = le16(22).clamp(1, 2);
    final sampleRate = le32(24).clamp(8000, 48000);
    final bits = le16(34).clamp(8, 32);
    final bytesPerMs =
        (sampleRate * channels * (bits ~/ 8) / 1000).round().clamp(1, 1 << 30);
    final totalMs = (wavBytes.length - 44) ~/ bytesPerMs;

    final langName = switch (language) {
      'lo' => 'ພາສາລາວ',
      'th' => 'ພາສາໄທ',
      'en' => 'English',
      _ => 'ພາສາລາວ',
    };
    final prompt = _buildPrompt(langName, hint);

    // Decide chunk boundaries (single chunk for short clips).
    List<List<int>> chunks;
    if (totalMs <= _chunkTargetMs + 20000) {
      chunks = [
        [0, totalMs]
      ];
    } else {
      List<List<int>> regions = const [];
      try {
        regions = await AudioSyncService.detectSpeechRegions(videoPath);
      } catch (_) {}
      chunks = _planChunks(totalMs, _chunkTargetMs, regions);
    }

    final allWords = <({int startMs, int endMs, String text})>[];
    
    // Process in parallel batches of 2 to avoid overwhelming free tier rate limits
    final batchSize = 2;
    for (int i = 0; i < chunks.length; i += batchSize) {
      final batch = chunks.sublist(i, (i + batchSize < chunks.length) ? i + batchSize : chunks.length);
      
      onProgress?.call('Gemini ກຳລັງຖອດສຽງຂະໜານ (${i + 1}-${i + batch.length}/${chunks.length})...');
      
      final futures = batch.map((chunk) async {
        final cs = chunk[0];
        final ce = chunk[1];
        if (ce - cs < 50) return <({int startMs, int endMs, String text})>[];
        
        final chunkWav = _sliceWav(wavBytes, cs, ce, bytesPerMs);
        final data = await _callGemini(chunkWav, prompt, onProgress);
        
        final words = <({int startMs, int endMs, String text})>[];
        for (final w in _parseWordEntries(data)) {
          words.add((startMs: w.startMs + cs, endMs: w.endMs + cs, text: w.text));
        }
        return words;
      });
      
      final results = await Future.wait(futures);
      for (final res in results) {
        allWords.addAll(res);
      }
    }

    if (allWords.isEmpty) return [];
    allWords.sort((a, b) => a.startMs.compareTo(b.startMs));

    // Gemini often splits Lao/Thai text mid-word (no spaces in the script), so
    // re-segment the whole transcript into REAL words with the native ICU
    // dictionary before grouping. This stops subtitles cutting in the middle of
    // a word (e.g. "ກຳ"|"ລັງ") — they now break only on true word boundaries.
    onProgress?.call('ກໍາລັງຈັດຄຳ...');
    final realWords = await _refineToRealWords(allWords, language);

    onProgress?.call('ກໍາລັງສ້າງ Subtitle...');
    return _groupWords(realWords, wordSplit, language);
  }

  /// Re-segment Gemini's (often sub-word) entries into real dictionary words via
  /// the native ICU BreakIterator, carrying timing across: each real word takes
  /// its start from the first source entry it covers and its end from the last.
  /// Only applied to Lao/Thai (space-less scripts); other languages pass through.
  Future<List<({int startMs, int endMs, String text})>> _refineToRealWords(
    List<({int startMs, int endMs, String text})> entries,
    String language,
  ) async {
    if (entries.length < 2) return entries;
    // 'lo', 'th', and Auto ('') are space-less → segment as Lao by default.
    if (language == 'en') return entries;
    final segLocale = language == 'th' ? 'th' : 'lo';

    // Concatenate entry texts and remember each char's source entry. Insert a
    // space at English/number boundaries (needSpaceBetweenWords) so ICU keeps
    // separate Latin words apart — otherwise joining e.g. ["Media","All","Easy"]
    // with no separator becomes "MediaAllEasy" which ICU can't split back.
    final sb = StringBuffer();
    final charEntry = <int>[]; // source-entry index for each char of `concat`
    String? prevText;
    for (int i = 0; i < entries.length; i++) {
      final t = entries[i].text;
      if (prevText != null && needSpaceBetweenWords(prevText, t)) {
        sb.write(' ');
        charEntry.add(i - 1); // the boundary space belongs to the previous entry
      }
      for (int c = 0; c < t.length; c++) {
        charEntry.add(i);
      }
      sb.write(t);
      prevText = t;
    }
    final concat = sb.toString();
    if (concat.isEmpty) return entries;

    List<String> words;
    try {
      final raw = await _channel.invokeMethod(
        'segmentWords',
        {'texts': [concat], 'locale': segLocale},
      );
      final lists = (raw as List)
          .map((e) => (e as List).map((w) => w.toString()).toList())
          .toList();
      words = lists.isNotEmpty ? lists.first : <String>[];
    } catch (_) {
      return entries; // ICU unavailable → keep Gemini's units
    }
    words = words.where((w) => w.trim().isNotEmpty).toList();
    if (words.length < 2) return entries;

    // Walk each ICU word over `concat` (indexOf resyncs past any dropped chars)
    // and map it back to the timing of the source entries it spans.
    final out = <({int startMs, int endMs, String text})>[];
    int cursor = 0;
    for (final w in words) {
      int at = concat.indexOf(w, cursor);
      if (at < 0) at = cursor.clamp(0, concat.length - 1);
      final startChar = at.clamp(0, charEntry.length - 1);
      final endChar = (at + w.length - 1).clamp(0, charEntry.length - 1);
      final firstEntry = charEntry[startChar];
      final lastEntry = charEntry[endChar];
      out.add((
        startMs: entries[firstEntry].startMs,
        endMs: entries[lastEntry].endMs,
        text: w,
      ));
      cursor = at + w.length;
    }
    return out.isEmpty ? entries : out;
  }

  String _buildPrompt(String langName, [String hint = '']) {
    final h = hint.trim();
    final glossary = h.isEmpty
        ? ''
        : '\n\nຄຳສະເພາະ/ຊື່ທີ່ອາດປະກົດໃນສຽງ (ສະກົດໃຫ້ຖືກຕາມນີ້ເມື່ອໄດ້ຍິນ): $h\n';
    return glossary +
      '''ຖອດສຽງ audio ນີ້ເປັນ $langName ພ້ອມ timestamp ລະດັບຄຳ (word-level) ໃຫ້ຊັດ ແລະ ຕົງກັບສຽງທີ່ສຸດ

ກົດການແບ່ງຄຳ (ສຳຄັນທີ່ສຸດ):
- ແຕ່ລະ entry = ໜຶ່ງ "ຄຳເຕັມທີ່ມີຄວາມໝາຍ" ເທົ່ານັ້ນ
- ຫ້າມຕັດກາງຄຳເດັດຂາດ! ຕົວຢ່າງ "ໂທລະສັບ" = 1 entry (ຫ້າມແຍກເປັນ "ໂທ"+"ລະສັບ"), "ໂຮງຮຽນ" = 1 entry, "ຂອບໃຈ" = 1 entry
- ສຳລັບ ພາສາລາວ/ໄທ: ໃຫ້ "ລວມພະຍາງ" ເຂົ້າເປັນຄຳທີ່ມີຄວາມໝາຍ — ຢ່າແຍກເປັນພະຍາງດ່ຽວ

ກົດ timestamp (ສຳຄັນຫຼາຍ):
- start = ວິນາທີທີ່ໄດ້ຍິນສຽງຄຳນັ້ນ "ເລີ່ມ" ແທ້ໆ, end = ວິນາທີທີ່ຄຳນັ້ນ "ຈົບ"
- ໃຫ້ລະອຽດເຖິງ 2 ຕຳແໜ່ງທົດສະນິຍົມ (ເຊັ່ນ 1.24)
- ຟັງໃຫ້ດີ ຢ່າໃຫ້ timestamp ຊ້າ ຫຼື ໄວ ກວ່າສຽງຈິງ
- start ຂອງຄຳຕໍ່ໄປ ຕ້ອງ >= end ຂອງຄຳກ່ອນໜ້າ

ກົດ text:
- ຕັດ filler ອອກ (ເອີ່, ອາ, ...)
- ສະກົດ $langName ໃຫ້ຖືກຕ້ອງ; ຖ້າມີ English ໃຫ້ສະກົດຖືກ
- ຕົວເລກ ໃຫ້ຂຽນເປັນ "ໂຕເລກ" (digits) ສະເໝີ ເຊັ່ນ 3, 14, 2024, 1500 — ຫ້າມຂຽນເປັນຕົວໜັງສື
- ຄຳ English ແລະ ຕົວເລກ ໃຫ້ເປັນ entry ແຍກຕ່າງຫາກ (ຫ້າມຕິດກັບຄຳລາວໃນ entry ດຽວກັນ).
  ຕົວຢ່າງ: "ໃຊ້ WhatsApp" = 2 entries ["ໃຊ້","WhatsApp"]; "ປີ 2024" = 2 entries ["ປີ","2024"]

ສົ່ງ JSON array ເທົ່ານັ້ນ (ບໍ່ໃສ່ text ອື່ນ):
[{"start":0.00,"end":0.50,"text":"ຄຳເຕັມ"}]''';
  }

  /// Plan chunk ranges [startMs, endMs]. Cuts at silence midpoints between
  /// speech regions whenever a chunk would exceed [target]; falls back to fixed
  /// cuts when no regions are available.
  List<List<int>> _planChunks(int totalMs, int target, List<List<int>> regions) {
    final out = <List<int>>[];
    if (regions.length < 2) {
      int s = 0;
      while (s < totalMs) {
        final e = (s + target) > totalMs ? totalMs : (s + target);
        out.add([s, e]);
        s = e;
      }
      return out.isEmpty ? [[0, totalMs]] : out;
    }
    int chunkStart = 0;
    for (int i = 0; i < regions.length - 1; i++) {
      final gapMid = (regions[i][1] + regions[i + 1][0]) ~/ 2;
      if (gapMid - chunkStart >= target) {
        out.add([chunkStart, gapMid]);
        chunkStart = gapMid;
      }
    }
    out.add([chunkStart, totalMs]);
    return out;
  }

  /// Extract a [startMs, endMs] slice of a 16-bit PCM WAV as a standalone WAV.
  Uint8List _sliceWav(Uint8List wav, int startMs, int endMs, int bytesPerMs) {
    int byteStart = 44 + startMs * bytesPerMs;
    int byteEnd = 44 + endMs * bytesPerMs;
    if (byteStart < 44) byteStart = 44;
    if (byteEnd > wav.length) byteEnd = wav.length;
    if (byteEnd < byteStart) byteEnd = byteStart;
    final pcm = wav.sublist(byteStart, byteEnd);
    final out = Uint8List(44 + pcm.length);
    out.setRange(0, 44, wav.sublist(0, 44));
    out.setRange(44, 44 + pcm.length, pcm);
    void w32(int off, int v) {
      out[off] = v & 0xFF;
      out[off + 1] = (v >> 8) & 0xFF;
      out[off + 2] = (v >> 16) & 0xFF;
      out[off + 3] = (v >> 24) & 0xFF;
    }
    w32(4, pcm.length + 36); // RIFF chunk size
    w32(40, pcm.length); // data chunk size
    return out;
  }

  /// One Gemini transcription call for a WAV buffer, with retry/backoff.
  Future<Map<String, dynamic>> _callGemini(
    Uint8List wavBytes,
    String prompt,
    void Function(String)? onProgress,
  ) async {
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'inline_data': {
                'mime_type': 'audio/wav',
                'data': base64Encode(wavBytes),
              }
            },
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {'temperature': 0.1},
    });

    const maxAttempts = 6; // retry the primary (best-Lao) model several times
    String responseBody = '';
    int statusCode = 0;
    // Once the primary model returns 429 (daily free-tier quota = 20/day for
    // 3.5), retrying it is pointless — switch to the fallback model, which has a
    // SEPARATE, larger free quota. So the app keeps working after 3.5 runs out.
    bool quotaFallback = false;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final useFallback = quotaFallback || attempt == maxAttempts;
      final activeModel = useFallback ? _fallbackModel : _primaryModel;
      final uri = Uri.parse('${_endpointFor(activeModel)}?key=$apiKey');

      if (attempt >= 2) {
        onProgress?.call(useFallback
            ? 'ສະລັບໄປໃຊ້ Gemini ຮຸ່ນສຳຮອງ (ຄັ້ງສຸດທ້າຍ)...'
            : '$activeModel ບໍ່ຫວ່າງ, ກຳລັງລອງໃໝ່ ($attempt/$maxAttempts)...');
      }

      try {
        final httpClient = HttpClient();
        httpClient.connectionTimeout = const Duration(seconds: 15);
        final request = await httpClient.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.write(body);
        final response =
            await request.close().timeout(const Duration(seconds: 45));
        responseBody = await response.transform(utf8.decoder).join();
        statusCode = response.statusCode;
        httpClient.close();
      } catch (e) {
        if (attempt >= maxAttempts) {
          throw GeminiSpeechException(
              'ເຊື່ອມຕໍ່ Gemini ບໍ່ໄດ້ (ອາດເນັດຊ້າ ຫຼື ເຊີເວີລົ່ມ) — ລອງໃໝ່ອີກຄັ້ງ');
        }
        onProgress?.call('ເນັດຊ້າກຳລັງລອງໃໝ່ ($attempt/$maxAttempts)...');
        await Future.delayed(Duration(seconds: 4 * attempt));
        continue;
      }

      if (statusCode == 200) {
        return jsonDecode(responseBody) as Map<String, dynamic>;
      }

      // 429 on the PRIMARY model = its daily quota is gone → switch to the
      // fallback model immediately (separate quota), don't waste time waiting.
      if (statusCode == 429 && !useFallback && !quotaFallback) {
        quotaFallback = true;
        onProgress?.call('Gemini 3.5 ໝົດໂຄຕ້າ — ສະຫຼັບໄປ Gemini 2.5...');
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }

      final retryable =
          statusCode == 503 || statusCode == 429 || statusCode == 500;
      if (retryable && attempt < maxAttempts) {
        final delaySecs = 3 * attempt;
        onProgress?.call(statusCode == 429
            ? 'Gemini ໂຄຕ້າເຕັມ (429) — ລໍຖ້າ $delaySecs ວິ ($attempt/$maxAttempts)...'
            : 'Gemini ຄົນໃຊ້ຫຼາຍ ($statusCode) — ລໍຖ້າ $delaySecs ວິ ($attempt/$maxAttempts)...');
        await Future.delayed(Duration(seconds: delaySecs));
        continue;
      }

      String msg;
      try {
        final err = jsonDecode(responseBody);
        msg = err['error']?['message'] ?? responseBody;
      } catch (_) {
        msg = responseBody;
      }
      if (statusCode == 429) {
        throw GeminiSpeechException(
            'Gemini ໝົດໂຄຕ້າຟຣີມື້ນີ້ (free tier 20 ຄັ້ງ/ມື້). ແນະນຳ: ໃສ່ Groq API key (ຟຣີ, ໂຄຕ້າສູງກວ່າ) ໃນ Settings ສຳລັບຖອດສຽງ — ຫຼື ລໍມື້ໃໝ່');
      }
      if (statusCode == 503) {
        throw GeminiSpeechException(
            'Gemini ກຳລັງມີຄົນໃຊ້ຫຼາຍ (503) — ລອງໃໝ່ໃນອີກ 1-2 ນາທີ');
      }
      throw GeminiSpeechException('Gemini $statusCode: $msg');
    }
    throw GeminiSpeechException('Gemini ບໍ່ຕອບສະໜອງ');
  }

  /// Join word units into natural display text (Lao/Thai tight, Latin spaced).
  String _joinWords(List<String> words, String language) => joinWordsSmart(words);

  List<({int startMs, int endMs, String text})> _parseWordEntries(
      Map<String, dynamic> data) {
    try {
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return [];
      final parts =
          (candidates[0]['content'] as Map<String, dynamic>?)?['parts']
              as List<dynamic>?;
      if (parts == null || parts.isEmpty) return [];

      var raw = (parts[0]['text'] as String? ?? '').trim();
      raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();

      final s = raw.indexOf('[');
      final e = raw.lastIndexOf(']');
      if (s == -1 || e == -1) return [];

      final list = jsonDecode(raw.substring(s, e + 1)) as List<dynamic>;
      return list
          .map((item) {
            final m = item as Map<String, dynamic>;
            final startMs = ((m['start'] as num? ?? 0) * 1000).toInt();
            final endMs = ((m['end'] as num? ?? 0) * 1000).toInt();
            final text = (m['text'] as String? ?? '').trim();
            return (
              startMs: startMs,
              endMs: endMs > startMs ? endMs : startMs + 300,
              text: text,
            );
          })
          .where((w) => w.text.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<SubtitleSegment> _groupWords(
    List<({int startMs, int endMs, String text})> words,
    WordSplit split,
    String language,
  ) {
    if (words.isEmpty) return [];
    final wordsPerGroup = switch (split) {
      WordSplit.one => 1,
      WordSplit.two => 2,
      WordSplit.three => 3,
      WordSplit.four => 4,
      WordSplit.six => 6,
      WordSplit.eight => 8,
      WordSplit.none => 0,
    };
    final result = <SubtitleSegment>[];
    if (wordsPerGroup > 0) {
      for (int i = 0; i < words.length; i += wordsPerGroup) {
        final chunk = words.sublist(i, (i + wordsPerGroup).clamp(0, words.length));
        result.add(_makeSegment(chunk, language));
      }
    } else {
      // Auto: shorter groups feel better-synced — break on pauses >= 400 ms or max 4 words
      const maxW = 4;
      const pauseMs = 400;
      var group = <({int startMs, int endMs, String text})>[];
      for (int i = 0; i < words.length; i++) {
        group.add(words[i]);
        final isLast = i == words.length - 1;
        final gap = isLast ? 9999 : words[i + 1].startMs - words[i].endMs;
        if (group.length >= maxW || gap >= pauseMs || isLast) {
          result.add(_makeSegment(group, language));
          group = [];
        }
      }
    }
    // Prevent overlap introduced by lead-in / linger padding:
    // a segment must not stay on screen past the next one's start.
    for (int i = 0; i < result.length - 1; i++) {
      if (result[i].endTime > result[i + 1].startTime) {
        result[i].endTime = result[i + 1].startTime;
      }
    }
    return result;
  }

  // Sync tuning: show the subtitle slightly BEFORE the word is spoken and let
  // it linger a moment after, which feels better-synced to viewers.
  static const int _leadInMs = 150;
  static const int _lingerMs = 150;

  SubtitleSegment _makeSegment(
      List<({int startMs, int endMs, String text})> chunk, String language) {
    final startMs = (chunk.first.startMs - _leadInMs).clamp(0, 1 << 31);
    final wordList = chunk.map((w) => w.text).toList();
    return SubtitleSegment(
      id: _uuid.v4(),
      text: _joinWords(wordList, language),
      startTime: Duration(milliseconds: startMs),
      endTime: Duration(milliseconds: chunk.last.endMs + _lingerMs),
      wordTimings: chunk.map((w) => Duration(milliseconds: w.startMs)).toList(),
      words: wordList,
    );
  }

  /// Auto ✨: ask Gemini to pick a fitting emoji and the single most important
  /// ("punch") word per subtitle line, then fill [segs].emoji / [segs].emphasis
  /// in place. Best-effort — leaves segments untouched on any failure.
  Future<void> autoEmojiHighlight(List<SubtitleSegment> segs) async {
    if (segs.isEmpty) return;
    const chunkSize = 80;
    bool hasAnySuccess = false;
    bool useFallbackModel = false; // switch to 2.5 once 3.5 hits its daily quota
    bool quotaHit = false;
    String lastErrorMessage = '';

    for (int start = 0; start < segs.length; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, segs.length);
      final slice = segs.sublist(start, end);

      // Build input: each line's word units (so Gemini returns a valid index).
      final input = <Map<String, dynamic>>[];
      for (int k = 0; k < slice.length; k++) {
        var words = (slice[k].words != null && slice[k].words!.isNotEmpty)
            ? slice[k].words!.where((w) => w.trim().isNotEmpty).toList()
            : splitLaoHighlightUnits(slice[k].text).where((w) => w.trim().isNotEmpty).toList();
        if (words.isEmpty) {
          words = [slice[k].text];
        }
        input.add({'i': k, 'words': words});
      }

      final prompt =
          'ສຳລັບແຕ່ລະ subtitle (ພາສາລາວ) ຂ້າງລຸ່ມ ໃຫ້ເລືອກ:\n'
          '1. "emoji" = emoji 1 ໂຕ ທີ່ເໝາະກັບຄວາມໝາຍຂອງປະໂຫຍກ (ຖ້າບໍ່ມີທີ່ເໝາະ ໃຫ້ "")\n'
          '2. "keyword" = index (ເລີ່ມ 0) ຂອງ "ຄຳເດັດ/ສຳคัญທີ່ສຸດ" 1 ຄຳ ໃນ words ເພື່ອເນັ້ນ '
          '(ຖ້າບໍ່ມີຄຳເດັດ ໃຫ້ -1)\n'
          'ສົ່ງ JSON array ລຽງຕາມ index "i" ເທົ່ານັ້ນ ບໍ່ໃສ່ text ອື່ນ:\n'
          '[{"i":0,"emoji":"💰","keyword":2}, ...]\n\n'
          'Input:\n${jsonEncode(input)}';

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.4,
          'responseMimeType': 'application/json'
        },
      });

      try {
        final model = useFallbackModel ? _fallbackModel : _primaryModel;
        final uri = Uri.parse('${_endpointFor(model)}?key=$apiKey');
        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        ).timeout(const Duration(minutes: 2));

        // 429 on primary = daily quota gone → retry this chunk on the fallback
        // model (separate quota) instead of failing.
        if (response.statusCode == 429 && !useFallbackModel) {
          useFallbackModel = true;
          quotaHit = true;
          start -= chunkSize; // redo this same chunk with the fallback model
          continue;
        }
        if (response.statusCode != 200) {
          if (response.statusCode == 429) quotaHit = true;
          lastErrorMessage = 'API error status ${response.statusCode}: ${response.body}';
          continue;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final parts = (data['candidates']?[0]?['content']
            as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
        if (parts == null || parts.isEmpty) {
          lastErrorMessage = 'Invalid API response candidates/parts';
          continue;
        }
        var raw = (parts[0]['text'] as String? ?? '').trim();
        raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();
        final s = raw.indexOf('[');
        final e = raw.lastIndexOf(']');
        if (s == -1 || e == -1) {
          lastErrorMessage = 'Could not parse JSON array from response';
          continue;
        }
        final list = jsonDecode(raw.substring(s, e + 1)) as List<dynamic>;

        for (final item in list) {
          final m = item as Map<String, dynamic>;
          final i = (m['i'] as num?)?.toInt() ?? -1;
          if (i < 0 || i >= slice.length) continue;
          final seg = slice[i];
          final wordCount = input[i]['words'].length as int;
          final emoji = (m['emoji'] as String? ?? '').trim();
          final kw = (m['keyword'] as num?)?.toInt() ?? -1;
          seg.emoji = emoji.isEmpty ? null : emoji;
          seg.emphasis = (kw >= 0 && kw < wordCount) ? [kw] : null;
        }
        hasAnySuccess = true;
      } catch (e) {
        lastErrorMessage = e.toString();
        // best-effort; skip this chunk on error
      }
    }

    if (!hasAnySuccess && segs.isNotEmpty) {
      if (quotaHit) {
        throw GeminiSpeechException(
            'Auto ✨ ໝົດໂຄຕ້າ Gemini ຟຣີມື້ນີ້ (20 ຄັ້ງ/ມື້) — ໃສ່ Groq key (ຟຣີ) ໃນ Settings ຫຼື ລໍມື້ໃໝ່');
      }
      throw GeminiSpeechException(
        lastErrorMessage.isNotEmpty
          ? 'Auto ✨ ບໍ່ສຳເລັດ: $lastErrorMessage'
          : 'Auto ✨ ບໍ່ສຳເລັດ — ລອງໃໝ່',
      );
    }
  }

  /// Write a catchy TikTok/Reels caption + hashtags (Lao) from the subtitle
  /// transcript so the creator can post fast. Returns ('', []) on failure.
  Future<({String caption, List<String> hashtags})> generateCaption(
    String transcript,
  ) async {
    final trimmed = transcript.trim();
    if (trimmed.isEmpty) return (caption: '', hashtags: <String>[]);
    final clip = trimmed.length > 2000 ? trimmed.substring(0, 2000) : trimmed;

    final prompt =
        'ນີ້ຄືเนื้อหา (transcript) ຂອງວິດີໂอสั้น TikTok/Reels:\n"$clip"\n\n'
        'ຂຽນເປັນ JSON:\n'
        '1. "caption" = ແคปชั่นภาษาลาว ดึงดูด สั้นกระชับ มี hook ให้คนหยุดดู '
        '(1-2 ประโยค) ใส่ emoji เล็กน้อย\n'
        '2. "hashtags" = แฮชแท็ก 6-10 อัน (ลาว+อังกฤษผสม ที่เกี่ยวข้องกับเนื้อหา '
        'รวม #fyp และแท็กลาวยอดนิยม)\n'
        'ສ່ง JSON ເທົ່ານັ້ນ ບໍ່ໃສ่ text อื่น:\n'
        '{"caption":"...","hashtags":["#...","#..."]}';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {'temperature': 0.8},
    });

    try {
      final uri = Uri.parse('$_endpoint?key=$apiKey');
      http.Response response;
      try {
        response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        ).timeout(const Duration(minutes: 2));
      } catch (_) {
        return (caption: '', hashtags: <String>[]);
      }
      if (response.statusCode != 200) {
        return (caption: '', hashtags: <String>[]);
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final parts = (data['candidates']?[0]?['content']
          as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) {
        return (caption: '', hashtags: <String>[]);
      }
      var raw = (parts[0]['text'] as String? ?? '').trim();
      raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final s = raw.indexOf('{');
      final e = raw.lastIndexOf('}');
      if (s == -1 || e == -1) return (caption: '', hashtags: <String>[]);
      final m = jsonDecode(raw.substring(s, e + 1)) as Map<String, dynamic>;
      final caption = (m['caption'] as String? ?? '').trim();
      final tags = (m['hashtags'] as List<dynamic>?)
              ?.map((t) => t.toString().trim())
              .where((t) => t.isNotEmpty)
              .toList() ??
          <String>[];
      return (caption: caption, hashtags: tags);
    } catch (_) {
      return (caption: '', hashtags: <String>[]);
    }
  }

  Future<List<String>> translateTexts(
      List<String> texts, String targetLang) async {
    if (texts.isEmpty) return [];

    final langName = switch (targetLang) {
      'en' => 'English',
      'th' => 'Thai (ภาษาไทย) — ສະກົດໄທໃຫ້ຖືກຕ້ອງ',
      'lo' =>
        'Lao (ພາສາລາວ) — ໃຊ້ການສະກົດລາວທີ່ຖືກຕ້ອງ, ແປເປັນຄຳເວົ້າລາວທຳມະຊາດ (ບໍ່ແມ່ນແປງຕົວອັກສອນໄທ)',
      'zh' => 'Chinese (中文)',
      _ => 'English',
    };

    final prompt =
        'ແປ subtitle ຕໍ່ໄປນີ້ທຸກ entry ເປັນ $langName ໃຫ້ຖືກຕ້ອງ ລຽບໄຫຼ ກະທັດຮັດ.\n'
        'ຮັກສາຈຳນວນ entry ໃຫ້ເທົ່າเดิม (${texts.length} ອັນ). ຮັກສາ ຊື່/ຍີ່ຫໍ້/ຕົວເລກ/ຄຳ English ໄວ້ຄືเดิม.\n'
        'ສົ່ງຄືນ JSON array ຂອງ strings ໃນລໍາດັບດຽວກັນ ບໍ່ໃສ່ text ອື່ນ:\n'
        '${jsonEncode(texts)}';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {'temperature': 0.2},
    });

    // Retry across primary → fallback model (separate quota) on 429/503.
    String responseBody = '';
    int statusCode = 0;
    bool quotaFallback = false;
    const maxAttempts = 5;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final useFallback = quotaFallback || attempt == maxAttempts;
      final uri = Uri.parse(
          '${_endpointFor(useFallback ? _fallbackModel : _primaryModel)}?key=$apiKey');
      http.Response resp;
      try {
        resp = await http
            .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
            .timeout(const Duration(seconds: 60));
      } catch (_) {
        if (attempt >= maxAttempts) {
          throw GeminiSpeechException('ເຊື່ອມຕໍ່ Gemini ບໍ່ໄດ້ — ລອງໃໝ່');
        }
        await Future.delayed(Duration(seconds: 2 * attempt));
        continue;
      }
      statusCode = resp.statusCode;
      responseBody = resp.body;
      if (statusCode == 200) break;
      if (statusCode == 429 && !useFallback && !quotaFallback) {
        quotaFallback = true; // 3.5 quota gone → switch to 2.5
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }
      final retryable = statusCode == 429 || statusCode == 503 || statusCode == 500;
      if (retryable && attempt < maxAttempts) {
        await Future.delayed(Duration(seconds: 2 * attempt));
        continue;
      }
      break;
    }

    if (statusCode != 200) {
      if (statusCode == 429) {
        throw GeminiSpeechException(
            'Gemini ໝົດໂຄຕ້າຟຣີມື້ນີ້ (20 ຄັ້ງ/ມື້) — ໃສ່ Groq key ຫຼື ລໍມື້ໃໝ່');
      }
      String msg;
      try {
        msg = jsonDecode(responseBody)['error']?['message'] ?? responseBody;
      } catch (_) {
        msg = responseBody;
      }
      throw GeminiSpeechException('Gemini $statusCode: $msg');
    }

    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) return texts;

      final parts =
          (candidates[0]['content'] as Map<String, dynamic>?)?['parts']
              as List<dynamic>?;
      if (parts == null || parts.isEmpty) return texts;

      var text = (parts[0]['text'] as String? ?? '').trim();
      text = text.replaceAll('```json', '').replaceAll('```', '').trim();

      final startIdx = text.indexOf('[');
      final endIdx = text.lastIndexOf(']');
      if (startIdx == -1 || endIdx == -1) return texts;

      final list =
          jsonDecode(text.substring(startIdx, endIdx + 1)) as List<dynamic>;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return texts;
    }
  }

  /// Translate a list of segments from Thai to Lao using Gemini.
  /// Keeps exactly the same number of segments so timestamps remain intact.
  Future<void> translateSegmentsToLao(
      List<SubtitleSegment> segments, void Function(String)? onProgress) async {
    if (segments.isEmpty) return;

    onProgress?.call('Gemini ກຳລັງແປພາສາໄທເປັນລາວ...');
    
    // Process in chunks to avoid overwhelming the model or prompt limits
    const chunkSize = 40;
    for (int i = 0; i < segments.length; i += chunkSize) {
      final end = (i + chunkSize > segments.length) ? segments.length : i + chunkSize;
      final batch = segments.sublist(i, end);
      final texts = batch.map((s) => s.text).toList();
      
      onProgress?.call('Gemini ກຳລັງແປ (${i + 1}-$end/${segments.length})...');

      final prompt =
          'You are an expert Thai-to-Lao translator for social media video subtitles.\n\n'
          'Task: Translate this JSON array of Thai subtitle segments into NATURAL Lao.\n\n'
          'CRITICAL: Thai and Lao are DIFFERENT languages. Do NOT just swap Thai characters to Lao. Write proper Lao.\n\n'
          'COMMON MISTAKES TO AVOID (TRANSLATE not transliterate):\n'
          '- à¹€à¸›à¹‡à¸™à¸¢à¸±à¸‡à¹„à¸‡à¸šà¹‰à¸²à¸‡ must become à»€àº›àº±àº™à»àº™àº§à»ƒàº”à»àº”à»ˆ (NOT à»€àº›àº±àº™àºàº±àº‡à»„àº‡àºšà»‰àº²àº‡)\n'
          '- à¸—à¸³à¹„à¸¡ must become à»€àº›àº±àº™àº«àºàº±àº‡ or àºà»‰àº­àº™àº«àºàº±àº‡ (NOT àº—àº³à»„àº¡)\n'
          '- à¸ˆà¸£à¸´à¸‡à¹† must become à»àº—à»‰à»† (NOT àºˆàº´àº‡à»†)\n'
          '- à¸ªà¸§à¸±à¸ªà¸”à¸µ must become àºªàº°àºšàº²àºàº”àºµ (NOT àºªàº°àº§àº±àº”àº”àºµ)\n'
          '- à¸‚à¸­à¸šà¸„à¸¸à¸“ must become àº‚àº­àºšà»ƒàºˆ (NOT àº‚àº­àºšàº„àº¸àº™)\n'
          '- à¸¡à¸²à¸ must become àº«àº¼àº²àº (NOT àº¡àº²àº)\n'
          '- à¸ªà¸™à¸¸à¸ must become àº¡à»ˆàº§àº™ (NOT àºªàº°àº™àº¸àº)\n'
          '- à¸­à¸£à¹ˆà¸­à¸¢ must become à»àºŠàºš (NOT àº­àº°àº«àº¼à»ˆàº­àº)\n'
          '- à¸ªà¸§à¸¢ must become àº‡àº²àº¡ (NOT àºªàº§àº)\n'
          '- à¸„à¸£à¸±à¸š/à¸„à¹ˆà¸° must become à»€àº”àºµà»‰/à»€àº”\n'
          '- à¹€à¸¥à¸¢ must become à»€àº¥àºµàº\n'
          '- à¹€à¸žà¸·à¹ˆà¸­à¸™ must become à»àº¹à»ˆ or à»€àºžàº·à»ˆàº­àº™\n'
          '- à¸à¹‡à¸„à¸·à¸­ must become àºà»àº„àº·\n\n'
          'RULES:\n'
          '1. TRANSLATE to natural spoken Lao. Do NOT transliterate Thai characters.\n'
          '2. Use REAL Lao words that Lao people actually say.\n'
          '3. Ensure 100% correct Lao vowels and consonants.\n'
          '4. Keep brand names, numbers, English words as-is.\n'
          '5. Maintain EXACTLY ${texts.length} items. Do NOT combine, split, or skip.\n'
          '6. Return ONLY a valid JSON array of strings.\n\n'
          'Input: ${jsonEncode(texts)}';


      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {'temperature': 0.1}, // Low temp for accurate translation
      });

      try {
        http.Response? response;
        const maxAttempts = 5;
        bool quotaFallback = false;
        for (int attempt = 1; attempt <= maxAttempts; attempt++) {
          final useFallback = quotaFallback || attempt == maxAttempts;
          final activeModel = useFallback ? _fallbackModel : _primaryModel;
          final uri = Uri.parse('${_endpointFor(activeModel)}?key=$apiKey');

          if (attempt >= 2) {
            onProgress?.call(useFallback
                ? 'ສະລັບໄປໃຊ້ Gemini ຮຸ່ນສຳຮອງ...'
                : '$activeModel ບໍ່ຫວ່າງ, ກຳລັງລອງໃໝ່ ($attempt/$maxAttempts)...');
          }

          try {
            response = await http.post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: body,
            ).timeout(const Duration(seconds: 45));
          } catch (_) {
            if (attempt >= maxAttempts) break;
            await Future.delayed(Duration(seconds: 3 * attempt));
            continue;
          }

          if (response.statusCode == 200) {
            break;
          }

          // 429 on primary = daily quota gone → jump to fallback model now.
          if (response.statusCode == 429 && !useFallback && !quotaFallback) {
            quotaFallback = true;
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }

          final retryable = response.statusCode == 429 || response.statusCode == 503 || response.statusCode == 500;
          if (retryable && attempt < maxAttempts) {
            final delaySecs = 3 * attempt;
            onProgress?.call('Gemini ຄົນໃຊ້ຫຼາຍ (${response.statusCode}) — ລໍຖ້າ $delaySecs ວິນາທີ ($attempt/$maxAttempts)...');
            await Future.delayed(Duration(seconds: delaySecs));
            continue;
          } else {
            break;
          }
        }

        if (response == null || response.statusCode != 200) continue;

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final parts = (data['candidates']?[0]?['content'] as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
        if (parts == null || parts.isEmpty) continue;

        var raw = (parts[0]['text'] as String? ?? '').trim();
        raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();
        final s = raw.indexOf('[');
        final e = raw.lastIndexOf(']');
        if (s == -1 || e == -1) continue;

        final list = jsonDecode(raw.substring(s, e + 1)) as List<dynamic>;
        
        // Safety check: only apply if the array length matches exactly!
        if (list.length == batch.length) {
          for (int j = 0; j < batch.length; j++) {
            batch[j].text = list[j].toString().trim();
            batch[j].words = null; // Clear Thai words so LaoWordService regenerates Lao words
            batch[j].wordTimings = null;
          }
        }
      } catch (_) {
        // Continue to next batch on error
      }
    }
  }

  /// General translate segments method that translates segments from source to target language
  Future<void> translateSegments({
    required List<SubtitleSegment> segments,
    required String sourceLang,
    required String targetLang,
    required void Function(String)? onProgress,
    bool keepOriginalAsBilingual = false,
  }) async {
    if (segments.isEmpty) return;

    final sourceName = switch (sourceLang) {
      'lo' => 'Lao (ພາສາລາວ)',
      'th' => 'Thai (ພາສາໄທ)',
      'en' => 'English',
      _ => 'Thai (ພາສາໄທ)',
    };

    final targetName = switch (targetLang) {
      'lo' => 'Lao (ພາສາລາວ)',
      'th' => 'Thai (ພາສາໄທ)',
      'en' => 'English',
      _ => 'Lao (ພາສາລາວ)',
    };

    onProgress?.call('Gemini ກຳລັງແປພາສາ...');
    
    const chunkSize = 40;
    for (int i = 0; i < segments.length; i += chunkSize) {
      final end = (i + chunkSize > segments.length) ? segments.length : i + chunkSize;
      final batch = segments.sublist(i, end);
      final texts = batch.map((s) => s.text).toList();
      
      onProgress?.call('Gemini ກຳລັງແປ (${i + 1}-$end/${segments.length})...');

      final String prompt;
      if (targetLang == 'lo') {
        // Deep Lao-specific prompt with spelling rules and examples
        prompt =
            'You are an expert Thai-to-Lao translator specializing in subtitle translation for social media videos (TikTok/Reels/Shorts).\n\n'
            'Task: Translate this JSON array of Thai subtitle segments into NATURAL Lao (ພາສາລາວ).\n\n'
            '⚠️ CRITICAL LAO SPELLING & VOCABULARY RULES (ກົດສະກົດພາສາລາວ):\n'
            'Thai and Lao are DIFFERENT languages with DIFFERENT spelling systems. You must NOT just swap Thai characters to Lao. You must write proper Lao.\n\n'
            'KEY DIFFERENCES:\n'
            '- Thai ไ◌ (sara ai maimalai) → Lao ໄ◌\n'
            '- Thai ใ◌ (sara ai maimuan) → Lao ໃ◌ (only 20 specific words use ໃ: ໃຊ້, ໃຫ້, ໃຫຍ່, ໃກ້, ໃຈ, ໃໝ່, ໃບ, ໃດ, ໃຕ້, ໃນ, ໃສ, ໃສ່, ໃຜ, ໃຝ່, ໃຍ, ໃຫວ້, ໃຫ້ only these)\n'
            '- Thai ็ (mai taikhu) → Lao ັ (mai kan)\n'
            '- Thai ์ (gaaran) → Lao ໌ (gaaran lao)\n'
            '- Thai ๆ → Lao ໆ\n'
            '- Thai ฯ → not used in Lao\n'
            '- Lao does NOT use Thai characters like: ฎ ฏ ฐ ฑ ฒ ณ ฤ ฦ ศ ษ ฬ ฮ (different set)\n'
            '- Thai ร → Lao ຣ or ລ depending on the word\n'
            '- Thai มี → Lao ມີ, Thai ไม่ → Lao ບໍ່\n\n'
            'COMMON TRANSLATION EXAMPLES (ຕ້ອງແປ ບໍ່ແມ່ນແປງຕົວອັກສອນ):\n'
            '- "เป็นยังไงบ้าง" → "ເປັນແນວໃດແດ່" or "ເປັນຈັ່ງໃດແດ່" (NOT "ເປັນຍັງໄງບ້າງ")\n'
            '- "ทำไม" → "ເປັນຫຍັງ" or "ຍ້ອນຫຍັງ" (NOT "ທຳໄມ")\n'
            '- "อย่างไร" → "ແນວໃດ" or "ຈັ່ງໃດ" (NOT "ຢ່າງໄຣ")\n'
            '- "อย่างแรกเลย" → "ຢ່າງທຳອິດເລີຍ" or "ກ່ອນອື່ນໝົດ"\n'
            '- "ก็คือ" → "ກໍຄື"\n'
            '- "ต้อง" → "ຕ້ອງ"\n'
            '- "ได้" → "ໄດ້"\n'
            '- "ไม่ได้" → "ບໍ່ໄດ້"\n'
            '- "จริงๆ" → "ແທ້ໆ" (NOT "ຈິງໆ")\n'
            '- "แล้ว" → "ແລ້ວ"\n'
            '- "ครับ/ค่ะ" → "ເດີ້/ເດ"\n'
            '- "สวัสดี" → "ສະບາຍດີ" (NOT "ສະວັດດີ")\n'
            '- "ขอบคุณ" → "ຂອບໃຈ" (NOT "ຂອບຄຸນ")\n'
            '- "ถ้า" → "ຖ້າ" or "ຖ້າວ່າ"\n'
            '- "เรื่อง" → "ເລື່ອງ"\n'
            '- "มาก" → "ຫຼາຍ" (NOT "ມາກ")\n'
            '- "เลย" → "ເລີຍ"\n'
            '- "ดี" → "ດີ"\n'
            '- "สนุก" → "ມ່ວນ" (NOT "ສະນຸກ")\n'
            '- "อร่อย" → "ແຊບ" (NOT "ອະຫຼ່ອຍ")\n'
            '- "สวย" → "ງາມ" (NOT "ສວຍ")\n'
            '- "เก่ง" → "ເກັ່ງ" or "ຈັກ"\n'
            '- "ไป" → "ໄປ"\n'
            '- "กิน" → "ກິນ"\n'
            '- "พูด" → "เວົ້າ" or "ເວົ້າ"\n'
            '- "บอก" → "ບອກ"\n'
            '- "เงิน" → "ເງິນ"\n'
            '- "เพื่อน" → "ໝູ່" or "ເພື່ອນ"\n'
            '- "ที่" → "ທີ່"\n\n'
            'RULES:\n'
            '1. TRANSLATE to natural spoken Lao — do NOT transliterate Thai characters to Lao equivalents.\n'
            '2. Use REAL Lao words and expressions that Lao people actually say in daily life.\n'
            '3. Ensure 100% correct Lao spelling with proper vowels (ສະຫຼະ) and consonants (ພະຍັນຊະນະ).\n'
            '4. Keep brand names, technical terms, numbers, and English words as-is.\n'
            '5. Each subtitle must be short, concise, and natural for video subtitles.\n'
            '6. Maintain EXACTLY ${texts.length} items in the output array. Do NOT combine, split, or skip any.\n'
            '7. Return ONLY a valid JSON array of strings. No markdown, no explanations.\n\n'
            'Input: ${jsonEncode(texts)}';
      } else if (targetLang == 'th' && sourceLang == 'lo') {
        prompt =
            'You are an expert Lao-to-Thai translator for social media subtitle videos.\n\n'
            'Task: Translate this JSON array of Lao subtitle segments into natural, modern spoken Thai (ภาษาไทย).\n\n'
            'RULES:\n'
            '1. Use natural conversational Thai, as spoken on Thai social media.\n'
            '2. Ensure 100% correct Thai spelling and grammar.\n'
            '3. Keep brand names, technical terms, numbers, and English words as-is.\n'
            '4. Maintain EXACTLY ${texts.length} items. Do NOT combine, split, or skip any.\n'
            '5. Return ONLY a valid JSON array of strings.\n\n'
            'Input: ${jsonEncode(texts)}';
      } else {
        prompt =
            'You are an expert bilingual subtitle translator specializing in translating spoken $sourceName to natural, modern, conversational $targetName for social media videos.\n\n'
            'Task: Translate this JSON array of subtitle segments into $targetName.\n\n'
            'CRITICAL RULES:\n'
            '1. Speak like a native speaker of $targetName. Use natural, conversational, modern spoken words. Avoid literal word-for-word transliterations that sound unnatural.\n'
            '2. Ensure 100% correct grammar, vocabulary, and spelling.\n'
            '3. Keep specific technical terms, brand/people names, numbers, or English words exactly as they are in the original.\n'
            '4. Strictly maintain the exact same array length. Translate each element individually. Do not combine, split, or omit any sentences. Input has ${texts.length} items, so you MUST output exactly ${texts.length} items.\n'
            '5. Return ONLY a valid JSON array of strings. Do not include markdown formatting or any extra explanations.\n\n'
            'Input: ${jsonEncode(texts)}';
      }

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {'temperature': 0.1},
      });

      try {
        http.Response? response;
        const maxAttempts = 5;
        bool quotaFallback = false;
        for (int attempt = 1; attempt <= maxAttempts; attempt++) {
          final useFallback = quotaFallback || attempt == maxAttempts;
          final activeModel = useFallback ? _fallbackModel : _primaryModel;
          final uri = Uri.parse('${_endpointFor(activeModel)}?key=$apiKey');

          if (attempt >= 2) {
            onProgress?.call(useFallback
                ? 'ສະລັບໄປໃຊ້ Gemini ຮຸ່ນສຳຮອງ...'
                : '$activeModel ບໍ່ຫວ່າງ, ກຳລັງລອງໃໝ່ ($attempt/$maxAttempts)...');
          }

          try {
            response = await http.post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: body,
            ).timeout(const Duration(seconds: 45));
          } catch (_) {
            if (attempt >= maxAttempts) break;
            await Future.delayed(Duration(seconds: 3 * attempt));
            continue;
          }

          if (response.statusCode == 200) {
            break;
          }

          // 429 on primary = daily quota gone → jump to fallback model now.
          if (response.statusCode == 429 && !useFallback && !quotaFallback) {
            quotaFallback = true;
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }

          final retryable = response.statusCode == 429 || response.statusCode == 503 || response.statusCode == 500;
          if (retryable && attempt < maxAttempts) {
            final delaySecs = 3 * attempt;
            onProgress?.call('Gemini ຄົນໃຊ້ຫຼາຍ (${response.statusCode}) — ລໍຖ້າ $delaySecs ວິນາທີ ($attempt/$maxAttempts)...');
            await Future.delayed(Duration(seconds: delaySecs));
            continue;
          } else {
            break;
          }
        }

        if (response == null || response.statusCode != 200) continue;

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final parts = (data['candidates']?[0]?['content'] as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
        if (parts == null || parts.isEmpty) continue;

        var raw = (parts[0]['text'] as String? ?? '').trim();
        raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();
        final s = raw.indexOf('[');
        final e = raw.lastIndexOf(']');
        if (s == -1 || e == -1) continue;

        final list = jsonDecode(raw.substring(s, e + 1)) as List<dynamic>;
        
        if (list.length == batch.length) {
          for (int j = 0; j < batch.length; j++) {
            final originalText = batch[j].text;
            final translatedText = list[j].toString().trim();
            if (keepOriginalAsBilingual) {
              batch[j].text = translatedText;
              batch[j].translatedText = originalText;
            } else {
              batch[j].text = translatedText;
              batch[j].translatedText = null;
            }
            batch[j].words = null; 
            batch[j].wordTimings = null;
          }
        }
      } catch (_) {
        // Continue to next batch on error
      }
    }
  }

  /// For each subtitle line, suggest a SHORT English meme/GIF search query
  /// (1–3 words, e.g. "shocked", "money rain", "facepalm"). Returns "" for lines
  /// that don't need a meme. Same length & order as [texts].
  Future<List<String>> suggestMemeQueries(List<String> texts) async {
    if (texts.isEmpty) return [];
    final prompt =
        'For each subtitle line below, give a SHORT English search query (1-3 words) '
        'for a funny/reaction meme GIF that fits its vibe (e.g. "shocked", "money rain", '
        '"facepalm", "clapping", "mind blown"). If a line is plain/neutral and needs no '
        'meme, return "". Keep the SAME number of items (${texts.length}) in order. '
        'Return ONLY a JSON array of strings.\n\nInput: ${jsonEncode(texts)}';
    final body = jsonEncode({
      'contents': [{'parts': [{'text': prompt}]}],
      'generationConfig': {'temperature': 0.5},
    });
    String responseBody = '';
    int statusCode = 0;
    bool quotaFallback = false;
    const maxAttempts = 4;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final useFallback = quotaFallback || attempt == maxAttempts;
      final uri = Uri.parse(
          '${_endpointFor(useFallback ? _fallbackModel : _primaryModel)}?key=$apiKey');
      http.Response resp;
      try {
        resp = await http
            .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
            .timeout(const Duration(seconds: 45));
      } catch (_) {
        if (attempt >= maxAttempts) return List.filled(texts.length, '');
        await Future.delayed(Duration(seconds: 2 * attempt));
        continue;
      }
      statusCode = resp.statusCode;
      responseBody = resp.body;
      if (statusCode == 200) break;
      if (statusCode == 429 && !useFallback && !quotaFallback) {
        quotaFallback = true;
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }
      if ((statusCode == 503 || statusCode == 500) && attempt < maxAttempts) {
        await Future.delayed(Duration(seconds: 2 * attempt));
        continue;
      }
      break;
    }
    if (statusCode != 200) return List.filled(texts.length, '');
    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final parts = (data['candidates']?[0]?['content']
          as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
      var raw = (parts?[0]['text'] as String? ?? '').trim();
      raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final s = raw.indexOf('[');
      final e = raw.lastIndexOf(']');
      if (s == -1 || e == -1) return List.filled(texts.length, '');
      final list = jsonDecode(raw.substring(s, e + 1)) as List<dynamic>;
      final out = list.map((x) => x.toString().trim()).toList();
      // pad/truncate to texts.length for safety
      if (out.length < texts.length) {
        out.addAll(List.filled(texts.length - out.length, ''));
      }
      return out.sublist(0, texts.length);
    } catch (_) {
      return List.filled(texts.length, '');
    }
  }

  /// For each subtitle line, suggest a SHORT English stock-photo search query
  /// describing the REAL VISUAL SUBJECT to show as B-roll (a place, object,
  /// scene, food, animal, activity). Abstract/filler/greeting lines return ""
  /// (no B-roll). Used by the auto B-roll feature.
  Future<List<String>> suggestBrollQueries(List<String> texts) async {
    if (texts.isEmpty) return [];
    final prompt =
        'The subtitle lines below are in Lao or Thai. FIRST understand the '
        'overall topic of the whole script, THEN for each line give a SHORT '
        'English stock-footage search query (1-3 words) for the REAL VISUAL '
        'SUBJECT to show as B-roll — a concrete, photogenic '
        'place/object/scene/food/animal/activity matching the line MEANING in '
        'context (not a word-by-word translation) — e.g. "mountain lake", '
        '"street food", "city at night", "coffee cup", "ocean waves", '
        '"rice field". Prefer generic subjects stock sites surely have; for '
        'specific people/brands/local places use the generic type instead '
        '(e.g. a Lao temple → "buddhist temple"). If a line is abstract, '
        'filler, a greeting, or has nothing concrete to show, return "". '
        'Keep the SAME number of items (${texts.length}) in order. '
        'Return ONLY a JSON array of strings.'
        '\n\nInput: ${jsonEncode(texts)}';
    final body = jsonEncode({
      'contents': [{'parts': [{'text': prompt}]}],
      'generationConfig': {'temperature': 0.4},
    });
    String responseBody = '';
    int statusCode = 0;
    bool quotaFallback = false;
    const maxAttempts = 4;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final useFallback = quotaFallback || attempt == maxAttempts;
      final uri = Uri.parse(
          '${_endpointFor(useFallback ? _fallbackModel : _primaryModel)}?key=$apiKey');
      http.Response resp;
      try {
        resp = await http
            .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
            .timeout(const Duration(seconds: 45));
      } catch (_) {
        if (attempt >= maxAttempts) return List.filled(texts.length, '');
        await Future.delayed(Duration(seconds: 2 * attempt));
        continue;
      }
      statusCode = resp.statusCode;
      responseBody = resp.body;
      if (statusCode == 200) break;
      if (statusCode == 429 && !useFallback && !quotaFallback) {
        quotaFallback = true;
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }
      if ((statusCode == 503 || statusCode == 500) && attempt < maxAttempts) {
        await Future.delayed(Duration(seconds: 2 * attempt));
        continue;
      }
      break;
    }
    if (statusCode != 200) return List.filled(texts.length, '');
    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final parts = (data['candidates']?[0]?['content']
          as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
      var raw = (parts?[0]['text'] as String? ?? '').trim();
      raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final s = raw.indexOf('[');
      final e = raw.lastIndexOf(']');
      if (s == -1 || e == -1) return List.filled(texts.length, '');
      final list = jsonDecode(raw.substring(s, e + 1)) as List<dynamic>;
      final out = list.map((x) => x.toString().trim()).toList();
      if (out.length < texts.length) {
        out.addAll(List.filled(texts.length - out.length, ''));
      }
      return out.sublist(0, texts.length);
    } catch (_) {
      return List.filled(texts.length, '');
    }
  }

  /// Generate a viral "post kit" from the transcript: a punchy on-screen hook,
  /// a post caption, and hashtags. Returns {'hook','caption','hashtags'} (empty
  /// strings on failure).
  Future<Map<String, String>> generateHookKit(List<String> texts,
      {String language = 'lo'}) async {
    if (texts.isEmpty) return {};
    final langName = switch (language) {
      'lo' => 'Lao (ພາສາລາວ)',
      'th' => 'Thai (ภาษาไทย)',
      'en' => 'English',
      _ => 'Lao (ພາສາລາວ)',
    };
    final prompt =
        'You are a viral short-form video strategist. Based on the transcript '
        'below (in $langName), produce: (1) "hook": a punchy 3-8 word on-screen '
        'hook for the first 3 seconds, in $langName; (2) "caption": a 1-2 '
        'sentence engaging post caption in $langName; (3) "hashtags": 5-8 '
        'relevant hashtags (mix $langName + English), space-separated, each '
        'starting with #. Return ONLY a JSON object with keys hook, caption, '
        'hashtags.\n\nTranscript:\n${texts.join(' ')}';
    final body = jsonEncode({
      'contents': [{'parts': [{'text': prompt}]}],
      'generationConfig': {'temperature': 0.8},
    });
    String responseBody = '';
    int statusCode = 0;
    bool quotaFallback = false;
    const maxAttempts = 4;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final useFallback = quotaFallback || attempt == maxAttempts;
      final uri = Uri.parse(
          '${_endpointFor(useFallback ? _fallbackModel : _primaryModel)}?key=$apiKey');
      http.Response resp;
      try {
        resp = await http
            .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
            .timeout(const Duration(seconds: 45));
      } catch (_) {
        if (attempt >= maxAttempts) return {};
        await Future.delayed(Duration(seconds: 2 * attempt));
        continue;
      }
      statusCode = resp.statusCode;
      responseBody = resp.body;
      if (statusCode == 200) break;
      if (statusCode == 429 && !useFallback && !quotaFallback) {
        quotaFallback = true;
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }
      if ((statusCode == 503 || statusCode == 500) && attempt < maxAttempts) {
        await Future.delayed(Duration(seconds: 2 * attempt));
        continue;
      }
      break;
    }
    if (statusCode != 200) return {};
    try {
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final parts = (data['candidates']?[0]?['content']
          as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
      var raw = (parts?[0]['text'] as String? ?? '').trim();
      raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final s = raw.indexOf('{');
      final e = raw.lastIndexOf('}');
      if (s == -1 || e == -1) return {};
      final m = jsonDecode(raw.substring(s, e + 1)) as Map<String, dynamic>;
      return {
        'hook': (m['hook'] ?? '').toString().trim(),
        'caption': (m['caption'] ?? '').toString().trim(),
        'hashtags': (m['hashtags'] ?? '').toString().trim(),
      };
    } catch (_) {
      return {};
    }
  }

  /// Second pass: send the FULL transcript text back to Gemini to fix spelling,
  /// typos and cross-chunk consistency — WITHOUT changing meaning, order, or the
  /// number of lines (so timings stay aligned). Edits `segment.text` in place.
  Future<void> proofreadSegments({
    required List<SubtitleSegment> segments,
    required String language,
    String hint = '',
    void Function(String)? onProgress,
  }) async {
    if (segments.isEmpty) return;
    final langName = switch (language) {
      'lo' => 'Lao (ພາສາລາວ)',
      'th' => 'Thai (ภาษาไทย)',
      'en' => 'English',
      _ => 'Lao (ພາສາລາວ)',
    };
    final h = hint.trim();
    final glossary = h.isEmpty
        ? ''
        : '\nProper nouns / names to spell correctly when they appear: $h\n';

    onProgress?.call('Gemini ກຳລັງກວດທານ...');
    const chunkSize = 40;
    for (int i = 0; i < segments.length; i += chunkSize) {
      final end = (i + chunkSize > segments.length) ? segments.length : i + chunkSize;
      final batch = segments.sublist(i, end);
      final texts = batch.map((s) => s.text).toList();
      onProgress?.call('Gemini ກຳລັງກວດທານ (${i + 1}-$end/${segments.length})...');

      final prompt =
          'You are a $langName subtitle proofreader. Below is a JSON array of subtitle lines transcribed from speech.\n'
          'Fix ONLY: spelling/typos, wrong/garbled characters, missing or extra spacing, and consistency of repeated names across lines.\n'
          'DO NOT: change the meaning, rephrase, translate, merge, split, reorder, add, or remove any line.\n'
          'Keep numbers as digits and keep English/brand words as-is.$glossary'
          'Return ONLY a valid JSON array of EXACTLY ${texts.length} strings, in the same order. No markdown, no explanations.\n\n'
          'Input: ${jsonEncode(texts)}';

      final body = jsonEncode({
        'contents': [{'parts': [{'text': prompt}]}],
        'generationConfig': {'temperature': 0.0},
      });

      try {
        http.Response? response;
        const maxAttempts = 4;
        bool quotaFallback = false;
        for (int attempt = 1; attempt <= maxAttempts; attempt++) {
          final useFallback = quotaFallback || attempt == maxAttempts;
          final uri = Uri.parse(
              '${_endpointFor(useFallback ? _fallbackModel : _primaryModel)}?key=$apiKey');
          try {
            response = await http
                .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
                .timeout(const Duration(seconds: 45));
          } catch (_) {
            if (attempt >= maxAttempts) break;
            await Future.delayed(Duration(seconds: 3 * attempt));
            continue;
          }
          if (response.statusCode == 200) break;
          if (response.statusCode == 429 && !useFallback && !quotaFallback) {
            quotaFallback = true;
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }
          final retryable = response.statusCode == 429 ||
              response.statusCode == 503 ||
              response.statusCode == 500;
          if (retryable && attempt < maxAttempts) {
            await Future.delayed(Duration(seconds: 3 * attempt));
            continue;
          }
          break;
        }
        if (response == null || response.statusCode != 200) continue;

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final parts = (data['candidates']?[0]?['content']
            as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
        if (parts == null || parts.isEmpty) continue;
        var raw = (parts[0]['text'] as String? ?? '').trim();
        raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();
        final s = raw.indexOf('[');
        final e = raw.lastIndexOf(']');
        if (s == -1 || e == -1) continue;
        final list = jsonDecode(raw.substring(s, e + 1)) as List<dynamic>;

        // Safety: only apply if the count matches exactly (keeps timing aligned).
        if (list.length == batch.length) {
          for (int j = 0; j < batch.length; j++) {
            final fixed = list[j].toString().trim();
            if (fixed.isNotEmpty && fixed != batch[j].text) {
              batch[j].text = fixed;
              // Re-derive word units later so karaoke stays correct.
              batch[j].words = null;
              batch[j].wordTimings = null;
            }
          }
        }
      } catch (_) {
        // best-effort — skip this batch on error
      }
    }
  }
}
