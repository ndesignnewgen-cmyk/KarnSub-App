import 'dart:math' as math;

/// KarnSub project model v2 — a real multi-track timeline (PRO_EDITOR_PLAN
/// phase 1). Pure Dart (no Flutter), JSON round-trippable.
///
/// All times are TIMELINE milliseconds (what the viewer sees after cuts),
/// except media in/out points ([MediaElement.trimInMs]) which are SOURCE
/// milliseconds. Keyframe times are relative to their element's start.
///
/// v1 projects (SubtitleProject) are converted by `migrateV1` in
/// migrate_v1.dart.

enum TrackKind {
  mainVideo, // the primary clip sequence (always packed, no gaps)
  video, // picture-in-picture / B-roll video
  sticker, // images, GIFs, stickers
  text, // free text layers
  subtitle,
  shape,
  effect, // adjustment-layer effects (zoom, fade, shake…) over a time range
  audio,
  sfx,
  music,
  voice, // AI voice
}

bool isAudioKind(TrackKind k) =>
    k == TrackKind.audio ||
    k == TrackKind.sfx ||
    k == TrackKind.music ||
    k == TrackKind.voice;

class ElementTransform {
  final double x; // 0–1 centre
  final double y;
  final double scale; // fraction of frame width (overlays) / zoom (video)
  final double rotation; // degrees
  final double opacity; // 0–1
  final bool flipH;

  const ElementTransform({
    this.x = 0.5,
    this.y = 0.5,
    this.scale = 1.0,
    this.rotation = 0,
    this.opacity = 1,
    this.flipH = false,
  });

  ElementTransform copyWith({
    double? x,
    double? y,
    double? scale,
    double? rotation,
    double? opacity,
    bool? flipH,
  }) =>
      ElementTransform(
        x: x ?? this.x,
        y: y ?? this.y,
        scale: scale ?? this.scale,
        rotation: rotation ?? this.rotation,
        opacity: opacity ?? this.opacity,
        flipH: flipH ?? this.flipH,
      );

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'scale': scale,
        'rotation': rotation,
        'opacity': opacity,
        if (flipH) 'flipH': true,
      };

  static ElementTransform fromJson(Map<String, dynamic>? j) => j == null
      ? const ElementTransform()
      : ElementTransform(
          x: _d(j['x'], 0.5),
          y: _d(j['y'], 0.5),
          scale: _d(j['scale'], 1),
          rotation: _d(j['rotation'], 0),
          opacity: _d(j['opacity'], 1),
          flipH: j['flipH'] == true,
        );

  @override
  bool operator ==(Object other) =>
      other is ElementTransform &&
      other.x == x &&
      other.y == y &&
      other.scale == scale &&
      other.rotation == rotation &&
      other.opacity == opacity &&
      other.flipH == flipH;

  @override
  int get hashCode => Object.hash(x, y, scale, rotation, opacity, flipH);
}

/// Easing of the segment that LEAVES a keyframe.
/// 0 linear, 1 easeIn, 2 easeOut, 3 easeInOut, 4 cubicIn, 5 cubicOut,
/// 6 bezier (uses [Keyframe.bezier]).
class Keyframe {
  final int timeMs; // relative to the element start
  final ElementTransform t;
  final int easing;
  final List<double>? bezier; // [x1, y1, x2, y2] when easing == 6

  const Keyframe(this.timeMs, this.t, {this.easing = 0, this.bezier});

  Map<String, dynamic> toJson() => {
        'timeMs': timeMs,
        't': t.toJson(),
        if (easing != 0) 'easing': easing,
        if (bezier != null) 'bezier': bezier,
      };

  static Keyframe fromJson(Map<String, dynamic> j) => Keyframe(
        (j['timeMs'] as num).toInt(),
        ElementTransform.fromJson(j['t'] as Map<String, dynamic>?),
        easing: (j['easing'] as num?)?.toInt() ?? 0,
        bezier: (j['bezier'] as List?)?.map((e) => (e as num).toDouble()).toList(),
      );
}

/// Shared easing curves (same numbering as v1 so old projects look the same).
double applyEasing(int easing, double t, [List<double>? bezier]) {
  t = t.clamp(0.0, 1.0);
  switch (easing) {
    case 1:
      return t * t;
    case 2:
      return 1 - (1 - t) * (1 - t);
    case 3:
      return t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
    case 4:
      return t * t * t;
    case 5:
      return 1 - math.pow(1 - t, 3).toDouble();
    case 6:
      if (bezier != null && bezier.length == 4) {
        return cubicBezier(bezier[0], bezier[1], bezier[2], bezier[3], t);
      }
      return t;
    default:
      return t;
  }
}

