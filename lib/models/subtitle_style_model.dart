import 'package:flutter/material.dart';

/// Map a numeric weight (100..900) to a Flutter [FontWeight].
FontWeight fontWeightFromInt(int w) {
  final idx = ((w ~/ 100) - 1).clamp(0, 8);
  return FontWeight.values[idx];
}

bool _isAsciiWordChar(int c) =>
    (c >= 0x41 && c <= 0x5A) || // A-Z
    (c >= 0x61 && c <= 0x7A) || // a-z
    (c >= 0x30 && c <= 0x39);   // 0-9

/// Whether a space should be drawn between two adjacent word tokens.
/// Lao/Thai words stay tight (no space); a space is added only when either
/// boundary touches a Latin letter or digit (mixed Lao+English / numbers).
bool needSpaceBetweenWords(String prev, String cur) {
  if (prev.isEmpty || cur.isEmpty) return false;
  return _isAsciiWordChar(prev.codeUnitAt(prev.length - 1)) ||
      _isAsciiWordChar(cur.codeUnitAt(0));
}

/// Split text into karaoke highlight units: Latin/number runs stay whole
/// (separated by spaces), Lao/Thai text is broken into syllable-ish units so
/// the highlight can sweep word-by-word even when there are no spaces.
List<String> splitLaoHighlightUnits(String text) {
  bool isLaoCons(int c) =>
      (c >= 0x0E81 && c <= 0x0EAE) || (c >= 0x0E01 && c <= 0x0E2E); // Lao + Thai consonants
  bool isLaoLead(int c) =>
      (c >= 0x0EC0 && c <= 0x0EC4) || (c >= 0x0E40 && c <= 0x0E44); // leading vowels ເແໂໃໄ / เแโใไ

  final units = <String>[];
  final sb = StringBuffer();
  bool sbIsAscii = false; // current buffer is a Latin/number run
  void flush() {
    if (sb.isNotEmpty) {
      units.add(sb.toString());
      sb.clear();
    }
  }

  for (int i = 0; i < text.length; i++) {
    final ch = text[i];
    final c = text.codeUnitAt(i);
    if (ch == ' ') {
      flush();
      sbIsAscii = false;
      continue;
    }
    final ascii = _isAsciiWordChar(c);
    if (ascii) {
      // Keep English words / numbers whole, but split them off from Lao.
      if (sb.isNotEmpty && !sbIsAscii) flush();
      sb.write(ch);
      sbIsAscii = true;
      continue;
    }
    // A Lao (or other) char ends any Latin/number run first.
    if (sb.isNotEmpty && sbIsAscii) flush();
    sbIsAscii = false;
    if (isLaoLead(c)) {
      flush();
      sb.write(ch);
    } else if (isLaoCons(c)) {
      if (sb.isNotEmpty) {
        final prevLast = sb.toString().codeUnitAt(sb.length - 1);
        if (!isLaoLead(prevLast)) flush(); // start a new syllable
      }
      sb.write(ch);
    } else {
      sb.write(ch); // vowel signs, tones → attach
    }
  }
  flush();
  final result = units.where((u) => u.trim().isNotEmpty).toList();
  if (result.isEmpty) return [text];
  // Merge a stray single final consonant into the previous unit (a Lao syllable
  // can't begin with a bare final consonant), so "ທາງ" stays "ທາງ" not "ທາ"+"ງ".
  bool isLaoConsonant(int c) =>
      (c >= 0x0E81 && c <= 0x0EAE) || (c >= 0x0E01 && c <= 0x0E2E);
  final merged = <String>[];
  for (final u in result) {
    if (merged.isNotEmpty &&
        u.length == 1 &&
        isLaoConsonant(u.codeUnitAt(0))) {
      merged[merged.length - 1] = merged.last + u;
    } else {
      merged.add(u);
    }
  }
  return merged;
}

/// Join word tokens into display text using [needSpaceBetweenWords] rules.
String joinWordsSmart(List<String> words) {
  final tokens = words.where((w) => w.isNotEmpty).toList();
  if (tokens.isEmpty) return '';
  final sb = StringBuffer(tokens.first);
  for (int i = 1; i < tokens.length; i++) {
    if (needSpaceBetweenWords(tokens[i - 1], tokens[i])) sb.write(' ');
    sb.write(tokens[i]);
  }
  return sb.toString();
}

enum SubtitleStyleType {
  standard,
  minimal,
  boldPop,
  neonGreen,
  karaoke,
  popLine,
  pastel,
  classic,
  fire,
  shadow,
  mrBeast,
  podcast,
  movie,
  neonPink,
  galaxy,
  goldBox,
  retro3d,
  outline,
  gradient,
  marker,
  hormozi,
}

enum WordSplit { none, one, two, three, four, six, eight }

