import 'package:file_picker/file_picker.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import '../theme/app_theme.dart';
import '../i18n/i18n.dart';
import '../models/subtitle_style_model.dart';
import '../providers/project_provider.dart';
import '../services/gemini_speech_service.dart';
import '../services/groq_speech_service.dart';
import '../services/openai_whisper_service.dart';
import '../services/audio_sync_service.dart';
import '../services/export_service.dart';
import '../services/subtitle_export_service.dart';
import '../services/image_search_service.dart';
import '../services/sfx_search_service.dart';
import '../services/sticker_service.dart';
import '../services/lao_font_service.dart';
import '../services/custom_font_service.dart';
import '../services/lao_word_service.dart';
import '../services/thumbnail_service.dart';
import '../services/media_info_service.dart';
import '../services/clip_player_controller.dart';
import '../services/api_config.dart';
import '../services/free_quota_service.dart';
import '../services/tts_service.dart';
import '../services/sfx_player_service.dart';
import '../utils/sfx_mapper.dart';
import '../widgets/style_preview_card.dart';
import 'export_screen.dart';
import 'settings_screen.dart';
import 'processing_screen.dart';
import 'tap_sync_screen.dart';

part 'editor/editor_playback.dart';
part 'editor/editor_effects.dart';
part 'editor/editor_text_tools.dart';
part 'editor/editor_preview.dart';
part 'editor/editor_style.dart';
part 'editor/editor_timeline.dart';
part 'editor/editor_transcript.dart';
part 'editor/editor_auto.dart';
part 'editor/editor_overlays.dart';
part 'editor/editor_export.dart';
part 'editor/editor_painters.dart';

// Available Lao-compatible fonts
const _laoFonts = [
  ('NotoSansLao', 'Noto Sans Lao', 'ທຳມະດາ'),
  ('NotoSerifLao', 'Noto Serif Lao', 'ຕົວຂຽນ'),
  ('NotoSansLaoLooped', 'Noto Sans Lao Looped', 'ມົນ'),
  ('Default', 'Default', 'System'),
];

// Available Thai-compatible fonts
const _thaiFonts = [
  ('NotoSansThai', 'Noto Sans Thai', 'ทั่วไป'),
  ('NotoSerifThai', 'Noto Serif Thai', 'มีหัว'),
  ('NotoSansThaiLooped', 'Noto Sans Thai Looped', 'แบบมน'),
  ('Default', 'Default', 'System'),
];

/// Default subtitle font for a given display language.
String defaultFontForLang(String lang) =>
    lang == 'th' ? 'NotoSansThai' : 'NotoSansLao';

