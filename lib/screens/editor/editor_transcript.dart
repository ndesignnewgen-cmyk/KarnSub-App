part of '../editor_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Subtitle tab: segment list/cards, sync bar, segment & SFX block ops.
/// Split out of editor_screen.dart verbatim (phase 0) — the
/// fields and lifecycle stay in [_EditorScreenState].
extension _EditorTranscript on _EditorScreenState {
  Widget _buildTranscriptTab() {
    return Consumer<ProjectProvider>(
      builder: (context, provider, _) {
        final project = provider.currentProject;
        final segments = project?.segments ?? [];
        final hasTranslation = segments.any((s) => s.translatedText != null);
        if (segments.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('ed.noSubtitle'),
                  style: const TextStyle(color: AppColors.textHint),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _showAddSegmentSheet(provider),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(tr('ed.addSubtitle')),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _openTapSync,
                  icon: const Icon(Icons.touch_app, size: 16),
                  label: Text(tr('tap.button')),
                ),
              ],
            ),
          );
        }
        return Stack(
          children: [
            Column(
              children: [
                // Re-split + bilingual toggle toolbar
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 6, 12, 3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_fix_high,
                        color: AppColors.primary,
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tr('ed.splitColon'),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _buildReSplitBtn(
                                tr('ed.auto'),
                                WordSplit.none,
                                provider,
                              ),
                              const SizedBox(width: 6),
                              _buildReSplitBtn('2 ${tr('split.word')}', WordSplit.two, provider),
                              const SizedBox(width: 6),
                              _buildReSplitBtn(
                                '3 ${tr('split.word')}',
                                WordSplit.three,
                                provider,
                              ),
                              const SizedBox(width: 6),
                              _buildReSplitBtn(
                                '4 ${tr('split.word')}',
                                WordSplit.four,
                                provider,
                              ),
                              const SizedBox(width: 6),
                              _buildReSplitBtn('6 ${tr('split.word')}', WordSplit.six, provider),
                              const SizedBox(width: 6),
                              _buildReSplitBtn(
                                '8 ${tr('split.word')}',
                                WordSplit.eight,
                                provider,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (hasTranslation) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: provider.toggleShowTranslation,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: provider.showTranslation
                                  ? AppColors.primary.withOpacity(0.15)
                                  : AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: provider.showTranslation
                                    ? AppColors.primary
                                    : AppColors.border,
                              ),
                            ),
                            child: Icon(
                              Icons.translate,
                              size: 14,
                              color: provider.showTranslation
                                  ? AppColors.primary
                                  : AppColors.textHint,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _buildSyncBar(provider),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 72),
                    itemCount: segments.length,
                    itemBuilder: (context, index) => _buildSegmentCard(
                      segments[index],
                      index,
                      provider,
                      showTranslation: provider.showTranslation,
                    ),
                  ),
                ),
              ],
            ),
            // FAB to add segment
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                onPressed: () => _showAddSegmentSheet(provider),
                backgroundColor: AppColors.primary,
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  void _nudgeSync(ProjectProvider provider, int deltaMs) {
    provider.shiftAllSegments(Duration(milliseconds: deltaMs));
    setState(() => _syncOffsetMs += deltaMs);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }


  String _newId(int k) => '${DateTime.now().microsecondsSinceEpoch}_$k';

  void _zoomTimeline(double factor) {
    setState(() => _pxPerSec = (_pxPerSec * factor).clamp(40.0, 400.0));
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollTimelineToPosition(),
    );
  }

  void _jumpSegment(ProjectProvider provider, int dir) {
    final segs = provider.currentProject?.segments ?? [];
    if (segs.isEmpty) return;
    final cur = _position.inMilliseconds;
    if (dir > 0) {
      for (final s in segs) {
        if (s.startTime.inMilliseconds > cur + 20) {
          _seekTo(s.startTime);
          _scrollTimelineToPosition();
          return;
        }
      }
    } else {
      for (int i = segs.length - 1; i >= 0; i--) {
        if (segs[i].startTime.inMilliseconds < cur - 20) {
          _seekTo(segs[i].startTime);
          _scrollTimelineToPosition();
          return;
        }
      }
    }
  }

  void _splitAtPlayhead(ProjectProvider provider, int index) {
    final segs = provider.currentProject!.segments
        .map((s) => s.copy())
        .toList();
    if (index < 0 || index >= segs.length) return;
    final s = segs[index];
    final cut = _position.inMilliseconds;
    final st = s.startTime.inMilliseconds, en = s.endTime.inMilliseconds;
    if (cut <= st + 80 || cut >= en - 80) {
      _toast(tr('ed.movePlayheadCenter'));
      return;
    }
    final words = s.words ?? [];
    final timings = s.wordTimings;
    SubtitleSegment a, b;
    if (words.length >= 2 &&
        timings != null &&
        timings.length == words.length) {
      final fw = <String>[], sw = <String>[];
      final ft = <Duration>[], stt = <Duration>[];
      for (int i = 0; i < words.length; i++) {
        if (timings[i].inMilliseconds < cut) {
          fw.add(words[i]);
          ft.add(timings[i]);
        } else {
          sw.add(words[i]);
          stt.add(timings[i]);
        }
      }
      if (fw.isEmpty || sw.isEmpty) {
        _toast(tr('ed.cantCutHere'));
        return;
      }
      a = SubtitleSegment(
        id: _newId(1),
        text: joinWordsSmart(fw),
        startTime: s.startTime,
        endTime: Duration(milliseconds: cut),
        words: fw,
        wordTimings: ft,
      );
      b = SubtitleSegment(
        id: _newId(2),
        text: joinWordsSmart(sw),
        startTime: Duration(milliseconds: cut),
        endTime: s.endTime,
        words: sw,
        wordTimings: stt,
      );
    } else {
      final ratio = (cut - st) / (en - st);
      final idx = (s.text.length * ratio).round().clamp(1, s.text.length - 1);
      a = SubtitleSegment(
        id: _newId(1),
        text: s.text.substring(0, idx).trim(),
        startTime: s.startTime,
        endTime: Duration(milliseconds: cut),
      );
      b = SubtitleSegment(
        id: _newId(2),
        text: s.text.substring(idx).trim(),
        startTime: Duration(milliseconds: cut),
        endTime: s.endTime,
      );
    }
    segs.removeAt(index);
    segs.insert(index, a);
    segs.insert(index + 1, b);
    provider.updateSegments(segs);
    setState(() => _selectedIndex = index);
  }

  void _mergeWithNext(ProjectProvider provider, int index) {
    final segs = provider.currentProject!.segments
        .map((s) => s.copy())
        .toList();
    if (index < 0 || index >= segs.length - 1) {
      _toast(tr('ed.noNextBlock'));
      return;
    }
    final a = segs[index], b = segs[index + 1];
    final words = <String>[...(a.words ?? []), ...(b.words ?? [])];
    final timings = (a.wordTimings != null && b.wordTimings != null)
        ? <Duration>[...a.wordTimings!, ...b.wordTimings!]
        : null;
    final mergedTrans = [
      a.translatedText,
      b.translatedText,
    ].where((t) => t != null && t.isNotEmpty).join(' ');
    final merged = SubtitleSegment(
      id: a.id,
      text: words.isNotEmpty
          ? joinWordsSmart(words)
          : joinWordsSmart([a.text, b.text]),
      startTime: a.startTime,
      endTime: b.endTime,
      words: words.isNotEmpty ? words : null,
      wordTimings: timings,
      translatedText: mergedTrans.isEmpty ? null : mergedTrans,
    );
    segs[index] = merged;
    segs.removeAt(index + 1);
    provider.updateSegments(segs);
    setState(() => _selectedIndex = index);
  }

  void _deleteSegment(ProjectProvider provider, int index) {
    final segs = provider.currentProject!.segments
        .map((s) => s.copy())
        .toList();
    if (index < 0 || index >= segs.length) return;
    segs.removeAt(index);
    provider.updateSegments(segs);
    setState(() => _selectedIndex = null);
  }

  void _deleteSfx(ProjectProvider provider, String id) {
    provider.removeSfxBlock(id);
    setState(() => _selectedSfxId = null);
    _toast(tr('ed.sfxDeleted'));
  }

  /// Duplicate an SFX block (offset 300ms later) and select the copy.
  void _duplicateSfx(ProjectProvider provider, String id) {
    final project = provider.currentProject;
    if (project == null) return;
    final src = project.sfxBlocks.where((b) => b.id == id).firstOrNull;
    if (src == null) return;
    final copy = src.copy(newId: const Uuid().v4());
    copy.startTime = src.startTime + const Duration(milliseconds: 300);
    provider.addSfxBlock(copy);
    setState(() => _selectedSfxId = copy.id);
    _toast(tr('ed.sfxCopied'));
  }

  /// Split an SFX block at the current playhead into two blocks.
  void _splitSfxAtPlayhead(ProjectProvider provider, String id) {
    final project = provider.currentProject;
    if (project == null) return;
    final block = project.sfxBlocks.where((b) => b.id == id).firstOrNull;
    if (block == null) return;
    final posMs = _position.inMilliseconds;
    final startMs = block.startTime.inMilliseconds;
    final fullLen = block.isCustom
        ? (block.duration?.inMilliseconds ?? 1000)
        : block.type.defaultDuration.inMilliseconds;
    final curDur = block.duration?.inMilliseconds ?? fullLen;
    final curTrim = block.trimStart?.inMilliseconds ?? 0;
    final cutOffset = posMs - startMs; // ms into the block
    if (cutOffset < 100 || cutOffset > curDur - 100) {
      _toast(tr('ed.movePlayheadSfx'));
      return;
    }
    provider.pushHistory();
    // First half keeps start, shortened duration.
    block.duration = Duration(milliseconds: cutOffset);
    // Second half: new block starting at playhead, trimmed forward.
    final second = block.copy(newId: const Uuid().v4());
    second.startTime = Duration(milliseconds: posMs);
    second.trimStart = Duration(milliseconds: curTrim + cutOffset);
    second.duration = Duration(milliseconds: curDur - cutOffset);
    provider.addSfxBlock(second);
    setState(() => _selectedSfxId = second.id);
    _toast(tr('ed.sfxSplit'));
  }

  /// Per-block SFX volume sheet.
  void _showBlockVolumeSheet(ProjectProvider provider, String id) {
    final project = provider.currentProject;
    if (project == null) return;
    final block = project.sfxBlocks.where((b) => b.id == id).firstOrNull;
    if (block == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('ed.sfxAudioLabel', {'name': block.isCustom ? (block.customName ?? "AUDIO") : block.type.name.toUpperCase()}),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: block.volume.clamp(0.0, 1.0),
                            min: 0.0,
                            max: 1.0,
                            activeColor: AppColors.primary,
                            inactiveColor: AppColors.border,
                            onChanged: (v) {
                              setSheet(() => block.volume = v);
                              provider.liveUpdate();
                            },
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text('${(block.volume * 100).round()}%',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() => provider.commit());
  }

  /// "Split" the AI voice track at the playhead = trim its tail to playhead.
  void _splitAiVoiceAtPlayhead(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null || project.aiVoicePath == null) return;
    final relMs = _position.inMilliseconds - project.aiVoiceOffsetMs;
    final fullMs = project.aiVoiceDurationMs ?? 0;
    final trimStart = project.aiVoiceTrimStartMs;
    final newEndSource = (trimStart + relMs);
    if (relMs < 100 || newEndSource >= fullMs) {
      _toast(tr('ed.movePlayheadAiTrack'));
      return;
    }
    provider.pushHistory();
    project.aiVoiceTrimEndMs = newEndSource.clamp(trimStart + 100, fullMs);
    provider.commit();
    setState(() {});
    _toast(tr('ed.aiTrackTrimmed'));
  }

  
  Widget _buildSfxTile(BuildContext context, ProjectProvider provider, SfxType type, String emoji, String title, String subtitle) {
    // Tap the row (or the play button) to PREVIEW the sound without closing the
    // sheet; tap the + button to add it to the timeline at the playhead.
    // Show Thai labels when the UI language is Thai (Lao literals are the default).
    final th = I18n.isThai ? _sfxThai[type] : null;
    final dispTitle = th?.$1 ?? title;
    final dispSub = th?.$2 ?? subtitle;
    return ListTile(
      leading: Text(emoji, style: const TextStyle(fontSize: 24)),
      title: Text(dispTitle, style: const TextStyle(color: Colors.white)),
      subtitle: Text(dispSub, style: const TextStyle(color: Colors.white54)),
      onTap: () => SfxPlayerService().playSfx(type),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_circle_outline, color: Colors.white70),
            tooltip: tr('ed.play'),
            onPressed: () => SfxPlayerService().playSfx(type),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle, color: AppColors.primary),
            tooltip: tr('ed.add'),
            onPressed: () {
              Navigator.pop(context);
              provider.addSfxBlock(SfxBlock(
                id: const Uuid().v4(),
                type: type,
                startTime: _position,
              ));
              _toast(tr('ed.sfxAdded', {'title': title}));
            },
          ),
        ],
      ),
    );
  }


  void _duplicateSegment(ProjectProvider provider, int index) {
    final segs = provider.currentProject!.segments
        .map((s) => s.copy())
        .toList();
    if (index < 0 || index >= segs.length) return;
    final s = segs[index];
    final dur = s.endTime - s.startTime;
    segs.insert(
      index + 1,
      SubtitleSegment(
        id: _newId(0),
        text: s.text,
        startTime: s.endTime,
        endTime: s.endTime + dur,
        translatedText: s.translatedText,
        words: s.words != null ? List.of(s.words!) : null,
        wordTimings: s.wordTimings != null
            ? s.wordTimings!.map((t) => t + dur).toList()
            : null,
      ),
    );
    provider.updateSegments(segs);
    setState(() => _selectedIndex = index + 1);
  }

  void _addAtPlayhead(ProjectProvider provider) {
    final segs = provider.currentProject!.segments
        .map((s) => s.copy())
        .toList();
    final start = _position;
    var end = start + const Duration(seconds: 2);
    if (_duration > Duration.zero && end > _duration) end = _duration;
    final ns = SubtitleSegment(
      id: _newId(0),
      text: tr('ed.newText'),
      startTime: start,
      endTime: end,
    );
    segs.add(ns);
    segs.sort((a, b) => a.startTime.compareTo(b.startTime));
    provider.updateSegments(segs);
    final idx = segs.indexWhere((x) => x.id == ns.id);
    setState(() => _selectedIndex = idx);
    _editSegment(ns, idx, provider);
  }

  Widget _miniIcon(IconData icon, VoidCallback onTap, {bool filled = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 30,
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: filled ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Icon(
          icon,
          size: 17,
          color: filled ? Colors.white : AppColors.textSecondary,
        ),
      ),
    );
  }

  // ── Per-segment style editor (Timeline → select block → 🎨 ສໄຕລ໌) ────────
  void _showSegmentStyleSheet(
    SubtitleSegment seg,
    int index,
    ProjectProvider provider,
  ) {
    final project = provider.currentProject!;
    const palette = <Color>[
      Colors.white,
      Colors.black,
      Color(0xFFFFC107),
      Color(0xFFFF6B6B),
      Color(0xFF39FF14),
      Color(0xFF4FC3F7),
      Color(0xFFFF6BDE),
      Color(0xFF9C59F5),
    ];
    final animLabels = {
      SubtitleAnimation.none: tr('ed.none'),
      SubtitleAnimation.fadeIn: 'Fade',
      SubtitleAnimation.slideUp: tr('ed.slideUp'),
      SubtitleAnimation.slideDown: tr('ed.slideDown'),
      SubtitleAnimation.slideLeft: tr('ed.slideLeft'),
      SubtitleAnimation.bounceIn: tr('ed.bounce'),
      SubtitleAnimation.typewriter: tr('ed.typewriter'),
    };

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            void update(VoidCallback change) {
              change();
              provider.commit();
              setSheet(() {});
              setState(() {});
            }

            Widget chip(
              String label,
              bool active,
              VoidCallback onTap,
            ) => GestureDetector(
              onTap: onTap,
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: active ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: active ? Colors.white : AppColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            );

            Widget sectionTitle(String t) => Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                t,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            );

            final eff = _effectiveStyle(project, seg);

            return DraggableScrollableSheet(
              expand: false,
              // Open compact so the video preview above stays visible while
              // styling; drag up (snaps) to see every option.
              initialChildSize: 0.45,
              maxChildSize: 0.92,
              minChildSize: 0.3,
              snap: true,
              snapSizes: const [0.45, 0.92],
              builder: (ctx, scrollCtrl) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: ListView(
                  controller: scrollCtrl,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.palette_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr('ed.segStyle'),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (seg.hasStyleOverride)
                          TextButton.icon(
                            onPressed: () =>
                                update(() => seg.clearStyleOverride()),
                            icon: const Icon(Icons.restart_alt, size: 16),
                            label: Text(tr('ed.clear')),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                    Text(
                      '"${seg.text}"',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12,
                      ),
                    ),

                    // ── Style preset ──
                    sectionTitle(tr('ed.tab.style')),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          chip(
                            tr('ed.default'),
                            seg.styleIndex == null,
                            () => update(() => seg.styleIndex = null),
                          ),
                          for (int i = 0; i < subtitlePresets.length; i++)
                            chip(
                              subtitlePresets[i].isPro && !_isPro
                                  ? '🔒 ${subtitlePresets[i].name}'
                                  : subtitlePresets[i].name,
                              seg.styleIndex == i,
                              () {
                                if (subtitlePresets[i].isPro && !_isPro) {
                                  Navigator.pop(context);
                                  _showProFeatureDialog(
                                    tr('ed.styleProDialog', {'name': subtitlePresets[i].name}),
                                  );
                                  return;
                                }
                                update(() => seg.styleIndex = i);
                              },
                            ),
                        ],
                      ),
                    ),

                    // ── Font ──
                    sectionTitle(tr('ed.font')),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          chip(
                            tr('ed.default'),
                            seg.fontFamily == null,
                            () => update(() => seg.fontFamily = null),
                          ),
                          for (final f in _laoFonts)
                            chip(
                              f.$2,
                              seg.fontFamily == f.$1,
                              () => update(() => seg.fontFamily = f.$1),
                            ),
                          for (final cf in CustomFontService.fonts)
                            chip(
                              cf.name,
                              seg.fontFamily ==
                                  CustomFontService.familyKey(cf.id),
                              () => update(
                                () => seg.fontFamily =
                                    CustomFontService.familyKey(cf.id),
                              ),
                            ),
                        ],
                      ),
                    ),

                    // ── Text color ──
                    sectionTitle(tr('ed.textColor')),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => update(() => seg.textColorValue = null),
                          child: Container(
                            width: 34,
                            height: 34,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: seg.textColorValue == null
                                    ? AppColors.primary
                                    : AppColors.border,
                                width: seg.textColorValue == null ? 2 : 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.format_color_reset,
                              size: 16,
                              color: AppColors.textHint,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final c in palette)
                                GestureDetector(
                                  onTap: () => update(
                                    () => seg.textColorValue = c.value,
                                  ),
                                  child: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: c,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: seg.textColorValue == c.value
                                            ? AppColors.primary
                                            : AppColors.border,
                                        width: seg.textColorValue == c.value
                                            ? 3
                                            : 1,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // ── Font size ──
                    sectionTitle(tr('ed.sizeWith', {'n': eff.fontSize.toStringAsFixed(0)})),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            min: 10,
                            max: 60,
                            value: eff.fontSize.clamp(10, 60),
                            activeColor: AppColors.primary,
                            onChanged: (v) {
                              seg.fontSize = v;
                              provider.liveUpdate();
                              setSheet(() {});
                            },
                            onChangeEnd: (_) => update(() {}),
                          ),
                        ),
                        if (seg.fontSize != null)
                          GestureDetector(
                            onTap: () => update(() => seg.fontSize = null),
                            child: const Icon(
                              Icons.restart_alt,
                              size: 18,
                              color: AppColors.textHint,
                            ),
                          ),
                      ],
                    ),

                    // ── Weight ──
                    sectionTitle(tr('ed.weight')),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          chip(
                            tr('ed.default'),
                            seg.fontWeight == null,
                            () => update(() => seg.fontWeight = null),
                          ),
                          chip(
                            tr('ed.thin'),
                            seg.fontWeight == 300,
                            () => update(() => seg.fontWeight = 300),
                          ),
                          chip(
                            tr('ed.regular'),
                            seg.fontWeight == 400,
                            () => update(() => seg.fontWeight = 400),
                          ),
                          chip(
                            tr('ed.bold'),
                            seg.fontWeight == 700,
                            () => update(() => seg.fontWeight = 700),
                          ),
                          chip(
                            tr('ed.boldest'),
                            seg.fontWeight == 900,
                            () => update(() => seg.fontWeight = 900),
                          ),
                        ],
                      ),
                    ),

                    // ── Animation ──
                    sectionTitle(tr('ed.animation')),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          chip(
                            tr('ed.default'),
                            seg.animation == null,
                            () => update(() => seg.animation = null),
                          ),
                          for (final a in SubtitleAnimation.values)
                            chip(
                              animLabels[a] ?? a.name,
                              seg.animation == a,
                              () => update(() => seg.animation = a),
                            ),
                        ],
                      ),
                    ),

                    // ── Karaoke (colour sweep) for this single phrase ──
                    sectionTitle(tr('ed.karaoke')),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          chip(
                            tr('ed.default'),
                            seg.karaoke == null,
                            () => update(() => seg.karaoke = null),
                          ),
                          chip(
                            _isPro ? tr('ed.on') : '🔒 ${tr('ed.on')}',
                            seg.karaoke == true,
                            () {
                              if (!_isPro) {
                                _showProFeatureDialog(tr('ed.karaokeProDialog'));
                                return;
                              }
                              update(() => seg.karaoke = true);
                            },
                          ),
                          chip(
                            tr('ed.off'),
                            seg.karaoke == false,
                            () => update(() => seg.karaoke = false),
                          ),
                        ],
                      ),
                    ),
                    if (eff.karaoke) ...[
                      // ── Word Pop (enlarge the active word) ──
                      sectionTitle(tr('ed.wordPop')),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            chip(
                              tr('ed.default'),
                              seg.karaokeScale == null,
                              () => update(() => seg.karaokeScale = null),
                            ),
                            chip(
                              tr('ed.on'),
                              seg.karaokeScale == true,
                              () => update(() => seg.karaokeScale = true),
                            ),
                            chip(
                              tr('ed.off'),
                              seg.karaokeScale == false,
                              () => update(() => seg.karaokeScale = false),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ── Position ──
                    sectionTitle(
                      tr('ed.subVPosition', {'p': (eff.positionY * 100).toStringAsFixed(0)}),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            min: 0.05,
                            max: 0.95,
                            value: eff.positionY.clamp(0.05, 0.95),
                            activeColor: AppColors.primary,
                            onChanged: (v) {
                              seg.positionY = v;
                              provider.liveUpdate();
                              setSheet(() {});
                            },
                            onChangeEnd: (_) => update(() {}),
                          ),
                        ),
                        if (seg.positionY != null)
                          GestureDetector(
                            onTap: () => update(() => seg.positionY = null),
                            child: const Icon(
                              Icons.restart_alt,
                              size: 18,
                              color: AppColors.textHint,
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 18),
                    // ── Apply to all segments ──
                    OutlinedButton.icon(
                      onPressed: () {
                        update(() {
                          for (final other in project.segments) {
                            if (identical(other, seg)) continue;
                            other.styleIndex = seg.styleIndex;
                            other.fontFamily = seg.fontFamily;
                            other.fontSize = seg.fontSize;
                            other.fontWeight = seg.fontWeight;
                            other.textColorValue = seg.textColorValue;
                            other.animation = seg.animation;
                            other.positionY = seg.positionY;
                          }
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(tr('ed.appliedAll')),
                            backgroundColor: AppColors.surface,
                          ),
                        );
                      },
                      icon: const Icon(Icons.done_all, size: 18),
                      label: Text(tr('ed.applyAll')),
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

  /// ແຕະໃຫ້ຕົງ — Tap Sync screen; it saves the segments as ONE undo step.
  Future<void> _openTapSync() async {
    if (_isPlaying) await _togglePlay();
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TapSyncScreen(clipPlayer: _clipPlayer),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      setState(() {});
      _toast(tr('tap.saved'));
    }
  }

  Widget _buildSyncBar(ProjectProvider provider) {
    final offsetSec = (_syncOffsetMs / 1000).toStringAsFixed(1);
    final offsetLabel = _syncOffsetMs > 0 ? '+${offsetSec}s' : '${offsetSec}s';

    Widget btn(String label, int deltaMs) => GestureDetector(
      onTap: () => _nudgeSync(provider, deltaMs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _autoSyncing ? null : () => _autoSync(provider),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primaryDark, AppColors.primary],
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_autoSyncing)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      else
                        const Icon(
                          Icons.auto_awesome,
                          color: Colors.white,
                          size: 15,
                        ),
                      const SizedBox(width: 6),
                      Text(
                        _autoSyncing ? tr('ed.syncing') : tr('ed.auto'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _openTapSync,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.touch_app,
                          color: AppColors.success, size: 15),
                      const SizedBox(width: 4),
                      Text(
                        tr('tap.button'),
                        style: const TextStyle(
                          color: AppColors.success,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      btn('-0.5', -500),
                      const SizedBox(width: 6),
                      btn('-0.1', -100),
                      const SizedBox(width: 6),
                      btn('-0.05', -50),
                      const SizedBox(width: 10),
                      Container(
                        constraints: const BoxConstraints(minWidth: 54),
                        alignment: Alignment.center,
                        child: Text(
                          offsetLabel,
                          style: TextStyle(
                            color: _syncOffsetMs == 0
                                ? AppColors.textHint
                                : AppColors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      btn('+0.05', 50),
                      const SizedBox(width: 6),
                      btn('+0.1', 100),
                      const SizedBox(width: 6),
                      btn('+0.5', 500),
                    ],
                  ),
                ),
              ),
              if (_syncOffsetMs != 0) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    provider.shiftAllSegments(
                      Duration(milliseconds: -_syncOffsetMs),
                    );
                    setState(() => _syncOffsetMs = 0);
                  },
                  child: const Icon(
                    Icons.restart_alt,
                    color: AppColors.textHint,
                    size: 20,
                  ),
                ),
              ],
            ],
          ),
          // Continuous fine offset: drag to slide ALL subtitles earlier/later
          // (±2s). Stays in sync with the nudge buttons and the reset above.
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              min: -2000,
              max: 2000,
              value: _syncOffsetMs.clamp(-2000, 2000).toDouble(),
              activeColor: AppColors.primary,
              onChanged: (v) {
                final delta = v.round() - _syncOffsetMs;
                if (delta != 0) _nudgeSync(provider, delta);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReSplitBtn(
    String label,
    WordSplit split,
    ProjectProvider provider,
  ) {
    final project = provider.currentProject!;
    final isActive = project.wordSplit == split;
    return GestureDetector(
      onTap: () => _reSplitSegments(split, provider),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// Re-split using the stored word units + per-word timestamps so it works for
  /// Lao (tight text) AND keeps each word on its real spoken time.
  void _reSplitSegments(WordSplit split, ProjectProvider provider) {
    final project = provider.currentProject!;
    final segs = project.segments;
    if (segs.isEmpty) return;

    // 1. Flatten every segment into word units (text + absolute start ms).
    final words = <String>[];
    final starts = <int>[];
    for (final s in segs) {
      final segWords = (s.words != null && s.words!.isNotEmpty)
          ? s.words!
          : splitLaoHighlightUnits(s.text).where((w) => w.trim().isNotEmpty).toList();
      if (segWords.isEmpty) continue;
      final hasTimings =
          s.wordTimings != null && s.wordTimings!.length == segWords.length;
      final segStart = s.startTime.inMilliseconds;
      final segDur = (s.endTime.inMilliseconds - segStart).clamp(1, 1 << 31);
      for (int i = 0; i < segWords.length; i++) {
        words.add(segWords[i]);
        starts.add(
          hasTimings
              ? s.wordTimings![i].inMilliseconds
              : segStart + (segDur * i ~/ segWords.length),
        );
      }
    }
    if (words.isEmpty) return;
    final lastEnd = segs.last.endTime.inMilliseconds;

    final perGroup = switch (split) {
      WordSplit.one => 1,
      WordSplit.two => 2,
      WordSplit.three => 3,
      WordSplit.four => 4,
      WordSplit.six => 6,
      WordSplit.eight => 8,
      WordSplit.none => 0,
    };

    int idc = 0;
    String mkId() => '${DateTime.now().microsecondsSinceEpoch}_${idc++}';
    final result = <SubtitleSegment>[];

    SubtitleSegment build(List<String> gw, List<int> gs, int endMs) {
      final st = gs.first;
      return SubtitleSegment(
        id: mkId(),
        text: joinWordsSmart(gw),
        startTime: Duration(milliseconds: st),
        endTime: Duration(milliseconds: endMs < st + 200 ? st + 200 : endMs),
        wordTimings: gs.map((m) => Duration(milliseconds: m)).toList(),
        words: List.of(gw),
      );
    }

    if (perGroup > 0) {
      for (int i = 0; i < words.length; i += perGroup) {
        final end = (i + perGroup).clamp(0, words.length);
        final segEnd = end < words.length ? starts[end] : lastEnd;
        result.add(
          build(words.sublist(i, end), starts.sublist(i, end), segEnd),
        );
      }
    } else {
      // Auto: break on a pause (>=400ms between word starts) or max 5 words.
      var gw = <String>[];
      var gs = <int>[];
      for (int i = 0; i < words.length; i++) {
        gw.add(words[i]);
        gs.add(starts[i]);
        final isLast = i == words.length - 1;
        final gap = isLast ? 1 << 30 : starts[i + 1] - starts[i];
        if (gw.length >= 5 || gap >= 400 || isLast) {
          final segEnd = isLast ? lastEnd : starts[i + 1];
          result.add(build(gw, gs, segEnd));
          gw = [];
          gs = [];
        }
      }
    }

    project.wordSplit = split;
    provider.updateSegments(result);
  }

  Widget _buildSegmentCard(
    SubtitleSegment segment,
    int index,
    ProjectProvider provider, {
    bool showTranslation = false,
  }) {
    final isActive = _activeSegmentIndex == index;
    final durMs =
        (segment.endTime - segment.startTime).inMilliseconds.clamp(0, 1 << 31);
    final durLabel = '${(durMs / 1000).toStringAsFixed(1)}s';
    return GestureDetector(
      onTap: () {
        _seekTo(segment.startTime);
        setState(() => _activeSegmentIndex = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 9, 6, 10),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withOpacity(0.15)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── header: number · time range · duration · actions ──
            Row(
              children: [
                Container(
                  width: 22,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.primary : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text('${index + 1}',
                      style: TextStyle(
                          color: isActive ? Colors.white : AppColors.textHint,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Icon(Icons.schedule,
                    size: 11, color: AppColors.textHint),
                const SizedBox(width: 3),
                Text(
                  '${_formatDuration(segment.startTime)} → ${_formatDuration(segment.endTime)}',
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(durLabel,
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.my_location,
                      color: AppColors.primary, size: 17),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  tooltip: tr('ed.setStartTip2'),
                  onPressed: () =>
                      _setSegmentStartToPlayhead(segment, index, provider),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      color: AppColors.textHint, size: 17),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                  onPressed: () => _editSegment(segment, index, provider),
                ),
              ],
            ),
            const SizedBox(height: 5),
            // ── subtitle text (the main content — bigger, readable) ──
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                segment.text,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  height: 1.3,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (showTranslation && segment.translatedText != null) ...[
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  segment.translatedText!,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12.5,
                    fontStyle: FontStyle.italic,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Move a single subtitle so it starts at the current video playhead,
  /// keeping its duration (end + word timings shift by the same amount).
  void _setSegmentStartToPlayhead(
    SubtitleSegment segment,
    int index,
    ProjectProvider provider,
  ) {
    final segs = provider.currentProject!.segments;
    if (index < 0 || index >= segs.length) return;
    final delta = _position - segs[index].startTime;
    if (delta == Duration.zero) return;
    Duration clamp(Duration d) => d < Duration.zero ? Duration.zero : d;
    final s = segs[index];
    s.startTime = clamp(s.startTime + delta);
    s.endTime = clamp(s.endTime + delta);
    if (s.wordTimings != null) {
      s.wordTimings = s.wordTimings!.map((t) => clamp(t + delta)).toList();
    }
    provider.updateSegments(segs);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('ed.setStartAt', {'t': _formatDuration(_position)})),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _editSegment(
    SubtitleSegment segment,
    int index,
    ProjectProvider provider,
  ) {
    final textCtrl = TextEditingController(text: segment.text);
    final transCtrl = TextEditingController(text: segment.translatedText ?? '');
    Duration startTime = segment.startTime;
    Duration endTime = segment.endTime;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('ed.editSubtitle'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: textCtrl,
                label: tr('ed.row1'),
                hint: tr('ed.subtitleTextHint'),
                autofocus: true,
                accentColor: AppColors.primary,
              ),
              const SizedBox(height: 10),
              _buildTextField(
                controller: transCtrl,
                label: tr('ed.row2'),
                hint: tr('ed.translationHint'),
                accentColor: const Color(0xFFFFB300),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Timestamp',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTimeEditor(
                            label: tr('ed.start'),
                            time: startTime,
                            maxTime:
                                endTime - const Duration(milliseconds: 100),
                            onChanged: (t) =>
                                setModalState(() => startTime = t),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(
                            Icons.arrow_forward,
                            color: AppColors.textHint,
                            size: 16,
                          ),
                        ),
                        Expanded(
                          child: _buildTimeEditor(
                            label: tr('ed.end'),
                            time: endTime,
                            maxTime: _duration,
                            onChanged: (t) => setModalState(() => endTime = t),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  final trans = transCtrl.text.trim();
                  final newText = textCtrl.text.trim();
                  final updated = provider.currentProject!.segments;
                  final s = updated[index];
                  final textChanged = newText != s.text;
                  if (textChanged) {
                    s.words = null;
                    s.wordTimings = null;
                  }
                  s.text = newText;
                  s.startTime = startTime;
                  s.endTime = endTime;
                  s.translatedText = trans.isEmpty ? null : trans;
                  // Re-derive word-level karaoke units for the new wording.
                  if (textChanged) {
                    try {
                      await LaoWordService.ensureWordUnits([
                        s,
                      ], locale: provider.currentProject!.language);
                    } catch (_) {}
                  }
                  provider.updateSegments(updated);
                  if (trans.isNotEmpty && !provider.showTranslation) {
                    provider.toggleShowTranslation();
                  }
                  if (context.mounted) Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: Text(tr('common.save')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeEditor({
    required String label,
    required Duration time,
    required Duration maxTime,
    required ValueChanged<Duration> onChanged,
  }) {
    final totalMs = maxTime.inMilliseconds.toDouble();
    final currentMs = time.inMilliseconds.toDouble().clamp(0, totalMs);
    void nudge(int ms) {
      final nv = (time.inMilliseconds + ms).clamp(0, maxTime.inMilliseconds);
      onChanged(Duration(milliseconds: nv));
    }

    Widget stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, color: AppColors.primary, size: 16),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textHint, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            stepBtn(Icons.remove, () => nudge(-100)),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                alignment: Alignment.center,
                child: Text(
                  _formatDuration(time),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            stepBtn(Icons.add, () => nudge(100)),
          ],
        ),
        Slider(
          value: currentMs.toDouble(),
          max: totalMs > 0 ? totalMs.toDouble() : 1.0,
          activeColor: AppColors.primary,
          inactiveColor: AppColors.border,
          onChanged: totalMs > 0
              ? (v) => onChanged(Duration(milliseconds: v.toInt()))
              : null,
        ),
      ],
    );
  }
}