enum AnimationSpeed { slow, normal, fast }

/// Entrance/exit animation duration (ms) for a speed setting.
int animationDurationMs(AnimationSpeed s) => switch (s) {
      AnimationSpeed.slow => 560,
      AnimationSpeed.normal => 350,
      AnimationSpeed.fast => 190,
    };

/// Typewriter reveal speed (ms per syllable unit) for a speed setting.
int typewriterUnitMs(AnimationSpeed s) => switch (s) {
      AnimationSpeed.slow => 85,
      AnimationSpeed.normal => 55,
      AnimationSpeed.fast => 32,
    };

enum SubtitleAnimation {
  none,
  fadeIn,
  slideUp,
  slideDown,
  slideLeft,
  bounceIn,
  typewriter,
}

enum TranslateMode { none, translate, bilingual }

enum AspectRatioMode { ratio9x16, ratio1x1, ratio16x9, ratio4x5 }

class SubtitlePreset {
  final SubtitleStyleType type;
  final String name;
  final Color textColor;
  final Color? backgroundColor;
  final double fontSize;
  final FontWeight fontWeight;
  final bool hasShadow;
  final bool hasNeonGlow;
  final bool hasUnderline;
  final bool isKaraoke;
  final Color? glowColor;
  final Color? underlineColor;
  // Thick retro extruded "3D" shadow (offset block behind the text).
  final bool has3dShadow;
  // Hard outline (stroke) around the glyphs (TikTok sticker look).
  final bool hasOutline;
  final Color? outlineColor;
  // Gradient fill across the text (null = solid textColor).
  final List<Color>? gradientColors;
  // PRO-only style — free users see it locked.
  final bool isPro;

  const SubtitlePreset({
    required this.type,
    required this.name,
    required this.textColor,
    this.backgroundColor,
    this.fontSize = 18,
    this.fontWeight = FontWeight.w600,
    this.hasShadow = false,
    this.hasNeonGlow = false,
    this.hasUnderline = false,
    this.isKaraoke = false,
    this.glowColor,
    this.underlineColor,
    this.has3dShadow = false,
    this.hasOutline = false,
    this.outlineColor,
    this.gradientColors,
    this.isPro = false,
  });
}

const List<SubtitlePreset> subtitlePresets = [
  SubtitlePreset(
    type: SubtitleStyleType.standard,
    name: 'ມາດຕະຖານ',
    textColor: Colors.white,
    backgroundColor: Color(0xCC000000),
    fontWeight: FontWeight.w600,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.minimal,
    name: 'ມິນິມອນ',
    textColor: Colors.white,
    backgroundColor: null,
    hasShadow: true,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.boldPop,
    name: 'ໂດດເດັ່ນ',
    textColor: Color(0xFFFFD700),
    backgroundColor: Colors.black,
    fontWeight: FontWeight.w900,
    fontSize: 20,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.neonGreen,
    name: 'ນີອອນຂຽວ',
    textColor: Color(0xFF39FF14),
    hasNeonGlow: true,
    glowColor: Color(0xFF39FF14),
    fontWeight: FontWeight.bold,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.karaoke,
    name: 'ຄາລາໂອເກະ',
    textColor: Colors.white,
    backgroundColor: Color(0xFF6C63FF),
    isKaraoke: true,
    fontWeight: FontWeight.bold,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.popLine,
    name: 'ປ໋ອບໄລນ໌',
    textColor: Colors.white,
    hasUnderline: true,
    underlineColor: Color(0xFF6C63FF),
    fontWeight: FontWeight.bold,
    fontSize: 20,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.pastel,
    name: 'ພາສະເທນ',
    textColor: Color(0xFFFF9EC4),
    fontWeight: FontWeight.w700,
    hasShadow: true,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.classic,
    name: 'ຄລາດສິກ',
    textColor: Colors.white,
    hasShadow: true,
    fontWeight: FontWeight.bold,
    fontSize: 20,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.fire,
    name: 'ໄຟ',
    textColor: Color(0xFFFF6B35),
    backgroundColor: Color(0xFF1A0A00),
    hasNeonGlow: true,
    glowColor: Color(0xFFFF4500),
    fontWeight: FontWeight.w900,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.shadow,
    name: 'ເງົາ',
    textColor: Colors.white,
    backgroundColor: Color(0x80000000),
    hasShadow: true,
    fontWeight: FontWeight.w700,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.mrBeast,
    name: 'MrBeast',
    textColor: Colors.white,
    backgroundColor: Colors.black,
    fontWeight: FontWeight.w900,
    fontSize: 22,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.podcast,
    name: 'Podcast',
    textColor: Colors.white,
    backgroundColor: Color(0xCC1A1A2E),
    fontWeight: FontWeight.w500,
    fontSize: 16,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.movie,
    name: 'Movie',
    textColor: Color(0xFFFFF9C4),
    hasShadow: true,
    fontWeight: FontWeight.w600,
    fontSize: 18,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.neonPink,
    name: 'Neon Pink',
    textColor: Color(0xFFFF6BDE),
    hasNeonGlow: true,
    glowColor: Color(0xFFFF6BDE),
    fontWeight: FontWeight.bold,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.galaxy,
    name: 'Galaxy',
    textColor: Color(0xFFB0E0FF),
    backgroundColor: Color(0xCC0D0D2B),
    hasNeonGlow: true,
    glowColor: Color(0xFF6C9EFF),
    fontWeight: FontWeight.bold,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.goldBox,
    name: 'ກ່ອງຄຳ',
    textColor: Colors.black,
    backgroundColor: Color(0xFFFFC107),
    fontWeight: FontWeight.w900,
    fontSize: 19,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.retro3d,
    name: '3D Shadow',
    textColor: Colors.white,
    has3dShadow: true,
    isPro: true,
    fontWeight: FontWeight.w900,
    fontSize: 21,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.outline,
    name: 'ຂອບໜາ',
    textColor: Colors.white,
    hasOutline: true,
    outlineColor: Colors.black,
    isPro: true,
    fontWeight: FontWeight.w900,
    fontSize: 20,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.gradient,
    name: 'ໄລ່ສີ',
    textColor: Colors.white,
    gradientColors: [Color(0xFF7F00FF), Color(0xFFE100FF)],
    hasShadow: true,
    isPro: true,
    fontWeight: FontWeight.w900,
    fontSize: 20,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.marker,
    name: 'ໄຮໄລ້',
    textColor: Colors.black,
    backgroundColor: Color(0xF2FFE808),
    isPro: true,
    fontWeight: FontWeight.w800,
    fontSize: 19,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.hormozi,
    name: 'Hormozi',
    textColor: Color(0xFFFFE808),
    hasOutline: true,
    outlineColor: Colors.black,
    isPro: true,
    fontWeight: FontWeight.w900,
    fontSize: 23,
  ),
  SubtitlePreset(
    type: SubtitleStyleType.outline,
    name: 'ສົ້ມໜາ',
    textColor: Color(0xFFF7A823), // amber/orange fill
    hasOutline: true,
    outlineColor: Colors.black,
    hasShadow: true, // soft drop shadow behind the outline
    isPro: true,
    fontWeight: FontWeight.w900,
    fontSize: 23,
  ),
];

