import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../timeline/timeline_model.dart';

/// Pro Editor preview: the main video (from [ProMedia]) with the timeline's
/// layers composited in Flutter at the playhead — stickers/photos, PiP
/// placeholders, text, subtitles, zoom and fade effects.
///
/// This is the phase-2 preview; the exported video still comes from the
/// existing exporter (through the v1 bridge) until the unified GL engine of
/// phase 3 makes preview == export.
class ProPreview extends StatelessWidget {
  final ProjectTimeline timeline;
  final int ms;
  final Widget video;
  final double videoAspect;
  final String? selectedId;

  const ProPreview({
    super.key,
    required this.timeline,
    required this.ms,
    required this.video,
    required this.videoAspect,
    this.selectedId,
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
                  final toBlack = e.params['toBlack'] != false;
                  fade = math.max(fade, toBlack ? p : 1 - p);
                case ImageElement():
                  layers.add(_placed(e, rel, w, h,
                      Image.file(File(e.src), fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => _missing(Icons.image))));
                case VideoElement() when tr.kind != TrackKind.mainVideo:
                  layers.add(_placed(e, rel, w, h,
                      AspectRatio(aspectRatio: 16 / 9, child: _missing(Icons.movie))));
                case TextElement():
                  layers.add(_placed(e, rel, w, h, Text(e.text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Color((e.style['color'] as num?)?.toInt() ?? 0xFFFFFFFF),
                          fontSize: ((e.style['size'] as num?)?.toDouble() ?? 28) * w / 360,
                          fontWeight: FontWeight.w800,
                          shadows: const [Shadow(blurRadius: 4)]))));
                case SubtitleElement():
                  layers.add(_subtitle(e, w, h));
                default:
                  break;
              }
            }
          }
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                Transform.scale(
                  scale: zoom,
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
                ...layers,
                if (fade > 0)
                  IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: fade.clamp(0, 1)))),
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

  Widget _placed(TimelineElement e, int rel, double w, double h, Widget child) {
    final v = e as VisualElement;
    final t = transformAt(v.transform, v.keyframes, rel);
    final cover = (e is ImageElement && e.cover) || (e is VideoElement && e.cover);
    final selected = e.id == selectedId;
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
    if (cover) return Positioned.fill(child: body);
    final bw = (t.scale * w).clamp(8.0, w * 3);
    return Positioned(
      left: t.x * w - bw / 2,
      top: t.y * h - bw / 2,
      width: bw,
      height: bw,
      child: Center(child: body),
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
    );
  }
}
