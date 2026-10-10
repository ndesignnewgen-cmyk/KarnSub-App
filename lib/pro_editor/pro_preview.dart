import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../timeline/layer_render.dart';
import '../timeline/timeline_model.dart';

/// Pro Editor preview: the main video (from ProMedia) with the timeline's
/// layers composited at the playhead — stickers/photos (with masks), text,
/// shapes, PiP placeholders, subtitles, zoom/fade/shake and transitions.
/// Text, shapes and masks use the same painters as the exported PNGs.
///
/// Tap a layer to select it; drag / pinch / twist the selected one to move,
/// scale and rotate it ([onTransform]; keyframe-aware in the controller).
class ProPreview extends StatelessWidget {
  final ProjectTimeline timeline;
  final int ms;
  final Widget video;
  final double videoAspect;
  final String? selectedId;
  final ValueChanged<String>? onSelect;
  final VoidCallback? onTransformStart;
  final void Function(String id, ElementTransform t)? onTransform;
  final VoidCallback? onTransformEnd;

  const ProPreview({
    super.key,
    required this.timeline,
    required this.ms,
    required this.video,
    required this.videoAspect,
    this.selectedId,
    this.onSelect,
    this.onTransformStart,
    this.onTransform,
    this.onTransformEnd,
  });

  @override
  Widget build(BuildContext context) {
    final canvas = timeline.canvas;
    return Center(
      child: AspectRatio(
        aspectRatio: canvas.aspect,
        child: LayoutBuilder(builder: (_, c) {
          final w = c.maxWidth, h = c.maxHeight;
          final layers = <Widget>[];
          var zoom = 1.0;
          var fx = 0.5, fy = 0.5;
          var fade = 0.0;
          var shake = 0.0;
          for (final tr in timeline.tracks) {
            if (tr.hidden) continue;
            for (final e in tr.elements) {
              if (ms < e.startMs || ms >= e.endMs) continue;
              final rel = ms - e.startMs;
              switch (e) {
                case EffectElement(effect: 'zoom'):
                  final p = e.durationMs <= 0 ? 0.0 : rel / e.durationMs;
                  final from = (e.params['fromScale'] as num?)?.toDouble() ?? 1;
                  final to = (e.params['toScale'] as num?)?.toDouble() ?? 1.3;
                  zoom *= from + (to - from) * p;
                  fx = (e.params['focusX'] as num?)?.toDouble() ?? 0.5;
                  fy = (e.params['focusY'] as num?)?.toDouble() ?? 0.5;
                case EffectElement(effect: 'fade'):
                  final p = e.durationMs <= 0 ? 1.0 : rel / e.durationMs;
                  fade = math.max(fade, e.params['toBlack'] != false ? p : 1 - p);
                case EffectElement(effect: 'shake'):
                  shake = math.max(shake, (e.params['intensity'] as num?)?.toDouble() ?? 0.03);
                case ImageElement():
                  final m = e.mask;
                  layers.add(_placed(e, rel, w, h,
                      m != null && m.shape != 'none'
                          ? _MaskedImage(path: e.src, mask: m)
                          : Image.file(File(e.src), fit: BoxFit.contain, gaplessPlayback: true,
                              errorBuilder: (_, _, _) => _missing(Icons.image)),
                      aspect: null));
                case VideoElement() when tr.kind != TrackKind.mainVideo:
                  layers.add(_placed(e, rel, w, h, _missing(Icons.movie), aspect: 16 / 9));
                case TextElement():
                  final layer = TextLayer(e);
                  layers.add(_placed(e, rel, w, h,
                      CustomPaint(painter: _TextPainter(layer)), aspect: layer.size.aspectRatio));
                case ShapeElement():
                  layers.add(_placed(e, rel, w, h, CustomPaint(painter: _ShapePainter(e)), aspect: 1));
                case SubtitleElement():
                  layers.add(_subtitle(e, w, h));
                default:
                  break;
              }
            }
          }
          // Transitions (as exported: fade / zoom / shake around the cut).
          final main = timeline.mainTrack;
          for (final x in timeline.transitions) {
            final at = main?.elements.where((e) => e.id == x.fromId).firstOrNull?.endMs;
            if (at == null) continue;
            final half = x.durationMs / 2;
            final d = (ms - at).abs();
            if (half <= 0 || d > half) continue;
            final p = 1 - d / half; // 0 far → 1 at the cut
            switch (x.kind) {
              case 'fade':
                fade = math.max(fade, p);
              case 'zoom':
                zoom *= 1 + 0.35 * p;
              case 'shake':
                shake = math.max(shake, 0.05);
            }
          }
          final jitter = shake > 0
              ? Offset(math.sin(ms / 23) * shake * w, math.cos(ms / 31) * shake * h * 0.6)
              : Offset.zero;
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect?.call(''),
                  child: const ColoredBox(color: Colors.black),
                ),
                IgnorePointer(
                  child: Transform.translate(
                    offset: jitter,
                    child: Transform.scale(
                      scale: zoom * (shake > 0 ? 1 + shake * 2 : 1),
                      alignment: Alignment(fx * 2 - 1, fy * 2 - 1),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: SizedBox(
                          width: videoAspect >= 1 ? 1000 : 1000 * videoAspect,
                          height: videoAspect >= 1 ? 1000 / videoAspect : 1000,
                          child: video,
                        ),
                      ),
                    ),
                  ),
                ),
                ...layers,
                if (fade > 0)
                  IgnorePointer(
                      child: ColoredBox(color: Colors.black.withValues(alpha: fade.clamp(0, 1)))),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _missing(IconData i) => Container(
        color: Colors.white10,
        alignment: Alignment.center,
        child: Icon(i, color: Colors.white38),
      );

  /// A visual layer at its transform. [aspect] = width / height of its box
  /// (null: let the child size itself, e.g. a photo).
  Widget _placed(TimelineElement e, int rel, double w, double h, Widget child,
      {required double? aspect}) {
    final v = e as VisualElement;
    final t = transformAt(v.transform, v.keyframes, rel);
    final cover = (e is ImageElement && e.cover) || (e is VideoElement && e.cover);
    final selected = e.id == selectedId;
    final bw = (t.scale * w).clamp(8.0, w * 3);
    final bh = aspect == null ? bw : bw / aspect;
    final body = Opacity(
      opacity: t.opacity.clamp(0.0, 1.0),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..rotateZ(t.rotation * math.pi / 180)
          ..scaleByDouble(t.flipH ? -1.0 : 1.0, 1.0, 1.0, 1.0),
        child: Container(
          decoration: selected
              ? BoxDecoration(border: Border.all(color: AppColors.primary, width: 1.5))
              : null,
          child: child,
        ),
      ),
    );
    final interactive = _Gestures(
      key: ValueKey('pv_${e.id}'),
      onTap: () => onSelect?.call(e.id),
      enabled: selected && onTransform != null,
      start: t,
      canvas: Size(w, h),
      onStart: onTransformStart,
      onChange: (nt) => onTransform?.call(e.id, nt),
      onEnd: onTransformEnd,
      child: body,
    );
    if (cover) return Positioned.fill(child: interactive);
    return Positioned(
      left: t.x * w - bw / 2,
      top: t.y * h - bh / 2,
      width: bw,
      height: bh,
      child: interactive,
    );
  }

  Widget _subtitle(SubtitleElement e, double w, double h) {
    final s = timeline.settings;
    final size = ((s['fontSize'] as num?)?.toDouble() ?? 18) * w / 300;
    final y = (e.data['segPositionY'] as num?)?.toDouble() ??
        (s['subtitlePositionY'] as num?)?.toDouble() ??
        0.85;
    final emoji = e.data['segEmoji'] as String?;
    return Positioned(
      left: w * 0.06,
      right: w * 0.06,
      top: (y * h - size).clamp(0, h - size * 2),
      child: IgnorePointer(
        child: Text(
          emoji == null ? e.text : '${e.text} $emoji',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: size,
            fontWeight: FontWeight.w700,
            height: 1.3,
            shadows: const [Shadow(blurRadius: 4, color: Colors.black), Shadow(blurRadius: 1)],
          ),
        ),
      ),
    );
  }
}

/// Tap to select; when [enabled], one finger moves and two fingers scale and
/// rotate (relative to the transform at gesture start).
class _Gestures extends StatefulWidget {
  final VoidCallback onTap;
  final bool enabled;
  final ElementTransform start;
  final Size canvas;
  final VoidCallback? onStart;
  final ValueChanged<ElementTransform> onChange;
  final VoidCallback? onEnd;
  final Widget child;

