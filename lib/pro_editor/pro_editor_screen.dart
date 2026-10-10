import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../i18n/i18n.dart';
import '../models/subtitle_style_model.dart';
import '../providers/project_provider.dart';
import '../screens/export_screen.dart';
import '../screens/processing_screen.dart';
import '../services/free_quota_service.dart';
import '../services/media_info_service.dart';
import '../services/tap_sync_media.dart';
import '../services/video_merge_service.dart';
import '../services/thumbnail_service.dart';
import '../theme/app_theme.dart';
import '../timeline/export_plan.dart';
import '../timeline/layer_render.dart';
import '../timeline/project_v1.dart';
import '../timeline/timeline_audio.dart';
import '../timeline/timeline_model.dart';
import 'pro_editor_controller.dart';
import 'pro_media.dart';
import 'pro_preview.dart';
import 'pro_sheets.dart';
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
  @visibleForTesting
  final TimelineAudioRenderer? audioRenderer;
  @visibleForTesting
  final Widget Function(String wav, String engine, void Function(List<SubtitleSegment>) onResult)?
      processingBuilder;
  @visibleForTesting
  final Future<Directory> Function()? tempDir;
  @visibleForTesting
  final Future<List<({int ms, String path})>> Function(String videoPath)? thumbnailLoader;
  @visibleForTesting
  final Future<Directory> Function()? layerDir;
  @visibleForTesting
  final Future<String> Function(List<String> paths)? merge;
  @visibleForTesting
  final WidgetBuilder? exportScreen;

  const ProEditorScreen({
    super.key,
    this.mediaFactory,
    this.pickFile,
    this.probeDurationMs,
    this.audioRenderer,
    this.processingBuilder,
    this.tempDir,
    this.thumbnailLoader,
    this.layerDir,
    this.merge,
    this.exportScreen,
  });

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
  bool _fullscreen = false;
  final ThumbMap _thumbs = {};
  final Set<String> _thumbsLoading = {};

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

  /// Save v1 (+ the v2 timeline). Text/shape/mask layers are drawn to PNGs
  /// first so the classic editor and exporter see them too.
  Future<void> _save() async {
    if (!mounted) return;
    final provider = context.read<ProjectProvider>();
    final timeline = c.timeline;
    var rendered = const <String, String>{};
    try {
      rendered = await renderLayers(timeline, await _layerDir());
    } catch (_) {}
    // Finish even if the screen closed meanwhile — never drop the last edit.
    provider.updateProject(c.toProject(rendered: rendered));
  }

  Future<Directory> _layerDir() async {
    if (widget.layerDir != null) return widget.layerDir!();
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'layers'));
  }

  /// Filmstrip frames for every main-track source (each loaded once).
  Future<void> _loadThumbs() async {
    final srcs = c.timeline.mainTrack?.elements.whereType<VideoElement>().map((e) => e.src).toSet() ??
        const <String>{};
    for (final src in srcs) {
      if (_thumbs.containsKey(src) || !_thumbsLoading.add(src)) continue;
      final frames = await (widget.thumbnailLoader ??
          (String p) => ThumbnailService.extract(p, maxCount: 60, height: 120))(src);
      _thumbsLoading.remove(src);
      if (!mounted) return;
      if (frames.isNotEmpty) setState(() => _thumbs[src] = frames);
    }
  }

  /// "ໜ້າປົກ": the frame under the playhead becomes the project cover.
  Future<void> _setCover() async {
    final at = c.playhead.value;
    final clip = c.timeline.mainTrack?.elements
        .whereType<VideoElement>()
        .where((e) => at >= e.startMs && at < e.endMs)
        .firstOrNull;
    final frames = clip == null ? null : _thumbs[clip.src];
    if (clip == null || frames == null || frames.isEmpty) {
      _toast(tr('pe.cover.none'));
      return;
    }
    final srcMs = clip.trimInMs + ((at - clip.startMs) * clip.speed).round();
    var best = frames.first;
    for (final f in frames) {
      if ((f.ms - srcMs).abs() < (best.ms - srcMs).abs()) best = f;
    }
    try {
      final support = await getApplicationSupportDirectory();
      final dest = p.join(support.path, 'thumbs', 'cover_${c.base.id}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      Directory(p.dirname(dest)).createSync(recursive: true);
      await File(best.path).copy(dest);
      c.coverPath = dest;
    } catch (_) {
      c.coverPath = best.path;
    }
    _save();
    _toast(tr('pe.cover.set'));
  }

  Future<void> _syncMedia() async {
    _loadThumbs();
    // Preview always uses the gapless multi-clip layout (cut timeline).
    final changed = await media.sync(c.timeline, projectToV1(c.timeline).project);
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

  // ── AI subtitles from the EDITED timeline (CapCut "auto captions") ───────

  static const _audioCh = MethodChannel('com.anniekaydee.subtitle_app/audio');

  Future<void> _aiSubtitles() async {
    await _pause();
    if (c.timeline.mainTrack?.elements.isEmpty ?? true) {
      _toast(tr('pe.ai.noClips'));
      return;
    }
    final s = c.timeline.settings;
    var src = (s['sourceLanguage'] as String?) ?? 'lo';
    var dst = (s['language'] as String?) ?? 'lo';
    var engine = 'gemini';
    final hasSubs = c.timeline.tracksOf(TrackKind.subtitle).any((t) => t.elements.isNotEmpty);
    if (!mounted) return;
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Widget choice(String label, bool on, VoidCallback tap) => Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: on,
                  onSelected: (_) => set(tap),
                ),
              );
          Widget label(String t) => Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 6),
                child: Text(t, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              );
          const langs = [('lo', 'ລາວ'), ('th', 'ໄທ'), ('en', 'English')];
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('pe.ai.title'),
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(tr('pe.ai.sub'),
                      style: const TextStyle(color: AppColors.textHint, fontSize: 12)),
                  label(tr('pe.ai.spoken')),
                  Wrap(children: [
                    for (final (code, name) in langs)
                      choice(name, src == code, () => src = code),
                  ]),
                  label(tr('pe.ai.subsIn')),
                  Wrap(children: [
                    for (final (code, name) in langs.take(2))
                      choice(name, dst == code, () => dst = code),
                  ]),
                  label('AI'),
                  Wrap(children: [
                    choice(tr('ed.pickGemini'), engine == 'gemini', () => engine = 'gemini'),
                    choice(tr('ed.pickGroq'), engine == 'groq', () => engine = 'groq'),
                    choice('Whisper', engine == 'whisper', () => engine = 'whisper'),
                  ]),
                  if (hasSubs)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(tr('pe.ai.replace'),
                          style: const TextStyle(color: AppColors.warning, fontSize: 12)),
                    ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      key: const Key('pe_ai_go'),
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(tr('pe.ai.go')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (go != true || !mounted) return;

    // Language settings live in the timeline; save so the pipeline sees them.
    final translate = src != dst;
    c.updateSettings({
      'sourceLanguage': src,
      'language': dst,
      'translateMode': (translate ? TranslateMode.translate : TranslateMode.none).index,
    });
    _saveDebounce?.cancel();
    _save();

    // 1) The edited timeline's audio → one WAV.
    final progress = ValueNotifier<double>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('pe.ai.preparing'), style: const TextStyle(color: AppColors.textPrimary)),
              const SizedBox(height: 14),
              LinearProgressIndicator(value: v),
            ],
          ),
        ),
      ),
    );
    String? wav;
    try {
      final dir = await (widget.tempDir ?? getTemporaryDirectory)();
      final out = '${dir.path}/pro_timeline_audio.wav';
      final renderer = widget.audioRenderer ??
          TimelineAudioRenderer((media, wavOut) =>
              _audioCh.invokeMethod('extractAudio', {'videoPath': media, 'outputPath': wavOut}));
      final ms = await renderer.render(c.timeline, out, '${dir.path}/pro_audio_work',
          onProgress: (p) => progress.value = p);
      if (ms != null && ms > 0) wav = out;
    } catch (_) {
      wav = null;
    }
    if (mounted) Navigator.of(context, rootNavigator: true).pop(); // progress dialog
    progress.dispose();
    if (wav == null || !mounted) {
      _toast(tr('pe.err.badFile'));
      return;
    }

    // 2) The normal transcription pipeline, results handed back to us.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => (widget.processingBuilder ?? _defaultProcessing)(
          wav!,
          engine,
          (segments) {
            c.replaceSubtitles(segments);
            // The pipeline may pick a script-matching font on the project.
            final f = context.read<ProjectProvider>().currentProject?.fontFamily;
            if (f != null && f != c.timeline.settings['fontFamily']) {
              c.updateSettings({'fontFamily': f});
            }
          },
        ),
      ),
    );
  }

  static Widget _defaultProcessing(
          String wav, String engine, void Function(List<SubtitleSegment>) onResult) =>
      ProcessingScreen(
        videoPath: wav,
        aiEngine: engine,
        isReTranscribing: true,
        onResult: onResult,
      );

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

  /// Export = the existing exporter, fed ONE file + removed ranges:
  ///  1. save; 2. draw text/shape/mask layers to PNGs; 3. plan the main track
  ///  (merge several source files natively when needed); 4. hand that
  ///  project (in memory) to the export screen; restore afterwards.
  Future<void> _export() async {
    await _pause();
    _saveDebounce?.cancel();
    await _save();
    if (!mounted) return;
    final provider = context.read<ProjectProvider>();
    final saved = provider.currentProject;

    final progress = ValueNotifier<String>(tr('pe.export.preparing'));
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        content: ValueListenableBuilder<String>(
          valueListenable: progress,
          builder: (_, s, _) => Row(children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 16),
            Expanded(child: Text(s, style: const TextStyle(color: AppColors.textPrimary))),
          ]),
        ),
      ),
    );
    SubtitleProject? exportProject;
    String? error;
    try {
      var rendered = const <String, String>{};
      try {
        rendered = await renderLayers(c.timeline, await _layerDir());
      } catch (_) {
        // Export anyway; layers that could not be drawn show up as "lossy".
      }
      // Source lengths: known ones from the timeline, the rest probed.
      final lengths = <String, int>{};
      for (final v in c.timeline.mainTrack?.elements.whereType<VideoElement>() ?? <VideoElement>[]) {
        if (v.sourceMs != null || lengths.containsKey(v.src)) continue;
        final d = await _duration(v.src);
        if (d > 0) lengths[v.src] = d;
      }
      final plan = ExportPlan.of(c.timeline, lengths);
      if (plan == null) {
        error = tr('pe.ai.noClips');
      } else {
        if (plan.needsMerge) {
          progress.value = tr('pe.export.merging');
          plan.videoPath = await (widget.merge ?? VideoMergeService.merge)(plan.mergePaths);
        }
        final r = projectToV1(
            c.timeline.copyWith(settings: {...c.timeline.settings, 'id': c.base.id, 'name': c.base.name}),
            plan: plan,
            rendered: rendered);
        c.lossy = r.lossy;
        exportProject = r.project
          ..name = c.base.name
          ..thumbnailPath = c.coverPath ?? c.base.thumbnailPath;
      }
    } on VideoMergeException catch (e) {
      error = e.incompatible ? tr('pe.export.mergeIncompat') : tr('pe.export.mergeFail');
    } catch (e) {
      error = tr('pe.export.mergeFail');
    }
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
    if (!mounted) return;
    if (error != null || exportProject == null) {
      _toast(error ?? tr('pe.err.generic'));
      return;
    }
    // The export screen reads the current project; this one is in memory only.
    provider.setCurrentProject(exportProject);
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
      if (go != true || !mounted) {
        if (saved != null) provider.setCurrentProject(saved);
        return;
      }
    }
    await Navigator.push(
        context, MaterialPageRoute(builder: widget.exportScreen ?? (_) => const ExportScreen()));
    if (saved != null && mounted) provider.setCurrentProject(saved);
  }

  Future<void> _close() async {
    await _pause();
    _saveDebounce?.cancel();
    await _save();
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
                      onSelect: (id) => id.isEmpty ? c.clearSelection() : c.select(id),
                      onTransformStart: () => c.beginDrag('transform'),
                      onTransform: c.setTransform,
                      onTransformEnd: c.endDrag,
                    ),
                  ),
                ),
              ),
              _playBar(),
              if (!_fullscreen) ...[
                Expanded(
                  flex: 10,
                  child: ProTimelineView(
                    c: c,
                    onScrubStart: _onScrubStart,
                    onScrub: _onScrub,
                    onScrubEnd: _onScrubEnd,
                    onAddClip: _addClip,
                    onTrackMenu: _trackMenu,
                    thumbs: _thumbs,
                    onCover: _setCover,
                    onTransition: (a, b) => showTransitionSheet(context, c, a, b, _toast),
                    onKeyframe: () {
                      final id = c.primary;
                      if (id == null) return;
                      if (c.toggleKeyframe(id)) {
                        _toast(c.hasKeyframeNow(id) ? tr('pe.kf.added') : tr('pe.kf.removed'));
                      }
                    },
                  ),
                ),
                _toolbar(),
              ],
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
                  IconButton(
                    key: const Key('pe_fullscreen'),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                        color: AppColors.textPrimary),
                    onPressed: () => setState(() => _fullscreen = !_fullscreen),
                  ),
                  const SizedBox(width: 4),
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
      // Design 01: ຕັດຕໍ່ · ສຽງ · ຂໍ້ຄວາມ · ຊັບ AI · ຊ້ອນຊັ້ນ · Effect · ຟິວເຕີ (+ extras).
      items.addAll([
        _tool(Icons.content_cut, tr('pe.tool.edit'), c.splitAtPlayhead, key: 'split'),
        _tool(Icons.music_note_outlined, tr('pe.tool.audio'), _addMusic, key: 'audio'),
        _tool(Icons.text_fields, tr('pe.tool.text'), () {
          final id = c.addText(tr('pe.text.default'));
          if (id != null) showTextSheet(context, c, id);
        }, key: 'text'),
        _tool(Icons.auto_awesome, tr('pe.tool.aiSubs'), _aiSubtitles, key: 'aisubs',
            active: !c.timeline.tracksOf(TrackKind.subtitle).any((t) => t.elements.isNotEmpty)),
        _tool(Icons.layers_outlined, tr('pe.tool.overlay'), _addOverlay, key: 'overlay'),
        _tool(Icons.auto_fix_high, tr('pe.tool.effect'), () => _comingSoon('1.8'), key: 'effect'),
        _tool(Icons.filter_vintage_outlined, tr('pe.tool.filter'), () => _comingSoon('1.8'), key: 'filter'),
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
      // Design 02: ‹ | ແຍກ · ຄວາມໄວ · ສຽງ · Animation · ລຶບ · Mask (+ extras),
      // with the tools that fit the selected kind of layer.
      final id = e.id;
      final isMainClip = c.primaryTrack?.kind == TrackKind.mainVideo;
      final media = e is VideoElement || e is AudioElement;
      final visual = e is VisualElement && !isMainClip;
      items.addAll([
        _tool(Icons.chevron_left, '', c.clearSelection, key: 'back'),
        Container(width: 1, margin: const EdgeInsets.symmetric(vertical: 14), color: AppColors.border),
        if (e is TextElement)
          _tool(Icons.edit_note, tr('pe.tool.editText'), () => showTextSheet(context, c, id), key: 'editText'),
        if (e is ShapeElement)
          _tool(Icons.palette_outlined, tr('pe.tool.color'), () => showShapeSheet(context, c, id), key: 'color'),
        _tool(Icons.vertical_split_outlined, tr('pe.tool.split'), c.splitAtPlayhead, key: 'split'),
        if (e is VideoElement)
          _tool(Icons.speed, tr('pe.tool.speed'), () => _comingSoon('1.7'), key: 'speed'),
        if (media) _tool(Icons.volume_up_outlined, tr('pe.tool.volume'), _volumeSheet, key: 'volume'),
        if (visual)
          _tool(Icons.timeline, tr('pe.tool.curve'), () => showKeyframeSheet(context, c, id), key: 'curve'),
        if (visual)
          _tool(Icons.animation, 'Animation', () => showAnimationSheet(context, c, id), key: 'anim')
        else if (e is VideoElement)
          _tool(Icons.animation, 'Animation', () => _comingSoon('1.7'), key: 'anim'),
        _tool(Icons.delete_outline, tr('pe.tool.delete'), c.deleteSelected, key: 'delete'),
        if (e is ImageElement)
          _tool(Icons.crop_free, 'Mask', () => showMaskSheet(context, c, id), key: 'mask')
        else if (e is VideoElement)
          _tool(Icons.crop_free, 'Mask', () => _comingSoon('1.8'), key: 'mask'),
        _tool(Icons.copy_all, tr('pe.tool.duplicate'), c.duplicateSelected, key: 'duplicate'),
        _tool(Icons.content_copy, tr('pe.tool.copy'), () {
          c.copySelected();
          _toast(tr('pe.copied'));
        }, key: 'copy'),
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