/// CSS-style cubic-bezier(x1, y1, x2, y2) evaluated at progress [x].
double cubicBezier(double x1, double y1, double x2, double y2, double x) {
  double bx(double s) =>
      3 * (1 - s) * (1 - s) * s * x1 + 3 * (1 - s) * s * s * x2 + s * s * s;
  double by(double s) =>
      3 * (1 - s) * (1 - s) * s * y1 + 3 * (1 - s) * s * s * y2 + s * s * s;
  // Solve bx(s) = x by bisection (monotone for x1,x2 in [0,1]).
  double lo = 0, hi = 1, s = x;
  for (int i = 0; i < 30; i++) {
    s = (lo + hi) / 2;
    if (bx(s) < x) {
      lo = s;
    } else {
      hi = s;
    }
  }
  return by(s);
}

/// ElementTransform at [relMs] for keyframed elements (base when < 2 keyframes).
ElementTransform transformAt(ElementTransform base, List<Keyframe> kfs, int relMs) {
  if (kfs.isEmpty) return base;
  if (kfs.length == 1 || relMs <= kfs.first.timeMs) return kfs.first.t;
  if (relMs >= kfs.last.timeMs) return kfs.last.t;
  for (int i = 0; i + 1 < kfs.length; i++) {
    final a = kfs[i], b = kfs[i + 1];
    if (relMs >= a.timeMs && relMs <= b.timeMs) {
      final span = b.timeMs - a.timeMs;
      final p = span <= 0
          ? 1.0
          : applyEasing(a.easing, (relMs - a.timeMs) / span, a.bezier);
      double lerp(double u, double v) => u + (v - u) * p;
      return ElementTransform(
        x: lerp(a.t.x, b.t.x),
        y: lerp(a.t.y, b.t.y),
        scale: lerp(a.t.scale, b.t.scale),
        rotation: lerp(a.t.rotation, b.t.rotation),
        opacity: lerp(a.t.opacity, b.t.opacity),
        flipH: a.t.flipH,
      );
    }
  }
  return kfs.last.t;
}

enum LayerBlend { normal, screen, multiply, overlay, lighten, darken, add }

class MaskSpec {
  final String shape; // none, rect, ellipse, heart, star, diamond, split, band, text, custom
  final double feather; // 0–1
  final double size; // 0–1
  final double rotation; // degrees
  final bool inverted;
  const MaskSpec({
    this.shape = 'none',
    this.feather = 0,
    this.size = 0.6,
    this.rotation = 0,
    this.inverted = false,
  });
  Map<String, dynamic> toJson() => {
        'shape': shape,
        'feather': feather,
        'size': size,
        'rotation': rotation,
        if (inverted) 'inverted': true,
      };
  static MaskSpec? fromJson(Map<String, dynamic>? j) => j == null
      ? null
      : MaskSpec(
          shape: j['shape'] as String? ?? 'none',
          feather: _d(j['feather'], 0),
          size: _d(j['size'], 0.6),
          rotation: _d(j['rotation'], 0),
          inverted: j['inverted'] == true,
        );
}

/// Constant speed, or a speed curve (points of (progress 0–1, speed)).
class SpeedSpec {
  final double constant;
  final List<List<double>>? curve; // [[p, speed], ...] sorted by p
  final bool keepPitch;
  const SpeedSpec({this.constant = 1, this.curve, this.keepPitch = true});
  bool get isDefault => constant == 1 && curve == null;
  Map<String, dynamic> toJson() => {
        'constant': constant,
        if (curve != null) 'curve': curve,
        if (!keepPitch) 'keepPitch': false,
      };
  static SpeedSpec fromJson(Map<String, dynamic>? j) => j == null
      ? const SpeedSpec()
      : SpeedSpec(
          constant: _d(j['constant'], 1),
          curve: (j['curve'] as List?)
              ?.map((p) => (p as List).map((e) => (e as num).toDouble()).toList())
              .toList(),
          keepPitch: j['keepPitch'] != false,
        );
}

// ── Elements ───────────────────────────────────────────────────────────────

sealed class TimelineElement {
  final String id;
  final int startMs;
  final int durationMs;
  int get endMs => startMs + durationMs;