/// A one-tap "look" — bundles a preset + size/position + karaoke + animation so
/// a creator gets a polished result instantly (like CapCut/Submagic templates).
class SubtitleTemplate {
  final String name;
  final String emoji; // shown on the template card
  final SubtitleStyleType styleType;
  final String fontFamily;
  final double fontSize;
  final int fontWeight; // 100..900
  final double positionY; // 0..1
  final bool karaoke;
  final int karaokeColorValue; // ARGB
  final bool karaokeScale; // Word Pop
  final SubtitleAnimation animation;
  final SubtitleAnimation exitAnimation;
  final AnimationSpeed speed;
  final bool isPro;

  const SubtitleTemplate({
    required this.name,
    required this.emoji,
    required this.styleType,
    this.fontFamily = 'NotoSansLao',
    this.fontSize = 18,
    this.fontWeight = 600,
    this.positionY = 0.85,
    this.karaoke = false,
    this.karaokeColorValue = 0xFF9C59F5,
    this.karaokeScale = false,
    this.animation = SubtitleAnimation.fadeIn,
    this.exitAnimation = SubtitleAnimation.none,
    this.speed = AnimationSpeed.normal,
    this.isPro = false,
  });
}

const subtitleTemplates = <SubtitleTemplate>[
  SubtitleTemplate(
    name: 'ມາດຕະຖານ',
    emoji: '✨',
    styleType: SubtitleStyleType.standard,
    fontWeight: 600,
    animation: SubtitleAnimation.fadeIn,
  ),
  SubtitleTemplate(
    name: 'Minimal',
    emoji: '⚪',
    styleType: SubtitleStyleType.minimal,
    fontWeight: 500,
    positionY: 0.9,
    animation: SubtitleAnimation.none,
  ),
  SubtitleTemplate(
    name: 'Karaoke',
    emoji: '🎤',
    styleType: SubtitleStyleType.boldPop,
    fontWeight: 800,
    fontSize: 20,
    karaoke: true,
    karaokeScale: true,
    animation: SubtitleAnimation.bounceIn,
    isPro: true,
  ),
  SubtitleTemplate(
    name: 'TikTok',
    emoji: '🔥',
    styleType: SubtitleStyleType.boldPop,
    fontWeight: 900,
    fontSize: 21,
    karaoke: true,
    karaokeColorValue: 0xFFFFE808,
    karaokeScale: true,
    animation: SubtitleAnimation.slideUp,
    speed: AnimationSpeed.fast,
    isPro: true,
  ),
  SubtitleTemplate(
    name: 'Hormozi',
    emoji: '💪',
    styleType: SubtitleStyleType.hormozi,
    fontWeight: 900,
    fontSize: 23,
    karaoke: true,
    karaokeColorValue: 0xFF39FF14,
    karaokeScale: true,
    animation: SubtitleAnimation.slideUp,
    speed: AnimationSpeed.fast,
    isPro: true,
  ),
  SubtitleTemplate(
    name: 'ນີອອນ',
    emoji: '💚',
    styleType: SubtitleStyleType.neonGreen,
    fontWeight: 700,
    animation: SubtitleAnimation.fadeIn,
    isPro: true,
  ),
  SubtitleTemplate(
    name: 'ໄຮໄລ້',
    emoji: '🟡',
    styleType: SubtitleStyleType.marker,
    fontWeight: 800,
    fontSize: 19,
    animation: SubtitleAnimation.fadeIn,
    isPro: true,
  ),
  SubtitleTemplate(
    name: 'Galaxy',
    emoji: '🌌',
    styleType: SubtitleStyleType.galaxy,
    fontWeight: 800,
    animation: SubtitleAnimation.fadeIn,
    isPro: true,
  ),
];

