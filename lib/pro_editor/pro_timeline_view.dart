import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../timeline/timeline_model.dart';
import 'pro_editor_controller.dart';

/// CapCut-style multi-track timeline: the playhead stays in the middle and
/// the tracks scroll under it.
///   * one-finger drag on empty space → scrub (and scroll tracks vertically)
///   * two-finger pinch → zoom
///   * tap a block → select (tap empty space → deselect)
///   * drag the white handles of a selected block → trim (snaps)
///   * long-press a block and drag → move in time / to another track (snaps)
class ProTimelineView extends StatefulWidget {
  final ProEditorController c;
  final VoidCallback onScrubStart;
  final ValueChanged<int> onScrub;
  final VoidCallback onScrubEnd;
  final VoidCallback onAddClip;
  final void Function(Track track)? onTrackMenu;

  const ProTimelineView({
    super.key,
    required this.c,
    required this.onScrubStart,
    required this.onScrub,
    required this.onScrubEnd,
    required this.onAddClip,
    this.onTrackMenu,
  });

  static const double rulerH = 24;
  static const double mainH = 54;
  static const double thinH = 28;
  static const double gap = 4;
  static const double gutterW = 46;
  static const double handleW = 18;

  /// Display order: overlay tracks above the main track, sound/subtitles below.
  static List<Track> rows(ProjectTimeline t) {
    const above = {
      TrackKind.video, TrackKind.sticker, TrackKind.text, TrackKind.shape, TrackKind.effect,
    };
    return [
      ...t.tracks.where((x) => above.contains(x.kind)).toList().reversed,
      ...t.tracks.where((x) => x.kind == TrackKind.mainVideo),
      ...t.tracks.where((x) => !above.contains(x.kind) && x.kind != TrackKind.mainVideo),
    ];
  }

  static Color colorFor(TrackKind k) => switch (k) {
        TrackKind.mainVideo => const Color(0xFF2B3A50),
        TrackKind.video => const Color(0xFF3B82F6),
        TrackKind.sticker => const Color(0xFFF5B100),
        TrackKind.text => const Color(0xFFFF8A3D),
        TrackKind.shape => const Color(0xFFE879F9),
        TrackKind.effect => const Color(0xFF34D399),
        TrackKind.subtitle => AppColors.primaryDark,
        TrackKind.music => const Color(0xFF0F766E),
        TrackKind.voice => const Color(0xFFA23B72),
        TrackKind.sfx => const Color(0xFFB91C1C),
        TrackKind.audio => const Color(0xFF0E7490),
      };

  @override
  State<ProTimelineView> createState() => _ProTimelineViewState();
}

class _ProTimelineViewState extends State<ProTimelineView> {
  ProEditorController get c => widget.c;
  final _stackKey = GlobalKey();

  double _vScroll = 0;
  double _scaleStartPps = 80;
  bool _scrubbing = false;
  bool _rawDrag = false; // a trim handle owns the pointer

  // Trim drag.
  String? _trimId;
  bool _trimLeft = true;
  double _trimStartX = 0;
  int _trimOrigMs = 0;

  // Move drag.
  String? _moveId;
  int _moveOrigStart = 0;
  double _moveStartX = 0;

  double _rowH(Track t) =>
      t.kind == TrackKind.mainVideo ? ProTimelineView.mainH : ProTimelineView.thinH;

  List<(Track, double)> _layout(List<Track> rows) {
    var y = ProTimelineView.rulerH + ProTimelineView.gap - _vScroll;
    return [
      for (final r in rows)
        () {
          final out = (r, y);
          y += _rowH(r) + ProTimelineView.gap;
          return out;
        }(),
    ];
  }