  const TimelineElement({required this.id, required this.startMs, required this.durationMs});

  String get type;

  /// Same element moved/resized on the timeline.
  TimelineElement withTiming({int? startMs, int? durationMs});

  /// Same element with a new id (duplicate / split).
  TimelineElement withId(String id);

  Map<String, dynamic> toJson();

  Map<String, dynamic> baseJson() => {
        'type': type,
        'id': id,
        'startMs': startMs,
        'durationMs': durationMs,
      };

  static TimelineElement fromJson(Map<String, dynamic> j) {
    switch (j['type']) {
      case 'video':
        return VideoElement.fromJson(j);
      case 'image':
        return ImageElement.fromJson(j);
      case 'subtitle':
        return SubtitleElement.fromJson(j);
      case 'text':
        return TextElement.fromJson(j);
      case 'shape':
        return ShapeElement.fromJson(j);
      case 'audio':
        return AudioElement.fromJson(j);
      case 'effect':
        return EffectElement.fromJson(j);
      default:
        throw FormatException('unknown element type ${j['type']}');
    }
  }
}

/// Elements whose content comes from a media file with in/out points.
abstract interface class MediaElement {
  String get src;
  int get trimInMs; // source ms where this element starts playing
  double get speed;
}

/// Visual elements share transform / keyframes / blend / mask / opacity.
abstract interface class VisualElement {
  ElementTransform get transform;
  List<Keyframe> get keyframes;
  LayerBlend get blend;
  MaskSpec? get mask;
}

class VideoElement extends TimelineElement implements MediaElement, VisualElement {
  @override
  final String src;
  @override
  final int trimInMs;
  final SpeedSpec speedSpec;
  final double volume;
  final bool muted;
  final bool reversed;
  @override
  final ElementTransform transform;
  @override
  final List<Keyframe> keyframes;
  @override
  final LayerBlend blend;
  @override
  final MaskSpec? mask;
  final bool cover; // fill the frame (crop), ignore transform position/scale
  final int? sourceMs; // full length of the source file (export needs it)

  const VideoElement({
    required super.id,
    required super.startMs,
    required super.durationMs,
    required this.src,
    this.trimInMs = 0,
    this.speedSpec = const SpeedSpec(),
    this.volume = 1,
    this.muted = false,
    this.reversed = false,
    this.transform = const ElementTransform(),
    this.keyframes = const [],
    this.blend = LayerBlend.normal,
    this.mask,
    this.cover = false,
    this.sourceMs,
  });

  @override
  double get speed => speedSpec.constant;
  @override
  String get type => 'video';

  /// Source ms where this element stops (constant speed).
  int get trimOutMs => trimInMs + (durationMs * speed).round();

  VideoElement copyWith({
    String? id,
    int? startMs,
    int? durationMs,
    String? src,
    int? trimInMs,
    SpeedSpec? speedSpec,
    double? volume,
    bool? muted,
    bool? reversed,
    ElementTransform? transform,
    List<Keyframe>? keyframes,
    LayerBlend? blend,
    MaskSpec? mask,
    bool? cover,
    int? sourceMs,
  }) =>
      VideoElement(
        id: id ?? this.id,
        startMs: startMs ?? this.startMs,
        durationMs: durationMs ?? this.durationMs,
        src: src ?? this.src,
        trimInMs: trimInMs ?? this.trimInMs,
        speedSpec: speedSpec ?? this.speedSpec,
        volume: volume ?? this.volume,
        muted: muted ?? this.muted,
        reversed: reversed ?? this.reversed,
        transform: transform ?? this.transform,
        keyframes: keyframes ?? this.keyframes,
        blend: blend ?? this.blend,
        mask: mask ?? this.mask,
        cover: cover ?? this.cover,
        sourceMs: sourceMs ?? this.sourceMs,
      );

