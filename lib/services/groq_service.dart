import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/subtitle_style_model.dart';

class GroqException implements Exception {
  final String message;
  GroqException(this.message);
  @override
  String toString() => message;
}

class GroqService {
  static const _endpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';
  // whisper-large-v3-turbo: ໄວ + ຟຣີ 7200 ວິ/ວັນ
  static const _model = 'whisper-large-v3-turbo';

  final String apiKey;
  final _uuid = const Uuid();

  GroqService({required this.apiKey});

  Future<List<SubtitleSegment>> transcribe(
    String filePath, {
    String language = '',
    WordSplit wordSplit = WordSplit.none,
    void Function(String status)? onProgress,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw GroqException('ບໍ່ພົບໄຟລ໌: $filePath');
    }

    onProgress?.call('ກຳລັງ Upload ໄຟລ໌...');

    final request = http.MultipartRequest('POST', Uri.parse(_endpoint));
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['model'] = _model;
    request.fields['response_format'] = 'verbose_json';
    request.fields['timestamp_granularities[]'] = 'segment';
    if (language.isNotEmpty) request.fields['language'] = language;

    request.files.add(await http.MultipartFile.fromPath('file', filePath));

    onProgress?.call('AI ກຳລັງຖອດສຽງ...');

    final streamed = await request.send().timeout(
      const Duration(minutes: 10),
      onTimeout: () => throw GroqException('Timeout — ລອງໃໝ່'),
    );
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      final msg = body['error']?['message'] ?? response.body;
      throw GroqException('Groq error: $msg');
    }

    onProgress?.call('ກຳລັງສ້າງ Subtitle...');

    final data = jsonDecode(response.body);
    final rawSegments = data['segments'] as List<dynamic>;

    List<SubtitleSegment> segments = rawSegments.map((seg) {
      String text = (seg['text'] as String).trim();
      if (language == 'lo') text = _thaiToLao(text);
      return SubtitleSegment(
        id: _uuid.v4(),
        text: text,
        startTime: _toDuration(seg['start'] as num),
        endTime: _toDuration(seg['end'] as num),
      );
    }).toList();

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

  static const _thaiLaoMap = {
    // Consonants
    'ก': 'ກ', 'ข': 'ຂ', 'ฃ': 'ຂ', 'ค': 'ຄ', 'ฅ': 'ຄ', 'ฆ': 'ຄ',
    'ง': 'ງ', 'จ': 'ຈ', 'ฉ': 'ສ', 'ช': 'ຊ', 'ซ': 'ຊ', 'ฌ': 'ຊ',
    'ญ': 'ຍ', 'ฎ': 'ດ', 'ฏ': 'ຕ', 'ฐ': 'ຖ', 'ฑ': 'ທ', 'ฒ': 'ທ',
    'ณ': 'ນ', 'ด': 'ດ', 'ต': 'ຕ', 'ถ': 'ຖ', 'ท': 'ທ', 'ธ': 'ທ',
    'น': 'ນ', 'บ': 'ບ', 'ป': 'ປ', 'ผ': 'ຜ', 'ฝ': 'ຝ', 'พ': 'ພ',
    'ฟ': 'ຟ', 'ภ': 'ພ', 'ม': 'ມ', 'ย': 'ຍ', 'ร': 'ຣ', 'ล': 'ລ',
    'ว': 'ວ', 'ศ': 'ສ', 'ษ': 'ສ', 'ส': 'ສ', 'ห': 'ຫ', 'ฬ': 'ລ',
    'อ': 'ອ', 'ฮ': 'ຮ',
    // Vowels
    'ะ': 'ະ', 'ั': 'ັ', 'า': 'າ', 'ำ': 'ຳ',
    'ิ': 'ິ', 'ี': 'ີ', 'ึ': 'ຶ', 'ื': 'ື',
    'ุ': 'ຸ', 'ู': 'ູ', '็': 'ັ',
    'เ': 'ເ', 'แ': 'ແ', 'โ': 'ໂ', 'ใ': 'ໃ', 'ไ': 'ໄ',
    'ๆ': 'ໆ',
    // Tone marks
    '่': '່', '้': '້', '๊': '໊', '๋': '໋',
    // Final marks
    '์': '໌', 'ํ': 'ໍ',
    // Digits
    '๐': '໐', '๑': '໑', '๒': '໒', '๓': '໓', '๔': '໔',
    '๕': '໕', '๖': '໖', '๗': '໗', '๘': '໘', '๙': '໙',
  };

  String _thaiToLao(String text) =>
      text.split('').map((c) => _thaiLaoMap[c] ?? c).join('');

  Duration _toDuration(num seconds) =>
      Duration(milliseconds: (seconds * 1000).round());
}