class SubtitleSegment {
  final String id;
  String text;
  Duration startTime;
  Duration endTime;
  bool isActive;
  String? translatedText;
  // Absolute video timestamps for each word (for karaoke & re-split accuracy)
  List<Duration>? wordTimings;
  // Original word units (kept separately because Lao display text has no
  // spaces between words, so it can't be recovered by splitting `text`).
  List<String>? words;

  // ── Per-segment style overrides (null = inherit the project-wide value) ──
  int? styleIndex; // index into subtitlePresets
  String? fontFamily;
  double? fontSize;
  int? fontWeight; // 100..900
  int? textColorValue; // ARGB int; overrides preset.textColor
  SubtitleAnimation? animation;
  double? positionY; // 0..1 vertical position
  double? positionX; // 0..1 horizontal position (0.5 = centre)
  double? rotation; // degrees, clockwise (WYSIWYG free-transform)
  bool? karaoke; // per-segment karaoke highlight (null = inherit project)
  bool? karaokeScale; // per-segment "Word Pop" (null = inherit project)
  // Auto ✨ — AI-picked emphasis ("punch") word indices + a fitting emoji.
  List<int>? emphasis; // word indices to highlight + enlarge (static)
  String? emoji; // emoji appended to the line (e.g. 💰❤️🔥)

  SubtitleSegment({
    required this.id,
    required this.text,
    required this.startTime,
    required this.endTime,
    this.isActive = false,
    this.translatedText,
    this.wordTimings,
    this.words,
    this.styleIndex,
    this.fontFamily,
    this.fontSize,
    this.fontWeight,
    this.textColorValue,
    this.animation,
    this.positionY,
    this.positionX,
    this.rotation,
    this.karaoke,
    this.karaokeScale,
    this.emphasis,
    this.emoji,
  });

  /// True when this segment overrides at least one style value.
  bool get hasStyleOverride =>
      styleIndex != null ||
      fontFamily != null ||
      fontSize != null ||
      fontWeight != null ||
      textColorValue != null ||
      animation != null ||
      positionY != null ||
      positionX != null ||
      rotation != null ||
      karaoke != null ||
      karaokeScale != null;

  /// Remove every per-segment override (revert to project-wide style).
  void clearStyleOverride() {
    styleIndex = null;
    fontFamily = null;
    fontSize = null;
    fontWeight = null;
    textColorValue = null;
    animation = null;
    positionY = null;
    positionX = null;
    rotation = null;
    karaoke = null;
    karaokeScale = null;
  }

  SubtitleSegment copy() => SubtitleSegment(
        id: id,
        text: text,
        startTime: startTime,
        endTime: endTime,
        translatedText: translatedText,
        wordTimings: wordTimings != null ? List.of(wordTimings!) : null,
        words: words != null ? List.of(words!) : null,
        styleIndex: styleIndex,
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        textColorValue: textColorValue,
        animation: animation,
        positionY: positionY,
        positionX: positionX,
        rotation: rotation,
        karaoke: karaoke,
        karaokeScale: karaokeScale,
        emphasis: emphasis != null ? List.of(emphasis!) : null,
        emoji: emoji,
      );
}

