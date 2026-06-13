import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/subtitle_style_model.dart';
import '../services/api_config.dart';
import '../services/api_config.dart';

class TtsService {
  static const _channel = MethodChannel('com.anniekaydee.subtitle_app/audio');

  static const _primaryTtsModel = 'gemini-3.1-flash-tts-preview';
  static const _fallbackTtsModel = 'gemini-2.5-flash-preview-tts';
  
  static String _getTtsEndpoint(String model) {
    return 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';
  }

  // The 30 Gemini prebuilt voices. `name` = friendly label shown to the user,
  // `locale` = the Gemini voiceName, `gender` is best-effort for the UI tag.
  static const List<Map<String, String>> _geminiVoices = [
    {'name': 'Zephyr', 'locale': 'Zephyr', 'gender': 'female'},
    {'name': 'Puck', 'locale': 'Puck', 'gender': 'male'},
    {'name': 'Charon', 'locale': 'Charon', 'gender': 'male'},
    {'name': 'Kore', 'locale': 'Kore', 'gender': 'female'},
    {'name': 'Fenrir', 'locale': 'Fenrir', 'gender': 'male'},
    {'name': 'Leda', 'locale': 'Leda', 'gender': 'female'},
    {'name': 'Orus', 'locale': 'Orus', 'gender': 'male'},
    {'name': 'Aoede', 'locale': 'Aoede', 'gender': 'female'},
    {'name': 'Callirrhoe', 'locale': 'Callirrhoe', 'gender': 'female'},
    {'name': 'Autonoe', 'locale': 'Autonoe', 'gender': 'female'},
    {'name': 'Enceladus', 'locale': 'Enceladus', 'gender': 'male'},
    {'name': 'Iapetus', 'locale': 'Iapetus', 'gender': 'male'},
    {'name': 'Umbriel', 'locale': 'Umbriel', 'gender': 'male'},
    {'name': 'Algieba', 'locale': 'Algieba', 'gender': 'male'},
    {'name': 'Despina', 'locale': 'Despina', 'gender': 'female'},
    {'name': 'Erinome', 'locale': 'Erinome', 'gender': 'female'},
    {'name': 'Algenib', 'locale': 'Algenib', 'gender': 'male'},
    {'name': 'Rasalgethi', 'locale': 'Rasalgethi', 'gender': 'male'},
    {'name': 'Laomedeia', 'locale': 'Laomedeia', 'gender': 'female'},
    {'name': 'Achernar', 'locale': 'Achernar', 'gender': 'female'},
    {'name': 'Alnilam', 'locale': 'Alnilam', 'gender': 'male'},
    {'name': 'Schedar', 'locale': 'Schedar', 'gender': 'male'},
    {'name': 'Gacrux', 'locale': 'Gacrux', 'gender': 'female'},
    {'name': 'Pulcherrima', 'locale': 'Pulcherrima', 'gender': 'female'},
    {'name': 'Achird', 'locale': 'Achird', 'gender': 'male'},
    {'name': 'Zubenelgenubi', 'locale': 'Zubenelgenubi', 'gender': 'male'},
    {'name': 'Vindemiatrix', 'locale': 'Vindemiatrix', 'gender': 'female'},
    {'name': 'Sadachbia', 'locale': 'Sadachbia', 'gender': 'male'},
    {'name': 'Sadaltager', 'locale': 'Sadaltager', 'gender': 'male'},
    {'name': 'Sulafat', 'locale': 'Sulafat', 'gender': 'female'},
  ];

  TtsService();

  Future<List<String>> getLanguages() async {
    return ['lo', 'th', 'en'];
  }

  /// Returns the 30 Gemini prebuilt voices.
  /// No network call — Gemini voices are a fixed catalog.
  Future<List<Map<String, String>>> getVoicesForLanguage(String langCode) async {
    return _geminiVoices;
  }

