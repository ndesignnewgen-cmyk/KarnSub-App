import 'dart:convert';
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
        'segments': p.segments.map(_segmentToJson).toList(),
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
      segments: (j['segments'] as List<dynamic>)
          .map((s) => _segmentFromJson(s))
          .toList(),
    );
  }

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
