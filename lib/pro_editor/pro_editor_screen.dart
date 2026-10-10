import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../i18n/i18n.dart';
import '../models/subtitle_style_model.dart';
import '../providers/project_provider.dart';
import '../screens/export_screen.dart';
import '../services/free_quota_service.dart';
import '../services/media_info_service.dart';
import '../services/tap_sync_media.dart';
import '../theme/app_theme.dart';
import '../timeline/timeline_model.dart';
import 'pro_editor_controller.dart';
import 'pro_media.dart';
import 'pro_preview.dart';
import 'pro_timeline_view.dart';

/// Pro Editor (beta) — CapCut-style multi-track editing (PRO_EDITOR_PLAN
/// phase 2). Opens [ProjectProvider.currentProject], saves back to it (v1 +
/// the v2 timeline) so the classic editor and exporter keep working.
class ProEditorScreen extends StatefulWidget {
  /// Tests inject a fake player / file picker / duration probe.
  @visibleForTesting
  final TapSyncMedia Function(SubtitleProject projected)? mediaFactory;
  @visibleForTesting
  final Future<String?> Function(String kind)? pickFile;
  @visibleForTesting
  final Future<int> Function(String path)? probeDurationMs;

  const ProEditorScreen({super.key, this.mediaFactory, this.pickFile, this.probeDurationMs});

  @override
  State<ProEditorScreen> createState() => _ProEditorScreenState();
}

