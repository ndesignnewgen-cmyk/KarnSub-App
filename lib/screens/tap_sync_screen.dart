import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../i18n/i18n.dart';
import '../models/subtitle_style_model.dart';
import '../providers/project_provider.dart';
import '../services/clip_player_controller.dart';
import '../services/free_quota_service.dart';
import '../services/lao_word_service.dart';
import '../services/script_splitter.dart';
import '../services/tap_sync_calibration.dart';
import '../services/tap_sync_media.dart';
import '../services/tap_sync_session.dart';
import '../theme/app_theme.dart';
import '../widgets/tap_sync_widgets.dart';

/// "ແຕະໃຫ້ຕົງ" (Tap Sync): listen, then press along with each sentence (or
/// each word, karaoke) to set subtitle timing. See docs/TAP_SYNC_PLAN.md.
///
/// Pops `true` when segments were saved (one undo step in the editor).
class TapSyncScreen extends StatefulWidget {
  /// Open directly in word-by-word (karaoke) mode.
  final bool karaoke;

  /// The editor's native multi-clip player (shared — see TapSyncMedia).
  final ClipPlayerController? clipPlayer;

  /// Tests inject a fake player here.
  @visibleForTesting
  final TapSyncMedia Function(SubtitleProject project)? mediaFactory;

  const TapSyncScreen({
    super.key,
    this.karaoke = false,
    this.clipPlayer,
    this.mediaFactory,
  });

  @override
  State<TapSyncScreen> createState() => _TapSyncScreenState();
}

enum _Stage { setup, script, record, review }

enum _Source { ai, script }

class _Prefs {
  static const mode = 'tapsync.mode';
  static const karaokeMode = 'tapsync.karaokeMode';
  static const speed = 'tapsync.speed';
  static const snap = 'tapsync.snap';
  static const volKeys = 'tapsync.volKeys';
  static const offset = 'tapsync.offset';
  static const offsetBt = 'tapsync.offsetBt';
}

