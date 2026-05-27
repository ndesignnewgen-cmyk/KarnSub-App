import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/subtitle_style_model.dart';

class AzureSpeechException implements Exception {
  final String message;
  AzureSpeechException(this.message);
  @override
  String toString() => message;
}

class AzureSpeechService {
  static const _channel = MethodChannel('com.anniekaydee.subtitle_app/audio');

  final String apiKey;
  final String region;
  final _uuid = const Uuid();

  AzureSpeechService({required this.apiKey, required this.region});

  String get _endpoint =>
      'https://$region.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1';

  Future<List<SubtitleSegment>> transcribe(
    String videoPath, {
    String language = 'lo-LA',
    WordSplit wordSplit = WordSplit.none,
    void Function(String)? onProgress,
  }) async {
    // Step 1: Extract audio via native Android
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
      throw AzureSpeechException('ດຶງສຽງບໍ່ສຳເລັດ: ${e.message}');
    }

    final wavFile = File(wavPath);
    if (!wavFile.existsSync()) {
      throw AzureSpeechException('ໄຟລ໌ audio ສ້າງບໍ່ສຳເລັດ');
    }

    final wavBytes = await wavFile.readAsBytes();
    wavFile.deleteSync();

    // Azure REST API limit: ~60 seconds of audio
    final sampleRate = _readWavSampleRate(wavBytes);
    final channels = _readWavChannels(wavBytes);
    final durationSec =
        (wavBytes.length - 44) / (sampleRate * channels * 2.0);

    if (durationSec > 58) {
      throw AzureSpeechException(
          'ວິດີໂອຍາວ ${durationSec.toInt()} ວິ — Azure REST API ຮອງຮັບສູງສຸດ 58 ວິ\nກາລຸນາໃຊ້ຄລິບ < 1 ນາທີ');
    }

    onProgress?.call('ກຳລັງ Upload ສຽງ...');
    onProgress?.call('Azure AI ກຳລັງຖອດສຽງ...');

    // Step 2: Call Azure Speech REST API
    final uri = Uri.parse(
        '$_endpoint?language=$language&format=detailed&profanity=raw');

    final response = await http
        .post(
          uri,
          headers: {
            'Ocp-Apim-Subscription-Key': apiKey,
            'Content-Type':
                'audio/wav; codecs=audio/pcm; samplerate=$sampleRate',
            'Accept': 'application/json',
          },
          body: wavBytes,
        )
        .timeout(const Duration(minutes: 3));

    if (response.statusCode == 401) {
      throw AzureSpeechException('API Key ບໍ່ຖືກຕ້ອງ ຫຼື Region ຜິດ');
    }
    if (response.statusCode == 400) {
      throw AzureSpeechException(
          'Azure ບໍ່ຮອງຮັບ format ນີ້: ${response.body}');
    }
    if (response.statusCode != 200) {
      throw AzureSpeechException(
          'Azure Speech error ${response.statusCode}: ${response.body}');
    }

    onProgress?.call('ກຳລັງສ້າງ Subtitle...');

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final status = data['RecognitionStatus'] as String?;

    if (status == 'NoMatch' || status == 'InitialSilenceTimeout') {
      throw AzureSpeechException('ບໍ່ພົບສຽງໃນໄຟລ໌ — ກວດສອບວ່າວິດີໂອມີສຽງ');
    }
    if (status != 'Success') {
      throw AzureSpeechException('Azure: ຖອດສຽງບໍ່ສຳເລັດ ($status)');
    }

    // Step 3: Parse word-level timestamps
    var segments = _parseResponse(data);

    if (wordSplit != WordSplit.none) {
      segments = _splitByWords(segments, wordSplit);
    }
    return segments;
  }

  List<SubtitleSegment> _parseResponse(Map<String, dynamic> data) {
    final nbest = data['NBest'] as List<dynamic>?;

    if (nbest != null && nbest.isNotEmpty) {
      final best = nbest.first as Map<String, dynamic>;
      final words = best['Words'] as List<dynamic>?;

      if (words != null && words.isNotEmpty) {
        return _buildFromWords(words);
      }

      // Fallback: no word timestamps
      final text = (best['Display'] as String? ?? '').trim();
      final totalTicks = (data['Duration'] as num? ?? 0).toInt();
      if (text.isNotEmpty) {
        return [
          SubtitleSegment(
            id: _uuid.v4(),
            text: text,
            startTime: Duration.zero,
            endTime: _ticksToDuration(totalTicks),
          )
        ];
      }
    }

    final text = (data['DisplayText'] as String? ?? '').trim();
    return text.isEmpty
        ? []
        : [
            SubtitleSegment(
              id: _uuid.v4(),
              text: text,
              startTime: Duration.zero,
              endTime: const Duration(seconds: 3),
            )
          ];
  }

  List<SubtitleSegment> _buildFromWords(List<dynamic> words) {
    final segments = <SubtitleSegment>[];
    final chunk = <Map<String, dynamic>>[];
    int prevEndMs = 0;

    for (final w in words) {
      final offsetTicks = (w['Offset'] as num? ?? 0).toInt();
      final durTicks = (w['Duration'] as num? ?? 0).toInt();
      final startMs = offsetTicks ~/ 10000;
      final endMs = (offsetTicks + durTicks) ~/ 10000;
      final wordText = (w['Word'] as String? ?? '').trim();
      if (wordText.isEmpty) continue;

      final gap = startMs - prevEndMs;

      // New segment on pause > 600ms or chunk reaches 7 words
      if (chunk.isNotEmpty && (gap > 600 || chunk.length >= 7)) {
        segments.add(_makeSegment(chunk));
        chunk.clear();
      }

      chunk.add({'text': wordText, 'start': startMs, 'end': endMs});
      prevEndMs = endMs;
    }

    if (chunk.isNotEmpty) segments.add(_makeSegment(chunk));
    return segments;
  }

  SubtitleSegment _makeSegment(List<Map<String, dynamic>> words) =>
      SubtitleSegment(
        id: _uuid.v4(),
        text: words.map((w) => w['text'] as String).join(' ').trim(),
        startTime: Duration(milliseconds: words.first['start'] as int),
        endTime: Duration(milliseconds: words.last['end'] as int),
      );

  Duration _ticksToDuration(int ticks) =>
      Duration(milliseconds: ticks ~/ 10000);

  int _readWavSampleRate(Uint8List bytes) {
    if (bytes.length < 28) return 44100;
    return ByteData.sublistView(bytes, 24, 28).getInt32(0, Endian.little);
  }

  int _readWavChannels(Uint8List bytes) {
    if (bytes.length < 24) return 1;
    return ByteData.sublistView(bytes, 22, 24).getInt16(0, Endian.little);
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
