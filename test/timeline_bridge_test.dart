import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_app/models/subtitle_style_model.dart';
import 'package:subtitle_app/timeline/migrate_v1.dart';
import 'package:subtitle_app/timeline/project_v1.dart';
import 'package:subtitle_app/timeline/timeline_model.dart';
import 'package:subtitle_app/timeline/timeline_ops.dart';

late Directory tmp;
String file(String name) {
  final f = File('${tmp.path}/$name')..writeAsStringSync('x');
  return f.path;
}

String Function() ids() {
  var n = 0;
  return () => 'id${n++}';
}

const d = Duration.new;

/// A v1 project using everything the bridge must carry.
SubtitleProject richV1({List<List<int>> removed = const []}) {
  final video = file('main.mp4');
  return SubtitleProject(
    id: 'p1',
    name: 'Rich',
    videoPath: video,
    videoDuration: d(milliseconds: 10000),
    selectedStyle: subtitlePresets.first,
    fontSize: 21,
    isKaraokeHighlight: true,
    removedRanges: removed.map((r) => List.of(r)).toList(),
    segments: [
      SubtitleSegment(id: 's1', text: 'ສະບາຍດີ', startTime: d(milliseconds: 500),
          endTime: d(milliseconds: 1500), words: ['ສະບາຍ', 'ດີ'],
          wordTimings: [d(milliseconds: 500), d(milliseconds: 1000)], emoji: '🔥'),
      SubtitleSegment(id: 's2', text: 'ທຸກຄົນ', startTime: d(milliseconds: 4000),
          endTime: d(milliseconds: 5000), karaoke: true),
    ],
    imageOverlays: [
      ImageOverlay(id: 'o1', path: file('a.png'), startTime: d(milliseconds: 4200),
          endTime: d(milliseconds: 6000), x: 0.3, scale: 0.4, keyframes: [
        OverlayKeyframe(timeMs: 4200, x: 0.3),
        OverlayKeyframe(timeMs: 5200, x: 0.7, easing: 2),
      ]),
    ],
    zoomEffects: [
      ZoomEffect(id: 'z1', startTime: d(milliseconds: 6000), endTime: d(milliseconds: 7000),
          toScale: 1.5),
    ],
    fadeEffects: [
      FadeEffect(id: 'f1', startTime: d(milliseconds: 9000), endTime: d(milliseconds: 10000)),
    ],
    sfxBlocks: [
      SfxBlock(id: 'x1', type: SfxType.whoosh, startTime: d(milliseconds: 4100), volume: 0.6),
    ],
    bgMusicPath: file('music.mp3'),
    bgMusicVolume: 0.35,
    aiVoicePath: file('voice.wav'),
    aiVoiceDurationMs: 3000,
    aiVoiceOffsetMs: 4000,
  );
}

List<(String, int, int)> subs(SubtitleProject p) =>
    [for (final s in p.segments) (s.id, s.startTime.inMilliseconds, s.endTime.inMilliseconds)];

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('karnsub_bridge_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('no cuts: v1 → v2 → v1 gives the same project', () {
    final p = richV1();
    final back = projectToV1(migrateV1(p, newId: ids()).timeline);
    final q = back.project;
    expect(back.lossy, isEmpty);
    expect(q.videoPath, p.videoPath);
    expect(q.clips, isEmpty);
    expect(q.removedRanges, isEmpty);
    expect(subs(q), subs(p));
    final s1 = q.segments.first;
    expect(s1.words, ['ສະບາຍ', 'ດີ']);
    expect(s1.wordTimings!.map((w) => w.inMilliseconds), [500, 1000]);
    expect(s1.emoji, '🔥');
    expect(q.segments[1].karaoke, isTrue);
    final o = q.imageOverlays.single;
    expect((o.startTime.inMilliseconds, o.x, o.scale), (4200, 0.3, 0.4));
    expect(o.keyframes.map((k) => (k.timeMs, k.x, k.easing)), [(4200, 0.3, 0), (5200, 0.7, 2)]);
    expect(q.zoomEffects.single.toScale, 1.5);
    expect(q.fadeEffects.single.startTime.inMilliseconds, 9000);
    final sfx = q.sfxBlocks.single;
    expect((sfx.type, sfx.startTime.inMilliseconds, sfx.volume), (SfxType.whoosh, 4100, 0.6));
    expect((q.bgMusicPath, q.bgMusicVolume), (p.bgMusicPath, 0.35));
    expect((q.aiVoicePath, q.aiVoiceOffsetMs), (p.aiVoicePath, 4000));
    expect(q.fontSize, 21);
    expect(q.isKaraokeHighlight, isTrue);
    expect(q.name, 'Rich');
  });

  test('with a cut: v1 multi-clip on the cut timeline, same as v2', () {
    final p = richV1(removed: [[2000, 3000]]);
    final t = migrateV1(p, newId: ids()).timeline;
    final q = projectToV1(t).project;
    expect(q.clips.map((c) => (c.trimStartMs, c.trimEndMs)), [(0, 2000), (3000, 10000)]);
    expect(subs(q), [('s1', 500, 1500), ('s2', 3000, 4000)]);
    expect(q.imageOverlays.single.keyframes.map((k) => k.timeMs), [3200, 4200]);
    // And back again: the same timeline.
    final t2 = migrateV1(q, newId: ids()).timeline;
    List<(int, int)> spans(ProjectTimeline x) =>
        [for (final e in x.mainTrack!.elements) (e.startMs, e.endMs)];
    expect(spans(t2), spans(t));
    List<(String, int, int)> tsubs(ProjectTimeline x) => [
          for (final e in x.tracksOf(TrackKind.subtitle).expand((tr) => tr.elements))
            (e.id, e.startMs, e.endMs),
        ];
    expect(tsubs(t2), tsubs(t));
  });

  test('single trimmed clip → videoPath + removed head, times shifted back', () {
    final p = richV1();
    var t = migrateV1(p, newId: ids()).timeline;
    final mainId = t.mainTrack!.elements.single.id;
    // Trim 1 s off the front (subtitles keep their place in the picture).
    t = TimelineOps.trimElement(t, mainId, newStartMs: 1000);
    t = t.withTrack(t.mainTrack!); // already packed to 0
    final q = projectToV1(t).project;
    expect(q.clips, isEmpty);
    expect(q.removedRanges, [[0, 1000]]);
    expect(q.videoDuration!.inMilliseconds, 10000);
  });

  test('features v1 cannot show are reported, not silently dropped', () {
    final p = richV1();
    var t = migrateV1(p, newId: ids()).timeline;
    t = TimelineOps.addTrack(t, const Track(id: 'tx', kind: TrackKind.text));
    t = TimelineOps.addElement(t, 'tx',
        const TextElement(id: 'txt', startMs: 0, durationMs: 1000, text: 'ໂປຣ'));
    final main = t.mainTrack!.elements.single as VideoElement;
    t = TimelineOps.updateElement(t, main.copyWith(speedSpec: const SpeedSpec(constant: 2)));
    final r = projectToV1(t);
    expect(r.lossy, containsAll(['text', 'speed']));
    expect(r.project.segments.length, 2); // everything else still there
  });

  test('hidden tracks are left out of the v1 preview', () {
    var t = migrateV1(richV1(), newId: ids()).timeline;
    final subTrack = t.tracksOf(TrackKind.subtitle).single.id;
    t = TimelineOps.updateTrack(t, subTrack, hidden: true);
    expect(projectToV1(t).project.segments, isEmpty);
  });
}