  @override
  VideoElement withTiming({int? startMs, int? durationMs}) =>
      copyWith(startMs: startMs, durationMs: durationMs);
  @override
  VideoElement withId(String id) => copyWith(id: id);

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'src': src,
        'trimInMs': trimInMs,
        if (!speedSpec.isDefault) 'speed': speedSpec.toJson(),
        if (volume != 1) 'volume': volume,
        if (muted) 'muted': true,
        if (reversed) 'reversed': true,
        if (transform != const ElementTransform()) 'transform': transform.toJson(),
        if (keyframes.isNotEmpty) 'keyframes': keyframes.map((k) => k.toJson()).toList(),
        if (blend != LayerBlend.normal) 'blend': blend.name,
        if (mask != null) 'mask': mask!.toJson(),
        if (cover) 'cover': true,
        if (sourceMs != null) 'sourceMs': sourceMs,
      };

  static VideoElement fromJson(Map<String, dynamic> j) => VideoElement(
        id: j['id'] as String,
        startMs: (j['startMs'] as num).toInt(),
        durationMs: (j['durationMs'] as num).toInt(),
        src: j['src'] as String,
        trimInMs: (j['trimInMs'] as num?)?.toInt() ?? 0,
        speedSpec: SpeedSpec.fromJson(j['speed'] as Map<String, dynamic>?),
        volume: _d(j['volume'], 1),
        muted: j['muted'] == true,
        reversed: j['reversed'] == true,
        transform: ElementTransform.fromJson(j['transform'] as Map<String, dynamic>?),
        keyframes: _kfs(j['keyframes']),
        blend: _blend(j['blend']),
        mask: MaskSpec.fromJson(j['mask'] as Map<String, dynamic>?),
        cover: j['cover'] == true,
        sourceMs: (j['sourceMs'] as num?)?.toInt(),
      );
}

class ImageElement extends TimelineElement implements VisualElement {
  final String src;
  final bool animated; // GIF
  @override
  final ElementTransform transform;
  @override
  final List<Keyframe> keyframes;
  @override
  final LayerBlend blend;
  @override
  final MaskSpec? mask;
  final bool cover;

  const ImageElement({
    required super.id,
    required super.startMs,
    required super.durationMs,
    required this.src,
    this.animated = false,
    this.transform = const ElementTransform(scale: 0.5),
    this.keyframes = const [],
    this.blend = LayerBlend.normal,
    this.mask,
    this.cover = false,
  });

  @override
  String get type => 'image';

  ImageElement copyWith({
    String? id,
    int? startMs,
    int? durationMs,
    ElementTransform? transform,
    List<Keyframe>? keyframes,
    LayerBlend? blend,
    MaskSpec? mask,
    bool clearMask = false,
    bool? cover,
  }) =>
      ImageElement(
        id: id ?? this.id,
        startMs: startMs ?? this.startMs,
        durationMs: durationMs ?? this.durationMs,
        src: src,
        animated: animated,
        transform: transform ?? this.transform,
        keyframes: keyframes ?? this.keyframes,
        blend: blend ?? this.blend,
        mask: clearMask ? null : (mask ?? this.mask),
        cover: cover ?? this.cover,
      );

  @override
  ImageElement withTiming({int? startMs, int? durationMs}) =>
      copyWith(startMs: startMs, durationMs: durationMs);
  @override
  ImageElement withId(String id) => copyWith(id: id);

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'src': src,
        if (animated) 'animated': true,
        'transform': transform.toJson(),
        if (keyframes.isNotEmpty) 'keyframes': keyframes.map((k) => k.toJson()).toList(),
        if (blend != LayerBlend.normal) 'blend': blend.name,
        if (mask != null) 'mask': mask!.toJson(),
        if (cover) 'cover': true,
      };

  static ImageElement fromJson(Map<String, dynamic> j) => ImageElement(
        id: j['id'] as String,
        startMs: (j['startMs'] as num).toInt(),
        durationMs: (j['durationMs'] as num).toInt(),
        src: j['src'] as String,
        animated: j['animated'] == true,
        transform: ElementTransform.fromJson(j['transform'] as Map<String, dynamic>?),
        keyframes: _kfs(j['keyframes']),
        blend: _blend(j['blend']),
        mask: MaskSpec.fromJson(j['mask'] as Map<String, dynamic>?),
        cover: j['cover'] == true,
      );
}

/// A subtitle line. [data] is the full v1 SubtitleSegment JSON (text, words,
/// word timings, per-line style, karaoke, emphasis…) so nothing is lost; its
/// times inside [data] are ignored — the element's start/duration win, and
/// [wordStartsMs] are relative to the element start.
class SubtitleElement extends TimelineElement {
  final String text;
  final List<int>? wordStartsMs;
  final Map<String, dynamic> data;

  const SubtitleElement({
    required super.id,
    required super.startMs,
    required super.durationMs,
    required this.text,
    this.wordStartsMs,
    this.data = const {},
  });

  @override
  String get type => 'subtitle';