  double _contentH(List<Track> rows) =>
      ProTimelineView.rulerH +
      rows.fold<double>(0, (a, r) => a + _rowH(r) + ProTimelineView.gap) +
      ProTimelineView.gap;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant ProTimelineView old) {
    super.didUpdateWidget(old);
    if (old.c != c) {
      old.c.removeListener(_changed);
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  // ── Background gestures: scrub / vertical scroll / pinch zoom ────────────

  void _onScaleStart(ScaleStartDetails d) {
    if (_rawDrag) return;
    _scaleStartPps = c.pxPerSec;
    if (d.pointerCount < 2) {
      _scrubbing = true;
      widget.onScrubStart();
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails d, double viewH, double contentH) {
    if (_rawDrag) return;
    if (d.pointerCount >= 2) {
      if (_scrubbing) {
        _scrubbing = false;
        widget.onScrubEnd();
      }
      c.zoom((_scaleStartPps * d.horizontalScale) / c.pxPerSec);
      return;
    }
    final dx = d.focalPointDelta.dx;
    if (dx != 0) {
      widget.onScrub((c.playhead.value - dx * 1000 / c.pxPerSec).round());
    }
    final maxV = math.max(0.0, contentH - viewH);
    final nv = (_vScroll - d.focalPointDelta.dy).clamp(0.0, maxV);
    if (nv != _vScroll) setState(() => _vScroll = nv);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_scrubbing) {
      _scrubbing = false;
      widget.onScrubEnd();
    }
  }

  // ── Trim handles (raw pointers, so they never fight the scrub gesture) ───

  void _trimDown(TimelineElement e, bool left, PointerDownEvent ev) {
    _rawDrag = true;
    _trimId = e.id;
    _trimLeft = left;
    _trimStartX = ev.position.dx;
    _trimOrigMs = left ? e.startMs : e.endMs;
    c.beginDrag('trim');
    HapticFeedback.selectionClick();
  }

  void _trimMove(PointerMoveEvent ev) {
    final id = _trimId;
    if (id == null) return;
    final ms = _trimOrigMs + c.pxToMs(ev.position.dx - _trimStartX);
    c.trimTo(id, leftEdge: _trimLeft, ms: ms);
  }

  void _trimUp() {
    if (_trimId == null) return;
    _trimId = null;
    _rawDrag = false;
    c.endDrag();
  }

  // ── Long-press move ──────────────────────────────────────────────────────

  void _moveStart(TimelineElement e, LongPressStartDetails d) {
    _moveId = e.id;
    _moveOrigStart = e.startMs;
    _moveStartX = d.globalPosition.dx;
    c.select(e.id);
    c.beginDrag('move');
    HapticFeedback.mediumImpact();
  }

  void _moveUpdate(LongPressMoveUpdateDetails d, List<(Track, double)> layout) {
    final id = _moveId;
    if (id == null) return;
    final found = c.timeline.find(id);
    if (found == null) return;
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    var target = found.$1;
    if (box != null) {
      final y = box.globalToLocal(d.globalPosition).dy;
      for (final (tr, top) in layout) {
        if (y >= top && y < top + _rowH(tr) + ProTimelineView.gap) {
          target = tr;
          break;
        }
      }
    }
    final start = _moveOrigStart + c.pxToMs(d.globalPosition.dx - _moveStartX);
    c.moveTo(id, target.id, math.max(0, start));
  }

  void _moveEnd() {
    if (_moveId == null) return;
    _moveId = null;
    c.endDrag();
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final rows = ProTimelineView.rows(c.timeline);
      final contentH = _contentH(rows);
      final layout = _layout(rows);
      return ClipRect(
        child: ValueListenableBuilder<int>(
          valueListenable: c.playhead,
          builder: (context, playhead, _) {
            double xOf(int ms) => w / 2 + (ms - playhead) * c.pxPerSec / 1000;
            final children = <Widget>[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: c.clearSelection,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: (d) => _onScaleUpdate(d, h, contentH),
                  onScaleEnd: _onScaleEnd,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: ProTimelineView.rulerH,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _RulerPainter(
                      playhead: playhead,
                      pxPerSec: c.pxPerSec,
                      bookmarks: c.timeline.bookmarksMs,
                    ),
                  ),
                ),
              ),
            ];

            for (final (tr, top) in layout) {
              final rh = _rowH(tr);
              if (top + rh < ProTimelineView.rulerH || top > h) continue;
              // Track-level long press (empty part of the row) → track menu.
              children.add(Positioned(
                left: 0,
                right: 0,
                top: top,
                height: rh,
                child: IgnorePointer(
                  child: Container(
                    color: tr.kind == TrackKind.mainVideo
                        ? Colors.transparent
                        : Colors.white.withValues(alpha: 0.025),
                  ),
                ),
              ));
              for (final e in tr.elements) {
                final l = xOf(e.startMs), r = xOf(e.endMs);
                if (r < -40 || l > w + 40) continue; // off screen
                children.add(_block(tr, e, l, r - l, top, rh, layout));
                if (c.selected.contains(e.id) && !tr.locked) {
                  // Handles sit just OUTSIDE the block as their own widgets so
                  // their whole area is touchable.
                  children.add(_handle(e, true, l - ProTimelineView.handleW, top, rh));
                  children.add(_handle(e, false, r, top, rh));
                }
              }
              if (tr.kind == TrackKind.mainVideo) {
                final endX = xOf(tr.endMs);
                if (endX < w + 40) {
                  children.add(Positioned(
                    left: endX + 8,
                    top: top + (rh - 36) / 2,
                    child: _addButton(),
                  ));
                }
                children.add(Positioned(
                  left: 0,
                  top: top,
                  width: ProTimelineView.gutterW,
                  height: rh,
                  child: _gutter(tr),
                ));
              } else if (tr.muted || tr.locked || tr.hidden) {
                children.add(Positioned(
                  left: 4,
                  top: top + 4,
                  child: IgnorePointer(child: _flags(tr)),
                ));
              }
            }

            if (rows.isEmpty || c.timeline.mainTrack == null) {
              children.add(Positioned(
                left: w / 2 + 12,
                top: ProTimelineView.rulerH + 20,
                child: _addButton(),
              ));
            }

            // Playhead.
            children.add(Positioned(
              left: w / 2 - 1,
              top: 0,
              bottom: 0,
              width: 2,
              child: const IgnorePointer(child: ColoredBox(color: Colors.white)),
            ));
            return Stack(key: _stackKey, clipBehavior: Clip.hardEdge, children: children);
          },
        ),
      );
    });
  }

  Widget _addButton() => GestureDetector(
        key: const Key('pe_addClip'),
        onTap: widget.onAddClip,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.add, color: Colors.black),
        ),
      );

  Widget _gutter(Track tr) => GestureDetector(
        key: const Key('pe_mainGutter'),
        onTap: () => c.setTrack(tr.id, muted: !tr.muted),
        onLongPress: widget.onTrackMenu == null ? null : () => widget.onTrackMenu!(tr),
        child: Container(
          color: AppColors.background,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(tr.muted ? Icons.volume_off : Icons.volume_up,
                  size: 18, color: tr.muted ? AppColors.accent : AppColors.textSecondary),
              const SizedBox(height: 2),
              Text(tr.muted ? 'ປິດສຽງ' : 'ສຽງ',
                  style: const TextStyle(color: AppColors.textHint, fontSize: 9)),
            ],
          ),
        ),
      );

  Widget _flags(Track tr) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tr.muted) const Icon(Icons.volume_off, size: 12, color: Colors.white70),
          if (tr.locked) const Icon(Icons.lock, size: 12, color: Colors.white70),
          if (tr.hidden) const Icon(Icons.visibility_off, size: 12, color: Colors.white70),
        ],
      );

  Widget _block(Track tr, TimelineElement e, double left, double width, double top,
      double rh, List<(Track, double)> layout) {
    final selected = c.selected.contains(e.id);
    final color = ProTimelineView.colorFor(tr.kind);
    final dim = tr.hidden || tr.muted && isAudioKind(tr.kind);
    final label = switch (e) {
      SubtitleElement() => e.text,
      TextElement() => e.text,
      AudioElement() => e.label ?? e.src.split(RegExp(r'[\\/]')).last.replaceFirst('sfx:', ''),
      EffectElement() => e.effect,
      ShapeElement() => e.shape,
      ImageElement() => e.src.split(RegExp(r'[\\/]')).last,
      VideoElement() => tr.kind == TrackKind.mainVideo
          ? '${(e.durationMs / 1000).toStringAsFixed(1)}s'
          : e.src.split(RegExp(r'[\\/]')).last,
    };
    final speedBadge = e is VideoElement && e.speed != 1 ? '${e.speed}×' : null;
    final bw = math.max(2.0, width);
    return Positioned(
      key: Key('pe_el_${e.id}'),
      left: left,
      top: top,
      width: bw,
      height: rh,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => c.select(e.id),
        onLongPressStart: tr.locked ? null : (d) => _moveStart(e, d),
        onLongPressMoveUpdate: (d) => _moveUpdate(d, layout),
        onLongPressEnd: (_) => _moveEnd(),
        onLongPressCancel: _moveEnd,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: dim ? 0.45 : 1,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 0.5),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(tr.kind == TrackKind.mainVideo ? 6 : 5),
                    border: Border.all(
                      color: selected ? Colors.white : Colors.black.withValues(alpha: 0.25),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  alignment: tr.kind == TrackKind.mainVideo
                      ? Alignment.bottomLeft
                      : Alignment.centerLeft,
                  child: bw < 24
                      ? null
                      : Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: tr.kind == TrackKind.mainVideo ? 11 : 10.5,
                            fontWeight: FontWeight.w600,
                          )),
                ),
              ),
            ),
            if (speedBadge != null)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                      color: AppColors.primaryDark, borderRadius: BorderRadius.circular(4)),
                  child: Text(speedBadge,
                      style: const TextStyle(color: Colors.white, fontSize: 9)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _handle(TimelineElement e, bool left, double x, double top, double rh) => Positioned(
        key: Key('pe_trim${left ? 'L' : 'R'}_${e.id}'),
        left: x,
        top: top,
        height: rh,
        width: ProTimelineView.handleW,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (ev) => _trimDown(e, left, ev),
          onPointerMove: _trimMove,
          onPointerUp: (_) => _trimUp(),
          onPointerCancel: (_) => _trimUp(),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.horizontal(
                left: left ? const Radius.circular(5) : Radius.zero,
                right: left ? Radius.zero : const Radius.circular(5),
              ),
            ),
            alignment: Alignment.center,
            child: Container(width: 2, height: rh * 0.4, color: Colors.black54),
          ),
        ),
      );
}

