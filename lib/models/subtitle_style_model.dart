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

class SubtitleProject {
  final String id;
  String name;
  String? videoPath;
  String? thumbnailPath;
  AspectRatioMode aspectRatio;
  SubtitlePreset selectedStyle;
  WordSplit wordSplit;
  TranslateMode translateMode;
  List<SubtitleSegment> segments;
  Duration? videoDuration;
  DateTime createdAt;
  String language;
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
    this.videoDuration,
    DateTime? createdAt,
    this.language = 'lo',
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
  })  : segments = segments ?? [],
        createdAt = createdAt ?? DateTime.now();
}