class _TapSyncScreenState extends State<TapSyncScreen>
    with SingleTickerProviderStateMixin {
  static const _btExtraMs = -150; // default extra for Bluetooth headphones

  _Stage _stage = _Stage.setup;
  _Source _source = _Source.ai;
  late bool _karaoke = widget.karaoke;

  // Settings (remembered).
  TapMode _sentenceMode = TapMode.hold;
  TapMode _karaokeMode = TapMode.tap;
  double _speed = 0.75;
  bool _snap = true;
  bool _volKeys = true;
  int _offset = TapSyncCalibration.defaultOffsetMs;
  int? _offsetBt;
  bool _bt = false;
  bool _isPro = false;
  int _startLine = 0;

  // Script mode.
  final _scriptCtl = TextEditingController();
  List<String> _scriptLines = [];
  int _maxChars = 28;
  bool _splitting = false;

  // Media.
  late final SubtitleProject _project;
  TapSyncMedia? _media;
  bool _mediaReady = false;
  String? _mediaError;
  TapSyncAnalysis _analysis = TapSyncAnalysis.empty;
  bool _analysisReady = false;

  // Clock: last player position + when it was read (for extrapolation).
  final _sw = Stopwatch()..start();
  int _anchorPos = 0;
  int _anchorSw = 0;
  bool _playing = false;
  Timer? _poll;
  late final Ticker _ticker;
  final _now = ValueNotifier<int>(0);
  int? _autoPauseAt; // review: stop at the end of the played line

  // Session.
  TapSyncSession? _session;
  List<TapLine> _lines = [];

  /// Karaoke: which segment each word unit belongs to.
  List<int> _unitSeg = [];
  bool _countdown = false;
  int _countdownN = 0;
  bool _pressed = false;
  bool _dirty = false;

  // Re-tap of a single line from the review screen.
  int? _retapIndex;
  TapSyncSession? _mainSession;

  // Review.
  int _sel = 0;

  TapMode get _mode => _karaoke ? _karaokeMode : _sentenceMode;
  int get _effOffset => _bt ? (_offsetBt ?? _offset + _btExtraMs) : _offset;
  bool get _snapOn => _snap && _isPro && _analysis.onsets.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _project = context.read<ProjectProvider>().currentProject!;
    if (_project.segments.where((s) => s.text.trim().isNotEmpty).isEmpty) {
      _source = _Source.script;
    }
    _ticker = createTicker((_) => _now.value = _mediaNow());
    _loadPrefs();
    _initMedia();
    TapSyncNative.onVolumeKey = _onVolumeKey;
  }

  @override
  void dispose() {
    TapSyncNative.onVolumeKey = null;
    TapSyncNative.setVolumeKeyCapture(false);
    _poll?.cancel();
    _ticker.dispose();
    _media?.dispose();
    _scriptCtl.dispose();
    _now.dispose();
    super.dispose();
  }

  // ── Setup ────────────────────────────────────────────────────────────────

  Future<void> _loadPrefs() async {
    final results = await Future.wait([
      SharedPreferences.getInstance(),
      FreeQuotaService.isPro(),
      TapSyncNative.isBluetoothOutput(),
    ]);
    final p = results[0] as SharedPreferences;
    if (!mounted) return;
    setState(() {
      _isPro = results[1] as bool;
      _bt = results[2] as bool;
      _sentenceMode = p.getString(_Prefs.mode) == 'tap' ? TapMode.tap : TapMode.hold;
      _karaokeMode =
          p.getString(_Prefs.karaokeMode) == 'hold' ? TapMode.hold : TapMode.tap;
      _speed = p.getDouble(_Prefs.speed) ?? 0.75;
      _snap = p.getBool(_Prefs.snap) ?? true;
      _volKeys = p.getBool(_Prefs.volKeys) ?? true;
      _offset = p.getInt(_Prefs.offset) ?? TapSyncCalibration.defaultOffsetMs;
      _offsetBt = p.getInt(_Prefs.offsetBt);
      if (_karaoke && !_isPro) _karaoke = false;
    });
  }

  Future<void> _savePrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_Prefs.mode, _sentenceMode == TapMode.tap ? 'tap' : 'hold');
      await p.setString(
          _Prefs.karaokeMode, _karaokeMode == TapMode.tap ? 'tap' : 'hold');
      await p.setDouble(_Prefs.speed, _speed);
      await p.setBool(_Prefs.snap, _snap);
      await p.setBool(_Prefs.volKeys, _volKeys);
      await p.setInt(_Prefs.offset, _offset);
      if (_offsetBt != null) await p.setInt(_Prefs.offsetBt, _offsetBt!);
    } catch (_) {}
  }

  Future<void> _initMedia() async {
    final hasMedia = _project.clips.length >= 2 || _project.videoPath != null;
    if (!hasMedia && widget.mediaFactory == null) {
      setState(() => _mediaError = tr('tap.noVideo'));
      return;
    }
    final m = widget.mediaFactory?.call(_project) ??
        TapSyncMedia.forProject(_project, sharedClipPlayer: widget.clipPlayer);
    try {
      await m.init();
      await m.setVolume(1.0);
    } catch (e) {
      if (mounted) setState(() => _mediaError = tr('tap.noVideo'));
      return;
    }
    if (!mounted) {
      m.dispose();
      return;
    }
    _media = m;
    setState(() => _mediaReady = true);
    _startPoll();
    // Speech analysis (for snap + waveform) runs in the background.
    final a = await m.analyze();
    if (mounted) {
      setState(() {
        _analysis = a;
        _analysisReady = true;
      });
    }
  }

  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 100), (_) => _sync());
  }

  /// Refresh the clock anchor from the player.
  Future<void> _sync() async {
    final m = _media;
    if (m == null) return;
    final t0 = _sw.elapsedMicroseconds;
    final pos = await m.positionMs();
    final t1 = _sw.elapsedMicroseconds;
    if (!mounted) return;
    _anchorPos = pos;
    _anchorSw = (t0 + t1) ~/ 2000; // ms, midpoint of the query
    final wasPlaying = _playing;
    _playing = m.isPlaying;
    if (_playing) {
      // Removed ranges are cut from the final video — skip them here too.
      if (_project.clips.length < 2) {
        for (final r in _project.removedRanges) {
          if (r.length == 2 && pos >= r[0] && pos < r[1] - 50) {
            await m.seek(r[1]);
            return;
          }
        }
      }
      if (_autoPauseAt != null && pos >= _autoPauseAt!) {
        _autoPauseAt = null;
        await _pause();
        return;
      }
    }
    if (_stage == _Stage.record && _playing == false && wasPlaying) {
      // Reached the end of the media while recording.
      if (pos >= m.durationMs - 300) _onMediaEnded();
    }
    if (wasPlaying != _playing && mounted) setState(() {});
  }

  /// Media time right now, extrapolated from the last anchor.
  int _mediaNow() {
    if (!_playing) return _anchorPos;
    final dt = _sw.elapsedMilliseconds - _anchorSw;
    final speed = _stage == _Stage.record ? _speed : 1.0;
    return _anchorPos + (dt * speed).round();
  }

  Future<void> _seek(int ms) async {
    await _media?.seek(ms);
    _anchorPos = ms;
    _anchorSw = _sw.elapsedMilliseconds;
    _now.value = ms;
  }

  Future<void> _play() async {
    await _media?.play();
    _playing = true;
    _anchorSw = _sw.elapsedMilliseconds;
    if (!_ticker.isActive) _ticker.start();
    if (mounted) setState(() {});
  }

  Future<void> _pause() async {
    final pos = _mediaNow();
    await _media?.pause();
    _playing = false;
    _anchorPos = pos;
    _ticker.stop();
    _now.value = pos;
    if (mounted) setState(() {});
  }

  // ── Building the lines ───────────────────────────────────────────────────

  List<SubtitleSegment> get _segs => _project.segments;

  Future<void> _start() async {
    _savePrefs();
    if (_source == _Source.script && _scriptLines.isEmpty) {
      setState(() => _stage = _Stage.script);
      return;
    }
    await _buildLines();
    if (_lines.isEmpty) return;
    // Snap needs the speech analysis — give it a moment if it's still running.
    if (_snap && _isPro && !_analysisReady) {
      _toast(tr('tap.analyzing'));
      for (int i = 0; i < 60 && !_analysisReady && mounted; i++) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }
    var start = 0;
    if (_karaoke) {
      final k = _unitSeg.indexOf(_startLine);
      start = k < 0 ? 0 : k;
    } else if (_source == _Source.ai) {
      start = _startLine.clamp(0, _lines.length - 1);
    }
    _newSession(startIndex: start);
    await _enterRecord();
  }

  Future<void> _buildLines() async {
    if (_karaoke) {
      // Word units of every segment from the chosen sentence on.
      final idx = <int>[];
      final texts = <String>[];
      final words = <int, List<String>>{};
      for (int i = 0; i < _segs.length; i++) {
        final w = _segs[i].words?.where((x) => x.trim().isNotEmpty).toList();
        if (w != null && w.length >= 2) {
          words[i] = w;
        } else {
          idx.add(i);
          texts.add(_segs[i].text);
        }
      }
      if (texts.isNotEmpty) {
        final r = await LaoWordService.segment(texts, _project.language);
        for (int k = 0; k < idx.length; k++) {
          words[idx[k]] = k < r.length && r[k].isNotEmpty ? r[k] : [texts[k]];
        }
      }
      _lines = [];
      _unitSeg = [];
      for (int i = 0; i < _segs.length; i++) {
        final s = _segs[i];
        final w = words[i]!;
        final wt = s.wordTimings;
        for (int j = 0; j < w.length; j++) {
          final st = wt != null && wt.length == w.length
              ? wt[j].inMilliseconds
              : s.startTime.inMilliseconds;
          final en = wt != null && wt.length == w.length && j + 1 < w.length
              ? wt[j + 1].inMilliseconds
              : s.endTime.inMilliseconds;
          _lines.add(TapLine(w[j], origStartMs: st, origEndMs: en));
          _unitSeg.add(i);
        }
      }
      return;
    }
    if (_source == _Source.ai) {
      _lines = _segs
          .map((s) => TapLine(s.text,
              origStartMs: s.startTime.inMilliseconds,
              origEndMs: s.endTime.inMilliseconds))
          .toList();
    } else {
      _lines = _scriptLines.map((t) => TapLine(t)).toList();
    }
  }

  void _newSession({int startIndex = 0, List<TapLine>? lines}) {
    _session = TapSyncSession(
      lines: lines ?? _lines,
      mode: _mode,
      offsetMs: _effOffset,
      speed: _speed,
      snap: _snapOn,
      onsets: _analysis.onsets,
      speechEnds: _analysis.speechEnds,
      startIndex: startIndex,
      // Single words are short: no 0.7 s on-screen minimum, tiny min length.
      minDurMs: _karaoke ? 80 : 300,
      minShowMs: _karaoke ? 0 : 700,
    );
  }

  /// Where to start playback for line [i]: 2 s before it (or the previous
  /// line's end), never before 0.
  int _prerollFor(List<TapLine> lines, int i) {
    if (i <= 0) return 0;
    final prevEnd = lines[i - 1].effEndMs;
    final ownStart = lines[i].effStartMs;
    final ref = ownStart ?? prevEnd ?? 0;
    return (ref - 2000).clamp(0, 1 << 31);
  }

  Future<void> _enterRecord() async {
    final s = _session!;
    setState(() {
      _stage = _Stage.record;
      _countdown = true;
    });
    await _media?.setSpeed(_speed);
    await TapSyncNative.setVolumeKeyCapture(_volKeys);
    await _seek(_prerollFor(s.lines, s.index));
    for (var n = 3; n >= 1; n--) {
      if (!mounted || _stage != _Stage.record) return;
      setState(() => _countdownN = n);
      await Future.delayed(const Duration(milliseconds: 700));
    }
    if (!mounted || _stage != _Stage.record) return;
    setState(() => _countdown = false);
    await _play();
  }

  // ── Recording input ──────────────────────────────────────────────────────

  void _onVolumeKey(bool down) {
    if (_stage != _Stage.record) return;
    down ? _onDown() : _onUp();
  }

  void _onDown() {
    final s = _session;
    if (s == null || _countdown || s.isDone) return;
    if (!_playing) {
      _play();
      return;
    }
    final t = _mediaNow();
    setState(() {
      _pressed = true;
      _dirty = true;
      if (s.mode == TapMode.hold) {
        s.press(t);
      } else {
        s.tap(t);
      }
    });
    HapticFeedback.lightImpact();
    if (s.isDone) _finishRecording();
  }

  void _onUp() {
    final s = _session;
    if (!_pressed) return;
    setState(() => _pressed = false);
    if (s == null || s.mode != TapMode.hold || !s.inProgress) return;
    setState(() => s.release(_mediaNow()));
    HapticFeedback.selectionClick();
    if (s.isDone) _finishRecording();
  }

  Future<void> _undo() async {
    final s = _session;
    if (s == null) return;
    final seek = s.undo();
    setState(() {});
    if (seek != null) {
      await _seek(seek);
      if (!_playing) await _play();
    }
  }

  void _skip() {
    final s = _session;
    if (s == null) return;
    setState(() => s.skip());
    if (s.isDone) _finishRecording();
  }

  void _onMediaEnded() {
    final s = _session;
    if (s == null) return;
    if (s.inProgress) {
      if (s.mode == TapMode.hold) {
        s.release(_media!.durationMs);
      } else {
        s.tap(_media!.durationMs);
      }
    }
    _finishRecording();
  }

  bool _finishing = false;

  Future<void> _finishRecording() async {
    if (_finishing || _stage != _Stage.record) return;
    _finishing = true;
    try {
      await _finishRecordingInner();
    } finally {
      _finishing = false;
    }
  }

  Future<void> _finishRecordingInner() async {
    await _pause();
    await TapSyncNative.setVolumeKeyCapture(false);
    await _media?.setSpeed(1.0);
    final retap = _retapIndex;
    if (retap != null) {
      // Copy the single re-tapped line back into the main list.
      final one = _session!.lines.first;
      final target = _lines[retap];
      if (one.isTapped) {
        target
          ..rawStartMs = one.rawStartMs
          ..rawEndMs = one.rawEndMs
          ..startMs = one.startMs
          ..endMs = one.endMs
          ..snappedStart = one.snappedStart
          ..snappedEnd = one.snappedEnd
          ..skipped = false;
      }
      _session = _mainSession;
      _retapIndex = null;
      _mainSession = null;
      _sel = retap;
    }
    _session!.finalize();
    if (!mounted) return;
    setState(() {
      _stage = _Stage.review;
      if (retap == null) _sel = _firstTapped();
    });
  }

  int _firstTapped() {
    final i = _lines.indexWhere((l) => l.isTapped);
    return i < 0 ? 0 : i;
  }

  Future<void> _retapLine(int i) async {
    if (i < 0 || i >= _lines.length) return;
    final src = _lines[i];
    final copy = TapLine(src.text, origStartMs: src.effStartMs, origEndMs: src.effEndMs);
    _mainSession = _session;
    _retapIndex = i;
    _newSession(lines: [copy]);
    // Play from 2 s before this line.
    final ref = src.effStartMs ?? (i > 0 ? _lines[i - 1].effEndMs : 0) ?? 0;
    setState(() {
      _stage = _Stage.record;
      _countdown = true;
    });
    await _media?.setSpeed(_speed);
    await TapSyncNative.setVolumeKeyCapture(_volKeys);
    await _seek((ref - 2000).clamp(0, 1 << 31));
    for (var n = 3; n >= 1; n--) {
      if (!mounted || _stage != _Stage.record) return;
      setState(() => _countdownN = n);
      await Future.delayed(const Duration(milliseconds: 600));
    }
    if (!mounted) return;
    setState(() => _countdown = false);
    await _play();
  }

  // ── Saving ───────────────────────────────────────────────────────────────

  void _save() {
    final provider = context.read<ProjectProvider>();
    final s = _session!;
    s.finalize();
    List<SubtitleSegment> out;
    if (_karaoke) {
      out = _segs.map((x) => x.copy()).toList();
      for (int i = 0; i < out.length; i++) {
        final units = <TapLine>[];
        for (int k = 0; k < _lines.length; k++) {
          if (_unitSeg[k] == i) units.add(_lines[k]);
        }
        if (units.any((u) => u.isTapped)) TapSyncApply.applyWords(out[i], units);
      }
    } else if (_source == _Source.ai) {
      out = _segs.map((x) => x.copy()).toList();
      for (int i = 0; i < out.length && i < _lines.length; i++) {
        final l = _lines[i];
        if (l.isTapped) TapSyncApply.retime(out[i], l.startMs!, l.endMs!);
      }
    } else {
      s.fillUntimed();
      out = [
        for (final l in _lines)
          SubtitleSegment(
            id: const Uuid().v4(),
            text: l.text,
            startTime: Duration(milliseconds: l.effStartMs!),
            endTime: Duration(milliseconds: l.effEndMs!),
          ),
      ];
    }
    out.sort((a, b) => a.startTime.compareTo(b.startTime));
    // Never overlap the next segment.
    for (int i = 0; i + 1 < out.length; i++) {
      if (out[i].endTime > out[i + 1].startTime) {
        out[i].endTime = out[i + 1].startTime;
      }
    }
    provider.updateSegments(out); // one undo step
    _dirty = false;
    Navigator.pop(context, true);
  }

  Future<bool> _confirmExit() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(tr('tap.exitTitle'),
            style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(tr('tap.exitBody'),
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('common.cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('tap.exitDiscard'),
                  style: const TextStyle(color: AppColors.accent))),
        ],
      ),
    );
    return ok == true;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  void _showPro() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('PRO', style: TextStyle(color: Color(0xFFFFD700))),
        content: Text(tr('pro.dialogBody'),
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('common.close'))),
        ],
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(child: _body()),
      ),
    );
  }

  Future<void> _handleBack() async {
    switch (_stage) {
      case _Stage.setup:
        if (mounted) Navigator.pop(context);
      case _Stage.script:
        setState(() => _stage = _Stage.setup);
      case _Stage.record:
        if (_retapIndex != null) {
          await _pause();
          await TapSyncNative.setVolumeKeyCapture(false);
          setState(() {
            _session = _mainSession;
            _retapIndex = null;
            _mainSession = null;
            _stage = _Stage.review;
          });
          return;
        }
        await _pause();
        if (_session != null && _session!.tappedCount > 0) {
          await _finishRecording();
        } else {
          await TapSyncNative.setVolumeKeyCapture(false);
          setState(() => _stage = _Stage.setup);
        }
      case _Stage.review:
        if (await _confirmExit() && mounted) Navigator.pop(context);
    }
  }

  Widget _body() {
    switch (_stage) {
      case _Stage.setup:
        return _setupView();
      case _Stage.script:
        return _scriptView();
      case _Stage.record:
        return _recordView();
      case _Stage.review:
        return _reviewView();
    }
  }

  Widget _header(String title, {Widget? trailing, IconData icon = Icons.arrow_back_ios_new}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(icon, color: AppColors.textPrimary, size: 20),
            onPressed: _handleBack,
          ),
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      );

  Widget _segmented<T>(List<(T, String)> items, T value, ValueChanged<T> onChanged) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final it in items)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(it.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: it.$1 == value ? AppColors.primaryDark : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Text(it.$2,
                      style: TextStyle(
                          color: it.$1 == value
                              ? Colors.white
                              : AppColors.textSecondary,
                          fontWeight:
                              it.$1 == value ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 13)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sourceCard({
    required IconData icon,
    required String title,
    required String sub,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primaryDark.withValues(alpha: 0.25)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: selected ? 2 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(height: 10),
                Text(title,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const SizedBox(height: 4),
                Text(sub,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _proBadge() => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFFB300),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('PRO',
            style: TextStyle(
                color: Colors.black, fontSize: 9, fontWeight: FontWeight.w800)),
      );

  Widget _switchRow(String title, bool value, ValueChanged<bool> onChanged,
      {bool pro = false, String? sub}) {
    final locked = pro && !_isPro;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(title,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 14)),
                  ),
                  if (pro) _proBadge(),
                ]),
                if (sub != null)
                  Text(sub,
                      style: const TextStyle(
                          color: AppColors.textHint, fontSize: 11)),
              ],
            ),
          ),
          Switch(
            value: locked ? false : value,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.primaryDark,
            onChanged: (v) => locked ? _showPro() : onChanged(v),
          ),
        ],
      ),
    );
  }

  Widget _setupView() {
    final nSeg = _segs.where((s) => s.text.trim().isNotEmpty).length;
    final hasAi = nSeg > 0;
    final lineCount = _karaoke || _source == _Source.ai
        ? _segs.length
        : _scriptLines.length;
    return Column(
      children: [
        _header(tr('tap.title')),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primaryDark.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.primaryDark.withValues(alpha: 0.6)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                          color: AppColors.primaryDark,
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.touch_app, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(tr('tap.intro'),
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 13, height: 1.45)),
                    ),
                  ],
                ),
              ),
              if (_mediaError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_mediaError!,
                      style: const TextStyle(color: AppColors.accent)),
                ),
              _label(tr('tap.unit')),
              _segmented<bool>(
                [(false, tr('tap.unit.sentence')), (true, tr('tap.unit.word'))],
                _karaoke,
                (v) {
                  if (v && !_isPro) {
                    _showPro();
                    return;
                  }
                  if (v && !hasAi) return;
                  setState(() {
                    _karaoke = v;
                    if (v) _source = _Source.ai;
                  });
                },
              ),
              if (_karaoke)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(tr('tap.unit.wordHint'),
                      style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
                ),
              if (!_karaoke) ...[
                _label(tr('tap.source')),
                Row(
                  children: [
                    _sourceCard(
                      icon: Icons.auto_awesome,
                      title: tr('tap.source.ai'),
                      sub: tr('tap.source.aiCount', {'n': nSeg}),
                      selected: _source == _Source.ai,
                      onTap: hasAi ? () => setState(() => _source = _Source.ai) : null,
                    ),
                    const SizedBox(width: 10),
                    _sourceCard(
                      icon: Icons.content_paste,
                      title: tr('tap.source.script'),
                      sub: _scriptLines.isEmpty
                          ? tr('tap.source.scriptSub')
                          : tr('tap.source.aiCount', {'n': _scriptLines.length}),
                      selected: _source == _Source.script,
                      onTap: () => setState(() => _source = _Source.script),
                    ),
                  ],
                ),
                if (_source == _Source.script && _scriptLines.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _stage = _Stage.script),
                      icon: const Icon(Icons.edit, size: 16),
                      label: Text(tr('tap.script.edit')),
                    ),
                  ),
              ],
              _label(tr('tap.mode')),
              _segmented<TapMode>(
                [
                  (TapMode.hold, tr('tap.mode.hold')),
                  (TapMode.tap, tr('tap.mode.tap')),
                ],
                _mode,
                (v) => setState(() {
                  if (_karaoke) {
                    _karaokeMode = v;
                  } else {
                    _sentenceMode = v;
                  }
                }),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    _mode == TapMode.hold
                        ? tr('tap.mode.holdHint')
                        : tr('tap.mode.tapHint'),
                    style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
              ),
              _label(tr('tap.speed')),
              _segmented<double>(
                [(0.5, '0.5×'), (0.75, '0.75×'), (1.0, '1×')],
                _speed,
                (v) => setState(() => _speed = v),
              ),
              const SizedBox(height: 14),
              const Divider(color: AppColors.border),
              _switchRow(tr('tap.snap'), _snap, (v) => setState(() => _snap = v),
                  pro: true,
                  sub: !_analysisReady && _mediaReady ? tr('tap.analyzing') : null),
              _switchRow(tr('tap.volKeys'), _volKeys,
                  (v) => setState(() => _volKeys = v)),
              Row(
                children: [
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(
                          text: '${tr('tap.offset')}  ',
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 14)),
                      TextSpan(
                          text: '$_effOffset ms',
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontFamily: 'monospace',
                              fontSize: 14)),
                    ])),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final r = await showTapCalibration(context);
                      if (r == null || !mounted) return;
                      setState(() {
                        if (_bt) {
                          _offsetBt = r;
                        } else {
                          _offset = r;
                        }
                      });
                      _savePrefs();
                    },
                    child: Text(tr('tap.calibrate')),
                  ),
                ],
              ),
              if (_bt)
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: AppColors.warning, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(tr('tap.btWarn'),
                            style: const TextStyle(
                                color: AppColors.warning, fontSize: 12, height: 1.4)),
                      ),
                    ],
                  ),
                ),
              if (lineCount > 1 && (_karaoke || _source == _Source.ai)) ...[
                _label(tr('tap.startFrom')),
                DropdownButtonFormField<int>(
                  initialValue: _startLine.clamp(0, _segs.length - 1),
                  isExpanded: true,
                  dropdownColor: AppColors.surface,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (int i = 0; i < _segs.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text('${i + 1}. ${_segs[i].text}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13)),
                      ),
                  ],
                  onChanged: (v) => setState(() => _startLine = v ?? 0),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: !_mediaReady ? null : _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              child: Text(
                _source == _Source.script && !_karaoke && _scriptLines.isEmpty
                    ? tr('tap.script.next')
                    : tr('tap.startAt', {'n': _karaoke || _source == _Source.ai ? _startLine + 1 : 1}),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Script (paste) ───────────────────────────────────────────────────────

  Future<void> _splitScript() async {
    setState(() => _splitting = true);
    final r = await ScriptSplitter.split(_scriptCtl.text,
        maxChars: _maxChars, locale: _project.language);
    if (!mounted) return;
    setState(() {
      _scriptLines = r;
      _splitting = false;
    });
  }

  Future<void> _editScriptLine(int i) async {
    final ctl = TextEditingController(text: _scriptLines[i]);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(tr('tap.script.editLine'),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: TextField(
          controller: ctl,
          maxLines: 4,
          minLines: 1,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(helperText: tr('tap.script.editHint')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('common.cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctl.text),
              child: Text(tr('common.save'))),
        ],
      ),
    );
    ctl.dispose();
    if (r == null) return;
    final parts = r.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    setState(() {
      _scriptLines = [
        ..._scriptLines.sublist(0, i),
        ...parts,
        ..._scriptLines.sublist(i + 1),
      ];
    });
  }

  Future<void> _confirmScriptAndStart() async {
    if (_scriptLines.isEmpty) return;
    final existing = _segs.where((s) => s.text.trim().isNotEmpty).length;
    if (existing > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          content: Text(tr('tap.script.replaceWarn', {'n': existing}),
              style: const TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('common.cancel'))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('ed.ok'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    _source = _Source.script;
    _startLine = 0;
    await _start();
  }

  Widget _scriptView() {
    return Column(
      children: [
        _header(tr('tap.source.script')),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              TextField(
                controller: _scriptCtl,
                minLines: 5,
                maxLines: 10,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: tr('tap.script.hint'),
                  hintStyle: const TextStyle(color: AppColors.textHint),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(tr('tap.script.maxChars', {'n': _maxChars}),
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _maxChars.toDouble(),
                      min: 12,
                      max: 48,
                      divisions: 36,
                      onChanged: (v) => setState(() => _maxChars = v.round()),
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _splitting ? null : _splitScript,
                  icon: const Icon(Icons.format_list_numbered),
                  label: Text(tr('tap.script.split')),
                ),
              ),
              if (_scriptLines.isNotEmpty) ...[
                _label(tr('tap.script.lines', {'n': _scriptLines.length})),
                for (int i = 0; i < _scriptLines.length; i++)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: Text('${i + 1}',
                          style: const TextStyle(color: AppColors.textHint)),
                      title: Text(_scriptLines[i],
                          style: const TextStyle(color: AppColors.textPrimary)),
                      onTap: () => _editScriptLine(i),
                      trailing: i + 1 < _scriptLines.length
                          ? IconButton(
                              tooltip: tr('tap.script.merge'),
                              icon: const Icon(Icons.merge_type,
                                  color: AppColors.textSecondary, size: 20),
                              onPressed: () => setState(() => _scriptLines =
                                  ScriptSplitter.mergeWithNext(_scriptLines, i)),
                            )
                          : null,
                    ),
                  ),
                Text(tr('tap.script.tip'),
                    style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _scriptLines.isEmpty || !_mediaReady
                  ? null
                  : _confirmScriptAndStart,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
              ),
              child: Text(tr('tap.startAt', {'n': 1}),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Record ───────────────────────────────────────────────────────────────

  Widget _recordView() {
    final s = _session!;
    final total = s.lines.length;
    final idx = s.index.clamp(0, total);
    final cur = s.current;
    final prev = idx > 0 ? s.lines[idx - 1] : null;
    final hold = s.mode == TapMode.hold;
    final active = s.inProgress;
    final isLastTapEnd = !hold && active && s.next == null;

    final Color btnColor = _karaoke
        ? const Color(0xFFFFD43B)
        : (active ? AppColors.success : const Color(0xFF34D399));
    final String title;
    final String sub;
    if (!_playing && !_countdown) {
      title = tr('tap.rec.resume');
      sub = '';
    } else if (hold) {
      title = active ? tr('tap.rec.speaking') : tr('tap.rec.hold');
      sub = active ? tr('tap.rec.releaseHint') : tr('tap.rec.holdHint');
    } else {
      title = tr('tap.rec.tap');
      sub = isLastTapEnd
          ? tr('tap.rec.tapEndHint')
          : (_karaoke ? tr('tap.rec.tapWordHint') : tr('tap.rec.tapHint'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textPrimary),
                onPressed: _handleBack,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      _karaoke
                          ? tr('tap.rec.wordCount', {
                              'i': (idx + 1).clamp(1, total),
                              'n': total,
                            })
                          : '${(idx + 1).clamp(1, total)} / $total',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : idx / total,
                        minHeight: 4,
                        backgroundColor: AppColors.surfaceLight,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$_speed×',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontFamily: 'monospace',
                        fontSize: 12)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 170,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_media != null)
                ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _media!.preview()),
              if (_countdown)
                Text('$_countdownN',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 64,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(blurRadius: 12)])),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TapWaveform(
          nowMs: _now,
          samples: _analysis.waveform,
          lines: s.lines,
          activeStartMs: active ? cur?.startMs : null,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _karaoke
                ? _karaokeWords(s)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (prev != null)
                        Text('✓ ${prev.text}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textHint, fontSize: 13)),
                      const SizedBox(height: 10),
                      Text(cur?.text ?? tr('tap.rec.done'),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: active ? Colors.white : AppColors.textPrimary,
                              fontSize: 24,
                              height: 1.35,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      if (s.next != null)
                        Text('${tr('tap.rec.next')}: ${s.next!.text}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TapSideButton(
                    icon: Icons.undo,
                    label: _karaoke ? tr('tap.rec.backWord') : tr('tap.rec.back'),
                    onTap: _countdown ? null : _undo,
                  ),
                  const SizedBox(height: 12),
                  TapSideButton(
                    icon: Icons.skip_next,
                    label: tr('tap.rec.skip'),
                    onTap: _countdown || (hold && active) ? null : _skip,
                  ),
                ],
              ),
              // The big button shrinks on narrow phones so the side buttons fit.
              Expanded(
                child: LayoutBuilder(
                  builder: (_, c) => Center(
                    child: TapBigButton(
                      active: _pressed || active,
                      color: btnColor,
                      icon: hold ? Icons.mic : Icons.touch_app,
                      title: title,
                      subtitle: sub,
                      onDown: _onDown,
                      onUp: _onUp,
                      // Leave room for the outside border/glow (~14 px a side).
                      size: (c.maxWidth - 32).clamp(120.0, 180.0),
                    ),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TapSideButton(
                    icon: _playing ? Icons.pause : Icons.play_arrow,
                    label: _playing ? tr('tap.rec.pause') : tr('tap.rec.play'),
                    onTap: _countdown ? null : () => _playing ? _pause() : _play(),
                  ),
                  const SizedBox(height: 12),
                  TapSideButton(
                    icon: Icons.check,
                    label: tr('tap.rec.finish'),
                    onTap: _countdown || s.tappedCount == 0
                        ? null
                        : _finishRecording,
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            _volKeys ? tr('tap.rec.volHint') : tr('tap.rec.hapticHint'),
            style: const TextStyle(color: AppColors.textHint, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _karaokeWords(TapSyncSession s) {
    if (_unitSeg.isEmpty) return const SizedBox.shrink();
    final idx = s.index.clamp(0, s.lines.length - 1);
    final seg = _unitSeg[idx];
    final children = <Widget>[];
    for (int k = 0; k < s.lines.length; k++) {
      if (_unitSeg[k] != seg) continue;
      final l = s.lines[k];
      final isCur = k == s.index;
      final done = l.isTapped || (l.startMs != null && k < s.index);
      children.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isCur
              ? const Color(0xFFFFD43B).withValues(alpha: 0.15)
              : done
                  ? AppColors.primaryDark.withValues(alpha: 0.6)
                  : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isCur ? const Color(0xFFFFD43B) : Colors.transparent, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.text,
                style: TextStyle(
                    color: isCur
                        ? const Color(0xFFFFD43B)
                        : done
                            ? Colors.white
                            : AppColors.textHint,
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            Text(
                l.startMs != null
                    ? fmtTapTime(l.startMs!)
                    : (isCur ? tr('tap.rec.waiting') : '–'),
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                    fontFamily: 'monospace')),
          ],
        ),
      ));
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(tr('tap.rec.sentenceN', {'i': seg + 1, 'n': _segs.length}),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: children),
      ],
    );
  }

  // ── Review ───────────────────────────────────────────────────────────────

  void _nudge(int i, {required bool start, required int deltaMs}) {
    final l = _lines[i];
    if (!l.hasTiming) return;
    var s = l.effStartMs!, e = l.effEndMs!;
    if (start) {
      s = (s + deltaMs).clamp(0, e - 100);
    } else {
      e = (e + deltaMs).clamp(s + 100, 1 << 31);
    }
    setState(() {
      l
        ..startMs = s
        ..endMs = e
        ..skipped = false;
      if (start) l.snappedStart = false;
      if (!start) l.snappedEnd = false;
      _dirty = true;
    });
  }

  Future<void> _playLine(int i) async {
    final l = _lines[i];
    if (!l.hasTiming) return;
    await _media?.setSpeed(1.0);
    await _seek((l.effStartMs! - 300).clamp(0, 1 << 31));
    _autoPauseAt = l.effEndMs! + 300;
    await _play();
  }

  String? _currentReviewText(int now) {
    for (final l in _lines) {
      if (l.hasTiming && now >= l.effStartMs! && now < l.effEndMs!) return l.text;
    }
    return null;
  }

  Widget _reviewView() {
    final s = _session!;
    final sel = _sel.clamp(0, _lines.length - 1);
    final l = _lines[sel];
    final shift = (_effOffset * _speed).round();
    return Column(
      children: [
        _header(tr('tap.review.title'),
            trailing: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
              ),
              child: Text(tr('common.save')),
            )),
        SizedBox(
          height: 190,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              if (_media != null)
                Center(
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _media!.preview())),
              ValueListenableBuilder<int>(
                valueListenable: _now,
                builder: (_, now, _) {
                  final t = _currentReviewText(now);
                  if (t == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14, left: 24, right: 24),
                    child: Text(t,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
                  );
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              ValueListenableBuilder<int>(
                valueListenable: _now,
                builder: (_, now, _) => Text(
                    '${fmtTapTime(now)} / ${fmtTapTime(_media?.durationMs ?? 0)}',
                    style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontFamily: 'monospace',
                        fontSize: 12)),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow,
                    color: AppColors.textPrimary),
                onPressed: () async {
                  if (_playing) {
                    await _pause();
                  } else {
                    _autoPauseAt = null;
                    await _media?.setSpeed(1.0);
                    await _play();
                  }
                },
              ),
              const Spacer(),
              Text(tr('tap.review.withSubs'),
                  style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
            ],
          ),
        ),
        if (l.hasTiming)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TapLineWaveform(
              samples: _analysis.waveform,
              fromMs: (l.effStartMs! - 1200).clamp(0, 1 << 31),
              toMs: l.effEndMs! + 1200,
              startMs: l.effStartMs!,
              endMs: l.effEndMs!,
              pressedStartMs: l.rawStartMs == null ? null : (l.rawStartMs! + shift).clamp(0, 1 << 31),
              pressedEndMs: l.rawEndMs == null ? null : l.rawEndMs! + shift,
              nowMs: _now,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              _legendDash(),
              const SizedBox(width: 6),
              Text(tr('tap.review.pressed'),
                  style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
              const SizedBox(width: 14),
              Container(width: 14, height: 3, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(tr('tap.review.final'),
                  style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
              const SizedBox(height: 8),
              if (l.hasTiming)
                Row(
                  children: [
                    Expanded(child: _nudger(tr('tap.review.start'), l.effStartMs!, (d) => _nudge(sel, start: true, deltaMs: d))),
                    const SizedBox(width: 8),
                    Expanded(child: _nudger(tr('tap.review.end'), l.effEndMs!, (d) => _nudge(sel, start: false, deltaMs: d))),
                  ],
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _karaoke ? null : () => _retapLine(sel),
                  child: Text(tr('tap.review.retap')),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            itemCount: _lines.length,
            itemBuilder: (_, i) {
              final x = _lines[i];
              final selected = i == sel;
              final badge = _badge(s, x);
              return Material(
                color: selected
                    ? AppColors.primaryDark.withValues(alpha: 0.35)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    setState(() => _sel = i);
                    _playLine(i);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 56,
                          child: Text(
                              x.hasTiming ? fmtTapTime(x.effStartMs!) : '--',
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontFamily: 'monospace',
                                  fontSize: 12)),
                        ),
                        Expanded(
                          child: Text(x.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: selected ? Colors.white : AppColors.textPrimary,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
                        ),
                        ?badge,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _legendDash() => SizedBox(
        width: 14,
        height: 3,
        child: Row(
          children: [
            Expanded(child: Container(color: Colors.white70)),
            const SizedBox(width: 3),
            Expanded(child: Container(color: Colors.white70)),
          ],
        ),
      );

  Widget? _badge(TapSyncSession s, TapLine x) {
    String? text;
    Color c = AppColors.success;
    if (!_karaoke && s.isTooFast(x)) {
      text = tr('tap.badge.tooFast');
      c = AppColors.warning;
    } else if (x.isTapped && (x.snappedStart || x.snappedEnd)) {
      text = tr('tap.badge.snapped');
    } else if (x.isTapped) {
      text = tr('tap.badge.tapped');
      c = AppColors.primary;
    } else if (x.hasTiming) {
      text = tr('tap.badge.kept');
      c = AppColors.textHint;
    } else {
      text = tr('tap.badge.none');
      c = AppColors.accent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }

  Widget _nudger(String label, int ms, ValueChanged<int> onDelta) {
    Widget btn(IconData ic, int d) => InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onDelta(d),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(ic, size: 18, color: AppColors.textPrimary),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textHint, fontSize: 11)),
        const SizedBox(height: 4),
        Row(
          children: [
            btn(Icons.chevron_left, -50),
            Expanded(
              child: Text(fmtTapTime(ms),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontFamily: 'monospace',
                      fontSize: 14)),
            ),
            btn(Icons.chevron_right, 50),
          ],
        ),
      ],
    );
  }
}
