import 'dart:math' as math;
import 'dart:typed_data';

/// "ປັບຕາມມື" — measures how late this person (on this phone + headphones)
/// presses after hearing a sound, so Tap Sync can subtract it.
///
/// The test plays a short WAV of clicks at IRREGULAR intervals (so the user
/// reacts instead of anticipating a rhythm) and the user taps on each click.
/// Tap times are read from the same player clock as real Tap Sync, so player
/// start-up latency cancels out and only output latency + reaction remain.
class TapSyncCalibration {
  TapSyncCalibration._();

  static const int sampleRate = 44100;

  /// Click times (ms) inside the calibration WAV: 1.2 s lead-in, then 8 clicks
  /// 0.8–1.5 s apart.
  static const List<int> clickTimesMs = [
    1200, 2300, 3100, 4500, 5400, 6300, 7700, 8600,
  ];
  static const int totalMs = 10000;

  /// Default when the user never calibrated.
  static const int defaultOffsetMs = -180;

  /// Mono 16-bit PCM WAV with a short 1.5 kHz "tick" at every [clicks] time.
  static Uint8List buildClickWav({
    List<int> clicks = clickTimesMs,
    int durationMs = totalMs,
    int rate = sampleRate,
  }) {
    final n = rate * durationMs ~/ 1000;
    final pcm = Int16List(n);
    final clickLen = rate * 40 ~/ 1000; // 40 ms
    for (final c in clicks) {
      final at = rate * c ~/ 1000;
      for (int i = 0; i < clickLen && at + i < n; i++) {
        final t = i / rate;
        final env = math.exp(-i / (clickLen / 5)); // sharp attack, fast decay
        pcm[at + i] = (math.sin(2 * math.pi * 1500 * t) * env * 26000).round();
      }
    }
    final dataBytes = n * 2;
    final b = ByteData(44 + dataBytes);
    void str(int off, String s) {
      for (int i = 0; i < s.length; i++) {
        b.setUint8(off + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    b.setUint32(4, 36 + dataBytes, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    b.setUint32(16, 16, Endian.little); // PCM chunk size
    b.setUint16(20, 1, Endian.little); // PCM
    b.setUint16(22, 1, Endian.little); // mono
    b.setUint32(24, rate, Endian.little);
    b.setUint32(28, rate * 2, Endian.little); // byte rate
    b.setUint16(32, 2, Endian.little); // block align
    b.setUint16(34, 16, Endian.little); // bits
    str(36, 'data');
    b.setUint32(40, dataBytes, Endian.little);
    for (int i = 0; i < n; i++) {
      b.setInt16(44 + i * 2, pcm[i], Endian.little);
    }
    return b.buffer.asUint8List();
  }

  /// Offset (ms, ≤ 0) from the user's taps, or null when there are too few
  /// usable taps (fewer than 5 matched within −100…+700 ms of a click).
  /// Uses the median, so one early or very late tap doesn't skew it.
  static int? estimateOffset(
    List<int> tapTimesMs, {
    List<int> clicks = clickTimesMs,
    int minMatches = 5,
  }) {
    final delays = <int>[];
    final used = <int>{};
    for (final t in tapTimesMs) {
      int? best;
      for (int i = 0; i < clicks.length; i++) {
        if (used.contains(i)) continue;
        final d = t - clicks[i];
        if (d < -100 || d > 700) continue;
        if (best == null || d.abs() < (t - clicks[best]).abs()) best = i;
      }
      if (best != null) {
        used.add(best);
        delays.add(t - clicks[best]);
      }
    }
    if (delays.length < minMatches) return null;
    delays.sort();
    final m = delays.length;
    final median = m.isOdd
        ? delays[m ~/ 2]
        : ((delays[m ~/ 2 - 1] + delays[m ~/ 2]) / 2).round();
    return -median.clamp(0, 600);
  }
}
