import 'dart:io';
import 'dart:typed_data';

/// Lightweight audio clean-up applied ONLY to the copy sent to the speech
/// recognizer (never to the exported audio). Improves recognition on quiet or
/// rumbly recordings:
///   1. 1-pole high-pass (~75 Hz) — removes DC offset, mic rumble, AC hum base.
///   2. Peak normalization to ~-1 dBFS, with a capped gain so we lift quiet
///      voices without exploding background noise.
///
/// Operates on 16-bit PCM WAV. Returns the input unchanged on any problem.
class AudioPreprocess {
  static const _targetPeak = 0.97; // of full scale
  static const _maxGain = 8.0; // don't amplify silence/noise more than this
  static const _highPassHz = 75.0;

  /// Process a 16-bit PCM WAV byte buffer in place (returns new bytes).
  static Uint8List processBytes(Uint8List wav) {
    try {
      if (wav.length <= 44) return wav;
      int le16(int o) => wav[o] | (wav[o + 1] << 8);
      int le32(int o) =>
          wav[o] | (wav[o + 1] << 8) | (wav[o + 2] << 16) | (wav[o + 3] << 24);
      final channels = le16(22).clamp(1, 2);
      final sampleRate = le32(24).clamp(8000, 48000);
      final bits = le16(34);
      if (bits != 16) return wav; // only handle 16-bit PCM

      final out = Uint8List.fromList(wav); // copy (keep header)
      final bd = ByteData.sublistView(out);
      final n = (out.length - 44) ~/ 2; // sample count (incl. channels)
      if (n < 4) return wav;

      // 1-pole high-pass coefficient.
      final rc = 1.0 / (2 * 3.141592653589793 * _highPassHz);
      final dt = 1.0 / sampleRate;
      final alpha = rc / (rc + dt);

      // Filter per channel (interleaved). Track peak for normalization.
      final prevX = List<double>.filled(channels, 0);
      final prevY = List<double>.filled(channels, 0);
      final filtered = Float64List(n);
      double peak = 1.0;
      for (int i = 0; i < n; i++) {
        final ch = i % channels;
        final x = bd.getInt16(44 + i * 2, Endian.little).toDouble();
        final y = alpha * (prevY[ch] + x - prevX[ch]);
        prevX[ch] = x;
        prevY[ch] = y;
        filtered[i] = y;
        final a = y.abs();
        if (a > peak) peak = a;
      }

      // Peak normalization with capped gain.
      double gain = (_targetPeak * 32767.0) / peak;
      if (gain > _maxGain) gain = _maxGain;
      if (gain < 1.0) {
        // Already loud / would clip — only attenuate to avoid clipping.
        gain = (_targetPeak * 32767.0) / peak;
      }

      for (int i = 0; i < n; i++) {
        var v = (filtered[i] * gain).round();
        if (v > 32767) v = 32767;
        if (v < -32768) v = -32768;
        bd.setInt16(44 + i * 2, v, Endian.little);
      }
      return out;
    } catch (_) {
      return wav;
    }
  }

  /// Read a WAV file, clean it up, and overwrite it in place. Best-effort.
  static Future<void> processFile(String path) async {
    try {
      final f = File(path);
      if (!f.existsSync()) return;
      final bytes = await f.readAsBytes();
      final out = processBytes(bytes);
      if (!identical(out, bytes)) await f.writeAsBytes(out, flush: true);
    } catch (_) {
      // leave the file untouched
    }
  }
}
