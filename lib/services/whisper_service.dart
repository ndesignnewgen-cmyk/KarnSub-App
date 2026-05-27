import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/subtitle_style_model.dart';

class WhisperException implements Exception {
  final String message;
  WhisperException(this.message);
  @override
  String toString() => message;
}

class WhisperService {
  static const _endpoint = 'https://api.openai.com/v1/audio/transcriptions';
  final String apiKey;
  final _uuid = const Uuid();

  WhisperService({required this.apiKey});

  /// ຖອດສຽງຈາກ video/audio file
  /// ຄືນ List<SubtitleSegment> ພ້ອມ timestamp
  Future<List<SubtitleSegment>> transcribe(
    String filePath, {
    String language = '',         // '' = auto-detect, 'lo'=ລາວ, 'th'=ໄທ, 'en'=ອັງກິດ
    WordSplit wordSplit = WordSplit.none,
    void Function(String status)? onStatus,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw WhisperException('ບໍ່ພົບໄຟລ໌: $filePath');
    }

    onStatus?.call('ກຳລັງ Upload ໄຟລ໌...');

    final request = http.MultipartRequest('POST', Uri.parse(_endpoint));
    request.headers['Authorization'] = 'Bearer $apiKey';

    request.fields['model'] = 'whisper-1';
    request.fields['response_format'] = 'verbose_json';
    request.fields['timestamp_granularities[]'] = 'segment';
    if (language.isNotEmpty) {
      request.fields['language'] = language;
    }

    request.files.add(await http.MultipartFile.fromPath('file', filePath));

    onStatus?.call('AI ກຳລັງຖອດສຽງ...');

    final streamedResponse = await request.send().timeout(
      const Duration(minutes: 5),
      onTimeout: () => throw WhisperException('ໃຊ້ເວລານານເກີນ — ລອງໃໝ່'),
    );

    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      final msg = body['error']?['message'] ?? 'Unknown error';
      throw WhisperException('Whisper API Error: $msg');
    }

    onStatus?.call('ກຳລັງສ້າງ Subtitle...');

    final data = jsonDecode(response.body);
    final rawSegments = data['segments'] as List<dynamic>;

    List<SubtitleSegment> segments = rawSegments.map((seg) {
      return SubtitleSegment(
        id: _uuid.v4(),
        text: (seg['text'] as String).trim(),
        startTime: _secondsToDuration(seg['start'] as num),
        endTime: _secondsToDuration(seg['end'] as num),
      );
    }).toList();

    // ແບ່ງຄຳຕາມ wordSplit setting
    if (wordSplit != WordSplit.none) {
      segments = _splitByWords(segments, wordSplit);
    }

    return segments;
  }

  List<SubtitleSegment> _splitByWords(
      List<SubtitleSegment> segments, WordSplit split) {
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

    for (final seg in segments) {
      final words = seg.text.split(' ').where((w) => w.isNotEmpty).toList();
      if (words.length <= wordsPerLine) {
        result.add(seg);
        continue;
      }

      final totalDuration = seg.endTime - seg.startTime;
      final chunkCount = (words.length / wordsPerLine).ceil();
      final chunkDuration = totalDuration ~/ chunkCount;

      for (int i = 0; i < chunkCount; i++) {
        final start = i * wordsPerLine;
        final end = (start + wordsPerLine).clamp(0, words.length);
        final chunkWords = words.sublist(start, end);
        final chunkStart = seg.startTime + (chunkDuration * i);
        final chunkEnd = i == chunkCount - 1
            ? seg.endTime
            : seg.startTime + (chunkDuration * (i + 1));

        result.add(SubtitleSegment(
          id: _uuid.v4(),
          text: chunkWords.join(' '),
          startTime: chunkStart,
          endTime: chunkEnd,
        ));
      }
    }

    return result;
  }

  Duration _secondsToDuration(num seconds) {
    final ms = (seconds * 1000).round();
    return Duration(milliseconds: ms);
  }
}
