import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/subtitle_style_model.dart';

class StorageService {
  static const _keyProjects = 'saved_projects';

  static Future<void> saveProjects(List<SubtitleProject> projects) async {
    final prefs = await SharedPreferences.getInstance();
    final list = projects.map((p) => _projectToJson(p)).toList();
    await prefs.setString(_keyProjects, jsonEncode(list));
  }

  static Future<List<SubtitleProject>> loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyProjects);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((j) => _projectFromJson(j)).toList();
    } catch (_) {
      return [];
    }
  }

  static Map<String, dynamic> _projectToJson(SubtitleProject p) => {
        'id': p.id,
        'name': p.name,
        'videoPath': p.videoPath,
        'thumbnailPath': p.thumbnailPath,
        'videoDurationMs': p.videoDuration?.inMilliseconds,
        'aspectRatio': p.aspectRatio.index,
        'styleType': p.selectedStyle.type.index,
        'wordSplit': p.wordSplit.index,
        'translateMode': p.translateMode.index,
        'createdAt': p.createdAt.millisecondsSinceEpoch,
        'language': p.language,
        'sourceLanguage': p.sourceLanguage,
        'transcriptionHint': p.transcriptionHint,
        'proofread': p.proofread,
        'fontSize': p.fontSize,
        'fontWeight': p.fontWeight,
        'subtitlePositionY': p.subtitlePositionY,
        'fontFamily': p.fontFamily,
        'isKaraokeHighlight': p.isKaraokeHighlight,
        'karaokeHighlightColor': p.karaokeHighlightColor.value,
        'karaokeScale': p.karaokeScale,
        'bilingualPresetIndex': p.bilingualPresetIndex,
        'bilingualFontSize': p.bilingualFontSize,
        'bilingualGap': p.bilingualGap,
        'showBilingual': p.showBilingual,
        'subtitleAnimation': p.subtitleAnimation.index,
        'exitAnimation': p.exitAnimation.index,
        'animationSpeed': p.animationSpeed.index,
        'isAutoCut': p.isAutoCut,
        'autoCutGapMs': p.autoCutGapMs,
        'isAutoSyncSfx': p.isAutoSyncSfx,
        // Audio mixer (3 tracks): original / AI voice / SFX.
        'originalVolume': p.originalVolume,
        'aiVoiceVolume': p.aiVoiceVolume,
        'sfxVolume': p.sfxVolume,
        'originalMuted': p.originalMuted,
        'aiVoiceMuted': p.aiVoiceMuted,
        'sfxMuted': p.sfxMuted,
        if (p.aiVoicePath != null) 'aiVoicePath': p.aiVoicePath,
        if (p.aiVoiceDurationMs != null) 'aiVoiceDurationMs': p.aiVoiceDurationMs,
        'aiVoiceOffsetMs': p.aiVoiceOffsetMs,
        'aiVoiceTrimStartMs': p.aiVoiceTrimStartMs,
        'aiVoiceTrimEndMs': p.aiVoiceTrimEndMs,
        'aiVoiceSpeed': p.aiVoiceSpeed,
        if (p.bgMusicPath != null) 'bgMusicPath': p.bgMusicPath,
        if (p.bgMusicDurationMs != null) 'bgMusicDurationMs': p.bgMusicDurationMs,
        'bgMusicVolume': p.bgMusicVolume,
        'bgMusicMuted': p.bgMusicMuted,
        'bgMusicDuck': p.bgMusicDuck,
        'bgBlur': p.bgBlur,
        'removedRanges': p.removedRanges,
        'splitPointsMs': p.splitPointsMs,
        'imageOverlays': p.imageOverlays.map(_imageOverlayToJson).toList(),
        'zoomEffects': p.zoomEffects.map(_zoomEffectToJson).toList(),
        'fadeEffects': p.fadeEffects.map(_fadeEffectToJson).toList(),
        'shakeEffects': p.shakeEffects.map(_shakeEffectToJson).toList(),
        'segments': p.segments.map(_segmentToJson).toList(),
        'sfxBlocks': p.sfxBlocks.map(_sfxBlockToJson).toList(),
      };

  static SubtitleProject _projectFromJson(Map<String, dynamic> j) {
    final styleIndex = (j['styleType'] as int).clamp(0, subtitlePresets.length - 1);
    return SubtitleProject(
      id: j['id'],
      name: j['name'],
      videoPath: j['videoPath'],
      thumbnailPath: j['thumbnailPath'] as String?,
      videoDuration: (j['videoDurationMs'] as int?) != null
          ? Duration(milliseconds: j['videoDurationMs'] as int)
          : null,
      aspectRatio: AspectRatioMode.values[j['aspectRatio'] ?? 0],
      selectedStyle: subtitlePresets[styleIndex],
      wordSplit: WordSplit.values[j['wordSplit'] ?? 0],
      translateMode: TranslateMode.values[j['translateMode'] ?? 0],
      createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt'] ?? 0),
      language: j['language'] as String? ?? 'lo',
      sourceLanguage: j['sourceLanguage'] as String? ?? 'th',
      transcriptionHint: j['transcriptionHint'] as String? ?? '',
      proofread: j['proofread'] as bool? ?? true,
      fontSize: (j['fontSize'] as num?)?.toDouble() ?? 18.0,
      fontWeight: (j['fontWeight'] as int?) ?? 600,
      subtitlePositionY: (j['subtitlePositionY'] as num?)?.toDouble() ?? 0.85,
      fontFamily: j['fontFamily'] as String? ?? 'NotoSansLao',
      isKaraokeHighlight: j['isKaraokeHighlight'] as bool? ?? false,
      karaokeHighlightColor: Color(j['karaokeHighlightColor'] as int? ?? 0xFF9C59F5),
      karaokeScale: j['karaokeScale'] as bool? ?? false,
      bilingualPresetIndex: (j['bilingualPresetIndex'] as int? ?? 1).clamp(0, subtitlePresets.length - 1),
      bilingualFontSize: (j['bilingualFontSize'] as num?)?.toDouble() ?? 13.0,
      bilingualGap: (j['bilingualGap'] as num?)?.toDouble() ?? 4.0,
      showBilingual: j['showBilingual'] as bool? ?? false,
      subtitleAnimation: SubtitleAnimation.values[(j['subtitleAnimation'] as int? ?? 0).clamp(0, SubtitleAnimation.values.length - 1)],
      exitAnimation: SubtitleAnimation.values[(j['exitAnimation'] as int? ?? 0).clamp(0, SubtitleAnimation.values.length - 1)],
      animationSpeed: AnimationSpeed.values[(j['animationSpeed'] as int? ?? 1).clamp(0, AnimationSpeed.values.length - 1)],
      isAutoCut: j['isAutoCut'] as bool? ?? false,
      autoCutGapMs: (j['autoCutGapMs'] as num?)?.toInt() ?? 300,
      isAutoSyncSfx: j['isAutoSyncSfx'] as bool? ?? false,
      originalVolume: (j['originalVolume'] as num?)?.toDouble() ?? 1.0,
      aiVoiceVolume: (j['aiVoiceVolume'] as num?)?.toDouble() ?? 1.0,
      sfxVolume: (j['sfxVolume'] as num?)?.toDouble() ?? 1.0,
      originalMuted: j['originalMuted'] as bool? ?? false,
      aiVoiceMuted: j['aiVoiceMuted'] as bool? ?? false,
      sfxMuted: j['sfxMuted'] as bool? ?? false,
      // Drop a stale AI-voice path if the file no longer exists on disk.
      aiVoicePath: () {
        final pth = j['aiVoicePath'] as String?;
        return (pth != null && File(pth).existsSync()) ? pth : null;
      }(),
      aiVoiceDurationMs: j['aiVoiceDurationMs'] as int?,
      aiVoiceOffsetMs: j['aiVoiceOffsetMs'] as int? ?? 0,
      aiVoiceTrimStartMs: j['aiVoiceTrimStartMs'] as int? ?? 0,
      aiVoiceTrimEndMs: j['aiVoiceTrimEndMs'] as int?,
      aiVoiceSpeed: (j['aiVoiceSpeed'] as num?)?.toDouble() ?? 1.0,
      // Drop a stale bg-music path if the file no longer exists on disk.
      bgMusicPath: () {
        final pth = j['bgMusicPath'] as String?;
        return (pth != null && File(pth).existsSync()) ? pth : null;
      }(),
      bgMusicDurationMs: j['bgMusicDurationMs'] as int?,
      bgMusicVolume: (j['bgMusicVolume'] as num?)?.toDouble() ?? 0.45,
      bgMusicMuted: j['bgMusicMuted'] as bool? ?? false,
      bgMusicDuck: j['bgMusicDuck'] as bool? ?? true,
      bgBlur: j['bgBlur'] as bool? ?? false,
      removedRanges: (j['removedRanges'] as List<dynamic>?)
              ?.map((r) => (r as List<dynamic>).map((e) => e as int).toList())
              .toList() ??
          [],
      splitPointsMs: (j['splitPointsMs'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      imageOverlays: (j['imageOverlays'] as List<dynamic>?)
              ?.map((o) => _imageOverlayFromJson(o as Map<String, dynamic>))
              .where((o) => o != null)
              .cast<ImageOverlay>()
              .toList() ??
          [],
      zoomEffects: (j['zoomEffects'] as List<dynamic>?)
              ?.map((z) => _zoomEffectFromJson(z as Map<String, dynamic>))
              .toList() ??
          [],
      fadeEffects: (j['fadeEffects'] as List<dynamic>?)
              ?.map((f) => _fadeEffectFromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
      shakeEffects: (j['shakeEffects'] as List<dynamic>?)
              ?.map((s) => _shakeEffectFromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      segments: (j['segments'] as List<dynamic>)
          .map((s) => _segmentFromJson(s))
          .toList(),
      sfxBlocks: (j['sfxBlocks'] as List<dynamic>?)
              ?.map((s) => _sfxBlockFromJson(s))
              .toList() ??
          [],
    );
  }

  static Map<String, dynamic> _imageOverlayToJson(ImageOverlay o) => {
        'id': o.id,
        'path': o.path,
        'startMs': o.startTime.inMilliseconds,
        'endMs': o.endTime.inMilliseconds,
        'x': o.x,
        'y': o.y,
        'scale': o.scale,
        'rotation': o.rotation,
        'flipH': o.flipH,
        'isVideo': o.isVideo,
        'cover': o.cover,
        'opacity': o.opacity,
        'keyframes': o.keyframes
            .map((k) => {
                  'timeMs': k.timeMs,
                  'x': k.x,
                  'y': k.y,
                  'scale': k.scale,
                  'rotation': k.rotation,
                  'opacity': k.opacity,
                  'easing': k.easing,
                })
            .toList(),
      };

  // Returns null if the overlay's image file is gone (drops stale entries).
  static ImageOverlay? _imageOverlayFromJson(Map<String, dynamic> j) {
    final path = j['path'] as String?;
    if (path == null || !File(path).existsSync()) return null;
    return ImageOverlay(
      id: j['id'] as String,
      path: path,
      startTime: Duration(milliseconds: j['startMs'] as int? ?? 0),
      endTime: Duration(milliseconds: j['endMs'] as int? ?? 3000),
      x: (j['x'] as num?)?.toDouble() ?? 0.5,
      y: (j['y'] as num?)?.toDouble() ?? 0.5,
      scale: (j['scale'] as num?)?.toDouble() ?? 0.5,
      rotation: (j['rotation'] as num?)?.toDouble() ?? 0.0,
      flipH: j['flipH'] as bool? ?? false,
      isVideo: j['isVideo'] as bool? ?? false,
      cover: j['cover'] as bool? ?? false,
      opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
      keyframes: (j['keyframes'] as List<dynamic>?)
              ?.map((e) {
                final m = e as Map<String, dynamic>;
                return OverlayKeyframe(
                  timeMs: (m['timeMs'] as num?)?.toInt() ?? 0,
                  x: (m['x'] as num?)?.toDouble() ?? 0.5,
                  y: (m['y'] as num?)?.toDouble() ?? 0.5,
                  scale: (m['scale'] as num?)?.toDouble() ?? 0.5,
                  rotation: (m['rotation'] as num?)?.toDouble() ?? 0.0,
                  opacity: (m['opacity'] as num?)?.toDouble() ?? 1.0,
                  easing: (m['easing'] as num?)?.toInt() ?? 0,
                );
              })
              .toList() ??
          [],
    );
  }

  static Map<String, dynamic> _zoomEffectToJson(ZoomEffect z) => {
        'id': z.id,
        'startMs': z.startTime.inMilliseconds,
        'endMs': z.endTime.inMilliseconds,
        'fromScale': z.fromScale,
        'toScale': z.toScale,
        'focusX': z.focusX,
        'focusY': z.focusY,
        if (z.keyframes.isNotEmpty)
          'keyframes': z.keyframes
              .map((k) => {
                    'timeMs': k.timeMs,
                    'scale': k.scale,
                    'focusX': k.focusX,
                    'focusY': k.focusY,
                    'easing': k.easing,
                  })
              .toList(),
      };

  static ZoomEffect _zoomEffectFromJson(Map<String, dynamic> j) => ZoomEffect(
        id: j['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
        startTime: Duration(milliseconds: j['startMs'] as int? ?? 0),
        endTime: Duration(milliseconds: j['endMs'] as int? ?? 1000),
        fromScale: (j['fromScale'] as num?)?.toDouble() ?? 1.0,
        toScale: (j['toScale'] as num?)?.toDouble() ?? 1.3,
        focusX: (j['focusX'] as num?)?.toDouble() ?? 0.5,
        focusY: (j['focusY'] as num?)?.toDouble() ?? 0.5,
        keyframes: (j['keyframes'] as List<dynamic>?)
            ?.map((k) => ZoomKeyframe(
                  timeMs: (k['timeMs'] as num?)?.toInt() ?? 0,
                  scale: (k['scale'] as num?)?.toDouble() ?? 1.0,
                  focusX: (k['focusX'] as num?)?.toDouble() ?? 0.5,
                  focusY: (k['focusY'] as num?)?.toDouble() ?? 0.5,
                  easing: (k['easing'] as num?)?.toInt() ?? 0,
                ))
            .toList(),
      );

  static Map<String, dynamic> _fadeEffectToJson(FadeEffect f) => {
        'id': f.id,
        'startMs': f.startTime.inMilliseconds,
        'endMs': f.endTime.inMilliseconds,
        'toBlack': f.toBlack,
      };

  static FadeEffect _fadeEffectFromJson(Map<String, dynamic> j) => FadeEffect(
        id: j['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
        startTime: Duration(milliseconds: j['startMs'] as int? ?? 0),
        endTime: Duration(milliseconds: j['endMs'] as int? ?? 500),
        toBlack: j['toBlack'] as bool? ?? true,
      );

  static Map<String, dynamic> _shakeEffectToJson(ShakeEffect s) => {
        'id': s.id,
        'startMs': s.startTime.inMilliseconds,
        'endMs': s.endTime.inMilliseconds,
        'intensity': s.intensity,
      };

  static ShakeEffect _shakeEffectFromJson(Map<String, dynamic> j) => ShakeEffect(
        id: j['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
        startTime: Duration(milliseconds: j['startMs'] as int? ?? 0),
        endTime: Duration(milliseconds: j['endMs'] as int? ?? 500),
        intensity: (j['intensity'] as num?)?.toDouble() ?? 0.03,
      );

  static Map<String, dynamic> _sfxBlockToJson(SfxBlock s) => {
        'id': s.id,
        'type': s.type.index,
        'startMs': s.startTime.inMilliseconds,
        if (s.duration != null) 'durationMs': s.duration!.inMilliseconds,
        if (s.trimStart != null) 'trimStartMs': s.trimStart!.inMilliseconds,
        'volume': s.volume,
        'isCustom': s.isCustom,
        if (s.customPath != null) 'customPath': s.customPath,
        if (s.customName != null) 'customName': s.customName,
      };

  static SfxBlock _sfxBlockFromJson(Map<String, dynamic> j) => SfxBlock(
        id: j['id'],
        type: SfxType.values[(j['type'] as int?)?.clamp(0, SfxType.values.length - 1) ?? 0],
        startTime: Duration(milliseconds: j['startMs'] as int? ?? 0),
        duration: j['durationMs'] != null ? Duration(milliseconds: j['durationMs'] as int) : null,
        trimStart: j['trimStartMs'] != null ? Duration(milliseconds: j['trimStartMs'] as int) : null,
        volume: (j['volume'] as num?)?.toDouble() ?? 1.0,
        isCustom: j['isCustom'] as bool? ?? false,
        customPath: j['customPath'] as String?,
        customName: j['customName'] as String?,
      );

  static Map<String, dynamic> _segmentToJson(SubtitleSegment s) => {
        'id': s.id,
        'text': s.text,
        'start': s.startTime.inMilliseconds,
        'end': s.endTime.inMilliseconds,
        if (s.translatedText != null) 'translatedText': s.translatedText,
        if (s.wordTimings != null)
          'wordTimings': s.wordTimings!.map((d) => d.inMilliseconds).toList(),
        if (s.words != null) 'words': s.words,
        if (s.styleIndex != null) 'styleIndex': s.styleIndex,
        if (s.fontFamily != null) 'segFontFamily': s.fontFamily,
        if (s.fontSize != null) 'segFontSize': s.fontSize,
        if (s.fontWeight != null) 'segFontWeight': s.fontWeight,
        if (s.textColorValue != null) 'segTextColor': s.textColorValue,
        if (s.animation != null) 'segAnimation': s.animation!.index,
        if (s.positionY != null) 'segPositionY': s.positionY,
        if (s.positionX != null) 'segPositionX': s.positionX,
        if (s.rotation != null) 'segRotation': s.rotation,
        if (s.karaoke != null) 'segKaraoke': s.karaoke,
        if (s.karaokeScale != null) 'segKaraokeScale': s.karaokeScale,
        if (s.emphasis != null) 'segEmphasis': s.emphasis,
        if (s.emoji != null) 'segEmoji': s.emoji,
      };

  static SubtitleSegment _segmentFromJson(Map<String, dynamic> j) {
    final animIdx = j['segAnimation'] as int?;
    return SubtitleSegment(
      id: j['id'],
      text: j['text'],
      startTime: Duration(milliseconds: j['start']),
      endTime: Duration(milliseconds: j['end']),
      translatedText: j['translatedText'] as String?,
      wordTimings: (j['wordTimings'] as List<dynamic>?)
          ?.map((ms) => Duration(milliseconds: ms as int))
          .toList(),
      words: (j['words'] as List<dynamic>?)?.map((w) => w as String).toList(),
      styleIndex: (j['styleIndex'] as int?)
          ?.clamp(0, subtitlePresets.length - 1),
      fontFamily: j['segFontFamily'] as String?,
      fontSize: (j['segFontSize'] as num?)?.toDouble(),
      fontWeight: j['segFontWeight'] as int?,
      textColorValue: j['segTextColor'] as int?,
      animation: animIdx != null
          ? SubtitleAnimation.values[
              animIdx.clamp(0, SubtitleAnimation.values.length - 1)]
          : null,
      positionY: (j['segPositionY'] as num?)?.toDouble(),
      positionX: (j['segPositionX'] as num?)?.toDouble(),
      rotation: (j['segRotation'] as num?)?.toDouble(),
      karaoke: j['segKaraoke'] as bool?,
      karaokeScale: j['segKaraokeScale'] as bool?,
      emphasis: (j['segEmphasis'] as List<dynamic>?)
          ?.map((e) => e as int)
          .toList(),
      emoji: j['segEmoji'] as String?,
    );
  }
}