enum SfxType {
  pop,
  pop2,
  pop3,
  pop4,
  pop5,
  swoosh,
  swoosh2,
  whoosh,
  whoosh2,
  whoosh3,
  whoosh4,
  whoosh5,
  whoosh6,
  whoosh7,
  whoosh8,
  whoosh9,
  whoosh10,
  ding,
  ding2,
  punch,
  punch2,
  punch3,
  punch4,
  punch5,
  slap,
  slap2,
  wow,
  wow2,
  applause,
  cameraShutter,
  cameraShutter2,
  cameraShutter3,
  cashRegister,
  cashRegister2,
  cricket,
  magic,
  recordScratch,
  recordScratch2,
  squeak,
  squeak2,
  squeak3,
  squeak4,
  squeek,
  badumtss,
  badumtss2,
  vineBoom,
  beep,
  correct,
  buzzer,
  quack,
  boing,
  laugh,
  typing,
  glitch,
  thud,
  airhorn,
}

class SfxBlock {
  final String id;
  SfxType type;
  Duration startTime;
  Duration? duration; // If null, uses default length of the SFX
  Duration? trimStart; // Offset to start playing the SFX
  double volume; // Per-block volume 0.0–1.0 (multiplied by track SFX volume)

  // Custom audio support
  bool isCustom;
  String? customPath;
  String? customName;
  bool isAiVoice;

  SfxBlock({
    required this.id,
    required this.type,
    required this.startTime,
    this.duration,
    this.trimStart,
    this.volume = 1.0,
    this.isCustom = false,
    this.customPath,
    this.customName,
    this.isAiVoice = false,
  });

  SfxBlock copy({String? newId}) => SfxBlock(
        id: newId ?? id,
        type: type,
        startTime: startTime,
        duration: duration,
        trimStart: trimStart,
        volume: volume,
        isCustom: isCustom,
        customPath: customPath,
        customName: customName,
        isAiVoice: isAiVoice,
      );
}

/// An image (B-roll / meme / sticker) overlaid on the video for a time range.
/// Position is normalised (0–1) of the display so preview and export agree.
class ImageOverlay {
  final String id;
  String path; // absolute file path (copied into app support dir)
  Duration startTime;
  Duration endTime;
  double x; // 0–1 centre X
  double y; // 0–1 centre Y
  double scale; // fraction of video width (e.g. 0.5 = half width)
  double rotation; // degrees
  bool flipH; // mirror horizontally
  bool isVideo; // true = B-roll video clip (decoded frame-by-frame); false = still image/GIF
  bool cover; // true = fill the whole frame (crop overflow), ignoring x/y/scale/rotation
  double opacity; // 0–1 static opacity (used when there are no keyframes)
  List<OverlayKeyframe> keyframes; // CapCut-style: animate x/y/scale/rotation/opacity

  ImageOverlay({
    required this.id,
    required this.path,
    required this.startTime,
    required this.endTime,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 0.5,
    this.rotation = 0.0,
    this.flipH = false,
    this.isVideo = false,
    this.cover = false,
    this.opacity = 1.0,
    List<OverlayKeyframe>? keyframes,
  }) : keyframes = keyframes ?? [];

  ImageOverlay copy({String? newId}) => ImageOverlay(
        id: newId ?? id,
        path: path,
        startTime: startTime,
        endTime: endTime,
        x: x,
        y: y,
        scale: scale,
        rotation: rotation,
        flipH: flipH,
        isVideo: isVideo,
        cover: cover,
        opacity: opacity,
        keyframes: keyframes.map((k) => k.copy()).toList(),
      );
}

/// One keyframe of an image/B-roll overlay animation. At [timeMs] the overlay is
/// at position ([x],[y]), [scale], [rotation]° and [opacity]. Values interpolate
/// linearly between consecutive keyframes (CapCut-style).
class OverlayKeyframe {
  int timeMs;
  double x;
  double y;
  double scale;
  double rotation;
  double opacity;
  int easing; // outgoing curve: 0 linear,1 in,2 out,3 inOut,4 cubicIn,5 cubicOut
  OverlayKeyframe({
    required this.timeMs,
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 0.5,
    this.rotation = 0.0,
    this.opacity = 1.0,
    this.easing = 0,
  });
  OverlayKeyframe copy() => OverlayKeyframe(
      timeMs: timeMs, x: x, y: y, scale: scale, rotation: rotation,
      opacity: opacity, easing: easing);
}

/// One keyframe of a zoom/pan animation: at [timeMs] (absolute) the video is at
/// [scale] around focal point ([focusX],[focusY]). Values interpolate linearly
/// between consecutive keyframes.
class ZoomKeyframe {
  int timeMs;
  double scale;
  double focusX;
  double focusY;
  int easing; // outgoing curve to the next kf: 0 linear,1 in,2 out,3 inOut,4 cubicIn,5 cubicOut
  ZoomKeyframe({
    required this.timeMs,
    this.scale = 1.0,
    this.focusX = 0.5,
    this.focusY = 0.5,
    this.easing = 0,
  });
  ZoomKeyframe copy() => ZoomKeyframe(
      timeMs: timeMs, scale: scale, focusX: focusX, focusY: focusY, easing: easing);
}

