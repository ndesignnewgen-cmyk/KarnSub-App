import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/subtitle_style_model.dart';
import '../services/api_config.dart';
import 'audio_synth.dart';

class TtsService {
  // Premium curated fallback catalog for standard ElevenLabs voices (multilingual)
  static const List<Map<String, String>> _fallbackElevenVoices = [
    {'name': 'Rachel', 'locale': '21m00Tcm4TlvDq8ikWAM', 'gender': 'female'},
    {'name': 'Clyde', 'locale': '2EiwWnXF2V4j26hz8ZHL', 'gender': 'male'},
    {'name': 'Adam', 'locale': 'pNInz6obpgq5paNs9W5D', 'gender': 'male'},
    {'name': 'Nicole', 'locale': 'piTKgcLEGmPEeDFServer', 'gender': 'female'},
    {'name': 'Antoni', 'locale': 'ErXwobaYiN019PkySvjV', 'gender': 'male'},
    {'name': 'Bella', 'locale': 'EXAVITQu4vr4xnSDxMaL', 'gender': 'female'},
    {'name': 'Domi', 'locale': 'AZnzlk1XvdvUeBnXmlld', 'gender': 'female'},
    {'name': 'Elli', 'locale': 'MF3mGyEYCl7XYWbV9VbO', 'gender': 'female'},
    {'name': 'Josh', 'locale': 'TxGEqn7nUJQDX49t3u4g', 'gender': 'male'},
    {'name': 'Arnold', 'locale': 'VR6A4mxSTDL5QQGgMiPP', 'gender': 'male'},
  ];

  TtsService();

  Future<List<String>> getLanguages() async {
    return ['lo', 'th', 'en'];
  }

