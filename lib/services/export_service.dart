import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:saver_gallery/saver_gallery.dart';
import '../models/subtitle_style_model.dart';
import 'lao_font_service.dart';
import 'audio_synth.dart';

class ExportException implements Exception {
  final String message;
  ExportException(this.message);
  @override
  String toString() => message;
}

enum ExportQuality { hd720, fhd1080 }

class ExportService {
  static const _channel = MethodChannel('com.anniekaydee.subtitle_app/audio');

  // App logo (white, transparent background) used as the free-tier watermark.
  static const _watermarkAsset = 'assets/icon/watermark_logo.png';
  static String? _watermarkLogoPath;

  /// Copies the bundled app logo to a temp file (once) so native can decode it.
  /// Returns null if the asset can't be loaded.
  static Future<String?> _resolveWatermarkLogoPath() async {
    if (_watermarkLogoPath != null && File(_watermarkLogoPath!).existsSync()) {
      return _watermarkLogoPath;
    }
    try {
      final bytes = await rootBundle.load(_watermarkAsset);
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'wm_logo.png'));
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      _watermarkLogoPath = file.path;
      return _watermarkLogoPath;
    } catch (e) {
      debugPrint('[ExportService] watermark logo load failed: $e');
      return null;
    }
  }

  /// Export SRT file → save to Download/SubtitleAI
  static Future<String> exportSrtFile(
    List<SubtitleSegment> segments,
    String projectName,
  ) async {
    if (segments.isEmpty) throw ExportException('ບໍ່ມີ Subtitle ທີ່ຈະ Export');

    final tempDir = await getTemporaryDirectory();
    final safeName = projectName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName = '${safeName}_$ts.srt';
    final tempPath = p.join(tempDir.path, fileName);

    await File(tempPath).writeAsString(_buildSrtContent(segments));

    final saveResult = await SaverGallery.saveFile(
      filePath: tempPath,
      fileName: fileName,
      androidRelativePath: 'Download/SubtitleAI',
      skipIfExists: false,
    );

    try {
      File(tempPath).deleteSync();
    } catch (_) {}

    if (!saveResult.isSuccess) {
      throw ExportException(
        'ບໍ່ສາມາດບັນທຶກ SRT ໄດ້ (${saveResult.errorMessage ?? ''})',
      );
    }

    return 'Download/SubtitleAI/$fileName';
  }

  /// Export video with subtitles burned in via native MediaCodec + mp4parser muxer.
  static Future<String> exportVideoWithSubtitles(
    String videoPath,
    List<SubtitleSegment> segments,
    SubtitleProject project,
    ExportQuality quality,
    void Function(double progress, String status)? onProgress, {
    bool withWatermark = false,
    String watermarkPosition = 'top',
  }) async {
    if (segments.isEmpty) throw ExportException('ບໍ່ມີ Subtitle ທີ່ຈະ Export');

    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final tempOutputPath = p.join(tempDir.path, 'export_$ts.mp4');

    final safeName = project.name.replaceAll(RegExp(r'[^\w\s\-]'), '_').trim();
    final fileName = '${safeName}_$ts.mp4';

    onProgress?.call(0.05, 'ກຳລັງກຽມ...');

    final watermarkLogoPath = withWatermark
        ? await _resolveWatermarkLogoPath()
        : null;

    final fontPath = await LaoFontService.resolveExportFontPath(
      project.fontFamily,
    );
    final isKaraoke = project.isKaraokeHighlight;

    // Effective per-segment karaoke (null override inherits the project value),
    // so a single phrase can have the colour-sweep + Word Pop on its own.
    bool effKaraoke(SubtitleSegment s) =>
        s.karaoke ?? project.isKaraokeHighlight;
    bool effPop(SubtitleSegment s) => s.karaokeScale ?? project.karaokeScale;

    // Resolve the font file path for every font used by a per-segment override
    // (plus the project default) so the native side can burn each one.
    final fontPathCache = <String, String?>{project.fontFamily: fontPath};
    for (final s in segments) {
      final fam = s.fontFamily;
      if (fam != null && !fontPathCache.containsKey(fam)) {
        fontPathCache[fam] = await LaoFontService.resolveExportFontPath(fam);
      }
    }

    // Build the per-segment style override map (only when the segment actually
    // overrides something) so export matches the per-segment preview.
    Map<String, dynamic>? segStyle(SubtitleSegment s) {
      if (!s.hasStyleOverride) return null;
      final p = s.styleIndex != null
          ? subtitlePresets[s.styleIndex!.clamp(0, subtitlePresets.length - 1)]
          : project.selectedStyle;
      final fam = s.fontFamily ?? project.fontFamily;
      final sp = fontPathCache[fam];
      return <String, dynamic>{
        'textColor': s.textColorValue ?? p.textColor.value,
        if (p.backgroundColor != null) 'bgColor': p.backgroundColor!.value,
        'hasShadow': p.hasShadow,
        'has3dShadow': p.has3dShadow,
        'hasOutline': p.hasOutline,
        if (p.outlineColor != null) 'outlineColor': p.outlineColor!.value,
        if (p.gradientColors != null)
          'gradientColors': p.gradientColors!.map((c) => c.value).toList(),
        'hasNeonGlow': p.hasNeonGlow,
        if (p.glowColor != null) 'glowColor': p.glowColor!.value,
        'hasUnderline': p.hasUnderline,
        if (p.underlineColor != null) 'underlineColor': p.underlineColor!.value,
        'fontWeight': s.fontWeight ?? project.fontWeight,
        'fontSize': s.fontSize ?? project.fontSize,
        'positionY': s.positionY ?? project.subtitlePositionY,
        'positionX': s.positionX ?? 0.5,
        'rotation': s.rotation ?? 0.0,
        if (sp != null) 'fontPath': sp,
        'animationType': (s.animation ?? project.subtitleAnimation).name,
        // Per-segment karaoke decision (explicit on/off so native can override
        // the project default in either direction).
        'karaoke': effKaraoke(s),
        if (effKaraoke(s)) 'karaokeColor': project.karaokeHighlightColor.value,
        if (effKaraoke(s)) 'karaokeScale': effPop(s),
      };
    }

    final segmentsData = segments.map((s) {
      final data = <String, dynamic>{
        'startMs': s.startTime.inMilliseconds,
        'endMs': s.endTime.inMilliseconds,
        'text': s.text,
      };
      final st = segStyle(s);
      if (st != null) data['style'] = st;
      final hasEmphasis = s.emphasis != null && s.emphasis!.isNotEmpty;
      // Word units are needed for the karaoke sweep AND for ✨ punch-word
      // emphasis (both render per-word in native).
      if (effKaraoke(s) || hasEmphasis) {
        final wordsList = (s.words != null && s.words!.isNotEmpty)
            ? s.words!.where((w) => w.isNotEmpty).toList()
            : splitLaoHighlightUnits(s.text);
        data['words'] = wordsList;
        if (s.wordTimings != null &&
            s.wordTimings!.length == wordsList.length) {
          data['wordTimingsMs'] = s.wordTimings!
              .map((d) => d.inMilliseconds)
              .toList();
        }
      }
      // Auto ✨ emphasis word indices + emoji (rendered identically to preview).
      if (hasEmphasis) data['emphasis'] = s.emphasis;
      if (s.emoji != null && s.emoji!.isNotEmpty) data['emoji'] = s.emoji;
      if (project.showBilingual &&
          s.translatedText != null &&
          s.translatedText!.isNotEmpty) {
        data['translatedText'] = s.translatedText;
      }
      return data;
    }).toList();

    final preset = project.selectedStyle;
    final bilingualPreset =
        subtitlePresets[project.bilingualPresetIndex.clamp(
          0,
          subtitlePresets.length - 1,
        )];
    final styleData = <String, dynamic>{
      'textColor': preset.textColor.value,
      if (preset.backgroundColor != null)
        'bgColor': preset.backgroundColor!.value,
      'hasShadow': preset.hasShadow,
      'has3dShadow': preset.has3dShadow,
      'hasOutline': preset.hasOutline,
      if (preset.outlineColor != null)
        'outlineColor': preset.outlineColor!.value,
      if (preset.gradientColors != null)
        'gradientColors': preset.gradientColors!.map((c) => c.value).toList(),
      'isBold': project.fontWeight >= 600,
      'fontWeight': project.fontWeight,
      'fontSize': project.fontSize,
      'positionY': project.subtitlePositionY,
      if (fontPath != null) 'fontPath': fontPath,
      if (isKaraoke) 'karaokeColor': project.karaokeHighlightColor.value,
      if (isKaraoke) 'karaokeScale': project.karaokeScale,
      // Colour for Auto ✨ punch words (used even when karaoke sweep is off).
      'emphasisColor': project.karaokeHighlightColor.value,
      // Main-line decoration so export matches the preview for every style.
      'hasNeonGlow': preset.hasNeonGlow,
      if (preset.glowColor != null) 'glowColor': preset.glowColor!.value,
      'hasUnderline': preset.hasUnderline,
      if (preset.underlineColor != null)
        'underlineColor': preset.underlineColor!.value,
      'animationType': project.subtitleAnimation.name,
      'animInMs': animationDurationMs(project.animationSpeed),
      'animOutType': project.exitAnimation.name,
      'typeUnitMs': typewriterUnitMs(project.animationSpeed),
      if (withWatermark) 'watermarkText': 'KarnSub',
      if (withWatermark) 'watermarkPosition': watermarkPosition,
      if (withWatermark && watermarkLogoPath != null)
        'watermarkLogoPath': watermarkLogoPath,
      if (project.showBilingual) ...{
        'bilingualTextColor': bilingualPreset.textColor.value,
        if (bilingualPreset.backgroundColor != null)
          'bilingualBgColor': bilingualPreset.backgroundColor!.value,
        'bilingualHasShadow': bilingualPreset.hasShadow,
        'bilingualIsBold': bilingualPreset.fontWeight.index >= 6,
        'bilingualFontSize': project.bilingualFontSize,
        'bilingualGap': project.bilingualGap,
        'bilingualHasNeonGlow': bilingualPreset.hasNeonGlow,
        if (bilingualPreset.glowColor != null)
          'bilingualGlowColor': bilingualPreset.glowColor!.value,
      },
    };

    onProgress?.call(0.1, 'ກຳລັງ Export...');

    // Receive live progress (0..1) pushed from native during encoding.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'exportProgress') {
        final p = (call.arguments as num).toDouble();
        onProgress?.call(p, 'ກຳລັງ Export... ${(p * 100).toInt()}%');
      }
    });

    final hasSfx = project.sfxBlocks.isNotEmpty;
    String exportedPath = '';

    try {
      exportedPath = await _channel.invokeMethod('burnSubtitles', {
        'videoPath': videoPath,
        'outputPath': tempOutputPath,
        'fileName': fileName,
        'segments': segmentsData,
        'style': styleData,
        'autoCut': project.isAutoCut,
        'returnTempPath': hasSfx,
      });
    } on PlatformException catch (e) {
      _channel.setMethodCallHandler(null);
      throw ExportException('Export ຜິດພາດ: ${e.message ?? 'Unknown'}');
    }
    
    _channel.setMethodCallHandler(null);

    if (hasSfx) {
      onProgress?.call(0.95, 'ກຳລັງ Mix SFX ເຂົ້າສຽງ...');
      try {
        final mixedVideoPath = await _mixSfxNative(
          exportedPath, project.sfxBlocks, tempDir.path, ts, fileName,
        );
        onProgress?.call(1.0, 'ສຳເລັດ!');
        return mixedVideoPath;
      } catch (e) {
        debugPrint('[ExportService] SFX mix failed, saving without SFX: $e');
        // fallback: save the subtitle-only video
        final saveResult = await SaverGallery.saveFile(
          filePath: exportedPath,
          fileName: fileName,
          androidRelativePath: 'Movies/SubtitleAI',
          skipIfExists: false,
        );
        try { File(exportedPath).deleteSync(); } catch (_) {}
        onProgress?.call(1.0, 'ສຳເລັດ! (ບໍ່ມີ SFX)');
        return saveResult.isSuccess ? 'Movies/SubtitleAI/$fileName' : exportedPath;
      }
    } else {
      onProgress?.call(1.0, 'ສຳເລັດ!');
      return exportedPath;
    }
  }

  /// Mix SFX blocks into the video audio using pure Dart PCM mixing + native muxer.
  /// No FFmpeg required — uses the existing extractAudio + replaceAudioTrack native methods.
  static Future<String> _mixSfxNative(
    String videoPath,
    List<SfxBlock> sfxBlocks,
    String tempDirPath,
    int ts,
    String fileName,
  ) async {
    const sampleRate = 16000; // matches native extractAudio TARGET_SAMPLE_RATE
    final extractedWav = p.join(tempDirPath, 'orig_audio_$ts.wav');
    final mixedWav    = p.join(tempDirPath, 'mixed_audio_$ts.wav');
    final mixedVideo  = p.join(tempDirPath, 'sfx_video_$ts.mp4');

    // 1. Extract original audio from the subtitle-burned video
    await _channel.invokeMethod('extractAudio', {
      'videoPath': videoPath,
      'outputPath': extractedWav,
    });

    // 2. Read WAV → Int16List PCM
    final wavBytes = await File(extractedWav).readAsBytes();
    if (wavBytes.length <= 44) throw Exception('Extracted WAV too small');
    // WAV is little-endian 16-bit PCM starting at byte 44
    final pcm = Int16List.view(wavBytes.buffer, 44);

    // 3. Mix each SFX block into the PCM buffer at its start-time offset
    for (final block in sfxBlocks) {
      final sfxBytes = _generateSfxPcm(block.type, sampleRate);
      final sfxSamples = Int16List.view(sfxBytes.buffer);
      final offsetSamples = (block.startTime.inMilliseconds * sampleRate ~/ 1000)
          .clamp(0, pcm.length - 1);
      final copyLen = sfxSamples.length.clamp(0, pcm.length - offsetSamples);
      for (int i = 0; i < copyLen; i++) {
        final mixed = (pcm[offsetSamples + i] + sfxSamples[i]).clamp(-32768, 32767);
        pcm[offsetSamples + i] = mixed;
      }
    }

    // 4. Write back as WAV (reuse original header, update PCM region in-place)
    final mixed = wavBytes.toList();
    final pcmBytes = pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes);
    for (int i = 0; i < pcmBytes.length; i++) {
      mixed[44 + i] = pcmBytes[i];
    }
    await File(mixedWav).writeAsBytes(mixed);

    // 5. Mux mixed audio back into video using existing native replaceAudioTrack
    await _channel.invokeMethod('replaceAudioTrack', {
      'videoPath': videoPath,
      'audioPath': mixedWav,
      'outputPath': mixedVideo,
      'fileName': fileName,
    });

    // 6. Cleanup temp files
    try { File(videoPath).deleteSync(); } catch (_) {}
    try { File(extractedWav).deleteSync(); } catch (_) {}
    try { File(mixedWav).deleteSync(); } catch (_) {}

    return 'Movies/SubtitleAI/$fileName';
  }

  static Uint8List _generateSfxPcm(SfxType type, int sampleRate) {
    return switch (type) {
      SfxType.pop      => AudioSynth.generatePop(sampleRate),
      SfxType.ding     => AudioSynth.generateDing(sampleRate),
      SfxType.swoosh   => AudioSynth.generateSwoosh(sampleRate),
      SfxType.chime    => AudioSynth.generateChime(sampleRate),
      SfxType.drum     => AudioSynth.generateDrum(sampleRate),
      SfxType.beep     => AudioSynth.generateBeep(sampleRate),
      SfxType.bubble   => AudioSynth.generateBubble(sampleRate),
      SfxType.click    => AudioSynth.generateClick(sampleRate),
      SfxType.whoosh   => AudioSynth.generateWhoosh(sampleRate),
      SfxType.tada     => AudioSynth.generateTada(sampleRate),
      SfxType.bounce   => AudioSynth.generateBounce(sampleRate),
      SfxType.glitch   => AudioSynth.generateGlitch(sampleRate),
      SfxType.heart    => AudioSynth.generateHeart(sampleRate),
      SfxType.fire     => AudioSynth.generateFire(sampleRate),
      SfxType.wind     => AudioSynth.generateWind(sampleRate),
      SfxType.laugh    => AudioSynth.generateLaugh(sampleRate),
      SfxType.sad      => AudioSynth.generateSad(sampleRate),
      SfxType.magic    => AudioSynth.generateMagic(sampleRate),
      SfxType.power    => AudioSynth.generatePower(sampleRate),
      SfxType.surprise => AudioSynth.generateSurprise(sampleRate),
    };
  }

  static String buildSrtContent(List<SubtitleSegment> segments) =>
      _buildSrtContent(segments);

  static String _buildSrtContent(List<SubtitleSegment> segments) {
    final buffer = StringBuffer();
    for (int i = 0; i < segments.length; i++) {
      final s = segments[i];
      buffer.writeln('${i + 1}');
      buffer.writeln('${_toSrtTime(s.startTime)} --> ${_toSrtTime(s.endTime)}');
      buffer.writeln(s.text);
      buffer.writeln();
    }
    return buffer.toString();
  }

  static String _toSrtTime(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = d.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }

  static Future<List<int>> detectSpeechRegions(String videoPath) async {
    try {
      final List<dynamic>? res = await _channel.invokeMethod<List<dynamic>>('detectSpeechRegions', {
        'videoPath': videoPath,
      });
      return res?.cast<int>() ?? [];
    } catch (e) {
      debugPrint('Failed to detect speech regions: $e');
      return [];
    }
  }
}
