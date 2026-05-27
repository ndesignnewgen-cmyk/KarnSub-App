import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/subtitle_style_model.dart';

class GoogleSpeechException implements Exception {
  final String message;
  GoogleSpeechException(this.message);
  @override
  String toString() => message;
}

class GoogleSpeechService {
  static const _channel = MethodChannel('com.anniekaydee.subtitle_app/audio');
  static const _endpoint =
      'https://speech.googleapis.com/v1/speech:recognize';

  final String apiKey;
  final _uuid = const Uuid();

  GoogleSpeechService({required this.apiKey});

  Future<List<SubtitleSegment>> transcribe(
    String videoPath, {
    String language = 'lo-LA',
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
      throw GoogleSpeechException('ດຶງສຽງບໍ່ສໍາເລັດ: ${e.message}');
    }

    final wavFile = File(wavPath);
    if (!wavFile.existsSync()) {
      throw GoogleSpeechException('ໄຟລ໌ audio ສ້າງບໍ່ສໍາເລັດ');
    }

    final fileSize = await wavFile.length();
    if (fileSize > 10 * 1024 * 1024) {
      wavFile.deleteSync();
      throw GoogleSpeechException(
          'ໄຟລ໌ audio ໃຫຍ່ເກີນ 10MB — ກາລຸນາໃຊ້ວິດີໂອສັ້ນກວ່ານີ້ (ບໍ່ເກີນ ~60 ວິນາທີ)');
    }

    onProgress?.call('ກໍາລັງສົ່ງສຽງໄປ Google...');

    final bytes = await wavFile.readAsBytes();
    wavFile.deleteSync();

    int sampleRate = 16000;
    if (bytes.length >= 28) {
      sampleRate = bytes[24] |
          (bytes[25] << 8) |
          (bytes[26] << 16) |
          (bytes[27] << 24);
    }

    final audioBase64 = base64Encode(bytes);

    final body = jsonEncode({
      'config': {
        'encoding': 'LINEAR16',
        'sampleRateHertz': sampleRate,
        'languageCode': language,
        'enableWordTimeOffsets': true,
        'model': 'default',
      },
      'audio': {
        'content': audioBase64,
      },
    });

    onProgress?.call('Google Speech ຖອດສຽງ...');

    final uri = Uri.parse('$_endpoint?key=$apiKey');
    final httpClient = HttpClient();
    final request = await httpClient.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(body);
    final response = await request.close().timeout(const Duration(minutes: 3));

    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode == 400) {
      final err = jsonDecode(responseBody);
      final msg = err['error']?['message'] ?? 'Bad request';
      throw GoogleSpeechException('Google error: $msg');
    }
    if (response.statusCode == 403) {
      throw GoogleSpeechException(
          'API Key ບໍ່ຖືກຕ້ອງ ຫຼື ຍັງບໍ່ໄດ້ເປີດ Speech-to-Text API');
    }
    if (response.statusCode == 429) {
      throw GoogleSpeechException('ເກີນ quota — ລໍຖ້າສັກຄູ່ແລ້ວລອງໃໝ່');
    }
    if (response.statusCode != 200) {
      throw GoogleSpeechException(
          'Google error ${response.statusCode}: $responseBody');
    }

    onProgress?.call('ກໍາລັງສ້າງ Subtitle...');

    final data = jsonDecode(responseBody) as Map<String, dynamic>;
    var segments = _parseResponse(data);

    if (wordSplit != WordSplit.none) {
      segments = _splitByWords(segments, wordSplit);
    }
    return segments;
  }

  List<SubtitleSegment> _parseResponse(Map<String, dynamic> data) {
    final results = data['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return [];

    final allWords = <Map<String, dynamic>>[];
    for (final result in results) {
      final alternatives = result['alternatives'] as List<dynamic>?;
      if (alternatives == null || alternatives.isEmpty) continue;
      final words = alternatives[0]['words'] as List<dynamic>?;
      if (words != null) {
        allWords.addAll(words.cast<Map<String, dynamic>>());
      }
    }

    if (allWords.isEmpty) {
      final buffer = StringBuffer();
      for (final result in results) {
        final alternatives = result['alternatives'] as List<dynamic>?;
        if (alternatives != null && alternatives.isNotEmpty) {
          buffer.write(alternatives[0]['transcript'] as String? ?? '');
        }
      }
      final text = buffer.toString().trim();
      if (text.isEmpty) return [];
      return [
        SubtitleSegment(
          id: _uuid.v4(),
          text: text,
          startTime: Duration.zero,
          endTime: const Duration(seconds: 5),
        )
      ];
    }

    return _buildFromWords(allWords);
  }

  List<SubtitleSegment> _buildFromWords(List<Map<String, dynamic>> words) {
    final segments = <SubtitleSegment>[];
    final chunk = <Map<String, dynamic>>[];
    int prevEndMs = 0;

    for (final w in words) {
      final startMs = _parseTimeMs(w['startTime'] as String? ?? '0s');
      final endMs = _parseTimeMs(w['endTime'] as String? ?? '0s');
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

  int _parseTimeMs(String t) {
    final s = t.replaceAll('s', '');
    return ((double.tryParse(s) ?? 0) * 1000).toInt();
  }

  SubtitleSegment _makeSegment(List<Map<String, dynamic>> words) {
    final text =
        words.map((w) => (w['text'] as String).trim()).join(' ').trim();
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
