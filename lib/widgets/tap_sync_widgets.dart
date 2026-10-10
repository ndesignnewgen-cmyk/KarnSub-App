import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../i18n/i18n.dart';
import '../services/audio_sync_service.dart';
import '../services/tap_sync_calibration.dart';
import '../services/tap_sync_session.dart';
import '../theme/app_theme.dart';

/// "07.32" style seconds with 2 decimals (minutes added past 60 s).
String fmtTapTime(int ms) {
  final neg = ms < 0;
  ms = ms.abs();
  final m = ms ~/ 60000;
  final s = (ms % 60000) / 1000.0;
  final ss = s.toStringAsFixed(2).padLeft(5, '0');
  return '${neg ? '-' : ''}${m > 0 ? '$m:' : ''}$ss';
}

/// Scrolling waveform with the playhead in the middle and tapped spans drawn
/// on top. [nowMs] drives repaints without rebuilding the screen.
class TapWaveform extends StatelessWidget {
  final ValueListenable<int> nowMs;
  final List<double> samples;
  final List<TapLine> lines;
  final int? activeStartMs; // in-progress span start (hold / tap mode)
  final int windowMs;
  final double height;

  const TapWaveform({
    super.key,
    required this.nowMs,
    required this.samples,
    required this.lines,
    this.activeStartMs,
    this.windowMs = 6000,
    this.height = 72,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ValueListenableBuilder<int>(
          valueListenable: nowMs,
          builder: (_, now, _) => CustomPaint(
            painter: _WavePainter(
              now: now,
              samples: samples,
              lines: lines,
              activeStart: activeStartMs,
              windowMs: windowMs,
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final int now;
  final List<double> samples;
  final List<TapLine> lines;
  final int? activeStart;
  final int windowMs;

  _WavePainter({
    required this.now,
    required this.samples,
    required this.lines,
    required this.activeStart,
    required this.windowMs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final from = now - windowMs ~/ 2;
    double x(int ms) => (ms - from) / windowMs * w;

    // Tapped spans (behind the bars).
    final done = Paint()..color = AppColors.primary.withValues(alpha: 0.28);
    final doneEdge = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final l in lines) {
      if (!l.hasTiming) continue;
      final a = x(l.effStartMs!), b = x(l.effEndMs!);
      if (b < 0 || a > w) continue;
      final r = RRect.fromRectAndRadius(
          Rect.fromLTRB(a, 6, b, h - 6), const Radius.circular(6));
      canvas.drawRRect(r, done);
      canvas.drawRRect(r, doneEdge);
    }
    if (activeStart != null) {
      final a = x(activeStart!), b = w / 2;
      final r = RRect.fromRectAndRadius(
          Rect.fromLTRB(a, 6, b, h - 6), const Radius.circular(6));
      canvas.drawRRect(
          r, Paint()..color = AppColors.success.withValues(alpha: 0.25));
      canvas.drawRRect(
          r,
          Paint()
            ..color = AppColors.success
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }

    // Waveform bars.
    const step = AudioSyncService.waveformStepMs;
    final bar = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: 0.55)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final barPx = 4.0;
    final msPerBar = (barPx / w * windowMs).round().clamp(step, 1000);
    for (int t = (from ~/ msPerBar) * msPerBar; t < from + windowMs; t += msPerBar) {
      if (t < 0) continue;
      final i = t ~/ step;
      double v = 0;
      if (samples.isNotEmpty && i < samples.length) {
        final j2 = math.min(samples.length, i + msPerBar ~/ step);
        for (int j = i; j < j2; j++) {
          v = math.max(v, samples[j]);
        }
      }
      final bh = math.max(2.0, v * (h - 16));
      final px = x(t);
      canvas.drawLine(
          Offset(px, h / 2 - bh / 2), Offset(px, h / 2 + bh / 2), bar);
    }

    // Playhead.
    canvas.drawLine(
      Offset(w / 2, 0),
      Offset(w / 2, h),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_WavePainter o) =>
      o.now != now ||
      o.activeStart != activeStart ||
      !identical(o.samples, samples) ||
      o.lines != lines;
}

/// Static waveform around one line for the review screen: dashed = where the
/// user pressed (after the reaction offset), solid box = final (snapped) time.
class TapLineWaveform extends StatelessWidget {
  final List<double> samples;
  final int fromMs;
  final int toMs;
  final int startMs;
  final int endMs;
  final int? pressedStartMs;
  final int? pressedEndMs;
  final ValueListenable<int> nowMs;

  const TapLineWaveform({
    super.key,
    required this.samples,
    required this.fromMs,
    required this.toMs,
    required this.startMs,
    required this.endMs,
    required this.nowMs,
    this.pressedStartMs,
    this.pressedEndMs,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: 64,
        width: double.infinity,
        child: ValueListenableBuilder<int>(
          valueListenable: nowMs,
          builder: (_, now, _) => CustomPaint(
            painter: _LineWavePainter(this, now),
          ),
        ),
      ),
    );
  }
}

class _LineWavePainter extends CustomPainter {
  final TapLineWaveform c;
  final int now;
  _LineWavePainter(this.c, this.now);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final span = math.max(1, c.toMs - c.fromMs);
    double x(int ms) => (ms - c.fromMs) / span * w;
    const step = AudioSyncService.waveformStepMs;
    final bar = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final msPerBar = math.max(step, (4.0 / w * span).round());
    for (int t = c.fromMs; t < c.toMs; t += msPerBar) {
      final i = t ~/ step;
      final v = (i >= 0 && i < c.samples.length) ? c.samples[i] : 0.0;
      final bh = math.max(2.0, v * (h - 12));
      canvas.drawLine(Offset(x(t), h / 2 - bh / 2),
          Offset(x(t), h / 2 + bh / 2), bar);
    }
    final box = Rect.fromLTRB(x(c.startMs), 4, x(c.endMs), h - 4);
    canvas.drawRect(
        box, Paint()..color = AppColors.primary.withValues(alpha: 0.22));
    canvas.drawRect(
        box,
        Paint()
          ..color = AppColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    void dashed(int? ms) {
      if (ms == null) return;
      final px = x(ms);
      final p = Paint()
        ..color = Colors.white70
        ..strokeWidth = 1.5;
      for (double y = 0; y < h; y += 6) {
        canvas.drawLine(Offset(px, y), Offset(px, math.min(h, y + 3)), p);
      }
    }

    dashed(c.pressedStartMs);
    dashed(c.pressedEndMs);
    if (now >= c.fromMs && now <= c.toMs) {
      canvas.drawLine(Offset(x(now), 0), Offset(x(now), h),
          Paint()
            ..color = AppColors.warning
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_LineWavePainter o) => true;
}

/// Half-screen round button for the thumb. Reports raw pointer down/up so
/// hold mode can measure press AND release.
class TapBigButton extends StatelessWidget {
  final bool active;
  final Color color;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final double size;

  const TapBigButton({
    super.key,
    required this.active,
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onDown,
    required this.onUp,
    this.size = 190,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onDown(),
      onPointerUp: (_) => onUp(),
      onPointerCancel: (_) => onUp(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? color : color.withValues(alpha: 0.85),
          border: Border.all(
            color: color.withValues(alpha: active ? 0.45 : 0.18),
            width: active ? 14 : 10,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: active ? 0.55 : 0.25),
              blurRadius: active ? 36 : 18,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.black87, size: 34),
            const SizedBox(height: 6),
            Text(title,
                style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 17,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small round icon button with a caption under it.
class TapSideButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const TapSideButton(
      {super.key, required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    // The whole thing (circle + label) is one touch target.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.surfaceLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  color: enabled ? AppColors.textPrimary : AppColors.textHint),
            ),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color:
                        enabled ? AppColors.textSecondary : AppColors.textHint,
                    fontSize: 11,
                    height: 1.2)),
          ],
        ),
      ),
    );
  }
}

/// "ປັບຕາມມື" — 10-second test: tap on every tick, get your offset.
/// Returns the measured offset (ms, ≤ 0) or null when cancelled/failed.
Future<int?> showTapCalibration(BuildContext context) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    isDismissible: false,
    enableDrag: false,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => const _CalibrationSheet(),
  );
}

class _CalibrationSheet extends StatefulWidget {
  const _CalibrationSheet();
  @override
  State<_CalibrationSheet> createState() => _CalibrationSheetState();
}

class _CalibrationSheetState extends State<_CalibrationSheet> {
  VideoPlayerController? _vc;
  final _taps = <int>[];
  final _sw = Stopwatch()..start();
  int _anchorPos = 0;
  int _anchorSw = 0;
  Timer? _poll;
  bool _running = false;
  bool _finished = false;
  int? _result;
  bool _pressed = false;

  @override
  void dispose() {
    _poll?.cancel();
    _vc?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _taps.clear();
      _finished = false;
      _result = null;
      _running = true;
    });
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/tap_calibration.wav');
    if (!await f.exists()) {
      await f.writeAsBytes(TapSyncCalibration.buildClickWav(), flush: true);
    }
    await _vc?.dispose();
    final vc = VideoPlayerController.file(f);
    await vc.initialize();
    _vc = vc;
    await vc.play();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 100), (_) async {
      final t0 = _sw.elapsedMilliseconds;
      final p = (await vc.position)?.inMilliseconds ?? 0;
      final t1 = _sw.elapsedMilliseconds;
      _anchorPos = p;
      _anchorSw = (t0 + t1) ~/ 2;
      if (p >= TapSyncCalibration.totalMs - 300 ||
          !vc.value.isPlaying && p > 1000) {
        _finish();
      }
    });
  }

  void _finish() {
    if (_finished) return;
    _poll?.cancel();
    _vc?.pause();
    setState(() {
      _running = false;
      _finished = true;
      _result = TapSyncCalibration.estimateOffset(_taps);
    });
  }

  void _onTap() {
    if (!_running) return;
    final now = _sw.elapsedMilliseconds;
    _taps.add(_anchorPos + (now - _anchorSw));
    HapticFeedback.lightImpact();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final total = TapSyncCalibration.clickTimesMs.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('tap.calib.title'),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              _finished
                  ? (_result == null
                      ? tr('tap.calib.fail')
                      : tr('tap.calib.result', {'ms': _result!}))
                  : tr('tap.calib.body', {'n': total}),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 20),
            Listener(
              onPointerDown: (_) {
                setState(() => _pressed = true);
                _onTap();
              },
              onPointerUp: (_) => setState(() => _pressed = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _running
                      ? (_pressed ? AppColors.warning : AppColors.primary)
                      : AppColors.surfaceLight,
                ),
                alignment: Alignment.center,
                child: Text(
                  _running
                      ? '${_taps.length} / $total'
                      : tr('tap.calib.tapHere'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _poll?.cancel();
                      _vc?.pause();
                      Navigator.pop(context);
                    },
                    child: Text(tr('common.cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _running
                        ? null
                        : (_finished && _result != null)
                            ? () => Navigator.pop(context, _result)
                            : _start,
                    child: Text(_finished && _result != null
                        ? tr('tap.calib.use')
                        : (_finished
                            ? tr('tap.calib.retry')
                            : tr('tap.calib.start'))),
                  ),
                ),
              ],
            ),
            if (_finished && _result != null)
              TextButton(
                onPressed: _start,
                child: Text(tr('tap.calib.retry'),
                    style: const TextStyle(color: AppColors.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }
}