/// Thai labels for SFX tiles (title, subtitle), keyed by SfxType. Used only
/// when the UI language is Thai; otherwise the Lao literals at the call sites
/// are shown. Keeps the 30+ call sites untouched.
const Map<SfxType, (String, String)> _sfxThai = {
  SfxType.pop: ('เสียง Pop', 'ยอดนิยม'),
  SfxType.pop2: ('เสียง Pop 2', 'ยอดนิยม 2'),
  SfxType.punch: ('เสียง Punch', 'เสียงตี/ชก'),
  SfxType.punch2: ('เสียง Punch 2', 'เสียงตี/ชก 2'),
  SfxType.slap: ('เสียง Slap', 'เสียงตบหน้า'),
  SfxType.wow: ('เสียง Wow', 'เสียงว้าว'),
  SfxType.cricket: ('เสียง Cricket', 'เสียงจิ้งหรีด (เงียบ/จืด)'),
  SfxType.vineBoom: ('เสียง Vine Boom', 'เสียงตูมแบบมีมดังๆ'),
  SfxType.laugh: ('เสียง Laugh', 'เสียงหัวเราะ'),
  SfxType.boing: ('เสียง Boing', 'เสียงเด้งดึ๋ง'),
  SfxType.thud: ('เสียง Thud', 'เสียงของตกหนักๆ'),
  SfxType.squeak: ('เสียง Squeak', 'เสียงบีบหนู'),
  SfxType.quack: ('เสียง Quack', 'เสียงเป็ด'),
  SfxType.swoosh: ('เสียง Swoosh', 'เสียงปาด'),
  SfxType.swoosh2: ('เสียง Swoosh 2', 'เสียงปาด 2'),
  SfxType.whoosh: ('เสียง Whoosh', 'เสียงลม/เสียงเคลื่อนที่'),
  SfxType.whoosh2: ('เสียง Whoosh 2', 'เสียงลม/เสียงเคลื่อนที่ 2'),
  SfxType.whoosh3: ('เสียง Whoosh 3', 'เสียงลม/เสียงเคลื่อนที่ 3'),
  SfxType.whoosh4: ('เสียง Whoosh 4', 'เสียงลม/เสียงเคลื่อนที่ 4'),
  SfxType.whoosh5: ('เสียง Whoosh 5', 'เสียงลม/เสียงเคลื่อนที่ 5'),
  SfxType.ding: ('เสียง Ding', 'เสียงกระดิ่ง/แจ้งเตือน'),
  SfxType.ding2: ('เสียง Ding 2', 'เสียงกระดิ่ง/แจ้งเตือน 2'),
  SfxType.applause: ('เสียง Applause', 'เสียงตบมือ'),
  SfxType.cameraShutter: ('เสียง Camera Shutter', 'เสียงกดชัตเตอร์กล้อง'),
  SfxType.cashRegister: ('เสียง Cash Register', 'เสียงเครื่องคิดเงิน'),
  SfxType.recordScratch: ('เสียง Record Scratch', 'เสียงแผ่นเสียงสะดุด'),
  SfxType.badumtss: ('เสียง Ba Dum Tss', 'เสียงกลองรับมุกตลก'),
  SfxType.beep: ('เสียง Beep', 'เสียงบี๊บ'),
  SfxType.correct: ('เสียง Correct', 'เสียงถูกต้อง'),
  SfxType.buzzer: ('เสียง Buzzer', 'เสียงผิดพลาด/หมดเวลา'),
  SfxType.magic: ('เสียง Magic', 'เสียงเวทมนตร์'),
  SfxType.typing: ('เสียง Typing', 'เสียงพิมพ์คีย์บอร์ด'),
  SfxType.glitch: ('เสียง Glitch', 'เสียงโทรทัศน์ช็อต'),
  SfxType.airhorn: ('เสียง Airhorn', 'เสียงแตรลม'),
  SfxType.pop3: ('เสียง Pop 3', 'ยอดนิยม 3'),
  SfxType.pop4: ('เสียง Pop 4', 'ยอดนิยม 4'),
  SfxType.pop5: ('เสียง Pop 5', 'ยอดนิยม 5'),
  SfxType.punch3: ('เสียง Punch 3', 'เสียงตี/ชก 3'),
  SfxType.punch4: ('เสียง Punch 4', 'เสียงตี/ชก 4'),
  SfxType.punch5: ('เสียง Punch 5', 'เสียงตี/ชก 5'),
  SfxType.slap2: ('เสียง Slap 2', 'เสียงตบหน้า 2'),
  SfxType.wow2: ('เสียง Wow 2', 'เสียงว้าว 2'),
  SfxType.squeak2: ('เสียง Squeak 2', 'เสียงบีบหนู 2'),
  SfxType.squeak3: ('เสียง Squeak 3', 'เสียงบีบหนู 3'),
  SfxType.squeak4: ('เสียง Squeak 4', 'เสียงบีบหนู 4'),
  SfxType.squeek: ('เสียง Squeek', 'เสียงบีบหนู (อื่น)'),
  SfxType.whoosh6: ('เสียง Whoosh 6', 'เสียงลม/เคลื่อนที่ 6'),
  SfxType.whoosh7: ('เสียง Whoosh 7', 'เสียงลม/เคลื่อนที่ 7'),
  SfxType.whoosh8: ('เสียง Whoosh 8', 'เสียงลม/เคลื่อนที่ 8'),
  SfxType.whoosh9: ('เสียง Whoosh 9', 'เสียงลม/เคลื่อนที่ 9'),
  SfxType.whoosh10: ('เสียง Whoosh 10', 'เสียงลม/เคลื่อนที่ 10'),
  SfxType.cameraShutter2: ('เสียง Camera Shutter 2', 'เสียงกดชัตเตอร์กล้อง 2'),
  SfxType.cameraShutter3: ('เสียง Camera Shutter 3', 'เสียงกดชัตเตอร์กล้อง 3'),
  SfxType.cashRegister2: ('เสียง Cash Register 2', 'เสียงเครื่องคิดเงิน 2'),
  SfxType.recordScratch2: ('เสียง Record Scratch 2', 'เสียงแผ่นเสียงสะดุด 2'),
  SfxType.badumtss2: ('เสียง Ba Dum Tss 2', 'เสียงกลองรับมุกตลก 2'),
};

