part of '../editor_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Top bar + video preview with subtitle/overlay rendering.
/// Split out of editor_screen.dart verbatim (phase 0) — the
/// fields and lifecycle stay in [_EditorScreenState].
extension _EditorPreview on _EditorScreenState {
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Consumer<ProjectProvider>(
        builder: (context, provider, _) {
          return Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  color: AppColors.textPrimary,
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 4),

              const SizedBox(width: 4),
              // Undo
              IconButton(
                icon: Icon(
                  Icons.undo,
                  color: provider.canUndo
                      ? AppColors.textSecondary
                      : AppColors.textHint,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                tooltip: 'Undo',
                onPressed: provider.canUndo ? provider.undo : null,
              ),
              const SizedBox(width: 2),
              // Redo
              IconButton(
                icon: Icon(
                  Icons.redo,
                  color: provider.canRedo
                      ? AppColors.textSecondary
                      : AppColors.textHint,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                tooltip: 'Redo',
                onPressed: provider.canRedo ? provider.redo : null,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Translate (icon-only to save space)
              if (_isTranslating)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              else
                GestureDetector(
                  onTap: () => _showTranslateSheet(provider),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.translate,
                      color: AppColors.textSecondary,
                      size: 16,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              // AI Caption + Hashtag generator (for posting to TikTok/FB fast)
              GestureDetector(
                onTap: () => _showCaptionSheet(provider),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(
                    Icons.tag,
                    color: AppColors.textSecondary,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // SRT export (icon-only to save header width)
              GestureDetector(
                onTap: () => _exportSRT(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(
                    Icons.subtitles_outlined,
                    color: AppColors.textSecondary,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // AI Dubbing (icon-only to save header width)
              GestureDetector(
                onTap: () => _showDubbingDialog(provider),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(
                    Icons.record_voice_over_outlined,
                    color: AppColors.textSecondary,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 6),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _showExportOptions,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppGradients.primary,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.ios_share_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Export',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Wraps the preview subtitle so it can be moved (drag), resized (pinch) and
  /// rotated directly on the video — CapCut-style WYSIWYG. Per-segment.
  Widget _wrapEditable(
    ProjectProvider provider,
    SubtitleProject project,
    SubtitleSegment seg,
    double rotationDeg,
    double boxW,
    double boxH, {
    required Widget child,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _previewSelected = !_previewSelected),
      onScaleStart: (d) {
        provider.pushHistory();
        _gBaseFont = seg.fontSize ?? project.fontSize;
        _gBaseRot = seg.rotation ?? 0.0;
        if (!_previewSelected) setState(() => _previewSelected = true);
      },
      onScaleUpdate: (d) {
        // Move (works with 1 or 2 fingers via the focal point).
        seg.positionX = (((seg.positionX ?? 0.5)) + d.focalPointDelta.dx / boxW)
            .clamp(0.04, 0.96);
        seg.positionY =
            (((seg.positionY ?? project.subtitlePositionY)) +
                    d.focalPointDelta.dy / boxH)
                .clamp(0.04, 0.98);
        // Resize + rotate need two fingers.
        if (d.pointerCount >= 2) {
          seg.fontSize = (_gBaseFont * d.scale).clamp(8.0, 140.0);
          seg.rotation = _gBaseRot + d.rotation / _deg2rad;
        }
        provider.liveUpdate();
        setState(() {});
      },
      onScaleEnd: (_) => provider.commit(),
      child: Transform.rotate(
        angle: rotationDeg * _deg2rad,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: _previewSelected
                  ? BoxDecoration(
                      border: Border.all(color: AppColors.primary, width: 1.5),
                      borderRadius: BorderRadius.circular(4),
                    )
                  : null,
              padding: const EdgeInsets.all(4),
              child: child,
            ),
            if (_previewSelected) ...[
              Positioned(
                top: -12,
                left: -12,
                child: _previewHandle(
                  Icons.close,
                  () => setState(() => _previewSelected = false),
                ),
              ),
              Positioned(
                top: -12,
                right: -12,
                child: _previewHandle(Icons.edit, () {
                  _editSegment(seg, _activeSegmentIndex, provider);
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _previewHandle(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white70),
        ),
        child: Icon(icon, size: 15, color: Colors.white),
      ),
    );
  }

  Widget _buildVideoPreview() {
    return Consumer<ProjectProvider>(
      builder: (context, provider, _) {
        final project = provider.currentProject;
        final segments = project?.segments ?? [];
        // Show a subtitle ONLY when the playhead is within its time range —
        // during gaps between subtitles nothing should appear.
        SubtitleSegment? activeSegment;
        for (final s in segments) {
          if (_position >= s.startTime && _position <= s.endTime) {
            activeSegment = s;
            break;
          }
        }

        // On the Timeline tab keep the preview a bit smaller so the track
        // below has enough room to edit comfortably.
        // Same preview size on every tab (consistent, not cramped on mobile).
        final previewHeight = (MediaQuery.of(context).size.height * 0.36).clamp(
          200.0,
          360.0,
        );

        // ── Multi-clip: render the native gapless player's texture. ──
        if ((project?.clips.length ?? 0) >= 2 && _clipTextureId != null) {
          final ar = (_clipPlayer != null &&
                  _clipPlayer!.videoW > 0 &&
                  _clipPlayer!.videoH > 0)
              ? _clipPlayer!.videoW / _clipPlayer!.videoH
              : 9 / 16;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            height: previewHeight,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: ar,
                      child: Texture(textureId: _clipTextureId!),
                    ),
                  ),
                  // Play/pause tap layer.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _togglePlay,
                      child: AnimatedOpacity(
                        opacity: _isPlaying ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: Center(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow,
                                color: Colors.white, size: 34),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final controller = _videoController;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          height: previewHeight,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (controller != null && controller.value.isInitialized)
                  Center(
                    child: AspectRatio(
                      aspectRatio: (project?.bgBlur ?? false)
                          ? 9 / 16
                          : controller.value.aspectRatio,
                      child: LayoutBuilder(
                        builder: (ctx, c) {
                          // Scale subtitle to the video box so preview == export
                          // (export uses fontSize * videoHeight / 220).
                          final scale = (c.maxHeight / 220).clamp(0.5, 8.0);
                          // Live zoom (Ken-Burns) + shake preview — only the video
                          // transforms; subtitle + overlays stay fixed (matches native).
                          final zm = _zoomAt(_position.inMilliseconds);
                          final shAmp = _shakeAt(_position.inMilliseconds);
                          Widget videoW = VideoPlayer(controller);
                          if (zm.$1 > 1.001) {
                            videoW = Transform.scale(
                              scale: zm.$1,
                              alignment:
                                  Alignment(zm.$2 * 2 - 1, zm.$3 * 2 - 1),
                              child: videoW,
                            );
                          }
                          if (shAmp > 0) {
                            final ts = _position.inMilliseconds / 1000.0;
                            final maxOff = shAmp * c.maxWidth;
                            final dx = (math.sin(ts * 57) +
                                    math.sin(ts * 89) * 0.6) *
                                maxOff;
                            final dy = (math.cos(ts * 63) +
                                    math.cos(ts * 97) * 0.6) *
                                maxOff;
                            videoW = Transform.scale(
                              scale: 1 + shAmp * 2,
                              child: Transform.translate(
                                  offset: Offset(dx, dy), child: videoW),
                            );
                          }
                          if (zm.$1 > 1.001 || shAmp > 0) {
                            videoW = ClipRect(child: videoW);
                          }
                          // Blurred background: video contained on a blurred,
                          // cover-scaled copy (matches the native 9:16 export).
                          Widget videoLayer = videoW;
                          if (project?.bgBlur ?? false) {
                            videoLayer = Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRect(
                                  child: ImageFiltered(
                                    imageFilter: ui.ImageFilter.blur(
                                        sigmaX: 18, sigmaY: 18),
                                    child: FittedBox(
                                      fit: BoxFit.cover,
                                      child: SizedBox(
                                        width: controller.value.size.width,
                                        height: controller.value.size.height,
                                        child: VideoPlayer(controller),
                                      ),
                                    ),
                                  ),
                                ),
                                Container(color: Colors.black26),
                                Center(
                                  child: AspectRatio(
                                    aspectRatio: controller.value.aspectRatio,
                                    child: videoW,
                                  ),
                                ),
                              ],
                            );
                          }
                          return Stack(
                            children: [
                              // When a clip is selected: pinch = zoom, drag = pan
                              // → auto keyframe at the playhead (CapCut-style).
                              Positioned.fill(
                                child: _selectedClipIndex != null
                                    ? GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onScaleStart: (d) {
                                          _pauseForEdit();
                                          _kfBaseScale =
                                              _zoomAt(_position.inMilliseconds).$1;
                                          _kfMoved = false;
                                          _kfZoom = null;
                                          _kfActive = null;
                                        },
                                        onScaleUpdate: (d) {
                                          if (!_kfMoved) {
                                            provider.pushHistory();
                                            final z = _ensureZoomForSelectedClip(
                                                provider);
                                            if (z == null) return;
                                            _kfZoom = z;
                                            _kfActive = _keyframeAtPlayhead(z);
                                            _kfMoved = true;
                                          }
                                          final kf = _kfActive;
                                          if (kf == null) return;
                                          final ns = (_kfBaseScale * d.scale)
                                              .clamp(1.0, 4.0);
                                          kf.scale = ns;
                                          if (ns > 1.001) {
                                            kf.focusX = (kf.focusX -
                                                    d.focalPointDelta.dx /
                                                        (c.maxWidth * ns))
                                                .clamp(0.0, 1.0);
                                            kf.focusY = (kf.focusY -
                                                    d.focalPointDelta.dy /
                                                        (c.maxHeight * ns))
                                                .clamp(0.0, 1.0);
                                          }
                                          provider.liveUpdate();
                                          setState(() {});
                                        },
                                        onScaleEnd: (d) {
                                          if (_kfMoved) {
                                            provider.commit();
                                            _toast(tr('ed.kfCaptured'));
                                          }
                                          _kfZoom = null;
                                          _kfActive = null;
                                          _kfMoved = false;
                                        },
                                        child: videoLayer,
                                      )
                                    : videoLayer,
                              ),
                              if (_selectedClipIndex != null)
                                Positioned(
                                  top: 6,
                                  left: 0,
                                  right: 0,
                                  child: IgnorePointer(
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(tr('ed.kfHint'),
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10)),
                                      ),
                                    ),
                                  ),
                                ),
                              // Image overlays active at the current playhead
                              // (drawn under the subtitle text).
                              if (project != null)
                                ..._buildImageOverlayWidgets(
                                    provider, project, c.maxWidth, c.maxHeight),
                              if (activeSegment != null && project != null)
                                Builder(
                                  builder: (_) {
                                    final eff = _effectiveStyle(
                                      project,
                                      activeSegment!,
                                    );
                                    return Positioned.fill(
                                      child: Align(
                                        alignment: Alignment.center,
                                        child: Transform.translate(
                                          // Anchor the subtitle CENTRE at
                                          // (positionX*W, positionY*H) — the exact
                                          // model the native exporter uses, so the
                                          // preview matches the export 1:1.
                                          offset: Offset(
                                            (eff.positionX - 0.5) * c.maxWidth,
                                            (eff.positionY - 0.5) * c.maxHeight,
                                          ),
                                          child: _wrapEditable(
                                            provider,
                                            project,
                                            activeSegment!,
                                            eff.rotation,
                                            c.maxWidth,
                                            c.maxHeight,
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                  ),
                                              child: _buildAnimatedSubtitleWrapper(
                                                animation: eff.animation,
                                                exitAnimation:
                                                    project.exitAnimation,
                                                speed: project.animationSpeed,
                                                segment: activeSegment,
                                                position: _position,
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    (eff.karaoke ||
                                                            (activeSegment
                                                                    .emphasis
                                                                    ?.isNotEmpty ??
                                                                false))
                                                        ? _buildKaraokeSubtitle(
                                                            activeSegment,
                                                            eff.preset,
                                                            fontSize:
                                                                eff.fontSize *
                                                                scale,
                                                            fontFamily:
                                                                eff.fontFamily,
                                                            highlightColor: project
                                                                .karaokeHighlightColor,
                                                            scalePop:
                                                                eff.karaokeScale ||
                                                                (activeSegment
                                                                        .emphasis
                                                                        ?.isNotEmpty ??
                                                                    false),
                                                            sweep: eff.karaoke,
                                                            emphasis:
                                                                activeSegment
                                                                    .emphasis ??
                                                                const [],
                                                            emoji: activeSegment
                                                                .emoji,
                                                            position: _position,
                                                            fontWeight:
                                                                fontWeightFromInt(
                                                                  eff.fontWeight,
                                                                ),
                                                            textColorOverride:
                                                                eff.textColor,
                                                          )
                                                        : _buildSubtitleOverlay(
                                                            _appendEmoji(
                                                              eff.animation ==
                                                                      SubtitleAnimation
                                                                          .typewriter
                                                                  ? _typewriterReveal(
                                                                      activeSegment!,
                                                                      _position,
                                                                      project
                                                                          .animationSpeed,
                                                                    )
                                                                  : activeSegment
                                                                        .text,
                                                              activeSegment
                                                                  .emoji,
                                                            ),
                                                            eff.preset,
                                                            fontSizeOverride:
                                                                eff.fontSize *
                                                                scale,
                                                            fontFamily:
                                                                eff.fontFamily,
                                                            fontWeightOverride:
                                                                fontWeightFromInt(
                                                                  eff.fontWeight,
                                                                ),
                                                            textColorOverride:
                                                                eff.textColor,
                                                          ),
                                                    if (project.showBilingual &&
                                                        activeSegment
                                                                .translatedText !=
                                                            null &&
                                                        activeSegment
                                                            .translatedText!
                                                            .isNotEmpty) ...[
                                                      SizedBox(
                                                        height:
                                                            project
                                                                .bilingualGap *
                                                            scale,
                                                      ),
                                                      _buildSubtitleOverlay(
                                                        activeSegment
                                                            .translatedText!,
                                                        subtitlePresets[project
                                                            .bilingualPresetIndex
                                                            .clamp(
                                                              0,
                                                              subtitlePresets
                                                                      .length -
                                                                  1,
                                                            )],
                                                        fontSizeOverride:
                                                            project
                                                                .bilingualFontSize *
                                                            scale,
                                                        fontFamily:
                                                            eff.fontFamily,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              // Fade transition — black overlay over everything.
                              if (_fadeAt(_position.inMilliseconds) > 0.001)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: Container(
                                      color: Colors.black.withOpacity(
                                          _fadeAt(_position.inMilliseconds)
                                              .clamp(0.0, 1.0)),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  )
                else
                  const Center(
                    child: Icon(
                      Icons.movie_outlined,
                      color: AppColors.textHint,
                      size: 48,
                    ),
                  ),
                // (play controls moved to a dedicated bar below the preview)
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedSubtitleWrapper({
    required SubtitleAnimation animation,
    required SubtitleAnimation exitAnimation,
    required AnimationSpeed speed,
    required SubtitleSegment segment,
    required Duration position,
    required Widget child,
  }) {
    final durMs = animationDurationMs(speed);
    final elapsed = (position - segment.startTime).inMilliseconds;
    final remaining = (segment.endTime - position).inMilliseconds;
    // Exit takes priority in the last [durMs] of the segment.
    if (exitAnimation != SubtitleAnimation.none &&
        remaining >= 0 &&
        remaining < durMs) {
      return _animLayer(
        exitAnimation,
        (remaining / durMs).clamp(0.0, 1.0),
        true,
        child,
      );
    }
    if (animation != SubtitleAnimation.none &&
        elapsed >= 0 &&
        elapsed < durMs) {
      return _animLayer(
        animation,
        (elapsed / durMs).clamp(0.0, 1.0),
        false,
        child,
      );
    }
    return child;
  }

  /// One animation layer. [t] = raw progress (0 = hidden, 1 = shown).
  /// [exit] flips the travel direction so the text leaves the way it came.
  Widget _animLayer(SubtitleAnimation type, double t, bool exit, Widget child) {
    final vis = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t); // easeOutCubic
    final hidden = 1.0 - vis;
    switch (type) {
      case SubtitleAnimation.fadeIn:
        return Opacity(opacity: vis, child: child);
      case SubtitleAnimation.slideUp:
        return Transform.translate(
          offset: Offset(0, (exit ? -1 : 1) * 16 * hidden),
          child: Opacity(opacity: vis, child: child),
        );
      case SubtitleAnimation.slideDown:
        return Transform.translate(
          offset: Offset(0, (exit ? 1 : -1) * 16 * hidden),
          child: Opacity(opacity: vis, child: child),
        );
      case SubtitleAnimation.slideLeft:
        return Transform.translate(
          offset: Offset((exit ? -1 : 1) * 20 * hidden, 0),
          child: Opacity(opacity: vis, child: child),
        );
      case SubtitleAnimation.bounceIn:
        final s = exit ? vis : _bounceEase(t);
        return Transform.scale(
          scale: s.clamp(0.0, 1.2),
          child: Opacity(opacity: vis.clamp(0.0, 1.0), child: child),
        );
      case SubtitleAnimation.typewriter:
      case SubtitleAnimation.none:
        return child;
    }
  }

  /// Typewriter reveal: text revealed so far, by syllable units (speed-based)
  /// so Lao combining marks never split mid-glyph.
  String _typewriterReveal(SubtitleSegment s, Duration pos, AnimationSpeed sp) {
    final units = (s.words != null && s.words!.isNotEmpty)
        ? s.words!.where((w) => w.isNotEmpty).toList()
        : splitLaoHighlightUnits(s.text);
    if (units.isEmpty) return s.text;
    final elapsedMs = (pos - s.startTime).inMilliseconds;
    if (elapsedMs <= 0) return '';
    final k = (elapsedMs ~/ typewriterUnitMs(sp)).clamp(0, units.length);
    return joinWordsSmart(units.sublist(0, k));
  }

  double _bounceEase(double t) {
    const s = 1.70158;
    final t2 = t - 1.0;
    return t2 * t2 * ((s + 1) * t2 + s) + 1.0;
  }

  /// Resolve the style values to use for [s], applying its per-segment
  /// overrides on top of the project-wide defaults (null override = inherit).
  ({
    SubtitlePreset preset,
    String fontFamily,
    double fontSize,
    int fontWeight,
    Color? textColor,
    SubtitleAnimation animation,
    double positionY,
    double positionX,
    double rotation,
    bool karaoke,
    bool karaokeScale,
  })
  _effectiveStyle(SubtitleProject p, SubtitleSegment s) {
    final preset = s.styleIndex != null
        ? subtitlePresets[s.styleIndex!.clamp(0, subtitlePresets.length - 1)]
        : p.selectedStyle;
    return (
      preset: preset,
      fontFamily: s.fontFamily ?? p.fontFamily,
      fontSize: s.fontSize ?? p.fontSize,
      fontWeight: s.fontWeight ?? p.fontWeight,
      textColor: s.textColorValue != null ? Color(s.textColorValue!) : null,
      animation: s.animation ?? p.subtitleAnimation,
      positionY: s.positionY ?? p.subtitlePositionY,
      positionX: s.positionX ?? 0.5,
      rotation: s.rotation ?? 0.0,
      karaoke: s.karaoke ?? p.isKaraokeHighlight,
      karaokeScale: s.karaokeScale ?? p.karaokeScale,
    );
  }

  /// Image overlays active at the current playhead, positioned + draggable on
  /// the preview (normalised x/y/scale → matches the native export 1:1).
  List<Widget> _buildImageOverlayWidgets(
    ProjectProvider provider,
    SubtitleProject project,
    double w,
    double h,
  ) {
    final posMs = _position.inMilliseconds;
    final widgets = <Widget>[];
    for (final ov in project.imageOverlays) {
      if (posMs < ov.startTime.inMilliseconds || posMs > ov.endTime.inMilliseconds) {
        continue;
      }
      final selected = _selectedImageId == ov.id;
      final st = _overlayStateAt(ov, posMs);

      // Full-screen "cover" overlay: fill the whole preview, crop overflow.
      if (ov.cover) {
        Widget media = ov.isVideo
            ? _brollPreview(ov.id)
            : Image.file(File(ov.path),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink());
        if (ov.isVideo) {
          // _brollPreview already returns an AspectRatio video; wrap to cover.
          media = FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: w,
              height: w / _brollAspect(ov.id),
              child: media,
            ),
          );
        }
        widgets.add(Positioned(
          left: 0,
          top: 0,
          width: w,
          height: h,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _pauseForEdit();
              setState(() {
                _selectedImageId = ov.id;
                _selectedIndex = null;
                _selectedSfxId = null;
                _selectedClipIndex = null;
              });
            },
            child: Opacity(
              opacity: st.opacity.clamp(0.0, 1.0),
              child: Transform.flip(
                flipX: ov.flipH,
                child: ClipRect(
                  child: Container(
                    decoration: selected
                        ? BoxDecoration(
                            border: Border.all(color: AppColors.primary, width: 2))
                        : null,
                    child: media,
                  ),
                ),
              ),
            ),
          ),
        ));
        continue;
      }

      // Allow scaling beyond the screen (up to 3× video width). The widget is
      // sized to the scaled width; rotation/flip applied around its centre.
      final imgW = (st.scale * w).clamp(20.0, w * 3.0);
      widgets.add(Positioned(
        // Centre the (possibly oversized) box on (x,y); it may extend off-screen.
        left: st.x * w - imgW / 2,
        top: st.y * h - imgW / 2,
        width: imgW,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // onScale handles drag (1 finger) + pinch-zoom + twist-rotate (2).
          // If the overlay has keyframes, edits write to a keyframe at the
          // playhead (CapCut-style); otherwise they change the static values.
          onScaleStart: (_) {
            _pauseForEdit();
            provider.pushHistory();
            final s0 = _overlayStateAt(ov, _position.inMilliseconds);
            _imgBaseScale = s0.scale;
            _imgBaseRot = s0.rotation;
            setState(() {
              _selectedImageId = ov.id;
              _selectedIndex = null;
              _selectedSfxId = null;
              _selectedClipIndex = null;
            });
          },
          onScaleUpdate: (d) {
            setState(() {
              if (ov.keyframes.isNotEmpty) {
                final kf = _overlayKeyframeAtPlayhead(ov);
                if (d.pointerCount >= 2) {
                  kf.scale = (_imgBaseScale * d.scale).clamp(0.05, 3.0);
                  kf.rotation =
                      (_imgBaseRot + d.rotation * 180 / 3.1415926535) % 360;
                }
                kf.x = (kf.x + d.focalPointDelta.dx / w).clamp(-0.5, 1.5);
                kf.y = (kf.y + d.focalPointDelta.dy / h).clamp(-0.5, 1.5);
              } else {
                if (d.pointerCount >= 2) {
                  ov.scale = (_imgBaseScale * d.scale).clamp(0.05, 3.0);
                  ov.rotation =
                      (_imgBaseRot + d.rotation * 180 / 3.1415926535) % 360;
                }
                ov.x = (ov.x + d.focalPointDelta.dx / w).clamp(-0.5, 1.5);
                ov.y = (ov.y + d.focalPointDelta.dy / h).clamp(-0.5, 1.5);
              }
            });
            provider.liveUpdate();
          },
          onScaleEnd: (_) => provider.commit(),
          child: Opacity(
            opacity: st.opacity.clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: st.rotation * 3.1415926535 / 180.0,
              child: Transform.flip(
                flipX: ov.flipH,
                child: Container(
                  decoration: selected
                      ? BoxDecoration(
                          border: Border.all(color: AppColors.primary, width: 2))
                      : null,
                  child: ov.isVideo
                      ? _brollPreview(ov.id)
                      : Image.file(
                          File(ov.path),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                ),
              ),
            ),
          ),
        ),
      ));
    }
    return widgets;
  }

  /// Live B-roll video frame for the preview. Falls back to a black box with a
  /// spinner while the controller initializes.
  Widget _brollPreview(String id) {
    final c = _brollCtrls[id];
    if (c == null || !c.value.isInitialized) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            ),
          ),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: c.value.aspectRatio,
      child: VideoPlayer(c),
    );
  }

  /// Aspect ratio of a B-roll clip's controller (w/h), or 16:9 while loading.
  double _brollAspect(String id) {
    final c = _brollCtrls[id];
    if (c != null && c.value.isInitialized && c.value.aspectRatio > 0) {
      return c.value.aspectRatio;
    }
    return 16 / 9;
  }

  Widget _buildSubtitleOverlay(
    String text,
    SubtitlePreset preset, {
    double? fontSizeOverride,
    String fontFamily = 'NotoSansLao',
    FontWeight? fontWeightOverride,
    Color? textColorOverride,
  }) {
    final fontSize = fontSizeOverride ?? preset.fontSize;
    final weight = fontWeightOverride ?? preset.fontWeight;
    final mainColor = textColorOverride ?? preset.textColor;
    Widget textWidget;

    if (preset.has3dShadow) {
      // Thick retro extrude: stack many hard black shadows stepping down-right.
      final depth = (fontSize * 0.13).round().clamp(3, 14);
      textWidget = Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: _applyLaoFont(
          fontFamily,
          TextStyle(
            color: mainColor,
            fontWeight: weight,
            fontSize: fontSize,
            shadows: [
              for (int i = 1; i <= depth; i++)
                Shadow(
                  color: Colors.black,
                  offset: Offset(i.toDouble(), i.toDouble()),
                  blurRadius: 0,
                ),
            ],
          ),
        ),
      );
    } else if (preset.gradientColors != null &&
        preset.gradientColors!.length >= 2) {
      // Gradient fill text.
      textWidget = ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(
          colors: preset.gradientColors!,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(r),
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: _applyLaoFont(
            fontFamily,
            TextStyle(
              color: Colors.white,
              fontWeight: weight,
              fontSize: fontSize,
              shadows: preset.hasShadow
                  ? [
                      const Shadow(
                        color: Colors.black,
                        blurRadius: 8,
                        offset: Offset(1, 2),
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      );
    } else if (preset.hasOutline) {
      // Hard stroke outline (sticker look): stroke layer + fill on top.
      final strokeW = (fontSize * 0.13).clamp(2.0, 12.0);
      // Optional soft drop shadow (matches the native exporter: offset down-right).
      final outShadows = preset.hasShadow
          ? [
              Shadow(
                color: Colors.black.withOpacity(0.7),
                blurRadius: fontSize * 0.2,
                offset: Offset(fontSize * 0.03, fontSize * 0.06),
              ),
            ]
          : null;
      Widget layer(Paint? fg, Color? col, {List<Shadow>? sh}) => Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: _applyLaoFont(
          fontFamily,
          TextStyle(
            foreground: fg,
            color: col,
            fontWeight: weight,
            fontSize: fontSize,
            shadows: sh,
          ),
        ),
      );
      textWidget = Stack(
        alignment: Alignment.center,
        children: [
          layer(
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = strokeW
              ..strokeJoin = StrokeJoin.round
              ..color = preset.outlineColor ?? Colors.black,
            null,
            sh: outShadows,
          ),
          layer(null, mainColor),
        ],
      );
    } else if (preset.hasNeonGlow) {
      textWidget = Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: _applyLaoFont(
          fontFamily,
          TextStyle(
            color: mainColor,
            fontWeight: weight,
            fontSize: fontSize,
            shadows: [
              Shadow(
                color: preset.glowColor ?? preset.textColor,
                blurRadius: 16,
              ),
              Shadow(
                color: preset.glowColor ?? preset.textColor,
                blurRadius: 32,
              ),
            ],
          ),
        ),
      );
    } else if (preset.hasUnderline) {
      textWidget = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _applyLaoFont(
              fontFamily,
              TextStyle(
                color: preset.textColor,
                fontWeight: weight,
                fontSize: fontSize,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Container(
            height: 3,
            width: 100,
            decoration: BoxDecoration(
              color: preset.underlineColor ?? AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      );
    } else {
      textWidget = Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: _applyLaoFont(
          fontFamily,
          TextStyle(
            color: mainColor,
            fontWeight: weight,
            fontSize: fontSize,
            shadows: preset.hasShadow
                ? [
                    const Shadow(
                      color: Colors.black,
                      blurRadius: 8,
                      offset: Offset(1, 2),
                    ),
                  ]
                : null,
          ),
        ),
      );
    }

    if (preset.backgroundColor != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: preset.backgroundColor,
          borderRadius: BorderRadius.circular(5),
        ),
        child: textWidget,
      );
    }
    return textWidget;
  }

  Widget _buildKaraokeSubtitle(
    SubtitleSegment segment,
    SubtitlePreset preset, {
    required double fontSize,
    required String fontFamily,
    required Color highlightColor,
    required Duration position,
    bool scalePop = false,
    bool sweep = true,
    List<int> emphasis = const [],
    String? emoji,
    FontWeight? fontWeight,
    Color? textColorOverride,
  }) {
    final baseColor = textColorOverride ?? preset.textColor;
    // Karaoke units = WHOLE WORDS (highlight one word at a time, e.g. "ທາງ").
    // Uses the segment's ICU word units; falls back to splitting the raw text
    // only when no units are stored.
    final words = (segment.words != null && segment.words!.isNotEmpty)
        ? segment.words!.where((w) => w.isNotEmpty).toList()
        : splitLaoHighlightUnits(segment.text);
    if (words.isEmpty) return const SizedBox();

    // Active word = the last word whose start time <= current position.
    final int activeIdx;
    final timings = segment.wordTimings;
    if (timings != null && timings.length == words.length) {
      activeIdx = timings
          .lastIndexWhere((t) => position >= t)
          .clamp(0, words.length - 1);
    } else {
      final segDurMs =
          segment.endTime.inMilliseconds - segment.startTime.inMilliseconds;
      final elapsedMs =
          position.inMilliseconds - segment.startTime.inMilliseconds;
      final wordDurMs = segDurMs > 0 ? segDurMs / words.length : 1000.0;
      activeIdx = segDurMs > 0
          ? (elapsedMs / wordDurMs).floor().clamp(0, words.length - 1)
          : 0;
    }

    final baseStyle = _applyLaoFont(
      fontFamily,
      TextStyle(
        color: baseColor,
        fontWeight: fontWeight ?? preset.fontWeight,
        fontSize: fontSize,
        shadows: const [
          Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(1, 1)),
        ],
      ),
    );

    // Only sweep word-by-word when there are ≥2 word units. A single unit
    // (e.g. edited Lao text with no spaces, or a one-word phrase) would
    // otherwise colour the whole line, so render it plain instead.
    final canHighlight = words.length >= 2;
    final emphasisSet = emphasis.toSet();
    final spans = <TextSpan>[];
    for (int i = 0; i < words.length; i++) {
      if (i > 0 && needSpaceBetweenWords(words[i - 1], words[i])) {
        spans.add(const TextSpan(text: ' '));
      }
      // A word is highlighted if the karaoke sweep is on it, OR it's an
      // AI-picked "punch" word (Auto ✨ emphasis — always highlighted).
      final isActive = sweep && canHighlight && i == activeIdx;
      final isEmphasis = emphasisSet.contains(i);
      final hot = isActive || isEmphasis;
      spans.add(
        TextSpan(
          text: words[i],
          style: baseStyle.copyWith(
            color: hot ? highlightColor : baseColor,
            // Word Pop: enlarge the hot word (~1.22×) so it grows.
            fontSize: (hot && scalePop) ? fontSize * 1.22 : fontSize,
          ),
        ),
      );
    }
    if (emoji != null && emoji.isNotEmpty) {
      spans.add(TextSpan(text: ' $emoji', style: baseStyle));
    }

    final content = Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.center,
    );

    // If background color is set on the preset, wrap in a box
    if (preset.backgroundColor != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: preset.backgroundColor,
          borderRadius: BorderRadius.circular(5),
        ),
        child: content,
      );
    }
    return content;
  }
}
