part of '../editor_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Timeline tab: tracks, filmstrip, blocks, toolbars, mixer.
/// Split out of editor_screen.dart verbatim (phase 0) — the
/// fields and lifecycle stay in [_EditorScreenState].
extension _EditorTimeline on _EditorScreenState {
  Widget _buildScrubber() {
    final totalMs = _duration.inMilliseconds.toDouble();
    final currentMs = _position.inMilliseconds.toDouble();

    Widget sideBtn(IconData icon, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, color: AppColors.textSecondary, size: 19),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              _formatDuration(_position),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                sideBtn(Icons.replay_5_rounded, () {
                  final t = _position - const Duration(seconds: 5);
                  _seekTo(t < Duration.zero ? Duration.zero : t);
                }),
                const SizedBox(width: 22),
                GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: AppGradients.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 22),
                sideBtn(Icons.forward_5_rounded, () {
                  final t = _position + const Duration(seconds: 5);
                  _seekTo(t > _duration ? _duration : t);
                }),
              ],
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              _formatDuration(_duration),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11.5,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final tabs = [
      (Icons.edit_note_rounded, tr('ed.tab.text')),
      (Icons.view_timeline_outlined, tr('ed.tab.timeline')),
      (Icons.palette_outlined, tr('ed.tab.style')),
      (Icons.height_rounded, tr('ed.tab.position')),
    ];
    const innerH = 38.0;
    final anim = _tabController.animation;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final tabW = c.maxWidth / tabs.length;
          return SizedBox(
            height: innerH,
            child: AnimatedBuilder(
              animation: anim ?? _tabController,
              builder: (context, _) {
                // anim.value is a continuous 0..n-1 position that follows the
                // swipe, so the pill slides smoothly between tabs.
                final pos = anim?.value ?? _tabController.index.toDouble();
                return Stack(
                  children: [
                    Positioned(
                      left: pos * tabW,
                      top: 0,
                      bottom: 0,
                      width: tabW,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppGradients.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (int i = 0; i < tabs.length; i++)
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _tabController.animateTo(i),
                              child: () {
                                final on = (pos - i).abs() < 0.5;
                                final col = on
                                    ? Colors.white
                                    : AppColors.textSecondary;
                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(tabs[i].$1, size: 16, color: col),
                                    const SizedBox(height: 2),
                                    Text(
                                      tabs[i].$2,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: col,
                                      ),
                                    ),
                                  ],
                                );
                              }(),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabContent() {
    return TabBarView(
      controller: _tabController,
      // Tabs change only by tapping the tab bar — so pinch-zoom / drags on the
      // timeline never accidentally swipe to the Transcript/Style tab.
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildTranscriptTab(),
        _buildTimelineTab(),
        _buildStyleTab(),
        _buildPositionTab(),
      ],
    );
  }

  // ─── CapCut-style timeline ────────────────────────────────────────────────

  void _shiftSegment(SubtitleSegment s, int deltaMs) {
    int c(int v) => v < 0 ? 0 : v;
    s.startTime = Duration(
      milliseconds: c(s.startTime.inMilliseconds + deltaMs),
    );
    s.endTime = Duration(milliseconds: c(s.endTime.inMilliseconds + deltaMs));
    if (s.wordTimings != null) {
      s.wordTimings = s.wordTimings!
          .map((t) => Duration(milliseconds: c(t.inMilliseconds + deltaMs)))
          .toList();
    }
  }

  /// Ripple shift: move segment [index] AND every segment after it by [deltaMs]
  /// (used in ripple mode so fixing a drift point carries the rest along).
  void _shiftFromIndex(int index, int deltaMs, ProjectProvider provider) {
    final segs = provider.currentProject?.segments;
    if (segs == null) return;
    for (int k = index; k < segs.length; k++) {
      _shiftSegment(segs[k], deltaMs);
    }
  }

  void _resizeStart(SubtitleSegment s, int deltaMs) {
    final endMs = s.endTime.inMilliseconds;
    final ns = (s.startTime.inMilliseconds + deltaMs).clamp(0, endMs - 200);
    s.startTime = Duration(milliseconds: ns);
  }

  void _resizeEnd(SubtitleSegment s, int deltaMs, int maxMs) {
    final startMs = s.startTime.inMilliseconds;
    final ne = (s.endTime.inMilliseconds + deltaMs).clamp(startMs + 200, maxMs);
    s.endTime = Duration(milliseconds: ne);
  }

  void _snapSegmentToOnset(SubtitleSegment s) {
    if (_timelineOnsets.isEmpty) return;
    final st = s.startTime.inMilliseconds;
    int best = _timelineOnsets.first;
    int bestD = (best - st).abs();
    for (final o in _timelineOnsets) {
      final d = (o - st).abs();
      if (d < bestD) {
        bestD = d;
        best = o;
      }
    }
    if (bestD <= 150) _shiftSegment(s, best - st);
  }

  /// Snap a trimmed edge (start if [isLeft], else end) to the nearest detected
  /// speech onset within 180ms — so dragging an edge locks onto real speech.
  void _snapEdgeToOnset(SubtitleSegment s, bool isLeft) {
    if (_timelineOnsets.isEmpty) return;
    final t = isLeft ? s.startTime.inMilliseconds : s.endTime.inMilliseconds;
    int best = _timelineOnsets.first;
    int bestD = (best - t).abs();
    for (final o in _timelineOnsets) {
      final d = (o - t).abs();
      if (d < bestD) {
        bestD = d;
        best = o;
      }
    }
    if (bestD > 180) return;
    if (isLeft) {
      if (best < s.endTime.inMilliseconds - 200) {
        s.startTime = Duration(milliseconds: best);
      }
    } else {
      if (best > s.startTime.inMilliseconds + 200) {
        s.endTime = Duration(milliseconds: best);
      }
    }
  }

  /// Pinch tracking: drop a finger; end the pinch when fewer than 2 remain.
  void _endPtr(int pointer) {
    _ptrs.remove(pointer);
    if (_pinching && _ptrs.length < 2) {
      setState(() => _pinching = false);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollTimelineToPosition(),
      );
    }
  }

  // CapCut model: the playhead is FIXED at the viewport centre and the timeline
  // scrolls under it, so scrollOffset (px) maps directly to time: offset = t*px.


  Widget _timelineBlock(
    int i,
    SubtitleSegment s,
    ProjectProvider provider,
    double leftPad,
    int totalMs,
    String fontFamily,
    double blockTop,
    double blockHeight,
  ) {
    final left = (s.startTime.inMilliseconds / 1000.0) * _pxPerSec + leftPad;
    final w =
        ((s.endTime.inMilliseconds - s.startTime.inMilliseconds) /
                1000.0 *
                _pxPerSec)
            .clamp(48.0, 100000.0);
    final active = _activeSegmentIndex == i;
    final selected = _selectedIndex == i;
    Widget handle(bool isLeft) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) {
        _pauseForEdit();
        provider.pushHistory();
        _dragIndex = i;
      },
      onHorizontalDragUpdate: (d) {
        final deltaMs = (d.delta.dx / _pxPerSec * 1000).round();
        if (isLeft) {
          _resizeStart(s, deltaMs);
        } else {
          _resizeEnd(s, deltaMs, totalMs);
        }
        provider.liveUpdate();
        setState(() {});
      },
      onHorizontalDragEnd: (_) {
        _snapEdgeToOnset(s, isLeft); // lock the edge to real speech
        provider.commit();
        setState(() => _dragIndex = null);
      },
      child: Container(
        width: 16,
        decoration: BoxDecoration(
          color: selected ? Colors.white38 : Colors.white24,
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(isLeft ? 7 : 0),
            right: Radius.circular(isLeft ? 0 : 7),
          ),
        ),
        child: Icon(
          isLeft ? Icons.chevron_left : Icons.chevron_right,
          size: 13,
          color: Colors.white,
        ),
      ),
    );
    return Positioned(
      top: blockTop,
      height: blockHeight,
      left: left,
      width: w,
      child: Container(
        decoration: BoxDecoration(
          color: (active || selected)
              ? AppColors.primary
              : AppColors.primary.withOpacity(0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? Colors.white
                : (active ? Colors.white54 : Colors.transparent),
            width: selected ? 2.2 : 1.5,
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: Row(
          children: [
            handle(true),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _pauseForEdit();
                  // Keep the playhead if it's already inside this caption.
                  _seekIfOutside(s.startTime, s.endTime);
                  setState(() {
                    _activeSegmentIndex = i;
                    _selectedIndex = i;
                    _selectedSfxId = null;
                    _selectedClipIndex = null;
                    _selectedImageId = null;
                  });
                },
                onDoubleTap: () => _editSegment(s, i, provider),
                onHorizontalDragStart: (_) {
                  _pauseForEdit();
                  provider.pushHistory();
                  _dragIndex = i;
                },
                onHorizontalDragUpdate: (d) {
                  final deltaMs = (d.delta.dx / _pxPerSec * 1000).round();
                  if (_rippleMode) {
                    _shiftFromIndex(i, deltaMs, provider);
                  } else {
                    _shiftSegment(s, deltaMs);
                  }
                  provider.liveUpdate();
                  setState(() {});
                },
                onHorizontalDragEnd: (_) {
                  // In ripple mode everything moved together — don't re-snap one.
                  if (!_rippleMode) _snapSegmentToOnset(s);
                  provider.commit();
                  setState(() => _dragIndex = null);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    s.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _applyLaoFont(
                      fontFamily,
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            handle(false),
          ],
        ),
      ),
    );
  }

  /// Filmstrip band of video frame thumbnails, placed behind the caption
  /// blocks (which are semi-transparent, so frames show through — CapCut style).
  Widget _buildFilmstrip(double leftPad, double top, double height) {
    final provider = context.read<ProjectProvider>();
    final project = provider.currentProject;
    final removed = project?.removedRanges ?? const <List<int>>[];
    final clips = project != null ? _videoClips(project) : const <({int start, int end})>[];
    final totalMs = _duration.inMilliseconds;
    // Multi-clip inline filmstrip (each source clip = its own block + divider).
    final mc = (project?.clips.length ?? 0) >= 2;
    final mcBounds =
        mc ? _clipBounds(project!) : const <({int start, int end, int dur})>[];

    // Trim handle for a video clip: drag left/right edge → record the trimmed
    // slice as a removedRange (CapCut-style direct trim).
    Widget clipTrimHandle(({int start, int end}) clip, bool isLeft) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          _pauseForEdit();
          _dragIndex = -1;
        },
        onHorizontalDragUpdate: (d) {
          final deltaMs = (d.delta.dx / _pxPerSec * 1000).round();
          setState(() {
            if (isLeft) {
              _clipTrimLeft = (_clipTrimLeft + deltaMs)
                  .clamp(0, (clip.end - clip.start) - 200);
            } else {
              _clipTrimRight = (_clipTrimRight - deltaMs)
                  .clamp(0, (clip.end - clip.start) - 200);
            }
          });
        },
        onHorizontalDragEnd: (_) {
          if (isLeft && _clipTrimLeft > 50) {
            _cutRange(provider, clip.start, clip.start + _clipTrimLeft);
          } else if (!isLeft && _clipTrimRight > 50) {
            _cutRange(provider, clip.end - _clipTrimRight, clip.end);
          }
          setState(() {
            _clipTrimLeft = 0;
            _clipTrimRight = 0;
            _dragIndex = null;
          });
        },
        child: Container(
          width: 14,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(isLeft ? 6 : 0),
              right: Radius.circular(isLeft ? 0 : 6),
            ),
          ),
          child: Icon(isLeft ? Icons.chevron_left : Icons.chevron_right,
              size: 13, color: Colors.white),
        ),
      );
    }

    return Positioned(
      top: top,
      height: height,
      left: 0,
      right: 0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Base: raw thumbnails.
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                if (mc) ...[
                  // Each source clip = its OWN block (rounded + border + gap),
                  // CapCut/Premiere style. Tap a block to select + jump to it.
                  for (int ci = 0; ci < project!.clips.length; ci++)
                    Builder(builder: (_) {
                      final clip = project.clips[ci];
                      final b = mcBounds[ci];
                      final cLeft = b.start / 1000.0 * _pxPerSec + leftPad;
                      final cW = (b.dur / 1000.0 * _pxPerSec).clamp(8.0, 1e6);
                      final ts = _clipThumbs[clip.id] ?? const [];
                      final sel = _mcSelected == ci;
                      final dragging = _dragClipIndex == ci;
                      return Positioned(
                        left: cLeft + 1.5 + (dragging ? _dragClipDx : 0),
                        top: 0,
                        height: height,
                        width: (cW - 3).clamp(6.0, 1e6),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _pauseForEdit();
                            setState(() {
                              _mcSelected = ci;
                              _selectedIndex = null;
                              _selectedSfxId = null;
                              _selectedClipIndex = null;
                              _selectedImageId = null;
                            });
                            _seekGlobal(b.start);
                            _scrollTimelineToPosition();
                          },
                          // Long-press + drag a block to reorder it (CapCut).
                          onLongPressStart: (_) {
                            _pauseForEdit();
                            setState(() {
                              _mcSelected = ci;
                              _dragClipIndex = ci;
                              _dragClipDx = 0;
                            });
                          },
                          onLongPressMoveUpdate: (d) {
                            setState(() => _dragClipDx = d.offsetFromOrigin.dx);
                          },
                          onLongPressEnd: (_) =>
                              _commitClipDrag(provider, ci, cLeft, leftPad),
                          child: Opacity(
                            opacity: dragging ? 0.75 : 1.0,
                            child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: sel
                                    ? Colors.white
                                    : const Color(0xFF7C4DFF),
                                width: sel ? 2.0 : 1.2,
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: ts.isEmpty
                                  ? Container(
                                      color: AppColors.surfaceLight,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                          Icons.movie_creation_outlined,
                                          color: AppColors.textHint,
                                          size: 16),
                                    )
                                  : Row(
                                      children: [
                                        for (final t in ts)
                                          Expanded(
                                            child: Image.file(
                                              File(t.path),
                                              fit: BoxFit.cover,
                                              gaplessPlayback: true,
                                              cacheHeight: 160,
                                              errorBuilder: (_, __, ___) =>
                                                  Container(
                                                      color: AppColors
                                                          .surfaceLight),
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                          ),
                          ),
                        ),
                      );
                    }),
                ] else
                  for (int i = 0; i < _thumbs.length; i++)
                    Positioned(
                      left: _thumbs[i].ms / 1000.0 * _pxPerSec + leftPad,
                      top: 0,
                      height: height,
                      width: ((i + 1 < _thumbs.length
                                  ? _thumbs[i + 1].ms - _thumbs[i].ms
                                  : 2000) /
                              1000.0 *
                              _pxPerSec) +
                          1,
                      child: Image.file(
                        File(_thumbs[i].path),
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        cacheHeight: 160,
                        errorBuilder: (_, __, ___) =>
                            Container(color: AppColors.surfaceLight),
                      ),
                    ),
                // Dim removed (cut) ranges.
                for (final r in removed)
                  Positioned(
                    left: r[0] / 1000.0 * _pxPerSec + leftPad,
                    top: 0,
                    height: height,
                    width:
                        ((r[1] - r[0]) / 1000.0 * _pxPerSec).clamp(2.0, 100000.0),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.72),
                      alignment: Alignment.center,
                      child: const Icon(Icons.content_cut,
                          color: Colors.redAccent, size: 12),
                    ),
                  ),
                // Auto-Cut: shade the silence gaps that WILL be trimmed on
                // export, so the result is visible before committing.
                if ((project?.isAutoCut ?? false) && _keptRegions.isNotEmpty)
                  ...(() {
                    final gaps = <List<int>>[];
                    int cursor = 0;
                    for (final r in _keptRegions) {
                      if (r[0] > cursor + 80) gaps.add([cursor, r[0]]);
                      cursor = r[1];
                    }
                    if (totalMs > cursor + 80) gaps.add([cursor, totalMs]);
                    return [
                      for (final g in gaps)
                        Positioned(
                          left: g[0] / 1000.0 * _pxPerSec + leftPad,
                          top: 0,
                          height: height,
                          width: ((g[1] - g[0]) / 1000.0 * _pxPerSec)
                              .clamp(2.0, 100000.0),
                          child: IgnorePointer(
                            child: Container(
                              color: const Color(0xFFE040FB)
                                  .withValues(alpha: 0.30),
                              alignment: Alignment.center,
                              child: const Icon(Icons.content_cut,
                                  color: Color(0xFFE040FB), size: 11),
                            ),
                          ),
                        ),
                    ];
                  })(),
              ],
            ),
          ),
          // Clip outlines + tap-to-select + split dividers (single-video cuts).
          // Skipped for multi-clip projects — the per-clip blocks above handle it.
          if (!mc)
          for (int ci = 0; ci < clips.length; ci++)
            Builder(builder: (_) {
              final clip = clips[ci];
              final selected = _selectedClipIndex == ci;
              final visLeft = (clip.start / 1000.0) * _pxPerSec +
                  leftPad +
                  (selected ? _clipTrimLeft / 1000.0 * _pxPerSec : 0);
              final visW = (((clip.end - clip.start) / 1000.0) * _pxPerSec -
                      (selected
                          ? (_clipTrimLeft + _clipTrimRight) / 1000.0 * _pxPerSec
                          : 0))
                  .clamp(8.0, 100000.0);
              return Positioned(
                left: visLeft,
                top: 0,
                height: height,
                width: visW,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _pauseForEdit();
                    _seekIfOutside(Duration(milliseconds: clip.start),
                        Duration(milliseconds: clip.end));
                    setState(() {
                      _selectedIndex = null;
                      _selectedSfxId = null;
                      _selectedImageId = null;
                      _selectedClipIndex = ci;
                      _clipTrimLeft = 0;
                      _clipTrimRight = 0;
                    });
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Selection outline.
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected ? AppColors.primary : Colors.white24,
                            width: selected ? 2.5 : 1,
                          ),
                        ),
                      ),
                      if (selected) ...[
                        Positioned(
                            left: 0, top: 0, bottom: 0, child: clipTrimHandle(clip, true)),
                        Positioned(
                            right: 0, top: 0, bottom: 0, child: clipTrimHandle(clip, false)),
                      ],
                    ],
                  ),
                ),
              );
            }),
          // Split-point dividers (white lines).
          if (project != null)
            for (final sp in project.splitPointsMs)
              if (sp > 0 && sp < totalMs)
                Positioned(
                  left: (sp / 1000.0) * _pxPerSec + leftPad - 1,
                  top: 0,
                  height: height,
                  width: 2,
                  child: Container(color: Colors.white),
                ),
          // Zoom keyframe markers (◆) — CapCut-style. Tap = jump, drag = retime,
          // long-press = delete.
          if (project != null)
            for (final z in project.zoomEffects)
              for (final kf in z.keyframes)
                Positioned(
                  left: (kf.timeMs / 1000.0) * _pxPerSec + leftPad - 11,
                  top: height / 2 - 11,
                  width: 22,
                  height: 22,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _seekTo(Duration(milliseconds: kf.timeMs));
                      _scrollTimelineToPosition();
                    },
                    onLongPress: () {
                      provider.pushHistory();
                      z.keyframes.remove(kf);
                      if (z.keyframes.isEmpty) {
                        project.zoomEffects.remove(z);
                      }
                      provider.commit();
                      setState(() {});
                      _toast(tr('ed.kfDeleted'));
                    },
                    onHorizontalDragStart: (_) {
                      _pauseForEdit();
                      provider.pushHistory();
                      _dragIndex = -1;
                    },
                    onHorizontalDragUpdate: (d) {
                      final deltaMs = (d.delta.dx / _pxPerSec * 1000).round();
                      setState(() {
                        kf.timeMs = (kf.timeMs + deltaMs).clamp(
                            z.startTime.inMilliseconds, z.endTime.inMilliseconds);
                      });
                      provider.liveUpdate();
                    },
                    onHorizontalDragEnd: (_) {
                      z.keyframes.sort((a, b) => a.timeMs.compareTo(b.timeMs));
                      provider.commit();
                      setState(() => _dragIndex = null);
                    },
                    child: Center(
                      child: Transform.rotate(
                        angle: 0.7853981634, // 45° → diamond
                        child: Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color:
                              ((kf.timeMs - _position.inMilliseconds).abs() <= 120)
                                  ? Colors.redAccent
                                  : const Color(0xFFFFB703),
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(color: Colors.white, width: 1.2),
                            boxShadow: const [
                              BoxShadow(color: Colors.black54, blurRadius: 2),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  /// Contextual action toolbar — shown at the BOTTOM of the timeline tab when a
  /// caption block is selected; otherwise a short hint.
  Widget _buildSegToolbar(
    ProjectProvider provider,
    List<SubtitleSegment> segments,
  ) {
    final project = provider.currentProject;
    if (project == null) return const SizedBox.shrink();
    // Show the toolbar even with no subtitles when this is a multi-clip project
    // (Edit-Clip mode) so clip tools are reachable.
    if (segments.isEmpty && project.clips.length < 2) {
      return const SizedBox.shrink();
    }

    int target = (_selectedIndex != null && _selectedIndex! < segments.length)
        ? _selectedIndex!
        : -1;
    if (target < 0 && segments.isNotEmpty) {
      for (int k = 0; k < segments.length; k++) {
        if (_position >= segments[k].startTime &&
            _position <= segments[k].endTime) {
          target = k;
          break;
        }
      }
    }
    if (target < 0 && segments.isNotEmpty) {
      target = _activeSegmentIndex.clamp(0, segments.length - 1);
    }
    final i = target; // -1 when there are no segments (multi-clip edit mode)

    final isSfxSelected = _selectedSfxId != null;

    // One tab-bar-style item: icon on top, label below.
    Widget item(
      IconData icon,
      String label,
      VoidCallback onTap, {
      bool danger = false,
      bool highlight = false,
      Color? customColor,
      Widget? customIcon,
    }) {
      final col = customColor ?? (danger
          ? AppColors.accent
          : (highlight ? const Color(0xFFFFD700) : AppColors.textSecondary));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick(); // subtle tap feedback (CapCut-feel)
          onTap();
        },
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              customIcon ?? Icon(icon, size: 20, color: col),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: col,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_mcSelected >= 0 &&
                  (provider.currentProject?.clips.length ?? 0) >= 2) ...[
                // A clip block is selected → clip actions (reorder/split/delete).
                item(Icons.chevron_left, tr('ed.clipMoveLeft'),
                    () => _mcMove(provider, -1)),
                item(Icons.chevron_right, tr('ed.clipMoveRight'),
                    () => _mcMove(provider, 1)),
                item(Icons.content_cut_rounded, tr('ed.split'),
                    () => _mcSplit(provider),
                    customColor: const Color(0xFF42A5F5)),
                item(Icons.delete_outline, tr('ed.delete'),
                    () => _deleteClip(provider, _mcSelected),
                    danger: true),
              ] else if (_selectedImageId != null) ...[
                // Image overlay toolbar: resize, rotate, delete.
                item(
                  Icons.photo_size_select_large,
                  tr('ed.size'),
                  () => _showImageScaleSheet(provider, _selectedImageId!),
                  customColor: AppColors.primary,
                ),
                item(
                  Icons.rotate_right,
                  tr('ed.rotate'),
                  () => _rotateImageOverlay(provider, _selectedImageId!),
                ),
                item(
                  Icons.flip,
                  tr('ed.flip'),
                  () => _flipImageOverlay(provider, _selectedImageId!),
                ),
                () {
                  final sel = provider.currentProject?.imageOverlays
                      .where((e) => e.id == _selectedImageId)
                      .firstOrNull;
                  final isCover = sel?.cover ?? false;
                  return item(
                    isCover ? Icons.fullscreen_exit : Icons.fullscreen,
                    tr(isCover ? 'ed.coverOff' : 'ed.coverOn'),
                    () => _toggleCover(provider, _selectedImageId!),
                    customColor: isCover ? AppColors.primary : null,
                  );
                }(),
                item(
                  Icons.opacity,
                  tr('ed.opacity'),
                  () => _showOverlayOpacitySheet(provider, _selectedImageId!),
                ),
                () {
                  final ov = provider.currentProject?.imageOverlays
                      .where((e) => e.id == _selectedImageId)
                      .firstOrNull;
                  final onKf = ov != null && _overlayKfAtPlayhead(ov) != null;
                  return item(
                    onKf ? Icons.diamond : Icons.diamond_outlined,
                    tr(onKf ? 'ed.kfRemove' : 'ed.kfAdd'),
                    () => _toggleOverlayKeyframe(provider, _selectedImageId!),
                    customColor:
                        onKf ? Colors.redAccent : const Color(0xFFFFB703),
                  );
                }(),
                () {
                  final ov = provider.currentProject?.imageOverlays
                      .where((e) => e.id == _selectedImageId)
                      .firstOrNull;
                  final kf = ov != null ? _overlayKfAtPlayhead(ov) : null;
                  if (kf == null) return const SizedBox.shrink();
                  return item(
                    Icons.show_chart,
                    tr('ed.curve'),
                    () => _showEasingSheet(kf.easing, (e) {
                      provider.pushHistory();
                      kf.easing = e;
                      provider.commit();
                      setState(() {});
                      _toast(tr('ed.curveSet'));
                    }),
                    customColor: const Color(0xFF00BFA5),
                  );
                }(),
                item(
                  Icons.delete_outline,
                  tr('ed.deleteImage'),
                  () => _deleteImageOverlay(provider, _selectedImageId!),
                  danger: true,
                ),
              ] else if (_selectedClipIndex != null) ...[
                // Video clip toolbar: split at playhead, zoom, or delete this clip.
                item(
                  Icons.content_cut_rounded,
                  tr('ed.cutClip'),
                  () => _splitVideoAtPlayhead(provider),
                  customColor: AppColors.primary,
                ),
                item(
                  Icons.zoom_in_rounded,
                  tr('ed.zoom'),
                  () => _showZoomSheet(provider),
                  customColor: const Color(0xFFFFB703),
                ),
                () {
                  final onKf = _clipZoomKfAtPlayhead(project) != null;
                  return item(
                    onKf ? Icons.diamond : Icons.diamond_outlined,
                    tr(onKf ? 'ed.kfRemove' : 'ed.kfAdd'),
                    () => _toggleClipKeyframe(provider),
                    customColor:
                        onKf ? Colors.redAccent : const Color(0xFF00BFA5),
                  );
                }(),
                () {
                  final kf = _clipZoomKfAtPlayhead(project);
                  if (kf == null) return const SizedBox.shrink();
                  return item(
                    Icons.show_chart,
                    tr('ed.curve'),
                    () => _showEasingSheet(kf.easing, (e) {
                      provider.pushHistory();
                      kf.easing = e;
                      provider.commit();
                      setState(() {});
                      _toast(tr('ed.curveSet'));
                    }),
                    customColor: const Color(0xFF00BFA5),
                  );
                }(),
                item(
                  Icons.gradient_rounded,
                  tr('ed.fade'),
                  () => _showFadeSheet(provider),
                  customColor: const Color(0xFF9C27B0),
                ),
                item(
                  Icons.vibration,
                  tr('ed.shake'),
                  () => _showShakeSheet(provider),
                  customColor: const Color(0xFFEA4C89),
                ),
                item(
                  Icons.delete_outline,
                  tr('ed.deleteClip'),
                  () => _deleteSelectedClip(provider),
                  danger: true,
                ),
              ] else if (_selectedSfxId == 'ai_voice') ...[
                // AI-voice track toolbar: split (trim tail), volume, remove.
                item(
                  Icons.content_cut,
                  tr('ed.cut'),
                  () => _splitAiVoiceAtPlayhead(provider),
                ),
                item(
                  Icons.volume_up,
                  tr('ed.audio'),
                  () => _showAudioMixerSheet(provider),
                  customColor: AppColors.primary,
                ),
                item(
                  Icons.delete_outline,
                  tr('ed.deleteAiVoice'),
                  () => _removeAiVoiceTrack(provider),
                  danger: true,
                ),
              ] else if (isSfxSelected) ...[
                // SFX block toolbar: copy / split / volume / delete.
                item(
                  Icons.content_copy,
                  tr('ed.copy'),
                  () => _duplicateSfx(provider, _selectedSfxId!),
                ),
                item(
                  Icons.content_cut,
                  tr('ed.split'),
                  () => _splitSfxAtPlayhead(provider, _selectedSfxId!),
                ),
                item(
                  Icons.volume_up,
                  tr('ed.audio'),
                  () => _showBlockVolumeSheet(provider, _selectedSfxId!),
                ),
                item(
                  Icons.delete_outline,
                  tr('ed.deleteSfx'),
                  () => _deleteSfx(provider, _selectedSfxId!),
                  danger: true,
                ),
              ] else ...[
                // ✨ 1-Tap Auto Edit (the hero one-tap polish).
                item(
                  Icons.movie_filter,
                  tr('ed.autoEdit'),
                  _autoSyncing ? () {} : () => _autoEdit(provider),
                  customColor: const Color(0xFFFFB703),
                  highlight: true,
                ),
                // 0. Auto Transcribe Button
                item(
                  Icons.mic_external_on,
                  tr('ed.transcribe'),
                  _autoTranscribe,
                  customColor: AppColors.primary,
                ),
                // 1. Auto Sync Button
              item(
                Icons.auto_fix_high,
                'Auto Sync',
                _autoSyncing ? () {} : () => _aiSync(provider),
                customColor: _autoSyncing ? AppColors.textHint : AppColors.primary,
                customIcon: _autoSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        ),
                      )
                    : null,
              ),
              
              // 2. Auto Emoji Button (emoji + highlight + matching SFX)
              item(
                Icons.auto_awesome,
                tr('ed.autoEmojiBtn'),
                _autoSyncing ? () {} : () => _autoEmoji(provider),
                customColor: const Color(0xFFFFB703),
              ),
              item(Icons.tag, tr('ed.autoHook'),
                  () => _autoHook(provider),
                  customColor: const Color(0xFFFFB703)),

              // 3. Auto-Cut ✂️ Button
              item(
                Icons.cut_rounded,
                'Auto-Cut',
                _autoSyncing ? () {} : () => _toggleAutoCut(provider),
                customColor: project.isAutoCut ? const Color(0xFFE040FB) : AppColors.textSecondary,
                highlight: project.isAutoCut,
              ),

              // 3b. Split the video clip at the playhead (CapCut ✂️). Creates a
              // divider so each clip can be trimmed/deleted directly on the strip.
              item(
                Icons.content_cut_rounded,
                tr('ed.cutClip'),
                () => _splitVideoAtPlayhead(provider),
                customColor: project.removedRanges.isNotEmpty
                    ? const Color(0xFFE040FB)
                    : AppColors.textSecondary,
                highlight: project.removedRanges.isNotEmpty,
              ),

              // 3c. Remove filler words ("um/uh/เออ/อืม/ເອີ") — tightens speech
              // by cutting each filler word's time span (offline, no AI needed).
              item(
                Icons.cleaning_services_rounded,
                tr('ed.removeFiller'),
                () => _autoRemoveFiller(provider),
                customColor: const Color(0xFFFF7043),
              ),

              // 3d. Text-based editing: tap words in the transcript to cut them.
              item(
                Icons.edit_note_rounded,
                tr('ed.textEdit'),
                () => _showTextEditSheet(provider),
                customColor: const Color(0xFF42A5F5),
              ),

              item(Icons.music_note, tr('ed.sfxBtn'),
                  () => _showAddSfxSheet(provider)),
              item(Icons.auto_awesome, tr('ed.autoSfxBtn'),
                  () => _applyAutoSfx(provider),
                  customColor: const Color(0xFFFFB703)),
              item(Icons.tune, tr('ed.mixerBtn'),
                  () => _showAudioMixerSheet(provider)),
              item(Icons.library_music, tr('ed.webSfx'),
                  () => _showWebSfxSheet(provider),
                  customColor: const Color(0xFF00BFA5)),
              item(Icons.image_outlined, tr('ed.image'),
                  () => _pickImageOverlay(provider)),
              item(Icons.emoji_emotions_outlined, tr('ed.sticker'),
                  () => _showStickerSheet(provider),
                  customColor: const Color(0xFFFFCA28)),
              item(Icons.video_library_outlined, tr('ed.broll'),
                  () => _pickVideoOverlay(provider),
                  customColor: const Color(0xFF7C4DFF)),
              item(Icons.ondemand_video, tr('ed.webBroll'),
                  () => _showWebBrollSheet(provider),
                  customColor: const Color(0xFF7C4DFF)),
              item(Icons.image_search, tr('ed.webImage'),
                  () => _showWebImageSheet(provider),
                  customColor: const Color(0xFF00BFA5)),
              item(Icons.auto_awesome_motion, tr('ed.autoVisual'),
                  () => _showAutoVisualSheet(provider),
                  customColor: const Color(0xFF7C4DFF)),
              item(Icons.blur_on_rounded, tr('ed.bgBlur'),
                  () => _toggleBgBlur(provider),
                  customColor: (provider.currentProject?.bgBlur ?? false)
                      ? AppColors.primary
                      : AppColors.textHint),

              // Segment-specific tools (only when a caption exists at playhead).
              if (segments.isNotEmpty && i >= 0 && i < segments.length) ...[
                // Divider line between global AI tools and segment tools
                Container(
                  width: 1,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: AppColors.border,
                ),

                // 4. Split Button
                item(Icons.content_cut, tr('ed.cut'),
                    () => _splitAtPlayhead(provider, i)),

                // 5. Merge Button
                item(Icons.merge, tr('ed.merge'),
                    () => _mergeWithNext(provider, i)),

                // 6. Copy Button
                item(
                  Icons.copy_all_outlined,
                  tr('ed.duplicate'),
                  () => _duplicateSegment(provider, i),
                ),

                // 7. Edit Button
                item(
                  Icons.edit_outlined,
                  tr('ed.edit'),
                  () => _editSegment(segments[i], i, provider),
                ),

                // 8. Style Button
                item(
                  Icons.palette_outlined,
                  tr('ed.tab.style'),
                  () => _showSegmentStyleSheet(segments[i], i, provider),
                  highlight: segments[i].hasStyleOverride,
                ),

                // 9. Delete Button
                item(
                  Icons.delete_outline,
                  tr('ed.delete'),
                  () => _deleteSegment(provider, i),
                  danger: true,
                ),
              ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Builds interactive drag blocks for the SFX track
  
  (Map<String, int>, int) _calculateSfxLanes(List<SfxBlock> blocks) {
    if (blocks.isEmpty) return ({}, 0);
    
    final sortedBlocks = List<SfxBlock>.from(blocks)..sort((a, b) => a.startTime.compareTo(b.startTime));
    final blockLanes = <String, int>{};
    final laneEndTimes = <int>[]; // End time in ms for each lane
    
    for (final block in sortedBlocks) {
      final startMs = block.startTime.inMilliseconds;
      final durMs = block.duration?.inMilliseconds ?? block.type.defaultDuration.inMilliseconds;
      final endMs = startMs + durMs; 
      
      int assignedLane = -1;
      for (int i = 0; i < laneEndTimes.length; i++) {
        // Add a small 50ms buffer between blocks on the same lane
        if (laneEndTimes[i] <= startMs) {
          assignedLane = i;
          laneEndTimes[i] = endMs;
          break;
        }
      }
      
      if (assignedLane == -1) {
        assignedLane = laneEndTimes.length;
        laneEndTimes.add(endMs);
      }
      
      blockLanes[block.id] = assignedLane;
    }
    
    return (blockLanes, laneEndTimes.length);
  }

  /// Stack image/B-roll overlays into separate lanes so overlapping clips don't
  /// sit on top of each other on one row (like CapCut's overlay tracks).
  (Map<String, int>, int) _calculateOverlayLanes(List<ImageOverlay> overlays) {
    if (overlays.isEmpty) return ({}, 0);

    final sorted = List<ImageOverlay>.from(overlays)
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final lanes = <String, int>{};
    final laneEndTimes = <int>[]; // end ms for each lane

    for (final ov in sorted) {
      final startMs = ov.startTime.inMilliseconds;
      final endMs = ov.endTime.inMilliseconds;

      int assignedLane = -1;
      for (int i = 0; i < laneEndTimes.length; i++) {
        if (laneEndTimes[i] <= startMs) {
          assignedLane = i;
          laneEndTimes[i] = endMs;
          break;
        }
      }
      if (assignedLane == -1) {
        assignedLane = laneEndTimes.length;
        laneEndTimes.add(endMs);
      }
      lanes[ov.id] = assignedLane;
    }

    return (lanes, laneEndTimes.length);
  }

  /// AI-voice track bar (spans the clip duration at its offset). Drag to move,
  /// tap to select (shows the AI toolbar), and it opens the mixer via toolbar.
  /// Timeline bars for image overlays (one row, like SFX). Drag to move,
  /// trim handles to change duration, tap to select.
  List<Widget> _buildImageOverlayBars(
    ProjectProvider provider,
    double leftPad,
    int totalMs,
    double top,
    double h, {
    Map<String, int> lanes = const {},
    double laneGap = 4.0,
  }) {
    final project = provider.currentProject;
    if (project == null) return const [];
    return project.imageOverlays.map((ov) {
      final lane = lanes[ov.id] ?? 0;
      final rowTop = top + lane * (h + laneGap);
      final left = (ov.startTime.inMilliseconds / 1000.0) * _pxPerSec + leftPad;
      final w = (((ov.endTime.inMilliseconds - ov.startTime.inMilliseconds) /
                  1000.0) *
              _pxPerSec)
          .clamp(36.0, 100000.0);
      final selected = _selectedImageId == ov.id;

      Widget trimHandle(bool isLeft) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) {
              _pauseForEdit();
              provider.pushHistory();
              _dragIndex = -1;
            },
            onHorizontalDragUpdate: (d) {
              final deltaMs = (d.delta.dx / _pxPerSec * 1000).round();
              setState(() {
                if (isLeft) {
                  final ns = (ov.startTime.inMilliseconds + deltaMs)
                      .clamp(0, ov.endTime.inMilliseconds - 200);
                  ov.startTime = Duration(milliseconds: ns);
                } else {
                  final ne = (ov.endTime.inMilliseconds + deltaMs)
                      .clamp(ov.startTime.inMilliseconds + 200, totalMs);
                  ov.endTime = Duration(milliseconds: ne);
                }
              });
              provider.liveUpdate();
            },
            onHorizontalDragEnd: (_) {
              provider.commit();
              setState(() => _dragIndex = null);
            },
            child: Container(
              width: 14,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.5),
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(isLeft ? 4 : 0),
                  right: Radius.circular(isLeft ? 0 : 4),
                ),
              ),
              child: Icon(isLeft ? Icons.chevron_left : Icons.chevron_right,
                  size: 12, color: Colors.white),
            ),
          );

      return Positioned(
        top: rowTop,
        left: left,
        width: w,
        height: h,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _pauseForEdit();
                _seekIfOutside(ov.startTime, ov.endTime);
                setState(() {
                  _selectedIndex = null;
                  _selectedSfxId = null;
                  _selectedClipIndex = null;
                  _selectedImageId = ov.id;
                });
              },
              onHorizontalDragStart: (_) {
                _pauseForEdit();
                provider.pushHistory();
                _dragIndex = -1;
              },
              onHorizontalDragUpdate: (d) {
                final deltaMs = (d.delta.dx / _pxPerSec * 1000).round();
                final dur = ov.endTime.inMilliseconds - ov.startTime.inMilliseconds;
                final ns = (ov.startTime.inMilliseconds + deltaMs)
                    .clamp(0, totalMs - dur);
                setState(() {
                  ov.startTime = Duration(milliseconds: ns);
                  ov.endTime = Duration(milliseconds: ns + dur);
                });
                provider.liveUpdate();
              },
              onHorizontalDragEnd: (_) {
                provider.commit();
                setState(() => _dragIndex = null);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: (ov.isVideo
                          ? const Color(0xFF7C4DFF)
                          : Colors.tealAccent.shade700)
                      .withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: selected ? Colors.white : Colors.white24,
                    width: selected ? 2.0 : 1.0,
                  ),
                ),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(ov.isVideo ? Icons.movie : Icons.image,
                        size: 11, color: Colors.white),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(tr(ov.isVideo ? 'ed.broll' : 'ed.image'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ],
                ),
              ),
            ),
            if (selected) ...[
              Positioned(left: 0, top: 0, bottom: 0, child: trimHandle(true)),
              Positioned(right: 0, top: 0, bottom: 0, child: trimHandle(false)),
            ],
            // Keyframe markers (◆) — tap to jump, long-press to delete.
            for (final kf in ov.keyframes)
              Positioned(
                left: ((kf.timeMs - ov.startTime.inMilliseconds) / 1000.0) *
                        _pxPerSec -
                    9,
                top: h / 2 - 9,
                width: 18,
                height: 18,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _seekTo(Duration(milliseconds: kf.timeMs));
                    _scrollTimelineToPosition();
                  },
                  onLongPress: () {
                    provider.pushHistory();
                    ov.keyframes.remove(kf);
                    provider.commit();
                    setState(() {});
                    _toast(tr('ed.kfDeleted'));
                  },
                  child: Center(
                    child: Transform.rotate(
                      angle: 0.7853981634,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color:
                              ((kf.timeMs - _position.inMilliseconds).abs() <= 120)
                                  ? Colors.redAccent
                                  : const Color(0xFFFFB703),
                          border: Border.all(color: Colors.white, width: 1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildAiVoiceTrackBar(
    ProjectProvider provider,
    double leftPad,
    int totalMs,
    double aiTop,
    double aiH,
  ) {
    final project = provider.currentProject!;
    final fullMs = project.aiVoiceDurationMs ?? 0;
    final trimStart = project.aiVoiceTrimStartMs;
    final trimEnd = project.aiVoiceTrimEndMs ?? fullMs;
    final visibleMs = (trimEnd - trimStart).clamp(0, fullMs);
    final w = ((visibleMs / 1000.0) * _pxPerSec).clamp(40.0, double.infinity);
    final offsetLeft = leftPad + (project.aiVoiceOffsetMs / 1000.0) * _pxPerSec;
    final muted = project.aiVoiceMuted;
    final selected = _selectedSfxId == 'ai_voice';

    Widget trimHandle(bool isLeft) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) {
            _pauseForEdit();
            provider.pushHistory();
            _dragIndex = -1;
          },
          onHorizontalDragUpdate: (d) {
            final deltaMs = (d.delta.dx / _pxPerSec * 1000).round();
            final curTrim = project.aiVoiceTrimStartMs;
            final curEnd = project.aiVoiceTrimEndMs ?? fullMs;
            if (isLeft) {
              // Move in-point: keep visible ≥100ms, trim ≥0, shift offset.
              final maxDelta = (curEnd - curTrim) - 100;
              final dd = deltaMs.clamp(-curTrim, maxDelta);
              project.aiVoiceTrimStartMs = curTrim + dd;
              project.aiVoiceOffsetMs =
                  (project.aiVoiceOffsetMs + dd).clamp(0, totalMs);
            } else {
              // Move out-point: clamp between in+100ms and full length.
              project.aiVoiceTrimEndMs =
                  (curEnd + deltaMs).clamp(curTrim + 100, fullMs);
            }
            provider.liveUpdate();
            setState(() {});
          },
          onHorizontalDragEnd: (_) {
            provider.commit();
            setState(() => _dragIndex = null);
          },
          child: Container(
            width: 14,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.45),
              borderRadius: BorderRadius.horizontal(
                left: Radius.circular(isLeft ? 4 : 0),
                right: Radius.circular(isLeft ? 0 : 4),
              ),
            ),
            child: Icon(isLeft ? Icons.chevron_left : Icons.chevron_right,
                size: 12, color: Colors.white),
          ),
        );

    return Positioned(
      top: aiTop,
      left: offsetLeft,
      width: w,
      height: aiH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _pauseForEdit();
              // Seek to head ONLY if the playhead is outside the AI track span.
              final aiStart = Duration(milliseconds: project.aiVoiceOffsetMs);
              final aiEnd = aiStart + Duration(milliseconds: visibleMs);
              _seekIfOutside(aiStart, aiEnd);
              setState(() {
                _selectedIndex = null;
                _selectedSfxId = 'ai_voice';
                _selectedClipIndex = null;
                _selectedImageId = null;
              });
            },
            onHorizontalDragStart: (_) {
              _pauseForEdit();
              provider.pushHistory();
              _dragIndex = -1; // suppress timeline scroll while dragging
            },
            onHorizontalDragUpdate: (d) {
              final deltaMs = (d.delta.dx / _pxPerSec * 1000).round();
              project.aiVoiceOffsetMs =
                  (project.aiVoiceOffsetMs + deltaMs).clamp(0, totalMs);
              provider.liveUpdate();
              setState(() {});
            },
            onHorizontalDragEnd: (_) {
              provider.commit();
              setState(() => _dragIndex = null);
            },
            child: Container(
              decoration: BoxDecoration(
                color: (muted ? Colors.grey : Colors.deepPurpleAccent)
                    .withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: selected ? Colors.white : Colors.white24,
                  width: selected ? 2.0 : 1.0,
                ),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(muted ? Icons.volume_off : Icons.record_voice_over,
                      size: 11, color: Colors.white),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(tr('ed.aiVoice'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ],
              ),
            ),
          ),
          if (selected) ...[
            Positioned(left: 0, top: 0, bottom: 0, child: trimHandle(true)),
            Positioned(right: 0, top: 0, bottom: 0, child: trimHandle(false)),
          ],
        ],
      ),
    );
  }

  void _showAiTrackAddedDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(tr('ed.aiTrackAdded'),
            style: const TextStyle(color: Colors.white)),
        content: Text(
          tr('ed.aiTrackInfo'),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child:
                Text(tr('ed.ok'), style: const TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _removeAiVoiceTrack(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null) return;
    provider.pushHistory();
    final old = project.aiVoicePath;
    project.aiVoicePath = null;
    project.aiVoiceDurationMs = null;
    provider.commit();
    try { if (old != null) File(old).deleteSync(); } catch (_) {}
    _aiVoicePlayer?.stop();
    _aiVoiceLoadedPath = null;
    if (mounted) setState(() => _selectedSfxId = null);
    _toast(tr('ed.aiTrackRemoved'));
  }

  /// 3-track audio mixer: original (video) / AI voice / SFX.
  /// Each row has a mute toggle + a volume slider; changes apply live + persist.
  void _showAudioMixerSheet(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null) return;

    void persistDebounced() {
      _mixerSaveDebounce?.cancel();
      _mixerSaveDebounce =
          Timer(const Duration(milliseconds: 400), () => provider.commit());
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Widget trackRow({
              required String emoji,
              required String label,
              required bool muted,
              required double volume,
              required bool enabled,
              required VoidCallback onToggleMute,
              required ValueChanged<double> onVolume,
            }) {
              return Opacity(
                opacity: enabled ? 1.0 : 0.4,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: enabled ? onToggleMute : null,
                      icon: Icon(muted ? Icons.volume_off : Icons.volume_up,
                          color: muted ? Colors.redAccent : AppColors.primary),
                    ),
                    SizedBox(
                      width: 92,
                      child: Text('$emoji $label',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ),
                    Expanded(
                      child: Slider(
                        value: volume.clamp(0.0, 1.0),
                        min: 0.0,
                        max: 1.0,
                        activeColor: AppColors.primary,
                        inactiveColor: AppColors.border,
                        onChanged: enabled && !muted ? onVolume : null,
                      ),
                    ),
                    SizedBox(
                      width: 38,
                      child: Text('${(volume * 100).round()}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 11)),
                    ),
                  ],
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 8),
                      child: Text(tr('ed.mixer'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ),
                    trackRow(
                      emoji: '🎬',
                      label: tr('ed.mainAudio'),
                      muted: project.originalMuted,
                      volume: project.originalVolume,
                      enabled: true,
                      onToggleMute: () {
                        setSheet(() =>
                            project.originalMuted = !project.originalMuted);
                        _applyTrackVolumes();
                        persistDebounced();
                      },
                      onVolume: (v) {
                        setSheet(() => project.originalVolume = v);
                        _applyTrackVolumes();
                        persistDebounced();
                      },
                    ),
                    trackRow(
                      emoji: '🎤',
                      label: tr('ed.aiVoice'),
                      muted: project.aiVoiceMuted,
                      volume: project.aiVoiceVolume,
                      enabled: project.aiVoicePath != null,
                      onToggleMute: () {
                        setSheet(
                            () => project.aiVoiceMuted = !project.aiVoiceMuted);
                        _applyTrackVolumes();
                        if (project.aiVoiceMuted) {
                          _aiVoicePlayer?.pause();
                        } else if (_isPlaying) {
                          _resumeAiVoice();
                        }
                        persistDebounced();
                      },
                      onVolume: (v) {
                        setSheet(() => project.aiVoiceVolume = v);
                        _applyTrackVolumes();
                        persistDebounced();
                      },
                    ),
                    trackRow(
                      emoji: '💥',
                      label: 'SFX',
                      muted: project.sfxMuted,
                      volume: project.sfxVolume,
                      enabled: project.sfxBlocks.isNotEmpty,
                      onToggleMute: () {
                        setSheet(() => project.sfxMuted = !project.sfxMuted);
                        persistDebounced();
                      },
                      onVolume: (v) {
                        setSheet(() => project.sfxVolume = v);
                        persistDebounced();
                      },
                    ),
                    trackRow(
                      emoji: '🎵',
                      label: tr('ed.bgMusic'),
                      muted: project.bgMusicMuted,
                      volume: project.bgMusicVolume,
                      enabled: project.bgMusicPath != null,
                      onToggleMute: () {
                        setSheet(() =>
                            project.bgMusicMuted = !project.bgMusicMuted);
                        _applyTrackVolumes();
                        if (project.bgMusicMuted) {
                          _bgMusicPlayer?.pause();
                        } else if (_isPlaying) {
                          _resumeBgMusic();
                        }
                        persistDebounced();
                      },
                      onVolume: (v) {
                        setSheet(() => project.bgMusicVolume = v);
                        _applyTrackVolumes();
                        persistDebounced();
                      },
                    ),
                    // Auto-duck toggle (only when music is loaded).
                    if (project.bgMusicPath != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Row(children: [
                          const Text('🎚️ ', style: TextStyle(fontSize: 13)),
                          Expanded(
                            child: Text(tr('ed.autoDuck'),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                          ),
                          Switch(
                            value: project.bgMusicDuck,
                            activeColor: AppColors.primary,
                            onChanged: (v) {
                              setSheet(() => project.bgMusicDuck = v);
                              persistDebounced();
                            },
                          ),
                        ]),
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          if (project.bgMusicPath == null) {
                            _pickBgMusic(provider);
                          } else {
                            _removeBgMusic(provider);
                          }
                        },
                        icon: Icon(
                            project.bgMusicPath == null
                                ? Icons.library_music
                                : Icons.delete_outline,
                            size: 16,
                            color: project.bgMusicPath == null
                                ? AppColors.primary
                                : Colors.redAccent),
                        label: Text(
                            project.bgMusicPath == null
                                ? tr('ed.addBgMusic')
                                : tr('ed.removeBgMusic'),
                            style: TextStyle(
                                color: project.bgMusicPath == null
                                    ? AppColors.primary
                                    : Colors.redAccent,
                                fontSize: 12)),
                      ),
                    ),
                    if (project.aiVoicePath != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _removeAiVoiceTrack(provider);
                          },
                          icon: const Icon(Icons.delete_outline,
                              size: 16, color: Colors.redAccent),
                          label: Text(tr('ed.removeAiTrackLabel'),
                              style: const TextStyle(
                                  color: Colors.redAccent, fontSize: 12)),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _buildInteractiveSfxBlocks(
    List<SfxBlock> blocks,
    Map<String, int> blockLanes,
    ProjectProvider provider,
    double leftPad,
    int totalMs,
    double sfxTop,
    double sfxH,
  ) {
    return blocks.map((block) {
      final left = (block.startTime.inMilliseconds / 1000.0) * _pxPerSec + leftPad;
      double dur = block.duration?.inMilliseconds != null ? block.duration!.inMilliseconds / 1000.0 : block.type.defaultDuration.inMilliseconds / 1000.0;
      // Custom audio shows the file name; built-in SFX shows the type name.
      String label = block.isCustom
          ? (block.customName ?? 'AUDIO')
          : block.type.name.toUpperCase();
      Color color = block.isCustom ? Colors.tealAccent.shade700 : AppColors.primary;

      final w = (dur * _pxPerSec).clamp(48.0, 1500.0);

      final isSelected = _selectedSfxId == block.id;
      final laneIndex = blockLanes.containsKey(block.id) ? blockLanes[block.id]! : 0;

      // Full source length (cap for the right trim handle). Custom audio uses its
      // decoded duration + any prior trim; built-in SFX uses the asset length.
      final fullLenMs = block.isCustom
          ? ((block.duration?.inMilliseconds ?? 1000) +
              (block.trimStart?.inMilliseconds ?? 0))
          : block.type.defaultDuration.inMilliseconds;

      // Trim handle: left resizes trimStart+start+duration, right resizes duration.
      Widget trimHandle(bool isLeft) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) {
              _pauseForEdit();
              provider.pushHistory();
              _dragIndex = -1; // suppress timeline scroll while trimming
            },
            onHorizontalDragUpdate: (d) {
              final deltaMs = (d.delta.dx / _pxPerSec * 1000).round();
              final curDur = block.duration?.inMilliseconds ?? fullLenMs;
              final curTrim = block.trimStart?.inMilliseconds ?? 0;
              if (isLeft) {
                // Move the in-point: clamp so duration stays ≥100ms and trim ≥0.
                final maxDelta = curDur - 100;
                final dd = deltaMs.clamp(-curTrim, maxDelta);
                block.trimStart = Duration(milliseconds: curTrim + dd);
                block.startTime = Duration(
                    milliseconds:
                        (block.startTime.inMilliseconds + dd).clamp(0, totalMs));
                block.duration = Duration(milliseconds: curDur - dd);
              } else {
                // Resize the out-point: clamp ≥100ms and ≤ remaining source.
                final maxDur = fullLenMs - curTrim;
                block.duration = Duration(
                    milliseconds: (curDur + deltaMs).clamp(100, maxDur));
              }
              provider.liveUpdate();
              setState(() {});
            },
            onHorizontalDragEnd: (_) {
              provider.commit();
              setState(() => _dragIndex = null);
            },
            child: Container(
              width: 14,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.45),
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(isLeft ? 4 : 0),
                  right: Radius.circular(isLeft ? 0 : 4),
                ),
              ),
              child: Icon(isLeft ? Icons.chevron_left : Icons.chevron_right,
                  size: 12, color: Colors.white),
            ),
          );

      return Positioned(
        top: sfxTop + laneIndex * (sfxH + 4.0),
        left: left,
        width: w,
        height: sfxH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Body: tap to select, drag to move.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _pauseForEdit();
                // Seek to head ONLY if the playhead is outside this block.
                final blockEnd = block.startTime +
                    Duration(milliseconds: (dur * 1000).round());
                _seekIfOutside(block.startTime, blockEnd);
                setState(() {
                  _selectedIndex = null; // deselect subtitle
                  _selectedSfxId = block.id;
                  _selectedClipIndex = null;
                  _selectedImageId = null;
                });
              },
              onHorizontalDragStart: (_) {
                _pauseForEdit();
                provider.pushHistory();
                _dragIndex = -1; // arbitrary non-null to disable scroll
              },
              onHorizontalDragUpdate: (d) {
                final deltaMs = (d.delta.dx / _pxPerSec * 1000).round();
                block.startTime = Duration(
                  milliseconds: (block.startTime.inMilliseconds + deltaMs)
                      .clamp(0, totalMs),
                );
                provider.liveUpdate();
                setState(() {});
              },
              onHorizontalDragEnd: (_) {
                provider.commit();
                setState(() => _dragIndex = null);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: 0.8)
                      : color.withValues(alpha: 0.4),
                  border: Border.all(
                    color: isSelected ? Colors.white : color,
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Icon(block.volume < 1.0 ? Icons.volume_down : Icons.music_note,
                        color: Colors.white, size: 12),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        overflow: TextOverflow.clip,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Trim handles (only when selected).
            if (isSelected) ...[
              Positioned(left: 0, top: 0, bottom: 0, child: trimHandle(true)),
              Positioned(right: 0, top: 0, bottom: 0, child: trimHandle(false)),
            ],
          ],
        ),
      );
    }).toList();
  }

  /// Bottom tools shown when a clip block on the timeline is selected:
  /// reorder (move left/right), split at playhead, delete.
  Widget _buildClipToolbar(ProjectProvider provider) {
    final project = provider.currentProject;
    if (_mcSelected < 0 || project == null || project.clips.length < 2) {
      return const SizedBox.shrink();
    }
    Widget btn(IconData icon, String label, VoidCallback onTap,
        {bool danger = false}) {
      final col = danger ? AppColors.accent : AppColors.textSecondary;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: col),
              const SizedBox(height: 4),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: col, fontSize: 10, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF7C4DFF)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          btn(Icons.chevron_left, tr('ed.clipMoveLeft'),
              () => _mcMove(provider, -1)),
          btn(Icons.chevron_right, tr('ed.clipMoveRight'),
              () => _mcMove(provider, 1)),
          btn(Icons.content_cut_rounded, tr('ed.split'),
              () => _mcSplit(provider)),
          btn(Icons.delete_outline, tr('ed.delete'),
              () => _deleteClip(provider, _mcSelected), danger: true),
        ],
      ),
    );
  }