/// Font options to show for a project, based on the script(s) it displays.
/// Thai projects get Thai fonts; Lao projects get Lao fonts; bilingual
/// Thai+Lao shows both groups so each line can pick a font that renders it.
List<(String, String, String)> _fontOptionsFor(SubtitleProject p) {
  final bilingual = p.translateMode == TranslateMode.bilingual;
  final needsThai =
      p.language == 'th' || (bilingual && p.sourceLanguage == 'th');
  final needsLao =
      p.language == 'lo' || (bilingual && p.sourceLanguage == 'lo');
  if (needsThai && !needsLao) return _thaiFonts;
  if (needsThai && needsLao) {
    // Both scripts: Thai fonts first, then Lao fonts (Default appears once).
    return [
      ..._thaiFonts.where((f) => f.$1 != 'Default'),
      ..._laoFonts,
    ];
  }
  return _laoFonts; // Lao-only, English, or unset → Lao set (Latin renders fine)
}

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
    'NotoSansThai' => GoogleFonts.notoSansThai(textStyle: base),
    'NotoSerifThai' => GoogleFonts.notoSerifThai(textStyle: base),
    'NotoSansThaiLooped' => GoogleFonts.notoSansThaiLooped(textStyle: base),
    _ => base,
  };
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

// Former static members of _EditorScreenState (top level so the
// editor part files can use them).
const double _deg2rad = 3.141592653589793 / 180.0;
/// Unambiguous filler words (lo / th / en). Kept conservative on purpose so
/// meaningful words are never removed.
const Set<String> _fillerWords = {
  // Lao
  'ເອີ', 'ເອີ້', 'ເອິ', 'ອື', 'ອືມ', 'ອ້າ', 'ເອ່ີ',
  // Thai
  'เออ', 'เอ้อ', 'เอ่อ', 'อ่า', 'อืม', 'เอิ่ม', 'อ่ะ', 'อึ', 'เอ้',
  // English
  'um', 'umm', 'uh', 'uhh', 'uhm', 'er', 'err', 'hmm', 'ah', 'eh',
};

List<(SubtitleAnimation, IconData, String)> get _animOptions => [
  (SubtitleAnimation.none, Icons.block, tr('ed.none')),
  (SubtitleAnimation.fadeIn, Icons.opacity, 'Fade'),
  (SubtitleAnimation.slideUp, Icons.arrow_upward, 'Slide ↑'),
  (SubtitleAnimation.slideDown, Icons.arrow_downward, 'Slide ↓'),
  (SubtitleAnimation.slideLeft, Icons.arrow_back, 'Slide ←'),
  (SubtitleAnimation.bounceIn, Icons.open_with, 'Bounce'),
  (SubtitleAnimation.typewriter, Icons.keyboard_outlined, tr('ed.typewriter')),
];

// Exit animations: typewriter doesn't apply as an exit effect.
List<(SubtitleAnimation, IconData, String)> get _exitAnimOptions => [
  (SubtitleAnimation.none, Icons.block, tr('ed.none')),
  (SubtitleAnimation.fadeIn, Icons.opacity, 'Fade'),
  (SubtitleAnimation.slideUp, Icons.arrow_upward, 'Slide ↑'),
  (SubtitleAnimation.slideDown, Icons.arrow_downward, 'Slide ↓'),
  (SubtitleAnimation.slideLeft, Icons.arrow_back, 'Slide ←'),
  (SubtitleAnimation.bounceIn, Icons.open_with, 'Bounce'),
];

List<(AnimationSpeed, String)> get _speedOptions => [
  (AnimationSpeed.slow, tr('ed.slow')),
  (AnimationSpeed.normal, tr('ed.normal')),
  (AnimationSpeed.fast, tr('ed.fast')),
];

const _karaokeColors = [
  Color(0xFF9C59F5), // purple
  Color(0xFFFF6B9D), // pink
  Color(0xFF4DABF7), // blue
  Color(0xFFFF922B), // orange
  Color(0xFF51CF66), // green
  Color(0xFFFF4757), // red
  Color(0xFFFFD43B), // yellow
  Color(0xFF22D3EE), // cyan
];


