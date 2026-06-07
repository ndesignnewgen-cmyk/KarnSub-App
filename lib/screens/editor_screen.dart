import 'package:file_picker/file_picker.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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
import 'processing_screen.dart';

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
  static const double _deg2rad = 3.141592653589793 / 180.0;
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
    await _applyTrackVolumes();
    _ensureBrollControllers(project); // restore B-roll players for saved overlays
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
    
    if (_keptRegions.isEmpty) {
      setState(() => _analyzingAudio = true);
      try {
        final flatList = await ExportService.detectSpeechRegions(project.videoPath!);
        final durMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 10000;
        _keptRegions = computeKeptRegions(flatList, durMs);
      } catch (e) {
        _toast(tr('ed.analyzeFail', {'e': e.toString()}));
      } finally {
        setState(() => _analyzingAudio = false);
      }
    }
    
    if (_keptRegions.isNotEmpty) {
      project.isAutoCut = true;
      provider.updateProject(project);
      _toast(tr('ed.autoCutOn'));
      setState(() {});
    } else {
      _toast(tr('ed.noSpeech'));
    }
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

  /// Live zoom scale + focal point at [ms] for the PREVIEW (mirrors native).
  /// Returns (scale, focusX, focusY); scale 1.0 = no zoom.
  (double, double, double) _zoomAt(int ms) {
    final zs = context.read<ProjectProvider>().currentProject?.zoomEffects;
    if (zs == null) return (1.0, 0.5, 0.5);
    for (final z in zs) {
      final s0 = z.startTime.inMilliseconds, e0 = z.endTime.inMilliseconds;
      if (ms < s0 || ms > e0) continue;
      if (z.keyframes.length >= 2) {
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
        final t = ((ms - a.timeMs) / span).clamp(0.0, 1.0);
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

  /// Delete the currently-selected video clip (removes its span + ripples).
  void _deleteSelectedClip(ProjectProvider provider) {
    final project = provider.currentProject;
    if (project == null || _selectedClipIndex == null) return;
    final clips = _videoClips(project);
    if (_selectedClipIndex! >= clips.length) {
      setState(() => _selectedClipIndex = null);
      return;
    }
    if (clips.length <= 1) {
      _toast(tr('ed.needOneClip'));
      return;
    }
    final clip = clips[_selectedClipIndex!];
    _cutRange(provider, clip.start, clip.end);
    setState(() => _selectedClipIndex = null);
  }

  void _onVideoUpdate() {
    if (!mounted) return;
    final v = _videoController!.value;
    final pos = v.position;
    final playing = v.isPlaying;
    _position = pos; // cheap field update (no rebuild) for scroll math
    if (!playing) _scrollTicker?.stop();

    final project = context.read<ProjectProvider>().currentProject;

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
            _videoController!.seekTo(Duration(milliseconds: nextStartMs));
            return;
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

  @override
  void dispose() {
    _scrubDebounce?.cancel();
    _mixerSaveDebounce?.cancel();
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
    final c = _videoController;
    if (c == null) return;
    _scrubDebounce?.cancel(); // drop any pending scrub seek
    if (_isPlaying) {
      c.pause();
      _pauseAiVoice();
      _pauseBgMusic();
      _pauseBroll();
      _scrollTicker?.stop();
      _scrollTimelineToPosition(); // settle exactly on the current position
      _lastSfxTickMs = -1;
    } else {
      final project = context.read<ProjectProvider>().currentProject;
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
                              Positioned.fill(child: videoLayer),
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
        ));
        continue;
      }

      // Allow scaling beyond the screen (up to 3× video width). The widget is
      // sized to the scaled width; rotation/flip applied around its centre.
      final imgW = (ov.scale * w).clamp(20.0, w * 3.0);
      widgets.add(Positioned(
        // Centre the (possibly oversized) box on (x,y); it may extend off-screen.
        left: ov.x * w - imgW / 2,
        top: ov.y * h - imgW / 2,
        width: imgW,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // onScale handles drag (1 finger) + pinch-zoom + twist-rotate (2).
          onScaleStart: (_) {
            _pauseForEdit();
            provider.pushHistory();
            _imgBaseScale = ov.scale;
            _imgBaseRot = ov.rotation;
            setState(() {
              _selectedImageId = ov.id;
              _selectedIndex = null;
              _selectedSfxId = null;
              _selectedClipIndex = null;
            });
          },
          onScaleUpdate: (d) {
            setState(() {
              if (d.pointerCount >= 2) {
                ov.scale = (_imgBaseScale * d.scale).clamp(0.05, 3.0);
                ov.rotation = (_imgBaseRot + d.rotation * 180 / 3.1415926535) % 360;
              }
              // focalPointDelta works for both 1- and 2-finger drags.
              ov.x = (ov.x + d.focalPointDelta.dx / w).clamp(-0.5, 1.5);
              ov.y = (ov.y + d.focalPointDelta.dy / h).clamp(-0.5, 1.5);
            });
            provider.liveUpdate();
          },
          onScaleEnd: (_) => provider.commit(),
          child: Transform.rotate(
            angle: ov.rotation * 3.1415926535 / 180.0,
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
                    tr('ed.previewExample'),
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
              _importingFont ? tr('ed.importingFont') : tr('ed.importFont'),
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
          content: Text(tr('ed.fontImported', {'name': font.name})),
          backgroundColor: AppColors.surface,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _importingFont = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('ed.fontImportFail', {'e': '$e'})),
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
    // If the deleted font was in use, fall back to the script-matching default.
    if (project.fontFamily == key) {
      project.fontFamily = defaultFontForLang(project.language);
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
              ],
            ),
          ),
          // Clip outlines + tap-to-select + split dividers.
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
              if (_selectedImageId != null) ...[
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

              // ── Track tools (moved from the Timeline header) ──
              item(Icons.music_note, tr('ed.sfxBtn'),
                  () => _showAddSfxSheet(provider)),
              item(Icons.auto_awesome, tr('ed.autoSfxBtn'),
                  () => _applyAutoSfx(provider),
                  customColor: const Color(0xFFFFB703)),
              item(Icons.tune, tr('ed.mixerBtn'),
                  () => _showAudioMixerSheet(provider)),
              item(Icons.image_outlined, tr('ed.image'),
                  () => _pickImageOverlay(provider)),
              item(Icons.video_library_outlined, tr('ed.broll'),
                  () => _pickVideoOverlay(provider),
                  customColor: const Color(0xFF7C4DFF)),
              item(Icons.ondemand_video, tr('ed.webBroll'),
                  () => _showWebBrollSheet(provider),
                  customColor: const Color(0xFF7C4DFF)),
              item(Icons.image_search, tr('ed.webImage'),
                  () => _showWebImageSheet(provider),
                  customColor: const Color(0xFF00BFA5)),
              item(Icons.gif_box, tr('ed.autoMeme'),
                  () => _autoMeme(provider),
                  customColor: const Color(0xFFEA4C89)),
              item(Icons.movie_filter, tr('ed.autoBroll'),
                  () => _autoBroll(provider),
                  customColor: const Color(0xFF7C4DFF)),
              item(Icons.library_music, tr('ed.webSfx'),
                  () => _showWebSfxSheet(provider),
                  customColor: const Color(0xFF00BFA5)),
              item(Icons.blur_on_rounded, tr('ed.bgBlur'),
                  () => _toggleBgBlur(provider),
                  customColor: (provider.currentProject?.bgBlur ?? false)
                      ? AppColors.primary
                      : AppColors.textHint),

              // Divider line between global AI tools and segment tools
              Container(
                width: 1,
                height: 24,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: AppColors.border,
              ),

              // 4. Split Button
              item(Icons.content_cut, tr('ed.cut'), () => _splitAtPlayhead(provider, i)),

              // 5. Merge Button
              item(Icons.merge, tr('ed.merge'), () => _mergeWithNext(provider, i)),

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

  /// AI-voice track bar (spans the clip duration at its offset). Drag to move,
  /// tap to select (shows the AI toolbar), and it opens the mixer via toolbar.
  /// Timeline bars for image overlays (one row, like SFX). Drag to move,
  /// trim handles to change duration, tap to select.
  List<Widget> _buildImageOverlayBars(
    ProjectProvider provider,
    double leftPad,
    int totalMs,
    double top,
    double h,
  ) {
    final project = provider.currentProject;
    if (project == null) return const [];
    return project.imageOverlays.map((ov) {
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
        top: top,
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

Widget _buildTimelineTab() {
    return Consumer<ProjectProvider>(
      builder: (context, provider, _) {
        final project = provider.currentProject;
        final segments = project?.segments ?? [];
        if (project == null || segments.isEmpty) {
          return Center(
            child: Text(
              tr('ed.noSubtitle'),
              style: const TextStyle(color: AppColors.textHint),
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
                  final totalDynamicHeight =
                      (hasImages ? imgTop + sfxH : aiTop + sfxH) + 40.0;
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
                                  ..._buildImageOverlayBars(provider, leftPad, totalMs, imgTop, sfxH),
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
      final vids = await ImageSearchService.searchVideo(q, limit: 4);
      if (vids.isNotEmpty) {
        path = await ImageSearchService.downloadVideo(vids.first);
        isVid = path != null;
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
  Future<void> _autoBroll(ProjectProvider provider) async {
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
        final vids = await ImageSearchService.searchVideo(q, limit: 4);
        if (vids.isNotEmpty) {
          path = await ImageSearchService.downloadVideo(vids.first);
          isVid = path != null;
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
        } catch (_) {}
      }

      // Karaoke word units (so the colour sweep moves word-by-word).
      if (S['karaoke'] == true) {
        step(tr('ed.autoEditStepKaraoke'));
        try {
          await LaoWordService.refineToRealWords(segs, locale: project.language);
          await LaoWordService.ensureWordUnits(segs, locale: project.language);
        } catch (_) {}
      }

      // Emoji + highlight via Gemini (best-effort; quota-safe internally).
      if (S['emoji'] == true && hasKey) {
        step(tr('ed.autoEditStepEmoji'));
        try {
          await GeminiSpeechService(apiKey: apiKey).autoEmojiHighlight(segs);
        } catch (_) {}
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
        for (final seg in segs) {
          final emoji = seg.emoji;
          SfxType? sfx;
          if (emoji != null && emoji.isNotEmpty) {
            sfx = SfxMapper.getSfxForEmoji(emoji);
          }
          if (sfx != null) {
            final already = project.sfxBlocks.any((b) =>
                (b.startTime - seg.startTime).abs() <
                const Duration(milliseconds: 200));
            if (!already) {
              provider.addSfxBlock(SfxBlock(
                  id: const Uuid().v4(), type: sfx, startTime: seg.startTime));
              sfxCount++;
            }
          }
        }
      }

      // Fade IN/OUT at the very start & end.
      if (S['fade'] == true) {
        step(tr('ed.autoEditStepFade'));
        _addAutoFades(provider);
      }

      // Subtle punch-in zoom on emphasised lines.
      if (S['zoom'] == true) {
        step(tr('ed.autoEditStepZoom'));
        _addAutoZooms(provider, segs);
      }

      // Cut silence (Auto-Cut) if not already on.
      if (S['cut'] == true) {
        step(tr('ed.autoEditStepCut'));
        if (!project.isAutoCut && project.videoPath != null) {
          try {
            if (_keptRegions.isEmpty) {
              final flat =
                  await ExportService.detectSpeechRegions(project.videoPath!);
              final durMs = _duration.inMilliseconds > 0
                  ? _duration.inMilliseconds
                  : 10000;
              _keptRegions = computeKeptRegions(flat, durMs);
            }
            if (_keptRegions.isNotEmpty) {
              project.isAutoCut = true;
              provider.updateProject(project);
            }
          } catch (_) {}
        }
      }

      // Auto B-roll (heavy: network downloads) — last.
      int brollCount = 0;
      if (S['broll'] == true && hasKey) {
        brollCount = await _runAutoBrollCore(provider, apiKey,
            onStep: (i, n) =>
                step(tr('ed.autoBrollStep', {'i': i, 'n': n})));
      }

      provider.commit();
      if (S['broll'] == true) _ensureBrollControllers(provider.currentProject);
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() {});
        final extra = [
          if (sfxCount > 0) '$sfxCount SFX',
          if (brollCount > 0) '$brollCount B-roll',
        ].join(' · ');
        _toast('${tr('ed.autoEditDone')}${extra.isNotEmpty ? ' · $extra' : ''}');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _toast(tr('ed.autoEmojiFail'));
      }
    }
  }

  Future<void> _autoEmoji(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null || project.segments.isEmpty) return;
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
      final hasGroq = (await ApiConfig.getGroqKey())?.isNotEmpty ?? false;
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

  /// Pick an image from the device and add it as an overlay at the playhead.
  Future<void> _pickImageOverlay(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null) return;
    _pauseForEdit();
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.single.path == null) return;
    final srcPath = result.files.single.path!;
    try {
      final supportDir = await getApplicationSupportDirectory();
      final dir = Directory(p.join(supportDir.path, 'overlays'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ext = p.extension(srcPath);
      final dest = p.join(
          dir.path, 'img_${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(srcPath).copy(dest);

      final startMs = _position.inMilliseconds;
      final endMs = (startMs + 3000).clamp(0, _duration.inMilliseconds);
      final overlay = ImageOverlay(
        id: const Uuid().v4(),
        path: dest,
        startTime: Duration(milliseconds: startMs),
        endTime: Duration(milliseconds: endMs == startMs ? startMs + 3000 : endMs),
      );
      provider.addImageOverlay(overlay);
      setState(() => _selectedImageId = overlay.id);
      _toast(tr('ed.imageAdded'));
    } catch (e) {
      _showErrorBanner(tr('ed.imageAddFail', {'e': e.toString()}));
    }
  }

  /// Pick a VIDEO clip from the device and add it as a B-roll overlay at the
  /// playhead — full-width, muted, plays in-place (preview + native export).
  Future<void> _pickVideoOverlay(ProjectProvider provider) async {
    final project = provider.currentProject;
    if (project == null) return;
    if (!_isPro) {
      _showProFeatureDialog(tr('ed.brollPro'));
      return;
    }
    _pauseForEdit();
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result == null || result.files.single.path == null) return;
    final srcPath = result.files.single.path!;
    try {
      final supportDir = await getApplicationSupportDirectory();
      final dir = Directory(p.join(supportDir.path, 'overlays'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ext = p.extension(srcPath);
      final dest = p.join(
          dir.path, 'vid_${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(srcPath).copy(dest);

      // Probe the clip length for a sensible default duration (cap 6s).
      int clipMs = 4000;
      try {
        final probe = VideoPlayerController.file(File(dest));
        await probe.initialize();
        clipMs = probe.value.duration.inMilliseconds;
        await probe.dispose();
      } catch (_) {}

      final startMs = _position.inMilliseconds;
      final span = clipMs.clamp(1000, 6000);
      var endMs = startMs + span;
      if (_duration.inMilliseconds > 0 && endMs > _duration.inMilliseconds) {
        endMs = _duration.inMilliseconds;
      }
      if (endMs <= startMs) endMs = startMs + span;
      final overlay = ImageOverlay(
        id: const Uuid().v4(),
        path: dest,
        startTime: Duration(milliseconds: startMs),
        endTime: Duration(milliseconds: endMs),
        x: 0.5,
        y: 0.40, // (used only if cover is turned off)
        scale: 1.0,
        isVideo: true,
        cover: true, // full-screen B-roll by default
      );
      provider.addImageOverlay(overlay);
      _ensureBrollControllers(provider.currentProject);
      setState(() => _selectedImageId = overlay.id);
      _toast(tr('ed.brollAdded'));
    } catch (e) {
      _showErrorBanner(tr('ed.imageAddFail', {'e': e.toString()}));
    }
  }

  /// Web image search → insert as an overlay at the playhead (Openverse, free).
  void _showWebImageSheet(ProjectProvider provider) {
    _pauseForEdit();
    // Pre-fill the query from the subtitle near the playhead.
    final segs = provider.currentProject?.segments ?? [];
    String seed = '';
    for (final s in segs) {
      if (_position >= s.startTime && _position <= s.endTime) {
        seed = s.text;
        break;
      }
    }
    final queryCtrl = TextEditingController(text: seed);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        List<WebImage> results = [];
        bool loading = false;
        bool inserting = false;
        int source = 0; // 0 = images (Openverse), 1 = meme GIF (Tenor)
        bool needTenorKey = false;
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> runSearch() async {
            FocusScope.of(ctx).unfocus();
            setSheet(() {
              loading = true;
              needTenorKey = false;
            });
            List<WebImage> r;
            if (source == 1) {
              // Meme GIF: works with no key (Tenor v1) — uses the user's own
              // Tenor v2 key if they added one (better quota).
              final tk = await ApiConfig.getTenorKey();
              r = await ImageSearchService.searchMeme(queryCtrl.text, userKey: tk);
            } else {
              r = await ImageSearchService.search(queryCtrl.text);
            }
            setSheet(() {
              results = r;
              loading = false;
            });
          }

          Future<void> aiKeyword() async {
            final apiKey = await ApiConfig.getApiKey();
            if (apiKey == null || apiKey.isEmpty || queryCtrl.text.trim().isEmpty) {
              return;
            }
            setSheet(() => loading = true);
            try {
              final en = await GeminiSpeechService(apiKey: apiKey)
                  .translateTexts([queryCtrl.text.trim()], 'en');
              if (en.isNotEmpty && en.first.trim().isNotEmpty) {
                queryCtrl.text = en.first.trim();
              }
            } catch (_) {}
            await runSearch();
          }

          Future<void> insert(WebImage img) async {
            if (inserting) return;
            setSheet(() => inserting = true);
            final path =
                await ImageSearchService.download(img.full, fallbackUrl: img.thumb);
            setSheet(() => inserting = false);
            if (path == null) {
              _toast(tr('ed.webImageFail'));
              return;
            }
            final startMs = _position.inMilliseconds;
            final endMs = (startMs + 3000).clamp(0, _duration.inMilliseconds);
            final overlay = ImageOverlay(
              id: const Uuid().v4(),
              path: path,
              startTime: Duration(milliseconds: startMs),
              endTime:
                  Duration(milliseconds: endMs <= startMs ? startMs + 3000 : endMs),
            );
            provider.addImageOverlay(overlay);
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) {
              setState(() => _selectedImageId = overlay.id);
              _toast(tr('ed.imageAdded'));
            }
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.image_search, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(tr('ed.webImage'),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 4),
                  Text(source == 1 ? tr('ed.gifNote') : tr('ed.webImageHelp'),
                      style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                  const SizedBox(height: 10),
                  // Source toggle: Image (Openverse) vs Meme GIF (Tenor).
                  Row(children: [
                    for (int sIdx = 0; sIdx < 2; sIdx++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(sIdx == 0 ? tr('ed.srcImage') : tr('ed.srcMeme')),
                          selected: source == sIdx,
                          showCheckmark: false,
                          labelStyle: TextStyle(
                              color: source == sIdx ? Colors.white : AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.surfaceLight,
                          onSelected: (_) => setSheet(() {
                            source = sIdx;
                            results = [];
                            needTenorKey = false;
                          }),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: queryCtrl,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => runSearch(),
                        decoration: InputDecoration(
                          hintText: tr('ed.webImageHint'),
                          hintStyle: const TextStyle(color: AppColors.textHint),
                          filled: true,
                          fillColor: AppColors.surfaceLight,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: loading ? null : runSearch,
                      icon: const Icon(Icons.search, color: AppColors.primary),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: loading ? null : aiKeyword,
                      icon: const Icon(Icons.auto_awesome, size: 16, color: Color(0xFFFFB703)),
                      label: Text(tr('ed.webImageAi'),
                          style: const TextStyle(color: Color(0xFFFFB703), fontSize: 12)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 300,
                    child: loading
                        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                        : needTenorKey
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(tr('ed.needTenorKey'),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: AppColors.textHint)),
                                    const SizedBox(height: 10),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) => const SettingsScreen()));
                                      },
                                      icon: const Icon(Icons.settings, size: 16),
                                      label: Text(tr('ed.goToSettings')),
                                    ),
                                  ],
                                ),
                              )
                            : results.isEmpty
                            ? Center(
                                child: Text(tr('ed.webImageEmpty'),
                                    style: const TextStyle(color: AppColors.textHint)))
                            : GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                ),
                                itemCount: results.length,
                                itemBuilder: (_, i) => GestureDetector(
                                  onTap: inserting ? null : () => insert(results[i]),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      results[i].thumb,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                          color: AppColors.surfaceLight,
                                          child: const Icon(Icons.broken_image,
                                              color: AppColors.textHint)),
                                    ),
                                  ),
                                ),
                              ),
                  ),
                  if (inserting)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 8),
                        Text(tr('ed.webImageInserting'),
                            style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                      ]),
                    ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  /// Search B-roll VIDEO clips from the web (Pixabay) and drop a chosen one in
  /// as a full-screen video overlay at the playhead.
  void _showWebBrollSheet(ProjectProvider provider) {
    if (!_isPro) {
      _showProFeatureDialog(tr('ed.brollPro'));
      return;
    }
    _pauseForEdit();
    final segs = provider.currentProject?.segments ?? [];
    String seed = '';
    for (final s in segs) {
      if (_position >= s.startTime && _position <= s.endTime) {
        seed = s.text;
        break;
      }
    }
    final queryCtrl = TextEditingController(text: seed);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        List<WebVideo> results = [];
        bool loading = false;
        bool inserting = false;
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> runSearch() async {
            FocusScope.of(ctx).unfocus();
            setSheet(() => loading = true);
            final r = await ImageSearchService.searchVideoDetailed(queryCtrl.text);
            setSheet(() {
              results = r;
              loading = false;
            });
          }

          Future<void> aiKeyword() async {
            final apiKey = await ApiConfig.getApiKey();
            if (apiKey == null || apiKey.isEmpty || queryCtrl.text.trim().isEmpty) {
              return;
            }
            setSheet(() => loading = true);
            try {
              final en = await GeminiSpeechService(apiKey: apiKey)
                  .translateTexts([queryCtrl.text.trim()], 'en');
              if (en.isNotEmpty && en.first.trim().isNotEmpty) {
                queryCtrl.text = en.first.trim();
              }
            } catch (_) {}
            await runSearch();
          }

          Future<void> insert(WebVideo vid) async {
            if (inserting) return;
            setSheet(() => inserting = true);
            final path = await ImageSearchService.downloadVideo(vid.url);
            if (path == null) {
              setSheet(() => inserting = false);
              _toast(tr('ed.webImageFail'));
              return;
            }
            int clipMs = 4000;
            try {
              final probe = VideoPlayerController.file(File(path));
              await probe.initialize();
              clipMs = probe.value.duration.inMilliseconds;
              await probe.dispose();
            } catch (_) {}
            final startMs = _position.inMilliseconds;
            final span = clipMs.clamp(1000, 6000);
            var endMs = startMs + span;
            if (_duration.inMilliseconds > 0 && endMs > _duration.inMilliseconds) {
              endMs = _duration.inMilliseconds;
            }
            if (endMs <= startMs) endMs = startMs + span;
            final overlay = ImageOverlay(
              id: const Uuid().v4(),
              path: path,
              startTime: Duration(milliseconds: startMs),
              endTime: Duration(milliseconds: endMs),
              x: 0.5,
              y: 0.40,
              scale: 1.0,
              isVideo: true,
              cover: true,
            );
            provider.addImageOverlay(overlay);
            _ensureBrollControllers(provider.currentProject);
            setSheet(() => inserting = false);
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) {
              setState(() => _selectedImageId = overlay.id);
              _toast(tr('ed.brollAdded'));
            }
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.ondemand_video, color: Color(0xFF7C4DFF)),
                    const SizedBox(width: 8),
                    Text(tr('ed.webBroll'),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 4),
                  Text(tr('ed.webBrollHelp'),
                      style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: queryCtrl,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 14),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => runSearch(),
                        decoration: InputDecoration(
                          hintText: tr('ed.webImageHint'),
                          hintStyle: const TextStyle(color: AppColors.textHint),
                          filled: true,
                          fillColor: AppColors.surfaceLight,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: loading ? null : runSearch,
                      icon: const Icon(Icons.search, color: Color(0xFF7C4DFF)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: loading ? null : aiKeyword,
                      icon: const Icon(Icons.auto_awesome,
                          size: 16, color: Color(0xFFFFB703)),
                      label: Text(tr('ed.webImageAi'),
                          style: const TextStyle(
                              color: Color(0xFFFFB703), fontSize: 12)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 300,
                    child: loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF7C4DFF)))
                        : results.isEmpty
                            ? Center(
                                child: Text(tr('ed.webBrollEmpty'),
                                    style: const TextStyle(
                                        color: AppColors.textHint)))
                            : GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                  childAspectRatio: 16 / 9,
                                ),
                                itemCount: results.length,
                                itemBuilder: (_, i) => GestureDetector(
                                  onTap:
                                      inserting ? null : () => insert(results[i]),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.network(
                                          results[i].thumb,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Container(
                                              color: AppColors.surfaceLight,
                                              child: const Icon(Icons.movie,
                                                  color: AppColors.textHint)),
                                        ),
                                        const Center(
                                          child: Icon(Icons.play_circle_fill,
                                              color: Colors.white70, size: 34),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                  ),
                  if (inserting)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 8),
                            Text(tr('ed.webBrollInserting'),
                                style: const TextStyle(
                                    color: AppColors.textHint, fontSize: 12)),
                          ]),
                    ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  /// Search the BBC Sound Effects archive (keyless) and drop a chosen sound in
  /// as a custom SFX block at the playhead. Downloads WAV so export works.
  void _showWebSfxSheet(ProjectProvider provider) {
    _pauseForEdit();
    final segs = provider.currentProject?.segments ?? [];
    String seed = '';
    for (final s in segs) {
      if (_position >= s.startTime && _position <= s.endTime) {
        seed = s.text;
        break;
      }
    }
    final queryCtrl = TextEditingController(text: seed);
    final previewPlayer = AudioPlayer();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        List<WebSfx> results = [];
        bool loading = false;
        bool inserting = false;
        String? playingId;
        int sfxSource = 0; // 0 = Freesound (meme/UI, needs token), 1 = BBC (realistic, keyless)
        bool needFreesoundKey = false;
        return StatefulBuilder(builder: (ctx, setSheet) {
          Future<void> runSearch() async {
            FocusScope.of(ctx).unfocus();
            setSheet(() {
              loading = true;
              needFreesoundKey = false;
            });
            List<WebSfx> r;
            if (sfxSource == 0) {
              final token = await ApiConfig.getFreesoundKey();
              if (token == null || token.trim().isEmpty) {
                setSheet(() {
                  loading = false;
                  needFreesoundKey = true;
                  results = [];
                });
                return;
              }
              r = await SfxSearchService.searchFreesound(queryCtrl.text, token);
            } else {
              r = await SfxSearchService.search(queryCtrl.text);
            }
            setSheet(() {
              results = r;
              loading = false;
            });
          }

          Future<void> aiKeyword() async {
            final apiKey = await ApiConfig.getApiKey();
            if (apiKey == null ||
                apiKey.isEmpty ||
                queryCtrl.text.trim().isEmpty) {
              return;
            }
            setSheet(() => loading = true);
            try {
              final en = await GeminiSpeechService(apiKey: apiKey)
                  .translateTexts([queryCtrl.text.trim()], 'en');
              if (en.isNotEmpty && en.first.trim().isNotEmpty) {
                queryCtrl.text = en.first.trim();
              }
            } catch (_) {}
            await runSearch();
          }

          Future<void> preview(WebSfx s) async {
            try {
              if (playingId == s.id) {
                await previewPlayer.stop();
                setSheet(() => playingId = null);
                return;
              }
              await previewPlayer.stop();
              await previewPlayer.play(UrlSource(s.mp3Url));
              setSheet(() => playingId = s.id);
              previewPlayer.onPlayerComplete.first.then((_) {
                if (ctx.mounted) setSheet(() => playingId = null);
              });
            } catch (_) {}
          }

          Future<void> insert(WebSfx s) async {
            if (inserting) return;
            setSheet(() => inserting = true);
            var path = await SfxSearchService.download(s);
            // Freesound previews are mp3 → decode to WAV so export can read it.
            if (path != null && s.needsDecode) {
              try {
                const ch = MethodChannel('com.anniekaydee.subtitle_app/audio');
                final wavPath = path.replaceAll(RegExp(r'\.mp3$'), '.wav');
                await ch.invokeMethod('extractAudio',
                    {'videoPath': path, 'outputPath': wavPath});
                final wf = File(wavPath);
                if (wf.existsSync() && wf.lengthSync() > 44) {
                  try { File(path).deleteSync(); } catch (_) {}
                  path = wavPath;
                }
              } catch (_) {/* keep mp3 — preview works, export best-effort */}
            }
            setSheet(() => inserting = false);
            if (path == null) {
              _toast(tr('ed.webSfxFail'));
              return;
            }
            final durMs = s.durationMs > 0 ? s.durationMs : 1500;
            provider.addSfxBlock(SfxBlock(
              id: const Uuid().v4(),
              type: SfxType.pop, // placeholder; isCustom drives behaviour
              startTime: _position,
              duration: Duration(milliseconds: durMs),
              isCustom: true,
              customPath: path,
              customName: s.title,
            ));
            await previewPlayer.stop();
            if (ctx.mounted) Navigator.pop(ctx);
            if (mounted) {
              setState(() {});
              _toast(tr('ed.webSfxAdded'));
            }
          }

          String fmtDur(int ms) {
            final sec = (ms / 1000);
            return '${sec.toStringAsFixed(sec < 10 ? 1 : 0)}s';
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.library_music, color: Color(0xFF00BFA5)),
                    const SizedBox(width: 8),
                    Text(tr('ed.webSfx'),
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 4),
                  Text(tr('ed.webSfxHelp'),
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 11)),
                  const SizedBox(height: 10),
                  // Source toggle: Freesound (meme/UI) vs BBC (realistic).
                  Row(children: [
                    for (int sIdx = 0; sIdx < 2; sIdx++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(sIdx == 0 ? tr('ed.srcMeme2') : tr('ed.srcReal')),
                          selected: sfxSource == sIdx,
                          showCheckmark: false,
                          labelStyle: TextStyle(
                              color: sfxSource == sIdx ? Colors.white : AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          selectedColor: const Color(0xFF00BFA5),
                          backgroundColor: AppColors.surfaceLight,
                          onSelected: (_) => setSheet(() {
                            sfxSource = sIdx;
                            results = [];
                            needFreesoundKey = false;
                          }),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: queryCtrl,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 14),
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => runSearch(),
                        decoration: InputDecoration(
                          hintText: tr('ed.webSfxHint'),
                          hintStyle: const TextStyle(color: AppColors.textHint),
                          filled: true,
                          fillColor: AppColors.surfaceLight,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: loading ? null : runSearch,
                      icon: const Icon(Icons.search, color: Color(0xFF00BFA5)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: loading ? null : aiKeyword,
                      icon: const Icon(Icons.auto_awesome,
                          size: 16, color: Color(0xFFFFB703)),
                      label: Text(tr('ed.webImageAi'),
                          style: const TextStyle(
                              color: Color(0xFFFFB703), fontSize: 12)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 320,
                    child: loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF00BFA5)))
                        : needFreesoundKey
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(tr('ed.needFreesound'),
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                                color: AppColors.textHint)),
                                        const SizedBox(height: 10),
                                        ElevatedButton.icon(
                                          onPressed: () {
                                            Navigator.pop(ctx);
                                            Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                    builder: (_) =>
                                                        const SettingsScreen()));
                                          },
                                          icon: const Icon(Icons.settings, size: 16),
                                          label: Text(tr('ed.goToSettings')),
                                        ),
                                      ]),
                                ),
                              )
                            : results.isEmpty
                            ? Center(
                                child: Text(tr('ed.webSfxEmpty'),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: AppColors.textHint)))
                            : ListView.separated(
                                itemCount: results.length,
                                separatorBuilder: (_, __) => const Divider(
                                    height: 1, color: AppColors.border),
                                itemBuilder: (_, i) {
                                  final s = results[i];
                                  final isPlaying = playingId == s.id;
                                  return ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: 4),
                                    leading: IconButton(
                                      onPressed: () => preview(s),
                                      icon: Icon(
                                          isPlaying
                                              ? Icons.stop_circle
                                              : Icons.play_circle_fill,
                                          color: const Color(0xFF00BFA5),
                                          size: 30),
                                    ),
                                    title: Text(s.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontSize: 13)),
                                    subtitle: Text(fmtDur(s.durationMs),
                                        style: const TextStyle(
                                            color: AppColors.textHint,
                                            fontSize: 11)),
                                    trailing: inserting
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2))
                                        : TextButton.icon(
                                            onPressed: () => insert(s),
                                            icon: const Icon(Icons.add,
                                                size: 16,
                                                color: Color(0xFF00BFA5)),
                                            label: Text(tr('ed.webSfxInsert'),
                                                style: const TextStyle(
                                                    color: Color(0xFF00BFA5),
                                                    fontSize: 12)),
                                          ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    ).whenComplete(() => previewPlayer.dispose());
  }

  void _deleteImageOverlay(ProjectProvider provider, String id) {
    final project = provider.currentProject;
    final o = project?.imageOverlays.where((e) => e.id == id).firstOrNull;
    provider.removeImageOverlay(id);
    try { if (o != null) File(o.path).deleteSync(); } catch (_) {}
    setState(() => _selectedImageId = null);
    _toast(tr('ed.imageDeleted'));
  }

  void _rotateImageOverlay(ProjectProvider provider, String id) {
    final o = provider.currentProject?.imageOverlays
        .where((e) => e.id == id)
        .firstOrNull;
    if (o == null) return;
    provider.pushHistory();
    o.rotation = (o.rotation + 90) % 360;
    provider.commit();
    setState(() {});
  }

  void _flipImageOverlay(ProjectProvider provider, String id) {
    final o = provider.currentProject?.imageOverlays
        .where((e) => e.id == id)
        .firstOrNull;
    if (o == null) return;
    provider.pushHistory();
    o.flipH = !o.flipH;
    provider.commit();
    setState(() {});
  }

  /// Toggle an overlay between full-screen (cover) and normal (band) placement.
  void _toggleCover(ProjectProvider provider, String id) {
    final o = provider.currentProject?.imageOverlays
        .where((e) => e.id == id)
        .firstOrNull;
    if (o == null) return;
    provider.pushHistory();
    o.cover = !o.cover;
    provider.commit();
    setState(() {});
    _toast(tr(o.cover ? 'ed.coverOnDone' : 'ed.coverOffDone'));
  }

  void _showImageScaleSheet(ProjectProvider provider, String id) {
    final o = provider.currentProject?.imageOverlays
        .where((e) => e.id == id)
        .firstOrNull;
    if (o == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('ed.imageSize'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: o.scale.clamp(0.1, 3.0),
                        min: 0.1,
                        max: 3.0,
                        activeColor: AppColors.primary,
                        inactiveColor: AppColors.border,
                        onChanged: (v) {
                          setSheet(() => o.scale = v);
                          provider.liveUpdate();
                          setState(() {});
                        },
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('${(o.scale * 100).round()}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() => provider.commit());
  }

  Future<void> _pickCustomAudio(ProjectProvider provider) async {
    Navigator.pop(context); // Close sheet
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );
    if (result == null || result.files.single.path == null) return;
    final srcPath = result.files.single.path!;
    final name = result.files.single.name;

    // Show a quick progress toast while decoding (MP3/M4A → WAV).
    _toast(tr('ed.addingAudio'));
    try {
      // Decode ANY audio format (MP3/M4A/WAV) into a 44.1kHz mono WAV via the
      // native MediaCodec extractor, so both preview AND export can read it.
      final supportDir = await getApplicationSupportDirectory();
      final sfxDir = Directory(p.join(supportDir.path, 'custom_sfx'));
      if (!sfxDir.existsSync()) sfxDir.createSync(recursive: true);
      final wavPath = p.join(
          sfxDir.path, 'sfx_${DateTime.now().millisecondsSinceEpoch}.wav');

      const channel = MethodChannel('com.anniekaydee.subtitle_app/audio');
      await channel.invokeMethod('extractAudio', {
        'videoPath': srcPath,
        'outputPath': wavPath,
      });

      // Read the decoded WAV header to get the true duration.
      final f = File(wavPath);
      if (!f.existsSync() || f.lengthSync() <= 44) {
        _showErrorBanner(tr('ed.cantReadAudio'));
        return;
      }
      final raf = await f.open();
      final hdr = await raf.read(44);
      await raf.close();
      final wavLen = f.lengthSync();
      final bd = ByteData.sublistView(hdr);
      final chs = bd.getInt16(22, Endian.little);
      final sr = bd.getInt32(24, Endian.little);
      final bps = bd.getInt16(34, Endian.little) ~/ 8;
      final durMs = (sr * chs * bps) > 0
          ? ((wavLen - 44) / (sr * chs * bps) * 1000).round()
          : 1000;

      provider.addSfxBlock(SfxBlock(
        id: const Uuid().v4(),
        type: SfxType.pop, // placeholder; isCustom drives behaviour
        startTime: _position,
        duration: Duration(milliseconds: durMs),
        isCustom: true,
        customPath: wavPath,
        customName: name,
      ));
      _toast(tr('ed.audioAdded', {'name': name}));
    } catch (e) {
      _showErrorBanner(tr('ed.audioAddFail', {'e': e.toString()}));
    }
  }

  void _showAddSfxSheet(ProjectProvider provider) {
    _pauseForEdit();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return DefaultTabController(
          length: 4,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 20),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Add SFX',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TabBar(
                      isScrollable: true,
                      indicatorColor: AppColors.primary,
                      labelColor: AppColors.primary,
                      unselectedLabelColor: Colors.white54,
                      tabs: [
                        Tab(text: tr('ed.sfxTab.funny')),
                        Tab(text: tr('ed.sfxTab.motion')),
                        Tab(text: tr('ed.sfxTab.general')),
                        Tab(text: tr('ed.sfxTab.mine')),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Tab 1: ຕະຫຼົກ/ຕີ (Funny/Hits)
                          ListView(
                            children: [
                              _buildSfxTile(context, provider, SfxType.pop, '🔥', 'ສຽງ Pop', 'ຍອດນິຍົມ'),
                              _buildSfxTile(context, provider, SfxType.pop2, '🔥', 'ສຽງ Pop 2', 'ຍອດນິຍົມ 2'),
                              _buildSfxTile(context, provider, SfxType.punch, '👊', 'ສຽງ Punch', 'ສຽງຕີ/ຊົກ'),
                              _buildSfxTile(context, provider, SfxType.punch2, '👊', 'ສຽງ Punch 2', 'ສຽງຕີ/ຊົກ 2'),
                              _buildSfxTile(context, provider, SfxType.slap, '🖐️', 'ສຽງ Slap', 'ສຽງຕົບໜ້າ'),
                              _buildSfxTile(context, provider, SfxType.wow, '😲', 'ສຽງ Wow', 'ສຽງວ້າວ'),
                              _buildSfxTile(context, provider, SfxType.cricket, '🦗', 'ສຽງ Cricket', 'ສຽງຈີ່ຫຼໍ່ (ງຽບ/ຈືດ)'),
                              _buildSfxTile(context, provider, SfxType.vineBoom, '💥', 'ສຽງ Vine Boom', 'ສຽງຕຸ້ມແບບມີມດັງໆ'),
                              _buildSfxTile(context, provider, SfxType.laugh, '😂', 'ສຽງ Laugh', 'ສຽງຫົວເລາະ'),
                              _buildSfxTile(context, provider, SfxType.boing, '🪀', 'ສຽງ Boing', 'ສຽງເດັ້ງດຶ໋ງ'),
                              _buildSfxTile(context, provider, SfxType.thud, '📦', 'ສຽງ Thud', 'ສຽງຂອງຕົກໜັກໆ'),
                              _buildSfxTile(context, provider, SfxType.squeak, '🐭', 'ສຽງ Squeak', 'ສຽງບີບໜູ'),
                              _buildSfxTile(context, provider, SfxType.quack, '🦆', 'ສຽງ Quack', 'ສຽງເປັດ'),
                              _buildSfxTile(context, provider, SfxType.pop3, '🔥', 'ສຽງ Pop 3', 'ຍອດນິຍົມ 3'),
                              _buildSfxTile(context, provider, SfxType.pop4, '🔥', 'ສຽງ Pop 4', 'ຍອດນິຍົມ 4'),
                              _buildSfxTile(context, provider, SfxType.pop5, '🔥', 'ສຽງ Pop 5', 'ຍອດນິຍົມ 5'),
                              _buildSfxTile(context, provider, SfxType.punch3, '👊', 'ສຽງ Punch 3', 'ສຽງຕີ/ຊົກ 3'),
                              _buildSfxTile(context, provider, SfxType.punch4, '👊', 'ສຽງ Punch 4', 'ສຽງຕີ/ຊົກ 4'),
                              _buildSfxTile(context, provider, SfxType.punch5, '👊', 'ສຽງ Punch 5', 'ສຽງຕີ/ຊົກ 5'),
                              _buildSfxTile(context, provider, SfxType.slap2, '🖐️', 'ສຽງ Slap 2', 'ສຽງຕົບໜ້າ 2'),
                              _buildSfxTile(context, provider, SfxType.wow2, '😲', 'ສຽງ Wow 2', 'ສຽງວ້າວ 2'),
                              _buildSfxTile(context, provider, SfxType.squeak2, '🐭', 'ສຽງ Squeak 2', 'ສຽງບີບໜູ 2'),
                              _buildSfxTile(context, provider, SfxType.squeak3, '🐭', 'ສຽງ Squeak 3', 'ສຽງບີບໜູ 3'),
                              _buildSfxTile(context, provider, SfxType.squeak4, '🐭', 'ສຽງ Squeak 4', 'ສຽງບີບໜູ 4'),
                              _buildSfxTile(context, provider, SfxType.squeek, '🐭', 'ສຽງ Squeek', 'ສຽງບີບໜູ (ອື່ນ)'),
                            ],
                          ),
                          // Tab 2: ການເຄື່ອນໄຫວ (Movement)
                          ListView(
                            children: [
                              _buildSfxTile(context, provider, SfxType.swoosh, '💨', 'ສຽງ Swoosh', 'ສຽງປາດ'),
                              _buildSfxTile(context, provider, SfxType.swoosh2, '💨', 'ສຽງ Swoosh 2', 'ສຽງປາດ 2'),
                              _buildSfxTile(context, provider, SfxType.whoosh, '🌬️', 'ສຽງ Whoosh', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່'),
                              _buildSfxTile(context, provider, SfxType.whoosh2, '🌬️', 'ສຽງ Whoosh 2', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 2'),
                              _buildSfxTile(context, provider, SfxType.whoosh3, '🌬️', 'ສຽງ Whoosh 3', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 3'),
                              _buildSfxTile(context, provider, SfxType.whoosh4, '🌬️', 'ສຽງ Whoosh 4', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 4'),
                              _buildSfxTile(context, provider, SfxType.whoosh5, '🌬️', 'ສຽງ Whoosh 5', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 5'),
                              _buildSfxTile(context, provider, SfxType.whoosh6, '🌬️', 'ສຽງ Whoosh 6', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 6'),
                              _buildSfxTile(context, provider, SfxType.whoosh7, '🌬️', 'ສຽງ Whoosh 7', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 7'),
                              _buildSfxTile(context, provider, SfxType.whoosh8, '🌬️', 'ສຽງ Whoosh 8', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 8'),
                              _buildSfxTile(context, provider, SfxType.whoosh9, '🌬️', 'ສຽງ Whoosh 9', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 9'),
                              _buildSfxTile(context, provider, SfxType.whoosh10, '🌬️', 'ສຽງ Whoosh 10', 'ສຽງລົມ/ສຽງເຄື່ອນທີ່ 10'),
                            ],
                          ),
                          // Tab 3: ທົ່ວໄປ (Misc)
                          ListView(
                            children: [
                              _buildSfxTile(context, provider, SfxType.ding, '🔔', 'ສຽງ Ding', 'ສຽງກະດິ່ງ/ແຈ້ງເຕືອນ'),
                              _buildSfxTile(context, provider, SfxType.ding2, '🔔', 'ສຽງ Ding 2', 'ສຽງກະດິ່ງ/ແຈ້ງເຕືອນ 2'),
                              _buildSfxTile(context, provider, SfxType.applause, '👏', 'ສຽງ Applause', 'ສຽງຕົບມື'),
                              _buildSfxTile(context, provider, SfxType.cameraShutter, '📸', 'ສຽງ Camera Shutter', 'ສຽງກົດຊັດເຕີກ້ອງ'),
                              _buildSfxTile(context, provider, SfxType.cashRegister, '💰', 'ສຽງ Cash Register', 'ສຽງເຄື່ອງຄິດເງິນ'),
                              _buildSfxTile(context, provider, SfxType.recordScratch, '💿', 'ສຽງ Record Scratch', 'ສຽງແຜ່ນສຽງສະດຸດ'),
                              _buildSfxTile(context, provider, SfxType.badumtss, '🥁', 'ສຽງ Ba Dum Tss', 'ສຽງກອງຮັບມຸກຕະລົກ'),
                              _buildSfxTile(context, provider, SfxType.beep, '🤖', 'ສຽງ Beep', 'ສຽງບີບ'),
                              _buildSfxTile(context, provider, SfxType.correct, '✅', 'ສຽງ Correct', 'ສຽງຖືກຕ້ອງ'),
                              _buildSfxTile(context, provider, SfxType.buzzer, '❌', 'ສຽງ Buzzer', 'ສຽງຜິດພາດ/ໝົດເວລາ'),
                              _buildSfxTile(context, provider, SfxType.magic, '🪄', 'ສຽງ Magic', 'ສຽງເວດມົນ'),
                              _buildSfxTile(context, provider, SfxType.typing, '⌨️', 'ສຽງ Typing', 'ສຽງພິມຄີບອດ'),
                              _buildSfxTile(context, provider, SfxType.glitch, '📺', 'ສຽງ Glitch', 'ສຽງໂທລະທັດຊ໋ອດ'),
                              _buildSfxTile(context, provider, SfxType.airhorn, '📯', 'ສຽງ Airhorn', 'ສຽງແກລົມ'),
                              _buildSfxTile(context, provider, SfxType.cameraShutter2, '📸', 'ສຽງ Camera Shutter 2', 'ສຽງກົດຊັດເຕີກ້ອງ 2'),
                              _buildSfxTile(context, provider, SfxType.cameraShutter3, '📸', 'ສຽງ Camera Shutter 3', 'ສຽງກົດຊັດເຕີກ້ອງ 3'),
                              _buildSfxTile(context, provider, SfxType.cashRegister2, '💰', 'ສຽງ Cash Register 2', 'ສຽງເຄື່ອງຄິດເງິນ 2'),
                              _buildSfxTile(context, provider, SfxType.recordScratch2, '💿', 'ສຽງ Record Scratch 2', 'ສຽງແຜ່ນສຽງສະດຸດ 2'),
                              _buildSfxTile(context, provider, SfxType.badumtss2, '🥁', 'ສຽງ Ba Dum Tss 2', 'ສຽງກອງຮັບມຸກຕະລົກ 2'),
                            ],
                          ),
                          // Tab 4: ສຽງຂອງຂ້ອຍ (My Audio)
                          ListView(
                            children: [
                              ListTile(
                                leading: const Icon(Icons.audio_file, color: AppColors.primary, size: 32),
                                title: Text(tr('ed.pickFromDevice'), style: const TextStyle(color: Colors.white)),
                                subtitle: Text(tr('ed.supportFormats'), style: const TextStyle(color: Colors.white54)),
                                trailing: const Icon(Icons.add_circle, color: AppColors.primary),
                                onTap: () => _pickCustomAudio(provider),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
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
      // 1) Match the Auto-✨ emoji first (most reliable). One SFX per segment.
      final emoji = seg.emoji;
      if (emoji != null && emoji.isNotEmpty) {
        final esfx = SfxMapper.getSfxForEmoji(emoji);
        if (esfx != null) {
          newBlocks.add(SfxBlock(
            id: const Uuid().v4(),
            type: esfx,
            startTime: seg.startTime,
          ));
          continue; // already added one for this segment
        }
      }
      // 2) Otherwise match by spoken words.
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
      _toast(tr('ed.noAutoSfx'));
      return;
    }

    // Confirm dialog
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(tr('ed.autoSfxTitle'), style: const TextStyle(color: Colors.white)),
        content: Text(tr('ed.autoSfxBody', {'n': newBlocks.length}), style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.pushHistory();
              // Keep old blocks, add new
              for (final b in newBlocks) {
                provider.addSfxBlock(b);
              }
              _toast(tr('ed.sfxAddedN', {'n': newBlocks.length}));
            },
            child: Text(tr('ed.mergeWithOld'), style: const TextStyle(color: Colors.white54)),
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
              _toast(tr('ed.autoSfxPlaced', {'n': newBlocks.length}));
            },
            child: Text(tr('ed.replaceAll'), style: const TextStyle(color: Colors.white)),
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
      _showProFeatureDialog(tr('ed.templateProDialog', {'name': t.name}));
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
    _toast(tr('ed.templateApplied', {'name': t.name}));
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
                  Text(
                    tr('ed.templates'),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildTemplatesRow(project, provider),
              const SizedBox(height: 22),
              Text(
                tr('ed.tab.style'),
                style: const TextStyle(
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
                        _showProFeatureDialog(tr('ed.styleProDialog', {'name': preset.name}));
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
                  Text(
                    tr('ed.fontSizeLabel'),
                    style: const TextStyle(
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
              Text(
                tr('ed.fontShort'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...(_fontOptionsFor(project).map(
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
              Text(
                tr('ed.weightFull'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _buildWeightChip(tr('ed.thin'), 300, project, provider),
                  const SizedBox(width: 8),
                  _buildWeightChip(tr('ed.regular'), 400, project, provider),
                  const SizedBox(width: 8),
                  _buildWeightChip(tr('ed.bold'), 700, project, provider),
                  const SizedBox(width: 8),
                  _buildWeightChip(tr('ed.boldest'), 900, project, provider),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static List<(SubtitleAnimation, IconData, String)> get _animOptions => [
    (SubtitleAnimation.none, Icons.block, tr('ed.none')),
    (SubtitleAnimation.fadeIn, Icons.opacity, 'Fade'),
    (SubtitleAnimation.slideUp, Icons.arrow_upward, 'Slide ↑'),
    (SubtitleAnimation.slideDown, Icons.arrow_downward, 'Slide ↓'),
    (SubtitleAnimation.slideLeft, Icons.arrow_back, 'Slide ←'),
    (SubtitleAnimation.bounceIn, Icons.open_with, 'Bounce'),
    (SubtitleAnimation.typewriter, Icons.keyboard_outlined, tr('ed.typewriter')),
  ];

  // Exit animations: typewriter doesn't apply as an exit effect.
  static List<(SubtitleAnimation, IconData, String)> get _exitAnimOptions => [
    (SubtitleAnimation.none, Icons.block, tr('ed.none')),
    (SubtitleAnimation.fadeIn, Icons.opacity, 'Fade'),
    (SubtitleAnimation.slideUp, Icons.arrow_upward, 'Slide ↑'),
    (SubtitleAnimation.slideDown, Icons.arrow_downward, 'Slide ↓'),
    (SubtitleAnimation.slideLeft, Icons.arrow_back, 'Slide ←'),
    (SubtitleAnimation.bounceIn, Icons.open_with, 'Bounce'),
  ];

  static List<(AnimationSpeed, String)> get _speedOptions => [
    (AnimationSpeed.slow, tr('ed.slow')),
    (AnimationSpeed.normal, tr('ed.normal')),
    (AnimationSpeed.fast, tr('ed.fast')),
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
        Text(
          tr('ed.animIn'),
          style: const TextStyle(
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
        Text(
          tr('ed.animOut'),
          style: const TextStyle(
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
        Text(
          tr('ed.animSpeed'),
          style: const TextStyle(
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('ed.bilingualSub'),
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      tr('ed.bilingualDesc'),
                      style: const TextStyle(color: AppColors.textHint, fontSize: 11),
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
                        _showProFeatureDialog(tr('ed.bilingualProDialog'));
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
                Text(
                  tr('ed.row2Size'),
                  style: const TextStyle(
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
                Text(
                  tr('ed.rowGap'),
                  style: const TextStyle(
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
            Text(
              tr('ed.row2Style'),
              style: const TextStyle(
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
                  tr('ed.preview'),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Karaoke Highlight',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      tr('ed.karaokeDesc'),
                      style: const TextStyle(color: AppColors.textHint, fontSize: 11),
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
            Text(
              tr('ed.highlightColor'),
              style: const TextStyle(
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
                      Text(
                        tr('ed.wordPop'),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        tr('ed.wordPopDesc'),
                        style: const TextStyle(
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
              Text(
                tr('ed.subPosition'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              // Quick presets
              Row(
                children: [
                  _buildPositionOption(
                    tr('ed.top'),
                    Icons.vertical_align_top,
                    pos < 0.2,
                    () {
                      project.subtitlePositionY = 0.1;
                      provider.updateProject(project);
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildPositionOption(
                    tr('ed.middle'),
                    Icons.vertical_align_center,
                    pos >= 0.2 && pos <= 0.7,
                    () {
                      project.subtitlePositionY = 0.5;
                      provider.updateProject(project);
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildPositionOption(
                    tr('ed.bottom'),
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
              Text(
                tr('ed.fineTune'),
                style: const TextStyle(
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
                          child: Text(
                            tr('ed.subHere'),
                            style: const TextStyle(
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
                  children: [
                    Text(
                      tr('ed.top'),
                      style: const TextStyle(color: AppColors.textHint, fontSize: 11),
                    ),
                    Text(
                      tr('ed.bottom'),
                      style: const TextStyle(color: AppColors.textHint, fontSize: 11),
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

  void _showExportOptions() {
    Widget tile(IconData icon, Color color, String title, String sub, VoidCallback onTap) {
      return ListTile(
        onTap: onTap,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(title,
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
        subtitle: Text(sub,
            style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textHint),
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text(tr('ed.exportTitle'),
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
            tile(Icons.movie_creation_outlined, AppColors.primary,
                tr('ed.exportVideo'), tr('ed.exportVideoSub'), () {
              Navigator.pop(ctx);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ExportScreen()));
            }),
            tile(Icons.subtitles_outlined, const Color(0xFF00BFA5),
                tr('ed.exportSrt'), tr('ed.exportSrtSub'), () {
              Navigator.pop(ctx);
              _exportSubtitleFile(vtt: false);
            }),
            tile(Icons.closed_caption_outlined, const Color(0xFF7C5CFF),
                tr('ed.exportVtt'), tr('ed.exportVttSub'), () {
              Navigator.pop(ctx);
              _exportSubtitleFile(vtt: true);
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _exportSubtitleFile({required bool vtt}) async {
    final project = context.read<ProjectProvider>().currentProject;
    if (project == null || project.segments.isEmpty) {
      _toast(tr('ed.noSubtitle'));
      return;
    }
    // Free users: 2 subtitle-file exports per day. PRO is unlimited.
    final remaining = await FreeQuotaService.remainingSrtExports();
    if (remaining <= 0) {
      _showProFeatureDialog(tr('ed.srtQuotaReached'));
      return;
    }
    final isPro = await FreeQuotaService.isPro();
    try {
      final path = await SubtitleExportService.export(
        segments: project.segments,
        baseName: project.name.trim().isEmpty ? 'subtitle' : project.name.trim(),
        vtt: vtt,
        bilingual: project.showBilingual,
      );
      if (!isPro) await FreeQuotaService.useSrtExport();
      if (mounted) {
        final left = isPro ? '' : tr('ed.srtQuota', {'n': remaining - 1});
        _toast('${tr('ed.subFileSaved', {'path': path})}$left');
      }
    } catch (e) {
      if (mounted) _toast(tr('ed.subFileFail', {'e': '$e'}));
    }
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
            Text(
              tr('ed.translateSub'),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('ed.pickTransLang'),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            _buildLangOption('🇬🇧 English', 'en', provider),
            const SizedBox(height: 10),
            _buildLangOption(tr('lang.opt.th'), 'th', provider),
            const SizedBox(height: 10),
            _buildLangOption(tr('lang.opt.lo'), 'lo', provider),
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
          SnackBar(
            content: Text(tr('ed.needGeminiTranslate')),
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
          SnackBar(
            content: Text(tr('ed.translateDone')),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('ed.translateFail', {'e': '$e'})),
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
              Text(
                tr('ed.addSubtitle'),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              // Line 1 — main text
              _buildTextField(
                controller: textCtrl,
                label: tr('ed.row1'),
                hint: tr('ed.egHello'),
                autofocus: true,
                accentColor: AppColors.primary,
              ),
              const SizedBox(height: 10),
              // Line 2 — translated text
              _buildTextField(
                controller: transCtrl,
                label: tr('ed.row2'),
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
                            label: tr('ed.start'),
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
                            label: tr('ed.end'),
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
                child: Text(tr('ed.add')),
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
            child: Text(tr('common.close')),
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

    final hasApiKey = true;

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
              title: Row(
                children: [
                  const Icon(Icons.record_voice_over, color: AppColors.primary, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    tr('ed.aiDubbing'),
                    style: const TextStyle(
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: AppColors.accent, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    tr('ed.noGeminiSet'),
                                    style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tr('ed.geminiTtsHint2'),
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      Text(
                        tr('ed.pickVoiceTone'),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Language selection
                    Text(tr('ed.voiceLang'), style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                    DropdownButton<String>(
                      value: ttsLang,
                      isExpanded: true,
                      dropdownColor: AppColors.surface,
                      style: const TextStyle(color: AppColors.textPrimary),
                      items: [
                        DropdownMenuItem(value: 'lo', child: Text(tr('ed.langLaoOpt'))),
                        DropdownMenuItem(value: 'th', child: Text(tr('ed.langThaiOpt'))),
                        DropdownMenuItem(value: 'en', child: Text(tr('ed.langEnOpt'))),
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
                      Text(tr('ed.voiceTones'), style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                      if (availableVoices.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text(
                            tr('ed.loadingVoices'),
                            style: const TextStyle(color: AppColors.textHint, fontSize: 12, fontStyle: FontStyle.italic),
                          ),
                        )
                      else
                        DropdownButton<String>(
                          value: selectedVoice.isEmpty ? null : selectedVoice,
                          isExpanded: true,
                          dropdownColor: AppColors.surface,
                          style: const TextStyle(color: AppColors.textPrimary),
                          items: availableVoices.map((v) {
                            final gender = v['gender'] == 'male' ? tr('ed.male') : (v['gender'] == 'female' ? tr('ed.female') : '');
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
                          Text(tr('ed.voiceSpeed'), style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
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
                          title: Text(
                            tr('ed.dubFromTranslation'),
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
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
                        title: Text(
                          tr('ed.sfxAutoSyncTitle'),
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          tr('ed.autoSfxDesc'),
                          style: const TextStyle(color: AppColors.textHint, fontSize: 10),
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
                      Text(tr('ed.exportFormat'), style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
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
                              title: Text(tr('ed.muxVideo'), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold)),
                              subtitle: Text(tr('ed.muxVideoSub'), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
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
                              title: Text(tr('ed.audioOnly'), style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold)),
                              subtitle: Text(tr('ed.audioOnlySub'), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
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
                  child: Text(tr('common.close'), style: const TextStyle(color: AppColors.textSecondary)),
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
                    label: Text(tr('ed.goToSettings'), style: const TextStyle(fontWeight: FontWeight.bold)),
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
                    label: Text(tr('ed.startDubbing'), style: const TextStyle(fontWeight: FontWeight.bold)),
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
    String progressText = tr('ed.preparingSystem');
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

              _ttsService.synthesizeAndStitch(
                segments: project.segments,
                languageCode: language,
                voiceName: voiceName,
                speechRate: speechRate,
                useTranslation: useTranslation,
                outputWavPath: outputWav,
                
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
                      progressText = tr('ed.savingAudio');
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
                    _showErrorBanner(tr('ed.audioSaveFail', {'e': e.toString()}));
                  }
                  return;
                }

                if (ctx.mounted) {
                  setProgState(() {
                    progressText = tr('ed.addingAiTrack');
                    progressPct = 0.95;
                  });
                }

                try {
                  // Non-destructive: save the stitched AI voice as a SEPARATE
                  // timeline track. The original video audio is left untouched;
                  // the tracks are only combined (at chosen volumes) on export.
                  final supportDir = await getApplicationSupportDirectory();
                  final aiDir = Directory(p.join(supportDir.path, 'ai_voice'));
                  if (!aiDir.existsSync()) aiDir.createSync(recursive: true);
                  final destPath = p.join(aiDir.path,
                      'ai_voice_${DateTime.now().millisecondsSinceEpoch}.wav');
                  await File(outputWav).copy(destPath);

                  // Read the WAV header to compute the track duration.
                  final raf = await File(destPath).open();
                  final hdr = await raf.read(44);
                  await raf.close();
                  final wavLen = await File(destPath).length();
                  final bd = ByteData.sublistView(hdr);
                  final chs = bd.getInt16(22, Endian.little);
                  final sr = bd.getInt32(24, Endian.little);
                  final bps = bd.getInt16(34, Endian.little) ~/ 8;
                  final durMs = (sr * chs * bps) > 0
                      ? ((wavLen - 44) / (sr * chs * bps) * 1000).round()
                      : 0;

                  provider.pushHistory();
                  // Replace any previous AI track file.
                  final oldPath = project.aiVoicePath;
                  if (oldPath != null && oldPath != destPath) {
                    try { File(oldPath).deleteSync(); } catch (_) {}
                  }
                  project.aiVoicePath = destPath;
                  project.aiVoiceDurationMs = durMs;
                  project.aiVoiceOffsetMs = 0;
                  project.aiVoiceTrimStartMs = 0;
                  project.aiVoiceTrimEndMs = null;
                  project.aiVoiceMuted = false;
                  provider.commit();
                  _aiVoiceLoadedPath = null;
                  await _ensureAiVoicePlayer();

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) setState(() {});
                  _showAiTrackAddedDialog();
                } catch (e) {
                  if (ctx.mounted) Navigator.pop(ctx);
                  _showErrorBanner(tr('ed.aiTrackFail', {'e': e.toString()}));
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
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 24),
            const SizedBox(width: 10),
            Text(
              tr('ed.dubDone'),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          tr('ed.dubMuxedBody', {'file': fileName}),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: Text(tr('ed.ok'), style: const TextStyle(fontWeight: FontWeight.bold)),
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
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 24),
            const SizedBox(width: 10),
            Text(
              tr('ed.dubSavedTitle'),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: Text(
          tr('ed.dubSavedBody', {'file': savedPath.split('/').last}),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            child: Text(tr('ed.ok'), style: const TextStyle(fontWeight: FontWeight.bold)),
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
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.amber, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tr('ed.saveAsAudioLayer'),
                style: const TextStyle(
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
            Text(
              tr('ed.muxFailBody'),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
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
            Text(
              tr('ed.audioLayerHint'),
              style: const TextStyle(color: AppColors.textHint, fontSize: 11.5, height: 1.4),
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
            child: Text(tr('ed.understood'), style: const TextStyle(fontWeight: FontWeight.bold)),
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
