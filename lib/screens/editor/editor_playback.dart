part of '../editor_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

/// Playback: video/clip players, AI voice, B-roll, music, scroll sync.
/// Split out of editor_screen.dart verbatim (phase 0) — the
/// fields and lifecycle stay in [_EditorScreenState].
extension _EditorPlayback on _EditorScreenState {
  Future<void> _autoTranscribe() async {
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null || project.videoPath == null) return;
    
    final engine = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(tr('ed.pickAiTitle')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'whisper'),
            child: Text(tr('ed.pickWhisper')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'groq'),
            child: Text(tr('ed.pickGroq')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'gemini'),
            child: Text(tr('ed.pickGemini')),
          ),
        ],
      ),
    );
    if (engine == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('ed.reTranscribeTitle')),
        content: Text(tr('ed.reTranscribeBody')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr('common.cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('ed.reTranscribeYes'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProcessingScreen(
            videoPath: project.videoPath!,
            aiEngine: engine,
            isReTranscribing: true,
          ),
        ),
      );
      // Reload UI since ProcessingScreen updated the provider's segments
      setState(() {});
    }
  }

  /// Lazily create / (re)load the AI-voice player from the project's track path.
  Future<void> _ensureAiVoicePlayer() async {
    final project = context.read<ProjectProvider>().currentProject;
    final path = project?.aiVoicePath;
    if (path == null || !File(path).existsSync()) return;
    _aiVoicePlayer ??= AudioPlayer();
    if (_aiVoiceLoadedPath != path) {
      await _aiVoicePlayer!.setReleaseMode(ReleaseMode.stop);
      await _aiVoicePlayer!.setSource(DeviceFileSource(path));
      _aiVoiceLoadedPath = path;
    }
    await _applyTrackVolumes();
  }

  /// Push the persisted per-track volumes/mutes onto the live players.
  Future<void> _applyTrackVolumes() async {
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null) return;
    await _videoController?.setVolume(
      project.originalMuted ? 0.0 : project.originalVolume.clamp(0.0, 1.0),
    );
    await _aiVoicePlayer?.setVolume(
      project.aiVoiceMuted ? 0.0 : project.aiVoiceVolume.clamp(0.0, 1.0),
    );
    await _bgMusicPlayer?.setVolume(_bgMusicLiveVolume(_position.inMilliseconds));
  }

  /// AI-voice position for a given video position, accounting for the track's
  /// timeline offset. Returns null when the playhead is outside the AI clip.
  Duration? _aiVoicePosFor(int videoMs, SubtitleProject project) {
    final rel = videoMs - project.aiVoiceOffsetMs;
    if (rel < 0) return null;
    final dur = project.aiVoiceDurationMs ?? 0;
    if (dur > 0 && rel > dur) return null;
    return Duration(milliseconds: rel);
  }

  Future<void> _resumeAiVoice() async {
    final ap = _aiVoicePlayer;
    if (ap == null) return;
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null) return;
    if (project.aiVoiceMuted || project.aiVoiceVolume <= 0) return;
    final pos = _aiVoicePosFor(_position.inMilliseconds, project);
    if (pos == null) { await ap.pause(); return; }
    await ap.seek(pos);
    await ap.resume();
  }

  Future<void> _pauseAiVoice() async {
    try { await _aiVoicePlayer?.pause(); } catch (_) {}
  }

  Future<void> _seekAiVoice(Duration videoPos) async {
    final ap = _aiVoicePlayer;
    if (ap == null) return;
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null) return;
    final pos = _aiVoicePosFor(videoPos.inMilliseconds, project);
    try {
      if (pos == null) { await ap.pause(); }
      else { await ap.seek(pos); }
    } catch (_) {}
  }

  /// Throttled drift correction: keep AI voice within ~250ms of the video.
  Future<void> _maybeCorrectAiDrift(int videoMs) async {
    final ap = _aiVoicePlayer;
    if (ap == null || !_isPlaying) return;
    if (videoMs - _lastAiDriftCheckMs < 1000) return;
    _lastAiDriftCheckMs = videoMs;
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null) return;
    final want = _aiVoicePosFor(videoMs, project);
    if (want == null) { await ap.pause(); return; }
    final aiPos = await ap.getCurrentPosition();
    if (aiPos == null) return;
    if ((aiPos.inMilliseconds - want.inMilliseconds).abs() > 250) {
      await ap.seek(want);
      if (!project.aiVoiceMuted && project.aiVoiceVolume > 0) await ap.resume();
    }
  }

  // ── B-roll video overlays (muted, looped players synced to the timeline) ──

  /// Create controllers only for video overlays NEAR the playhead (a small
  /// pre-roll window) and dispose ones that are far away or removed. This caps
  /// the number of simultaneous hardware decoders — the main cause of B-roll lag
  /// when many clips (e.g. Auto B-roll) are on the timeline.
  void _ensureBrollControllers(SubtitleProject? project) {
    if (project == null) return;
    final posMs = _position.inMilliseconds;
    const prerollMs = 2000; // open the decoder this long before the clip starts
    const graceMs = 1500; // keep it this long after the clip ends (hysteresis)
    final wanted = <String>{};
    for (final ov in project.imageOverlays) {
      if (!ov.isVideo) continue;
      final s = ov.startTime.inMilliseconds;
      final e = ov.endTime.inMilliseconds;
      if (posMs < s - prerollMs || posMs > e + graceMs) continue; // not near
      wanted.add(ov.id);
      if (_brollCtrls.containsKey(ov.id) || _brollInit.contains(ov.id)) continue;
      if (!File(ov.path).existsSync()) continue;
      _brollInit.add(ov.id);
      final c = VideoPlayerController.file(File(ov.path));
      c.initialize().then((_) async {
        await c.setVolume(0); // B-roll is muted (visuals only)
        await c.setLooping(true); // wrap handled natively → no manual re-seek
        _brollInit.remove(ov.id);
        if (!mounted) { c.dispose(); return; }
        _brollCtrls[ov.id] = c;
        setState(() {});
      }).catchError((_) {
        _brollInit.remove(ov.id);
        c.dispose();
      });
    }
    final stale = _brollCtrls.keys.where((id) => !wanted.contains(id)).toList();
    for (final id in stale) {
      _brollCtrls.remove(id)?.dispose();
      _brollActive.remove(id);
    }
  }

  /// Drive each B-roll controller from the playhead. Key to smoothness: align
  /// (seek) only ONCE when the clip enters its visible range, then let it
  /// free-run with the main video (looping handles wrap). No per-tick seeking
  /// during playback — that was the stutter. Only re-seek while paused/scrubbing.
  void _syncBroll(SubtitleProject? project) {
    if (_brollCtrls.isEmpty || project == null) return;
    final posMs = _position.inMilliseconds;
    for (final ov in project.imageOverlays) {
      if (!ov.isVideo) continue;
      final c = _brollCtrls[ov.id];
      if (c == null || !c.value.isInitialized) continue;
      final s = ov.startTime.inMilliseconds;
      final e = ov.endTime.inMilliseconds;
      final dur = c.value.duration.inMilliseconds;
      final visible = posMs >= s && posMs <= e;
      if (!visible) {
        if (_brollActive.remove(ov.id) || c.value.isPlaying) c.pause();
        continue;
      }
      final want = dur > 0 ? (posMs - s) % dur : (posMs - s);
      if (!_brollActive.contains(ov.id)) {
        // Just entered → align once, then hand off to free-run.
        _brollActive.add(ov.id);
        c.seekTo(Duration(milliseconds: want));
        if (_isPlaying) { c.play(); } else { c.pause(); }
      } else if (_isPlaying) {
        if (!c.value.isPlaying) c.play(); // keep playing; DON'T seek (smooth)
      } else {
        // Paused / scrubbing → keep the displayed frame aligned to the playhead.
        final cur = c.value.position.inMilliseconds;
        if ((cur - want).abs() > 120) c.seekTo(Duration(milliseconds: want));
        if (c.value.isPlaying) c.pause();
      }
    }
  }

  void _pauseBroll() {
    for (final c in _brollCtrls.values) {
      if (c.value.isInitialized && c.value.isPlaying) c.pause();
    }
  }

  // ── Background music (looped track under the video, with live auto-duck) ──
  Future<void> _ensureBgMusicPlayer() async {
    final project = context.read<ProjectProvider>().currentProject;
    final path = project?.bgMusicPath;
    if (path == null || !File(path).existsSync()) return;
    _bgMusicPlayer ??= AudioPlayer();
    if (_bgMusicLoadedPath != path) {
      await _bgMusicPlayer!.setReleaseMode(ReleaseMode.loop); // loop to fill video
      await _bgMusicPlayer!.setSource(DeviceFileSource(path));
      _bgMusicLoadedPath = path;
    }
    await _applyTrackVolumes();
  }

  /// Effective bg-music volume right now (0 if muted; ducked during speech).
  double _bgMusicLiveVolume(int videoMs) {
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null || project.bgMusicMuted) return 0.0;
    double vol = project.bgMusicVolume.clamp(0.0, 1.0);
    if (project.bgMusicDuck) {
      final inSpeech = project.segments.any((s) =>
          videoMs >= s.startTime.inMilliseconds &&
          videoMs < s.endTime.inMilliseconds);
      if (inSpeech) vol *= 0.22;
    }
    return vol;
  }

  Future<void> _resumeBgMusic() async {
    final bp = _bgMusicPlayer;
    if (bp == null) return;
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null || project.bgMusicMuted || project.bgMusicVolume <= 0) return;
    await bp.setVolume(_bgMusicLiveVolume(_position.inMilliseconds));
    await bp.resume();
  }

  Future<void> _pauseBgMusic() async {
    try { await _bgMusicPlayer?.pause(); } catch (_) {}
  }

  /// Update bg-music volume live as the playhead moves (auto-duck under speech).
  void _applyBgMusicDuck(int videoMs) {
    final bp = _bgMusicPlayer;
    if (bp == null || !_isPlaying) return;
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null || project.bgMusicPath == null) return;
    final ducked = project.bgMusicDuck &&
        project.segments.any((s) =>
            videoMs >= s.startTime.inMilliseconds &&
            videoMs < s.endTime.inMilliseconds);
    if (ducked != _bgDucked) {
      _bgDucked = ducked;
      bp.setVolume(_bgMusicLiveVolume(videoMs));
    }
  }

  Future<void> _pickBgMusic(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null) return;
    final res = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (res == null || res.files.single.path == null) return;
    final src = res.files.single.path!;
    try {
      final supportDir = await getApplicationSupportDirectory();
      final dir = Directory(p.join(supportDir.path, 'bg_music'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ext = p.extension(src).isNotEmpty ? p.extension(src) : '.mp3';
      final dest =
          p.join(dir.path, 'bg_${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(src).copy(dest);
      provider.pushHistory();
      project.bgMusicPath = dest;
      project.bgMusicMuted = false;
      provider.commit();
      _bgMusicLoadedPath = null;
      await _ensureBgMusicPlayer();
      if (_isPlaying) await _resumeBgMusic();
      if (mounted) setState(() {});
      _toast(tr('ed.bgMusicAdded'));
    } catch (e) {
      _toast(tr('ed.bgMusicFail'));
    }
  }

  void _removeBgMusic(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null) return;
    final old = project.bgMusicPath;
    _bgMusicPlayer?.stop();
    provider.pushHistory();
    project.bgMusicPath = null;
    project.bgMusicDurationMs = null;
    provider.commit();
    _bgMusicLoadedPath = null;
    try { if (old != null) File(old).deleteSync(); } catch (_) {}
    if (mounted) setState(() {});
    _toast(tr('ed.bgMusicRemoved'));
  }


  /// When karaoke is on, make sure every segment carries real ICU word-level
  /// units so the highlight sweeps one WORD at a time (not a coarse block).
  /// Idempotent + carries existing timing; runs once when the editor opens.
  Future<void> _ensureKaraokeWordUnits() async {
    final provider = context.read<ProjectProvider>();
    final project = provider.currentProject;
    if (project == null) return;
    final karaokeOn =
        project.isKaraokeHighlight ||
        project.segments.any((s) => s.karaoke == true);
    if (!karaokeOn) return;
    await LaoWordService.refineToRealWords(
      project.segments,
      locale: project.language,
    );
    if (mounted) {
      provider.commit();
      setState(() {});
    }
  }

  Future<void> _initVideo() async {
    final project = context.read<ProjectProvider>().currentProject;
    if (project?.videoPath == null) return;
    // Multi-clip → native gapless ExoPlayer player (smooth, upright).
    if (project!.clips.length >= 2) {
      await _initClipPlayer(project);
      return;
    }
    _videoController = VideoPlayerController.file(
      File(project!.videoPath!),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    await _videoController!.initialize();
    _activeClip = 0;
    setState(() {
      // Multi-clip: timeline length = sum of all clips (sequential preview).
      _duration = project.clips.length >= 2
          ? Duration(milliseconds: _clipsTotalMs(project))
          : _videoController!.value.duration;
    });
    if (project.clips.length < 2 && project.isAutoCut) {
      await _initKeptRegions();
    }
    _videoController!.addListener(_onVideoUpdate);
    await _applyTrackVolumes();
    _ensureBrollControllers(project); // restore B-roll players for saved overlays
    if (project.clips.length >= 2) _loadAllClipThumbs(project);
  }

  Future<void> _initKeptRegions() async {
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null || project.videoPath == null) return;
    try {
      final flatList = await ExportService.detectSpeechRegions(project.videoPath!);
      final durMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 10000;
      _keptRegions =
          computeKeptRegions(flatList, durMs, mergeGapMs: project.autoCutGapMs);
    } catch (e) {
      debugPrint('Failed to load kept regions: $e');
    }
  }

  List<List<int>> computeKeptRegions(List<int> speechFlatList, int totalDurationMs,
      {int mergeGapMs = 300}) {
    if (speechFlatList.isEmpty) return [];
    final List<List<int>> rawRegions = [];
    for (int i = 0; i < speechFlatList.length; i += 2) {
      if (i + 1 < speechFlatList.length) {
        rawRegions.add([speechFlatList[i], speechFlatList[i + 1]]);
      }
    }
    if (rawRegions.isEmpty) return [];

    // Merge regions separated by <= 300ms
    final List<List<int>> merged = [];
    var curStart = rawRegions[0][0];
    var curEnd = rawRegions[0][1];
    for (int i = 1; i < rawRegions.length; i++) {
      final rStart = rawRegions[i][0];
      final rEnd = rawRegions[i][1];
      if (rStart - curEnd <= mergeGapMs) {
        curEnd = rEnd;
      } else {
        merged.add([curStart, curEnd]);
        curStart = rStart;
        curEnd = rEnd;
      }
    }
    merged.add([curStart, curEnd]);
    return merged;
  }


  /// Kept video clips = [0..duration] minus removedRanges, further divided at
  /// each split point. Returns ordered spans on the ORIGINAL timeline.
  List<({int start, int end})> _videoClips(SubtitleProject project) {
    final total = _duration.inMilliseconds;
    if (total <= 0) return const [];
    final removed = _normalizeRanges(project.removedRanges);
    // Kept spans = complement of removed within [0,total].
    final kept = <List<int>>[];
    int cursor = 0;
    for (final r in removed) {
      final a = r[0].clamp(0, total);
      if (a > cursor) kept.add([cursor, a]);
      if (r[1] > cursor) cursor = r[1].clamp(0, total);
    }
    if (cursor < total) kept.add([cursor, total]);
    // Apply split points inside each kept span.
    final splits = [...project.splitPointsMs]..sort();
    final clips = <({int start, int end})>[];
    for (final span in kept) {
      int s = span[0];
      for (final sp in splits) {
        if (sp > s && sp < span[1]) {
          clips.add((start: s, end: sp));
          s = sp;
        }
      }
      clips.add((start: s, end: span[1]));
    }
    return clips;
  }

  /// Split the current video clip at the playhead (adds a divider).
  void _splitVideoAtPlayhead(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null) return;
    _pauseForEdit();
    final pos = _position.inMilliseconds;
    final clips = _videoClips(project);
    final inClip = clips.any((c) => pos > c.start + 50 && pos < c.end - 50);
    if (!inClip) {
      _toast(tr('ed.movePlayhead'));
      return;
    }
    if (project.splitPointsMs.any((s) => (s - pos).abs() < 50)) return;
    provider.pushHistory();
    project.splitPointsMs = [...project.splitPointsMs, pos]..sort();
    provider.commit();
    setState(() {});
    _toast(tr('ed.clipCut'));
  }

  /// Apply a single video cut [a,b] on the original timeline: record the removed
  /// range, drop captions/SFX inside it, refresh preview. Times never shift —
  /// native frame-drop + PTS remap pull later content earlier on export, and the
  /// preview skips removed ranges live.
  void _cutRange(ProjectProvider provider, int a, int b) {
    final project = provider.currentProject;
    if (project == null) return;
    if (b - a < 200) {
      _toast(tr('ed.tooShort'));
      return;
    }
    provider.pushHistory();
    project.removedRanges = _normalizeRanges([
      ...project.removedRanges,
      [a, b],
    ]);
    _deleteInRange(provider, a, b);
    provider.commit();
    setState(() {});
    // Jump the playhead just past the cut so preview resumes on kept footage.
    _seekTo(Duration(milliseconds: b.clamp(0, _duration.inMilliseconds)));
    _toast(tr('ed.videoCut'));
  }

  String _normFiller(String w) => w
      .toLowerCase()
      .replaceAll(RegExp(r'[\s.,!?…ๆฯ"”“\-]+'), '')
      .trim();

  /// Auto-remove filler words ("um / uh / เออ / อืม / ເອີ") from the whole
  /// project: cut each filler word's video+audio span (via removedRanges, the
  /// same proven path as manual cuts) and clean it out of the caption text.
  /// Offline + free — uses the word-level timings from transcription.
  /// Append another video clip to the END of the current one (CapCut-style).
  /// Merges the files natively (lossless when compatible, else re-encode), then
  /// reloads the player. Existing subtitles/cuts sit before the join so they
  /// stay valid; the appended footage has no captions until re-transcribed.
  Future<void> _appendClip(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null || project.videoPath == null) return;
    _pauseForEdit();

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    final newPath = picked?.files.firstOrNull?.path;
    if (newPath == null) return;

    setState(() => _appendingClip = true);
    try {
      final meta = await MediaInfoService.meta(
          newPath, '${project.id}_clip${DateTime.now().microsecondsSinceEpoch}');
      provider.pushHistory();
      // First append on a single-video project → seed clip 0 from videoPath.
      if (project.clips.isEmpty) {
        final m0 = await MediaInfoService.meta(
            project.videoPath!, '${project.id}_clip0');
        project.clips.add(VideoClip(
          id: '${DateTime.now().microsecondsSinceEpoch}_0',
          path: project.videoPath!,
          durationMs: m0.durationMs > 0 ? m0.durationMs : null,
        ));
      }
      project.clips.add(VideoClip(
        id: '${DateTime.now().microsecondsSinceEpoch}_n',
        path: newPath,
        durationMs: meta.durationMs > 0 ? meta.durationMs : null,
      ));
      provider.commit();
      setState(() => _appendingClip = false);
      _toast(project.segments.isNotEmpty
          ? tr('ed.clipAddedReTranscribe')
          : tr('ed.clipAdded'));
    } catch (e) {
      if (mounted) setState(() => _appendingClip = false);
      _toast(tr('ed.clipAddFail'));
    }
  }

  /// Swap the preview player over to [path] (used when the first clip changes
  /// via reorder/delete). Existing edits stay; sequential playback is stage 3.
  Future<void> _loadVideoFile(String path) async {
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null) return;
    if (project.videoPath == path && _videoController != null) return;
    final old = _videoController;
    old?.removeListener(_onVideoUpdate);
    await old?.pause();
    project.videoPath = path;
    final c = VideoPlayerController.file(
      File(path),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    await c.initialize();
    c.addListener(_onVideoUpdate);
    _videoController = c;
    _activeClip = 0;
    try { await old?.dispose(); } catch (_) {}
    if (mounted) {
      setState(() {
        _duration = project.clips.length >= 2
            ? Duration(milliseconds: _clipsTotalMs(project))
            : c.value.duration;
        _position = Duration.zero;
      });
    }
    await _applyTrackVolumes();
    _loadTimelineOnsets();
  }

  void _deleteClip(ProjectProvider provider, int index) {
    final project = provider.currentProject;
    if (project == null) return;
    final clips = project.clips;
    if (index < 0 || index >= clips.length) return;
    if (clips.length <= 1) {
      _toast(tr('ed.clipMinOne'));
      return;
    }
    provider.pushHistory();
    clips.removeAt(index);
    _mcSelected = -1;
    provider.commit();
    setState(() {});
    if (clips.length >= 2 && _clipPlayer != null) {
      _refreshClipPlayer(project);
    } else {
      _loadVideoFile(clips.first.path); // dropped to a single clip
    }
    _toast(tr('ed.clipDeleted'));
  }

  /// Finish a long-press drag of clip [ci]: figure out where it was dropped and
  /// reorder the clips list accordingly.
  void _commitClipDrag(
      ProjectProvider provider, int ci, double cLeft, double leftPad) {
    final dx = _dragClipDx;
    setState(() {
      _dragClipIndex = -1;
      _dragClipDx = 0;
    });
    final project = provider.currentProject;
    if (project == null || ci < 0 || ci >= project.clips.length) return;
    final bounds = _clipBounds(project);
    final b = bounds[ci];
    // Centre of the dragged block (px) → global ms → which slot it landed on.
    final origCenterPx = b.start / 1000.0 * _pxPerSec + leftPad + (b.dur / 1000.0 * _pxPerSec) / 2;
    final newCenterPx = origCenterPx + dx;
    final newCenterMs = ((newCenterPx - leftPad) / _pxPerSec * 1000).round();
    int target = bounds.indexWhere((x) => newCenterMs >= x.start && newCenterMs < x.end);
    if (target < 0) target = newCenterMs < 0 ? 0 : project.clips.length - 1;
    if (target == ci) return;
    provider.pushHistory();
    final c = project.clips.removeAt(ci);
    final dest = (target > ci ? target - 1 : target).clamp(0, project.clips.length);
    project.clips.insert(dest, c);
    _mcSelected = dest;
    provider.commit();
    setState(() {});
    if (_clipPlayer != null) {
      _refreshClipPlayer(project);
    } else {
      _loadVideoFile(project.clips.first.path);
    }
    _toast(tr('ed.clipMoved'));
  }

  /// Reorder the selected clip block left (-1) or right (+1) on the timeline.
  void _mcMove(ProjectProvider provider, int dir) {
    final project = provider.currentProject;
    if (project == null) return;
    final clips = project.clips;
    final i = _mcSelected;
    final j = i + dir;
    if (i < 0 || i >= clips.length || j < 0 || j >= clips.length) return;
    provider.pushHistory();
    final c = clips.removeAt(i);
    clips.insert(j, c);
    _mcSelected = j;
    provider.commit();
    setState(() {});
    if (_clipPlayer != null) {
      _refreshClipPlayer(project);
    } else {
      _loadVideoFile(clips.first.path);
    }
  }

  /// Split the selected clip into two at the playhead (CapCut ✂️).
  void _mcSplit(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null) return;
    final clips = project.clips;
    final i = _mcSelected;
    if (i < 0 || i >= clips.length) return;
    final bounds = _clipBounds(project)[i];
    final g = _position.inMilliseconds;
    if (g <= bounds.start + 200 || g >= bounds.end - 200) {
      _toast(tr('ed.movePlayhead'));
      return;
    }
    final clip = clips[i];
    final localSplit = clip.trimStartMs + (g - bounds.start); // source-time ms
    provider.pushHistory();
    final a = clip.copy(newId: '${DateTime.now().microsecondsSinceEpoch}_a')
      ..trimEndMs = localSplit;
    final b = clip.copy(newId: '${DateTime.now().microsecondsSinceEpoch}_b')
      ..trimStartMs = localSplit;
    clips.removeAt(i);
    clips.insert(i, b);
    clips.insert(i, a);
    _mcSelected = i;
    provider.commit();
    setState(() {});
    if (_clipPlayer != null) _refreshClipPlayer(project);
    _toast(tr('ed.clipCut'));
  }

  // ───────────────── Stage 3: multi-clip sequential preview ─────────────────
  // When a project has ≥2 clips they play back-to-back on one virtual timeline.
  // `_position`/`_duration` stay GLOBAL (sum of clips); `_videoController` is the
  // ACTIVE clip's player; switching clips swaps the controller (each clip keeps
  // its own native orientation → no rotation/merge issues).

  bool get _isMultiClip =>
      (context.read<ProjectProvider>().currentProject?.clips.length ?? 0) >= 2;

  /// Global timeline bounds for each clip: [start,end) ms + its trimmed length.
  List<({int start, int end, int dur})> _clipBounds(SubtitleProject project) {
    final out = <({int start, int end, int dur})>[];
    int cursor = 0;
    for (final c in project.clips) {
      final dur = c.effectiveMs > 0 ? c.effectiveMs : 1;
      out.add((start: cursor, end: cursor + dur, dur: dur));
      cursor += dur;
    }
    return out;
  }

  int _clipsTotalMs(SubtitleProject project) {
    int t = 0;
    for (final c in project.clips) {
      t += c.effectiveMs > 0 ? c.effectiveMs : 1;
    }
    return t;
  }

  /// Switch the active clip's controller. [localSeekMs] (relative to the clip's
  /// own start, before trim) seeks within it; -1 = start of the clip.
  Future<void> _switchToClip(int index,
      {bool play = false, int localSeekMs = -1}) async {
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null || index < 0 || index >= project.clips.length) return;
    _switchingClip = true; // set synchronously so concurrent calls bail
    final clip = project.clips[index];
    final old = _videoController;
    try {
      old?.removeListener(_onVideoUpdate);
      await old?.pause();
      final c = VideoPlayerController.file(
        File(clip.path),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await c.initialize();
      final seekMs = localSeekMs >= 0 ? localSeekMs : clip.trimStartMs;
      await c.seekTo(Duration(milliseconds: seekMs));
      _videoController = c;
      _activeClip = index;
      try { await old?.dispose(); } catch (_) {}
      await _applyTrackVolumes();
      if (play) await c.play();
      c.addListener(_onVideoUpdate); // add LAST so it never fires mid-swap
    } finally {
      _switchingClip = false;
    }
  }

  /// Seek the GLOBAL multi-clip timeline to [globalMs] via the native player.
  Future<void> _seekGlobal(int globalMs, {bool play = false}) async {
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null) return;
    final bounds = _clipBounds(project);
    if (bounds.isEmpty) return;
    final g = globalMs.clamp(0, _clipsTotalMs(project));
    int idx = bounds.indexWhere((b) => g >= b.start && g < b.end);
    if (idx < 0) idx = bounds.length - 1;
    final localInClip = g - bounds[idx].start; // 0-based within the clipped item
    final cp = _clipPlayer;
    if (cp != null) {
      await cp.seek(idx, localInClip);
      if (play) {
        await cp.play();
        _anchorPosMs = g;
        _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
        _scrollTicker?.start();
      }
      if (mounted) {
        setState(() {
          _position = Duration(milliseconds: g);
          if (play) _isPlaying = true;
        });
      }
    }
  }

  /// Create the native gapless player, feed it the clip playlist, and start
  /// polling its position for the timeline.
  Future<void> _initClipPlayer(SubtitleProject project) async {
    final cp = ClipPlayerController();
    final tid = await cp.create();
    await cp.setClips(
      project.clips.map((c) => c.path).toList(),
      trimStarts: project.clips.map((c) => c.trimStartMs).toList(),
      trimEnds: project.clips.map((c) => c.trimEndMs ?? -1).toList(),
    );
    await cp.refreshSize();
    await cp.setVolume(project.originalMuted ? 0.0 : project.originalVolume);
    _clipPlayer = cp;
    _clipTextureId = tid;
    if (mounted) {
      setState(() {
        _duration = Duration(milliseconds: _clipsTotalMs(project));
        _position = Duration.zero;
      });
    }
    _loadAllClipThumbs(project);
    _startClipPoll();
  }

  /// Re-feed the playlist after clips change (reorder / split / delete).
  Future<void> _refreshClipPlayer(SubtitleProject project) async {
    final cp = _clipPlayer;
    if (cp == null) return;
    await cp.setClips(
      project.clips.map((c) => c.path).toList(),
      trimStarts: project.clips.map((c) => c.trimStartMs).toList(),
      trimEnds: project.clips.map((c) => c.trimEndMs ?? -1).toList(),
    );
    await cp.refreshSize();
    if (mounted) {
      setState(() {
        _duration = Duration(milliseconds: _clipsTotalMs(project));
        _position = Duration.zero;
        _isPlaying = false;
      });
    }
  }

  void _startClipPoll() {
    _clipPoll?.cancel();
    _clipPoll = Timer.periodic(const Duration(milliseconds: 120), (_) async {
      final cp = _clipPlayer;
      if (cp == null || !mounted) return;
      final project = context.read<ProjectProvider>().currentProject;
      if (project == null) return;
      final p = await cp.position();
      final idx = (p['index'] as num?)?.toInt() ?? 0;
      final posMs = (p['posMs'] as num?)?.toInt() ?? 0;
      final playing = p['playing'] == true;
      final ended = p['ended'] == true;
      final bounds = _clipBounds(project);
      final global =
          (idx < bounds.length ? bounds[idx].start : 0) + posMs;
      if (cp.videoW == 0) await cp.refreshSize();
      if (!mounted) return;
      _position =
          Duration(milliseconds: global.clamp(0, _clipsTotalMs(project)));
      _anchorPosMs = _position.inMilliseconds;
      _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
      if (ended && _isPlaying) {
        setState(() => _isPlaying = false);
        _scrollTicker?.stop();
      } else if (playing != _isPlaying) {
        setState(() => _isPlaying = playing);
      }
    });
  }

  /// Load filmstrip thumbnails for each clip (for the inline multi-clip track).
  Future<void> _loadAllClipThumbs(SubtitleProject project) async {
    for (final c in project.clips) {
      if (_clipThumbs.containsKey(c.id)) continue;
      try {
        final t = await ThumbnailService.extract(c.path, maxCount: 10);
        if (!mounted) return;
        if (t.isNotEmpty) setState(() => _clipThumbs[c.id] = t);
      } catch (_) {}
    }
  }


  void _onVideoUpdate() {
    if (!mounted) return;
    // Guard against the listener firing on a controller that is being swapped
    // out / disposed during a multi-clip transition (was a crash source).
    final vc = _videoController;
    if (vc == null || !vc.value.isInitialized) return;
    final v = vc.value;
    final pos = v.position;
    final playing = v.isPlaying;
    _position = pos; // cheap field update (no rebuild) for scroll math
    if (!playing) _scrollTicker?.stop();

    // Release the scroll hold once the video genuinely starts advancing (or a
    // short safety timeout), then re-anchor so interpolation starts clean.
    if (playing && _waitingFirstPlayFrame) {
      final advanced = pos.inMilliseconds > _playStartPosMs;
      final timedOut =
          DateTime.now().millisecondsSinceEpoch - _anchorWallMs > 300;
      if (advanced || timedOut) {
        _waitingFirstPlayFrame = false;
        _anchorPosMs = pos.inMilliseconds;
        _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
      }
    }

    final project = context.read<ProjectProvider>().currentProject;

    // ── Multi-clip: map the active clip's local position onto the global
    // timeline and auto-advance to the next clip when the current one ends. ──
    if (project != null && project.clips.length >= 2) {
      final bounds = _clipBounds(project);
      if (_activeClip < bounds.length) {
        final clip = project.clips[_activeClip];
        final clipEndMs =
            clip.trimEndMs ?? (clip.durationMs ?? v.duration.inMilliseconds);
        final localMs = pos.inMilliseconds;
        final global = bounds[_activeClip].start + (localMs - clip.trimStartMs);
        _position =
            Duration(milliseconds: global.clamp(0, _clipsTotalMs(project)));
        if (playing && !_switchingClip && localMs >= clipEndMs - 120) {
          if (_activeClip + 1 < project.clips.length) {
            _switchToClip(_activeClip + 1, play: true);
          } else {
            _videoController?.pause();
            _scrollTicker?.stop();
          }
          return;
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        if (playing != _isPlaying || now - _lastUiTickMs >= 80) {
          _lastUiTickMs = now;
          setState(() => _isPlaying = playing);
        }
        _syncTimelineScroll();
        return;
      }
    }

    // Auto-skip removed/cut spans ONLY while actually playing. While paused or
    // scrubbing, leave the playhead exactly where the user put it (otherwise
    // scrubbing into trailing silence would snap to the clip end).
    if (playing) {
      // AI Auto-Cut: skip gaps between kept regions during playback.
      if (project != null && project.isAutoCut && _keptRegions.isNotEmpty) {
        final posMs = pos.inMilliseconds;
        bool inKept = false;
        int? nextStartMs;
        for (final region in _keptRegions) {
          if (posMs >= region[0] && posMs <= region[1]) {
            inKept = true;
            break;
          }
          if (region[0] > posMs) {
            if (nextStartMs == null || region[0] < nextStartMs) {
              nextStartMs = region[0];
            }
          }
        }
        if (!inKept) {
          if (nextStartMs != null) {
            // Only seek over a SIZEABLE silence. Tiny gaps (natural speech pauses)
            // are played through instead of seeked — each seek flushes the decoder
            // and causes a visible stutter. Export still trims every gap.
            if (nextStartMs - posMs > 450) {
              _videoController!.seekTo(Duration(milliseconds: nextStartMs));
              return;
            }
            // small gap → fall through and keep playing (smooth)
          } else {
            // Past the last kept region (trailing silence) → end of content.
            // Pause cleanly instead of snapping to the raw end (which froze it).
            _videoController!.pause();
            _pauseAiVoice();
            _pauseBgMusic();
            _pauseBroll();
            _scrollTicker?.stop();
            return;
          }
        }
      }

      // Manual video cuts: jump over any removed range during playback.
      if (project != null && project.removedRanges.isNotEmpty) {
        final posMs = pos.inMilliseconds;
        for (final r in project.removedRanges) {
          if (posMs >= r[0] && posMs < r[1]) {
            final jumpTo = r[1];
            if (jumpTo >= _duration.inMilliseconds - 50) {
              _videoController!.pause();
              _pauseAiVoice();
              _pauseBgMusic();
              _pauseBroll();
              _scrollTicker?.stop();
            } else {
              _videoController!.seekTo(Duration(milliseconds: jumpTo));
            }
            return;
          }
        }
      }
    }

    // Which subtitle is under the playhead now?
    int? newActive;
    if (project != null) {
      for (int i = 0; i < project.segments.length; i++) {
        final s = project.segments[i];
        if (pos >= s.startTime && pos <= s.endTime) {
          newActive = i;
          break;
        }
      }
    }
    final activeChanged = newActive != null && newActive != _activeSegmentIndex;
    final playChanged = playing != _isPlaying;
    // Throttle heavy full-tree rebuilds to ~12.5fps during playback (the video
    // texture + timeline scroll-ticker render independently). Rebuild at once on
    // play/segment changes. Stops tab content rebuilding every position tick.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (playChanged || activeChanged || now - _lastUiTickMs >= 80) {
      _lastUiTickMs = now;
      setState(() {
        _isPlaying = playing;
        if (activeChanged) {
          _activeSegmentIndex = newActive!;
          _previewSelected = false; // deselect when the caption changes
        }
      });
    }
    _ensureBrollControllers(project);
    _syncBroll(project);
    _syncTimelineScroll();
  }


  Future<void> _loadPreviewFonts() async {
    for (final f in [..._laoFonts, ..._thaiFonts]) {
      if (f.$1 == 'Default') continue;
      await LaoFontService.ensureLoaded(f.$1);
    }
    if (mounted) setState(() {}); // re-render preview with matched fonts
  }

  Future<void> _loadProStatus() async {
    final pro = await FreeQuotaService.isPro();
    if (mounted) setState(() => _isPro = pro);
  }

  void _showProFeatureDialog(String featureName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFFFD700), size: 22),
            const SizedBox(width: 8),
            Text(
              'PRO: $featureName',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
        content: Text(
          tr('pro.dialogBody'),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              tr('common.close'),
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            ),
            child: const Text('Upgrade PRO'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadTimelineOnsets() async {
    final project = context.read<ProjectProvider>().currentProject;
    if (project?.videoPath == null) return;
    final onsets = await AudioSyncService.detectSpeechOnsets(
      project!.videoPath!,
    );
    final wave = await AudioSyncService.waveform(project.videoPath!);
    if (mounted) {
      setState(() {
        _timelineOnsets = onsets;
        _waveform = wave;
      });
    }
    // Filmstrip thumbnails (slower) load in the background; timeline shows the
    // waveform meanwhile, then upgrades to frame previews when ready.
    final thumbs = await ThumbnailService.extract(project.videoPath!);
    if (mounted && thumbs.isNotEmpty) {
      setState(() => _thumbs = thumbs);
    }
  }

  Future<void> _togglePlay() async {
    // Multi-clip uses the native gapless player (no single _videoController).
    final mcProject = context.read<ProjectProvider>().currentProject;
    if (mcProject != null && mcProject.clips.length >= 2 && _clipPlayer != null) {
      _scrubDebounce?.cancel();
      if (_isPlaying) {
        await _clipPlayer!.pause();
        _scrollTicker?.stop();
        if (mounted) setState(() => _isPlaying = false);
      } else {
        final total = _clipsTotalMs(mcProject);
        if (_position.inMilliseconds >= total - 200) {
          await _seekGlobal(0, play: true);
        } else {
          await _clipPlayer!.play();
          _anchorPosMs = _position.inMilliseconds;
          _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
          _scrollTicker?.start();
          if (mounted) setState(() => _isPlaying = true);
        }
      }
      return;
    }
    final c = _videoController;
    if (c == null) return;
    _scrubDebounce?.cancel(); // drop any pending scrub seek
    if (_isPlaying) {
      c.pause();
      _pauseAiVoice();
      _pauseBgMusic();
      _pauseBroll();
      _scrollTicker?.stop();
      _waitingFirstPlayFrame = false;
      _scrollTimelineToPosition(); // settle exactly on the current position
      _lastSfxTickMs = -1;
    } else {
      final project = context.read<ProjectProvider>().currentProject;
      // Multi-clip native player: play / restart-at-end.
      if (project != null && project.clips.length >= 2 && _clipPlayer != null) {
        final total = _clipsTotalMs(project);
        if (_position.inMilliseconds >= total - 200) {
          await _seekGlobal(0, play: true);
        } else {
          await _clipPlayer!.play();
          _playStartPosMs = _position.inMilliseconds;
          _anchorPosMs = _playStartPosMs;
          _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
          _scrollTicker?.start();
          setState(() => _isPlaying = true);
        }
        return;
      }
      final posMs = c.value.position.inMilliseconds;
      // "At end" = real end, OR (with Auto-Cut) past the last kept region.
      bool atEnd = _duration > Duration.zero &&
          c.value.position >= _duration - const Duration(milliseconds: 200);
      int restartMs = 0;
      if ((project?.isAutoCut ?? false) && _keptRegions.isNotEmpty) {
        final inKept =
            _keptRegions.any((r) => posMs >= r[0] && posMs <= r[1]);
        if (!inKept && posMs >= _keptRegions.last[1]) atEnd = true;
        restartMs = _keptRegions.first[0];
      }
      // Restart from the start of content. Await the seek so the listener
      // doesn't immediately re-pause us at the old (end) position.
      if (atEnd) await c.seekTo(Duration(milliseconds: restartMs));
      await c.play();
      _resumeAiVoice();
      _resumeBgMusic();
      _syncBroll(project);
      _playStartPosMs = c.value.position.inMilliseconds;
      _anchorPosMs = _playStartPosMs;
      _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
      _lastSfxTickMs = _anchorPosMs - 1;
      _waitingFirstPlayFrame = true; // hold scroll until the video really rolls
      _scrollTicker?.start(); // drives scroll + smooth subtitle animation
    }
  }

  /// Pause playback immediately (used when the user taps/drags the timeline).
  void _pauseForEdit() {
    if (_isPlaying) {
      _videoController?.pause();
      _pauseAiVoice();
      _pauseBgMusic();
      _pauseBroll();
      _scrollTicker?.stop();
      _lastSfxTickMs = -1;
    }
  }

  void _seekTo(Duration pos) {
    // Tapping/scrubbing to seek pauses playback immediately (CapCut behaviour).
    if (_isPlaying) {
      _videoController?.pause();
      _pauseAiVoice();
      _pauseBgMusic();
      _scrollTicker?.stop();
      _isPlaying = false;
      _lastSfxTickMs = -1;
    }
    // Multi-clip: pos is on the GLOBAL timeline → load the right clip + seek.
    if (_isMultiClip) {
      _seekGlobal(pos.inMilliseconds);
      return;
    }
    _videoController?.seekTo(pos);
    _seekAiVoice(pos);
    setState(() => _position = pos);
    _syncBroll(context.read<ProjectProvider>().currentProject);
  }

  /// Seek to [start] ONLY when the playhead is currently outside [start, end].
  /// If the playhead already sits inside the block, leave it where it is so
  /// selecting a block doesn't jump the playhead to the block's head.
  void _seekIfOutside(Duration start, Duration end) {
    final pos = _position.inMilliseconds;
    if (pos < start.inMilliseconds || pos > end.inMilliseconds) {
      _seekTo(start);
      _scrollTimelineToPosition();
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Append an Auto-✨ emoji to the end of a subtitle line (or return as-is).
  String _appendEmoji(String text, String? emoji) =>
      (emoji != null && emoji.isNotEmpty) ? '$text $emoji' : text;


  /// During playback, scroll the timeline so the fixed centre playhead tracks
  /// the current position.
  void _syncTimelineScroll() {
    // Re-anchor the smooth ticker to the real position (corrects any drift),
    // and make sure it's running while playing on the timeline tab.
    if (!_isPlaying) return;
    _anchorPosMs = _position.inMilliseconds;
    _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
    if (_tabController.index == 1 && !(_scrollTicker?.isActive ?? false)) {
      _scrollTicker?.start();
    }
  }

  /// 60fps interpolation: estimate the play position from the last anchor and
  /// scroll the timeline under the fixed playhead — buttery even when
  /// video_player reports the position only a few times per second.
  void _onScrollTick(Duration _) {
    if (!_isPlaying) return;
    // Don't interpolate scroll until the video has actually begun advancing,
    // otherwise the timeline jumps ahead then snaps back on the first frame.
    if (_waitingFirstPlayFrame) return;
    final estMs =
        _anchorPosMs + (DateTime.now().millisecondsSinceEpoch - _anchorWallMs);
    // Smooth timeline scroll (timeline tab only).
    if (_tabController.index == 1 && _timelineScroll.hasClients) {
      final target = (estMs / 1000.0) * _pxPerSec;
      _timelineProgrammatic = true;
      _timelineScroll.jumpTo(
        target.clamp(0.0, _timelineScroll.position.maxScrollExtent),
      );
      _timelineProgrammatic = false;
    }
    // 60fps preview repaint, but ONLY during a subtitle's animation window —
    // keeps in/out/typewriter buttery without rebuilding the tree all the time.
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null) return;
    
    // SFX playback (respect the SFX track volume / mute from the mixer)
    if (_lastSfxTickMs >= -1 &&
        estMs > _lastSfxTickMs &&
        project.sfxBlocks.isNotEmpty &&
        !project.sfxMuted &&
        project.sfxVolume > 0) {
      for (final block in project.sfxBlocks) {
        final sTime = block.startTime.inMilliseconds;
        if (sTime > _lastSfxTickMs && sTime <= estMs) {
          SfxPlayerService().playSfx(
            block.type,
            volume: project.sfxVolume * block.volume,
            trimStart: block.trimStart,
            duration: block.duration,
            customPath: block.isCustom ? block.customPath : null,
          );
        }
      }
    }
    _lastSfxTickMs = estMs;
    // Keep the AI-voice track aligned with the video during playback.
    _maybeCorrectAiDrift(estMs);
    _applyBgMusicDuck(estMs);

    // Smooth 60fps repaint while an ANIMATED zoom is active — otherwise the
    // preview scale only updates a few times/sec and the zoom looks choppy.
    final animatedZoom = project.zoomEffects.any((z) =>
        (z.fromScale != z.toScale || z.keyframes.length >= 2) &&
        estMs >= z.startTime.inMilliseconds &&
        estMs <= z.endTime.inMilliseconds);
    final activeFade = project.fadeEffects.any((f) =>
        estMs >= f.startTime.inMilliseconds &&
        estMs <= f.endTime.inMilliseconds);
    final activeShake = project.shakeEffects.any((s) =>
        estMs >= s.startTime.inMilliseconds &&
        estMs <= s.endTime.inMilliseconds);
    if (animatedZoom || activeFade || activeShake) {
      _position = Duration(milliseconds: estMs);
      setState(() {});
      return;
    }

    if (project.subtitleAnimation == SubtitleAnimation.none &&
        project.exitAnimation == SubtitleAnimation.none) {
      return;
    }
    final durMs = animationDurationMs(project.animationSpeed);
    for (final s in project.segments) {
      final st = s.startTime.inMilliseconds;
      final en = s.endTime.inMilliseconds;
      if (estMs < st || estMs > en) continue;
      final inWin =
          project.subtitleAnimation != SubtitleAnimation.none &&
          project.subtitleAnimation != SubtitleAnimation.typewriter &&
          (estMs - st) < durMs;
      final outWin =
          project.exitAnimation != SubtitleAnimation.none &&
          (en - estMs) < durMs;
      bool typeWin = false;
      if (project.subtitleAnimation == SubtitleAnimation.typewriter) {
        final units = s.words?.where((w) => w.isNotEmpty).length ?? 0;
        final typeDur = units * typewriterUnitMs(project.animationSpeed);
        typeWin = (estMs - st) < typeDur + 120;
      }
      if (inWin || outWin || typeWin) {
        _position = Duration(milliseconds: estMs);
        setState(() {});
      }
      break;
    }
  }

  /// When the user scrubs the timeline (paused), seek the preview to match.
  /// Seeks are throttled (rapid seekTo calls can freeze video_player), with a
  /// trailing seek so the final resting frame is exact.
  void _onTimelineScroll() {
    if (_timelineProgrammatic || _isPlaying || _dragIndex != null) return;
    if (_tabController.index != 1 || !_timelineScroll.hasClients) return;
    final t = (_timelineScroll.offset / _pxPerSec * 1000).round().clamp(
      0,
      _duration.inMilliseconds,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastScrubSeekMs >= 80) {
      _lastScrubSeekMs = now;
      _seekTo(Duration(milliseconds: t));
    }
    _scrubDebounce?.cancel();
    _scrubDebounce = Timer(const Duration(milliseconds: 130), () {
      if (!_isPlaying && _tabController.index == 1) {
        _seekTo(Duration(milliseconds: t));
      }
    });
  }

  void _scrollTimelineToPosition() {
    if (!_timelineScroll.hasClients) return;
    final target = (_position.inMilliseconds / 1000.0) * _pxPerSec;
    _timelineProgrammatic = true;
    _timelineScroll.jumpTo(
      target.clamp(0.0, _timelineScroll.position.maxScrollExtent),
    );
    _timelineProgrammatic = false;
  }
}