  SubtitleElement copyWith({
    String? id,
    int? startMs,
    int? durationMs,
    String? text,
    List<int>? wordStartsMs,
    Map<String, dynamic>? data,
  }) =>
      SubtitleElement(
        id: id ?? this.id,
        startMs: startMs ?? this.startMs,
        durationMs: durationMs ?? this.durationMs,
        text: text ?? this.text,
        wordStartsMs: wordStartsMs ?? this.wordStartsMs,
        data: data ?? this.data,
      );

  @override
  SubtitleElement withTiming({int? startMs, int? durationMs}) =>
      copyWith(startMs: startMs, durationMs: durationMs);
  @override
  SubtitleElement withId(String id) => copyWith(id: id);

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'text': text,
        if (wordStartsMs != null) 'wordStartsMs': wordStartsMs,
        if (data.isNotEmpty) 'data': data,
      };

  static SubtitleElement fromJson(Map<String, dynamic> j) => SubtitleElement(
        id: j['id'] as String,
        startMs: (j['startMs'] as num).toInt(),
        durationMs: (j['durationMs'] as num).toInt(),
        text: j['text'] as String? ?? '',
        wordStartsMs: (j['wordStartsMs'] as List?)?.map((e) => (e as num).toInt()).toList(),
        data: (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

class TextElement extends TimelineElement implements VisualElement {
  final String text;
  final Map<String, dynamic> style; // font, size, colour, bg, shadow, stroke, animation…
  @override
  final ElementTransform transform;
  @override
  final List<Keyframe> keyframes;
  @override
  final LayerBlend blend;
  @override
  final MaskSpec? mask;

  const TextElement({
    required super.id,
    required super.startMs,
    required super.durationMs,
    required this.text,
    this.style = const {},
    this.transform = const ElementTransform(),
    this.keyframes = const [],
    this.blend = LayerBlend.normal,
    this.mask,
  });

  @override
  String get type => 'text';

  TextElement copyWith({
    String? text,
    Map<String, dynamic>? style,
    ElementTransform? transform,
    List<Keyframe>? keyframes,
  }) =>
      TextElement(
        id: id,
        startMs: startMs,
        durationMs: durationMs,
        text: text ?? this.text,
        style: style ?? this.style,
        transform: transform ?? this.transform,
        keyframes: keyframes ?? this.keyframes,
        blend: blend,
        mask: mask,
      );

  @override
  TextElement withTiming({int? startMs, int? durationMs}) => TextElement(
        id: id,
        startMs: startMs ?? this.startMs,
        durationMs: durationMs ?? this.durationMs,
        text: text,
        style: style,
        transform: transform,
        keyframes: keyframes,
        blend: blend,
        mask: mask,
      );
  @override
  TextElement withId(String id) => TextElement(
        id: id,
        startMs: startMs,
        durationMs: durationMs,
        text: text,
        style: style,
        transform: transform,
        keyframes: keyframes,
        blend: blend,
        mask: mask,
      );

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'text': text,
        if (style.isNotEmpty) 'style': style,
        'transform': transform.toJson(),
        if (keyframes.isNotEmpty) 'keyframes': keyframes.map((k) => k.toJson()).toList(),
        if (blend != LayerBlend.normal) 'blend': blend.name,
        if (mask != null) 'mask': mask!.toJson(),
      };

  static TextElement fromJson(Map<String, dynamic> j) => TextElement(
        id: j['id'] as String,
        startMs: (j['startMs'] as num).toInt(),
        durationMs: (j['durationMs'] as num).toInt(),
        text: j['text'] as String? ?? '',
        style: (j['style'] as Map?)?.cast<String, dynamic>() ?? const {},
        transform: ElementTransform.fromJson(j['transform'] as Map<String, dynamic>?),
        keyframes: _kfs(j['keyframes']),
        blend: _blend(j['blend']),
        mask: MaskSpec.fromJson(j['mask'] as Map<String, dynamic>?),
      );
}

class ShapeElement extends TimelineElement implements VisualElement {
  final String shape; // rect, ellipse, polygon, star, arrow
  final int fillColor; // ARGB
  final int strokeColor;
  final double strokeWidth;
  @override
  final ElementTransform transform;
  @override
  final List<Keyframe> keyframes;
  @override
  final LayerBlend blend;
  @override
  final MaskSpec? mask;

  const ShapeElement({
    required super.id,
    required super.startMs,
    required super.durationMs,
    required this.shape,
    this.fillColor = 0xFFFFFFFF,
    this.strokeColor = 0x00000000,
    this.strokeWidth = 0,
    this.transform = const ElementTransform(scale: 0.3),
    this.keyframes = const [],
    this.blend = LayerBlend.normal,
    this.mask,
  });

  @override
  String get type => 'shape';

  ShapeElement _copy({String? id, int? startMs, int? durationMs}) => copyWith(
        id: id,
        startMs: startMs,
        durationMs: durationMs,
      );

  ShapeElement copyWith({
    String? id,
    int? startMs,
    int? durationMs,
    String? shape,
    int? fillColor,
    int? strokeColor,
    double? strokeWidth,
    ElementTransform? transform,
    List<Keyframe>? keyframes,
  }) =>
      ShapeElement(
        id: id ?? this.id,
        startMs: startMs ?? this.startMs,
        durationMs: durationMs ?? this.durationMs,
        shape: shape ?? this.shape,
        fillColor: fillColor ?? this.fillColor,
        strokeColor: strokeColor ?? this.strokeColor,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        transform: transform ?? this.transform,
        keyframes: keyframes ?? this.keyframes,
        blend: blend,
        mask: mask,
      );

  @override
  ShapeElement withTiming({int? startMs, int? durationMs}) =>
      _copy(startMs: startMs, durationMs: durationMs);
  @override
  ShapeElement withId(String id) => _copy(id: id);

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'shape': shape,
        'fillColor': fillColor,
        if (strokeWidth > 0) 'strokeColor': strokeColor,
        if (strokeWidth > 0) 'strokeWidth': strokeWidth,
        'transform': transform.toJson(),
        if (keyframes.isNotEmpty) 'keyframes': keyframes.map((k) => k.toJson()).toList(),
        if (blend != LayerBlend.normal) 'blend': blend.name,
        if (mask != null) 'mask': mask!.toJson(),
      };

  static ShapeElement fromJson(Map<String, dynamic> j) => ShapeElement(
        id: j['id'] as String,
        startMs: (j['startMs'] as num).toInt(),
        durationMs: (j['durationMs'] as num).toInt(),
        shape: j['shape'] as String? ?? 'rect',
        fillColor: (j['fillColor'] as num?)?.toInt() ?? 0xFFFFFFFF,
        strokeColor: (j['strokeColor'] as num?)?.toInt() ?? 0,
        strokeWidth: _d(j['strokeWidth'], 0),
        transform: ElementTransform.fromJson(j['transform'] as Map<String, dynamic>?),
        keyframes: _kfs(j['keyframes']),
        blend: _blend(j['blend']),
        mask: MaskSpec.fromJson(j['mask'] as Map<String, dynamic>?),
      );
}

