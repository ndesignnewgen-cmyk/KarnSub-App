import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Dart side of the phase-P preview-engine prototype (PreviewEngine.kt).
class PreviewEngineController {
  static const _ch = MethodChannel('com.anniekaydee.subtitle_app/previewengine');
  int? textureId;
  int width = 1080;
  int height = 1920;

  Future<int?> create({int width = 1080, int height = 1920}) async {
    this.width = width;
    this.height = height;
    textureId = await _ch.invokeMethod<int>('create', {'width': width, 'height': height});
    return textureId;
  }

  Future<void> load(String main, {String? pip}) =>
      _ch.invokeMethod('load', {'main': main, 'pip': ?pip});
  Future<void> play() => _ch.invokeMethod('play');
  Future<void> pause() => _ch.invokeMethod('pause');
  Future<void> seek(int ms) => _ch.invokeMethod('seek', {'ms': ms});
  Future<void> setPip(double x, double y, double scale) =>
      _ch.invokeMethod('setPip', {'x': x, 'y': y, 'scale': scale});
  Future<void> setOverlay(Uint8List? png) => _ch.invokeMethod('setOverlay', {'png': png});

  Future<Map<String, dynamic>> stats() async =>
      Map<String, dynamic>.from(await _ch.invokeMethod('stats') as Map);

  Future<void> dispose() async {
    try {
      await _ch.invokeMethod('dispose');
    } catch (_) {}
    textureId = null;
  }
}

/// "ທົດສອບ engine" — the GO/NO-GO measurement screen (plan §4, phase P).
/// GO when, on the mid-range phone: render ≥ 30 fps with main + PiP + text,
/// seek ≤ 100 ms, slow frames ≤ 2 %, and no crash in 10 minutes.
class PreviewBenchScreen extends StatefulWidget {
  const PreviewBenchScreen({super.key});
  @override
  State<PreviewBenchScreen> createState() => _PreviewBenchScreenState();
}

class _PreviewBenchScreenState extends State<PreviewBenchScreen> {
  final _engine = PreviewEngineController();
  final _overlayKey = GlobalKey();
  String? _main;
  String? _pip;
  bool _playing = false;
  bool _ready = false;
  String? _error;
  Map<String, dynamic> _stats = const {};
  Timer? _statsTimer;
  final _sw = Stopwatch();
  double _scrub = 0;
  bool _text = true;
  int _res = 1080;

  @override
  void dispose() {
    _statsTimer?.cancel();
    _engine.dispose();
    super.dispose();
  }

