import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/subtitle_style_model.dart';
import 'lao_word_service.dart';
import 'wav_chunker.dart';

class OpenAIWhisperException implements Exception {
  final String message;
  OpenAIWhisperException(this.message);
  @override
  String toString() => message;
}

class OpenAIWhisperService {
  static const _channel = MethodChannel('com.anniekaydee.subtitle_app/audio');
  static const _endpoint = 'https://api.openai.com/v1/audio/transcriptions';

  final String apiKey;
  final _uuid = const Uuid();

  OpenAIWhisperService({required this.apiKey});

  Future<List<SubtitleSegment>> transcribe(
    String videoPath, {
    String language = 'lo',
    WordSplit wordSplit = WordSplit.none,
    void Function(String)? onProgress,
  }) async {
    // Step 1: Extract audio
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
      throw OpenAIWhisperException('ດຶງສຽງບໍ່ສຳເລັດ: ${e.message}');
    }

    final wavFile = File(wavPath);
    if (!wavFile.existsSync()) {
      throw OpenAIWhisperException('ໄຟລ໌ audio ສ້າງບໍ່ສຳເລັດ');
    }

    onProgress?.call('ກໍາລັງແບ່ງທ່ອນສຽງ...');
    final chunks = await WavChunker.splitWav(wavPath, chunkDurationSeconds: 15.0);
    final allSegments = <SubtitleSegment>[];

    // Process in batches of 5 to stay within rate limits but fast
    final batchSize = 5;
    for (int i = 0; i < chunks.length; i += batchSize) {
      final batch = chunks.sublist(i, (i + batchSize < chunks.length) ? i + batchSize : chunks.length);
      onProgress?.call('OpenAI ກຳລັງຖອດສຽງຂະໜານ (${i + 1}-${i + batch.length}/${chunks.length})...');

      final futures = batch.map((chunk) async {
        final request = http.MultipartRequest('POST', Uri.parse(_endpoint));
        request.headers['Authorization'] = 'Bearer $apiKey';
        request.fields['model'] = 'whisper-1';
        if (language == 'lo' || language == 'th') {
          request.fields['language'] = 'th'; // Force Thai for both 'th' and 'lo' to get perfect timestamps
        } else {
          request.fields['language'] = language;
        }
        request.fields['response_format'] = 'verbose_json';
        request.fields['timestamp_granularities[]'] = 'word';
        request.files.add(await http.MultipartFile.fromPath('file', chunk.path, filename: 'audio.wav'));

        http.Response response;
        try {
          final streamedResponse = await request.send().timeout(const Duration(seconds: 60));
          response = await http.Response.fromStream(streamedResponse).timeout(const Duration(seconds: 60));
        } catch (e) {
          throw OpenAIWhisperException('ເຄືອຂ່າຍມີບັນຫາ ຫຼື Timeout: $e');
        }

        try { File(chunk.path).deleteSync(); } catch (_) {}

        if (response.statusCode == 401) throw OpenAIWhisperException('API Key ບໍ່ຖືກຕ້ອງ');
        if (response.statusCode == 429) throw OpenAIWhisperException('ເກີນ rate limit — ລໍຖ້າສັກຄູ່ແລ້ວລອງໃໝ່');
        if (response.statusCode != 200) {
          final err = jsonDecode(response.body);
          throw OpenAIWhisperException('OpenAI error: ${err['error']?['message'] ?? response.statusCode}');
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final segments = _parseResponse(data);

        for (final s in segments) {
          final offsetMs = (chunk.startTime * 1000).toInt();
          s.startTime += Duration(milliseconds: offsetMs);
          s.endTime += Duration(milliseconds: offsetMs);
          if (s.wordTimings != null) {
            s.wordTimings = s.wordTimings!.map((t) => t + Duration(milliseconds: offsetMs)).toList();
          }
        }
        return segments;
      });

      final results = await Future.wait(futures);
      for (final res in results) {
        allSegments.addAll(res);
      }
    }

    try { wavFile.deleteSync(); } catch (_) {}

    onProgress?.call('ກຳລັງສ້າງ Subtitle...');
    allSegments.sort((a, b) => a.startTime.compareTo(b.startTime));
    
    var segments = allSegments;

    if (language == 'lo' || language == 'th') {
      try {
        await LaoWordService.refineToRealWords(segments, locale: language);
      } catch (_) {}
    }

    if (wordSplit != WordSplit.none) {
      segments = _splitByWords(segments, wordSplit);
    }
    return segments;
  }