  /// Synthesizes each segment's text to a temp WAV file using ElevenLabs, then
  /// compiles them into a single synchronized WAV file with precise silence padding matching subtitle timings.
  /// [useTranslation] dictates whether to use Translated text or Original text.
  Future<String?> synthesizeAndStitch({
    required List<SubtitleSegment> segments,
    required String languageCode,
    required String voiceName,
    required double speechRate,
    required bool useTranslation,
    required String outputWavPath,
    void Function(String)? onProgress,
  }) async {
    if (segments.isEmpty) return 'ບໍ່ມີຄຳບັນຍາຍເພື່ອພາກສຽງ';

    if (segments.isEmpty) return 'ບໍ່ມີຄຳບັນຍາຍເພື່ອພາກສຽງ';

    // Resolve the selected friendly name → Gemini voiceName.
    onProgress?.call('ກຳລັງກຽມພາກສຽງ...');
    final voices = await getVoicesForLanguage(languageCode);
    final matchedVoice = voices.firstWhere(
      (v) => v['name'] == voiceName,
      orElse: () => _geminiVoices.first,
    );
    final voiceId = matchedVoice['locale'] ?? 'Kore';

    final apiKey = await ApiConfig.getApiKey(); // Gemini key (same as transcription)
    if (apiKey == null || apiKey.isEmpty) {
      onProgress?.call('ບໍ່ພົບ Gemini API Key. ກະລຸນາຕັ້ງຄ່າກ່ອນ.');
      return 'ບໍ່ພົບ Gemini API Key. ກະລຸນາໃສ່ Gemini Key ໃນໜ້າຕັ້ງຄ່າ';
    }

    try {
      // ──────────────────────────────────────────────────────────────────
      // Single-request TTS (Fast Professional Style)
      // Combines all text without punctuation to force continuous, fast speech
      // ──────────────────────────────────────────────────────────────────
      onProgress?.call('ກຳລັງລວມຂໍ້ຄວາມສຳລັບພາກສຽງ...');

      final allTexts = <String>[];
      for (final seg in segments) {
        // Remove pauses (., \n) to force continuous fast speaking
        String text = (useTranslation ? (seg.translatedText ?? seg.text) : seg.text).trim();
        text = text.replaceAll('\n', ' ').replaceAll('.', ' ').replaceAll(',', ' ');
        if (text.isNotEmpty) allTexts.add(text);
      }

      if (allTexts.isEmpty) {
        return 'ບໍ່ມີຂໍ້ຄວາມທີ່ສາມາດພາກສຽງໄດ້';
      }

      // Join with space so there are no sentence breaks
      final combinedText = allTexts.join(' ');

      onProgress?.call('ກຳລັງສັງເຄາະສຽງ AI ແບບຕໍ່ເນື່ອງ (${allTexts.length} ປະໂຫຍກ)...');

      final payload = {
        'contents': [
          {
            'parts': [
              {'text': combinedText}
            ]
          }
        ],
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          'speechConfig': {
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': voiceId}
            }
          }
        }
      };

