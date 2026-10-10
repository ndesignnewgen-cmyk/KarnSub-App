part of '../editor_screen.dart';


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