/// A zoom / Ken-Burns effect on the VIDEO for a time range. If [keyframes] has
/// ≥2 points, the scale + focal animate across them (full keyframe mode);
/// otherwise it falls back to a simple linear [fromScale]→[toScale] over
/// [startTime]…[endTime] around ([focusX],[focusY]). 1.0 = no zoom.
class ZoomEffect {
  final String id;
  Duration startTime;
  Duration endTime;
  double fromScale;
  double toScale;
  double focusX; // 0–1
  double focusY; // 0–1
  List<ZoomKeyframe> keyframes;

  ZoomEffect({
    required this.id,
    required this.startTime,
    required this.endTime,
    this.fromScale = 1.0,
    this.toScale = 1.3,
    this.focusX = 0.5,
    this.focusY = 0.5,
    List<ZoomKeyframe>? keyframes,
  }) : keyframes = keyframes ?? [];

  ZoomEffect copy({String? newId}) => ZoomEffect(
        id: newId ?? id,
        startTime: startTime,
        endTime: endTime,
        fromScale: fromScale,
        toScale: toScale,
        focusX: focusX,
        focusY: focusY,
        keyframes: keyframes.map((k) => k.copy()).toList(),
      );
}

/// A fade transition: a black overlay whose alpha animates over a time range.
/// [toBlack] true = alpha 0→1 (fade OUT to black); false = 1→0 (fade IN from
/// black). A cut transition = a fade-out before the cut + a fade-in after.
class FadeEffect {
  final String id;
  Duration startTime;
  Duration endTime;
  bool toBlack;

  FadeEffect({
    required this.id,
    required this.startTime,
    required this.endTime,
    this.toBlack = true,
  });

  FadeEffect copy({String? newId}) => FadeEffect(
        id: newId ?? id,
        startTime: startTime,
        endTime: endTime,
        toBlack: toBlack,
      );
}

/// A camera-shake effect on the VIDEO for a time range. [intensity] is a
/// fraction of the frame size (e.g. 0.02 = subtle, 0.06 = strong). The frame is
/// scaled up slightly so the jitter never reveals black edges.
class ShakeEffect {
  final String id;
  Duration startTime;
  Duration endTime;
  double intensity;

  ShakeEffect({
    required this.id,
    required this.startTime,
    required this.endTime,
    this.intensity = 0.03,
  });

  ShakeEffect copy({String? newId}) => ShakeEffect(
        id: newId ?? id,
        startTime: startTime,
        endTime: endTime,
        intensity: intensity,
      );
}

/// One source clip on a CapCut-style multi-clip timeline. Clips are NOT merged
/// into a single file — they are played back-to-back (each with its own native
/// orientation) and concatenated only at export. [trimStartMs]/[trimEndMs] are
/// in/out points within the source (0/null = whole clip).
class VideoClip {
  final String id;
  String path;
  int trimStartMs;
  int? trimEndMs; // null = to the end of the source
  int? durationMs; // full source duration (cached for the timeline)

  VideoClip({
    required this.id,
    required this.path,
    this.trimStartMs = 0,
    this.trimEndMs,
    this.durationMs,
  });

  /// Length this clip contributes to the timeline (after trim).
  int get effectiveMs {
    final end = trimEndMs ?? durationMs ?? 0;
    final len = end - trimStartMs;
    return len > 0 ? len : (durationMs ?? 0);
  }

  VideoClip copy({String? newId}) => VideoClip(
        id: newId ?? id,
        path: path,
        trimStartMs: trimStartMs,
        trimEndMs: trimEndMs,
        durationMs: durationMs,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'trimStartMs': trimStartMs,
        if (trimEndMs != null) 'trimEndMs': trimEndMs,
        if (durationMs != null) 'durationMs': durationMs,
      };

  static VideoClip fromJson(Map<String, dynamic> j) => VideoClip(
        id: j['id'] as String,
        path: j['path'] as String,
        trimStartMs: (j['trimStartMs'] as num?)?.toInt() ?? 0,
        trimEndMs: (j['trimEndMs'] as num?)?.toInt(),
        durationMs: (j['durationMs'] as num?)?.toInt(),
      );
}