class _EditorScreenState extends State<EditorScreen>
    with TickerProviderStateMixin {
  VideoPlayerController? _videoController;
  // B-roll video overlays: one muted, looping player per overlay id, synced to
  // the timeline so the clip plays in-place during preview (Export composites it
  // natively). Keyed by ImageOverlay.id.
  final Map<String, VideoPlayerController> _brollCtrls = {};
  final Set<String> _brollInit = {}; // ids whose controller is initializing
  final Set<String> _brollActive = {}; // ids currently inside their visible range (aligned)
  // Auto Edit pipeline: which steps to run (user-togglable checklist, persisted).
  final Map<String, bool> _autoEditSteps = {
    'proofread': true,
    'karaoke': true,
    'emoji': true,
    'sfx': true,
    'fade': true,
    'zoom': true,
    'cut': true,
    'broll': false, // heavy (downloads) → off by default
  };
  bool _autoEditStepsLoaded = false;
  // CapCut-style keyframe editing: pinch=scale / drag=pan on the preview while a
  // clip is selected → auto-create/update a zoom keyframe at the playhead.
  ZoomEffect? _kfZoom;
  ZoomKeyframe? _kfActive;
  double _kfBaseScale = 1.0;
  bool _kfMoved = false;
  // Smooth 60fps timeline auto-scroll during playback (interpolated between the
  // coarse position reports from video_player).
  Ticker? _scrollTicker;
  int _anchorPosMs = 0;
  int _anchorWallMs = 0;
  // When play starts, ExoPlayer takes a moment to actually begin advancing.
  // Hold the wall-clock scroll interpolation until the first real frame so the
  // timeline doesn't race ahead then snap back (a one-time stutter at play).
  bool _waitingFirstPlayFrame = false;
  int _playStartPosMs = 0;
  bool _appendingClip = false; // true while merging an appended clip
  int _activeClip = 0; // index of the clip the preview controller is showing
  int _mcSelected = -1; // selected multi-clip block on the timeline (-1 = none)
  int _dragClipIndex = -1; // clip block being long-press dragged (-1 = none)
  double _dragClipDx = 0; // horizontal drag offset (px) while reordering
  bool _switchingClip = false; // guards against concurrent clip swaps (crash)
  // Native ExoPlayer gapless multi-clip player (CapCut-style smooth playback).
  ClipPlayerController? _clipPlayer;
  int? _clipTextureId;
  Timer? _clipPoll;
  // Per-clip filmstrip thumbnails (keyed by clip id) for the inline timeline.
  final Map<String, List<({int ms, String path})>> _clipThumbs = {};
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
  int? _selectedClipIndex; // selected video clip on the filmstrip
  int _clipTrimLeft = 0; // live trim preview (ms) on the selected clip's head
  int _clipTrimRight = 0; // live trim preview (ms) on the selected clip's tail
  String? _selectedImageId; // selected image overlay
  double _imgBaseScale = 1.0; // scale at gesture start
  double _imgBaseRot = 0.0; // rotation (deg) at gesture start
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
  bool _importingFont = false; // true while the font picker / copy is running
  bool _isPro = false;
  final TtsService _ttsService = TtsService();
  int _lastSfxTickMs = -1;

  // ── AI-voice track (separate audio layer, played alongside the video) ──
  AudioPlayer? _aiVoicePlayer;
  String? _aiVoiceLoadedPath; // path currently loaded into _aiVoicePlayer
  AudioPlayer? _bgMusicPlayer;
  String? _bgMusicLoadedPath;
  bool _bgDucked = false; // current live-duck state (preview)
  Timer? _mixerSaveDebounce;
  int _lastAiDriftCheckMs = 0;

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
    _ensureAiVoicePlayer();
    _ensureBgMusicPlayer();
  }

  @override
  void dispose() {
    _scrubDebounce?.cancel();
    _mixerSaveDebounce?.cancel();
    _clipPoll?.cancel();
    _clipPlayer?.dispose();
    _scrollTicker?.dispose();
    _videoController?.removeListener(_onVideoUpdate);
    _videoController?.dispose();
    _aiVoicePlayer?.dispose();
    _bgMusicPlayer?.dispose();
    for (final c in _brollCtrls.values) { c.dispose(); }
    _brollCtrls.clear();
    _brollActive.clear();
    _tabController.dispose();
    _timelineScroll.dispose();
    super.dispose();
  }

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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        strokeWidth: 3.5,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        tr('ed.analyzingWave'),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('ed.analyzingDeadAir'),
                        style: const TextStyle(
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

}
