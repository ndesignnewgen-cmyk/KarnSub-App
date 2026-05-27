import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/subtitle_style_model.dart';

class GeminiException implements Exception {
  final String message;
  GeminiException(this.message);
  @override
  String toString() => message;
}

class GeminiService {
  static const _uploadBase =
      'https://generativelanguage.googleapis.com/upload/v1beta/files';
  static const _generateBase =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

  final String apiKey;
  final _uuid = const Uuid();

  GeminiService({required this.apiKey});

  Future<List<SubtitleSegment>> transcribe(
    String filePath, {
    String language = '',
    WordSplit wordSplit = WordSplit.none,
    void Function(String status)? onStatus,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw GeminiException('ບໍ່ພົບໄຟລ໌: $filePath');
    }

    final mimeType = _detectMimeType(filePath);

    onStatus?.call('ກຳລັງ Upload ໄຟລ໌...');
    final fileUri = await _uploadFile(file, mimeType);

    onStatus?.call('AI ກຳລັງຖອດສຽງ...');
    await _waitForFileActive(fileUri);

    onStatus?.call('ກຳລັງສ້າງ Subtitle...');
    final srtText = await _generateTranscription(fileUri, mimeType, language);

    final segments = _parseSrt(srtText);
    if (segments.isEmpty) {
      throw GeminiException('ບໍ່ສາມາດຖອດສຽງໄດ້ — ກາລຸນາລອງໃໝ່');
    }

    if (wordSplit != WordSplit.none) {
      return _splitByWords(segments, wordSplit);
    }
    return segments;
  }

  // ---- Upload File via Gemini File API ----

  Future<String> _uploadFile(File file, String mimeType) async {
    final bytes = await file.readAsBytes();
    final fileName = file.path.split('/').last.split('\\').last;

    // Step 1: Initiate resumable upload
    final initResponse = await http.post(
      Uri.parse('$_uploadBase?key=$apiKey'),
      headers: {
        'X-Goog-Upload-Protocol': 'resumable',
        'X-Goog-Upload-Command': 'start',
        'X-Goog-Upload-Header-Content-Length': '${bytes.length}',
        'X-Goog-Upload-Header-Content-Type': mimeType,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'file': {'display_name': fileName}}),
    );

    if (initResponse.statusCode != 200) {
      _throwApiError(initResponse.body, 'Upload init');
    }

    final uploadUrl = initResponse.headers['x-goog-upload-url'];
    if (uploadUrl == null) {
      throw GeminiException('ບໍ່ໄດ້ຮັບ upload URL');
    }

    // Step 2: Upload file bytes
    final uploadResponse = await http.put(
      Uri.parse(uploadUrl),
      headers: {
        'Content-Length': '${bytes.length}',
        'X-Goog-Upload-Offset': '0',
        'X-Goog-Upload-Command': 'upload, finalize',
      },
      body: bytes,
    );

    if (uploadResponse.statusCode != 200) {
      _throwApiError(uploadResponse.body, 'Upload');
    }

