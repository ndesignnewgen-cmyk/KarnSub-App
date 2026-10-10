import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_app/timeline/timeline_audio.dart';
import 'package:subtitle_app/timeline/timeline_model.dart';

late Directory tmp;

/// A WAV whose every 16-bit sample equals the millisecond it belongs to
/// (rate 1000 Hz, mono) — so we can read back exactly which ms was copied.
Uint8List rampWav(int ms, {int rate = 1000}) {
  final pcm = ByteData(ms * rate ~/ 1000 * 2);
  for (var i = 0; i < pcm.lengthInBytes ~/ 2; i++) {
    pcm.setInt16(i * 2, (i * 1000 ~/ rate) % 30000, Endian.little);
  }
  return Uint8List.fromList([
    ...WavInfo.header(rate, 1, 16, pcm.lengthInBytes),
    ...pcm.buffer.asUint8List(),
  ]);
}

List<int> samples(String path) {
  final b = File(path).readAsBytesSync();
  final info = WavInfo.parse(b);
  final d = ByteData.sublistView(b, info.dataOffset, info.dataOffset + info.dataLength);
  return [for (var i = 0; i < info.dataLength ~/ 2; i++) d.getInt16(i * 2, Endian.little)];
}

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('karnsub_audio_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('WAV header round-trips and skips extra chunks', () {
    final h = WavInfo.header(44100, 1, 16, 1000);
    final info = WavInfo.parse(Uint8List.fromList([...h, ...Uint8List(1000)]));
    expect((info.sampleRate, info.channels, info.bitsPerSample, info.dataOffset, info.dataLength),
        (44100, 1, 16, 44, 1000));
    // Insert a LIST chunk between fmt and data.
    final withList = BytesBuilder()
      ..add(h.sublist(0, 36))
      ..add('LIST'.codeUnits)
      ..add([4, 0, 0, 0, 1, 2, 3, 4])
      ..add(h.sublist(36))
      ..add(Uint8List(1000));
    expect(WavInfo.parse(withList.toBytes()).dataOffset, 56);
    expect(() => WavInfo.parse(Uint8List(20)), throwsFormatException);
  });

  test('renders clips in timeline order, cut to their in/out points', () async {
    final a = File('${tmp.path}/a.wav')..writeAsBytesSync(rampWav(5000));
    final b = File('${tmp.path}/b.wav')..writeAsBytesSync(rampWav(5000));
    final extracted = <String>[];
    final r = TimelineAudioRenderer((src, out) async {
      extracted.add(src);
      await File(src).copy(out); // our "media" already is a WAV
    });
    const t = ProjectTimeline(tracks: [
      Track(id: 'main', kind: TrackKind.mainVideo, elements: [
        VideoElement(id: '1', startMs: 0, durationMs: 1000, src: 'B', trimInMs: 2000),
        VideoElement(id: '2', startMs: 1000, durationMs: 500, src: 'A', trimInMs: 100),
        VideoElement(id: '3', startMs: 1500, durationMs: 300, src: 'B', trimInMs: 0),
      ]),
    ]);
    // Map the logical sources to files.
    final r2 = TimelineAudioRenderer((src, out) => r.extract(src == 'A' ? a.path : b.path, out));
    final ms = await r2.render(t, '${tmp.path}/out.wav', '${tmp.path}/work');
    expect(ms, 1800);
    final s = samples('${tmp.path}/out.wav');
    expect(s.length, 1800);
    expect(s[0], 2000); // clip 1 starts at B's 2000 ms
    expect(s[999], 2999);
    expect(s[1000], 100); // clip 2 = A from 100 ms
    expect(s[1499], 599);
    expect(s[1500], 0); // clip 3 = B from 0
    expect(extracted.length, 2); // each source decoded once
  });

  test('muted clips, missing audio and short sources become silence', () async {
    final a = File('${tmp.path}/a.wav')..writeAsBytesSync(rampWav(1000));
    final r = TimelineAudioRenderer((src, out) async {
      if (src == 'noaudio') throw Exception('NO_AUDIO');
      await a.copy(out);
    });
    const t = ProjectTimeline(tracks: [
      Track(id: 'main', kind: TrackKind.mainVideo, elements: [
        VideoElement(id: '1', startMs: 0, durationMs: 200, src: 'A', muted: true),
        VideoElement(id: '2', startMs: 200, durationMs: 200, src: 'noaudio'),
        VideoElement(id: '3', startMs: 400, durationMs: 400, src: 'A', trimInMs: 800),
      ]),
    ]);
    final ms = await r.render(t, '${tmp.path}/out.wav', '${tmp.path}/work');
    expect(ms, 800);
    final s = samples('${tmp.path}/out.wav');
    expect(s.sublist(0, 400).every((x) => x == 0), isTrue);
    expect(s[400], 800); // the last 200 ms of A …
    expect(s[599], 999);
    expect(s.sublist(600).every((x) => x == 0), isTrue); // … then padded
  });

  test('no main track → nothing rendered', () async {
    final r = TimelineAudioRenderer((_, _) async {});
    expect(await r.render(const ProjectTimeline(), '${tmp.path}/o.wav', '${tmp.path}/w'), isNull);
  });
}