class SubtitleProject {
  final String id;
  String name;
  String? videoPath;
  // CapCut-style multi-clip timeline (ordered). Empty = single-video project
  // (uses [videoPath] as before — fully backward compatible).
  List<VideoClip> clips;
  String? thumbnailPath;
  AspectRatioMode aspectRatio;
  SubtitlePreset selectedStyle;
  WordSplit wordSplit;
  TranslateMode translateMode;
  List<SubtitleSegment> segments;
  List<SfxBlock> sfxBlocks;
  Duration? videoDuration;
  DateTime createdAt;
  String language;
  String sourceLanguage;
  /// Optional vocabulary hint: proper nouns / brands / place names / jargon the
  /// user expects in the audio. Fed to the transcriber to fix spelling of names.
  String transcriptionHint;
  /// Run a second Gemini "proofread" pass after transcription to fix spelling
  /// and cross-chunk consistency using full context.
  bool proofread;
  double fontSize;
  int fontWeight; // 100..900 (overrides the preset weight)
  double subtitlePositionY; // 0.0 = top, 1.0 = bottom
  String fontFamily; // e.g. 'NotoSansLao', 'NotoSerifLao', 'Default'
  bool isKaraokeHighlight;
  Color karaokeHighlightColor;
  bool karaokeScale; // "Word Pop": active word grows while it's highlighted
  // Bilingual (line 2) settings
  int bilingualPresetIndex;
  double bilingualFontSize;
  double bilingualGap; // vertical gap between main line and translated line
  bool showBilingual;
  SubtitleAnimation subtitleAnimation;
  SubtitleAnimation exitAnimation; // animation when the subtitle leaves
  AnimationSpeed animationSpeed; // in/out + typewriter speed
  bool isAutoCut;
  int autoCutGapMs; // silence longer than this (ms) gets cut — sensitivity
  bool isAutoSyncSfx;
  // Audio mixer (3 tracks): original (video) / AI voice / SFX.
  // Each track has an independent volume (0.0–1.0) and mute flag.
  double originalVolume;
  double aiVoiceVolume;
  double sfxVolume;
  bool originalMuted;
  bool aiVoiceMuted;
  bool sfxMuted;
  // Path to the stitched AI-voice WAV (timeline-aligned). null = no AI track yet.
  String? aiVoicePath;
  int? aiVoiceDurationMs;
  int aiVoiceOffsetMs;
  int aiVoiceTrimStartMs;
  int? aiVoiceTrimEndMs;
  double aiVoiceSpeed;
  // Manually-cut video ranges (ms [start,end] pairs) removed from the timeline.
  // Frames inside these ranges are dropped on export (reuses keptRegions).
  List<List<int>> removedRanges;
  // Split markers (ms on the ORIGINAL timeline) — divide the filmstrip into
  // selectable clips without removing anything.
  List<int> splitPointsMs;
  // Image/sticker overlays placed on the video.
  List<ImageOverlay> imageOverlays;
  // Zoom / Ken-Burns effects on the video (per time range).
  List<ZoomEffect> zoomEffects;
  // Fade transitions (black overlay, per time range).
  List<FadeEffect> fadeEffects;
  // Camera-shake effects (per time range).
  List<ShakeEffect> shakeEffects;
  // Background music: a single audio track under the whole video.
  // [bgMusicDuck] lowers the music automatically during speech segments.
  String? bgMusicPath;
  int? bgMusicDurationMs;
  double bgMusicVolume;
  bool bgMusicMuted;
  bool bgMusicDuck;
  // Blurred background: fit a non-9:16 video into a 9:16 frame with blurred fill.
  bool bgBlur;

  SubtitleProject({
    required this.id,
    required this.name,
    this.videoPath,
    this.thumbnailPath,
    this.aspectRatio = AspectRatioMode.ratio9x16,
    required this.selectedStyle,
    this.wordSplit = WordSplit.none,
    this.translateMode = TranslateMode.none,
    List<SubtitleSegment>? segments,
    List<SfxBlock>? sfxBlocks,
    this.videoDuration,
    DateTime? createdAt,
    this.language = 'lo',
    this.sourceLanguage = 'th',
    this.transcriptionHint = '',
    this.proofread = true,
    this.fontSize = 18.0,
    this.fontWeight = 600,
    this.subtitlePositionY = 0.85,
    this.fontFamily = 'NotoSansLao',
    this.isKaraokeHighlight = false,
    this.karaokeHighlightColor = const Color(0xFF9C59F5),
    this.karaokeScale = false,
    this.bilingualPresetIndex = 1,
    this.bilingualFontSize = 13.0,
    this.bilingualGap = 4.0,
    this.showBilingual = false,
    this.subtitleAnimation = SubtitleAnimation.none,
    this.exitAnimation = SubtitleAnimation.none,
    this.animationSpeed = AnimationSpeed.normal,
    this.isAutoCut = false,
    this.autoCutGapMs = 300,
    this.isAutoSyncSfx = false,
    this.originalVolume = 1.0,
    this.aiVoiceVolume = 1.0,
    this.sfxVolume = 1.0,
    this.originalMuted = false,
    this.aiVoiceMuted = false,
    this.sfxMuted = false,
    this.aiVoicePath,
    this.aiVoiceDurationMs,
    this.aiVoiceOffsetMs = 0,
    this.aiVoiceTrimStartMs = 0,
    this.aiVoiceTrimEndMs,
    this.aiVoiceSpeed = 1.0,
    List<List<int>>? removedRanges,
    List<int>? splitPointsMs,
    List<ImageOverlay>? imageOverlays,
    List<ZoomEffect>? zoomEffects,
    List<FadeEffect>? fadeEffects,
    List<ShakeEffect>? shakeEffects,
    List<VideoClip>? clips,
    this.bgMusicPath,
    this.bgMusicDurationMs,
    this.bgMusicVolume = 0.45,
    this.bgMusicMuted = false,
    this.bgMusicDuck = true,
    this.bgBlur = false,
  })  : segments = segments ?? [],
        sfxBlocks = sfxBlocks ?? [],
        removedRanges = removedRanges ?? [],
        splitPointsMs = splitPointsMs ?? [],
        imageOverlays = imageOverlays ?? [],
        zoomEffects = zoomEffects ?? [],
        fadeEffects = fadeEffects ?? [],
        shakeEffects = shakeEffects ?? [],
        clips = clips ?? [],
        createdAt = createdAt ?? DateTime.now();
}