/// Any sound: SFX (built-in `sfx:<name>` or a file), music, AI voice.
class AudioElement extends TimelineElement implements MediaElement {
  @override
  final String src;
  @override
  final int trimInMs;
  @override
  final double speed;
  final double volume;
  final String? label;
  final bool loop; // music under the whole video

  const AudioElement({
    required super.id,
    required super.startMs,
    required super.durationMs,
    required this.src,
    this.trimInMs = 0,
    this.speed = 1,
    this.volume = 1,
    this.label,
    this.loop = false,
  });

  @override
  String get type => 'audio';

  AudioElement copyWith({
    String? id,
    int? startMs,
    int? durationMs,
    int? trimInMs,
    double? volume,
  }) =>
      AudioElement(
        id: id ?? this.id,
        startMs: startMs ?? this.startMs,
        durationMs: durationMs ?? this.durationMs,
        src: src,
        trimInMs: trimInMs ?? this.trimInMs,
        speed: speed,
        volume: volume ?? this.volume,
        label: label,
        loop: loop,
      );

  @override
  AudioElement withTiming({int? startMs, int? durationMs}) =>
      copyWith(startMs: startMs, durationMs: durationMs);
  @override
  AudioElement withId(String id) => copyWith(id: id);

  @override
  Map<String, dynamic> toJson() => {
        ...baseJson(),
        'src': src,
        if (trimInMs != 0) 'trimInMs': trimInMs,
        if (speed != 1) 'speed': speed,
        if (volume != 1) 'volume': volume,
        if (label != null) 'label': label,
        if (loop) 'loop': true,
      };