  const _Gestures({
    super.key,
    required this.onTap,
    required this.enabled,
    required this.start,
    required this.canvas,
    required this.onChange,
    required this.child,
    this.onStart,
    this.onEnd,
  });

  @override
  State<_Gestures> createState() => _GesturesState();
}

class _GesturesState extends State<_Gestures> {
  ElementTransform? _from;
  Offset _origin = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onScaleStart: widget.enabled
          ? (d) {
              _from = widget.start;
              _origin = d.focalPoint;
              widget.onStart?.call();
            }
          : null,
      onScaleUpdate: widget.enabled
          ? (d) {
              final f = _from;
              if (f == null) return;
              final delta = d.focalPoint - _origin;
              widget.onChange(f.copyWith(
                x: (f.x + delta.dx / widget.canvas.width).clamp(-0.2, 1.2),
                y: (f.y + delta.dy / widget.canvas.height).clamp(-0.2, 1.2),
                scale: (f.scale * d.scale).clamp(0.03, 3.0),
                rotation: f.rotation + d.rotation * 180 / math.pi,
              ));
            }
          : null,
      onScaleEnd: widget.enabled
          ? (_) {
              _from = null;
              widget.onEnd?.call();
            }
          : null,
      child: widget.child,
    );
  }
}

class _TextPainter extends CustomPainter {
  final TextLayer layer;
  _TextPainter(this.layer);
  @override
  void paint(Canvas canvas, Size size) => layer.paint(canvas, size);
  @override
  bool shouldRepaint(_TextPainter o) =>
      o.layer.e.text != layer.e.text || !identical(o.layer.e.style, layer.e.style);
}

