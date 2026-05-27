import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/subtitle_style_model.dart';
import 'audio_sync_service.dart';

class GeminiSpeechException implements Exception {
  final String message;
  GeminiSpeechException(this.message);
  @override
  String toString() => message;
}

class GeminiSpeechService {
  static const _channel = MethodChannel('com.anniekaydee.subtitle_app/audio');
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  // Long audio is split into chunks of ~this length so Gemini's timestamps stay
  // accurate (its drift grows with duration). Each chunk is cut at a silence and
  // its words are offset by the chunk's exact start time.
  static const int _chunkTargetMs = 75000;

  final String apiKey;
  final _uuid = const Uuid();

  GeminiSpeechService({required this.apiKey});

  Future<List<SubtitleSegment>> transcribe(
    String videoPath, {
    String language = 'lo',
    WordSplit wordSplit = WordSplit.none,
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
    final wavBytes = await wavFile.readAsBytes();
    wavFile.deleteSync();
    if (wavBytes.length <= 44) return [];

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
    final prompt = _buildPrompt(langName);

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
    for (int ci = 0; ci < chunks.length; ci++) {
      final cs = chunks[ci][0];
      final ce = chunks[ci][1];
      if (ce - cs < 50) continue;
      onProgress?.call(chunks.length > 1
          ? 'Gemini ກໍາລັງຖອດສຽງ (${ci + 1}/${chunks.length})...'
          : 'Gemini ກໍາລັງຖອດສຽງລາວ...');
      final chunkWav = _sliceWav(wavBytes, cs, ce, bytesPerMs);
      final data = await _callGemini(chunkWav, prompt, onProgress);
      for (final w in _parseWordEntries(data)) {
        allWords.add(
            (startMs: w.startMs + cs, endMs: w.endMs + cs, text: w.text));
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

  String _buildPrompt(String langName) =>
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

    final uri = Uri.parse('$_endpoint?key=$apiKey');
    const maxAttempts = 4;
    String responseBody = '';
    int statusCode = 0;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final httpClient = HttpClient();
        final request = await httpClient.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.write(body);
        final response =
            await request.close().timeout(const Duration(minutes: 5));
        responseBody = await response.transform(utf8.decoder).join();
        statusCode = response.statusCode;
        httpClient.close();
      } catch (e) {
        if (attempt >= maxAttempts) {
          throw GeminiSpeechException(
              'ເຊື່ອມຕໍ່ Gemini ບໍ່ໄດ້ — ກວດເນັດ ຫຼື ລອງໃໝ່ (${e.runtimeType})');
        }
        await Future.delayed(Duration(seconds: 1 << attempt));
        continue;
      }

      if (statusCode == 200) {
        return jsonDecode(responseBody) as Map<String, dynamic>;
      }

      final retryable =
          statusCode == 503 || statusCode == 429 || statusCode == 500;
      if (retryable && attempt < maxAttempts) {
        onProgress
            ?.call('Gemini ຄົນໃຊ້ຫຼາຍ — ລອງໃໝ່ ($attempt/$maxAttempts)...');
        await Future.delayed(Duration(seconds: 1 << attempt)); // 2s,4s,8s
        continue;
      }

      String msg;
      try {
        final err = jsonDecode(responseBody);
        msg = err['error']?['message'] ?? responseBody;
      } catch (_) {
        msg = responseBody;
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
    for (int start = 0; start < segs.length; start += chunkSize) {
      final end = (start + chunkSize).clamp(0, segs.length);
      final slice = segs.sublist(start, end);

      // Build input: each line's word units (so Gemini returns a valid index).
      final input = <Map<String, dynamic>>[];
      for (int k = 0; k < slice.length; k++) {
        final words = (slice[k].words != null && slice[k].words!.isNotEmpty)
            ? slice[k].words!.where((w) => w.trim().isNotEmpty).toList()
            : [slice[k].text];
        input.add({'i': k, 'words': words});
      }

      final prompt =
          'ສຳລັບແຕ່ລະ subtitle (ພາສາລາວ) ຂ້າງລຸ່ມ ໃຫ້ເລືອກ:\n'
          '1. "emoji" = emoji 1 ໂຕ ທີ່ເໝາະກັບຄວາມໝາຍຂອງປະໂຫຍກ (ຖ້າບໍ່ມີທີ່ເໝາະ ໃຫ້ "")\n'
          '2. "keyword" = index (ເລີ່ມ 0) ຂອງ "ຄຳເด็ด/ສຳคัญທີ່ສຸດ" 1 ຄຳ ໃນ words ເພື່ອเน้น '
          '(ຖ້າບໍ່ມີຄຳເด็ด ໃຫ້ -1)\n'
          'ສົ່ງ JSON array ລຽงตาม index "i" ເທົ່ານັ້ນ ບໍ່ໃສ່ text ອື່ນ:\n'
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
        'generationConfig': {'temperature': 0.4},
      });

      try {
        final uri = Uri.parse('$_endpoint?key=$apiKey');
        final httpClient = HttpClient();
        final request = await httpClient.postUrl(uri);
        request.headers.contentType = ContentType.json;
        request.write(body);
        final response =
            await request.close().timeout(const Duration(minutes: 2));
        final respBody = await response.transform(utf8.decoder).join();
        httpClient.close();
        if (response.statusCode != 200) continue;

        final data = jsonDecode(respBody) as Map<String, dynamic>;
        final parts = (data['candidates']?[0]?['content']
            as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
        if (parts == null || parts.isEmpty) continue;
        var raw = (parts[0]['text'] as String? ?? '').trim();
        raw = raw.replaceAll('```json', '').replaceAll('```', '').trim();
        final s = raw.indexOf('[');
        final e = raw.lastIndexOf(']');
        if (s == -1 || e == -1) continue;
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
      } catch (_) {
        // best-effort; skip this chunk on error
      }
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
      final httpClient = HttpClient();
      final request = await httpClient.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.write(body);
      final response =
          await request.close().timeout(const Duration(minutes: 2));
      final respBody = await response.transform(utf8.decoder).join();
      httpClient.close();
      if (response.statusCode != 200) {
        return (caption: '', hashtags: <String>[]);
      }
      final data = jsonDecode(respBody) as Map<String, dynamic>;
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
      'th' => 'ພາສາໄທ',
      'zh' => 'ພາສາຈີນ',
      _ => 'English',
    };

    final prompt =
        'ແປ subtitle ຕໍ່ໄປນີ້ທຸກ entry ເປັນ $langName ໃຫ້ຖືກຕ້ອງ ລຽບໄຫຼ ກ້ວາງສັ້ນໄດ້ໃຈ.\n'
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

    final uri = Uri.parse('$_endpoint?key=$apiKey');
    final httpClient = HttpClient();
    final request = await httpClient.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(body);
    final response =
        await request.close().timeout(const Duration(minutes: 2));

    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      String msg;
      try {
        final err = jsonDecode(responseBody);
        msg = err['error']?['message'] ?? responseBody;
      } catch (_) {
        msg = responseBody;
      }
      throw GeminiSpeechException('Gemini ${response.statusCode}: $msg');
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
}
