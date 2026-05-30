import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:io';
import '../theme/app_theme.dart';
import '../models/subtitle_style_model.dart';
import '../providers/project_provider.dart';
import '../services/gemini_speech_service.dart';
import '../services/groq_speech_service.dart';
import '../services/openai_whisper_service.dart';
import '../services/audio_sync_service.dart';
import '../services/export_service.dart';
import '../services/lao_font_service.dart';
import '../services/custom_font_service.dart';
import '../services/lao_word_service.dart';
import '../services/thumbnail_service.dart';
import '../services/api_config.dart';
import '../services/free_quota_service.dart';
import '../services/tts_service.dart';
import '../services/sfx_player_service.dart';
import '../utils/sfx_mapper.dart';
import '../widgets/style_preview_card.dart';
import 'export_screen.dart';
import 'settings_screen.dart';

// Available Lao-compatible fonts
const _laoFonts = [
  ('NotoSansLao', 'Noto Sans Lao', 'ທຳມະດາ'),
  ('NotoSerifLao', 'Noto Serif Lao', 'ຕົວຂຽນ'),
  ('NotoSansLaoLooped', 'Noto Sans Lao Looped', 'ມົນ'),
  ('Default', 'Default', 'System'),
];

TextStyle _applyLaoFont(String fontFamily, TextStyle base) {
  // Prefer the SAME system font file the exporter uses → preview matches export.
  final sysFamily = LaoFontService.familyFor(fontFamily);
  if (sysFamily != null) {
    final wght = (base.fontWeight ?? FontWeight.w400).value.toDouble();
    return base.copyWith(
      fontFamily: sysFamily,
      // Honour weight via the variable-font axis (works if the system font
      // is a variable font; ignored gracefully for static fonts).
      fontVariations: [FontVariation('wght', wght)],
    );
  }
  // Fallback (not loaded yet / unavailable): Google Fonts.
  return switch (fontFamily) {
    'NotoSansLao' => GoogleFonts.notoSansLao(textStyle: base),
    'NotoSerifLao' => GoogleFonts.notoSerifLao(textStyle: base),
    'NotoSansLaoLooped' => GoogleFonts.notoSansLaoLooped(textStyle: base),
    _ => base,
  };
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with TickerProviderStateMixin {
  VideoPlayerController? _videoController;
  // Smooth 60fps timeline auto-scroll during playback (interpolated between the
  // coarse position reports from video_player).
  Ticker? _scrollTicker;
  int _anchorPosMs = 0;
  int _anchorWallMs = 0;
  late TabController _tabController;
  int _activeSegmentIndex = 0;
  bool _isPlaying = false;
  bool _isTranslating = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _syncOffsetMs = 0; // cumulative sync shift applied this session
  bool _autoSyncing = false;
  bool _analyzingAudio = false;
  List<List<int>> _keptRegions = [];
  // Timeline (CapCut-style) state
  final ScrollController _timelineScroll = ScrollController();
  List<int> _timelineOnsets = const [];
  int? _dragIndex; // segment being dragged on the timeline
  bool _rippleMode = false; // drag a block → all blocks after it move too
  bool _timelineProgrammatic = false; // guard against scroll/seek feedback loop
  int _lastScrubSeekMs = 0; // throttle seeks while scrubbing the timeline
  int _lastUiTickMs = 0; // throttle full-tree rebuilds during playback
  Timer? _scrubDebounce;
  double _pxPerSec = 120.0; // timeline horizontal scale (zoomable)
  int? _selectedIndex; // selected timeline block (shows action toolbar)
  String? _selectedSfxId; // selected SFX block ID
  List<double> _waveform = const []; // normalised amplitude per 20ms
  List<({int ms, String path})> _thumbs = const []; // filmstrip frames
  // Pinch-to-zoom (two-finger) state for the timeline.
  bool _pinching = false;
  final Map<int, Offset> _ptrs = {};
  double _pinchStartDist = 0;
  double _pinchStartPx = 0;
  // WYSIWYG preview free-transform state.
  bool _previewSelected = false;
  double _gBaseFont = 0;
  double _gBaseRot = 0;
  static const double _deg2rad = 3.141592653589793 / 180.0;
  bool _importingFont = false; // true while the font picker / copy is running
  bool _isPro = false;
  final TtsService _ttsService = TtsService();
  int _lastSfxTickMs = -1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {}); // show/hide the top scrubber per tab
      if (_tabController.index == 1) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollTimelineToPosition(),
        );
      }
      // Keep the ticker alive whenever playing (it drives timeline scroll AND
      // 60fps subtitle-animation frames on any tab).
      if (_isPlaying) {
        _anchorPosMs = _position.inMilliseconds;
        _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
        _scrollTicker?.start();
      }
    });
    _timelineScroll.addListener(_onTimelineScroll);
    _scrollTicker = createTicker(_onScrollTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initVideo());
    _loadTimelineOnsets();
    _loadPreviewFonts();
    _loadProStatus();
    _ensureKaraokeWordUnits();
    SfxPlayerService().init();
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
    _videoController = VideoPlayerController.file(
      File(project!.videoPath!),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    await _videoController!.initialize();
    setState(() {
      _duration = _videoController!.value.duration;
    });
    if (project.isAutoCut) {
      await _initKeptRegions();
    }
    _videoController!.addListener(_onVideoUpdate);
  }

  Future<void> _initKeptRegions() async {
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null || project.videoPath == null) return;
    try {
      final flatList = await ExportService.detectSpeechRegions(project.videoPath!);
      final durMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 10000;
      _keptRegions = computeKeptRegions(flatList, durMs);
    } catch (e) {
      debugPrint('Failed to load kept regions: $e');
    }
  }

  List<List<int>> computeKeptRegions(List<int> speechFlatList, int totalDurationMs) {
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
      if (rStart - curEnd <= 300) {
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

  Future<void> _toggleAutoCut(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null) return;
    
    if (project.isAutoCut) {
      project.isAutoCut = false;
      provider.updateProject(project);
      _toast('ປິດ AI Auto-Cut ແລ້ວ');
      setState(() {});
      return;
    }
    
    if (_keptRegions.isEmpty) {
      setState(() => _analyzingAudio = true);
      try {
        final flatList = await ExportService.detectSpeechRegions(project.videoPath!);
        final durMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 10000;
        _keptRegions = computeKeptRegions(flatList, durMs);
      } catch (e) {
        _toast('ການວິເຄາະສຽງຫຼົ້ມເຫຼວ: ${e.toString()}');
      } finally {
        setState(() => _analyzingAudio = false);
      }
    }
    
    if (_keptRegions.isNotEmpty) {
      project.isAutoCut = true;
      provider.updateProject(project);
      _toast('ເປີດ AI Auto-Cut ⚡ ຕັດຊ່ວງງຽບແລ້ວ!');
      setState(() {});
    } else {
      _toast('ບໍ່ພົບຊ່ວງສຽງເວົ້າໃນວິດີໂອ');
    }
  }

  void _onVideoUpdate() {
    if (!mounted) return;
    final v = _videoController!.value;
    final pos = v.position;
    final playing = v.isPlaying;
    _position = pos; // cheap field update (no rebuild) for scroll math
    if (!playing) _scrollTicker?.stop();

    // AI Auto-Cut dynamic preview seek listener
    final project = context.read<ProjectProvider>().currentProject;
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
          _videoController!.seekTo(Duration(milliseconds: nextStartMs));
          return;
        } else {
          _videoController!.seekTo(_duration);
          return;
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
    _syncTimelineScroll();
  }

  @override
  void dispose() {
    _scrubDebounce?.cancel();
    _scrollTicker?.dispose();
    _videoController?.removeListener(_onVideoUpdate);
    _videoController?.dispose();
    _tabController.dispose();
    _timelineScroll.dispose();
    super.dispose();
  }

  Future<void> _loadPreviewFonts() async {
    for (final f in _laoFonts) {
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
        content: const Text(
          'ຟີເຈີນີ້ສຳລັບ PRO ເທົ່ານັ້ນ\nສະມັກ PRO 39,000 ກີບ/ເດືອນ ໃນໜ້າ "ຕັ້ງຄ່າ"',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'ປິດ',
              style: TextStyle(color: AppColors.textSecondary),
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

  void _togglePlay() {
    final c = _videoController;
    if (c == null) return;
    _scrubDebounce?.cancel(); // drop any pending scrub seek
    if (_isPlaying) {
      c.pause();
      _scrollTicker?.stop();
      _scrollTimelineToPosition(); // settle exactly on the current position
      _lastSfxTickMs = -1;
    } else {
      // If we're at (or past) the end, restart from the beginning.
      if (_duration > Duration.zero &&
          c.value.position >= _duration - const Duration(milliseconds: 200)) {
        c.seekTo(Duration.zero);
      }
      c.play();
      _anchorPosMs = c.value.position.inMilliseconds;
      _anchorWallMs = DateTime.now().millisecondsSinceEpoch;
      _lastSfxTickMs = _anchorPosMs - 1;
      _scrollTicker?.start(); // drives scroll + smooth subtitle animation
    }
  }

  /// Pause playback immediately (used when the user taps/drags the timeline).
  void _pauseForEdit() {
    if (_isPlaying) {
      _videoController?.pause();
      _scrollTicker?.stop();
      _lastSfxTickMs = -1;
    }
  }

  void _seekTo(Duration pos) {
    // Tapping/scrubbing to seek pauses playback immediately (CapCut behaviour).
    if (_isPlaying) {
      _videoController?.pause();
      _scrollTicker?.stop();
      _isPlaying = false;
      _lastSfxTickMs = -1;
    }
    _videoController?.seekTo(pos);
    setState(() => _position = pos);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Append an Auto-✨ emoji to the end of a subtitle line (or return as-is).
  String _appendEmoji(String text, String? emoji) =>
      (emoji != null && emoji.isNotEmpty) ? '$text $emoji' : text;

  /// CapCut-style play bar below the preview: play/seek buttons on one row and
  /// the scrub slider on a SEPARATE row, on a solid bar (not over the video) —
  /// so tapping play/pause can't accidentally grab the scrubber and jump.
  Widget _buildPlayBar() {
    final provider = context.read<ProjectProvider>();
    Widget iconBtn(
      IconData icon,
      double size,
      Color color,
      VoidCallback onTap,
    ) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
        child: Icon(icon, size: size, color: color),
      ),
    );
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4), // Reduced vertical padding
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              _formatDuration(_position),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 11,
              ),
            ),
          ),
          const Spacer(),
          iconBtn(
            Icons.fast_rewind,
            18, // Reduced from 20
            AppColors.textSecondary,
            () => _jumpSegment(provider, -1),
          ),
          iconBtn(
            _isPlaying
                ? Icons.pause_circle_filled
                : Icons.play_circle_filled,
            28, // Reduced from 34
            AppColors.primary,
            _togglePlay,
          ),
          iconBtn(
            Icons.fast_forward,
            18, // Reduced from 20
            AppColors.textSecondary,
            () => _jumpSegment(provider, 1),
          ),
          const Spacer(),
          SizedBox(
            width: 40,
            child: Text(
              _formatDuration(_duration),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// CapCut-style scrubbable TIME RULER (replaces the slider line): tick marks +
  /// second labels, with a playhead line. Tap or drag anywhere to seek.
  Widget _buildTimeRuler() {
    final durMs = _duration.inMilliseconds;
    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth;
        void seekAt(double dx) {
          if (durMs <= 0) return;
          if (_isPlaying) _videoController?.pause();
          final ms = ((dx / w) * durMs).round().clamp(0, durMs);
          _seekTo(Duration(milliseconds: ms));
          _scrollTimelineToPosition();
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekAt(d.localPosition.dx),
          onHorizontalDragStart: (d) => seekAt(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
          child: SizedBox(
            height: 24,
            width: double.infinity,
            child: CustomPaint(
              painter: _TimeRulerPainter(
                positionMs: _position.inMilliseconds,
                durationMs: durMs,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                _buildVideoPreview(),
                // Play + scrub controls as a dedicated bar BELOW the preview (CapCut
                // style) — not overlaid on the video, and the play button is kept
                // clear of the scrub slider so tapping play never jumps the playhead.
                _buildPlayBar(),
                _buildTabBar(),
                Expanded(child: _buildTabContent()),
              ],
            ),
          ),
          if (_analyzingAudio)
            Container(
              color: Colors.black.withOpacity(0.65),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        strokeWidth: 3.5,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'ກຳລັງກວດສອບຄື້ນສຽງ... ⚡',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'ກຳລັງວິເຄາະຫາຊ່ວງງຽບ (Dead Air) ຂອງວິດີໂອ',
                        style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

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
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ExportScreen()),
                ),
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
                      aspectRatio: controller.value.aspectRatio,
                      child: LayoutBuilder(
                        builder: (ctx, c) {
                          // Scale subtitle to the video box so preview == export
                          // (export uses fontSize * videoHeight / 220).
                          final scale = (c.maxHeight / 220).clamp(0.5, 8.0);
                          return Stack(
                            children: [
                              Positioned.fill(child: VideoPlayer(controller)),
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
      Widget layer(Paint? fg, Color? col) => Text(
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

  Widget _buildWeightChip(
    String label,
    int weight,
    SubtitleProject project,
    ProjectProvider provider,
  ) {
    final isSelected = project.fontWeight == weight;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          project.fontWeight = weight;
          provider.updateProject(project);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: _applyLaoFont(
              project.fontFamily,
              TextStyle(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: fontWeightFromInt(weight),
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One selectable font row (used for both built-in and imported fonts).
  Widget _buildFontTile({
    required String fontKey,
    required String name,
    required bool isSelected,
    required VoidCallback onTap,
    VoidCallback? onDelete,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.12)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppColors.primary : AppColors.textHint,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'ຕົວຢ່າງ: ສະບາຍດີ ລາວ',
                    style: _applyLaoFont(
                      fontKey,
                      TextStyle(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textHint,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: AppColors.textHint,
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }

  /// "Import font" button — opens the system picker for a .ttf/.otf file.
  Widget _buildImportFontButton(
    ProjectProvider provider,
    SubtitleProject project,
  ) {
    return GestureDetector(
      onTap: _importingFont ? null : () => _importFont(provider, project),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.5),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_importingFont)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            else
              const Icon(Icons.add, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              _importingFont ? 'ກຳລັງນຳເຂົ້າ...' : 'ນຳເຂົ້າ font (.ttf / .otf)',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importFont(
    ProjectProvider provider,
    SubtitleProject project,
  ) async {
    setState(() => _importingFont = true);
    try {
      final font = await CustomFontService.importFromPicker();
      if (!mounted) return;
      if (font == null) {
        setState(() => _importingFont = false);
        return;
      }
      // Auto-select the freshly imported font.
      project.fontFamily = CustomFontService.familyKey(font.id);
      provider.updateProject(project);
      setState(() => _importingFont = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ນຳເຂົ້າ "${font.name}" ສຳເລັດ'),
          backgroundColor: AppColors.surface,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _importingFont = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ນຳເຂົ້າ font ບໍ່ສຳເລັດ: $e'),
          backgroundColor: AppColors.accent,
        ),
      );
    }
  }

  Future<void> _deleteCustomFont(
    CustomFont cf,
    ProjectProvider provider,
    SubtitleProject project,
  ) async {
    final key = CustomFontService.familyKey(cf.id);
    await CustomFontService.remove(cf.id);
    // If the deleted font was in use, fall back to the default Lao font.
    if (project.fontFamily == key) {
      project.fontFamily = 'NotoSansLao';
      provider.updateProject(project);
    }
    if (mounted) setState(() {});
  }

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
    const tabs = [
      (Icons.subject_rounded, 'ຂໍ້ຄວາມ'),
      (Icons.view_timeline_outlined, 'ໄທມ໌ໄລນ໌'),
      (Icons.palette_outlined, 'ສໄຕລ໌'),
      (Icons.open_with_rounded, 'ຕຳແໜ່ງ'),
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
    
    // SFX playback
    if (_lastSfxTickMs >= -1 && estMs > _lastSfxTickMs && project.sfxBlocks.isNotEmpty) {
      for (final block in project.sfxBlocks) {
        final sTime = block.startTime.inMilliseconds;
        if (sTime > _lastSfxTickMs && sTime <= estMs) {
          SfxPlayerService().playSfx(block.type);
        }
      }
    }
    _lastSfxTickMs = estMs;

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
                  _seekTo(s.startTime);
                  setState(() {
                    _activeSegmentIndex = i;
                    _selectedIndex = i;
                  });
                  _scrollTimelineToPosition();
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
    return Positioned(
      top: top,
      height: height,
      left: 0,
      right: 0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            for (int i = 0; i < _thumbs.length; i++)
              Positioned(
                left: _thumbs[i].ms / 1000.0 * _pxPerSec + leftPad,
                top: 0,
                height: height,
                width:
                    ((i + 1 < _thumbs.length
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
          ],
        ),
      ),
    );
  }

  /// Contextual action toolbar — shown at the BOTTOM of the timeline tab when a
  /// caption block is selected; otherwise a short hint.
  Widget _buildSegToolbar(
    ProjectProvider provider,
    List<SubtitleSegment> segments,
  ) {
    if (segments.isEmpty) return const SizedBox.shrink();
    final project = provider.currentProject;
    if (project == null) return const SizedBox.shrink();

    int target = (_selectedIndex != null && _selectedIndex! < segments.length)
        ? _selectedIndex!
        : -1;
    if (target < 0) {
      for (int k = 0; k < segments.length; k++) {
        if (_position >= segments[k].startTime &&
            _position <= segments[k].endTime) {
          target = k;
          break;
        }
      }
    }
    if (target < 0) target = _activeSegmentIndex.clamp(0, segments.length - 1);
    final i = target;

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
        onTap: onTap,
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
              if (isSfxSelected) ...[
                // SFX Toolbar
                item(
                  Icons.delete_outline,
                  'ລຶບ SFX',
                  () => _deleteSfx(provider, _selectedSfxId!),
                  danger: true,
                ),
              ] else ...[
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
              
              // 2. Auto ✨ Button
              item(
                Icons.auto_awesome,
                'Auto ✨',
                _autoSyncing ? () {} : () => _autoEmoji(provider),
                customColor: const Color(0xFFFFB703),
              ),

              // 3. Auto-Cut ✂️ Button
              item(
                Icons.cut_rounded,
                'Auto-Cut',
                _autoSyncing ? () {} : () => _toggleAutoCut(provider),
                customColor: project.isAutoCut ? const Color(0xFFE040FB) : AppColors.textSecondary,
                highlight: project.isAutoCut,
              ),

              // Divider line between global AI tools and segment tools
              Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: AppColors.border,
              ),

              // 4. Split Button
              item(Icons.content_cut, 'ຕັດ', () => _splitAtPlayhead(provider, i)),
              
              // 5. Merge Button
              item(Icons.merge, 'ລວມ', () => _mergeWithNext(provider, i)),
              
              // 6. Copy Button
              item(
                Icons.copy_all_outlined,
                'ສຳເນົາ',
                () => _duplicateSegment(provider, i),
              ),
              
              // 7. Edit Button
              item(
                Icons.edit_outlined,
                'ແກ້',
                () => _editSegment(segments[i], i, provider),
              ),
              
              // 8. Style Button
              item(
                Icons.palette_outlined,
                'ສໄຕລ໌',
                () => _showSegmentStyleSheet(segments[i], i, provider),
                highlight: segments[i].hasStyleOverride,
              ),
              
              // 9. Delete Button
              item(
                Icons.delete_outline,
                'ລຶບ',
                () => _deleteSegment(provider, i),
                danger: true,
              ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Builds interactive drag blocks for the SFX track
  List<Widget> _buildInteractiveSfxBlocks(
    List<SfxBlock> blocks,
    ProjectProvider provider,
    double leftPad,
    int totalMs,
    double sfxTop,
    double sfxH,
  ) {
    return blocks.map((block) {
      final left = (block.startTime.inMilliseconds / 1000.0) * _pxPerSec + leftPad;
      double dur;
      String label;
      Color color;

      switch (block.type) {
        case SfxType.pop:
          dur = 0.06;
          label = '🌟 Pop';
          color = Colors.amberAccent;
          break;
        case SfxType.ding:
          dur = 0.35;
          label = '🔔 Ding';
          color = Colors.cyanAccent;
          break;
        case SfxType.swoosh:
          dur = 0.40;
          label = '💨 Swoosh';
          color = Colors.lightBlueAccent;
          break;
        case SfxType.chime:
          dur = 0.50;
          label = '✨ Chime';
          color = Colors.purpleAccent;
          break;
        case SfxType.drum:
          dur = 0.25;
          label = '🥁 Drum';
          color = Colors.orangeAccent;
          break;
        case SfxType.beep:
          dur = 0.20;
          label = '🤖 Beep';
          color = Colors.greenAccent;
          break;
        case SfxType.bubble:
          dur = 0.15;
          label = '💧 Bubble';
          color = Colors.lightBlue;
          break;
        case SfxType.click:
          dur = 0.05;
          label = '👆 Click';
          color = Colors.grey;
          break;
        case SfxType.whoosh:
          dur = 0.60;
          label = '🚀 Whoosh';
          color = Colors.indigoAccent;
          break;
        case SfxType.tada:
          dur = 1.00;
          label = '🎉 Tada';
          color = Colors.pinkAccent;
          break;
        case SfxType.bounce:
          dur = 0.30;
          label = '🦘 Bounce';
          color = Colors.limeAccent;
          break;
        case SfxType.glitch:
          dur = 0.25;
          label = '⚠️ Glitch';
          color = Colors.redAccent;
          break;
        case SfxType.heart:
          dur = 0.50;
          label = '❤️ Heart';
          color = Colors.pinkAccent;
          break;
        case SfxType.fire:
          dur = 0.35;
          label = '🔥 Fire';
          color = Colors.deepOrangeAccent;
          break;
        case SfxType.wind:
          dur = 0.70;
          label = '🌬️ Wind';
          color = Colors.tealAccent;
          break;
        case SfxType.laugh:
          dur = 0.55;
          label = '😂 Laugh';
          color = Colors.yellowAccent;
          break;
        case SfxType.sad:
          dur = 0.60;
          label = '😢 Sad';
          color = Colors.blueAccent;
          break;
        case SfxType.magic:
          dur = 0.55;
          label = '🪄 Magic';
          color = Colors.deepPurpleAccent;
          break;
        case SfxType.power:
          dur = 0.30;
          label = '💪 Power';
          color = Colors.orange;
          break;
        case SfxType.surprise:
          dur = 0.45;
          label = '😮 Surprise';
          color = Colors.lime;
          break;
      }

      final w = (dur * _pxPerSec).clamp(32.0, 150.0);
      final selected = _selectedSfxId == block.id;

      return Positioned(
        top: sfxTop,
        left: left,
        width: w,
        height: sfxH,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _pauseForEdit();
            _seekTo(block.startTime);
            setState(() {
              _selectedIndex = null; // deselect subtitle
              _selectedSfxId = block.id;
            });
            _scrollTimelineToPosition();
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
              color: color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: selected ? Colors.white : Colors.transparent,
                width: selected ? 2.0 : 0.0,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildTimelineTab() {
    return Consumer<ProjectProvider>(
      builder: (context, provider, _) {
        final project = provider.currentProject;
        final segments = project?.segments ?? [];
        if (project == null || segments.isEmpty) {
          return const Center(
            child: Text(
              'ຍັງບໍ່ມີ Subtitle',
              style: TextStyle(color: AppColors.textHint),
            ),
          );
        }
        final totalMs = _duration.inMilliseconds > 0
            ? _duration.inMilliseconds
            : segments.last.endTime.inMilliseconds + 2000;

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
                          ? 'ໂໝດກ້ອນ: ລາກ → ກ້ອນທີຫຼັງເລື່ອນຕາມ'
                          : 'ໂໝດດ່ຽວ: ລາກສະເພาะກ້ອນດຽວ',
                    );
                  }, filled: _rippleMode),
                  const SizedBox(width: 4),
                  _miniIcon(Icons.zoom_out, () => _zoomTimeline(0.7)),
                  const SizedBox(width: 4),
                  _miniIcon(Icons.zoom_in, () => _zoomTimeline(1.4)),
                  const SizedBox(width: 4),
                  _miniIcon(
                    Icons.music_note,
                    () => _showAddSfxSheet(provider),
                  ),
                  const SizedBox(width: 4),
                  _miniIcon(
                    Icons.auto_awesome,
                    () => _applyAutoSfx(provider),
                  ),
                  const SizedBox(width: 4),
                  _miniIcon(
                    Icons.add,
                    () => _addAtPlayhead(provider),
                    filled: true,
                  ),
                ],
              ),
            ),
            // (contextual action toolbar moved to the bottom — _buildSegToolbar)
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
                  const sfxH = 18.0; // slim SFX track
                  final filmTop = rulerH + gap;
                  final waveTop = filmTop + (hasFilm ? filmH + gap : 0);
                  final capTop = waveTop + waveH + gap;
                  final blockTop = capTop;
                  final blockH = capH;
                  final sfxTop = blockTop + blockH + gap;
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
                            child: SizedBox(
                              width: contentW,
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTapDown: (d) {
                                        _pauseForEdit();
                                        final ms =
                                            ((d.localPosition.dx - leftPad) /
                                                    _pxPerSec *
                                                    1000)
                                                .round()
                                                .clamp(0, totalMs);
                                        _seekTo(Duration(milliseconds: ms));
                                        _scrollTimelineToPosition();
                                        if (_selectedIndex != null || _selectedSfxId != null) {
                                          setState(() {
                                            _selectedIndex = null;
                                            _selectedSfxId = null;
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
                                    ..._buildInteractiveSfxBlocks(project.sfxBlocks, provider, leftPad, totalMs, sfxTop, sfxH),
                                ],
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
                const Text(
                  'ຍັງບໍ່ມີ Subtitle',
                  style: TextStyle(color: AppColors.textHint),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _showAddSegmentSheet(provider),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('ເພີ່ມ Subtitle'),
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
                      const Text(
                        'ແບ່ງ:',
                        style: TextStyle(
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
                                'ອັດຕະໂນມັດ',
                                WordSplit.none,
                                provider,
                              ),
                              const SizedBox(width: 6),
                              _buildReSplitBtn('2 ຄຳ', WordSplit.two, provider),
                              const SizedBox(width: 6),
                              _buildReSplitBtn(
                                '3 ຄຳ',
                                WordSplit.three,
                                provider,
                              ),
                              const SizedBox(width: 6),
                              _buildReSplitBtn(
                                '4 ຄຳ',
                                WordSplit.four,
                                provider,
                              ),
                              const SizedBox(width: 6),
                              _buildReSplitBtn('6 ຄຳ', WordSplit.six, provider),
                              const SizedBox(width: 6),
                              _buildReSplitBtn(
                                '8 ຄຳ',
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
            // Absolute precise alignment that maps word timings but keeps your custom subtitle grouping exactly as edited!
            AudioSyncService.forcedAlignToWhisper(segs, wt.startsMs, wt.endMs);
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
            segs.clear();
            segs.addAll(newSegs);
            whisperSuccess = true;
          } else if (wt.startsMs.length >= 3) {
            AudioSyncService.forcedAlignToWhisper(segs, wt.startsMs, wt.endMs);
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
            _toast('ກວດຫາສຽງເວົ້າບໍ່ພໍ — ລອງປັບດ້ວຍມື');
            if (mounted) setState(() => _autoSyncing = false);
            return;
          }
          changed = AudioSyncService.alignToOnsets(segs, onsets);
        }
      }

      provider.updateSegments(segs); // single undo step
      setState(() => _syncOffsetMs = 0);
      _toast(whisperSuccess ? '⚡️ ຊິງດ້ວຍ Whisper ສຳເລັດ 100%' : 'ຊິງອັດຕະໂນມັດສຳເລັດ (ປັບ $changed ປ່ອນ)');
    } catch (_) {
      _toast('ຊິງບໍ່ສຳເລັດ');
    } finally {
      if (mounted) setState(() => _autoSyncing = false);
    }
  }

  /// Strong AI sync: align each subtitle's start AND end to the real spoken
  /// phrase (front + back), stretching/shrinking to fit. One undo step.
  /// Auto ✨ — ask Gemini to pick an emoji + the punch word for every line,
  /// then highlight/enlarge those words and append the emoji (PRO feature).
  Future<void> _autoEmoji(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null || project.segments.isEmpty) return;
    if (!_isPro) {
      _showProFeatureDialog('Auto ✨ (Emoji + ໄຮໄລ້ຄຳເດັດ)');
      return;
    }
    final apiKey = await ApiConfig.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _toast('ຍັງບໍ່ໄດ້ໃສ່ Gemini API Key');
      return;
    }
    setState(() => _autoSyncing = true);
    try {
      final segs = project.segments.map((s) => s.copy()).toList();
      await GeminiSpeechService(apiKey: apiKey).autoEmojiHighlight(segs);
      provider.updateSegments(segs);

      // Auto-add SFX blocks that match the assigned emojis
      final sfxAdded = <SfxBlock>[];
      for (final seg in segs) {
        final emoji = seg.emoji;
        if (emoji == null || emoji.isEmpty) continue;
        final sfxType = SfxMapper.getSfxForEmoji(emoji);
        if (sfxType == null) continue;
        // Avoid duplicate SFX at the same timestamp
        final already = project.sfxBlocks.any(
          (b) => (b.startTime - seg.startTime).abs() < const Duration(milliseconds: 200),
        );
        if (!already) {
          sfxAdded.add(SfxBlock(id: const Uuid().v4(), type: sfxType, startTime: seg.startTime));
        }
      }
      for (final b in sfxAdded) {
        provider.addSfxBlock(b);
      }

      _toast(sfxAdded.isNotEmpty
          ? 'Auto ✨ ສຳເລັດ — emoji + ໄຮໄລ້ + SFX ${sfxAdded.length} ຈຸດ'
          : 'Auto ✨ ສຳເລັດ — ໃສ່ emoji + ໄຮໄລ້ຄຳເດັດ');
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '').replaceAll('GeminiSpeechException: ', '');
      _toast(msg.contains('Auto ✨') ? msg : 'Auto ✨ ບໍ່ສຳເລັດ — ລອງໃໝ່');
    } finally {
      if (mounted) setState(() => _autoSyncing = false);
    }
  }

  /// AI Caption + Hashtag — Gemini writes a catchy Lao caption + hashtags from
  /// the subtitle transcript so the creator can copy & post to TikTok fast.
  Future<void> _showCaptionSheet(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null || project.segments.isEmpty) {
      _toast('ຍັງບໍ່ມີ Subtitle');
      return;
    }
    if (!_isPro) {
      _showProFeatureDialog('AI Caption + Hashtag');
      return;
    }
    final apiKey = await ApiConfig.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _toast('ຍັງບໍ່ໄດ້ໃສ່ Gemini API Key');
      return;
    }
    final transcript = project.segments.map((s) => s.text).join(' ');
    if (!mounted) return;

    Widget copyChip(String label, IconData icon, String value) =>
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: value));
            _toast('ຄັດລອກແລ້ວ');
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
                    const Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(color: AppColors.primary),
                          SizedBox(height: 12),
                          Text(
                            'Gemini ກຳລັງຂຽນແคปชั่น...',
                            style: TextStyle(color: AppColors.textHint),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ] else if (all.isEmpty) ...[
                    const SizedBox(height: 20),
                    const Center(
                      child: Text(
                        'ສ້າງບໍ່ສຳເລັດ — ລອງໃໝ່',
                        style: TextStyle(color: AppColors.textHint),
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
                        copyChip('ຄັດລອกທັງໝົด', Icons.copy_all, all),
                        if (caption.isNotEmpty)
                          copyChip('ແคปชั่น', Icons.short_text, caption),
                        if (tagsLine.isNotEmpty)
                          copyChip('Hashtag', Icons.tag, tagsLine),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '💡 ກดຄัดລอก แล้วไปวางในแคปชั่น TikTok/FB ได้เลย',
                      style: TextStyle(color: AppColors.textHint, fontSize: 11),
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
      // Prefer Whisper phrase windows (Groq key) — far more accurate for Lao
      // than energy VAD; fall back to energy VAD, then word-gap re-cut.
      List<List<int>> regions = const [];
      bool usedWhisper = false;
      final groqKey = await ApiConfig.getGroqKey();
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

      provider.updateSegments(newSegs);
      setState(() => _syncOffsetMs = 0);
      _toast(
        usedWhisper
            ? 'AI ຕັດຄຳ + Whisper Sync ສຳເລັດ (${newSegs.length} ປ່ອນ)'
            : 'AI ຕັດຄຳ + ຊິງ ສຳເລັດ (${newSegs.length} ປ່ອນ)',
      );
    } catch (_) {
      _toast('ຊິງບໍ່ສຳເລັດ');
    } finally {
      if (mounted) setState(() => _autoSyncing = false);
    }
  }

  // ─── Timeline editing operations ──────────────────────────────────────────

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
      _toast('ເລື່ອນ playhead ໃຫ້ຢູ່ກາງກ້ອນ ກ່ອນຕັດ');
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
        _toast('ຕັດບ່ອນນີ້ບໍ່ໄດ້');
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
      _toast('ບໍ່ມີກ້ອນຕໍ່ໄປ');
      return;
    }
    final a = segs[index], b = segs[index + 1];
    final words = <String>[...(a.words ?? []), ...(b.words ?? [])];
    final timings = (a.wordTimings != null && b.wordTimings != null)
        ? <Duration>[...a.wordTimings!, ...b.wordTimings!]
        : null;
    final tr = [
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
      translatedText: tr.isEmpty ? null : tr,
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
    _toast('ລຶບ SFX ແລ້ວ');
  }

  void _showAddSfxSheet(ProjectProvider provider) {
    _pauseForEdit();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ເພີ່ມສຽງ Effect ໃສ່ Timeline',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Text('🌟', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Pop', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງປ໋ອບສັ້ນໆ', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.pop);
                            provider.addSfxBlock(SfxBlock(
                              id: const Uuid().v4(),
                              type: SfxType.pop,
                              startTime: _position,
                            ));
                          },
                        ),
                        ListTile(
                          leading: const Text('🔔', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Ding', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງກິ້ງໃສໆ', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.ding);
                            provider.addSfxBlock(SfxBlock(
                              id: const Uuid().v4(),
                              type: SfxType.ding,
                              startTime: _position,
                            ));
                          },
                        ),
                        ListTile(
                          leading: const Text('💨', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Swoosh', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງຜ່ານໄວໆ (Transition)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.swoosh);
                            provider.addSfxBlock(SfxBlock(
                              id: const Uuid().v4(),
                              type: SfxType.swoosh,
                              startTime: _position,
                            ));
                          },
                        ),
                        ListTile(
                          leading: const Text('✨', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Chime', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງວິ້ງເວດມົນ', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.chime);
                            provider.addSfxBlock(SfxBlock(
                              id: const Uuid().v4(),
                              type: SfxType.chime,
                              startTime: _position,
                            ));
                          },
                        ),
                        ListTile(
                          leading: const Text('🥁', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Drum', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງຕຸບໜັກໆ (Punchy)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.drum);
                            provider.addSfxBlock(SfxBlock(
                              id: const Uuid().v4(),
                              type: SfxType.drum,
                              startTime: _position,
                            ));
                          },
                        ),
                        ListTile(
                          leading: const Text('🤖', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Beep', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງບິບ (ເຊັນເຊີ / ເອເລັກໂຕຣນິກ)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.beep);
                            provider.addSfxBlock(SfxBlock(
                              id: const Uuid().v4(),
                              type: SfxType.beep,
                              startTime: _position,
                            ));
                          },
                        ),
                        ListTile(
                          leading: const Text('💧', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Bubble', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງຟອງນ້ຳແຕກ (ໜ້າຮັກ/ຕະຫຼົກ)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.bubble);
                            provider.addSfxBlock(SfxBlock(
                              id: const Uuid().v4(),
                              type: SfxType.bubble,
                              startTime: _position,
                            ));
                          },
                        ),
                        ListTile(
                          leading: const Text('👆', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Click', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງຄລິກເມົາສ໌ (UI/ທົ່ວໄປ)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.click);
                            provider.addSfxBlock(SfxBlock(
                              id: const Uuid().v4(),
                              type: SfxType.click,
                              startTime: _position,
                            ));
                          },
                        ),
                        ListTile(
                          leading: const Text('🚀', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Whoosh', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງລົມພັດລາກຍາວ (ສະລໍ້/ໃຫຍ່)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.whoosh);
                            provider.addSfxBlock(SfxBlock(
                              id: const Uuid().v4(),
                              type: SfxType.whoosh,
                              startTime: _position,
                            ));
                          },
                        ),
                        ListTile(
                          leading: const Text('🎉', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Tada', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງສະເຫຼີມສະຫຼອງ (ສຳເລັດ)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.tada);
                            provider.addSfxBlock(SfxBlock(
                              id: const Uuid().v4(),
                              type: SfxType.tada,
                              startTime: _position,
                            ));
                          },
                        ),
                        ListTile(
                          leading: const Text('🦘', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Bounce', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງກະໂດດ (ຕື່ນເຕັ້ນ/ມ່ວນ)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.bounce);
                            provider.addSfxBlock(SfxBlock(
                              id: const Uuid().v4(),
                              type: SfxType.bounce,
                              startTime: _position,
                            ));
                          },
                        ),
                        ListTile(
                          leading: const Text('⚠️', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Glitch', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງຊັອດ (ຜິດພາດ/ຫັກມຸມ)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.glitch);
                            provider.addSfxBlock(SfxBlock(id: const Uuid().v4(), type: SfxType.glitch, startTime: _position));
                          },
                        ),
                        const Divider(color: Colors.white12, height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text('ສຽງໃໝ່ ✨', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        ListTile(
                          leading: const Text('❤️', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Heart', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງຫົວໃຈ (ຮັກ/ໂຣແມນຕິກ)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.heart);
                            provider.addSfxBlock(SfxBlock(id: const Uuid().v4(), type: SfxType.heart, startTime: _position));
                          },
                        ),
                        ListTile(
                          leading: const Text('🔥', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Fire', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງໄຟ (ຮ້ອນ/ດຸ/ສຸດຍອດ)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.fire);
                            provider.addSfxBlock(SfxBlock(id: const Uuid().v4(), type: SfxType.fire, startTime: _position));
                          },
                        ),
                        ListTile(
                          leading: const Text('🌬️', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Wind', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງລົມ (ສະຫງົບ/ທຳມະຊາດ)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.wind);
                            provider.addSfxBlock(SfxBlock(id: const Uuid().v4(), type: SfxType.wind, startTime: _position));
                          },
                        ),
                        ListTile(
                          leading: const Text('😂', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Laugh', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງຫົວ (ຕະຫຼົກ/ມ່ວນ)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.laugh);
                            provider.addSfxBlock(SfxBlock(id: const Uuid().v4(), type: SfxType.laugh, startTime: _position));
                          },
                        ),
                        ListTile(
                          leading: const Text('😢', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Sad', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງເສົ້າ (ຊ້ອນໃຈ/ອ່ອນໃຈ)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.sad);
                            provider.addSfxBlock(SfxBlock(id: const Uuid().v4(), type: SfxType.sad, startTime: _position));
                          },
                        ),
                        ListTile(
                          leading: const Text('🪄', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Magic', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງເວດມົນ (ຕື່ນໃຈ/ການປ່ຽນ)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.magic);
                            provider.addSfxBlock(SfxBlock(id: const Uuid().v4(), type: SfxType.magic, startTime: _position));
                          },
                        ),
                        ListTile(
                          leading: const Text('💪', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Power', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງຕຸ້ມໜັກ (ແຮງ/ຊ໊ອກ)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.power);
                            provider.addSfxBlock(SfxBlock(id: const Uuid().v4(), type: SfxType.power, startTime: _position));
                          },
                        ),
                        ListTile(
                          leading: const Text('😮', style: TextStyle(fontSize: 24)),
                          title: const Text('ສຽງ Surprise', style: TextStyle(color: Colors.white)),
                          subtitle: const Text('ສຽງຕົກໃຈ (Reveal/ເຊີ້)', style: TextStyle(color: Colors.white54)),
                          onTap: () {
                            Navigator.pop(context);
                            SfxPlayerService().playSfx(SfxType.surprise);
                            provider.addSfxBlock(SfxBlock(id: const Uuid().v4(), type: SfxType.surprise, startTime: _position));
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _applyAutoSfx(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null) return;

    _pauseForEdit();
    
    // Auto-generate SFX blocks
    final newBlocks = <SfxBlock>[];
    for (final seg in project.segments) {
      // Prioritize word timings if available
      if (seg.words != null && seg.wordTimings != null) {
        var currentMs = seg.startTime.inMilliseconds;
        for (int i = 0; i < seg.words!.length; i++) {
          final word = seg.words![i];
          final sfx = SfxMapper.getSfxForWord(word);
          if (sfx != null) {
            newBlocks.add(SfxBlock(
              id: const Uuid().v4(),
              type: sfx,
              startTime: Duration(milliseconds: currentMs),
            ));
          }
          if (i < seg.wordTimings!.length) {
            currentMs += seg.wordTimings![i].inMilliseconds;
          }
        }
      } else {
        // Fallback to checking the entire text
        final words = seg.text.split(RegExp(r'\s+'));
        for (final word in words) {
          final sfx = SfxMapper.getSfxForWord(word);
          if (sfx != null) {
            newBlocks.add(SfxBlock(
              id: const Uuid().v4(),
              type: sfx,
              startTime: seg.startTime,
            ));
            break; // Only one SFX per segment if we don't have word timings to avoid overlapping too much
          }
        }
      }
    }

    if (newBlocks.isEmpty) {
      _toast('ບໍ່ພົບຄຳສັບທີ່ກົງກັບ SFX ອັດຕະໂນມັດໃນວິດີໂອນີ້');
      return;
    }

    // Confirm dialog
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('ໃສ່ SFX ອັດຕະໂນມັດ ✨', style: TextStyle(color: Colors.white)),
        content: Text('ພົບຕຳແໜ່ງທີ່ເໝາະສົມ ${newBlocks.length} ຈຸດ.\nທ່ານຕ້ອງການລຶບ SFX ເກົ່າອອກກ່ອນ ຫຼື ວາງທັບໃສ່ເລີຍ?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.pushHistory();
              // Keep old blocks, add new
              for (final b in newBlocks) {
                provider.addSfxBlock(b);
              }
              _toast('ເພີ່ມ ${newBlocks.length} SFX ແລ້ວ');
            },
            child: const Text('ລວມກັບຂອງເກົ່າ', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Navigator.pop(ctx);
              provider.pushHistory();
              // Remove old blocks
              for (final old in List.from(project.sfxBlocks)) {
                provider.removeSfxBlock(old.id);
              }
              for (final b in newBlocks) {
                provider.addSfxBlock(b);
              }
              _toast('ວາງ ${newBlocks.length} SFX ອັດຕະໂນມັດແລ້ວ');
            },
            child: const Text('ແທນທີ່ໃໝ່ໝົດ', style: TextStyle(color: Colors.white)),
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
      text: 'ຂໍ້ຄວາມໃໝ່',
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
    const animLabels = {
      SubtitleAnimation.none: 'ບໍ່ມີ',
      SubtitleAnimation.fadeIn: 'Fade',
      SubtitleAnimation.slideUp: 'ຂຶ້ນ',
      SubtitleAnimation.slideDown: 'ລົງ',
      SubtitleAnimation.slideLeft: 'ຊ້າຍ',
      SubtitleAnimation.bounceIn: 'ເດັ້ງ',
      SubtitleAnimation.typewriter: 'ພິມດີດ',
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
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.palette_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'ສໄຕລ໌ປະໂຫຍກນີ້',
                            style: TextStyle(
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
                            label: const Text('ລ້າງ'),
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
                    sectionTitle('ສໄຕລ໌'),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          chip(
                            'ຄ່າລວມ',
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
                                    'ສະໄຕລ໌ ${subtitlePresets[i].name}',
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
                    sectionTitle('ຟອນຕ໌'),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          chip(
                            'ຄ່າລວມ',
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
                    sectionTitle('ສີໂຕໜັງສື'),
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
                    sectionTitle('ຂະໜາດ (${eff.fontSize.toStringAsFixed(0)})'),
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
                    sectionTitle('ນ້ຳໜັກ'),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          chip(
                            'ຄ່າລວມ',
                            seg.fontWeight == null,
                            () => update(() => seg.fontWeight = null),
                          ),
                          chip(
                            'ບາງ',
                            seg.fontWeight == 300,
                            () => update(() => seg.fontWeight = 300),
                          ),
                          chip(
                            'ທຳມະດາ',
                            seg.fontWeight == 400,
                            () => update(() => seg.fontWeight = 400),
                          ),
                          chip(
                            'ໜາ',
                            seg.fontWeight == 700,
                            () => update(() => seg.fontWeight = 700),
                          ),
                          chip(
                            'ໜາສຸດ',
                            seg.fontWeight == 900,
                            () => update(() => seg.fontWeight = 900),
                          ),
                        ],
                      ),
                    ),

                    // ── Animation ──
                    sectionTitle('ອະນິເມຊັນ'),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          chip(
                            'ຄ່າລວມ',
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
                    sectionTitle('ໄລ່ສີ (Karaoke)'),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          chip(
                            'ຄ່າລວມ',
                            seg.karaoke == null,
                            () => update(() => seg.karaoke = null),
                          ),
                          chip(
                            _isPro ? 'ເປີດ' : '🔒 ເປີດ',
                            seg.karaoke == true,
                            () {
                              if (!_isPro) {
                                _showProFeatureDialog('Karaoke ໄລ່ສີ');
                                return;
                              }
                              update(() => seg.karaoke = true);
                            },
                          ),
                          chip(
                            'ປິດ',
                            seg.karaoke == false,
                            () => update(() => seg.karaoke = false),
                          ),
                        ],
                      ),
                    ),
                    if (eff.karaoke) ...[
                      // ── Word Pop (enlarge the active word) ──
                      sectionTitle('ຂະຫຍາຍຄຳ (Word Pop)'),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            chip(
                              'ຄ່າລວມ',
                              seg.karaokeScale == null,
                              () => update(() => seg.karaokeScale = null),
                            ),
                            chip(
                              'ເປີດ',
                              seg.karaokeScale == true,
                              () => update(() => seg.karaokeScale = true),
                            ),
                            chip(
                              'ປິດ',
                              seg.karaokeScale == false,
                              () => update(() => seg.karaokeScale = false),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ── Position ──
                    sectionTitle(
                      'ຕຳແໜ່ງແນວຕັ້ງ (${(eff.positionY * 100).toStringAsFixed(0)}%)',
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
                          const SnackBar(
                            content: Text('ໃຊ້ກັບທຸກປະໂຫຍກແລ້ວ'),
                            backgroundColor: AppColors.surface,
                          ),
                        );
                      },
                      icon: const Icon(Icons.done_all, size: 18),
                      label: const Text('ໃຊ້ກັບທຸກປະໂຫຍກ'),
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
                        _autoSyncing ? 'ກຳລັງຊິງ...' : 'ອັດຕະໂນມັດ',
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
              const SizedBox(width: 10),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      btn('-0.5', -500),
                      const SizedBox(width: 6),
                      btn('-0.1', -100),
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
    return GestureDetector(
      onTap: () {
        _seekTo(segment.startTime);
        setState(() => _activeSegmentIndex = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _formatDuration(segment.startTime),
                style: TextStyle(
                  color: isActive ? Colors.white : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    segment.text,
                    style: TextStyle(
                      color: isActive
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: isActive
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                  if (showTranslation && segment.translatedText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      segment.translatedText!,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.my_location,
                color: AppColors.primary,
                size: 18,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              tooltip: 'ຕັ້ງເລີ່ມ = ຕຳແໜ່ງປັດຈຸບັນ',
              onPressed: () =>
                  _setSegmentStartToPlayhead(segment, index, provider),
            ),
            const SizedBox(width: 2),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: const Icon(
                Icons.edit_outlined,
                color: AppColors.textHint,
                size: 18,
              ),
              onPressed: () => _editSegment(segment, index, provider),
            ),
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
        content: Text('ຕັ້ງເລີ່ມທີ່ ${_formatDuration(_position)}'),
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
              const Text(
                'ແກ້ Subtitle',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: textCtrl,
                label: 'ແຖວ 1 (ພາສາຫຼັກ)',
                hint: 'ຂໍ້ຄວາມ subtitle...',
                autofocus: true,
                accentColor: AppColors.primary,
              ),
              const SizedBox(height: 10),
              _buildTextField(
                controller: transCtrl,
                label: 'ແຖວ 2 (ພາສາທີ 2 — ທາງເລືອກ)',
                hint: 'ຄຳແປ...',
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
                            label: 'ເລີ່ມ',
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
                            label: 'ສິ້ນສຸດ',
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
                child: const Text('ບັນທຶກ'),
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

  /// One-tap template gallery (style + size + position + karaoke + animation).
  Widget _buildTemplatesRow(SubtitleProject project, ProjectProvider provider) {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: subtitleTemplates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final t = subtitleTemplates[i];
          final locked = t.isPro && !_isPro;
          final selected =
              project.selectedStyle.type == t.styleType &&
              project.isKaraokeHighlight == t.karaoke;
          return GestureDetector(
            onTap: () => _applyTemplate(t, project, provider),
            child: Container(
              width: 76,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withOpacity(0.15)
                    : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(t.emoji, style: const TextStyle(fontSize: 24)),
                        const SizedBox(height: 6),
                        Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (locked)
                    const Positioned(
                      top: 0,
                      right: 0,
                      child: Icon(
                        Icons.lock,
                        size: 12,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _applyTemplate(
    SubtitleTemplate t,
    SubtitleProject project,
    ProjectProvider provider,
  ) async {
    if (t.isPro && !_isPro) {
      _showProFeatureDialog('ແມ່ແບບ ${t.name}');
      return;
    }
    final preset = subtitlePresets.firstWhere(
      (p) => p.type == t.styleType,
      orElse: () => project.selectedStyle,
    );
    project.selectedStyle = preset;
    project.fontFamily = t.fontFamily;
    project.fontSize = t.fontSize;
    project.fontWeight = t.fontWeight;
    project.subtitlePositionY = t.positionY;
    project.isKaraokeHighlight = t.karaoke;
    project.karaokeHighlightColor = Color(t.karaokeColorValue);
    project.karaokeScale = t.karaokeScale;
    project.subtitleAnimation = t.animation;
    project.exitAnimation = t.exitAnimation;
    project.animationSpeed = t.speed;
    provider.updateProject(project);
    // When the template turns karaoke on, make sure every line has real
    // word-level units so the sweep moves word-by-word.
    if (t.karaoke) {
      await LaoWordService.refineToRealWords(
        project.segments,
        locale: project.language,
      );
      if (mounted) {
        provider.commit();
        setState(() {});
      }
    }
    _toast('ໃຊ້ແມ່ແບບ ${t.name} ✨');
  }

  Widget _buildStyleTab() {
    return Consumer<ProjectProvider>(
      builder: (context, provider, _) {
        final project = provider.currentProject;
        if (project == null) return const SizedBox();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_mosaic,
                    color: Color(0xFFFFC107),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'ແມ່ແບບ (ກดเดียวสวย)',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildTemplatesRow(project, provider),
              const SizedBox(height: 22),
              const Text(
                'ສໄຕລ໌',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: 90,
                ),
                itemCount: subtitlePresets.length,
                itemBuilder: (context, index) {
                  final preset = subtitlePresets[index];
                  return StylePreviewCard(
                    preset: preset,
                    isSelected: project.selectedStyle.type == preset.type,
                    locked: preset.isPro && !_isPro,
                    onTap: () {
                      if (preset.isPro && !_isPro) {
                        _showProFeatureDialog('ສະໄຕລ໌ ${preset.name}');
                        return;
                      }
                      project.selectedStyle = preset;
                      provider.updateProject(project);
                    },
                  );
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ຂະໜາດຕົວໜັງສື',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${project.fontSize.toInt()}px',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: AppColors.surfaceLight,
                  thumbColor: AppColors.primary,
                  overlayColor: AppColors.primary.withOpacity(0.2),
                ),
                child: Slider(
                  value: project.fontSize.clamp(4.0, 60.0),
                  min: 4,
                  max: 60,
                  divisions: 56,
                  onChanged: (v) {
                    project.fontSize = v;
                    provider.updateProject(project);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text(
                      '4',
                      style: TextStyle(color: AppColors.textHint, fontSize: 11),
                    ),
                    Text(
                      '60',
                      style: TextStyle(color: AppColors.textHint, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _buildAnimationPicker(project, provider),
              const SizedBox(height: 24),
              _buildKaraokeSection(project, provider),
              const SizedBox(height: 24),
              _buildBilingualSection(project, provider),
              const SizedBox(height: 24),
              const Text(
                'ຟອນຕ໌ລາວ',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...(_laoFonts.map(
                (f) => _buildFontTile(
                  fontKey: f.$1,
                  name: f.$2,
                  isSelected: project.fontFamily == f.$1,
                  onTap: () {
                    project.fontFamily = f.$1;
                    provider.updateProject(project);
                  },
                ),
              )),
              // User-imported fonts (CapCut-style)
              ...CustomFontService.fonts.map((cf) {
                final key = CustomFontService.familyKey(cf.id);
                return _buildFontTile(
                  fontKey: key,
                  name: cf.name,
                  isSelected: project.fontFamily == key,
                  onTap: () {
                    project.fontFamily = key;
                    provider.updateProject(project);
                  },
                  onDelete: () => _deleteCustomFont(cf, provider, project),
                );
              }),
              _buildImportFontButton(provider, project),
              const SizedBox(height: 20),
              const Text(
                'ນ້ຳໜັກໂຕໜັງສື',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildWeightChip('ບາງ', 300, project, provider),
                  const SizedBox(width: 8),
                  _buildWeightChip('ທຳມະດາ', 400, project, provider),
                  const SizedBox(width: 8),
                  _buildWeightChip('ໜາ', 700, project, provider),
                  const SizedBox(width: 8),
                  _buildWeightChip('ໜາສຸດ', 900, project, provider),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static const _animOptions = [
    (SubtitleAnimation.none, Icons.block, 'ບໍ່ມີ'),
    (SubtitleAnimation.fadeIn, Icons.opacity, 'Fade'),
    (SubtitleAnimation.slideUp, Icons.arrow_upward, 'Slide ↑'),
    (SubtitleAnimation.slideDown, Icons.arrow_downward, 'Slide ↓'),
    (SubtitleAnimation.slideLeft, Icons.arrow_back, 'Slide ←'),
    (SubtitleAnimation.bounceIn, Icons.open_with, 'Bounce'),
    (SubtitleAnimation.typewriter, Icons.keyboard_outlined, 'ພິມດີດ'),
  ];

  // Exit animations: typewriter doesn't apply as an exit effect.
  static const _exitAnimOptions = [
    (SubtitleAnimation.none, Icons.block, 'ບໍ່ມີ'),
    (SubtitleAnimation.fadeIn, Icons.opacity, 'Fade'),
    (SubtitleAnimation.slideUp, Icons.arrow_upward, 'Slide ↑'),
    (SubtitleAnimation.slideDown, Icons.arrow_downward, 'Slide ↓'),
    (SubtitleAnimation.slideLeft, Icons.arrow_back, 'Slide ←'),
    (SubtitleAnimation.bounceIn, Icons.open_with, 'Bounce'),
  ];

  static const _speedOptions = [
    (AnimationSpeed.slow, 'ຊ້າ'),
    (AnimationSpeed.normal, 'ປົກກະຕິ'),
    (AnimationSpeed.fast, 'ໄວ'),
  ];

  Widget _animChip({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.15)
              : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimationPicker(
    SubtitleProject project,
    ProjectProvider provider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Animation ຕອນເຂົ້າ',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _animOptions.map((opt) {
              return _animChip(
                icon: opt.$2,
                label: opt.$3,
                isSelected: project.subtitleAnimation == opt.$1,
                onTap: () {
                  project.subtitleAnimation = opt.$1;
                  provider.updateProject(project);
                },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Animation ຕອນອອກ',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _exitAnimOptions.map((opt) {
              return _animChip(
                icon: opt.$2,
                label: opt.$3,
                isSelected: project.exitAnimation == opt.$1,
                onTap: () {
                  project.exitAnimation = opt.$1;
                  provider.updateProject(project);
                },
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'ຄວາມໄວ Animation',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: _speedOptions.map((opt) {
            final isSelected = project.animationSpeed == opt.$1;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  project.animationSpeed = opt.$1;
                  provider.updateProject(project);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withOpacity(0.15)
                        : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    opt.$2,
                    style: TextStyle(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBilingualSection(
    SubtitleProject project,
    ProjectProvider provider,
  ) {
    final biPreset =
        subtitlePresets[project.bilingualPresetIndex.clamp(
          0,
          subtitlePresets.length - 1,
        )];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: project.showBilingual
            ? const Color(0xFFFFB300).withOpacity(0.07)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: project.showBilingual
              ? const Color(0xFFFFB300)
              : AppColors.border,
          width: project.showBilingual ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with toggle
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: project.showBilingual
                      ? const Color(0xFFFFB300).withOpacity(0.2)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.translate,
                  color: project.showBilingual
                      ? const Color(0xFFFFB300)
                      : AppColors.textHint,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ຊັບສອງພາສາ',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'ສະແດງ 2 ແຖວ ພ້ອມ style ຕ່າງກັນ',
                      style: TextStyle(color: AppColors.textHint, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  Switch(
                    value: project.showBilingual,
                    activeColor: const Color(0xFFFFB300),
                    onChanged: (v) {
                      if (v && !_isPro) {
                        _showProFeatureDialog('ຊັບສອງພາສາ');
                        return;
                      }
                      project.showBilingual = v;
                      provider.updateProject(project);
                      if (v != provider.showTranslation) {
                        provider.toggleShowTranslation();
                      }
                    },
                  ),
                  if (!_isPro)
                    const Positioned(
                      top: 0,
                      right: 0,
                      child: Icon(
                        Icons.lock_rounded,
                        size: 12,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (project.showBilingual) ...[
            const SizedBox(height: 16),
            // Font size for line 2
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ຂະໜາດ ແຖວ 2',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB300).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    '${project.bilingualFontSize.toInt()}px',
                    style: const TextStyle(
                      color: Color(0xFFFFB300),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: const Color(0xFFFFB300),
                inactiveTrackColor: AppColors.surfaceLight,
                thumbColor: const Color(0xFFFFB300),
                overlayColor: const Color(0xFFFFB300).withOpacity(0.2),
              ),
              child: Slider(
                value: project.bilingualFontSize.clamp(4.0, 48.0),
                min: 4,
                max: 48,
                divisions: 44,
                onChanged: (v) {
                  project.bilingualFontSize = v;
                  provider.updateProject(project);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    '4',
                    style: TextStyle(color: AppColors.textHint, fontSize: 10),
                  ),
                  Text(
                    '48',
                    style: TextStyle(color: AppColors.textHint, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Gap between the main line and the translated line
            Row(
              children: [
                const Text(
                  'ໄລຍະຫ່າງ ແຖວ 1 ↔ ແຖວ 2',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB300).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    project.bilingualGap.toInt().toString(),
                    style: const TextStyle(
                      color: Color(0xFFFFB300),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: const Color(0xFFFFB300),
                inactiveTrackColor: AppColors.surfaceLight,
                thumbColor: const Color(0xFFFFB300),
                overlayColor: const Color(0xFFFFB300).withOpacity(0.2),
              ),
              child: Slider(
                value: project.bilingualGap.clamp(0.0, 40.0),
                min: 0,
                max: 40,
                divisions: 40,
                onChanged: (v) {
                  project.bilingualGap = v;
                  provider.updateProject(project);
                },
              ),
            ),
            const SizedBox(height: 16),
            // Style grid for line 2
            const Text(
              'Style ແຖວ 2',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                mainAxisExtent: 90,
              ),
              itemCount: subtitlePresets.length,
              itemBuilder: (context, index) {
                final preset = subtitlePresets[index];
                return StylePreviewCard(
                  preset: preset,
                  isSelected: project.bilingualPresetIndex == index,
                  onTap: () {
                    project.bilingualPresetIndex = index;
                    provider.updateProject(project);
                  },
                );
              },
            ),
            const SizedBox(height: 12),
            // Live preview of line 2
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: _buildSubtitleOverlay(
                  'ຕົວຢ່າງ / Preview',
                  biPreset,
                  fontSizeOverride: project.bilingualFontSize,
                  fontFamily: project.fontFamily,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static const _karaokeColors = [
    Color(0xFF9C59F5), // purple
    Color(0xFFFF6B9D), // pink
    Color(0xFF4DABF7), // blue
    Color(0xFFFF922B), // orange
    Color(0xFF51CF66), // green
    Color(0xFFFF4757), // red
    Color(0xFFFFD43B), // yellow
    Color(0xFF22D3EE), // cyan
  ];

  Widget _buildKaraokeSection(
    SubtitleProject project,
    ProjectProvider provider,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: project.isKaraokeHighlight
            ? AppColors.primary.withOpacity(0.08)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: project.isKaraokeHighlight
              ? AppColors.primary
              : AppColors.border,
          width: project.isKaraokeHighlight ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: project.isKaraokeHighlight
                      ? project.karaokeHighlightColor.withOpacity(0.2)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.highlight,
                  color: project.isKaraokeHighlight
                      ? project.karaokeHighlightColor
                      : AppColors.textHint,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Karaoke Highlight',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'ໄຮໄລຣທີລະຄຳຕາມຈັງຫວະ',
                      style: TextStyle(color: AppColors.textHint, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Stack(
                alignment: Alignment.topRight,
                children: [
                  Switch(
                    value: project.isKaraokeHighlight,
                    activeColor: AppColors.primary,
                    onChanged: (v) async {
                      if (v && !_isPro) {
                        _showProFeatureDialog('Karaoke Highlight');
                        return;
                      }
                      project.isKaraokeHighlight = v;
                      provider.updateProject(project);
                      // Refresh to real word-level units so the sweep is per-word.
                      if (v) {
                        await LaoWordService.refineToRealWords(
                          project.segments,
                          locale: project.language,
                        );
                        if (mounted) {
                          provider.commit();
                          setState(() {});
                        }
                      }
                    },
                  ),
                  if (!_isPro)
                    const Positioned(
                      top: 0,
                      right: 0,
                      child: Icon(
                        Icons.lock_rounded,
                        size: 12,
                        color: Color(0xFFFFD700),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (project.isKaraokeHighlight) ...[
            const SizedBox(height: 14),
            const Text(
              'ສີໄຮໄລຣ',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _karaokeColors.map((color) {
                final isSelected =
                    project.karaokeHighlightColor.value == color.value;
                return GestureDetector(
                  onTap: () {
                    project.karaokeHighlightColor = color;
                    provider.updateProject(project);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withOpacity(0.7),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ຂະຫຍາຍຄຳ (Word Pop)',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const Text(
                        'ຄຳທີ່ໄລ່ສີຈະເດັ້ງໃຫຍ່ຂຶ້ນ',
                        style: TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: project.karaokeScale,
                  activeColor: AppColors.primary,
                  onChanged: (v) {
                    project.karaokeScale = v;
                    provider.updateProject(project);
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPositionTab() {
    return Consumer<ProjectProvider>(
      builder: (context, provider, _) {
        final project = provider.currentProject;
        if (project == null) return const SizedBox();
        final pos = project.subtitlePositionY;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ຕຳໜ່ວ Subtitle',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              // Quick presets
              Row(
                children: [
                  _buildPositionOption(
                    'ເທິງ',
                    Icons.vertical_align_top,
                    pos < 0.2,
                    () {
                      project.subtitlePositionY = 0.1;
                      provider.updateProject(project);
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildPositionOption(
                    'ກາງ',
                    Icons.vertical_align_center,
                    pos >= 0.2 && pos <= 0.7,
                    () {
                      project.subtitlePositionY = 0.5;
                      provider.updateProject(project);
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildPositionOption(
                    'ລຸ່ມ',
                    Icons.vertical_align_bottom,
                    pos > 0.7,
                    () {
                      project.subtitlePositionY = 0.85;
                      provider.updateProject(project);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'ປັບລະອຽດ',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              // Visual position indicator
              Container(
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: (pos * 140).clamp(8, 132),
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'ຊັບຢູ່ນີ້',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: AppColors.surfaceLight,
                  thumbColor: AppColors.primary,
                  overlayColor: AppColors.primary.withOpacity(0.2),
                ),
                child: Slider(
                  value: pos,
                  min: 0.05,
                  max: 0.95,
                  onChanged: (v) {
                    project.subtitlePositionY = v;
                    provider.updateProject(project);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text(
                      'ເທິງ',
                      style: TextStyle(color: AppColors.textHint, fontSize: 11),
                    ),
                    Text(
                      'ລຸ່ມ',
                      style: TextStyle(color: AppColors.textHint, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPositionOption(
    String label,
    IconData icon,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withOpacity(0.15)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTranslateSheet(ProjectProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ແປ Subtitle',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'ເລືອກພາສາທີ່ຕ້ອງການແປ',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            _buildLangOption('🇬🇧 English', 'en', provider),
            const SizedBox(height: 10),
            _buildLangOption('🇹🇭 ພາສາໄທ', 'th', provider),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLangOption(
    String label,
    String langCode,
    ProjectProvider provider,
  ) {
    return GestureDetector(
      onTap: () async {
        Navigator.pop(context);
        await _translateSegments(langCode, provider);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Future<void> _translateSegments(
    String targetLang,
    ProjectProvider provider,
  ) async {
    final project = provider.currentProject;
    if (project == null || project.segments.isEmpty) return;

    final apiKey = await ApiConfig.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ກາລຸນາໃສ່ Gemini API Key ໃນ Settings'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
      return;
    }

    setState(() => _isTranslating = true);
    try {
      final service = GeminiSpeechService(apiKey: apiKey);
      final texts = project.segments.map((s) => s.text).toList();
      final translated = await service.translateTexts(texts, targetLang);

      final updated = project.segments.asMap().entries.map((e) {
        final s = e.value.copy();
        if (e.key < translated.length) s.translatedText = translated[e.key];
        return s;
      }).toList();

      provider.updateSegments(updated, recordHistory: false);
      if (mounted) {
        if (!provider.showTranslation) provider.toggleShowTranslation();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ແປສຳເລັດ!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ແປຜິດພາດ: $e'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isTranslating = false);
    }
  }

  void _showAddSegmentSheet(ProjectProvider provider) {
    final textCtrl = TextEditingController();
    final transCtrl = TextEditingController();
    Duration startTime = _position;
    Duration endTime = _position + const Duration(seconds: 3);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => SingleChildScrollView(
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
              const Text(
                'ເພີ່ມ Subtitle',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              // Line 1 — main text
              _buildTextField(
                controller: textCtrl,
                label: 'ແຖວ 1 (ພາສາຫຼັກ)',
                hint: 'ເຊັ່ນ: ສະບາຍດີ',
                autofocus: true,
                accentColor: AppColors.primary,
              ),
              const SizedBox(height: 10),
              // Line 2 — translated text
              _buildTextField(
                controller: transCtrl,
                label: 'ແຖວ 2 (ພາສາທີ 2 — ທາງເລືອກ)',
                hint: 'ເຊັ່ນ: Hello',
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
                            label: 'ເລີ່ມ',
                            time: startTime,
                            maxTime: _duration > Duration.zero
                                ? _duration
                                : const Duration(hours: 1),
                            onChanged: (t) => setModal(() => startTime = t),
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
                            label: 'ສິ້ນສຸດ',
                            time: endTime,
                            maxTime: _duration > Duration.zero
                                ? _duration
                                : const Duration(hours: 1),
                            onChanged: (t) => setModal(() => endTime = t),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  final text = textCtrl.text.trim();
                  if (text.isEmpty) return;
                  final trans = transCtrl.text.trim();
                  final newSeg = SubtitleSegment(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    text: text,
                    startTime: startTime,
                    endTime: endTime > startTime
                        ? endTime
                        : startTime + const Duration(seconds: 2),
                    translatedText: trans.isEmpty ? null : trans,
                  );
                  final updated =
                      List<SubtitleSegment>.from(
                          provider.currentProject!.segments,
                        )
                        ..add(newSeg)
                        ..sort((a, b) => a.startTime.compareTo(b.startTime));
                  provider.updateSegments(updated);
                  // auto-show bilingual if second line was filled
                  if (trans.isNotEmpty && !provider.showTranslation) {
                    provider.toggleShowTranslation();
                  }
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Text('ເພີ່ມ'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool autofocus = false,
    Color accentColor = AppColors.primary,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: accentColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          autofocus: autofocus,
          style: const TextStyle(color: AppColors.textPrimary),
          maxLines: 2,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textHint),
            filled: true,
            fillColor: AppColors.surfaceLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accentColor, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  void _exportSRT() {
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null) return;

    final buffer = StringBuffer();
    for (int i = 0; i < project.segments.length; i++) {
      final s = project.segments[i];
      buffer.writeln('${i + 1}');
      buffer.writeln('${_toSRTTime(s.startTime)} --> ${_toSRTTime(s.endTime)}');
      buffer.writeln(s.text);
      buffer.writeln();
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'SRT Content',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Text(
            buffer.toString(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ປິດ'),
          ),
        ],
      ),
    );
  }

  String _toSRTTime(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = d.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
    return '$h:$m:$s,$ms';
  }

  void _showDubbingDialog(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null) return;

    final hasApiKey = await ApiConfig.hasElevenLabsKey();

    String ttsLang = project.language.isEmpty ? 'lo' : project.language;
    if (ttsLang == 'Auto') ttsLang = 'lo';

    String selectedVoice = '';
    double speechRate = 0.5;
    bool useTranslation = project.showBilingual;
    bool saveAudioOnly = false;
    List<Map<String, String>> availableVoices = [];
    bool loadingVoices = true;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            // Load voices if not loaded yet
            if (loadingVoices && hasApiKey) {
              loadingVoices = false;
              _ttsService.getVoicesForLanguage(ttsLang).then((voices) {
                if (ctx.mounted) {
                  setDlgState(() {
                    availableVoices = voices;
                    if (voices.isNotEmpty) {
                      // Try to find a common voice like Rachel or Adam, or select first
                      final defaultVoice = voices.firstWhere(
                        (v) => v['name']!.toLowerCase().contains('rachel') || v['name']!.toLowerCase().contains('adam'),
                        orElse: () => voices.first,
                      );
                      selectedVoice = defaultVoice['name'] ?? '';
                    } else {
                      selectedVoice = '';
                    }
                  });
                }
              });
            }

            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.record_voice_over, color: AppColors.primary, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'ພາກສຽງ AI (AI Dubbing)',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!hasApiKey) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.accent.withOpacity(0.25)),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: AppColors.accent, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'ຍັງບໍ່ໄດ້ຕັ້ງຄ່າ ElevenLabs API Key',
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(
                              'ກາລຸນາຕັ້ງຄ່າ ElevenLabs API Key ໃນໜ້າຕັ້ງຄ່າກ່ອນ ເພື່ອພາກສຽງດ້ວຍສຽງພາກລະດັບ Premium ທີ່ມີຄວາມເປັນທຳມະຊາດສູງສຸດ.',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      const Text(
                        'ເລືອກພາສາ ແລະ ໂທນສຽງພາກ:',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Language selection
                    const Text('ພາສາສຽງພາກ:', style: TextStyle(color: AppColors.textHint, fontSize: 11)),
                    DropdownButton<String>(
                      value: ttsLang,
                      isExpanded: true,
                      dropdownColor: AppColors.surface,
                      style: const TextStyle(color: AppColors.textPrimary),
                      items: const [
                        DropdownMenuItem(value: 'lo', child: Text('ພາສາລາວ (Lao)')),
                        DropdownMenuItem(value: 'th', child: Text('ພາສາໄທ (Thai)')),
                        DropdownMenuItem(value: 'en', child: Text('ພາສາອັງກິດ (English)')),
                      ],
                      onChanged: !hasApiKey ? null : (val) {
                        if (val != null) {
                          setDlgState(() {
                            ttsLang = val;
                            loadingVoices = true; // trigger reloading voices
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    if (hasApiKey) ...[
                      // Voice selection
                      const Text('ໂທນສຽງພາກ (ElevenLabs Voices):', style: TextStyle(color: AppColors.textHint, fontSize: 11)),
                      if (availableVoices.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            'ກຳລັງໂຫລດລາຍຊື່ສຽງພາກ...',
                            style: TextStyle(color: AppColors.textHint, fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                        )
                      else
                        DropdownButton<String>(
                          value: selectedVoice.isEmpty ? null : selectedVoice,
                          isExpanded: true,
                          dropdownColor: AppColors.surface,
                          style: const TextStyle(color: AppColors.textPrimary),
                          items: availableVoices.map((v) {
                            final gender = v['gender'] == 'male' ? ' (ຊາຍ)' : (v['gender'] == 'female' ? ' (ຍິງ)' : '');
                            return DropdownMenuItem(
                              value: v['name'],
                              child: Text('${v['name']}$gender'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDlgState(() => selectedVoice = val);
                            }
                          },
                        ),
                      const SizedBox(height: 12),
                      // Speech rate
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('ຄວາມໄວສຽງພາກ:', style: TextStyle(color: AppColors.textHint, fontSize: 11)),
                          Text('${(speechRate * 2).toStringAsFixed(1)}x', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Slider(
                        value: speechRate,
                        min: 0.1,
                        max: 1.0,
                        activeColor: AppColors.primary,
                        inactiveColor: AppColors.border,
                        onChanged: (val) {
                          setDlgState(() => speechRate = val);
                        },
                      ),
                      const SizedBox(height: 6),
                      // Use translation toggle
                      if (project.showBilingual) ...[
                        CheckboxListTile(
                          title: const Text(
                            'ພາກສຽງໂດຍໃຊ້ຂໍ້ຄວາມແປ (Translation)',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
                          ),
                          value: useTranslation,
                          activeColor: AppColors.primary,
                          checkColor: Colors.white,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (val) {
                            if (val != null) {
                              setDlgState(() => useTranslation = val);
                            }
                          },
                        ),
                      ],
                      CheckboxListTile(
                        title: const Text(
                          'ໃສ່ເອັບເຟັກສຽງອັດສະລິຍະ 💥 (SFX Auto-Sync)',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'ໃສ່ສຽງ Pop/Ding ໃຫ້ຕົງກັບ Emoji ແລະ ຄຳໄຮໄລຣ໌ອັດຕະໂນມັດ',
                          style: TextStyle(color: AppColors.textHint, fontSize: 10),
                        ),
                        value: project.isAutoSyncSfx,
                        activeColor: AppColors.primary,
                        checkColor: Colors.white,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (val) {
                          if (val != null) {
                            setDlgState(() {
                              project.isAutoSyncSfx = val;
                              provider.updateProject(project);
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      const Text('ຮູບແບບການບັນທຶກ (Export Format):', style: TextStyle(color: AppColors.textHint, fontSize: 11)),
                      const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border, width: 0.5),
                        ),
                        child: Column(
                          children: [
                            RadioListTile<bool>(
                              title: const Text('ພາກສຽງໃສ່ວິດີໂອ (Mux Video)', style: TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold)),
                              subtitle: const Text('ລວມສຽງພາກ ແລະ ວິດີໂອເຂົ້າກັນ', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                              value: false,
                              groupValue: saveAudioOnly,
                              activeColor: AppColors.primary,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                              onChanged: (val) {
                                if (val != null) {
                                  setDlgState(() => saveAudioOnly = val);
                                }
                              },
                            ),
                            const Divider(height: 1, color: AppColors.border),
                            RadioListTile<bool>(
                              title: const Text('ບັນທຶກແຍກສະເພາະໄຟລ໌ສຽງ (Audio Only)', style: TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold)),
                              subtitle: const Text('ບັນທຶກເປັນໄຟລ໌ .wav ໄວ້ໃນເຄື່ອງ ເພື່ອໄປຕັດຕໍ່ເອງ', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                              value: true,
                              groupValue: saveAudioOnly,
                              activeColor: AppColors.primary,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                              onChanged: (val) {
                                if (val != null) {
                                  setDlgState(() => saveAudioOnly = val);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ປິດ', style: TextStyle(color: AppColors.textSecondary)),
                ),
                if (!hasApiKey)
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.settings, size: 16),
                    label: const Text('ໄປທີ່ໜ້າຕັ້ງຄ່າ', style: TextStyle(fontWeight: FontWeight.bold)),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: selectedVoice.isEmpty
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            _runDubbingPipeline(
                              provider: provider,
                              language: ttsLang,
                              voiceName: selectedVoice,
                              speechRate: speechRate,
                              useTranslation: useTranslation,
                              saveAudioOnly: saveAudioOnly,
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.surfaceLight,
                    ),
                    icon: const Icon(Icons.record_voice_over, size: 16),
                    label: const Text('ເລີ່ມພາກສຽງ', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _runDubbingPipeline({
    required ProjectProvider provider,
    required String language,
    required String voiceName,
    required double speechRate,
    required bool useTranslation,
    bool saveAudioOnly = false,
  }) async {
    final project = provider.currentProject;
    if (project == null || project.videoPath == null) return;


    // Show persistent progress overlay
    String progressText = 'ກຳລັງກຽມລະບົບ...';
    double progressPct = 0.0;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setProgState) {
            // Hook synthesis callback to dynamically update progress screen
            if (progressPct == 0.0) {
              progressPct = 0.05;
              final tempDir = Directory.systemTemp;
              final outputWav = '${tempDir.path}/tts_stitched_${DateTime.now().millisecondsSinceEpoch}.wav';
              final outputSfxWav = '${tempDir.path}/sfx_only_${DateTime.now().millisecondsSinceEpoch}.wav';
              final outputMp4 = '${tempDir.path}/dubbed_${DateTime.now().millisecondsSinceEpoch}.mp4';
              final fileName = 'dubbed_${DateTime.now().millisecondsSinceEpoch}.mp4';

              _ttsService.synthesizeAndStitch(
                segments: project.segments,
                languageCode: language,
                voiceName: voiceName,
                speechRate: speechRate,
                useTranslation: useTranslation,
                outputWavPath: outputWav,
                outputSfxWavPath: project.sfxBlocks.isNotEmpty ? outputSfxWav : null,
                autoSyncSfx: project.sfxBlocks.isNotEmpty, // Generate SFX track if blocks exist
                sfxBlocks: project.sfxBlocks,
                onProgress: (status) {
                  if (ctx.mounted) {
                    setProgState(() {
                      progressText = status;
                      if (status.contains('ສັງເຄາະສຽງປະໂຫຍກ')) {
                        progressPct = 0.15 + (0.65 * chunksProgressFraction(status));
                      } else if (status.contains('ຈັດຊ່ວງເວລາ')) {
                        progressPct = 0.85;
                      }
                    });
                  }
                },
              ).then((errorMsg) async {
                if (errorMsg != null) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  _showErrorBanner(errorMsg);
                  return;
                }

                if (saveAudioOnly) {
                  if (ctx.mounted) {
                    setProgState(() {
                      progressText = 'ກຳລັງບັນທຶກໄຟລ໌ສຽງ...';
                      progressPct = 0.95;
                    });
                  }
                  try {
                    const channel = MethodChannel('com.anniekaydee.subtitle_app/audio');
                    final newPath = await channel.invokeMethod<String>('saveAudioToGallery', {
                      'audioPath': outputWav,
                      'fileName': 'dubbed_audio_${DateTime.now().millisecondsSinceEpoch}.wav',
                    });

                    if (newPath != null) {
                      if (project.sfxBlocks.isNotEmpty) {
                        await channel.invokeMethod<String>('saveAudioToGallery', {
                          'audioPath': outputSfxWav,
                          'fileName': 'sfx_only_${DateTime.now().millisecondsSinceEpoch}.wav',
                        });
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showAudioSuccessDialog(newPath);
                    } else {
                      throw Exception('Failed to save audio to gallery');
                    }
                  } catch (e) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    _showErrorBanner('Terminated. ການບັນທຶກໄຟລ໌ສຽງຫຼົ້ມເຫຼວ: ${e.toString()}');
                  }
                  return;
                }

                if (ctx.mounted) {
                  setProgState(() {
                    progressText = 'ກຳລັງປະສົມສຽງໃສ່ວິດີໂອ (Muxing)...';
                    progressPct = 0.95;
                  });
                }

                try {
                  const channel = MethodChannel('com.anniekaydee.subtitle_app/audio');
                  final newPath = await channel.invokeMethod<String>('replaceAudioTrack', {
                    'videoPath': project.videoPath,
                    'audioPath': outputWav,
                    'outputPath': outputMp4,
                    'fileName': fileName,
                  });

                  if (newPath != null && File(newPath).existsSync()) {
                    // Update project video path and refresh player!
                    provider.pushHistory();
                    project.videoPath = newPath;
                    provider.liveUpdate();
                    provider.commit();

                    await _initVideo();

                    if (project.sfxBlocks.isNotEmpty) {
                      await channel.invokeMethod<String>('saveAudioToGallery', {
                        'audioPath': outputSfxWav,
                        'fileName': 'sfx_only_${DateTime.now().millisecondsSinceEpoch}.wav',
                      });
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    _showSuccessDialog(fileName);
                  } else {
                    throw Exception('Muxer returned null or file not found');
                  }
                } catch (e) {
                  // ---- FALLBACK: Muxing failed → save as Audio Only instead ----
                  debugPrint('⚠️ Muxing failed, falling back to Audio Only: $e');
                  if (ctx.mounted) {
                    setProgState(() {
                      progressText = 'Mux ບໍ່ສຳເລັດ → ກຳລັງບັນທຶກເປັນໄຟລ໌ສຽງແທນ...';
                      progressPct = 0.97;
                    });
                  }
                  try {
                    const fallbackChannel = MethodChannel('com.anniekaydee.subtitle_app/audio');
                    final audioPath = await fallbackChannel.invokeMethod<String>('saveAudioToGallery', {
                      'audioPath': outputWav,
                      'fileName': 'dubbed_audio_${DateTime.now().millisecondsSinceEpoch}.wav',
                    });
                    if (audioPath != null) {
                      if (project.sfxBlocks.isNotEmpty) {
                        await fallbackChannel.invokeMethod<String>('saveAudioToGallery', {
                          'audioPath': outputSfxWav,
                          'fileName': 'sfx_only_${DateTime.now().millisecondsSinceEpoch}.wav',
                        });
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      _showAudioFallbackDialog(audioPath);
                    } else {
                      throw Exception('Audio fallback also failed');
                    }
                  } catch (e2) {
                    if (ctx.mounted) Navigator.pop(ctx);
                    _showErrorBanner('ການບັນທຶກສຽງຫຼົ້ມເຫຼວ: ${e2.toString()}');
                  }
                }
              });
            }

            return PopScope(
              canPop: false,
              child: AlertDialog(
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                content: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        progressText,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(progressPct * 100).toInt()}%',
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  double chunksProgressFraction(String status) {
    try {
      final match = RegExp(r'(\d+)/(\d+)').firstMatch(status);
      if (match != null) {
        final current = double.parse(match.group(1)!);
        final total = double.parse(match.group(2)!);
        return current / total;
      }
    } catch (_) {}
    return 0.5;
  }

  void _showErrorBanner(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.accent,
      ),
    );
  }

  void _showSuccessDialog(String fileName) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success, size: 24),
            SizedBox(width: 10),
            Text(
              'ພາກສຽງສຳເລັດແລ້ວ! ✅',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          'ສຽງພາກ AI ໄດ້ຖືກລວມເຂົ້າກັບວິດີໂອຮຽບຮ້ອຍແລ້ວ!\nໄຟລ໌ວິດີໂອຖືກບັນທຶກໄວ້ໃນຄັງຮູບເປັນຊື່:\n\n$fileName',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: const Text('ຕົກລົງ', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAudioSuccessDialog(String savedPath) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success, size: 24),
            SizedBox(width: 10),
            Text(
              'ບັນທຶກສຽງພາກສຳເລັດ! 🎙️',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          'ໄຟລ໌ສຽງພາກ AI ໄດ້ຖືກບັນທຶກສະເພາະແຍກໄວ້ໃນເຄື່ອງຮຽບຮ້ອຍແລ້ວ!\n\nໄຟລ໌ຖືກບັນທຶກໄວ້ໃນໂຟນເດີ Music/SubtitleAI ຂອງເຄື່ອງ:\n\n${savedPath.split('/').last}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: const Text('ຕົກລົງ', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Shown when Muxing fails but audio was saved as a fallback layer file
  void _showAudioFallbackDialog(String savedPath) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.amber, size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'ບັນທຶກເປັນ Audio Layer ແທນ 🎵',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ການປະສົມສຽງໃສ່ວິດີໂອໂດຍກົງບໍ່ສຳເລັດ, ແຕ່ໄຟລ໌ສຽງພາກໄດ້ຖືກບັນທຶກແຍກສຳເລັດແລ້ວ! ✅',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                '📂 Music/SubtitleAI/${savedPath.split('/').last}',
                style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '💡 ວິທີໃຊ້: ນຳເຂົ້າໄຟລ໌ສຽງນີ້ເປັນ Audio Layer ແຍກໃນ CapCut ຫຼື TikTok ແລ້ວວາງທັບວິດີໂອໄດ້ເລີຍ!',
              style: TextStyle(color: AppColors.textHint, fontSize: 11.5, height: 1.4),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('ເຂົ້າໃຈແລ້ວ 👍', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

/// Compact icon + label used inside the editor's TabBar.
/// Time ruler for the timeline (ticks every second, labels every 5s).
class _RulerPainter extends CustomPainter {
  final int totalMs;
  final double pxPerSec;
  final double leftPad;
  _RulerPainter({
    required this.totalMs,
    required this.pxPerSec,
    required this.leftPad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tick = Paint()
      ..color = const Color(0xFF555555)
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    final totalSec = (totalMs / 1000).ceil();
    for (int s = 0; s <= totalSec; s++) {
      final x = leftPad + s * pxPerSec;
      final big = s % 5 == 0;
      canvas.drawLine(
        Offset(x, size.height - (big ? 10 : 6)),
        Offset(x, size.height),
        tick,
      );
      if (big) {
        final mm = (s ~/ 60).toString().padLeft(2, '0');
        final ss = (s % 60).toString().padLeft(2, '0');
        tp.text = TextSpan(
          text: '$mm:$ss',
          style: const TextStyle(color: Color(0xFF888888), fontSize: 9),
        );
        tp.layout();
        tp.paint(canvas, Offset(x + 2, 0));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) =>
      old.totalMs != totalMs || old.pxPerSec != pxPerSec;
}

/// Audio waveform behind the timeline track (amplitude per [stepMs]).
class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  final int stepMs;
  final double pxPerSec;
  final double leftPad;
  _WaveformPainter({
    required this.samples,
    required this.stepMs,
    required this.pxPerSec,
    required this.leftPad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final paint = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final midY = size.height / 2;
    final pxPerMs = pxPerSec / 1000.0;
    // Draw at most one bar per ~2px to keep it light.
    final stepPx = stepMs * pxPerMs;
    final skip = (2.0 / stepPx).ceil().clamp(1, 1000);
    for (int i = 0; i < samples.length; i += skip) {
      final x = leftPad + i * stepMs * pxPerMs;
      if (x < -4 || x > size.width + 4) continue;
      final h = (samples[i] * (size.height * 0.45)).clamp(0.6, size.height / 2);
      canvas.drawLine(Offset(x, midY - h), Offset(x, midY + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.samples != samples || old.pxPerSec != pxPerSec;
}

/// Vertical markers showing detected speech-onset times.
/// CapCut-style time ruler: tick marks + mm:ss labels with a playhead, used in
/// the play bar (replaces the slider). Tap/drag handled by the parent.
class _TimeRulerPainter extends CustomPainter {
  final int positionMs;
  final int durationMs;
  _TimeRulerPainter({required this.positionMs, required this.durationMs});

  String _fmt(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (durationMs <= 0 || w <= 0) return;
    final durSec = durationMs / 1000.0;
    final baseY = h - 6;
    canvas.drawLine(
      Offset(0, baseY),
      Offset(w, baseY),
      Paint()
        ..color = const Color(0x22FFFFFF)
        ..strokeWidth = 1,
    );

    // Pick a label step (1,2,5,10,...s) so ~6 labels fit without crowding.
    final approx = (durSec / 6).ceil().clamp(1, 600);
    const steps = [1, 2, 5, 10, 15, 30, 60, 120, 300];
    final step = steps.firstWhere((s) => s >= approx, orElse: () => 600);
    final minor = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 1;

    for (int s = 0; s <= durSec.ceil(); s++) {
      final x = (s / durSec) * w;
      final isMajor = s % step == 0;
      canvas.drawLine(
        Offset(x, baseY),
        Offset(x, baseY - (isMajor ? 10 : 5)),
        isMajor ? major : minor,
      );
      if (isMajor) {
        final tpr = TextPainter(
          text: TextSpan(
            text: _fmt(s),
            style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 9),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final lx = (x - tpr.width / 2).clamp(0.0, w - tpr.width);
        tpr.paint(canvas, Offset(lx, 0));
      }
    }

    // Progress fill + playhead.
    final px = (positionMs / durationMs).clamp(0.0, 1.0) * w;
    canvas.drawRect(
      Rect.fromLTRB(0, baseY - 1.5, px, baseY + 1.5),
      Paint()..color = AppColors.primary.withOpacity(0.5),
    );
    canvas.drawLine(
      Offset(px, 2),
      Offset(px, h),
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      Offset(px, baseY),
      3.5,
      Paint()..color = AppColors.primary,
    );
  }

  @override
  bool shouldRepaint(covariant _TimeRulerPainter old) =>
      old.positionMs != positionMs || old.durationMs != durationMs;
}

class _OnsetPainter extends CustomPainter {
  final List<int> onsets;
  final double pxPerSec;
  final double leftPad;
  _OnsetPainter({
    required this.onsets,
    required this.pxPerSec,
    required this.leftPad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x9900E5A0)
      ..strokeWidth = 1.5;
    // Small triangle tick at the top of each onset so it's easy to spot where
    // speech starts (align your block's left edge to these).
    final tick = Paint()
      ..color = const Color(0xCC00E5A0)
      ..style = PaintingStyle.fill;
    for (final o in onsets) {
      final x = leftPad + o / 1000.0 * pxPerSec;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
      final path = Path()
        ..moveTo(x - 3, 0)
        ..lineTo(x + 3, 0)
        ..lineTo(x, 5)
        ..close();
      canvas.drawPath(path, tick);
    }
  }

  @override
  bool shouldRepaint(covariant _OnsetPainter old) => old.onsets != onsets;
}