  static AudioElement fromJson(Map<String, dynamic> j) => AudioElement(
        id: j['id'] as String,
        startMs: (j['startMs'] as num).toInt(),
        durationMs: (j['durationMs'] as num).toInt(),
        src: j['src'] as String,
        trimInMs: (j['trimInMs'] as num?)?.toInt() ?? 0,
        speed: _d(j['speed'], 1),
        volume: _d(j['volume'], 1),
        label: j['label'] as String?,
        loop: j['loop'] == true,
      );
}

/// A time-ranged effect on everything below it (zoom, fade, shake, filter…).
/// [params] are effect-specific; keyframe times are relative to the start.
class EffectElement extends TimelineElement {
  final String effect; // zoom, fade, shake, filter, adjust…
  final Map<String, dynamic> params;

  const EffectElement({
    required super.id,
    required super.startMs,
    required super.durationMs,
    required this.effect,
    this.params = const {},
  });

  @override
  String get type => 'effect';

  @override
  EffectElement withTiming({int? startMs, int? durationMs}) => EffectElement(
        id: id,
        startMs: startMs ?? this.startMs,
        durationMs: durationMs ?? this.durationMs,
        effect: effect,
        params: params,
      );
  @override
  EffectElement withId(String id) => EffectElement(
      id: id, startMs: startMs, durationMs: durationMs, effect: effect, params: params);

  @override
  Map<String, dynamic> toJson() => {...baseJson(), 'effect': effect, 'params': params};

