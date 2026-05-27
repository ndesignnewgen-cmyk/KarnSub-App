import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/subtitle_style_model.dart';

class AssemblyAIException implements Exception {
  final String message;
  AssemblyAIException(this.message);
  @override
  String toString() => message;
}

class AssemblyAIService {
  static const _channel = MethodChannel('com.anniekaydee.subtitle_app/audio');
  static const _baseUrl = 'https://api.assemblyai.com/v2';

  final String apiKey;
  final _uuid = const Uuid();

  AssemblyAIService({required this.apiKey});

  Map<String, String> get _headers => {
        'Authorization': apiKey,
        'Content-Type': 'application/json',
      };

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
      throw AssemblyAIException('ດຶງສຽງບໍ່ສຳເລັດ: ${e.message}');
    }

    final wavFile = File(wavPath);
    if (!wavFile.existsSync()) {
      throw AssemblyAIException('ໄຟລ໌ audio ສ້າງບໍ່ສຳເລັດ');
    }

    final wavBytes = await wavFile.readAsBytes();
    wavFile.deleteSync();

    // Step 2: Upload audio
    onProgress?.call('ກຳລັງ Upload ສຽງ...');
    final uploadUri = Uri.parse('$_baseUrl/upload');
    final uploadReq = http.StreamedRequest('POST', uploadUri);
    uploadReq.headers['Authorization'] = apiKey;
    uploadReq.headers['Content-Type'] = 'application/octet-stream';
    uploadReq.headers['Content-Length'] = wavBytes.length.toString();

    // send() must be called BEFORE adding data to avoid deadlock
    final client = http.Client();
    final sendFuture = client.send(uploadReq).timeout(const Duration(minutes: 5));
    uploadReq.sink.add(wavBytes);
    await uploadReq.sink.close();

    final uploadStreamedRes = await sendFuture;
    final uploadBody = await uploadStreamedRes.stream.bytesToString();
    client.close();

    if (uploadStreamedRes.statusCode == 401) {
      throw AssemblyAIException('API Key ບໍ່ຖືກຕ້ອງ');
    }
    if (uploadStreamedRes.statusCode != 200) {
      throw AssemblyAIException(
          'Upload ລົ້ມເຫຼວ (${uploadStreamedRes.statusCode}): $uploadBody');
    }

    final audioUrl =
        (jsonDecode(uploadBody) as Map<String, dynamic>)['upload_url']
            as String;

    // Step 3: Submit transcription
    onProgress?.call('AssemblyAI ກຳລັງຖອດສຽງ...');

    final body = <String, dynamic>{
      'audio_url': audioUrl,
      'speech_models': ['universal-2'],
      'format_text': false,
    };

    // AssemblyAI: use language_detection for better accuracy on Lao
    if (language == 'lo') {
      body['language_detection'] = true;
    } else {
      body['language_code'] = language;
    }

    final transcriptRes = await http
        .post(
          Uri.parse('$_baseUrl/transcript'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    if (transcriptRes.statusCode != 200) {
      final err = jsonDecode(transcriptRes.body);
      throw AssemblyAIException(
          'ສ້າງ job ລົ້ມເຫຼວ: ${err['error'] ?? transcriptRes.statusCode}');
    }

    final transcriptId =
        (jsonDecode(transcriptRes.body) as Map<String, dynamic>)['id']
            as String;

    // Step 4: Poll for completion
    while (true) {
      await Future.delayed(const Duration(seconds: 3));

      final pollRes = await http
          .get(
            Uri.parse('$_baseUrl/transcript/$transcriptId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));

      final data =
          jsonDecode(pollRes.body) as Map<String, dynamic>;
      final status = data['status'] as String?;

      if (status == 'completed') {
        onProgress?.call('ກຳລັງສ້າງ Subtitle...');
        var segments = _parseResponse(data);
        if (wordSplit != WordSplit.none) {
          segments = _splitByWords(segments, wordSplit);
        }
        return segments;
      } else if (status == 'error') {
        throw AssemblyAIException(
            'ຖອດສຽງລົ້ມເຫຼວ: ${data['error'] ?? 'unknown error'}');
      }
      // status == 'queued' or 'processing' — keep polling
    }
  }

  static const _thaiLaoMap = {
    'ก': 'ກ', 'ข': 'ຂ', 'ฃ': 'ຂ', 'ค': 'ຄ', 'ฅ': 'ຄ', 'ฆ': 'ຄ',
    'ง': 'ງ', 'จ': 'ຈ', 'ฉ': 'ສ', 'ช': 'ຊ', 'ซ': 'ຊ', 'ฌ': 'ຊ',
    'ญ': 'ຍ', 'ฎ': 'ດ', 'ฏ': 'ຕ', 'ฐ': 'ຖ', 'ฑ': 'ທ', 'ฒ': 'ທ',
    'ณ': 'ນ', 'ด': 'ດ', 'ต': 'ຕ', 'ถ': 'ຖ', 'ท': 'ທ', 'ธ': 'ທ',
    'น': 'ນ', 'บ': 'ບ', 'ป': 'ປ', 'ผ': 'ຜ', 'ฝ': 'ຝ', 'พ': 'ພ',
    'ฟ': 'ຟ', 'ภ': 'ພ', 'ม': 'ມ', 'ย': 'ຍ', 'ร': 'ຣ', 'ล': 'ລ',
    'ว': 'ວ', 'ศ': 'ສ', 'ษ': 'ສ', 'ส': 'ສ', 'ห': 'ຫ', 'ฬ': 'ລ',
    'อ': 'ອ', 'ฮ': 'ຮ', 'ฯ': 'ฯ', 'ะ': 'ະ', 'ั': 'ັ', 'า': 'າ',
    'ำ': 'ຳ', 'ิ': 'ິ', 'ี': 'ີ', 'ึ': 'ຶ', 'ื': 'ື', 'ุ': 'ຸ',
    'ู': 'ູ', 'เ': 'ເ', 'แ': 'ແ', 'โ': 'ໂ', 'ใ': 'ໃ', 'ไ': 'ໄ',
    'ๆ': 'ໆ', '็': '໋', '่': '່', '้': '້', '๊': '໊', '๋': '໋',
    '์': '໌', 'ํ': 'ํ',
    '๐': '໐', '๑': '໑', '๒': '໒', '๓': '໓', '๔': '໔',
    '๕': '໕', '๖': '໖', '๗': '໗', '๘': '໘', '๙': '໙',
  };

  String _thaiToLao(String text) =>
      text.split('').map((c) => _thaiLaoMap[c] ?? c).join('');

  bool _isThai(String text) =>
      text.runes.any((r) => r >= 0x0E00 && r <= 0x0E7F);

  List<SubtitleSegment> _parseResponse(Map<String, dynamic> data) {
    final words = data['words'] as List<dynamic>?;

    if (words != null && words.isNotEmpty) {
      return _buildFromWords(words);
    }

    var text = (data['text'] as String? ?? '').trim();
    if (_isThai(text)) text = _thaiToLao(text);
    final duration = (data['audio_duration'] as num?)?.toInt() ?? 3;
    return text.isEmpty
        ? []
        : [
            SubtitleSegment(
              id: _uuid.v4(),
              text: text,
              startTime: Duration.zero,
              endTime: Duration(seconds: duration),
            )
          ];
  }

  List<SubtitleSegment> _buildFromWords(List<dynamic> words) {
    final segments = <SubtitleSegment>[];
    final chunk = <Map<String, dynamic>>[];
    int prevEndMs = 0;

    for (final w in words) {
      final startMs = (w['start'] as num? ?? 0).toInt();
      final endMs = (w['end'] as num? ?? 0).toInt();
      var wordText = (w['text'] as String? ?? '').trim();
      if (wordText.isEmpty) continue;
      if (_isThai(wordText)) wordText = _thaiToLao(wordText);

      final gap = startMs - prevEndMs;

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