      http.Response? response;
      const maxRetries = 5;
      String currentModel = _primaryTtsModel;
      bool usedFallback = false;
      
      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        final url = Uri.parse('${_getTtsEndpoint(currentModel)}?key=$apiKey');
        try {
          response = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          ).timeout(const Duration(minutes: 3));
        } catch (e) {
          if (attempt >= maxRetries) {
            return 'ເຊື່ອມຕໍ່ Gemini ບໍ່ໄດ້: $e';
          }
          onProgress?.call('ເນັດຊ້າ ລອງໃໝ່ ($attempt/$maxRetries)...');
          await Future.delayed(Duration(seconds: 3 * attempt));
          continue;
        }

        if (response.statusCode == 429) {
          if (!usedFallback) {
            onProgress?.call('ໂຄຕ້າຮຸ່ນຫຼັກເຕັມ! ກຳລັງສະລັບໄປໃຊ້ຮຸ່ນສຳຮອງ...');
            currentModel = _fallbackTtsModel;
            usedFallback = true;
            continue; // retry immediately with fallback
          }
          if (attempt >= maxRetries) break;
          final waitSec = 5 * attempt;
          onProgress?.call('Quota ສຳຮອງກໍເຕັມ — ລໍຖ້າ ${waitSec}ວິ ($attempt/$maxRetries)...');
          await Future.delayed(Duration(seconds: waitSec));
          continue;
        }
        break;
      }

      if (response == null) {
        return 'Gemini TTS: ບໍ່ສາມາດເຊື່ອມຕໍ່ໄດ້';
      }

      if (response.statusCode != 200) {
        final statusCode = response.statusCode;
        String details = response.body;
        try {
          final json = jsonDecode(response.body);
          details = json['error']?['message'] ?? response.body;
        } catch (_) {}

        if (statusCode == 400) {
          return 'Gemini TTS Error (400): Key ບໍ່ຖືກຕ້ອງ ຫຼື ຄຳຮ້ອງຜິດ. ກວດສອບ Gemini Key.';
        } else if (statusCode == 403) {
          return 'Gemini TTS Error (403): Key ບໍ່ມີສິດໃຊ້ TTS.';
        } else if (statusCode == 429) {
          return 'Gemini TTS (429): $details';
        }
        return 'Gemini TTS Error $statusCode: $details';
      }

      onProgress?.call('ກຳລັງປະມວນຜົນສຽງ...');
      String? b64;
      try {
        final json = jsonDecode(response.body);
        final parts = json['candidates']?[0]?['content']?['parts'] as List?;
        if (parts != null) {
          for (final pt in parts) {
            final inline = pt['inlineData'] ?? pt['inline_data'];
            if (inline != null && inline['data'] != null) {
              b64 = inline['data'] as String;
              break;
            }
          }
        }
      } catch (_) {}

      if (b64 == null || b64.isEmpty) {
        String shortBody = response.body.length > 300 ? response.body.substring(0, 300) + '...' : response.body;
        return 'Gemini TTS ບໍ່ສົ່ງສຽງກັບມາ. Response: $shortBody';
      }

      final rawPcmBytes = base64Decode(b64);
      
      final isAlreadyWav = rawPcmBytes.length >= 4 &&
          rawPcmBytes[0] == 82 && // 'R'
          rawPcmBytes[1] == 73 && // 'I'
          rawPcmBytes[2] == 70 && // 'F'
          rawPcmBytes[3] == 70;   // 'F'

      final Uint8List wavBytes;
      if (isAlreadyWav) {
        wavBytes = rawPcmBytes;
      } else {
        const sampleRate = 24000;
        const channels = 1;
        const bitsPerSample = 16;
        
        final header = _buildWavHeader(
          totalPcmSize: rawPcmBytes.length,
          channels: channels,
          sampleRate: sampleRate,
          bitsPerSample: bitsPerSample,
        );

        final wavBuilder = BytesBuilder();
        wavBuilder.add(header);
        wavBuilder.add(rawPcmBytes);
        wavBytes = wavBuilder.toBytes();
      }

      final outputFile = File(outputWavPath);
      await outputFile.writeAsBytes(wavBytes);

      onProgress?.call('ພາກສຽງ AI ສຳເລັດ! ✅');

      return null; // Success!
    } catch (e) {
      return 'ເກີດຂໍ້ຜິດພາດໃນການພາກສຽງ: ${e.toString()}';
    }
  }


  Uint8List _buildWavHeader({
    required int totalPcmSize,
    required int channels,
    required int sampleRate,
    required int bitsPerSample,
  }) {
    final header = Uint8List(44);
    final data = ByteData.view(header.buffer);

    // RIFF Chunk Descriptor
    header[0] = 82; // 'R'
    header[1] = 73; // 'I'
    header[2] = 70; // 'F'
    header[3] = 70; // 'F'
    data.setInt32(4, 36 + totalPcmSize, Endian.little);
    header[8] = 87;  // 'W'
    header[9] = 65;  // 'A'
    header[10] = 86; // 'V'
    header[11] = 69; // 'E'

    // "fmt " sub-chunk
    header[12] = 102; // 'f'
    header[13] = 109; // 'm'
    header[14] = 116; // 't'
    header[15] = 32;  // ' '
    data.setInt32(16, 16, Endian.little); // Subchunk1Size
    data.setInt16(20, 1, Endian.little);  // AudioFormat (PCM)
    data.setInt16(22, channels, Endian.little);
    data.setInt32(24, sampleRate, Endian.little);
    data.setInt32(28, sampleRate * channels * (bitsPerSample ~/ 8), Endian.little); // ByteRate
    data.setInt16(32, channels * (bitsPerSample ~/ 8), Endian.little); // BlockAlign
    data.setInt16(34, bitsPerSample, Endian.little);

    // "data" sub-chunk
    header[36] = 100; // 'd'
    header[37] = 97;  // 'a'
    header[38] = 116; // 't'
    header[39] = 97;  // 'a'
    data.setInt32(40, totalPcmSize, Endian.little);

    return header;
  }
}