    final data = jsonDecode(uploadResponse.body);
    final uri = data['file']?['uri'] as String?;
    if (uri == null) throw GeminiException('ບໍ່ໄດ້ຮັບ file URI');
    return uri;
  }

  // ---- Wait for file to be ACTIVE ----

  Future<void> _waitForFileActive(String fileUri) async {
    // Extract file name from URI
    final fileName = fileUri.split('/').last;
    const maxRetries = 20;

    for (int i = 0; i < maxRetries; i++) {
      await Future.delayed(const Duration(seconds: 3));

      final res = await http.get(
        Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/files/$fileName?key=$apiKey'),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final state = data['state'] as String?;
        if (state == 'ACTIVE') return;
        if (state == 'FAILED') {
          throw GeminiException('File processing FAILED ໃນ Gemini');
        }
      }
    }
    throw GeminiException('File ໃຊ້ເວລາດົນເກີນ — ລອງໃໝ່');
  }

  // ---- Generate transcription ----

  Future<String> _generateTranscription(
      String fileUri, String mimeType, String language) async {
    final langHint = language.isNotEmpty ? language : 'Lao (ພາສາລາວ)';

    final prompt =
        'ພາສາໃນວິດີໂອນີ້ແມ່ນ $langHint. '
        'ກາລຸນາຖອດສຽງຄຳເວົ້າທັງໝົດໃນວິດີໂອ/ສຽງນີ້. '
        'ຂຽນຜົນລັດດ້ວຍ ອັກສອນລາວ (Lao script) ເທົ່ານັ້ນ — ຫ້າມໃຊ້ອັກສອນໄທ. '
        'ສົ່ງຜົນລັດໃນຮູບແບບ SRT ເທົ່ານັ້ນ ຕາມຮູບແບບນີ້:\n'
        '[ໝາຍເລກ]\n'
        '[HH:MM:SS,mmm --> HH:MM:SS,mmm]\n'
        '[ຂໍ້ຄວາມລາວ]\n\n'
        'ຫ້າມໃສ່ຄຳອະທິບາຍ ຫຼື ຂໍ້ຄວາມອື່ນ — ສົ່ງສະເພາະ SRT.';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'file_data': {
                'mime_type': mimeType,
                'file_uri': fileUri,
              }
            },
            {'text': prompt},
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'maxOutputTokens': 8192,
      },
    });

    final res = await http
        .post(
          Uri.parse('$_generateBase?key=$apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(const Duration(minutes: 5));

    if (res.statusCode != 200) {
      _throwApiError(res.body, 'Generate');
    }

    final data = jsonDecode(res.body);
    final text = data['candidates']?[0]?['content']?['parts']?[0]?['text']
        as String?;
    if (text == null) throw GeminiException('Gemini ບໍ່ຕອບກັບ text');
    return text.trim();
  }

  // ---- Parse SRT ----

  List<SubtitleSegment> _parseSrt(String srt) {
    final segments = <SubtitleSegment>[];
    // Clean markdown code blocks if present
    final cleaned = srt
        .replaceAll(RegExp(r'```[a-z]*\n?'), '')
        .replaceAll('```', '')
        .trim();

    final blocks = cleaned.split(RegExp(r'\n\s*\n'));

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.length < 3) continue;

      // Find timestamp line
      int timeLineIndex = -1;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('-->')) {
          timeLineIndex = i;
          break;
        }
      }
      if (timeLineIndex == -1) continue;

      final timeParts = lines[timeLineIndex].split('-->');
      if (timeParts.length != 2) continue;

      final start = _parseSrtTime(timeParts[0].trim());
      final end = _parseSrtTime(timeParts[1].trim());
      if (start == null || end == null) continue;

      final textLines = lines.sublist(timeLineIndex + 1);
      final text = textLines.join(' ').trim();
      if (text.isEmpty) continue;

      segments.add(SubtitleSegment(
        id: _uuid.v4(),
        text: text,
        startTime: start,
        endTime: end,
      ));
    }
    return segments;
  }

  Duration? _parseSrtTime(String s) {
    try {
      // Support both , and . as ms separator
      final normalized = s.replaceAll(',', '.').trim();
      final parts = normalized.split(':');
      if (parts.length != 3) return null;
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final secMs = parts[2].split('.');
      final sec = int.parse(secMs[0]);
      final ms = secMs.length > 1
          ? int.parse(secMs[1].padRight(3, '0').substring(0, 3))
          : 0;
      return Duration(hours: h, minutes: m, seconds: sec, milliseconds: ms);
    } catch (_) {
      return null;
    }
  }

  // ---- Word Split ----

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
      final totalDur = seg.endTime - seg.startTime;
      final chunkCount = (words.length / wordsPerLine).ceil();
      final chunkDur = totalDur ~/ chunkCount;

      for (int i = 0; i < chunkCount; i++) {
        final start = i * wordsPerLine;
        final end = (start + wordsPerLine).clamp(0, words.length);
        result.add(SubtitleSegment(
          id: _uuid.v4(),
          text: words.sublist(start, end).join(' '),
          startTime: seg.startTime + (chunkDur * i),
          endTime: i == chunkCount - 1
              ? seg.endTime
              : seg.startTime + (chunkDur * (i + 1)),
        ));
      }
    }
    return result;
  }

  // ---- Helpers ----

  String _detectMimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'avi' => 'video/x-msvideo',
      'mkv' => 'video/x-matroska',
      'webm' => 'video/webm',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'wav' => 'audio/wav',
      'aac' => 'audio/aac',
      _ => 'video/mp4',
    };
  }

  void _throwApiError(String body, String context) {
    try {
      final data = jsonDecode(body);
      final msg = data['error']?['message'] ?? body;
      throw GeminiException('Gemini $context error: $msg');
    } catch (e) {
      if (e is GeminiException) rethrow;
      throw GeminiException('Gemini $context error: $body');
    }
  }
}