class _ShapePainter extends CustomPainter {
  final ShapeElement e;
  _ShapePainter(this.e);
  @override
  void paint(Canvas canvas, Size size) => paintShape(canvas, size, e);
  @override
  bool shouldRepaint(_ShapePainter o) =>
      o.e.shape != e.shape ||
      o.e.fillColor != e.fillColor ||
      o.e.strokeColor != e.strokeColor ||
      o.e.strokeWidth != e.strokeWidth;
}

/// A photo with its mask applied (same painter as the export).
class _MaskedImage extends StatefulWidget {
  final String path;
  final MaskSpec mask;
  const _MaskedImage({required this.path, required this.mask});
  @override
  State<_MaskedImage> createState() => _MaskedImageState();
}

class _MaskedImageState extends State<_MaskedImage> {
  ui.Image? _img;
  String? _loaded;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _MaskedImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  Future<void> _load() async {
    final p = widget.path;
    try {
      final img = await decodeImageFile(p, maxSide: 900);
      if (!mounted || widget.path != p) return;
      setState(() {
        _img = img;
        _loaded = p;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final img = _img;
    if (img == null || _loaded != widget.path) return const SizedBox.expand();
    return AspectRatio(
      aspectRatio: img.width / img.height,
      child: CustomPaint(painter: _MaskPainter(img, widget.mask)),
    );
  }
}

class _MaskPainter extends CustomPainter {
  final ui.Image img;
  final MaskSpec m;
  _MaskPainter(this.img, this.m);
  @override
  void paint(Canvas canvas, Size size) => paintMasked(canvas, size, img, m);
  @override
  bool shouldRepaint(_MaskPainter o) => o.img != img || o.m != m;
}