  static EffectElement fromJson(Map<String, dynamic> j) => EffectElement(
        id: j['id'] as String,
        startMs: (j['startMs'] as num).toInt(),
        durationMs: (j['durationMs'] as num).toInt(),
        effect: j['effect'] as String,
        params: (j['params'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

// ── Tracks, transitions, timeline ──────────────────────────────────────────

class Track {
  final String id;
  final TrackKind kind;
  final bool muted;
  final bool locked;
  final bool hidden;
  final double volume; // audio tracks + main video's original audio
  final bool duck; // music: lower under speech
  final List<TimelineElement> elements; // sorted by start, never overlapping

  const Track({
    required this.id,
    required this.kind,
    this.muted = false,
    this.locked = false,
    this.hidden = false,
    this.volume = 1,
    this.duck = false,
    this.elements = const [],
  });

  int get endMs => elements.isEmpty ? 0 : elements.map((e) => e.endMs).reduce(math.max);

  Track copyWith({
    bool? muted,
    bool? locked,
    bool? hidden,
    double? volume,
    bool? duck,
    List<TimelineElement>? elements,
  }) =>
      Track(
        id: id,
        kind: kind,
        muted: muted ?? this.muted,
        locked: locked ?? this.locked,
        hidden: hidden ?? this.hidden,
        volume: volume ?? this.volume,
        duck: duck ?? this.duck,
        elements: elements ?? this.elements,
      );

  /// True when [e] fits on this track without overlapping (ignoring [ignoreId]).
  bool fits(int startMs, int endMs, {String? ignoreId}) => elements.every(
      (x) => x.id == ignoreId || x.endMs <= startMs || x.startMs >= endMs);

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        if (muted) 'muted': true,
        if (locked) 'locked': true,
        if (hidden) 'hidden': true,
        if (volume != 1) 'volume': volume,
        if (duck) 'duck': true,
        'elements': elements.map((e) => e.toJson()).toList(),
      };

  static Track fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        kind: TrackKind.values.byName(j['kind'] as String),
        muted: j['muted'] == true,
        locked: j['locked'] == true,
        hidden: j['hidden'] == true,
        volume: _d(j['volume'], 1),
        duck: j['duck'] == true,
        elements: (j['elements'] as List)
            .map((e) => TimelineElement.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Transition {
  final String fromId; // element ending
  final String toId; // element starting right after it
  final String kind; // dissolve, slideLeft, zoomIn, spin, glitch, flash…
  final int durationMs;
  const Transition({
    required this.fromId,
    required this.toId,
    required this.kind,
    this.durationMs = 500,
  });
  Map<String, dynamic> toJson() =>
      {'from': fromId, 'to': toId, 'kind': kind, 'durationMs': durationMs};
  static Transition fromJson(Map<String, dynamic> j) => Transition(
        fromId: j['from'] as String,
        toId: j['to'] as String,
        kind: j['kind'] as String,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 500,
      );
}

class CanvasSpec {
  final int width;
  final int height;
  final int fps;
  final String background; // 'black', 'blur', '#RRGGBB'
  const CanvasSpec({
    this.width = 1080,
    this.height = 1920,
    this.fps = 30,
    this.background = 'black',
  });
  double get aspect => width / height;
  Map<String, dynamic> toJson() =>
      {'width': width, 'height': height, 'fps': fps, 'background': background};
  static CanvasSpec fromJson(Map<String, dynamic>? j) => j == null
      ? const CanvasSpec()
      : CanvasSpec(
          width: (j['width'] as num?)?.toInt() ?? 1080,
          height: (j['height'] as num?)?.toInt() ?? 1920,
          fps: (j['fps'] as num?)?.toInt() ?? 30,
          background: j['background'] as String? ?? 'black',
        );
}

class ProjectTimeline {
  static const int schemaVersion = 2;

  final List<Track> tracks; // draw order: index 0 = bottom
  final List<Transition> transitions;
  final CanvasSpec canvas;
  final List<int> bookmarksMs;

  /// Project-level settings carried from v1 that aren't timeline structure
  /// (subtitle style, language, karaoke colour, auto-cut, …).
  final Map<String, dynamic> settings;

  const ProjectTimeline({
    this.tracks = const [],
    this.transitions = const [],
    this.canvas = const CanvasSpec(),
    this.bookmarksMs = const [],
    this.settings = const {},
  });

  int get durationMs =>
      tracks.isEmpty ? 0 : tracks.map((t) => t.endMs).reduce(math.max);

  Track? get mainTrack {
    for (final t in tracks) {
      if (t.kind == TrackKind.mainVideo) return t;
    }
    return null;
  }

  Track? track(String id) {
    for (final t in tracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// (track, element) for [elementId], or null.
  (Track, TimelineElement)? find(String elementId) {
    for (final t in tracks) {
      for (final e in t.elements) {
        if (e.id == elementId) return (t, e);
      }
    }
    return null;
  }

  List<Track> tracksOf(TrackKind k) => tracks.where((t) => t.kind == k).toList();

  /// Visible (non-hidden) elements under [ms], bottom to top.
  List<TimelineElement> elementsAt(int ms) => [
        for (final t in tracks)
          if (!t.hidden)
            for (final e in t.elements)
              if (ms >= e.startMs && ms < e.endMs) e,
      ];

  ProjectTimeline copyWith({
    List<Track>? tracks,
    List<Transition>? transitions,
    CanvasSpec? canvas,
    List<int>? bookmarksMs,
    Map<String, dynamic>? settings,
  }) =>
      ProjectTimeline(
        tracks: tracks ?? this.tracks,
        transitions: transitions ?? this.transitions,
        canvas: canvas ?? this.canvas,
        bookmarksMs: bookmarksMs ?? this.bookmarksMs,
        settings: settings ?? this.settings,
      );

  /// Replace one track (matched by id).
  ProjectTimeline withTrack(Track t) => copyWith(
      tracks: [for (final x in tracks) x.id == t.id ? t : x]);

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'canvas': canvas.toJson(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
        if (transitions.isNotEmpty) 'transitions': transitions.map((t) => t.toJson()).toList(),
        if (bookmarksMs.isNotEmpty) 'bookmarksMs': bookmarksMs,
        if (settings.isNotEmpty) 'settings': settings,
      };

  static ProjectTimeline fromJson(Map<String, dynamic> j) {
    final v = (j['schemaVersion'] as num?)?.toInt() ?? 0;
    if (v != schemaVersion) {
      throw FormatException('timeline schema $v, expected $schemaVersion');
    }
    return ProjectTimeline(
      canvas: CanvasSpec.fromJson(j['canvas'] as Map<String, dynamic>?),
      tracks: (j['tracks'] as List)
          .map((t) => Track.fromJson(t as Map<String, dynamic>))
          .toList(),
      transitions: (j['transitions'] as List?)
              ?.map((t) => Transition.fromJson(t as Map<String, dynamic>))
              .toList() ??
          const [],
      bookmarksMs: (j['bookmarksMs'] as List?)?.map((e) => (e as num).toInt()).toList() ??
          const [],
      settings: (j['settings'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

double _d(Object? v, double def) => (v as num?)?.toDouble() ?? def;

List<Keyframe> _kfs(Object? v) =>
    (v as List?)?.map((k) => Keyframe.fromJson(k as Map<String, dynamic>)).toList() ??
    const [];

LayerBlend _blend(Object? v) =>
    v is String ? LayerBlend.values.asNameMap()[v] ?? LayerBlend.normal : LayerBlend.normal;