class _ProEditorScreenState extends State<ProEditorScreen>
    with SingleTickerProviderStateMixin {
  late final ProEditorController c;
  late final ProMedia media;
  bool _isPro = false;

  Timer? _saveDebounce;
  Timer? _mediaDebounce;
  Timer? _poll;
  late final Ticker _ticker;
  final _sw = Stopwatch()..start();
  int _anchorPos = 0;
  int _anchorSw = 0;
  bool _playing = false;
  int _lastSeekSw = 0;
  String? _shownError;

  @override
  void initState() {
    super.initState();
    final project = context.read<ProjectProvider>().currentProject!;
    c = ProEditorController(project);
    media = ProMedia(factory: widget.mediaFactory);
    c.addListener(_onControllerChange);
    _ticker = createTicker((_) {
      if (_playing) c.seek(_anchorPos + (_sw.elapsedMilliseconds - _anchorSw));
    });
    _syncMedia();
    FreeQuotaService.isPro().then((v) {
      if (mounted) setState(() => _isPro = v);
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _mediaDebounce?.cancel();
    _poll?.cancel();
    _ticker.dispose();
    c.removeListener(_onControllerChange);
    media.dispose();
    c.dispose();
    super.dispose();
  }

  // ── Persistence & media sync ─────────────────────────────────────────────

  void _onControllerChange() {
    final err = c.lastError;
    if (err != null && err != _shownError) {
      _shownError = err;
      _toast(_errorText(err));
    } else if (err == null) {
      _shownError = null;
    }
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), _save);
    _mediaDebounce?.cancel();
    _mediaDebounce = Timer(const Duration(milliseconds: 300), _syncMedia);
    if (mounted) setState(() {});
  }

  void _save() {
    if (!mounted) return;
    context.read<ProjectProvider>().updateProject(c.toProject());
  }

  Future<void> _syncMedia() async {
    final changed = await media.sync(c.timeline, c.toProject());
    if (!mounted || !changed) return;
    if (_playing) await _pause();
    await media.seek(c.playhead.value);
    setState(() {});
  }

  String _errorText(String code) => switch (code) {
        'overlap' => tr('pe.err.overlap'),
        'locked' => tr('pe.err.locked'),
        'tooShort' => tr('pe.err.tooShort'),
        'nothingHere' => tr('pe.err.nothingHere'),
        'wrongTrack' => tr('pe.err.wrongTrack'),
        _ => tr('pe.err.generic'),
      };

  // ── Playback ─────────────────────────────────────────────────────────────

  Future<void> _play() async {
    if (!media.ready) return;
    if (c.playhead.value >= c.durationMs - 50) {
      c.seek(0);
      await media.seek(0);
    }
    await media.play();
    _playing = true;
    _anchorPos = c.playhead.value;
    _anchorSw = _sw.elapsedMilliseconds;
    _ticker.start();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 150), (_) async {
      final pos = await media.positionMs();
      if (!mounted || !_playing) return;
      _anchorPos = pos;
      _anchorSw = _sw.elapsedMilliseconds;
      if (pos >= c.durationMs - 30 || !media.isPlaying && pos > 0) {
        await _pause();
      }
    });
    setState(() {});
  }

  Future<void> _pause() async {
    _poll?.cancel();
    _ticker.stop();
    _playing = false;
    await media.pause();
    if (mounted) setState(() {});
  }

  void _onScrubStart() {
    if (_playing) _pause();
  }

  void _onScrub(int ms) {
    c.seek(ms);
    final now = _sw.elapsedMilliseconds;
    if (now - _lastSeekSw > 60) {
      _lastSeekSw = now;
      media.seek(c.playhead.value);
    }
  }

  void _onScrubEnd() => media.seek(c.playhead.value);

  // ── Adding media ─────────────────────────────────────────────────────────

  Future<String?> _pick(String kind) async {
    if (widget.pickFile != null) return widget.pickFile!(kind);
    final type = switch (kind) {
      'video' => FileType.video,
      'image' => FileType.image,
      'audio' => FileType.audio,
      _ => FileType.any,
    };
    final r = await FilePicker.platform.pickFiles(type: type);
    final src = r?.files.single.path;
    if (src == null) return null;
    // Keep our own copy (the picker's cache can be cleared by the system).
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'pro_media'))..createSync(recursive: true);
    final dest = p.join(dir.path, '${kind}_${DateTime.now().millisecondsSinceEpoch}${p.extension(src)}');
    await File(src).copy(dest);
    return dest;
  }

  Future<int> _duration(String path) async {
    if (widget.probeDurationMs != null) return widget.probeDurationMs!(path);
    final m = await MediaInfoService.meta(path, 'pro_${path.hashCode}');
    return m.durationMs;
  }

  Future<void> _addClip() async {
    await _pause();
    final path = await _pick('video');
    if (path == null) return;
    final dur = await _duration(path);
    if (dur <= 0) {
      _toast(tr('pe.err.badFile'));
      return;
    }
    c.addMainClip(path, dur);
  }

  Future<void> _addOverlay() async {
    await _pause();
    if (!mounted) return;
    final kind = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.movie, color: AppColors.textPrimary),
              title: Text(tr('pe.overlay.video'), style: const TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, 'video'),
            ),
            ListTile(
              leading: const Icon(Icons.image, color: AppColors.textPrimary),
              title: Text(tr('pe.overlay.image'), style: const TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, 'image'),
            ),
          ],
        ),
      ),
    );
    if (kind == null) return;
    if (kind == 'video') {
      // Decision (plan §8): Free 1 PiP layer, PRO 2.
      final limit = _isPro ? 2 : 1;
      if (c.pipLayersAt(c.playhead.value) >= limit) {
        _toast(_isPro ? tr('pe.pip.max') : tr('pe.pip.pro'));
        return;
      }
    }
    final path = await _pick(kind);
    if (path == null) return;
    var dur = kind == 'video' ? await _duration(path) : 3000;
    if (dur <= 0) dur = 3000;
    c.addOverlay(path, dur, isVideo: kind == 'video');
  }

  Future<void> _addMusic() async {
    await _pause();
    final path = await _pick('audio');
    if (path == null) return;
    var dur = await _duration(path);
    if (dur <= 0) {
      _toast(tr('pe.err.badFile'));
      return;
    }
    final room = c.durationMs - c.playhead.value;
    if (room > 0 && dur > room) dur = room;
    c.addAudio(path, dur, label: p.basenameWithoutExtension(path));
  }

  // ── Sheets ───────────────────────────────────────────────────────────────

  void _volumeSheet() {
    final e = c.primaryElement;
    if (e == null || (e is! VideoElement && e is! AudioElement)) return;
    final id = e.id;
    var v = e is VideoElement ? e.volume : (e as AudioElement).volume;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('pe.volume'),
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                Row(
                  children: [
                    const Icon(Icons.volume_down, color: AppColors.textSecondary),
                    Expanded(
                      child: Slider(
                        value: v,
                        max: 2,
                        divisions: 40,
                        label: '${(v * 100).round()}%',
                        onChanged: (x) => set(() => v = x),
                        onChangeEnd: (x) => c.setVolume(id, x),
                      ),
                    ),
                    Text('${(v * 100).round()}%',
                        style: const TextStyle(color: AppColors.textPrimary, fontFamily: 'monospace')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _trackMenu(Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              value: track.muted,
              title: Text(tr('pe.track.mute'), style: const TextStyle(color: AppColors.textPrimary)),
              onChanged: (v) {
                c.setTrack(track.id, muted: v);
                Navigator.pop(ctx);
              },
            ),
            SwitchListTile(
              value: track.locked,
              title: Text(tr('pe.track.lock'), style: const TextStyle(color: AppColors.textPrimary)),
              onChanged: (v) {
                c.setTrack(track.id, locked: v);
                Navigator.pop(ctx);
              },
            ),
            if (track.kind != TrackKind.mainVideo)
              SwitchListTile(
                value: track.hidden,
                title: Text(tr('pe.track.hide'), style: const TextStyle(color: AppColors.textPrimary)),
                onChanged: (v) {
                  c.setTrack(track.id, hidden: v);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _comingSoon(String version) => _toast(tr('pe.soon', {'v': version}));

  // ── Export / close ───────────────────────────────────────────────────────

  Future<void> _export() async {
    await _pause();
    _saveDebounce?.cancel();
    final project = c.toProject();
    if (!mounted) return;
    final provider = context.read<ProjectProvider>();
    provider.updateProject(project);
    provider.setCurrentProject(project);
    if (c.lossy.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(tr('pe.lossy.title'), style: const TextStyle(color: AppColors.textPrimary)),
          content: Text(
            tr('pe.lossy.body', {'list': c.lossy.map((k) => tr('pe.lossy.$k')).join(', ')}),
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('common.cancel'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('pe.export'))),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ExportScreen()));
  }

  Future<void> _close() async {
    await _pause();
    _saveDebounce?.cancel();
    _save();
    if (mounted) Navigator.pop(context);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ));
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _topBar(),
              Expanded(
                flex: 11,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ValueListenableBuilder<int>(
                    valueListenable: c.playhead,
                    builder: (_, ms, _) => ProPreview(
                      timeline: c.timeline,
                      ms: ms,
                      video: media.preview(),
                      videoAspect: media.aspectRatio,
                      selectedId: c.primary,
                    ),
                  ),
                ),
              ),
              _playBar(),
              Expanded(
                flex: 10,
                child: ProTimelineView(
                  c: c,
                  onScrubStart: _onScrubStart,
                  onScrub: _onScrub,
                  onScrubEnd: _onScrubEnd,
                  onAddClip: _addClip,
                  onTrackMenu: _trackMenu,
                ),
              ),
              _toolbar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        child: Row(
          children: [
            IconButton(
              key: const Key('pe_close'),
              icon: const Icon(Icons.close, color: AppColors.textPrimary),
              onPressed: _close,
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('BETA',
                  style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w800)),
            ),
            const Spacer(),
            Flexible(
              child: GestureDetector(
                onTap: _export,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text('1080P',
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            style: TextStyle(color: AppColors.textPrimary, fontFamily: 'monospace')),
                      ),
                      Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.textPrimary),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              key: const Key('pe_export'),
              onPressed: _export,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 36),
              ),
              child: Text(tr('pe.export')),
            ),
          ],
        ),
      );

  static String _fmt(int ms) {
    final s = ms ~/ 1000;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _playBar() => SizedBox(
        height: 44,
        child: Row(
          children: [
            const SizedBox(width: 16),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: ValueListenableBuilder<int>(
                    valueListenable: c.playhead,
                    builder: (_, ms, _) => Text('${_fmt(ms)} / ${_fmt(c.durationMs)}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontFamily: 'monospace', fontSize: 12)),
                  ),
                ),
              ),
            ),
            IconButton(
              key: const Key('pe_play'),
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow, color: AppColors.textPrimary, size: 30),
              onPressed: _playing ? _pause : _play,
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    key: const Key('pe_undo'),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.undo, color: c.canUndo ? AppColors.textPrimary : AppColors.textHint),
                    onPressed: c.canUndo ? c.undo : null,
                  ),
                  IconButton(
                    key: const Key('pe_redo'),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.redo, color: c.canRedo ? AppColors.textPrimary : AppColors.textHint),
                    onPressed: c.canRedo ? c.redo : null,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _toolbar() {
    final e = c.primaryElement;
    final items = <Widget>[];
    if (e == null) {
      items.addAll([
        _tool(Icons.content_cut, tr('pe.tool.split'), c.splitAtPlayhead, key: 'split'),
        _tool(Icons.music_note, tr('pe.tool.audio'), _addMusic, key: 'audio'),
        _tool(Icons.title, tr('pe.tool.text'), () => _comingSoon('1.7'), key: 'text'),
        _tool(Icons.layers, tr('pe.tool.overlay'), _addOverlay, key: 'overlay'),
        _tool(Icons.auto_awesome, tr('pe.tool.effect'), () => _comingSoon('1.8'), key: 'effect'),
        _tool(Icons.filter_vintage, tr('pe.tool.filter'), () => _comingSoon('1.8'), key: 'filter'),
        _tool(Icons.bookmark_add_outlined, tr('pe.tool.bookmark'), c.toggleBookmark, key: 'bookmark'),
        _tool(c.ripple ? Icons.link : Icons.link_off, tr('pe.tool.ripple'), () {
          c.ripple = !c.ripple;
          _toast(c.ripple ? tr('pe.ripple.on') : tr('pe.ripple.off'));
          setState(() {});
        }, key: 'ripple', active: c.ripple),
        if (c.hasClipboard)
          _tool(Icons.content_paste, tr('pe.tool.paste'), c.paste, key: 'paste'),
      ]);
    } else {
      final media = e is VideoElement || e is AudioElement;
      items.addAll([
        _tool(Icons.chevron_left, '', c.clearSelection, key: 'back'),
        _tool(Icons.vertical_split, tr('pe.tool.split'), c.splitAtPlayhead, key: 'split'),
        if (e is VideoElement)
          _tool(Icons.speed, tr('pe.tool.speed'), () => _comingSoon('1.7'), key: 'speed'),
        if (media) _tool(Icons.volume_up, tr('pe.tool.volume'), _volumeSheet, key: 'volume'),
        if (e is VideoElement || e is ImageElement)
          _tool(Icons.animation, 'Animation', () => _comingSoon('1.7'), key: 'anim'),
        _tool(Icons.copy_all, tr('pe.tool.duplicate'), c.duplicateSelected, key: 'duplicate'),
        _tool(Icons.content_copy, tr('pe.tool.copy'), () {
          c.copySelected();
          _toast(tr('pe.copied'));
        }, key: 'copy'),
        _tool(Icons.delete_outline, tr('pe.tool.delete'), c.deleteSelected, key: 'delete'),
        if (e is VideoElement || e is ImageElement)
          _tool(Icons.crop_free, 'Mask', () => _comingSoon('1.7'), key: 'mask'),
      ]);
    }
    return Container(
      height: 66,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        children: items,
      ),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap,
          {required String key, bool active = false}) =>
      InkWell(
        key: Key('pe_tool_$key'),
        onTap: onTap,
        child: SizedBox(
          width: label.isEmpty ? 44 : 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: active ? AppColors.primary : AppColors.textPrimary, size: 22),
              if (label.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: active ? AppColors.primary : AppColors.textSecondary, fontSize: 10.5)),
              ],
            ],
          ),
        ),
      );
}
