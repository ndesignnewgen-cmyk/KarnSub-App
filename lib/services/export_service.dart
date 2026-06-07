import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:saver_gallery/saver_gallery.dart';
import '../models/subtitle_style_model.dart';
import 'lao_font_service.dart';

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

    // We must run the audio-mix pass whenever any track is non-default:
    // SFX blocks exist, an AI-voice track is present, or the original audio
    // volume was changed / muted.
    final aiVoicePath = (project.aiVoicePath != null &&
            File(project.aiVoicePath!).existsSync())
        ? project.aiVoicePath
        : null;
    final bgMusicPath = (project.bgMusicPath != null &&
            File(project.bgMusicPath!).existsSync())
        ? project.bgMusicPath
        : null;
    final needsAudioMix = project.sfxBlocks.isNotEmpty ||
        aiVoicePath != null ||
        (bgMusicPath != null && !project.bgMusicMuted && project.bgMusicVolume > 0) ||
        project.originalMuted ||
        project.originalVolume != 1.0;
    String exportedPath = '';

    // Manual video cuts → keptRegions (the complement of removedRanges on the
    // ORIGINAL timeline). Native drops frames outside these and remaps PTS.
    final keptRegionsMs = _removedToKeptRegions(
      project.removedRanges,
      project.videoDuration?.inMilliseconds ?? 0,
    );

    // Zoom / Ken-Burns effects → flat maps for the native compositor.
    final zoomEffectsData = project.zoomEffects
        .map((z) => <String, dynamic>{
              'startMs': z.startTime.inMilliseconds,
              'endMs': z.endTime.inMilliseconds,
              'fromScale': z.fromScale,
              'toScale': z.toScale,
              'focusX': z.focusX,
              'focusY': z.focusY,
              if (z.keyframes.isNotEmpty)
                'keyframes': z.keyframes
                    .map((k) => <String, dynamic>{
                          'timeMs': k.timeMs,
                          'scale': k.scale,
                          'focusX': k.focusX,
                          'focusY': k.focusY,
                        })
                    .toList(),
            })
        .toList();

    // Fade transitions → flat maps for the native compositor.
    final fadeEffectsData = project.fadeEffects
        .map((f) => <String, dynamic>{
              'startMs': f.startTime.inMilliseconds,
              'endMs': f.endTime.inMilliseconds,
              'toBlack': f.toBlack,
            })
        .toList();

    // Camera-shake effects → flat maps for the native compositor.
    final shakeEffectsData = project.shakeEffects
        .map((s) => <String, dynamic>{
              'startMs': s.startTime.inMilliseconds,
              'endMs': s.endTime.inMilliseconds,
              'intensity': s.intensity,
            })
        .toList();

    // Image overlays → flat maps for the native compositor.
    final imageOverlaysData = project.imageOverlays
        .where((o) => File(o.path).existsSync())
        .map((o) => <String, dynamic>{
              'path': o.path,
              'startMs': o.startTime.inMilliseconds,
              'endMs': o.endTime.inMilliseconds,
              'x': o.x,
              'y': o.y,
              'scale': o.scale,
              'rotation': o.rotation,
              'flipH': o.flipH,
              if (o.isVideo) 'isVideo': true,
              if (o.cover) 'cover': true,
            })
        .toList();

    try {
      exportedPath = await _channel.invokeMethod('burnSubtitles', {
        'videoPath': videoPath,
        'outputPath': tempOutputPath,
        'fileName': fileName,
        'segments': segmentsData,
        'style': styleData,
        'autoCut': project.isAutoCut,
        if (keptRegionsMs != null) 'keptRegionsMs': keptRegionsMs,
        if (imageOverlaysData.isNotEmpty) 'imageOverlays': imageOverlaysData,
        if (zoomEffectsData.isNotEmpty) 'zoomEffects': zoomEffectsData,
        if (fadeEffectsData.isNotEmpty) 'fadeEffects': fadeEffectsData,
        if (shakeEffectsData.isNotEmpty) 'shakeEffects': shakeEffectsData,
        if (project.bgBlur) 'bgBlur': true,
        'returnTempPath': needsAudioMix,
      });
    } on PlatformException catch (e) {
      _channel.setMethodCallHandler(null);
      throw ExportException('Export ຜິດພາດ: ${e.message ?? 'Unknown'}');
    }

    _channel.setMethodCallHandler(null);

    if (needsAudioMix) {
      onProgress?.call(0.95, 'ກຳລັງ Mix ສຽງ...');
      try {
        final mixedVideoPath = await _mixAudioTracksNative(
          videoPath: exportedPath,
          sfxBlocks: project.sfxBlocks,
          aiVoicePath: aiVoicePath,
          originalVolume: project.originalMuted ? 0.0 : project.originalVolume,
          aiVoiceVolume: project.aiVoiceMuted ? 0.0 : project.aiVoiceVolume,
          aiVoiceSpeed: project.aiVoiceSpeed,
          sfxVolume: project.sfxMuted ? 0.0 : project.sfxVolume,
          aiVoiceOffsetMs: project.aiVoiceOffsetMs,
          aiVoiceTrimStartMs: project.aiVoiceTrimStartMs,
          aiVoiceTrimEndMs: project.aiVoiceTrimEndMs,
          bgMusicPath: (bgMusicPath != null && !project.bgMusicMuted) ? bgMusicPath : null,
          bgMusicVolume: project.bgMusicVolume,
          bgMusicDuck: project.bgMusicDuck,
          speechRangesMs: project.segments
              .map((s) => [s.startTime.inMilliseconds, s.endTime.inMilliseconds])
              .toList(),
          tempDirPath: tempDir.path,
          ts: ts,
          fileName: fileName,
        );
        onProgress?.call(1.0, 'ສຳເລັດ!');
        return mixedVideoPath;
      } catch (e, stack) {
        debugPrint('[ExportService] audio mix failed: $e\n$stack');
        try { File(exportedPath).deleteSync(); } catch (_) {}
        final errStr = e.toString().replaceAll('PlatformException', '');
        throw ExportException('ລວມສຽງບໍ່ສຳເລັດ: $errStr');
      }
    } else {
      onProgress?.call(1.0, 'ສຳເລັດ!');
      return exportedPath;
    }
  }

  /// Mix up to 3 audio tracks (original video audio + AI voice + SFX) into one,
  /// each scaled by its own volume, using pure Dart PCM mixing + native muxer.
  /// No FFmpeg required — reuses the existing extractAudio + replaceAudioTrack
  /// native methods. Everything is normalised to 16 kHz mono S16LE.
  static Future<String> _mixAudioTracksNative({
    required String videoPath,
    required List<SfxBlock> sfxBlocks,
    required String? aiVoicePath,
    required double originalVolume,
    required double aiVoiceVolume,
    required double aiVoiceSpeed,
    required double sfxVolume,
    required int aiVoiceOffsetMs,
    required int aiVoiceTrimStartMs,
    required int? aiVoiceTrimEndMs,
    String? bgMusicPath,
    double bgMusicVolume = 0.45,
    bool bgMusicDuck = true,
    List<List<int>> speechRangesMs = const [],
    required String tempDirPath,
    required int ts,
    required String fileName,
  }) async {
    const sampleRate = 44100; // matches native extractAudio TARGET_SAMPLE_RATE
    final extractedWav = p.join(tempDirPath, 'orig_audio_$ts.wav');
    final mixedWav     = p.join(tempDirPath, 'mixed_audio_$ts.wav');
    final mixedVideo   = p.join(tempDirPath, 'mixed_video_$ts.mp4');

    // 1. Extract original audio from the subtitle-burned video.
    await _channel.invokeMethod('extractAudio', {
      'videoPath': videoPath,
      'outputPath': extractedWav,
    });

    // 2. Read WAV → Int16List PCM (mutable copy we mix into).
    final wavBytes = await File(extractedWav).readAsBytes();
    if (wavBytes.length <= 44) throw Exception('Extracted WAV too small');
    final pcm = Int16List.sublistView(wavBytes, 44);

    // 3. Scale the original (main) audio by its volume.
    if (originalVolume != 1.0) {
      for (int i = 0; i < pcm.length; i++) {
        pcm[i] = (pcm[i] * originalVolume).round().clamp(-32768, 32767);
      }
    }

    // 4. Mix the AI-voice track (24 kHz from ElevenLabs/Google → resample to 44.1 kHz).
    if (aiVoicePath != null && aiVoiceVolume > 0) {
      final aiBytes = await File(aiVoicePath).readAsBytes();
      if (aiBytes.length > 44) {
        final aiRate = _getWavSampleRate(aiBytes);
        final aiChannels = _getWavChannels(aiBytes);
        final dataOffset = _getWavDataOffset(aiBytes);
        final rawPcm = Int16List.sublistView(aiBytes, dataOffset);
        
        final monoPcm = aiChannels > 1 ? _mixDownToMono(rawPcm, aiChannels) : rawPcm;
        final aiResampled = (aiRate == sampleRate && aiVoiceSpeed == 1.0)
            ? monoPcm
            : _resamplePcm16(monoPcm, aiRate, sampleRate, speed: aiVoiceSpeed);
        
        final startOffsetSamples = (aiVoiceOffsetMs > 0 ? (aiVoiceOffsetMs * sampleRate ~/ 1000) : 0).clamp(0, pcm.length);
        var baseTrimStart = (aiVoiceTrimStartMs * sampleRate ~/ 1000);
        if (aiVoiceOffsetMs < 0) {
          baseTrimStart += (-aiVoiceOffsetMs * sampleRate ~/ 1000);
        }
        final trimStartSamples = baseTrimStart.clamp(0, aiResampled.length);
        
        final trimEndSamples = aiVoiceTrimEndMs != null 
            ? (aiVoiceTrimEndMs * sampleRate ~/ 1000).clamp(0, aiResampled.length)
            : aiResampled.length;
            
        final visibleLen = (trimEndSamples - trimStartSamples).clamp(0, aiResampled.length - trimStartSamples);
        final copyLen = visibleLen.clamp(0, pcm.length - startOffsetSamples);
        
        for (int i = 0; i < copyLen; i++) {
          final mixed = (pcm[startOffsetSamples + i] + (aiResampled[trimStartSamples + i] * aiVoiceVolume).round()).clamp(-32768, 32767);
          pcm[startOffsetSamples + i] = mixed;
        }
      }
    }

    // 5. Mix each SFX block at its start-time offset, scaled by SFX volume.
    if (sfxVolume > 0) {
      for (final block in sfxBlocks) {
        final sfxBytes = await _loadSfxPcm(block.type, sampleRate, customPath: block.isCustom ? block.customPath : null);
        if (sfxBytes.isEmpty) continue;
        // The sfxBytes are now guaranteed to be aligned and even length.
        final sfxSamples = Int16List.view(sfxBytes.buffer, sfxBytes.offsetInBytes, sfxBytes.lengthInBytes ~/ 2);
        
        final trimStartSamples = (block.trimStart?.inMilliseconds ?? 0) * sampleRate ~/ 1000;
        final maxDurSamples = sfxSamples.length - trimStartSamples;
        if (maxDurSamples <= 0) continue;
        
        var durSamples = maxDurSamples;
        if (block.duration != null) {
          durSamples = (block.duration!.inMilliseconds * sampleRate ~/ 1000).clamp(0, maxDurSamples);
        } else if (!block.isCustom) {
          // For predefined SFX, if duration is null (old projects), fallback to default UI duration
          durSamples = (block.type.defaultDuration.inMilliseconds * sampleRate ~/ 1000).clamp(0, maxDurSamples);
        }
        
        final offsetSamples = (block.startTime.inMilliseconds * sampleRate ~/ 1000)
            .clamp(0, pcm.length - 1);
        final copyLen = durSamples.clamp(0, pcm.length - offsetSamples);
        
        // 50ms fade out to prevent clicking if the SFX is trimmed
        final isTrimmed = block.duration != null && block.duration!.inMilliseconds < (sfxSamples.length * 1000 ~/ sampleRate) - 100;
        final fadeOutSamples = isTrimmed ? (50 * sampleRate ~/ 1000).clamp(0, copyLen) : 0;
        
        final blockVol = sfxVolume * block.volume;
        for (int i = 0; i < copyLen; i++) {
          var vol = blockVol;
          if (fadeOutSamples > 0 && copyLen - i < fadeOutSamples) {
            vol = blockVol * (copyLen - i) / fadeOutSamples;
          }
          final mixed = (pcm[offsetSamples + i] + (sfxSamples[trimStartSamples + i] * vol).round())
              .clamp(-32768, 32767);
          pcm[offsetSamples + i] = mixed;
        }
      }
    }

    // 5b. Background music — loops to fill the video, auto-ducks under speech.
    if (bgMusicPath != null && bgMusicVolume > 0) {
      try {
        final bgWav = p.join(tempDirPath, 'bgmusic_$ts.wav');
        await _channel.invokeMethod('extractAudio', {
          'videoPath': bgMusicPath, // extractAudio decodes any media's audio track
          'outputPath': bgWav,
        });
        final bgBytes = await File(bgWav).readAsBytes();
        if (bgBytes.length > 44) {
          final bgRate = _getWavSampleRate(bgBytes);
          final bgCh = _getWavChannels(bgBytes);
          final bgOff = _getWavDataOffset(bgBytes);
          final rawBg = Int16List.sublistView(bgBytes, bgOff);
          final monoBg = bgCh > 1 ? _mixDownToMono(rawBg, bgCh) : rawBg;
          final bg = bgRate == sampleRate ? monoBg : _resamplePcm16(monoBg, bgRate, sampleRate);
          final musicLen = bg.length;
          if (musicLen > 0) {
            // Duck: drop music to 22% during speech, with an 80ms ramp so it
            // glides instead of clicking.
            const duckGain = 0.22;
            final rampSamples = (80 * sampleRate ~/ 1000).clamp(1, 1 << 30);
            final step = 1.0 / rampSamples;
            final sr = <List<int>>[];
            if (bgMusicDuck) {
              for (final r in speechRangesMs) {
                final a = (r[0] * sampleRate ~/ 1000);
                final b = (r[1] * sampleRate ~/ 1000);
                if (b > a) sr.add([a, b]);
              }
              sr.sort((x, y) => x[0].compareTo(y[0]));
            }
            double curGain = 1.0;
            int ridx = 0;
            for (int i = 0; i < pcm.length; i++) {
              while (ridx < sr.length && i >= sr[ridx][1]) ridx++;
              final inSpeech = ridx < sr.length && i >= sr[ridx][0] && i < sr[ridx][1];
              final target = inSpeech ? duckGain : 1.0;
              if (curGain < target) {
                curGain += step; if (curGain > target) curGain = target;
              } else if (curGain > target) {
                curGain -= step; if (curGain < target) curGain = target;
              }
              final m = bg[i % musicLen];
              pcm[i] = (pcm[i] + (m * bgMusicVolume * curGain).round())
                  .clamp(-32768, 32767);
            }
          }
        }
        try { File(bgWav).deleteSync(); } catch (_) {}
      } catch (e) {
        debugPrint('[ExportService] bg music mix skipped: $e');
      }
    }

    // 6. Write back as WAV (reuse the original 44-byte header, swap PCM region).
    final pcmBytes = pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes);
    final out = Uint8List(44 + pcmBytes.length);
    out.setRange(0, 44, wavBytes);
    out.setRange(44, out.length, pcmBytes);
    await File(mixedWav).writeAsBytes(out);

    // 7. Mux mixed audio back into video via the existing native muxer.
    await _channel.invokeMethod('replaceAudioTrack', {
      'videoPath': videoPath,
      'audioPath': mixedWav,
      'outputPath': mixedVideo,
      'fileName': fileName,
    });

    // 8. Cleanup temp files (NOT the AI-voice source — it's a saved track).
    try { File(videoPath).deleteSync(); } catch (_) {}
    try { File(extractedWav).deleteSync(); } catch (_) {}
    try { File(mixedWav).deleteSync(); } catch (_) {}

    return 'Movies/SubtitleAI/$fileName';
  }

  /// Linear resample of 16-bit mono PCM from [srcRate] to [dstRate], with optional [speed] factor.
  static Int16List _resamplePcm16(Int16List src, int srcRate, int dstRate, {double speed = 1.0}) {
    if ((srcRate == dstRate && speed == 1.0) || src.isEmpty) return src;
    final ratio = (srcRate / dstRate) * speed;
    final dstLen = (src.length / ratio).floor();
    final dst = Int16List(dstLen);
    for (int i = 0; i < dstLen; i++) {
      final srcPos = i * ratio;
      final i0 = srcPos.floor();
      final i1 = (i0 + 1 < src.length) ? i0 + 1 : i0;
      final frac = srcPos - i0;
      dst[i] = (src[i0] * (1 - frac) + src[i1] * frac).round().clamp(-32768, 32767);
    }
    return dst;
  }

  static Int16List _mixDownToMono(Int16List src, int channels) {
    if (channels <= 1) return src;
    final dstLen = src.length ~/ channels;
    final dst = Int16List(dstLen);
    for (int i = 0; i < dstLen; i++) {
      int sum = 0;
      for (int ch = 0; ch < channels; ch++) {
        sum += src[i * channels + ch];
      }
      dst[i] = (sum ~/ channels).clamp(-32768, 32767);
    }
    return dst;
  }

  static int _getWavSampleRate(Uint8List bytes) {
    if (bytes.length < 44) return 44100;
    final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    int offset = 12; // Skip RIFF, size, WAVE
    while (offset + 8 <= bd.lengthInBytes) {
      final chunkId = String.fromCharCodes(bytes.skip(offset).take(4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      if (chunkId == 'fmt ') {
        return bd.getUint32(offset + 12, Endian.little);
      }
      offset += 8 + chunkSize;
      if (chunkSize % 2 != 0) offset += 1;
    }
    return 44100;
  }

  static int _getWavChannels(Uint8List bytes) {
    if (bytes.length < 44) return 1;
    final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    int offset = 12; // Skip RIFF, size, WAVE
    while (offset + 8 <= bd.lengthInBytes) {
      final chunkId = String.fromCharCodes(bytes.skip(offset).take(4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      if (chunkId == 'fmt ') {
        return bd.getUint16(offset + 10, Endian.little); // offset+8 is fmt data, +2 is num channels
      }
      offset += 8 + chunkSize;
      if (chunkSize % 2 != 0) offset += 1;
    }
    return 1;
  }

  static int _getWavDataOffset(Uint8List bytes) {
    if (bytes.length < 44) return 44;
    final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    int offset = 12;
    while (offset + 8 <= bd.lengthInBytes) {
      final chunkId = String.fromCharCodes(bytes.skip(offset).take(4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      if (chunkId == 'data') {
        return offset + 8;
      }
      offset += 8 + chunkSize;
      if (chunkSize % 2 != 0) offset += 1;
    }
    return 44;
  }

  static Future<Uint8List> _loadSfxPcm(SfxType type, int sampleRate, {String? customPath}) async {
    String? assetPath;
    try {
      Uint8List bytes;
      if (customPath != null && customPath.isNotEmpty) {
        final file = File(customPath);
        if (!await file.exists()) return Uint8List(0);
        bytes = await file.readAsBytes();
        assetPath = customPath;
      } else {
        final name = type.name;
        final snakeCaseName = name.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}');
        assetPath = 'assets/sfx/$snakeCaseName.wav';
        final data = await rootBundle.load(assetPath);
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      }

      if (bytes.length > 44) {
        final srcRate = _getWavSampleRate(bytes);
        final srcChannels = _getWavChannels(bytes);
        final dataOffset = _getWavDataOffset(bytes);
        final length = bytes.lengthInBytes - dataOffset;
        final evenLength = (length ~/ 2) * 2;
        final pcmBytes = Uint8List.view(bytes.buffer, bytes.offsetInBytes + dataOffset, evenLength);
        
        final pcm16 = Int16List.view(pcmBytes.buffer, pcmBytes.offsetInBytes, pcmBytes.lengthInBytes ~/ 2);
        final monoPcm = srcChannels > 1 ? _mixDownToMono(pcm16, srcChannels) : pcm16;
        
        if (srcRate == sampleRate) {
          return monoPcm.buffer.asUint8List(monoPcm.offsetInBytes, monoPcm.lengthInBytes);
        } else {
          final resampled = _resamplePcm16(monoPcm, srcRate, sampleRate);
          return resampled.buffer.asUint8List(resampled.offsetInBytes, resampled.lengthInBytes);
        }
      }
    } catch (e, stack) {
      debugPrint('Failed to load SFX $assetPath: $e\n$stack');
    }
    return Uint8List(0);
  }

  /// Convert manual removed ranges → kept regions (flat ms pairs) covering the
  /// rest of [totalMs]. Returns null when nothing was cut. Native expects a flat
  /// list [start0,end0, start1,end1, ...] on the ORIGINAL timeline.
  static List<int>? _removedToKeptRegions(
      List<List<int>> removed, int totalMs) {
    if (removed.isEmpty || totalMs <= 0) return null;
    final sorted = [...removed]..sort((a, b) => a[0].compareTo(b[0]));
    final kept = <int>[];
    int cursor = 0;
    for (final r in sorted) {
      final a = r[0].clamp(0, totalMs);
      final b = r[1].clamp(0, totalMs);
      if (a > cursor) {
        kept..add(cursor)..add(a); // keep the gap before this cut
      }
      if (b > cursor) cursor = b;
    }
    if (cursor < totalMs) {
      kept..add(cursor)..add(totalMs); // keep the tail
    }
    return kept.isEmpty ? null : kept;
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