  Future<String?> _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.video);
    return r?.files.single.path;
  }

  Future<void> _start() async {
    if (_main == null) return;
    setState(() => _error = null);
    try {
      final h = _res == 1080 ? 1920 : 1280;
      await _engine.create(width: _res, height: h);
      await _engine.load(_main!, pip: _pip);
      await _sendOverlay();
      setState(() => _ready = true);
      _sw
        ..reset()
        ..start();
      _statsTimer?.cancel();
      _statsTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        try {
          final s = await _engine.stats();
          if (mounted) setState(() => _stats = s);
        } catch (_) {}
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  /// Text layer drawn by Flutter (Lao shaping is correct here), sent as PNG.
  Future<void> _sendOverlay() async {
    if (!_text) {
      await _engine.setOverlay(null);
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final box = _overlayKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (box == null) return;
    final img = await box.toImage(pixelRatio: _engine.width / box.size.width);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    await _engine.setOverlay(bytes?.buffer.asUint8List());
  }

  Widget _overlayLayer() => RepaintBoundary(
        key: _overlayKey,
        child: SizedBox(
          width: 270,
          height: 480,
          child: Stack(
            children: [
              Positioned(
                left: 14,
                right: 14,
                bottom: 70,
                child: Text(
                  'ມື້ນີ້ພາມາຊີມກາເຟສົດ — ທົດສອບຊັບລາວ',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                top: 40,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Color(0xFFF5B100), borderRadius: BorderRadius.all(Radius.circular(8))),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text('ກາເຟດີ ຢູ່ວຽງຈັນ',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _stat(String label, Object? v, {bool? good}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))),
            Text('$v',
                style: TextStyle(
                    color: good == null ? AppColors.textPrimary : (good ? AppColors.success : AppColors.accent),
                    fontFamily: 'monospace',
                    fontSize: 12)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final fps = (_stats['renderFps'] as num?)?.toDouble() ?? 0;
    final vfps = (_stats['videoFps'] as num?)?.toDouble() ?? 0;
    final slow = (_stats['slowFrames'] as num?)?.toInt() ?? 0;
    final total = (_stats['totalFrames'] as num?)?.toInt() ?? 0;
    final seek = (_stats['seekLatencyMs'] as num?)?.toDouble() ?? -1;
    final slowPct = total == 0 ? 0.0 : slow * 100 / total;
    final minutes = _sw.elapsed.inSeconds / 60;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Engine test (phase P)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Off-screen source for the overlay texture.
          Offstage(offstage: true, child: _overlayLayer()),
          if (!_ready) ...[
            ListTile(
              title: Text(_main ?? 'Main video', style: const TextStyle(color: AppColors.textPrimary)),
              trailing: const Icon(Icons.folder_open, color: AppColors.textSecondary),
              onTap: () async {
                final p = await _pick();
                if (p != null) setState(() => _main = p);
              },
            ),
            ListTile(
              title: Text(_pip ?? 'PiP video (optional)', style: const TextStyle(color: AppColors.textPrimary)),
              trailing: const Icon(Icons.folder_open, color: AppColors.textSecondary),
              onTap: () async {
                final p = await _pick();
                if (p != null) setState(() => _pip = p);
              },
            ),
            SwitchListTile(
              value: _text,
              title: const Text('Text layer', style: TextStyle(color: AppColors.textPrimary)),
              onChanged: (v) => setState(() => _text = v),
            ),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1080, label: Text('1080p')),
                ButtonSegment(value: 720, label: Text('720p')),
              ],
              selected: {_res},
              onSelectionChanged: (s) => setState(() => _res = s.first),
            ),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _main == null ? null : _start, child: const Text('Start')),
          ],
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.accent)),
          if (_ready && _engine.textureId != null) ...[
            AspectRatio(
              aspectRatio: _engine.width / _engine.height,
              child: Texture(textureId: _engine.textureId!),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(_playing ? Icons.pause : Icons.play_arrow, color: AppColors.textPrimary),
                  onPressed: () async {
                    _playing ? await _engine.pause() : await _engine.play();
                    setState(() => _playing = !_playing);
                  },
                ),
                Expanded(
                  child: Slider(
                    value: _scrub,
                    onChanged: (v) {
                      setState(() => _scrub = v);
                      _engine.seek((v * 30000).round());
                    },
                  ),
                ),
              ],
            ),
            _stat('Render fps (GO ≥ 30)', fps.toStringAsFixed(1), good: fps >= 30),
            _stat('Video frames/s', vfps.toStringAsFixed(1)),
            _stat('Slow frames (GO ≤ 2%)', '${slowPct.toStringAsFixed(1)}%  ($slow/$total)',
                good: slowPct <= 2),
            _stat('Seek latency (GO ≤ 100 ms)', seek < 0 ? '—' : '${seek.toStringAsFixed(0)} ms',
                good: seek < 0 ? null : seek <= 100),
            _stat('GL draw: last / max', '${_stats['lastDrawMs'] ?? '-'} / ${_stats['maxDrawMs'] ?? '-'} ms'),
            _stat('Running (GO: 10 min, no crash)', '${minutes.toStringAsFixed(1)} min', good: minutes >= 10),
            _stat('Output', '${_engine.width}×${_engine.height}  PiP: ${_pip != null}  Text: $_text'),
          ],
        ],
      ),
    );
  }
}