  /// Forced-alignment helper: return Whisper's accurate timing skeleton —
  /// per-WORD start times (+ last word end) AND the phrase-level [regions]
  /// ([startMs,endMs] per Whisper segment). The text is ignored (we keep
  /// Gemini's better Lao spelling); we only borrow the acoustic timing.
  /// [regions] are the most reliable for matching subtitle DURATION to speech.
  /// Returns empty on any failure (best-effort).
  Future<({List<int> startsMs, int endMs, List<List<int>> regions})>
      fetchWordTimings(
    String videoPath, {
    String language = 'lo',
    void Function(String)? onProgress,
  }) async {
    const empty = (startsMs: <int>[], endMs: 0, regions: <List<int>>[]);
    final tempDir = await getTemporaryDirectory();
    final wavPath =
        '${tempDir.path}/wsync_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await _channel.invokeMethod('extractAudio', {
        'videoPath': videoPath,
        'outputPath': wavPath,
      });
    } catch (_) {
      return empty;
    }
    final wavFile = File(wavPath);
    if (!wavFile.existsSync()) return empty;
    if (await wavFile.length() > 25 * 1024 * 1024) {
      // OpenAI caps uploads at 25MB — skip (caller falls back to energy VAD).
      try {
        wavFile.deleteSync();
      } catch (_) {}
      return empty;
    }

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_endpoint));
      request.headers['Authorization'] = 'Bearer $apiKey';
      request.fields['model'] = 'whisper-1';
      request.fields['response_format'] = 'verbose_json';
      request.fields['timestamp_granularities[]'] = 'word';
      if (language == 'lo' || language == 'th') {
        request.fields['language'] = 'th'; // Force Thai for both 'th' and 'lo' to get perfect timestamps
        request.fields['prompt'] =
            'ຖອດສຽງພາສາລາວ. ພາສາລາວ. ສາທາລະນະລັດ ປະຊາທິປະໄຕ ປະຊາຊົນລາວ. ກຸງວຽງຈັນ. ຂໍຂອບໃຈ.';
      } else {
        request.fields['language'] = language;
      }
      request.files
          .add(await http.MultipartFile.fromPath('file', wavPath,
              filename: 'audio.wav'));

      onProgress?.call('Whisper ກຳລັງຈັບເວລາ...');
      final res = await request.send().timeout(const Duration(minutes: 5));
      final body = await res.stream.bytesToString();
      try {
        wavFile.deleteSync();
      } catch (_) {}
      if (res.statusCode != 200) return empty;

      final data = jsonDecode(body) as Map<String, dynamic>;
      final words = data['words'] as List<dynamic>?;
      final starts = <int>[];
      int endMs = 0;
      if (words != null) {
        for (final w in words) {
          final m = w as Map<String, dynamic>;
          final s = ((m['start'] as num? ?? 0) * 1000).toInt();
          final e = ((m['end'] as num? ?? 0) * 1000).toInt();
          starts.add(s);
          if (e > endMs) endMs = e;
        }
        starts.sort();
      }

      // Phrase-level windows (natural pauses) — best for matching duration.
      final regions = <List<int>>[];
      final segs = data['segments'] as List<dynamic>?;
      if (segs != null) {
        for (final seg in segs) {
          final m = seg as Map<String, dynamic>;
          final s = ((m['start'] as num? ?? 0) * 1000).toInt();
          final e = ((m['end'] as num? ?? 0) * 1000).toInt();
          if (e > s) regions.add([s, e]);
          if (e > endMs) endMs = e;
        }
        regions.sort((a, b) => a[0].compareTo(b[0]));
      }
      if (starts.isEmpty && regions.isEmpty) return empty;
      return (startsMs: starts, endMs: endMs, regions: regions);
    } catch (_) {
      try {
        if (wavFile.existsSync()) wavFile.deleteSync();
      } catch (_) {}
      return empty;
    }
  }

  List<SubtitleSegment> _parseResponse(Map<String, dynamic> data) {
    // 1. Use segment timestamps — reliable for all languages including Lao
    final segs = data['segments'] as List<dynamic>?;
    if (segs != null && segs.isNotEmpty) {
      return _buildFromSegments(segs);
    }

    // 2. Fallback to word-level timestamps if segments are missing
    final words = data['words'] as List<dynamic>?;
    if (words != null && words.isNotEmpty) {
      return _buildFromWords(words);
    }

    // 3. Fallback: no timestamps at all
    var text = (data['text'] as String? ?? '').trim();
    if (_isThai(text)) text = _thaiToLao(text);
    final duration = (data['duration'] as num?)?.toDouble() ?? 3.0;
    return text.isEmpty
        ? []
        : [
            SubtitleSegment(
              id: _uuid.v4(),
              text: text,
              startTime: Duration.zero,
              endTime: Duration(milliseconds: (duration * 1000).toInt()),
            )
          ];
  }

  List<SubtitleSegment> _buildFromSegments(List<dynamic> segs) {
    final result = <SubtitleSegment>[];
    for (final s in segs) {
      final startMs = ((s['start'] as num? ?? 0) * 1000).toInt();
      final endMs = ((s['end'] as num? ?? 0) * 1000).toInt();
      var text = (s['text'] as String? ?? '').trim();
      if (text.isEmpty) continue;
      if (_isThai(text)) text = _thaiToLao(text);
      result.add(SubtitleSegment(
        id: _uuid.v4(),
        text: text,
        startTime: Duration(milliseconds: startMs),
        endTime: Duration(
            milliseconds: endMs > startMs ? endMs : startMs + 3000),
      ));
    }
    return result;
  }

  List<SubtitleSegment> _buildFromWords(List<dynamic> words) {
    final segments = <SubtitleSegment>[];
    final chunk = <Map<String, dynamic>>[];
    int prevEndMs = 0;

    for (final w in words) {
      // OpenAI returns start/end in seconds (float)
      final startMs = ((w['start'] as num? ?? 0) * 1000).toInt();
      final endMs = ((w['end'] as num? ?? 0) * 1000).toInt();
      final wordText = (w['word'] as String? ?? '').trim();
      if (wordText.isEmpty) continue;

      final gap = startMs - prevEndMs;

      // New segment on pause > 500ms or 5 words
      if (chunk.isNotEmpty && (gap > 500 || chunk.length >= 5)) {
        segments.add(_makeSegment(chunk));
        chunk.clear();
      }

      chunk.add({'text': wordText, 'start': startMs, 'end': endMs});
      prevEndMs = endMs;
    }

    if (chunk.isNotEmpty) segments.add(_makeSegment(chunk));
    return segments;
  }

  static const _thaiLaoMap = {
    'ก': 'ກ', 'ข': 'ຂ', 'ฃ': 'ຂ', 'ค': 'ຄ', 'ฅ': 'ຄ', 'ฆ': 'ຄ',
    'ง': 'ງ', 'จ': 'ຈ', 'ฉ': 'ສ', 'ช': 'ຊ', 'ซ': 'ຊ', 'ฌ': 'ຊ',
    'ญ': 'ຍ', 'ฎ': 'ດ', 'ฏ': 'ຕ', 'ฐ': 'ຖ', 'ฑ': 'ທ', 'ฒ': 'ທ',
    'ณ': 'ນ', 'ด': 'ດ', 'ต': 'ຕ', 'ถ': 'ຖ', 'ท': 'ທ', 'ธ': 'ທ',
    'น': 'ນ', 'บ': 'ບ', 'ป': 'ປ', 'ผ': 'ຜ', 'ฝ': 'ຝ', 'พ': 'ພ',
    'ฟ': 'ຟ', 'ภ': 'ພ', 'ม': 'ມ', 'ย': 'ຍ', 'ร': 'ຣ', 'ล': 'ລ',
    'ว': 'ວ', 'ศ': 'ສ', 'ษ': 'ສ', 'ส': 'ສ', 'ห': 'ຫ', 'ฬ': 'ລ',
    'อ': 'ອ', 'ฮ': 'ຮ', 'ะ': 'ະ', 'ั': 'ັ', 'า': 'າ', 'ำ': 'ຳ',
    'ิ': 'ິ', 'ี': 'ີ', 'ึ': 'ຶ', 'ื': 'ື', 'ุ': 'ຸ', 'ู': 'ູ',
    'เ': 'ເ', 'แ': 'ແ', 'โ': 'ໂ', 'ใ': 'ໃ', 'ไ': 'ໄ', 'ๆ': 'ໆ',
    '็': '໋', '่': '່', '้': '້', '๊': '໊', '๋': '໋', '์': '໌',
    '๐': '໐', '๑': '໑', '๒': '໒', '๓': '໓', '๔': '໔',
    '๕': '໕', '๖': '໖', '๗': '໗', '๘': '໘', '๙': '໙',
  };

  bool _isThai(String text) =>
      text.runes.any((r) => r >= 0x0E00 && r <= 0x0E7F);

  String _thaiToLao(String text) =>
      text.split('').map((c) => _thaiLaoMap[c] ?? c).join('');

  SubtitleSegment _makeSegment(List<Map<String, dynamic>> words) {
    final wordList = words.map((w) {
      var t = (w['text'] as String).trim();
      if (_isThai(t)) t = _thaiToLao(t);
      return t;
    }).toList();

    final text = joinWordsSmart(wordList);
    
    return SubtitleSegment(
      id: _uuid.v4(),
      text: text,
      startTime: Duration(milliseconds: words.first['start'] as int),
      endTime: Duration(milliseconds: words.last['end'] as int),
      words: wordList,
      wordTimings: words.map((w) => Duration(milliseconds: w['start'] as int)).toList(),
    );
  }

  List<SubtitleSegment> _splitByWords(
      List<SubtitleSegment> segs, WordSplit split) {
    final wordsPerLine = switch (split) {
      WordSplit.one => 1,
      WordSplit.two => 2,
      WordSplit.three => 3,
      WordSplit.four => 4,
      WordSplit.six => 6,
      WordSplit.eight => 8,
      WordSplit.none => 999,
    };
    final result = <SubtitleSegment>[];
    for (final seg in segs) {
      final words = seg.words ?? seg.text.split(' ').where((w) => w.isNotEmpty).toList();
      if (words.length <= wordsPerLine) {
        result.add(seg);
        continue;
      }
      final total = seg.endTime - seg.startTime;
      final chunks = (words.length / wordsPerLine).ceil();
      final chunkDur = total ~/ chunks;

      final timings = seg.wordTimings;

      for (int i = 0; i < chunks; i++) {
        final s = i * wordsPerLine;
        final e = (s + wordsPerLine).clamp(0, words.length);
        final chunkWords = words.sublist(s, e);
        final chunkStartTime = (timings != null && timings.length == words.length)
            ? timings[s]
            : seg.startTime + (chunkDur * i);
        final chunkEndTime = (timings != null && timings.length == words.length && e < words.length)
            ? timings[e]
            : (i == chunks - 1 ? seg.endTime : seg.startTime + (chunkDur * (i + 1)));

        result.add(SubtitleSegment(
          id: _uuid.v4(),
          text: joinWordsSmart(chunkWords),
          startTime: chunkStartTime,
          endTime: chunkEndTime,
          words: chunkWords,
          wordTimings: (timings != null && timings.length == words.length)
              ? timings.sublist(s, e)
              : null,
        ));
      }
    }
    return result;
  }
}
