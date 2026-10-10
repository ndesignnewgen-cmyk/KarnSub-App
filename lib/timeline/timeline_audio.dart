import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'timeline_model.dart';

/// PCM format of a WAV file.
class WavInfo {
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int dataOffset; // byte offset of the PCM data
  final int dataLength; // bytes of PCM data

  const WavInfo(this.sampleRate, this.channels, this.bitsPerSample, this.dataOffset,
      this.dataLength);

  int get blockAlign => channels * bitsPerSample ~/ 8;

  /// Byte offset (within the data) of [ms], aligned to a whole frame.
  int byteAt(int ms) => (ms * sampleRate ~/ 1000) * blockAlign;

  int get durationMs => dataLength ~/ blockAlign * 1000 ~/ sampleRate;

  /// Parse a RIFF/WAVE header (walks the chunks, so extra chunks are fine).
  static WavInfo parse(Uint8List b) {
    final d = ByteData.sublistView(b);
    String tag(int o) => String.fromCharCodes(b.sublist(o, o + 4));
    if (b.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
      throw const FormatException('not a WAV file');
    }
    int? rate, ch, bits;
    var o = 12;
    while (o + 8 <= b.length) {
      final id = tag(o);
      final size = d.getUint32(o + 4, Endian.little);
      if (id == 'fmt ') {
        ch = d.getUint16(o + 10, Endian.little);
        rate = d.getUint32(o + 12, Endian.little);
        bits = d.getUint16(o + 22, Endian.little);
      } else if (id == 'data') {
        if (rate == null || ch == null || bits == null) break;
        return WavInfo(rate, ch, bits, o + 8, size);
      }
      o += 8 + size + (size.isOdd ? 1 : 0);
    }
    throw const FormatException('WAV header incomplete');
  }

  static Uint8List header(int sampleRate, int channels, int bits, int dataBytes) {
    final h = ByteData(44);
    void s(int o, String t) {
      for (var i = 0; i < 4; i++) {
        h.setUint8(o + i, t.codeUnitAt(i));
      }
    }

    final align = channels * bits ~/ 8;
    s(0, 'RIFF');
    h.setUint32(4, 36 + dataBytes, Endian.little);
    s(8, 'WAVE');
    s(12, 'fmt ');
    h.setUint32(16, 16, Endian.little);
    h.setUint16(20, 1, Endian.little);
    h.setUint16(22, channels, Endian.little);
    h.setUint32(24, sampleRate, Endian.little);
    h.setUint32(28, sampleRate * align, Endian.little);
    h.setUint16(32, align, Endian.little);
    h.setUint16(34, bits, Endian.little);
    s(36, 'data');
    h.setUint32(40, dataBytes, Endian.little);
    return h.buffer.asUint8List();
  }
}

/// Renders the audio of the EDITED main track (clips in timeline order, each
/// cut to its in/out points) into one WAV, so AI transcription produces
/// subtitles that line up with the edited video, not the original files.
///
/// [extract] decodes a media file's audio to a WAV (the native `extractAudio`
/// in the app; a fake in tests). Each source file is decoded only once.
class TimelineAudioRenderer {
  final Future<void> Function(String mediaPath, String wavOut) extract;
  TimelineAudioRenderer(this.extract);

  /// Writes [outPath]; returns the rendered length in ms, or null when the
  /// timeline has no main-track clips. Muted clips become silence; a source
  /// without an audio track is silence too.
  Future<int?> render(ProjectTimeline t, String outPath, String workDir,
      {void Function(double progress)? onProgress}) async {
    final clips = t.mainTrack?.elements.whereType<VideoElement>().toList() ?? const [];
    if (clips.isEmpty) return null;
    await Directory(workDir).create(recursive: true);

    // Decode each distinct source once.
    final decoded = <String, (File, WavInfo)?>{};
    final sources = clips.map((c) => c.src).toSet().toList();
    for (var i = 0; i < sources.length; i++) {
      final src = sources[i];
      final wav = File('$workDir/src_$i.wav');
      try {
        await extract(src, wav.path);
        final raf = await wav.open();
        final head = await raf.read(4096);
        await raf.close();
        decoded[src] = (wav, WavInfo.parse(head));
      } catch (_) {
        decoded[src] = null; // no audio track / unreadable → silence
      }
      onProgress?.call((i + 1) / (sources.length + 1));
    }

    // Output format = the first decodable source (extractAudio always
    // resamples to one format, so in practice all match).
    final fmt = decoded.values.whereType<(File, WavInfo)>().firstOrNull?.$2 ??
        const WavInfo(16000, 1, 16, 44, 0);

    final out = await File(outPath).open(mode: FileMode.write);
    try {
      await out.writeFrom(WavInfo.header(fmt.sampleRate, fmt.channels, fmt.bitsPerSample, 0));
      var written = 0;
      for (final c in clips) {
        final want = fmt.byteAt(c.durationMs);
        final dec = decoded[c.src];
        var copied = 0;
        if (dec != null && !c.muted && _sameFormat(dec.$2, fmt)) {
          final (file, info) = dec;
          final start = math.min(info.byteAt(c.trimInMs), info.dataLength);
          final len = math.min(want, info.dataLength - start);
          if (len > 0) {
            final raf = await file.open();
            try {
              await raf.setPosition(info.dataOffset + start);
              var left = len;
              while (left > 0) {
                final chunk = await raf.read(math.min(left, 1 << 20));
                if (chunk.isEmpty) break;
                await out.writeFrom(chunk);
                left -= chunk.length;
                copied += chunk.length;
              }
            } finally {
              await raf.close();
            }
          }
        }
        // Pad (silence) up to the clip's timeline length.
        var pad = want - copied;
        while (pad > 0) {
          final n = math.min(pad, 1 << 16);
          await out.writeFrom(Uint8List(n));
          pad -= n;
        }
        written += want;
      }
      // Patch the sizes.
      await out.setPosition(0);
      await out.writeFrom(
          WavInfo.header(fmt.sampleRate, fmt.channels, fmt.bitsPerSample, written));
      onProgress?.call(1);
      return written ~/ fmt.blockAlign * 1000 ~/ fmt.sampleRate;
    } finally {
      await out.close();
      for (final d in decoded.values) {
        try {
          await d?.$1.delete();
        } catch (_) {}
      }
    }
  }

  static bool _sameFormat(WavInfo a, WavInfo b) =>
      a.sampleRate == b.sampleRate && a.channels == b.channels && a.bitsPerSample == b.bitsPerSample;
}
