part of '../editor_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Video effects: blur, auto-cut, zoom/keyframes, shake, fade.
/// Split out of editor_screen.dart verbatim (phase 0) — the
/// fields and lifecycle stay in [_EditorScreenState].
extension _EditorEffects on _EditorScreenState {
  void _toggleBgBlur(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null) return;
    _pauseForEdit();
    provider.pushHistory();
    project.bgBlur = !project.bgBlur;
    provider.commit();
    setState(() {});
    _toast(project.bgBlur ? tr('ed.bgBlurOn') : tr('ed.bgBlurOff'));
  }

  Future<void> _toggleAutoCut(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null) return;

    if (project.isAutoCut) {
      project.isAutoCut = false;
      provider.updateProject(project);
      _toast(tr('ed.autoCutOff'));
      setState(() {});
      return;
    }
    // Turning ON → let the user choose how aggressively to cut silence.
    _showAutoCutSheet(provider);
  }

  /// Sensitivity picker for Auto-Cut. gap = the minimum silence (ms) that gets
  /// cut: bigger = gentler (keeps natural pauses), smaller = tighter.
  void _showAutoCutSheet(ProjectProvider provider) {
    _pauseForEdit();
    Future<void> apply(int gap) async {
      Navigator.pop(context);
      final project = provider.currentProject;
      if (project == null || project.videoPath == null) return;
      setState(() => _analyzingAudio = true);
      try {
        final flatList = await ExportService.detectSpeechRegions(project.videoPath!);
        final durMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 10000;
        _keptRegions = computeKeptRegions(flatList, durMs, mergeGapMs: gap);
      } catch (e) {
        _toast(tr('ed.analyzeFail', {'e': e.toString()}));
      } finally {
        setState(() => _analyzingAudio = false);
      }
      if (_keptRegions.isNotEmpty) {
        project.autoCutGapMs = gap;
        project.isAutoCut = true;
        provider.updateProject(project);
        _toast(tr('ed.autoCutOn'));
        setState(() {});
      } else {
        _toast(tr('ed.noSpeech'));
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        Widget opt(IconData ic, String label, String sub, int gap) => ListTile(
              leading: Icon(ic, color: const Color(0xFFE040FB)),
              title: Text(label,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              subtitle: Text(sub,
                  style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
              onTap: () => apply(gap),
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Text(tr('ed.autoCutLevel'),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            opt(Icons.spa_outlined, tr('ed.cutGentle'), tr('ed.cutGentleSub'), 700),
            opt(Icons.tune, tr('ed.cutMedium'), tr('ed.cutMediumSub'), 300),
            opt(Icons.cut, tr('ed.cutTight'), tr('ed.cutTightSub'), 150),
            const SizedBox(height: 12),
          ]),
        );
      },
    );
  }

  // ── Manual video cut ──────────────────────────────────────────────────────

  /// Merge overlapping/adjacent removed ranges and sort them.
  List<List<int>> _normalizeRanges(List<List<int>> ranges) {
    if (ranges.isEmpty) return [];
    final sorted = [...ranges]..sort((a, b) => a[0].compareTo(b[0]));
    final out = <List<int>>[sorted.first];
    for (final r in sorted.skip(1)) {
      final last = out.last;
      if (r[0] <= last[1] + 50) {
        last[1] = r[1] > last[1] ? r[1] : last[1];
      } else {
        out.add(r);
      }
    }
    return out;
  }

  /// Easing curve applied to a keyframe interval. 0 linear, 1 in, 2 out,
  /// 3 in-out, 4 cubic-in, 5 cubic-out. Mirrors the native ease().
  double _ease(int mode, double t) {
    switch (mode) {
      case 1:
        return t * t;
      case 2:
        return 1 - (1 - t) * (1 - t);
      case 3:
        if (t < 0.5) return 2 * t * t;
        final u = -2 * t + 2;
        return 1 - (u * u) / 2;
      case 4:
        return t * t * t;
      case 5:
        final u = 1 - t;
        return 1 - u * u * u;
      default:
        return t;
    }
  }

  /// Live zoom scale + focal point at [ms] for the PREVIEW (mirrors native).
  /// Returns (scale, focusX, focusY); scale 1.0 = no zoom.
  (double, double, double) _zoomAt(int ms) {
    final zs = context.read<ProjectProvider>().currentProject?.zoomEffects;
    if (zs == null) return (1.0, 0.5, 0.5);
    for (final z in zs) {
      final s0 = z.startTime.inMilliseconds, e0 = z.endTime.inMilliseconds;
      if (ms < s0 || ms > e0) continue;
      if (z.keyframes.isNotEmpty) {
        final kfs = z.keyframes;
        if (ms <= kfs.first.timeMs) {
          return (kfs.first.scale, kfs.first.focusX, kfs.first.focusY);
        }
        if (ms >= kfs.last.timeMs) {
          return (kfs.last.scale, kfs.last.focusX, kfs.last.focusY);
        }
        int i = 0;
        while (i < kfs.length - 1 && kfs[i + 1].timeMs < ms) {
          i++;
        }
        final a = kfs[i], b = kfs[i + 1];
        final span = (b.timeMs - a.timeMs).clamp(1, 1 << 31);
        final t = _ease(a.easing, ((ms - a.timeMs) / span).clamp(0.0, 1.0));
        return (
          a.scale + (b.scale - a.scale) * t,
          a.focusX + (b.focusX - a.focusX) * t,
          a.focusY + (b.focusY - a.focusY) * t,
        );
      }
      final dur = (e0 - s0).clamp(1, 1 << 31);
      final t = ((ms - s0) / dur).clamp(0.0, 1.0);
      final s = z.fromScale + (z.toScale - z.fromScale) * t;
      return (s < 1.0 ? 1.0 : s, z.focusX, z.focusY);
    }
    return (1.0, 0.5, 0.5);
  }

  /// Interpolated overlay transform + opacity at [ms] (keyframes → animate;
  /// none → static values).
  ({double x, double y, double scale, double rotation, double opacity})
      _overlayStateAt(ImageOverlay ov, int ms) {
    final kfs = ov.keyframes;
    if (kfs.isEmpty) {
      return (x: ov.x, y: ov.y, scale: ov.scale, rotation: ov.rotation, opacity: ov.opacity);
    }
    if (ms <= kfs.first.timeMs) {
      final k = kfs.first;
      return (x: k.x, y: k.y, scale: k.scale, rotation: k.rotation, opacity: k.opacity);
    }
    if (ms >= kfs.last.timeMs) {
      final k = kfs.last;
      return (x: k.x, y: k.y, scale: k.scale, rotation: k.rotation, opacity: k.opacity);
    }
    int i = 0;
    while (i < kfs.length - 1 && kfs[i + 1].timeMs < ms) {
      i++;
    }
    final a = kfs[i], b = kfs[i + 1];
    final span = (b.timeMs - a.timeMs).clamp(1, 1 << 31);
    final t = _ease(a.easing, ((ms - a.timeMs) / span).clamp(0.0, 1.0));
    double l(double p, double q) => p + (q - p) * t;
    return (
      x: l(a.x, b.x),
      y: l(a.y, b.y),
      scale: l(a.scale, b.scale),
      rotation: l(a.rotation, b.rotation),
      opacity: l(a.opacity, b.opacity),
    );
  }

  /// Find an overlay keyframe near the playhead (within [tolMs]), else create one
  /// seeded with the current interpolated state, and return it.
  OverlayKeyframe _overlayKeyframeAtPlayhead(ImageOverlay ov, {int tolMs = 90}) {
    final ms = _position.inMilliseconds
        .clamp(ov.startTime.inMilliseconds, ov.endTime.inMilliseconds);
    for (final k in ov.keyframes) {
      if ((k.timeMs - ms).abs() <= tolMs) return k;
    }
    final s = _overlayStateAt(ov, ms);
    final kf = OverlayKeyframe(
        timeMs: ms,
        x: s.x,
        y: s.y,
        scale: s.scale,
        rotation: s.rotation,
        opacity: s.opacity);
    ov.keyframes.add(kf);
    ov.keyframes.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return kf;
  }

  /// Get the zoom effect overlapping the selected clip, creating an empty-keyframe
  /// one spanning the clip if none exists. Returns null if no clip is selected.
  ZoomEffect? _ensureZoomForSelectedClip(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null || _selectedClipIndex == null) return null;
    final clips = _videoClips(project);
    if (_selectedClipIndex! >= clips.length) return null;
    final clip = clips[_selectedClipIndex!];
    for (final e in project.zoomEffects) {
      if (clip.start < e.endTime.inMilliseconds &&
          e.startTime.inMilliseconds < clip.end) {
        return e;
      }
    }
    final z = ZoomEffect(
      id: const Uuid().v4(),
      startTime: Duration(milliseconds: clip.start),
      endTime: Duration(milliseconds: clip.end),
      fromScale: 1.0,
      toScale: 1.0, // start with NO zoom (the default 1.3 caused a slight zoom-in)
      keyframes: [],
    );
    project.zoomEffects.add(z); // direct (history handled by caller)
    return z;
  }

  /// Find a keyframe within [tolMs] of the playhead, else create one seeded with
  /// the current interpolated state, and return it.
  ZoomKeyframe _keyframeAtPlayhead(ZoomEffect z, {int tolMs = 90}) {
    final ms = _position.inMilliseconds
        .clamp(z.startTime.inMilliseconds, z.endTime.inMilliseconds);
    for (final k in z.keyframes) {
      if ((k.timeMs - ms).abs() <= tolMs) return k;
    }
    final base = _zoomAt(ms);
    final kf = ZoomKeyframe(
        timeMs: ms, scale: base.$1, focusX: base.$2, focusY: base.$3);
    z.keyframes.add(kf);
    z.keyframes.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return kf;
  }

  /// Apply zoom (Ken-Burns) to the selected video clip's time range.
  void _showZoomSheet(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null || _selectedClipIndex == null) return;
    final clips = _videoClips(project);
    if (_selectedClipIndex! >= clips.length) return;
    final clip = clips[_selectedClipIndex!];
    _pauseForEdit();

    void apply(double from, double to) {
      provider.addZoomEffect(ZoomEffect(
        id: const Uuid().v4(),
        startTime: Duration(milliseconds: clip.start),
        endTime: Duration(milliseconds: clip.end),
        fromScale: from,
        toScale: to,
      ));
      if (mounted) {
        Navigator.pop(context);
        setState(() {});
        _toast(tr('ed.zoomAdded'));
      }
    }

    void removeZoom() {
      final hit = project.zoomEffects.where((z) =>
          clip.start < z.endTime.inMilliseconds &&
          z.startTime.inMilliseconds < clip.end);
      for (final z in hit.toList()) {
        provider.removeZoomEffect(z.id);
      }
      if (mounted) {
        Navigator.pop(context);
        setState(() {});
        _toast(tr('ed.zoomRemoved'));
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        Widget opt(IconData ic, String label, String sub, VoidCallback onTap,
            {Color color = AppColors.primary}) {
          return ListTile(
            leading: Icon(ic, color: color),
            title: Text(label,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            subtitle: Text(sub,
                style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
            onTap: onTap,
          );
        }

        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Text(tr('ed.zoomTitle'),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            opt(Icons.zoom_in_rounded, tr('ed.zoomIn'), tr('ed.zoomInSub'),
                () => apply(1.0, 1.4)),
            opt(Icons.zoom_out_rounded, tr('ed.zoomOut'), tr('ed.zoomOutSub'),
                () => apply(1.4, 1.0)),
            opt(Icons.center_focus_strong_rounded, tr('ed.zoomHold'),
                tr('ed.zoomHoldSub'), () => apply(1.3, 1.3)),
            opt(Icons.flash_on_rounded, tr('ed.zoomPunch'), tr('ed.zoomPunchSub'),
                () => apply(1.0, 1.6)),
            opt(Icons.timeline_rounded, tr('ed.kf'), tr('ed.kfSub'), () {
              Navigator.pop(context);
              _showKeyframeSheet(provider);
            }, color: const Color(0xFF00BFA5)),
            const Divider(height: 1, color: AppColors.border),
            opt(Icons.zoom_out_map_rounded, tr('ed.zoomNone'), tr('ed.zoomNoneSub'),
                removeZoom,
                color: Colors.redAccent),
            const SizedBox(height: 12),
          ]),
        );
      },
    );
  }

  /// Full keyframe editor for zoom/pan on the selected clip. Lets the user place
  /// multiple keyframes (time + scale + focal) that animate across the clip.
  void _showKeyframeSheet(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null || _selectedClipIndex == null) return;
    final clips = _videoClips(project);
    if (_selectedClipIndex! >= clips.length) return;
    final clip = clips[_selectedClipIndex!];
    _pauseForEdit();

    // Get-or-create a ZoomEffect covering this clip (reuse if one overlaps).
    ZoomEffect? ze;
    for (final z in project.zoomEffects) {
      if (clip.start < z.endTime.inMilliseconds &&
          z.startTime.inMilliseconds < clip.end) {
        ze = z;
        break;
      }
    }
    if (ze == null) {
      ze = ZoomEffect(
        id: const Uuid().v4(),
        startTime: Duration(milliseconds: clip.start),
        endTime: Duration(milliseconds: clip.end),
        keyframes: [],
      );
      provider.addZoomEffect(ze);
    }
    final zoom = ze; // non-null

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        int scrubMs = _position.inMilliseconds.clamp(clip.start, clip.end);
        double scale = 1.2, fx = 0.5, fy = 0.5;
        int? selKf;

        return StatefulBuilder(builder: (ctx, setSheet) {
          void syncFromKf(int i) {
            final k = zoom.keyframes[i];
            selKf = i;
            scrubMs = k.timeMs.clamp(clip.start, clip.end);
            scale = k.scale;
            fx = k.focusX;
            fy = k.focusY;
            _seekTo(Duration(milliseconds: scrubMs));
            setState(() {});
          }

          void addKf() {
            zoom.keyframes.add(ZoomKeyframe(
                timeMs: scrubMs, scale: scale, focusX: fx, focusY: fy));
            zoom.keyframes.sort((a, b) => a.timeMs.compareTo(b.timeMs));
            selKf = zoom.keyframes.indexWhere((k) => k.timeMs == scrubMs);
            provider.commit();
            setSheet(() {});
            setState(() {});
          }

          void liveEditSel() {
            if (selKf != null && selKf! < zoom.keyframes.length) {
              zoom.keyframes[selKf!]
                ..scale = scale
                ..focusX = fx
                ..focusY = fy;
              setState(() {}); // live preview
            }
          }

          Widget slider(String label, double val, double min, double max,
              ValueChanged<double> onCh) {
            return Row(children: [
              SizedBox(
                  width: 58,
                  child: Text(label,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12))),
              Expanded(
                child: Slider(
                  value: val.clamp(min, max),
                  min: min,
                  max: max,
                  activeColor: const Color(0xFF00BFA5),
                  onChanged: onCh,
                  onChangeEnd: (_) => provider.commit(),
                ),
              ),
              SizedBox(
                  width: 40,
                  child: Text(val.toStringAsFixed(2),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11))),
            ]);
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  14, 14, 14, MediaQuery.of(ctx).viewInsets.bottom + 14),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Icon(Icons.timeline_rounded, color: Color(0xFF00BFA5)),
                  const SizedBox(width: 8),
                  Text(tr('ed.kfTitle'),
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(tr('common.done'),
                          style: const TextStyle(color: Color(0xFF00BFA5)))),
                ]),
                // Scrub position within the clip.
                Row(children: [
                  SizedBox(
                      width: 58,
                      child: Text(tr('ed.kfTime'),
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12))),
                  Expanded(
                    child: Slider(
                      value: scrubMs.toDouble().clamp(
                          clip.start.toDouble(), clip.end.toDouble()),
                      min: clip.start.toDouble(),
                      max: clip.end.toDouble(),
                      activeColor: AppColors.primary,
                      onChanged: (v) {
                        scrubMs = v.round();
                        _seekTo(Duration(milliseconds: scrubMs));
                        setSheet(() {});
                        setState(() {});
                      },
                    ),
                  ),
                  SizedBox(
                      width: 40,
                      child: Text(
                          '${((scrubMs - clip.start) / 1000).toStringAsFixed(1)}s',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11))),
                ]),
                slider(tr('ed.kfScale'), scale, 1.0, 3.0, (v) {
                  setSheet(() => scale = v);
                  liveEditSel();
                }),
                slider('X', fx, 0.0, 1.0, (v) {
                  setSheet(() => fx = v);
                  liveEditSel();
                }),
                slider('Y', fy, 0.0, 1.0, (v) {
                  setSheet(() => fy = v);
                  liveEditSel();
                }),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: addKf,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00BFA5),
                        foregroundColor: Colors.white),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: Text(tr('ed.kfAdd')),
                  ),
                ),
                const SizedBox(height: 10),
                // Keyframe chips.
                if (zoom.keyframes.isEmpty)
                  Text(tr('ed.kfEmpty'),
                      style:
                          const TextStyle(color: AppColors.textHint, fontSize: 12))
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (int i = 0; i < zoom.keyframes.length; i++)
                        GestureDetector(
                          onTap: () => setSheet(() => syncFromKf(i)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: selKf == i
                                  ? const Color(0xFF00BFA5)
                                  : AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(
                                  '◆ ${((zoom.keyframes[i].timeMs - clip.start) / 1000).toStringAsFixed(1)}s · ${zoom.keyframes[i].scale.toStringAsFixed(1)}x',
                                  style: TextStyle(
                                      color: selKf == i
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                      fontSize: 11)),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () {
                                  zoom.keyframes.removeAt(i);
                                  if (zoom.keyframes.isEmpty) {
                                    provider.removeZoomEffect(zoom.id);
                                  } else {
                                    provider.commit();
                                  }
                                  selKf = null;
                                  setSheet(() {});
                                  setState(() {});
                                },
                                child: const Icon(Icons.close,
                                    size: 13, color: Colors.redAccent),
                              ),
                            ]),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 6),
              ]),
            ),
          );
        });
      },
    );
  }

  /// Live shake intensity (fraction) at [ms] for the PREVIEW (mirrors native).
  double _shakeAt(int ms) {
    final ss = context.read<ProjectProvider>().currentProject?.shakeEffects;
    if (ss == null) return 0.0;
    for (final s in ss) {
      if (ms >= s.startTime.inMilliseconds && ms <= s.endTime.inMilliseconds) {
        return s.intensity;
      }
    }
    return 0.0;
  }

  /// Add a camera-shake effect to the selected clip.
  void _showShakeSheet(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null || _selectedClipIndex == null) return;
    final clips = _videoClips(project);
    if (_selectedClipIndex! >= clips.length) return;
    final clip = clips[_selectedClipIndex!];
    _pauseForEdit();

    void apply(double intensity) {
      provider.addShakeEffect(ShakeEffect(
        id: const Uuid().v4(),
        startTime: Duration(milliseconds: clip.start),
        endTime: Duration(milliseconds: clip.end),
        intensity: intensity,
      ));
      if (mounted) {
        Navigator.pop(context);
        setState(() {});
        _toast(tr('ed.shakeAdded'));
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        Widget opt(IconData ic, String label, VoidCallback onTap,
            {Color color = const Color(0xFFEA4C89)}) {
          return ListTile(
            leading: Icon(ic, color: color),
            title: Text(label,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            onTap: onTap,
          );
        }

        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Text(tr('ed.shakeTitle'),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            opt(Icons.vibration, tr('ed.shakeLight'), () => apply(0.015)),
            opt(Icons.vibration, tr('ed.shakeMed'), () => apply(0.03)),
            opt(Icons.vibration, tr('ed.shakeStrong'), () => apply(0.06)),
            const Divider(height: 1, color: AppColors.border),
            opt(Icons.clear_rounded, tr('ed.shakeNone'), () {
              provider.removeShakeEffectsIn(clip.start, clip.end);
              if (mounted) {
                Navigator.pop(context);
                setState(() {});
                _toast(tr('ed.shakeRemoved'));
              }
            }, color: Colors.redAccent),
            const SizedBox(height: 12),
          ]),
        );
      },
    );
  }

  /// Live fade-overlay opacity (0..1) at [ms] for the PREVIEW (mirrors native).
  double _fadeAt(int ms) {
    final fs = context.read<ProjectProvider>().currentProject?.fadeEffects;
    if (fs == null) return 0.0;
    for (final f in fs) {
      final s0 = f.startTime.inMilliseconds, e0 = f.endTime.inMilliseconds;
      if (ms < s0 || ms > e0) continue;
      final dur = (e0 - s0).clamp(1, 1 << 31);
      final t = ((ms - s0) / dur).clamp(0.0, 1.0);
      return f.toBlack ? t : (1.0 - t);
    }
    return 0.0;
  }

  /// Add fade transitions to the selected clip (in / out / at the cut).
  void _showFadeSheet(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null || _selectedClipIndex == null) return;
    final clips = _videoClips(project);
    if (_selectedClipIndex! >= clips.length) return;
    final clip = clips[_selectedClipIndex!];
    final dur = (clip.end - clip.start);
    final fadeMs = (500).clamp(100, dur ~/ 2 == 0 ? 500 : dur ~/ 2);
    _pauseForEdit();

    void addFade(int startMs, int endMs, bool toBlack) {
      provider.addFadeEffect(FadeEffect(
        id: const Uuid().v4(),
        startTime: Duration(milliseconds: startMs),
        endTime: Duration(milliseconds: endMs),
        toBlack: toBlack,
      ));
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        Widget opt(IconData ic, String label, String sub, VoidCallback onTap,
            {Color color = const Color(0xFF9C27B0)}) {
          return ListTile(
            leading: Icon(ic, color: color),
            title: Text(label,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            subtitle: Text(sub,
                style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
            onTap: () {
              onTap();
              if (mounted) {
                Navigator.pop(ctx);
                setState(() {});
                _toast(tr('ed.fadeAdded'));
              }
            },
          );
        }

        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Text(tr('ed.fadeTitle'),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            opt(Icons.south_east_rounded, tr('ed.fadeIn'), tr('ed.fadeInSub'),
                () => addFade(clip.start, clip.start + fadeMs, false)),
            opt(Icons.north_east_rounded, tr('ed.fadeOut'), tr('ed.fadeOutSub'),
                () => addFade(clip.end - fadeMs, clip.end, true)),
            opt(Icons.swap_horiz_rounded, tr('ed.fadeCut'), tr('ed.fadeCutSub'),
                () {
              // Fade out the end of this clip + fade in the start of the next.
              addFade(clip.end - fadeMs, clip.end, true);
              final next = _selectedClipIndex! + 1;
              if (next < clips.length) {
                addFade(clips[next].start, clips[next].start + fadeMs, false);
              }
            }),
            const Divider(height: 1, color: AppColors.border),
            opt(Icons.clear_rounded, tr('ed.fadeNone'), tr('ed.fadeNoneSub'), () {
              provider.removeFadeEffectsIn(clip.start, clip.end);
            }, color: Colors.redAccent),
            const SizedBox(height: 12),
          ]),
        );
      },
    );
  }

  /// Delete subtitles / SFX whose time falls inside a removed video range
  /// [a,b]. Times are NOT shifted — native drops the removed frames and remaps
  /// PTS, so later captions (matched by original PTS) land on the correct
  /// pulled-earlier frames automatically. This mirrors the proven Auto-Cut path.
  void _deleteInRange(ProjectProvider provider, int a, int b) {
    final project = provider.currentProject;
    if (project == null) return;
    // Drop captions whose midpoint sits inside the removed range.
    project.segments = project.segments.where((s) {
      final mid = (s.startTime.inMilliseconds + s.endTime.inMilliseconds) ~/ 2;
      return !(mid >= a && mid < b);
    }).toList();
    // Drop SFX that start inside the removed range.
    project.sfxBlocks.removeWhere(
        (blk) => blk.startTime.inMilliseconds >= a && blk.startTime.inMilliseconds < b);
  }

  // ── CapCut-style direct video clips ───────────────────────────────────────
}