class _RulerPainter extends CustomPainter {
  final int playhead;
  final double pxPerSec;
  final List<int> bookmarks;
  _RulerPainter({required this.playhead, required this.pxPerSec, required this.bookmarks});

  static const _steps = [100, 250, 500, 1000, 2000, 5000, 10000, 30000, 60000];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    double xOf(int ms) => w / 2 + (ms - playhead) * pxPerSec / 1000;
    final step = _steps.firstWhere((s) => s * pxPerSec / 1000 >= 64, orElse: () => 60000);
    final minor = step ~/ 2;
    final from = math.max(0, ((playhead - w / 2 * 1000 / pxPerSec) ~/ minor) * minor);
    final to = playhead + (w / 2 * 1000 / pxPerSec).round() + minor;
    final tick = Paint()
      ..color = AppColors.textHint
      ..strokeWidth = 1;
    for (int t = from; t <= to; t += minor) {
      final x = xOf(t);
      final major = t % step == 0;
      canvas.drawLine(Offset(x, size.height - (major ? 8 : 4)), Offset(x, size.height), tick);
      if (major) {
        final tp = TextPainter(
          text: TextSpan(
              text: _fmt(t),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 9, fontFamily: 'monospace')),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, 2));
      }
    }
    final bm = Paint()..color = AppColors.warning;
    for (final b in bookmarks) {
      final x = xOf(b);
      if (x < -6 || x > w + 6) continue;
      canvas.drawPath(
          Path()
            ..moveTo(x - 4, size.height - 10)
            ..lineTo(x + 4, size.height - 10)
            ..lineTo(x, size.height - 3)
            ..close(),
          bm);
    }
  }

  static String _fmt(int ms) {
    final s = ms ~/ 1000;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    if (ms % 1000 != 0) return '$ss.${(ms % 1000) ~/ 100}';
    return '$mm:$ss';
  }

  @override
  bool shouldRepaint(_RulerPainter o) =>
      o.playhead != playhead || o.pxPerSec != pxPerSec || o.bookmarks != bookmarks;
}
