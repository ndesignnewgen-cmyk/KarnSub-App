import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/i18n.dart';
import '../theme/app_theme.dart';
import '../timeline/timeline_model.dart';
import 'pro_editor_controller.dart';

/// Video frames for the filmstrip: source path → (source ms, jpeg path).
typedef ThumbMap = Map<String, List<({int ms, String path})>>;

/// CapCut-style multi-track timeline (design screens 01–02): the playhead
/// stays in the middle and the tracks scroll under it.
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
  final ThumbMap thumbs;
  final VoidCallback? onCover;
  final void Function(String fromId, String toId)? onTransition;
  final VoidCallback? onKeyframe;

  const ProTimelineView({
    super.key,
    required this.c,
    required this.onScrubStart,
    required this.onScrub,
    required this.onScrubEnd,
    required this.onAddClip,
    this.onTrackMenu,
    this.thumbs = const {},
    this.onCover,
    this.onTransition,
    this.onKeyframe,
  });

  static const double rulerH = 24;
  static const double mainH = 56;
  static const double barH = 14; // thin overlay tracks (stickers, PiP, effects…)
  static const double subH = 24;
  static const double audioH = 22;
  static const double gap = 5;
  static const double gutterW = 78;
  static const double handleW = 18;

  static const overlayKinds = {
    TrackKind.video, TrackKind.sticker, TrackKind.text, TrackKind.shape, TrackKind.effect,
  };

  /// Display order: overlay tracks above the main track, subtitles and
  /// sound below (subtitle → music → voice → sfx → other audio).
  static List<Track> rows(ProjectTimeline t) {
    int below(TrackKind k) => switch (k) {
          TrackKind.subtitle => 0,
          TrackKind.music => 1,
          TrackKind.voice => 2,
          TrackKind.sfx => 3,
          _ => 4,
        };
    final under = t.tracks
        .where((x) => !overlayKinds.contains(x.kind) && x.kind != TrackKind.mainVideo)
        .toList()
      ..sort((a, b) => below(a.kind).compareTo(below(b.kind)));
    return [
      ...t.tracks.where((x) => overlayKinds.contains(x.kind)).toList().reversed,
      ...t.tracks.where((x) => x.kind == TrackKind.mainVideo),
      ...under,
    ];
  }

  static double rowHeight(Track t) => switch (t.kind) {
        TrackKind.mainVideo => mainH,
        TrackKind.subtitle => subH,
        _ when overlayKinds.contains(t.kind) => barH,
        _ => audioH,
      };

  static Color colorFor(TrackKind k) => switch (k) {
        TrackKind.mainVideo => const Color(0xFF2B3A50),
        TrackKind.video => const Color(0xFF4F8BF0),
        TrackKind.sticker => const Color(0xFFF5B100),
        TrackKind.text => const Color(0xFFFF8A3D),
        TrackKind.shape => const Color(0xFFE879F9),
        TrackKind.effect => const Color(0xFF34D399),
        TrackKind.subtitle => const Color(0xFF5B4FD6),
        TrackKind.music => const Color(0xFF145C55),
        TrackKind.voice => const Color(0xFF8A2D63),
        TrackKind.sfx => const Color(0xFFA32A2A),
        TrackKind.audio => const Color(0xFF0E5E70),
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

  String? _trimId;
  bool _trimLeft = true;
  double _trimStartX = 0;
  int _trimOrigMs = 0;

  String? _moveId;
  int _moveOrigStart = 0;
  double _moveStartX = 0;

  double _rowH(Track t) => ProTimelineView.rowHeight(t);

  List<(Track, double)> _layout(List<Track> rows) {
    var y = ProTimelineView.rulerH + ProTimelineView.gap + 4 - _vScroll;
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
      ProTimelineView.gap * 2;

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

  // ── Background gestures ──────────────────────────────────────────────────

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
    if (dx != 0) widget.onScrub((c.playhead.value - dx * 1000 / c.pxPerSec).round());
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

  // ── Trim (raw pointers so they never fight the scrub gesture) ────────────

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
    c.trimTo(id, leftEdge: _trimLeft, ms: _trimOrigMs + c.pxToMs(ev.position.dx - _trimStartX));
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
      for (final (track, top) in layout) {
        if (y >= top && y < top + _rowH(track) + ProTimelineView.gap) {
          target = track;
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
      final selTrack = c.primaryTrack?.id;
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

            for (final (track, top) in layout) {
              final rh = _rowH(track);
              if (top + rh < ProTimelineView.rulerH || top > h) continue;
              // Other tracks dim while something is selected (design 02).
              final dim = selTrack != null && selTrack != track.id;
              for (final e in track.elements) {
                final l = xOf(e.startMs), r = xOf(e.endMs);
                if (r < -40 || l > w + 40) continue;
                children.add(_block(track, e, l, r - l, top, rh, layout, w, dim));
                if (c.selected.contains(e.id) && !track.locked) {
                  const ht = ProTimelineView.handleW;
                  final isMain = track.kind == TrackKind.mainVideo;
                  children.add(_handle(e, true, l - ht, isMain ? top : top - 4, isMain ? rh : rh + 8));
                  children.add(_handle(e, false, r, isMain ? top : top - 4, isMain ? rh : rh + 8));
                }
              }
              if (track.kind == TrackKind.mainVideo) {
                children.addAll(_transitionMarkers(track, top, rh, xOf, w));
                final endX = xOf(track.endMs);
                if (endX < w + 40) {
                  children.add(Positioned(
                    left: endX + 10,
                    top: top + (rh - 38) / 2,
                    child: _addButton(),
                  ));
                }
                children.add(Positioned(
                  left: 0,
                  top: top - 2,
                  width: ProTimelineView.gutterW,
                  height: rh + 4,
                  child: _gutter(track),
                ));
              } else if (track.muted || track.locked || track.hidden) {
                children.add(Positioned(
                  left: 4,
                  top: top + (rh - 12) / 2,
                  child: IgnorePointer(child: _flags(track)),
                ));
              }
            }

            if (c.timeline.mainTrack == null) {
              children.add(Positioned(
                left: w / 2 + 12,
                top: ProTimelineView.rulerH + 20,
                child: _addButton(),
              ));
            }

            if (c.primary != null && widget.onKeyframe != null) {
              children.add(Positioned(
                right: 10,
                top: ProTimelineView.rulerH + 6,
                child: GestureDetector(
                  key: const Key('pe_keyframe'),
                  onTap: widget.onKeyframe,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.control_point_duplicate,
                        size: 18, color: AppColors.textPrimary),
                  ),
                ),
              ));
            }

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

  List<Widget> _transitionMarkers(
      Track track, double top, double rh, double Function(int) xOf, double w) {
    final out = <Widget>[];
    final els = track.elements;
    for (var i = 0; i + 1 < els.length; i++) {
      final a = els[i], b = els[i + 1];
      if (a.endMs != b.startMs) continue;
      final x = xOf(a.endMs);
      if (x < -20 || x > w + 20) continue;
      final has = c.timeline.transitions.any((t) => t.fromId == a.id && t.toId == b.id);
      out.add(Positioned(
        key: Key('pe_tr_${a.id}'),
        left: x - 11,
        top: top + (rh - 22) / 2,
        child: GestureDetector(
          onTap: widget.onTransition == null ? null : () => widget.onTransition!(a.id, b.id),
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: has ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(5),
              boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black45)],
            ),
            child: Icon(Icons.compare_arrows, size: 14, color: has ? Colors.white : Colors.black87),
          ),
        ),
      ));
    }
    return out;
  }

  Widget _addButton() => GestureDetector(
        key: const Key('pe_addClip'),
        onTap: widget.onAddClip,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.add, color: Colors.black),
        ),
      );

  Widget _gutterTile(IconData icon, String label, VoidCallback? onTap,
          {Key? key, Color color = AppColors.textSecondary, VoidCallback? onLong}) =>
      Expanded(
        child: GestureDetector(
          key: key,
          onTap: onTap,
          onLongPress: onLong,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(height: 3),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(color: AppColors.textHint, fontSize: 8.5)),
              ],
            ),
          ),
        ),
      );

  Widget _gutter(Track track) => Container(
        color: AppColors.background,
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
        child: Row(
          children: [
            _gutterTile(
              track.muted ? Icons.volume_off : Icons.volume_up,
              tr('pe.gutter.mute'),
              () => c.setTrack(track.id, muted: !track.muted),
              key: const Key('pe_mainGutter'),
              color: track.muted ? AppColors.accent : AppColors.textSecondary,
              onLong: widget.onTrackMenu == null ? null : () => widget.onTrackMenu!(track),
            ),
            _gutterTile(Icons.edit_outlined, tr('pe.gutter.cover'), widget.onCover,
                key: const Key('pe_cover')),
          ],
        ),
      );

  Widget _flags(Track track) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (track.muted) const Icon(Icons.volume_off, size: 12, color: Colors.white70),
          if (track.locked) const Icon(Icons.lock, size: 12, color: Colors.white70),
          if (track.hidden) const Icon(Icons.visibility_off, size: 12, color: Colors.white70),
        ],
      );

  String _labelFor(Track track, TimelineElement e) {
    String base(String p) => p.split(RegExp(r'[\\/]')).last;
    switch (e) {
      case SubtitleElement():
        return e.text;
      case TextElement():
        return e.text;
      case AudioElement():
        if (track.kind == TrackKind.voice && e.id == 'aivoice') return tr('pe.aiVoice');
        var name = e.label ?? base(e.src).replaceFirst('sfx:', '');
        if (track.kind == TrackKind.music && (e.label == null || e.label == 'music')) {
          final file = base(e.src);
          final dot = file.lastIndexOf('.');
          name = dot > 0 ? file.substring(0, dot) : file;
        }
        if (track.kind == TrackKind.music) {
          return track.duck ? '♪ $name · ${tr('pe.duck')}' : '♪ $name';
        }
        return name;
      case EffectElement():
        return e.effect;
      case ShapeElement():
        return e.shape;
      case ImageElement():
        return base(e.src);
      case VideoElement():
        return '${(e.durationMs / 1000).toStringAsFixed(1)}s';
    }
  }

  Widget _block(Track track, TimelineElement e, double left, double width, double top, double rh,
      List<(Track, double)> layout, double viewW, bool dimOther) {
    final selected = c.selected.contains(e.id);
    final isMain = track.kind == TrackKind.mainVideo;
    final isBar = ProTimelineView.overlayKinds.contains(track.kind);
    final color = ProTimelineView.colorFor(track.kind);
    final dim = dimOther || track.hidden || (track.muted && isAudioKind(track.kind));
    final bw = math.max(2.0, width);

    Widget body;
    if (isMain) {
      body = _filmstrip(e as VideoElement, left, bw, rh, viewW, selected);
    } else if (isBar && !selected) {
      // Thin coloured bar (design 01); a full block when selected.
      body = Center(
        child: Container(
          height: 7,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        ),
      );
    } else {
      body = Container(
        margin: const EdgeInsets.symmetric(horizontal: 0.5),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: selected ? 2 : 0,
          ),
        ),
        alignment: Alignment.centerLeft,
        child: bw < 24 || isBar
            ? null
            : Text(_labelFor(track, e),
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
                style: const TextStyle(
                    color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
      );
    }

    return Positioned(
      key: Key('pe_el_${e.id}'),
      left: left,
      top: top,
      width: bw,
      height: rh,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => c.select(e.id),
        onLongPressStart: track.locked ? null : (d) => _moveStart(e, d),
        onLongPressMoveUpdate: (d) => _moveUpdate(d, layout),
        onLongPressEnd: (_) => _moveEnd(),
        onLongPressCancel: _moveEnd,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: dim ? 0.38 : 1,
          child: body,
        ),
      ),
    );
  }

  /// Main-track clip: video frames across the block (design 01).
  Widget _filmstrip(VideoElement e, double left, double bw, double rh, double viewW, bool selected) {
    final frames = widget.thumbs[e.src] ?? const [];
    final tiles = <Widget>[];
    if (frames.isNotEmpty) {
      final tileW = rh * 0.78;
      // Only the tiles that are on screen.
      final first = math.max(0, ((-left) / tileW).floor());
      final last = math.min((bw / tileW).ceil(), ((viewW - left) / tileW).ceil());
      for (var i = first; i < last; i++) {
        final x = i * tileW;
        final relMs = ((x + tileW / 2) / c.pxPerSec * 1000).round();
        final srcMs = e.trimInMs + (relMs * e.speed).round();
        var best = frames.first;
        for (final f in frames) {
          if ((f.ms - srcMs).abs() < (best.ms - srcMs).abs()) best = f;
        }
        tiles.add(Positioned(
          left: x,
          top: 0,
          bottom: 0,
          width: tileW + 0.5,
          child: Image.file(File(best.path),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF2B3A50))),
        ));
      }
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0.5),
      decoration: BoxDecoration(
        color: ProTimelineView.colorFor(TrackKind.mainVideo),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected ? Colors.white : Colors.black.withValues(alpha: 0.35),
          width: selected ? 2.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          ...tiles,
          if (bw >= 30)
            Positioned(
              left: 6,
              bottom: 4,
              child: Text('${(e.durationMs / 1000).toStringAsFixed(1)}s',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(blurRadius: 3, color: Colors.black)],
                  )),
            ),
          if (e.speed != 1 && bw >= 50)
            Positioned(
              right: 5,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                    color: AppColors.primaryDark, borderRadius: BorderRadius.circular(4)),
                child: Text('${e.speed}×', style: const TextStyle(color: Colors.white, fontSize: 9)),
              ),
            ),
        ],
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
                left: left ? const Radius.circular(6) : Radius.zero,
                right: left ? Radius.zero : const Radius.circular(6),
              ),
            ),
            alignment: Alignment.center,
            child: Container(width: 2.5, height: rh * 0.38, color: Colors.black87),
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
    final step = _steps.firstWhere((s) => s * pxPerSec / 1000 >= 72, orElse: () => 60000);
    final minor = step ~/ 2;
    final from = math.max(0, ((playhead - w / 2 * 1000 / pxPerSec) ~/ minor) * minor);
    final to = playhead + (w / 2 * 1000 / pxPerSec).round() + minor;
    final dot = Paint()..color = AppColors.textHint;
    for (int t = from; t <= to; t += minor) {
      final x = xOf(t);
      if (t % step == 0) {
        final tp = TextPainter(
          text: TextSpan(
              text: _fmt(t),
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 9.5, fontFamily: 'monospace')),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, 4));
      } else {
        canvas.drawCircle(Offset(x, 10), 1.2, dot);
      }
    }
    final bm = Paint()..color = const Color(0xFFF5A300);
    for (final b in bookmarks) {
      final x = xOf(b);
      if (x < -6 || x > w + 6) continue;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset(x, size.height - 4), width: 7, height: 5),
              const Radius.circular(1.5)),
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