Widget _buildTimelineTab() {
    return Consumer<ProjectProvider>(
      builder: (context, provider, _) {
        final project = provider.currentProject;
        final segments = project?.segments ?? [];
        // The timeline shows the video filmstrip + clip track even when there
        // are no subtitles yet (so clips can be cut/trimmed in Edit-Clip mode).
        if (project == null || project.videoPath == null) {
          return Center(
            child: Text(
              tr('ed.noSubtitle'),
              style: const TextStyle(color: AppColors.textHint),
            ),
          );
        }
        final totalMs = _duration.inMilliseconds > 0
            ? _duration.inMilliseconds
            : (segments.isNotEmpty
                ? segments.last.endTime.inMilliseconds + 2000
                : 10000);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 5, 12, 3),
              child: Row(
                children: [
                  const Text(
                    'Timeline 🎬',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  // Ripple toggle: ON = dragging a block moves all blocks after
                  // it too (fix a drift point, carry the rest); OFF = move one.
                  _miniIcon(_rippleMode ? Icons.link : Icons.link_off, () {
                    setState(() => _rippleMode = !_rippleMode);
                    _toast(
                      _rippleMode
                          ? tr('ed.rippleMode')
                          : tr('ed.singleMode'),
                    );
                  }, filled: _rippleMode),
                  const SizedBox(width: 4),
                  _miniIcon(Icons.zoom_out, () => _zoomTimeline(0.7)),
                  const SizedBox(width: 4),
                  _miniIcon(Icons.zoom_in, () => _zoomTimeline(1.4)),
                  const SizedBox(width: 4),
                  // SFX / Auto-SFX / Mixer / Image moved to the bottom toolbar.
                  _miniIcon(
                    Icons.add,
                    () => _addAtPlayhead(provider),
                    filled: true,
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final vw = constraints.maxWidth;
                  final leftPad = vw / 2; // so time 0..end can reach centre
                  final contentW = vw + (totalMs / 1000.0) * _pxPerSec;
                  // ── CapCut-style: slim tracks packed at the top (compact) ──
                  const rulerH = 14.0;
                  const gap = 4.0;
                  final hasFilm = _thumbs.isNotEmpty;
                  const filmH = 44.0; // slim video filmstrip
                  const waveH = 26.0; // slim audio track
                  const capH = 38.0; // slim caption-block track
                  const sfxH = 38.0; // matched height with caption-block track
                  final filmTop = rulerH + gap;
                  final waveTop = filmTop + (hasFilm ? filmH + gap : 0);
                  final capTop = waveTop + waveH + gap;
                  final blockTop = capTop;
                  final blockH = capH;
                  final sfxTop = blockTop + blockH + gap;
                  final laneResult = _calculateSfxLanes(project.sfxBlocks);
                  final blockLanes = laneResult.$1;
                  final numLanes = laneResult.$2;
                  final aiTop = sfxTop + math.max(1, numLanes) * (sfxH + gap);
                  final hasAiTrack = project.aiVoicePath != null;
                  final imgTop = aiTop + (hasAiTrack ? sfxH + gap : 0);
                  final hasImages = project.imageOverlays.isNotEmpty;
                  final ovLaneResult =
                      _calculateOverlayLanes(project.imageOverlays);
                  final overlayLanes = ovLaneResult.$1;
                  final numOverlayLanes = math.max(1, ovLaneResult.$2);
                  // Total height of the (multi-lane) overlay track.
                  final imgTrackH =
                      numOverlayLanes * sfxH + (numOverlayLanes - 1) * gap;
                  final totalDynamicHeight =
                      (hasImages ? imgTop + imgTrackH : aiTop + sfxH) + 40.0;
                  return Listener(
                    onPointerDown: (e) {
                      _ptrs[e.pointer] = e.position;
                      if (_ptrs.length == 2) {
                        final p = _ptrs.values.toList();
                        _pinchStartDist = (p[0] - p[1]).distance;
                        _pinchStartPx = _pxPerSec;
                        setState(() => _pinching = true);
                      }
                    },
                    onPointerMove: (e) {
                      if (_ptrs.containsKey(e.pointer)) {
                        _ptrs[e.pointer] = e.position;
                      }
                      if (_pinching &&
                          _ptrs.length >= 2 &&
                          _pinchStartDist > 1) {
                        final p = _ptrs.values.toList();
                        final dist = (p[0] - p[1]).distance;
                        setState(
                          () => _pxPerSec =
                              (_pinchStartPx * dist / _pinchStartDist).clamp(
                                40.0,
                                400.0,
                              ),
                        );
                        // Anchor the zoom to the playhead so the timeline doesn't
                        // slide sideways while pinching (keeps the red line fixed).
                        _scrollTimelineToPosition();
                      }
                    },
                    onPointerUp: (e) => _endPtr(e.pointer),
                    onPointerCancel: (e) => _endPtr(e.pointer),
                    child: Stack(
                      children: [
                        NotificationListener<ScrollStartNotification>(
                          onNotification: (n) {
                            // User started scrubbing → stop playback immediately.
                            if (n.dragDetails != null) _pauseForEdit();
                            return false;
                          },
                          child: SingleChildScrollView(
                            controller: _timelineScroll,
                            scrollDirection: Axis.horizontal,
                            physics: _pinching
                                ? const NeverScrollableScrollPhysics()
                                : null,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SizedBox(
                                width: contentW,
                                height: math.max(constraints.maxHeight, totalDynamicHeight),
                                child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      // onTapUp (not onTapDown) so a tap that lands
                                      // on a keyframe diamond / block on top wins
                                      // the gesture arena and this doesn't clear
                                      // the selection or hijack the seek.
                                      onTapUp: (d) {
                                        _pauseForEdit();
                                        final ms =
                                            ((d.localPosition.dx - leftPad) /
                                                    _pxPerSec *
                                                    1000)
                                                .round()
                                                .clamp(0, totalMs);
                                        _seekTo(Duration(milliseconds: ms));
                                        _scrollTimelineToPosition();
                                        // Multi-clip: tapping the timeline selects
                                        // the clip block under the tap (robust —
                                        // no reliance on the block's own gesture).
                                        if (project.clips.length >= 2) {
                                          final bounds = _clipBounds(project);
                                          int idx = bounds.indexWhere((b) =>
                                              ms >= b.start && ms < b.end);
                                          if (idx < 0 && bounds.isNotEmpty) {
                                            idx = bounds.length - 1;
                                          }
                                          setState(() {
                                            _mcSelected = idx;
                                            _selectedIndex = null;
                                            _selectedSfxId = null;
                                            _selectedClipIndex = null;
                                            _selectedImageId = null;
                                          });
                                          return;
                                        }
                                        if (_selectedIndex != null ||
                                            _selectedSfxId != null ||
                                            _selectedClipIndex != null ||
                                            _selectedImageId != null) {
                                          setState(() {
                                            _selectedIndex = null;
                                            _selectedSfxId = null;
                                            _selectedClipIndex = null;
                                            _selectedImageId = null;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  // Ruler (time marks) — top track
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    height: rulerH,
                                    child: CustomPaint(
                                      painter: _RulerPainter(
                                        totalMs: totalMs,
                                        pxPerSec: _pxPerSec,
                                        leftPad: leftPad,
                                      ),
                                    ),
                                  ),
                                  // Filmstrip track (video frames)
                                  if (hasFilm)
                                    _buildFilmstrip(leftPad, filmTop, filmH),
                                  // Waveform track (audio)
                                  if (_waveform.isNotEmpty)
                                    Positioned(
                                      top: waveTop,
                                      left: 0,
                                      right: 0,
                                      height: waveH,
                                      child: CustomPaint(
                                        painter: _WaveformPainter(
                                          samples: _waveform,
                                          stepMs:
                                              AudioSyncService.waveformStepMs,
                                          pxPerSec: _pxPerSec,
                                          leftPad: leftPad,
                                        ),
                                      ),
                                    ),
                                  // Onset markers across the caption track
                                  if (_timelineOnsets.isNotEmpty)
                                    Positioned(
                                      top: capTop,
                                      left: 0,
                                      right: 0,
                                      height: capH,
                                      child: CustomPaint(
                                        painter: _OnsetPainter(
                                          onsets: _timelineOnsets,
                                          pxPerSec: _pxPerSec,
                                          leftPad: leftPad,
                                        ),
                                      ),
                                    ),
                                  ...segments.asMap().entries.map(
                                    (e) => _timelineBlock(
                                      e.key,
                                      e.value,
                                      provider,
                                      leftPad,
                                      totalMs,
                                      project.fontFamily,
                                      blockTop,
                                      blockH,
                                    ),
                                  ),
                                  if (project.sfxBlocks.isNotEmpty)
                                    ..._buildInteractiveSfxBlocks(project.sfxBlocks, blockLanes, provider, leftPad, totalMs, sfxTop, sfxH),
                                  if (project.aiVoicePath != null)
                                    _buildAiVoiceTrackBar(provider, leftPad, totalMs, aiTop, sfxH),
                                  ..._buildImageOverlayBars(provider, leftPad, totalMs, imgTop, sfxH, lanes: overlayLanes, laneGap: gap),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Fixed centre playhead (CapCut style) — timeline scrolls under it.
                        Positioned(
                          top: 0,
                          bottom: 0,
                          left: vw / 2 - 1,
                          width: 2,
                          child: IgnorePointer(
                            child: Container(color: AppColors.accent),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // (play controls moved onto the preview overlay)
            // Contextual action toolbar at the bottom (CapCut style)
            _buildSegToolbar(provider, segments),
          ],
        );
      },
    );
  }
}
