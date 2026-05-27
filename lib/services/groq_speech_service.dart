import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/subtitle_style_model.dart';

class GroqSpeechException implements Exception {
  final String message;
  GroqSpeechException(this.message);
  @override
  String toString() => message;
}

class GroqSpeechService {
  static const _channel = MethodChannel('com.anniekaydee.subtitle_app/audio');
  static const _endpoint = 'https://api.groq.com/openai/v1/audio/transcriptions';

  final String apiKey;
  final _uuid = const Uuid();

  GroqSpeechService({required this.apiKey});

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
      throw GroqSpeechException('ດຶງສຽງບໍ່ສໍາເລັດ: ${e.message}');
    }

    final wavFile = File(wavPath);
    if (!wavFile.existsSync()) {
      throw GroqSpeechException('ໄຟລ໌ audio ສ້າງບໍ່ສໍາເລັດ');
    }

    final fileSize = await wavFile.length();
    if (fileSize > 25 * 1024 * 1024) {
      wavFile.deleteSync();
      throw GroqSpeechException(
          'ໄຟລ໌ audio ໃຫຍ່ເກີນ 25MB — ກາລຸນາໃຊ້ວິດີໂອສັ້ນກວ່ານີ້');
    }

    onProgress?.call('ກໍາລັງ Upload ສຽງ...');

    final request = http.MultipartRequest('POST', Uri.parse(_endpoint));
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['model'] = 'whisper-large-v3';
    request.fields['response_format'] = 'verbose_json';
    request.fields['timestamp_granularities[]'] = 'segment';

    if (language == 'lo') {
      request.fields['prompt'] =
          'ພາສາລາວ. ສາທາລະນະລັດ ປະຊາທິປະໄຕ ປະຊາຊົນລາວ. ກຸງວຽງຈັນ. ຂໍຂອບໃຈ.';
    } else {
      request.fields['language'] = language;
    }

    request.files.add(await http.MultipartFile.fromPath(
        'file', wavPath,
        filename: 'audio.wav'));

    onProgress?.call('Groq ກໍາລັງຖອດສຽງ...');

    final streamedRes =
        await request.send().timeout(const Duration(minutes: 5));
    final body = await streamedRes.stream.bytesToString();

    wavFile.deleteSync();

    if (streamedRes.statusCode == 401) {
      throw GroqSpeechException('API Key ບໍ່ຖືກຕ້ອງ');
    }
    if (streamedRes.statusCode == 429) {
      throw GroqSpeechException('ເກີນ rate limit — ລໍຖ້າສັກຄູ່ແລ້ວລອງໃໝ່');
    }
    if (streamedRes.statusCode != 200) {
      final err = jsonDecode(body);
      throw GroqSpeechException(
          'Groq error: ${err['error']?['message'] ?? streamedRes.statusCode}');
    }

    onProgress?.call('ກໍາລັງສ້າງ Subtitle...');

    final data = jsonDecode(body) as Map<String, dynamic>;
    var segments = _parseResponse(data);

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
      // Groq caps uploads at 25MB — skip (caller falls back to energy VAD).
      try {
        wavFile.deleteSync();
      } catch (_) {}
      return empty;
    }

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_endpoint));
      request.headers['Authorization'] = 'Bearer $apiKey';
      request.fields['model'] = 'whisper-large-v3';
      request.fields['response_format'] = 'verbose_json';
      request.fields['timestamp_granularities[]'] = 'word';
      if (language != 'lo') request.fields['language'] = language;
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
    // Use segment timestamps — reliable for all languages including Lao
    final segs = data['segments'] as List<dynamic>?;
    if (segs != null && segs.isNotEmpty) {
      return _buildFromSegments(segs);
    }

    // Fallback: full text, even timing
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
      final startMs = ((w['start'] as num? ?? 0) * 1000).toInt();
      final endMs = ((w['end'] as num? ?? 0) * 1000).toInt();
      final wordText = (w['word'] as String? ?? '').trim();
      if (wordText.isEmpty) continue;

      final gap = startMs - prevEndMs;

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
    'อ': 'ອ', 'ฮ': 'ຮ', 'ะ': 'ະ', 'า': 'າ', 'ำ': 'ຳ',
    'ิ': 'ິ', 'ี': 'ີ', 'ึ': 'ຶ', 'ื': 'ື', 'ุ': 'ຸ', 'ู': 'ູ',
    'เ': 'ເ', 'แ': 'ແ', 'โ': 'ໂ', 'ใ': 'ໃ', 'ไ': 'ໄ', 'ๆ': 'ໆ',
    '็': '໋', '่': '່', '้': '້', '๊': '໊', '๋': '໋', '์': '໌',
    '๐': '໐', '๑': '໑', '๒': '໒', '๓': '໓', '๔': '໔',
    '๕': '໕', '๖': '໖', '๗': '໗', '๘': '໘', '๙': '໙',
    'ั': 'ັ',
  };

  bool _isThai(String text) =>
      text.runes.any((r) => r >= 0x0E00 && r <= 0x0E7F);

  String _thaiToLao(String text) =>
      text.split('').map((c) => _thaiLaoMap[c] ?? c).join('');

  SubtitleSegment _makeSegment(List<Map<String, dynamic>> words) {
    var text = words.map((w) => (w['text'] as String).trim()).join(' ').trim();
    if (_isThai(text)) text = _thaiToLao(text);
    return SubtitleSegment(
      id: _uuid.v4(),
      text: text,
      startTime: Duration(milliseconds: words.first['start'] as int),
      endTime: Duration(milliseconds: words.last['end'] as int),
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
      final words =
          seg.text.split(' ').where((w) => w.isNotEmpty).toList();
      if (words.length <= wordsPerLine) {
        result.add(seg);
        continue;
      }
      final total = seg.endTime - seg.startTime;
      final chunks = (words.length / wordsPerLine).ceil();
      final chunkDur = total ~/ chunks;
      for (int i = 0; i < chunks; i++) {
        final s = i * wordsPerLine;
        final e = (s + wordsPerLine).clamp(0, words.length);
        result.add(SubtitleSegment(
          id: _uuid.v4(),
          text: words.sublist(s, e).join(' '),
          startTime: seg.startTime + (chunkDur * i),
          endTime: i == chunks - 1
              ? seg.endTime
              : seg.startTime + (chunkDur * (i + 1)),
        ));
      }
    }
    return result;
  }
}
