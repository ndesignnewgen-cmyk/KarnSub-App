part of '../editor_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Auto tools: auto sync/meme/B-roll/hook/edit/emoji/caption, AI sync.
/// Split out of editor_screen.dart verbatim (phase 0) — the
/// fields and lifecycle stay in [_EditorScreenState].
extension _EditorAuto on _EditorScreenState {
  /// Auto-sync: detect where speech actually starts in the audio (native VAD),
  /// then correct the systematic offset and snap each segment to a nearby
  /// speech onset (via AudioSyncService). One undo step; falls back gracefully.
  Future<void> _autoSync(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null ||
        project.videoPath == null ||
        project.segments.isEmpty) {
      return;
    }
    setState(() => _autoSyncing = true);
    try {
      final segs = project.segments.map((s) => s.copy()).toList();
      
      // Re-segment Lao/Thai syllables into dictionary units to ensure timing is always precise (e.g. if edited)
      await LaoWordService.ensureWordUnits(segs, locale: project.language);
      
      final groqKey = await ApiConfig.getGroqKey();
      final openAiKey = await ApiConfig.getOpenAiKey();
      final hasGroq = groqKey != null && groqKey.isNotEmpty;
      final hasOpenAi = openAiKey != null && openAiKey.isNotEmpty;

      bool whisperSuccess = false;
      if (hasGroq || hasOpenAi) {
        try {
          final lang = project.language == 'lo' ? 'th' : project.language;
          final wt = hasGroq
              ? await GroqSpeechService(apiKey: groqKey)
                  .fetchWordTimings(project.videoPath!, language: lang)
              : await OpenAIWhisperService(apiKey: openAiKey!)
                  .fetchWordTimings(project.videoPath!, language: lang);
                  
          if (project.wordSplit == WordSplit.none && wt.startsMs.length >= 3) {
            // DTW: keep your grouping, but align every word to its REAL onset.
            AudioSyncService.dtwAlignToWhisper(segs, wt.startsMs, wt.endMs);
            whisperSuccess = true;
          } else if (wt.regions.length >= 2) {
            final maxWords = switch (project.wordSplit) {
              WordSplit.one => 1,
              WordSplit.two => 2,
              WordSplit.three => 3,
              WordSplit.four => 4,
              WordSplit.six => 6,
              WordSplit.eight => 8,
              WordSplit.none => 6,
            };
            final newSegs = AudioSyncService.resegmentByRegions(segs, wt.regions, maxWords: maxWords);
            // DTW-align the re-cut blocks to real onsets (accurate start + end).
            if (wt.startsMs.length >= 3) {
              AudioSyncService.dtwAlignToWhisper(newSegs, wt.startsMs, wt.endMs);
            } else {
              AudioSyncService.snapToOnsets(newSegs, wt.startsMs);
            }
            segs.clear();
            segs.addAll(newSegs);
            whisperSuccess = true;
          } else if (wt.startsMs.length >= 3) {
            AudioSyncService.dtwAlignToWhisper(segs, wt.startsMs, wt.endMs);
            whisperSuccess = true;
          }
        } catch (e) {
          debugPrint('Whisper sync failed: $e');
        }
      }

      int changed = 0;
      if (!whisperSuccess) {
        // Fallback to local VAD Region/Onset alignment
        final regions = await AudioSyncService.detectSpeechRegions(project.videoPath!);
        if (regions.length >= 2) {
          changed = AudioSyncService.alignToRegions(segs, regions);
        } else {
          final onsets = await AudioSyncService.detectSpeechOnsets(project.videoPath!);
          if (onsets.length < 2) {
            _toast(tr('ed.syncNotEnough'));
            if (mounted) setState(() => _autoSyncing = false);
            return;
          }
          changed = AudioSyncService.alignToOnsets(segs, onsets);
        }
      }

      provider.updateSegments(segs); // single undo step
      setState(() => _syncOffsetMs = 0);
      _toast(whisperSuccess ? tr('ed.whisperSync100') : tr('ed.syncDone', {'n': changed}));
    } catch (_) {
      _toast(tr('ed.syncFail'));
    } finally {
      if (mounted) setState(() => _autoSyncing = false);
    }
  }

  /// Strong AI sync: align each subtitle's start AND end to the real spoken
  /// phrase (front + back), stretching/shrinking to fit. One undo step.
  /// Auto ✨ — ask Gemini to pick an emoji + the punch word for every line,
  /// then highlight/enlarge those words and append the emoji (PRO feature).
  /// Auto Meme: AI picks punchy moments → fetches a matching meme GIF →
  /// inserts it as an overlay at that subtitle's time (capped, best-effort).
  Future<void> _autoMeme(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null || project.segments.isEmpty) {
      _toast(tr('ed.noSubtitle'));
      return;
    }
    if (!_isPro) {
      _showProFeatureDialog(tr('ed.autoMemePro'));
      return;
    }
    final apiKey = await ApiConfig.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _toast(tr('proc.noGeminiKey'));
      return;
    }
    _pauseForEdit();

    // Choose target segments: prefer ones with an emoji; else spread out. Cap 6.
    const cap = 6;
    final segs = project.segments;
    var idxs = <int>[];
    for (int i = 0; i < segs.length; i++) {
      if ((segs[i].emoji ?? '').isNotEmpty) idxs.add(i);
    }
    if (idxs.isEmpty) {
      final stepN = (segs.length / cap).ceil().clamp(1, segs.length);
      for (int i = 0; i < segs.length; i += stepN) {
        idxs.add(i);
      }
    }
    if (idxs.length > cap) {
      // keep an even spread of `cap` items
      final picked = <int>[];
      final stride = idxs.length / cap;
      for (int k = 0; k < cap; k++) {
        picked.add(idxs[(k * stride).floor()]);
      }
      idxs = picked;
    }

    String status = tr('ed.autoMemeTitle');
    void Function(void Function())? setDlg;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: StatefulBuilder(builder: (ctx, sd) {
          setDlg = sd;
          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 6),
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(status,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  textAlign: TextAlign.center),
            ]),
          );
        }),
      ),
    );

    int added = 0;
    try {
      final texts = idxs.map((i) => segs[i].text).toList();
      final queries =
          await GeminiSpeechService(apiKey: apiKey).suggestMemeQueries(texts);
      final tenorKey = await ApiConfig.getTenorKey();
      provider.pushHistory();
      for (int k = 0; k < idxs.length; k++) {
        final q = (k < queries.length ? queries[k] : '').trim();
        if (q.isEmpty) continue;
        setDlg?.call(() => status = tr('ed.autoMemeStep', {'i': k + 1, 'n': idxs.length}));
        final memes =
            await ImageSearchService.searchMeme(q, userKey: tenorKey, limit: 1);
        if (memes.isEmpty) continue;
        final path = await ImageSearchService.download(memes.first.full,
            fallbackUrl: memes.first.thumb);
        if (path == null) continue;
        final seg = segs[idxs[k]];
        final endMs = seg.endTime.inMilliseconds > seg.startTime.inMilliseconds
            ? seg.endTime.inMilliseconds
            : seg.startTime.inMilliseconds + 2500;
        provider.addImageOverlay(ImageOverlay(
          id: const Uuid().v4(),
          path: path,
          startTime: seg.startTime,
          endTime: Duration(milliseconds: endMs),
          x: 0.5,
          y: 0.28, // upper area, clear of the bottom subtitle
          scale: 0.46,
        ));
        added++;
      }
      provider.commit();
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() {});
        _toast(added > 0
            ? tr('ed.autoMemeDone', {'n': added})
            : tr('ed.autoMemeNone'));
      }
    } catch (_) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _toast(tr('ed.autoMemeNone'));
      }
    }
  }

  /// Core of Auto B-roll (NO own UI / history): pick photogenic moments, fetch a
  /// stock clip (video → photo fallback) and drop each as a full-screen B-roll
  /// overlay. Returns how many were added. [onStep] reports progress (i of n).
  /// Caller handles pushHistory()/commit() and the progress dialog.
  Future<int> _runAutoBrollCore(
    ProjectProvider provider,
    String apiKey, {
    void Function(int i, int n)? onStep,
    bool photoOnly = false,
  }) async {
    final project = provider.currentProject;
    if (project == null || project.segments.isEmpty) return 0;
    const cap = 8;
    final segs = project.segments;
    var idxs = <int>[for (int i = 0; i < segs.length; i++) i];
    idxs = idxs.where((i) => segs[i].text.trim().length >= 6).toList();
    if (idxs.isEmpty) idxs = [for (int i = 0; i < segs.length; i++) i];
    if (idxs.length > cap) {
      final picked = <int>[];
      final stride = idxs.length / cap;
      for (int k = 0; k < cap; k++) {
        picked.add(idxs[(k * stride).floor()]);
      }
      idxs = picked;
    }
    final texts = idxs.map((i) => segs[i].text).toList();
    final queries =
        await GeminiSpeechService(apiKey: apiKey).suggestBrollQueries(texts);
    int added = 0;
    for (int k = 0; k < idxs.length; k++) {
      final q = (k < queries.length ? queries[k] : '').trim();
      if (q.isEmpty) continue;
      onStep?.call(k + 1, idxs.length);
      String? path;
      bool isVid = false;
      if (!photoOnly) {
        final vids = await ImageSearchService.searchVideo(q, limit: 4);
        if (vids.isNotEmpty) {
          path = await ImageSearchService.downloadVideo(vids.first);
          isVid = path != null;
        }
      }
      if (path == null) {
        final imgs = await ImageSearchService.search(q, limit: 3);
        if (imgs.isNotEmpty) {
          path = await ImageSearchService.download(imgs.first.full,
              fallbackUrl: imgs.first.thumb);
        }
      }
      if (path == null) continue;
      final seg = segs[idxs[k]];
      final endMs = seg.endTime.inMilliseconds > seg.startTime.inMilliseconds
          ? seg.endTime.inMilliseconds
          : seg.startTime.inMilliseconds + 2500;
      provider.addImageOverlay(ImageOverlay(
        id: const Uuid().v4(),
        path: path,
        startTime: seg.startTime,
        endTime: Duration(milliseconds: endMs),
        x: 0.5,
        y: 0.40,
        scale: 1.0,
        isVideo: isVid,
        cover: true,
      ));
      added++;
    }
    return added;
  }

  /// Auto Edit: fade IN from black at the very start + fade OUT to black at the
  /// very end. Skips if any fade already exists (so re-runs don't stack).
  void _addAutoFades(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null || project.fadeEffects.isNotEmpty) return;
    final durMs = _duration.inMilliseconds;
    if (durMs < 1200) return;
    provider.addFadeEffect(FadeEffect(
      id: const Uuid().v4(),
      startTime: Duration.zero,
      endTime: const Duration(milliseconds: 500),
      toBlack: false, // black → clear (fade in)
    ));
    provider.addFadeEffect(FadeEffect(
      id: const Uuid().v4(),
      startTime: Duration(milliseconds: durMs - 600),
      endTime: Duration(milliseconds: durMs),
      toBlack: true, // clear → black (fade out)
    ));
  }

  /// Auto Edit: a subtle punch-in zoom on up to 3 emphasised lines. Skips if any
  /// zoom already exists (so re-runs don't stack).
  void _addAutoZooms(ProjectProvider provider, List<SubtitleSegment> segs) {
    final project = provider.currentProject;
    if (project == null || project.zoomEffects.isNotEmpty) return;
    final picks = <SubtitleSegment>[];
    for (final s in segs) {
      if ((s.emphasis ?? const []).isNotEmpty) picks.add(s);
      if (picks.length >= 3) break;
    }
    for (final s in picks) {
      provider.addZoomEffect(ZoomEffect(
        id: const Uuid().v4(),
        startTime: s.startTime,
        endTime: s.endTime,
        fromScale: 1.0,
        toScale: 1.12,
        focusX: 0.5,
        focusY: 0.45,
      ));
    }
  }

  Future<void> _loadAutoEditSteps() async {
    if (_autoEditStepsLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in _autoEditSteps.keys.toList()) {
        final v = prefs.getBool('autoedit_$k');
        if (v != null) _autoEditSteps[k] = v;
      }
    } catch (_) {}
    _autoEditStepsLoaded = true;
  }

  Future<void> _saveAutoEditSteps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final e in _autoEditSteps.entries) {
        await prefs.setBool('autoedit_${e.key}', e.value);
      }
    } catch (_) {}
  }

  /// Checklist sheet — tick which Auto Edit steps to run, then Start.
  void _showAutoEditChecklist(ProjectProvider provider) {
    final items = <(String, IconData, String)>[
      ('proofread', Icons.spellcheck, 'ed.aeProofread'),
      ('karaoke', Icons.music_note, 'ed.aeKaraoke'),
      ('emoji', Icons.emoji_emotions, 'ed.aeEmoji'),
      ('sfx', Icons.graphic_eq, 'ed.aeSfx'),
      ('fade', Icons.gradient, 'ed.aeFade'),
      ('zoom', Icons.zoom_in, 'ed.aeZoom'),
      ('cut', Icons.content_cut, 'ed.aeCut'),
      ('broll', Icons.movie_filter, 'ed.aeBroll'),
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.auto_fix_high, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(tr('ed.autoEditTitle'),
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 4),
                    Text(tr('ed.aePick'),
                        style: const TextStyle(
                            color: AppColors.textHint, fontSize: 12)),
                    const SizedBox(height: 4),
                    ...items.map((it) => SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: _autoEditSteps[it.$1] ?? false,
                          activeColor: AppColors.primary,
                          secondary: Icon(it.$2,
                              color: AppColors.textSecondary, size: 20),
                          title: Text(tr(it.$3),
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 14)),
                          onChanged: (v) =>
                              setSheet(() => _autoEditSteps[it.$1] = v),
                        )),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _saveAutoEditSteps();
                          _runAutoEditPipeline(provider);
                        },
                        icon: const Icon(Icons.play_arrow, color: Colors.white),
                        label: Text(tr('ed.aeRun'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  /// Auto B-roll: AI reads the transcript, picks photogenic moments, finds a
  /// matching royalty-free photo (Pixabay) and drops it as a large full-width
  /// overlay above the subtitle for that line's duration — like a B-roll cut.
  /// Auto Hook + caption + hashtags: AI writes a viral post kit from the
  /// transcript and shows it with copy buttons.
  Future<void> _autoHook(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null || project.segments.isEmpty) {
      _toast(tr('ed.noSubtitle'));
      return;
    }
    if (!_isPro) {
      _showProFeatureDialog(tr('ed.autoHookPro'));
      return;
    }
    final apiKey = await ApiConfig.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _toast(tr('proc.noGeminiKey'));
      return;
    }
    _pauseForEdit();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
    );
    Map<String, String> kit = {};
    try {
      kit = await GeminiSpeechService(apiKey: apiKey).generateHookKit(
        project.segments.map((s) => s.text).toList(),
        language: project.language,
      );
    } catch (_) {}
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!mounted) return;
    if (kit.isEmpty || (kit['hook'] ?? '').isEmpty && (kit['caption'] ?? '').isEmpty) {
      _toast(tr('ed.autoHookNone'));
      return;
    }

    Widget block(String title, String value) {
      if (value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title,
                style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                _toast(tr('ed.copied'));
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy, size: 15, color: AppColors.primary),
              ),
            ),
          ]),
          const SizedBox(height: 2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(8)),
            child: Text(value,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
          ),
        ]),
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.tag, color: Color(0xFFFFB703), size: 20),
          const SizedBox(width: 8),
          Text(tr('ed.autoHook'),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            block(tr('ed.hookLabel'), kit['hook'] ?? ''),
            block(tr('ed.captionLabel'), kit['caption'] ?? ''),
            block(tr('ed.hashtagLabel'), kit['hashtags'] ?? ''),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              final all = [
                kit['hook'] ?? '',
                '',
                kit['caption'] ?? '',
                '',
                kit['hashtags'] ?? '',
              ].join('\n').trim();
              Clipboard.setData(ClipboardData(text: all));
              Navigator.pop(ctx);
              _toast(tr('ed.copiedAll'));
            },
            child: Text(tr('ed.copyAll'),
                style: const TextStyle(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('common.close'),
                style: const TextStyle(color: AppColors.textHint)),
          ),
        ],
      ),
    );
  }

  /// Auto Visual hub: pick what to auto-insert — funny GIF (meme), stock video
  /// B-roll, or stock photo B-roll.
  void _showAutoVisualSheet(ProjectProvider provider) {
    _pauseForEdit();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        Widget opt(IconData ic, Color c, String label, String sub, VoidCallback onTap) =>
            ListTile(
              leading: Icon(ic, color: c),
              title: Text(label,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              subtitle: Text(sub,
                  style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                onTap();
              },
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Text(tr('ed.autoVisual'),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            opt(Icons.movie_creation, const Color(0xFF7C4DFF), tr('ed.avVideo'),
                tr('ed.avVideoSub'), () => _autoBroll(provider)),
            opt(Icons.image, const Color(0xFF00BFA5), tr('ed.avPhoto'),
                tr('ed.avPhotoSub'), () => _autoBroll(provider, photoOnly: true)),
            opt(Icons.gif_box, const Color(0xFFEA4C89), tr('ed.avMeme'),
                tr('ed.avMemeSub'), () => _autoMeme(provider)),
            const SizedBox(height: 12),
          ]),
        );
      },
    );
  }

  Future<void> _autoBroll(ProjectProvider provider, {bool photoOnly = false}) async {
    final project = provider.currentProject;
    if (project == null || project.segments.isEmpty) {
      _toast(tr('ed.noSubtitle'));
      return;
    }
    if (!_isPro) {
      _showProFeatureDialog(tr('ed.autoBrollPro'));
      return;
    }
    final apiKey = await ApiConfig.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _toast(tr('proc.noGeminiKey'));
      return;
    }
    _pauseForEdit();

    // Spread across the timeline: prefer longer (content-rich) lines. Cap 8.
    const cap = 8;
    final segs = project.segments;
    var idxs = <int>[for (int i = 0; i < segs.length; i++) i];
    // skip very short / filler-ish lines (< 6 chars)
    idxs = idxs.where((i) => segs[i].text.trim().length >= 6).toList();
    if (idxs.isEmpty) idxs = [for (int i = 0; i < segs.length; i++) i];
    if (idxs.length > cap) {
      final picked = <int>[];
      final stride = idxs.length / cap;
      for (int k = 0; k < cap; k++) {
        picked.add(idxs[(k * stride).floor()]);
      }
      idxs = picked;
    }

    String status = tr('ed.autoBrollTitle');
    void Function(void Function())? setDlg;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: StatefulBuilder(builder: (ctx, sd) {
          setDlg = sd;
          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 6),
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(status,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  textAlign: TextAlign.center),
            ]),
          );
        }),
      ),
    );

    int added = 0;
    try {
      final texts = idxs.map((i) => segs[i].text).toList();
      final queries =
          await GeminiSpeechService(apiKey: apiKey).suggestBrollQueries(texts);
      provider.pushHistory();
      for (int k = 0; k < idxs.length; k++) {
        final q = (k < queries.length ? queries[k] : '').trim();
        if (q.isEmpty) continue;
        setDlg?.call(
            () => status = tr('ed.autoBrollStep', {'i': k + 1, 'n': idxs.length}));
        // Prefer a stock VIDEO clip (real moving B-roll); fall back to a photo.
        String? path;
        bool isVid = false;
        if (!photoOnly) {
          final vids = await ImageSearchService.searchVideo(q, limit: 4);
          if (vids.isNotEmpty) {
            path = await ImageSearchService.downloadVideo(vids.first);
            isVid = path != null;
          }
        }
        if (path == null) {
          final imgs = await ImageSearchService.search(q, limit: 3);
          if (imgs.isNotEmpty) {
            path = await ImageSearchService.download(imgs.first.full,
                fallbackUrl: imgs.first.thumb);
          }
        }
        if (path == null) continue;
        final seg = segs[idxs[k]];
        final endMs = seg.endTime.inMilliseconds > seg.startTime.inMilliseconds
            ? seg.endTime.inMilliseconds
            : seg.startTime.inMilliseconds + 2500;
        provider.addImageOverlay(ImageOverlay(
          id: const Uuid().v4(),
          path: path,
          startTime: seg.startTime,
          endTime: Duration(milliseconds: endMs),
          x: 0.5,
          y: 0.40, // (used only if cover is turned off)
          scale: 1.0,
          isVideo: isVid,
          cover: true, // full-screen B-roll by default
        ));
        added++;
      }
      provider.commit();
      _ensureBrollControllers(provider.currentProject); // spin up preview players
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() {});
        _toast(added > 0
            ? tr('ed.autoBrollDone', {'n': added})
            : tr('ed.autoBrollNone'));
      }
    } catch (_) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _toast(tr('ed.autoBrollNone'));
      }
    }
  }

  /// 1-Tap Auto Edit: run the whole polish pipeline in one tap —
  /// Karaoke word units → emoji + highlight (Gemini) → SFX → cut silence.
  /// Each step is best-effort so a single failure never aborts the rest.
  Future<void> _autoEdit(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null || project.segments.isEmpty) {
      _toast(tr('ed.noSubtitle'));
      return;
    }
    if (!_isPro) {
      _showProFeatureDialog(tr('ed.autoEditPro'));
      return;
    }
    await _loadAutoEditSteps();
    if (!mounted) return;
    _showAutoEditChecklist(provider);
  }

  /// Runs the selected Auto Edit steps (from [_autoEditSteps]) in one pass.
  /// Each step is best-effort so a single failure never aborts the rest.
  Future<void> _runAutoEditPipeline(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null || project.segments.isEmpty) return;
    _pauseForEdit();
    final S = _autoEditSteps;

    String status = tr('ed.autoEditStepKaraoke');
    void Function(void Function())? setDlg;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: StatefulBuilder(builder: (ctx, sd) {
          setDlg = sd;
          return AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 6),
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 18),
              Text(tr('ed.autoEditTitle'),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(status,
                  style: const TextStyle(color: AppColors.textHint, fontSize: 12),
                  textAlign: TextAlign.center),
            ]),
          );
        }),
      ),
    );
    void step(String s) {
      status = s;
      setDlg?.call(() {});
    }

    // Per-step outcome (true=done, false=failed) → shown as ✓/✗ at the end so
    // the user can SEE which steps actually ran (e.g. Gemini 503 mid-pipeline).
    final results = <String, bool>{};
    try {
      provider.pushHistory();
      final segs = project.segments.map((s) => s.copy()).toList();
      final apiKey = await ApiConfig.getApiKey();
      final hasKey = apiKey != null && apiKey.isNotEmpty;

      // Proofread (fix spelling/typos) — before word-splitting.
      if (S['proofread'] == true && hasKey) {
        step(tr('ed.autoEditStepProof'));
        try {
          await GeminiSpeechService(apiKey: apiKey)
              .proofreadSegments(segments: segs, language: project.language);
          results['proofread'] = true;
        } catch (_) {
          results['proofread'] = false;
        }
      }

      // Karaoke word units (so the colour sweep moves word-by-word).
      if (S['karaoke'] == true) {
        step(tr('ed.autoEditStepKaraoke'));
        try {
          await LaoWordService.refineToRealWords(segs, locale: project.language);
          await LaoWordService.ensureWordUnits(segs, locale: project.language);
          results['karaoke'] = true;
        } catch (_) {
          results['karaoke'] = false;
        }
      }

      // Emoji + highlight via Gemini (best-effort; quota-safe internally).
      if (S['emoji'] == true && hasKey) {
        step(tr('ed.autoEditStepEmoji'));
        try {
          await GeminiSpeechService(apiKey: apiKey).autoEmojiHighlight(segs);
          results['emoji'] = true;
        } catch (_) {
          results['emoji'] = false;
        }
      }
      provider.updateSegments(segs, recordHistory: false);
      if (S['emoji'] == true) {
        project.isKaraokeHighlight = true;
        provider.updateProject(project);
      }

      // Auto SFX from the assigned emojis (and matching words).
      int sfxCount = 0;
      if (S['sfx'] == true) {
        step(tr('ed.autoEditStepSfx'));
        // Strict mapping (unmatched emoji = no sound) + thinning (gap/variety/cap)
        // so we don't spam Pop in the viewer's ears.
        final cands = <({int ms, SfxType type})>[];
        for (final seg in segs) {
          final emoji = seg.emoji;
          if (emoji == null || emoji.isEmpty) continue;
          final sfx = SfxMapper.getSfxForEmoji(emoji, strict: true);
          if (sfx != null) {
            cands.add((ms: seg.startTime.inMilliseconds, type: sfx));
          }
        }
        for (final b in _thinAutoSfx(cands)) {
          final already = project.sfxBlocks.any((x) =>
              (x.startTime - b.startTime).abs() <
              const Duration(milliseconds: 200));
          if (!already) {
            provider.addSfxBlock(b);
            sfxCount++;
          }
        }
        results['sfx'] = true;
      }

      // Fade IN/OUT at the very start & end.
      if (S['fade'] == true) {
        step(tr('ed.autoEditStepFade'));
        _addAutoFades(provider);
        results['fade'] = true;
      }

      // Subtle punch-in zoom on emphasised lines.
      if (S['zoom'] == true) {
        step(tr('ed.autoEditStepZoom'));
        _addAutoZooms(provider, segs);
        results['zoom'] = true;
      }

      // Cut silence (Auto-Cut) if not already on.
      if (S['cut'] == true) {
        step(tr('ed.autoEditStepCut'));
        if (project.isAutoCut) {
          results['cut'] = true; // already on
        } else if (project.videoPath != null) {
          try {
            if (_keptRegions.isEmpty) {
              final flat =
                  await ExportService.detectSpeechRegions(project.videoPath!);
              final durMs = _duration.inMilliseconds > 0
                  ? _duration.inMilliseconds
                  : 10000;
              _keptRegions = computeKeptRegions(flat, durMs,
                  mergeGapMs: project.autoCutGapMs);
            }
            if (_keptRegions.isNotEmpty) {
              project.isAutoCut = true;
              provider.updateProject(project);
              results['cut'] = true;
            } else {
              results['cut'] = false;
            }
          } catch (_) {
            results['cut'] = false;
          }
        }
      }

      // Auto B-roll (heavy: network downloads) — last.
      int brollCount = 0;
      if (S['broll'] == true && hasKey) {
        try {
          brollCount = await _runAutoBrollCore(provider, apiKey,
              onStep: (i, n) =>
                  step(tr('ed.autoBrollStep', {'i': i, 'n': n})));
          results['broll'] = brollCount > 0;
        } catch (_) {
          results['broll'] = false;
        }
      }

      provider.commit();
      if (S['broll'] == true) _ensureBrollControllers(provider.currentProject);
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() {});
        _showAutoEditSummary(results, sfxCount, brollCount);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _toast(tr('ed.autoEmojiFail'));
      }
    }
  }

  /// Remove every auto-added emoji + emphasis ("punch word") highlight from all
  /// subtitle lines — the off-switch for Auto Emoji.
  void _clearEmoji(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null) return;
    provider.pushHistory();
    final segs = project.segments.map((s) => s.copy()).toList();
    for (final s in segs) {
      s.emoji = null;
      s.emphasis = null;
    }
    provider.updateSegments(segs);
    if (mounted) setState(() {});
    _toast(tr('ed.emojiRemoved'));
  }

  /// Auto Edit result checklist: which steps ran ✓ and which failed ✗ (e.g.
  /// a Gemini 503 mid-pipeline) so the user isn't left guessing.
  void _showAutoEditSummary(Map<String, bool> results, int sfxCount, int brollCount) {
    if (results.isEmpty) {
      _toast(tr('ed.autoEditDone'));
      return;
    }
    const labels = <String, String>{
      'proofread': 'ed.aeProofread',
      'karaoke': 'ed.aeKaraoke',
      'emoji': 'ed.aeEmoji',
      'sfx': 'ed.aeSfx',
      'fade': 'ed.aeFade',
      'zoom': 'ed.aeZoom',
      'cut': 'ed.aeCut',
      'broll': 'ed.aeBroll',
    };
    String suffix(String k) {
      if (k == 'sfx' && sfxCount > 0) return ' ($sfxCount)';
      if (k == 'broll' && brollCount > 0) return ' ($brollCount)';
      return '';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('ed.autoEditDone'),
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in results.entries)
              if (labels.containsKey(e.key))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Icon(e.value ? Icons.check_circle : Icons.cancel,
                        size: 17,
                        color: e.value ? AppColors.success : AppColors.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${tr(labels[e.key]!)}${suffix(e.key)}',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
                    ),
                  ]),
                ),
            if (results.values.any((v) => !v)) ...[
              const SizedBox(height: 8),
              Text(tr('ed.aeRetryHint'),
                  style:
                      const TextStyle(color: AppColors.textHint, fontSize: 11.5)),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('ed.ok')),
          ),
        ],
      ),
    );
  }

  Future<void> _autoEmoji(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null || project.segments.isEmpty) return;

    // If emojis already exist, offer to regenerate or remove them all.
    final hasEmoji = project.segments
        .any((s) => (s.emoji ?? '').isNotEmpty || (s.emphasis?.isNotEmpty ?? false));
    if (hasEmoji) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(tr('ed.emojiExistTitle'),
              style: const TextStyle(color: Colors.white)),
          content: Text(tr('ed.emojiExistMsg'),
              style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'remove'),
              child: Text(tr('ed.emojiRemove'),
                  style: const TextStyle(color: AppColors.accent)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'regen'),
              child: Text(tr('ed.emojiRegen'),
                  style: const TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );
      if (choice == 'remove') {
        _clearEmoji(provider);
        return;
      }
      if (choice != 'regen') return; // dismissed
    }

    if (!_isPro) {
      _showProFeatureDialog(tr('ed.proAutoEmoji'));
      return;
    }
    final apiKey = await ApiConfig.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _toast(tr('proc.noGeminiKey'));
      return;
    }
    setState(() => _autoSyncing = true);
    try {
      final segs = project.segments.map((s) => s.copy()).toList();
      await GeminiSpeechService(apiKey: apiKey).autoEmojiHighlight(segs);
      provider.updateSegments(segs);

      // Auto-add SFX (strict map + thinning) so it doesn't spam Pop everywhere.
      final cands = <({int ms, SfxType type})>[];
      for (final seg in segs) {
        final emoji = seg.emoji;
        if (emoji == null || emoji.isEmpty) continue;
        final sfxType = SfxMapper.getSfxForEmoji(emoji, strict: true);
        if (sfxType != null) {
          cands.add((ms: seg.startTime.inMilliseconds, type: sfxType));
        }
      }
      final sfxAdded = <SfxBlock>[];
      for (final b in _thinAutoSfx(cands)) {
        final already = project.sfxBlocks.any(
          (x) => (x.startTime - b.startTime).abs() < const Duration(milliseconds: 200),
        );
        if (!already) {
          sfxAdded.add(b);
          provider.addSfxBlock(b);
        }
      }

      _toast(sfxAdded.isNotEmpty
          ? tr('ed.autoEmojiDone1', {'n': sfxAdded.length})
          : tr('ed.autoEmojiDone2'));
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '').replaceAll('GeminiSpeechException: ', '');
      _toast(msg.contains('Auto ✨') ? msg : tr('ed.autoEmojiFail'));
    } finally {
      if (mounted) setState(() => _autoSyncing = false);
    }
  }

  /// AI Caption + Hashtag — Gemini writes a catchy Lao caption + hashtags from
  /// the subtitle transcript so the creator can copy & post to TikTok fast.
  Future<void> _showCaptionSheet(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null || project.segments.isEmpty) {
      _toast(tr('ed.noSubtitle'));
      return;
    }
    if (!_isPro) {
      _showProFeatureDialog('AI Caption + Hashtag');
      return;
    }
    final apiKey = await ApiConfig.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _toast(tr('proc.noGeminiKey'));
      return;
    }
    final transcript = project.segments.map((s) => s.text).join(' ');
    if (!mounted) return;

    Widget copyChip(String label, IconData icon, String value) =>
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            _toast(tr('set.copied'));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: AppColors.primary, size: 16),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        );

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            14,
            16,
            MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: FutureBuilder<({String caption, List<String> hashtags})>(
            future: GeminiSpeechService(
              apiKey: apiKey,
            ).generateCaption(transcript),
            builder: (ctx, snap) {
              final loading = snap.connectionState != ConnectionState.done;
              final caption = snap.data?.caption ?? '';
              final tags = snap.data?.hashtags ?? const <String>[];
              final tagsLine = tags.join(' ');
              final all = [
                caption,
                if (tagsLine.isNotEmpty) tagsLine,
              ].where((x) => x.isNotEmpty).join('\n\n');
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tag, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'AI Caption + Hashtag',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: AppColors.textHint,
                          size: 20,
                        ),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (loading) ...[
                    const SizedBox(height: 30),
                    Center(
                      child: Column(
                        children: [
                          const CircularProgressIndicator(color: AppColors.primary),
                          const SizedBox(height: 12),
                          Text(
                            tr('ed.writingCaption'),
                            style: const TextStyle(color: AppColors.textHint),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ] else if (all.isEmpty) ...[
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        tr('ed.captionFail'),
                        style: const TextStyle(color: AppColors.textHint),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: SelectableText(
                        all,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        copyChip(tr('ed.copyAll'), Icons.copy_all, all),
                        if (caption.isNotEmpty)
                          copyChip(tr('ed.caption'), Icons.short_text, caption),
                        if (tagsLine.isNotEmpty)
                          copyChip('Hashtag', Icons.tag, tagsLine),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr('ed.captionHint'),
                      style: const TextStyle(color: AppColors.textHint, fontSize: 11),
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _aiSync(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null ||
        project.videoPath == null ||
        project.segments.isEmpty) {
      return;
    }
    setState(() => _autoSyncing = true);
    try {
      final maxWords = switch (project.wordSplit) {
        WordSplit.one => 1,
        WordSplit.two => 2,
        WordSplit.three => 3,
        WordSplit.four => 4,
        WordSplit.six => 6,
        WordSplit.eight => 8,
        WordSplit.none => 8,
      };
      final segs = project.segments.map((s) => s.copy()).toList();
      // First fix any mid-word cuts in the existing units (e.g. "ໂຫຼ"+"ດ") by
      // re-segmenting each phrase into real dictionary words via ICU. This lets
      // older projects be corrected in-app without re-transcribing.
      await LaoWordService.refineToRealWords(segs, locale: project.language);
      // Re-cut subtitles onto the REAL spoken phrases (each subtitle's start/end
      // = the phrase's true boundaries → DURATION matches speech, with pauses).
      // Whisper phrase windows (Groq key) are great for languages Whisper knows
      // — but it CAN'T read Lao, so its Lao timings drift worse and worse over
      // the clip (same bug fixed in processing v1.2.2). For Lao always use the
      // language-agnostic energy VAD instead.
      List<List<int>> regions = const [];
      bool usedWhisper = false;
      final groqKey =
          project.language == 'lo' ? null : await ApiConfig.getGroqKey();
      if (groqKey != null && groqKey.isNotEmpty) {
        try {
          final wt = await GroqSpeechService(
            apiKey: groqKey,
          ).fetchWordTimings(project.videoPath!, language: project.language);
          if (wt.regions.length >= 2) {
            regions = wt.regions;
            usedWhisper = true;
          }
        } catch (_) {}
      }
      if (regions.isEmpty) {
        regions = await AudioSyncService.detectSpeechRegions(
          project.videoPath!,
        );
      }

      List<SubtitleSegment> newSegs;
      if (regions.length >= 2) {
        newSegs = AudioSyncService.resegmentByRegions(
          segs,
          regions,
          maxWords: maxWords,
        );
      } else {
        newSegs = AudioSyncService.resegmentByWordGaps(
          segs,
          maxWords: maxWords,
        );
        final onsets = await AudioSyncService.detectSpeechOnsets(
          project.videoPath!,
        );
        if (onsets.length >= newSegs.length ~/ 2 && onsets.length >= 3) {
          AudioSyncService.alignToOnsets(newSegs, onsets);
        }
      }

      // Group syllables into real words (ICU) for word-by-word karaoke.
      await LaoWordService.ensureWordUnits(newSegs, locale: project.language);

      // Never let two captions overlap (same guard as transcription).
      newSegs.sort((a, b) => a.startTime.compareTo(b.startTime));
      for (int i = 0; i < newSegs.length - 1; i++) {
        final cur = newSegs[i];
        final next = newSegs[i + 1];
        if (cur.endTime > next.startTime) {
          cur.endTime = next.startTime.inMilliseconds >
                  cur.startTime.inMilliseconds
              ? next.startTime
              : cur.startTime + const Duration(milliseconds: 300);
        }
      }

      provider.updateSegments(newSegs);
      setState(() => _syncOffsetMs = 0);
      // Groq hint only applies to non-Lao (Lao always uses VAD now).
      final hasGroq = project.language == 'lo' ||
          ((await ApiConfig.getGroqKey())?.isNotEmpty ?? false);
      _toast(
        usedWhisper
            ? tr('ed.aiCutSyncWhisper', {'n': newSegs.length})
            : (hasGroq
                ? tr('ed.aiCutSync', {'n': newSegs.length})
                : tr('ed.aiCutSyncHint', {'n': newSegs.length})),
      );
    } catch (_) {
      _toast(tr('ed.syncFail'));
    } finally {
      if (mounted) setState(() => _autoSyncing = false);
    }
  }

  // ─── Timeline editing operations ──────────────────────────────────────────
}