extension SfxTypeExtension on SfxType {
  Duration get defaultDuration {
    double dur;
    switch (this) {
      case SfxType.airhorn: dur = 1.99; break;
      case SfxType.applause: dur = 4.44; break;
      case SfxType.badumtss: dur = 1.94; break;
      case SfxType.badumtss2: dur = 1.42; break;
      case SfxType.beep: dur = 2.12; break;
      case SfxType.boing: dur = 9.65; break;
      case SfxType.buzzer: dur = 1.78; break;
      case SfxType.cameraShutter: dur = 7.87; break;
      case SfxType.cameraShutter2: dur = 0.34; break;
      case SfxType.cameraShutter3: dur = 0.67; break;
      case SfxType.cashRegister: dur = 1.10; break;
      case SfxType.cashRegister2: dur = 3.19; break;
      case SfxType.correct: dur = 1.32; break;
      case SfxType.cricket: dur = 1.30; break;
      case SfxType.ding: dur = 2.19; break;
      case SfxType.ding2: dur = 2.74; break;
      case SfxType.glitch: dur = 1.75; break;
      case SfxType.laugh: dur = 2.48; break;
      case SfxType.magic: dur = 4.80; break;
      case SfxType.pop: dur = 1.02; break;
      case SfxType.pop2: dur = 1.63; break;
      case SfxType.pop3: dur = 0.72; break;
      case SfxType.pop4: dur = 3.15; break;
      case SfxType.pop5: dur = 1.97; break;
      case SfxType.punch: dur = 1.56; break;
      case SfxType.punch2: dur = 1.57; break;
      case SfxType.punch3: dur = 0.72; break;
      case SfxType.punch4: dur = 1.42; break;
      case SfxType.punch5: dur = 1.06; break;
      case SfxType.quack: dur = 3.12; break;
      case SfxType.recordScratch: dur = 20.43; break;
      case SfxType.recordScratch2: dur = 1.66; break;
      case SfxType.slap: dur = 0.60; break;
      case SfxType.slap2: dur = 9.69; break;
      case SfxType.squeak: dur = 3.43; break;
      case SfxType.squeak2: dur = 3.91; break;
      case SfxType.squeak3: dur = 0.86; break;
      case SfxType.squeak4: dur = 5.09; break;
      case SfxType.squeek: dur = 3.08; break;
      case SfxType.swoosh: dur = 0.36; break;
      case SfxType.swoosh2: dur = 1.06; break;
      case SfxType.thud: dur = 3.11; break;
      case SfxType.typing: dur = 68.35; break;
      case SfxType.vineBoom: dur = 1.31; break;
      case SfxType.whoosh: dur = 1.92; break;
      case SfxType.whoosh10: dur = 8.04; break;
      case SfxType.whoosh2: dur = 7.32; break;
      case SfxType.whoosh3: dur = 2.52; break;
      case SfxType.whoosh4: dur = 4.03; break;
      case SfxType.whoosh5: dur = 0.58; break;
      case SfxType.whoosh6: dur = 2.12; break;
      case SfxType.whoosh7: dur = 3.08; break;
      case SfxType.whoosh8: dur = 3.03; break;
      case SfxType.whoosh9: dur = 6.03; break;
      case SfxType.wow: dur = 1.90; break;
      case SfxType.wow2: dur = 1.66; break;
    }
    return Duration(milliseconds: (dur * 1000).round());
  }
}