  /// Dynamically queries ElevenLabs for supported and cloned voices.
  /// Falls back to premium standard offline catalog if key is missing or offline.
  Future<List<Map<String, String>>> getVoicesForLanguage(String langCode) async {
    final sfxOption = {
      'name': 'ສະເພາະເອັບເຟັກສຽງ SFX (SFX Only)',
      'locale': 'sfx_only',
      'gender': 'neutral',
    };

    // 1. Try to fetch dynamic voices from ElevenLabs API if key is present
    final apiKey = await ApiConfig.getElevenLabsKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        final url = Uri.parse('https://api.elevenlabs.io/v1/voices');
        final response = await http.get(
          url,
          headers: {'xi-api-key': apiKey},
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final voicesList = data['voices'] as List?;
          if (voicesList != null) {
            final result = <Map<String, String>>[];
            for (final v in voicesList) {
              final m = Map<String, dynamic>.from(v);
              final name = m['name'] as String? ?? '';
              final voiceId = m['voice_id'] as String? ?? '';
              
              // Extract gender from voice labels if present
              final labels = Map<String, dynamic>.from(m['labels'] ?? {});
              final gender = (labels['gender'] as String? ?? 'unknown').toLowerCase();
              
              result.add({
                'name': name,
                'locale': voiceId, // store ElevenLabs voice_id in locale
                'gender': gender,
              });
            }
            if (result.isNotEmpty) {
              // Sort standard, custom logically
              result.sort((a, b) => a['name']!.compareTo(b['name']!));
              return [sfxOption, ...result];
            }
          }
        }
      } catch (_) {
        // Fall back to offline static lists on error or timeout
      }
    }

    // 2. Return premium curated fallback catalog
    return [sfxOption, ..._fallbackElevenVoices];
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
    String? outputSfxWavPath,
    required bool autoSyncSfx,
    List<SfxBlock>? sfxBlocks,
    void Function(String)? onProgress,
  }) async {
    if (segments.isEmpty) return 'ບໍ່ມີຄຳບັນຍາຍເພື່ອພາກສຽງ';

    final bool isSfxOnly = voiceName == 'ສະເພາະເອັບເຟັກສຽງ SFX (SFX Only)';

    if (isSfxOnly) {
      onProgress?.call('ກຳລັງສ້າງເອັບເຟັກສຽງອັດສະລິຍະ...');
      final sampleRate = 24000;
      final channels = 1;
      final bitsPerSample = 16;
      final bytesPerSample = bitsPerSample ~/ 8;
      
      // Calculate total duration
      int totalDurationMs = 0;
      for (final seg in segments) {
        if (seg.endTime.inMilliseconds > totalDurationMs) {
          totalDurationMs = seg.endTime.inMilliseconds;
        }
      }
      if (totalDurationMs == 0) totalDurationMs = 10000; // fallback
      
      final numSamples = (totalDurationMs / 1000.0 * sampleRate).toInt();
      final flatPcmBytes = Uint8List(numSamples * channels * bytesPerSample);
      
      final popSfx = AudioSynth.generatePop(sampleRate);
      final dingSfx = AudioSynth.generateDing(sampleRate);
      final bytesPerMs = (sampleRate * channels * bytesPerSample) ~/ 1000;
      
      for (final seg in segments) {
        // Play Pop SFX if there's an emoji
        if (seg.emoji != null && seg.emoji!.isNotEmpty) {
          final startMs = seg.startTime.inMilliseconds;
          final offset = startMs * bytesPerMs;
          _mixPcm(flatPcmBytes, popSfx, offset);
        }
        
        // Play Ding SFX for emphasis words
        if (seg.emphasis != null && seg.emphasis!.isNotEmpty) {
          if (seg.wordTimings != null && seg.wordTimings!.isNotEmpty) {
            for (final idx in seg.emphasis!) {
              if (idx < seg.wordTimings!.length) {
                final wordTimeMs = seg.wordTimings![idx].inMilliseconds;
                final offset = wordTimeMs * bytesPerMs;
                _mixPcm(flatPcmBytes, dingSfx, offset);
              }
            }
          } else {
            final startMs = seg.startTime.inMilliseconds;
            final offset = startMs * bytesPerMs;
            _mixPcm(flatPcmBytes, dingSfx, offset);
          }
        }
      }
      
      // Write to file
      final outputFile = File(outputWavPath);
      final waveHeader = _buildWavHeader(
        totalPcmSize: flatPcmBytes.length,
        channels: channels,
        sampleRate: sampleRate,
        bitsPerSample: bitsPerSample,
      );
      
      final outputBytes = BytesBuilder();
      outputBytes.add(waveHeader);
      outputBytes.add(flatPcmBytes);
      await outputFile.writeAsBytes(outputBytes.toBytes());
      return null; // Success!
    }

    final apiKey = await ApiConfig.getElevenLabsKey();
    if (apiKey == null || apiKey.isEmpty) {
      onProgress?.call('ບໍ່ພົບ API Key. ກາລຸນາຕັ້ງຄ່າກ່ອນ.');
      return 'ບໍ່ພົບ API Key ຂອງ ElevenLabs. ກະລຸນາກວດສອບໜ້າຕັ້ງຄ່າ API Key';
    }

    // Determine voice ID from selected voice name (lookup dynamic list)
    onProgress?.call('ກຳລັງກວດສອບລາຍຊື່ສຽງພາກ...');
    final voices = await getVoicesForLanguage(languageCode);
    final matchedVoice = voices.firstWhere(
      (v) => v['name'] == voiceName,
      orElse: () => voices.isNotEmpty ? voices.first : _fallbackElevenVoices.first,
    );
    final voiceId = matchedVoice['locale'] ?? '21m00Tcm4TlvDq8ikWAM';

    final tempDir = await getTemporaryDirectory();
    final List<({int startMs, int endMs, File file})> chunks = [];

    try {
      onProgress?.call('ກຳລັງກຽມພາກສຽງດ້ວຍ ElevenLabs...');

      // 1. Synthesize each segment using ElevenLabs REST API
      for (int i = 0; i < segments.length; i++) {
        final seg = segments[i];
        final text = (useTranslation ? (seg.translatedText ?? seg.text) : seg.text).trim();
        if (text.isEmpty) continue;

        onProgress?.call('ກຳລັງສັງເຄາະສຽງປະໂຫຍກທີ່ ${i + 1}/${segments.length}...');
        final tempFile = File('${tempDir.path}/tts_chunk_${DateTime.now().millisecondsSinceEpoch}_$i.wav');

        // Post request to ElevenLabs S16LE PCM 24kHz stream endpoint
        final url = Uri.parse('https://api.elevenlabs.io/v1/text-to-speech/$voiceId?output_format=pcm_24000');
        final payload = {
          'text': text,
          'model_id': 'eleven_multilingual_v2',
          'voice_settings': {
            'stability': 0.5,
            'similarity_boost': 0.75,
          }
        };

        final response = await http.post(
          url,
          headers: {
            'xi-api-key': apiKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        );

        if (response.statusCode == 200) {
          final rawPcmBytes = response.bodyBytes;
          if (rawPcmBytes.isNotEmpty) {
            // ElevenLabs returns raw pcm_24000 S16LE bytes. Prepend standard 44-byte WAV header.
            final header = _buildWavHeader(
              totalPcmSize: rawPcmBytes.length,
              channels: 1, // Mono
              sampleRate: 24000, // 24 kHz
              bitsPerSample: 16, // 16-bit
            );

            final wavBuilder = BytesBuilder();
            wavBuilder.add(header);
            wavBuilder.add(rawPcmBytes);

            await tempFile.writeAsBytes(wavBuilder.toBytes());

            if (tempFile.existsSync() && tempFile.lengthSync() > 44) {
              chunks.add((
                startMs: seg.startTime.inMilliseconds,
                endMs: seg.endTime.inMilliseconds,
                file: tempFile,
              ));
            }
          } else {
            throw Exception('Response bodyBytes is empty');
          }
        } else {
          final statusCode = response.statusCode;
          String details = response.body;
          try {
            final json = jsonDecode(response.body);
            details = json['detail']?['message'] ?? json['error']?['message'] ?? response.body;
          } catch (_) {}
          
          if (statusCode == 401) {
            return 'ElevenLabs Error (401): API Key ບໍ່ຖືກຕ້ອງ (Invalid API Key). ກະລຸນາກວດສອບ Key ຄືນໃໝ່.';
          } else if (statusCode == 403) {
            return 'ElevenLabs Error (403): ໂຄຕາໝົດ ຫຼື ຕົວອັກສອນໝົດ (Out of characters/credits). ກະລຸນາກວດສອບແພັກເກັດຂອງທ່ານ.';
          } else if (statusCode == 400 && details.contains('restricted')) {
            return 'ElevenLabs Error (400): Key ຖືກຈຳກັດສິດ (Restricted Key). ກະລຸນາກວດສອບວ່າໄດ້ອະນຸມັດ "Text to Speech" ໃຫ້ກັບ Key ຕົວນີ້ແລ້ວ ຫຼື ປິດປຸ່ມ Restrict Key ໃນ ElevenLabs Dashboard.';
          }
          
          final errMsg = 'ElevenLabs API Error $statusCode: $details';
          onProgress?.call('ເກີດຂໍ້ຜິດພາດ: $errMsg');
          throw Exception(errMsg);
        }
      }

      if (chunks.isEmpty) {
        onProgress?.call('ບໍ່ມີຂໍ້ຄວາມສຳລັບການພາກສຽງ');
        return 'ບໍ່ມີຂໍ້ຄວາມທີ່ສາມາດພາກສຽງໄດ້';
      }

      onProgress?.call('ກຳລັງຈັດຊ່ວງເວລາໃຫ້ຕົງປາກ...');
      
      // 2. Read the first WAV file header to extract audio specs (SampleRate, Channels)
      final firstFileBytes = await chunks.first.file.readAsBytes();
      if (firstFileBytes.length < 44) return 'ໄຟລ໌ສຽງພາກຊົ່ວຄາວເສຍຫາຍ';
      
      final channels = ByteData.sublistView(firstFileBytes, 22, 24).getInt16(0, Endian.little);
      final sampleRate = ByteData.sublistView(firstFileBytes, 24, 28).getInt32(0, Endian.little);
      final bitsPerSample = ByteData.sublistView(firstFileBytes, 34, 36).getInt16(0, Endian.little);
      final bytesPerSample = bitsPerSample ~/ 8;
      
      // 3. Stitched Audio Data Buffer
      final List<Uint8List> pcmBuffers = [];
      int currentTimelineMs = 0;

      for (final chunk in chunks) {
        // A. Calculate silence gap from currentTimelineMs to chunk's startMs
        final silenceMs = chunk.startMs - currentTimelineMs;
        if (silenceMs > 0) {
          final numSamples = (silenceMs / 1000.0 * sampleRate).toInt();
          final silenceByteSize = numSamples * channels * bytesPerSample;
          final silenceBytes = Uint8List(silenceByteSize); // all initialized to 0x00
          pcmBuffers.add(silenceBytes);
          currentTimelineMs = chunk.startMs;
        }

        // B. Read the raw PCM data (excluding the WAV header)
        final chunkBytes = await chunk.file.readAsBytes();
        
        // Find "data" chunk offset to safely extract raw PCM
        int dataOffset = 44;
        for (int offset = 12; offset < chunkBytes.length - 8; offset++) {
          if (chunkBytes[offset] == 100 && // 'd'
              chunkBytes[offset + 1] == 97 && // 'a'
              chunkBytes[offset + 2] == 116 && // 't'
              chunkBytes[offset + 3] == 97) { // 'a'
            dataOffset = offset + 8;
            break;
          }
        }
        
        if (dataOffset < chunkBytes.length) {
          final rawPcm = chunkBytes.sublist(dataOffset);
          pcmBuffers.add(rawPcm);
          
          final chunkDurationMs = (rawPcm.length / (sampleRate * channels * bytesPerSample) * 1000).toInt();
          currentTimelineMs += chunkDurationMs;
        }
      }

      // 4. Concatenate pcmBuffers into a single flat Uint8List
      final flatBuilder = BytesBuilder();
      for (final buffer in pcmBuffers) {
        flatBuilder.add(buffer);
      }
      final flatPcmBytes = flatBuilder.toBytes();

      // Perform mixing on flatPcmBytes if autoSyncSfx is active
      if (autoSyncSfx && outputSfxWavPath != null && sfxBlocks != null) {
        final popSfx = AudioSynth.generatePop(sampleRate);
        final dingSfx = AudioSynth.generateDing(sampleRate);
        final swooshSfx = AudioSynth.generateSwoosh(sampleRate);
        final chimeSfx = AudioSynth.generateChime(sampleRate);
        final drumSfx = AudioSynth.generateDrum(sampleRate);
        final beepSfx = AudioSynth.generateBeep(sampleRate);
        final bubbleSfx = AudioSynth.generateBubble(sampleRate);
        final clickSfx = AudioSynth.generateClick(sampleRate);
        final whooshSfx = AudioSynth.generateWhoosh(sampleRate);
        final tadaSfx = AudioSynth.generateTada(sampleRate);
        final bounceSfx = AudioSynth.generateBounce(sampleRate);
        final glitchSfx = AudioSynth.generateGlitch(sampleRate);
        
        final bytesPerMs = (sampleRate * channels * bytesPerSample) ~/ 1000;
        
        // Create a separate array of zeros for the SFX track
        final sfxPcmBytes = Uint8List(flatPcmBytes.length);

        for (final block in sfxBlocks) {
          final startMs = block.startTime.inMilliseconds;
          final offset = startMs * bytesPerMs;
          if (block.type == SfxType.pop) {
            _mixPcm(sfxPcmBytes, popSfx, offset);
          } else if (block.type == SfxType.ding) {
            _mixPcm(sfxPcmBytes, dingSfx, offset);
          } else if (block.type == SfxType.swoosh) {
            _mixPcm(sfxPcmBytes, swooshSfx, offset);
          } else if (block.type == SfxType.chime) {
            _mixPcm(sfxPcmBytes, chimeSfx, offset);
          } else if (block.type == SfxType.drum) {
            _mixPcm(sfxPcmBytes, drumSfx, offset);
          } else if (block.type == SfxType.beep) {
            _mixPcm(sfxPcmBytes, beepSfx, offset);
          } else if (block.type == SfxType.bubble) {
            _mixPcm(sfxPcmBytes, bubbleSfx, offset);
          } else if (block.type == SfxType.click) {
            _mixPcm(sfxPcmBytes, clickSfx, offset);
          } else if (block.type == SfxType.whoosh) {
            _mixPcm(sfxPcmBytes, whooshSfx, offset);
          } else if (block.type == SfxType.tada) {
            _mixPcm(sfxPcmBytes, tadaSfx, offset);
          } else if (block.type == SfxType.bounce) {
            _mixPcm(sfxPcmBytes, bounceSfx, offset);
          } else if (block.type == SfxType.glitch) {
            _mixPcm(sfxPcmBytes, glitchSfx, offset);
          }
        }

        // Save the SFX track separately
        final sfxOutputFile = File(outputSfxWavPath);
        final sfxWaveHeader = _buildWavHeader(
          totalPcmSize: sfxPcmBytes.length,
          channels: channels,
          sampleRate: sampleRate,
          bitsPerSample: bitsPerSample,
        );
        final sfxOutputBytes = BytesBuilder();
        sfxOutputBytes.add(sfxWaveHeader);
        sfxOutputBytes.add(sfxPcmBytes);
        await sfxOutputFile.writeAsBytes(sfxOutputBytes.toBytes());
      }

      // Create output WAV file and write 44-byte WAV header (Main TTS only)
      final outputFile = File(outputWavPath);
      final waveHeader = _buildWavHeader(
        totalPcmSize: flatPcmBytes.length,
        channels: channels,
        sampleRate: sampleRate,
        bitsPerSample: bitsPerSample,
      );

      final outputBytes = BytesBuilder();
      outputBytes.add(waveHeader);
      outputBytes.add(flatPcmBytes);

      await outputFile.writeAsBytes(outputBytes.toBytes());

      // 5. Clean up temporary chunk files
      for (final chunk in chunks) {
        try {
          if (chunk.file.existsSync()) {
            chunk.file.deleteSync();
          }
        } catch (_) {}
      }

      return null; // Success!
    } catch (e) {
      // Cleanup temp files on error
      for (final chunk in chunks) {
        try {
          if (chunk.file.existsSync()) {
            chunk.file.deleteSync();
          }
        } catch (_) {}
      }
      return 'ເກີດຂໍ້ຜິດພາດໃນການພາກສຽງ: ${e.toString()}';
    }
  }

  void _mixPcm(Uint8List mainPcm, Uint8List sfxPcm, int startOffset) {
    final mainData = ByteData.view(mainPcm.buffer, mainPcm.offsetInBytes, mainPcm.lengthInBytes);
    final sfxData = ByteData.view(sfxPcm.buffer, sfxPcm.offsetInBytes, sfxPcm.lengthInBytes);
    
    final numSamples = sfxPcm.length ~/ 2;
    for (int i = 0; i < numSamples; i++) {
      final mainIdx = startOffset + i * 2;
      if (mainIdx + 1 >= mainPcm.length) break;
      
      final sfxSample = sfxData.getInt16(i * 2, Endian.little);
      final mainSample = mainData.getInt16(mainIdx, Endian.little);
      
      // Linear mix and clamp
      int mixed = mainSample + sfxSample;
      if (mixed > 32767) mixed = 32767;
      if (mixed < -32768) mixed = -32768;
      
      mainData.setInt16(mainIdx, mixed, Endian.little);
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
