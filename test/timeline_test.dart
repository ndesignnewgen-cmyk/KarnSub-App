import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_app/models/subtitle_style_model.dart';
import 'package:subtitle_app/timeline/migrate_v1.dart';
import 'package:subtitle_app/timeline/time_map.dart';
import 'package:subtitle_app/timeline/timeline_model.dart';
import 'package:subtitle_app/timeline/timeline_ops.dart';

const d = Duration.new;

SubtitleSegment seg(String id, int a, int b, {List<int>? words}) => SubtitleSegment(
      id: id,
      text: 'ສະບາຍດີ $id',
      startTime: d(milliseconds: a),
      endTime: d(milliseconds: b),
      words: words == null ? null : [for (var i = 0; i < words.length; i++) 'w$i'],
      wordTimings: words?.map((w) => d(milliseconds: w)).toList(),
    );

SubtitleProject v1({
  int durationMs = 10000,
  List<List<int>> removed = const [],
  List<int> splits = const [],
  List<SubtitleSegment>? segments,
  List<ImageOverlay>? overlays,
  List<SfxBlock>? sfx,
  List<VideoClip>? clips,
}) =>
    SubtitleProject(
      id: 'p',
      name: 'test',
      videoPath: '/v/main.mp4',
      videoDuration: d(milliseconds: durationMs),
      selectedStyle: subtitlePresets.first,
      removedRanges: removed.map((r) => List.of(r)).toList(),
      splitPointsMs: List.of(splits),
      segments: segments,
      imageOverlays: overlays,
      sfxBlocks: sfx,
      clips: clips,
    );

/// Deterministic ids for split pieces.
String Function() ids() {
  var n = 0;
  return () => 'id${n++}';
}

List<(int, int)> spans(Track t) => [for (final e in t.elements) (e.startMs, e.endMs)];

void main() {
  group('model', () {
    test('every element type round-trips through JSON', () {
      final tl = ProjectTimeline(
        canvas: const CanvasSpec(width: 1080, height: 1350, fps: 60, background: 'blur'),
        bookmarksMs: const [1200],
        settings: const {'language': 'lo'},
        transitions: const [Transition(fromId: 'v1', toId: 'v2', kind: 'dissolve', durationMs: 300)],
        tracks: [
          const Track(id: 'main', kind: TrackKind.mainVideo, volume: 0.5, elements: [
            VideoElement(id: 'v1', startMs: 0, durationMs: 2000, src: 'a.mp4', trimInMs: 500,
                speedSpec: SpeedSpec(constant: 2, curve: [[0, 1], [1, 3]], keepPitch: false),
                reversed: true, blend: LayerBlend.screen,
                mask: MaskSpec(shape: 'heart', feather: 0.3, inverted: true)),
            VideoElement(id: 'v2', startMs: 2000, durationMs: 1000, src: 'b.mp4'),
          ]),
          Track(id: 'st', kind: TrackKind.sticker, hidden: true, elements: [
            ImageElement(id: 'i', startMs: 100, durationMs: 900, src: 'x.gif', animated: true,
                keyframes: const [
                  Keyframe(0, ElementTransform(x: 0.1)),
                  Keyframe(500, ElementTransform(x: 0.9), easing: 6, bezier: [0.4, 0, 0.6, 1]),
                ]),
          ]),
          const Track(id: 'tx', kind: TrackKind.text, elements: [
            TextElement(id: 't', startMs: 0, durationMs: 500, text: 'ໂປຣ 1 ແຖມ 1',
                style: {'font': 'NotoSansLao', 'color': 0xFFFF0000}),
          ]),
          const Track(id: 'sh', kind: TrackKind.shape, elements: [
            ShapeElement(id: 's', startMs: 0, durationMs: 500, shape: 'star',
                strokeWidth: 2, strokeColor: 0xFF000000),
          ]),
          const Track(id: 'sub', kind: TrackKind.subtitle, elements: [
            SubtitleElement(id: 'u', startMs: 0, durationMs: 800, text: 'ສະບາຍດີ',
                wordStartsMs: [0, 400], data: {'karaoke': true}),
          ]),
          const Track(id: 'fx', kind: TrackKind.effect, elements: [
            EffectElement(id: 'z', startMs: 0, durationMs: 800, effect: 'zoom',
                params: {'toScale': 1.3}),
          ]),
          const Track(id: 'mu', kind: TrackKind.music, duck: true, muted: true, elements: [
            AudioElement(id: 'a', startMs: 0, durationMs: 3000, src: 'm.mp3', loop: true,
                volume: 0.4, trimInMs: 1000, speed: 1.5, label: 'music'),
          ]),
        ],
      );
      final json = jsonEncode(tl.toJson());
      final back = ProjectTimeline.fromJson(jsonDecode(json));
      expect(jsonEncode(back.toJson()), json);
      expect(back.durationMs, 3000);
      expect(back.mainTrack!.elements.length, 2);
      final v = back.find('v1')!.$2 as VideoElement;
      expect(v.speed, 2);
      expect(v.trimOutMs, 500 + 4000);
      expect(v.mask!.shape, 'heart');
    });

    test('wrong schema version is rejected', () {
      expect(() => ProjectTimeline.fromJson({'schemaVersion': 1, 'tracks': []}),
          throwsFormatException);
    });

    test('transformAt interpolates with easing', () {
      const kfs = [
        Keyframe(0, ElementTransform(x: 0, scale: 1)),
        Keyframe(1000, ElementTransform(x: 1, scale: 2)),
      ];
      expect(transformAt(const ElementTransform(), kfs, -5).x, 0);
      expect(transformAt(const ElementTransform(), kfs, 500).x, closeTo(0.5, 1e-9));
      expect(transformAt(const ElementTransform(), kfs, 500).scale, closeTo(1.5, 1e-9));
      expect(transformAt(const ElementTransform(), kfs, 2000).x, 1);
      const eased = [
        Keyframe(0, ElementTransform(x: 0), easing: 1),
        Keyframe(1000, ElementTransform(x: 1)),
      ];
      expect(transformAt(const ElementTransform(), eased, 500).x, closeTo(0.25, 1e-9));
      expect(transformAt(const ElementTransform(x: 0.3), const [], 10).x, 0.3);
    });

    test('cubic bezier behaves like CSS', () {
      expect(cubicBezier(0, 0, 1, 1, 0.5), closeTo(0.5, 1e-6)); // linear
      expect(cubicBezier(0.42, 0, 0.58, 1, 0.5), closeTo(0.5, 1e-3)); // ease-in-out
      expect(cubicBezier(0.42, 0, 1, 1, 0.25), lessThan(0.25)); // ease-in starts slow
      expect(applyEasing(6, 1, [0.4, 0, 0.6, 1]), closeTo(1, 1e-6));
    });
  });

  group('TimeMap', () {
    test('identity', () {
      final m = TimeMap.identity(5000);
      expect(m.map(1234), 1234);
      expect(m.durationMs, 5000);
    });

    test('times after a cut shift left; times inside are removed', () {
      final m = TimeMap.fromRemoved([[2000, 3000]], 10000);
      expect(m.durationMs, 9000);
      expect(m.map(1000), 1000);
      expect(m.map(2500), isNull);
      expect(m.map(4000), 3000);
      expect(m.mapClamp(2500), 2000);
      expect(m.mapRange(1500, 3500), (1500, 2500)); // spans the cut → shorter
      expect(m.mapRange(2100, 2900), isNull); // wholly inside the cut
    });

    test('overlapping, unsorted and out-of-range cuts', () {
      final m = TimeMap.fromRemoved([[8000, 12000], [1000, 2000], [1500, 2500], [-5, 100]], 10000);
      expect(m.kept, [(100, 1000), (2500, 8000)]);
      expect(m.durationMs, 900 + 5500);
      expect(m.map(2500), 900);
      expect(m.mapClamp(9000), m.durationMs);
      expect(m.map(8000), m.durationMs); // the very end
    });
  });

  group('migrateV1', () {
    test('simple project: one main clip, subtitles unchanged', () {
      final r = migrateV1(v1(segments: [seg('a', 1000, 2000, words: [1000, 1500])]), newId: ids());
      final t = r.timeline;
      expect(r.droppedCount, 0);
      final main = t.mainTrack!;
      expect(main.elements.single.durationMs, 10000);
      expect((main.elements.single as VideoElement).src, '/v/main.mp4');
      final sub = t.tracksOf(TrackKind.subtitle).single.elements.single as SubtitleElement;
      expect((sub.startMs, sub.endMs), (1000, 2000));
      expect(sub.wordStartsMs, [0, 500]); // relative to the line
      expect(sub.data['text'], 'ສະບາຍດີ a');
      expect(t.canvas.height, 1920);
    });

    test('cuts become separate main clips and everything after moves left', () {
      final r = migrateV1(
        v1(
          removed: [[2000, 3000]],
          segments: [
            seg('before', 500, 1500),
            seg('inside', 2200, 2800),
            seg('across', 1800, 3500),
            seg('after', 4000, 5000, words: [4000, 4500]),
          ],
        ),
        newId: ids(),
      );
      final t = r.timeline;
      final main = t.mainTrack!;
      expect(spans(main), [(0, 2000), (2000, 9000)]);
      expect((main.elements[1] as VideoElement).trimInMs, 3000); // source resumes after the cut
      final subs = {
        for (final e in t.tracksOf(TrackKind.subtitle).expand((x) => x.elements))
          e.id: (e.startMs, e.endMs),
      };
      expect(subs['before'], (500, 1500));
      expect(subs['across'], (1800, 2500));
      expect(subs['after'], (3000, 4000));
      expect(subs.containsKey('inside'), isFalse);
      expect(r.droppedCount, 1);
      final droppedSeg = (t.settings['v1Dropped'] as List).single as Map;
      expect(droppedSeg['kind'], 'subtitle');
      expect((droppedSeg['segment'] as Map)['text'], 'ສະບາຍດີ inside'); // recoverable
    });

    test('split points divide the main clip without removing anything', () {
      final t = migrateV1(v1(splits: [3000, 7000]), newId: ids()).timeline;
      expect(spans(t.mainTrack!), [(0, 3000), (3000, 7000), (7000, 10000)]);
      expect(t.mainTrack!.elements.map((e) => (e as VideoElement).trimInMs), [0, 3000, 7000]);
    });

    test('multi-clip: each clip keeps its own source and trim', () {
      final t = migrateV1(
        v1(clips: [
          VideoClip(id: 'c1', path: '/v/a.mp4', trimStartMs: 1000, trimEndMs: 4000, durationMs: 9000),
          VideoClip(id: 'c2', path: '/v/b.mp4', durationMs: 2000),
        ], segments: [seg('s', 3500, 4500)]),
        newId: ids(),
      ).timeline;
      final els = t.mainTrack!.elements.cast<VideoElement>();
      expect(els.map((e) => (e.src, e.trimInMs, e.startMs, e.durationMs)).toList(), [
        ('/v/a.mp4', 1000, 0, 3000),
        ('/v/b.mp4', 0, 3000, 2000),
      ]);
      final s = t.tracksOf(TrackKind.subtitle).single.elements.single;
      expect((s.startMs, s.endMs), (3500, 4500)); // global time is kept
    });

    test('overlapping overlays go on separate lanes; keyframes become relative', () {
      final t = migrateV1(
        v1(overlays: [
          ImageOverlay(id: 'o1', path: '/i/a.png', startTime: d(milliseconds: 1000),
              endTime: d(milliseconds: 3000), x: 0.2, keyframes: [
            OverlayKeyframe(timeMs: 1000, x: 0.2),
            OverlayKeyframe(timeMs: 2000, x: 0.8, easing: 3),
          ]),
          ImageOverlay(id: 'o2', path: '/i/b.gif', startTime: d(milliseconds: 2000),
              endTime: d(milliseconds: 4000)),
          ImageOverlay(id: 'o3', path: '/v/broll.mp4', isVideo: true, cover: true,
              startTime: d(milliseconds: 5000), endTime: d(milliseconds: 6000)),
        ]),
        newId: ids(),
      ).timeline;
      final stickers = t.tracksOf(TrackKind.sticker);
      expect(stickers.length, 2);
      final o1 = t.find('o1')!.$2 as ImageElement;
      expect(o1.keyframes.map((k) => k.timeMs), [0, 1000]);
      expect(o1.keyframes[1].easing, 3);
      expect(o1.transform.x, 0.2);
      expect((t.find('o2')!.$2 as ImageElement).animated, isTrue);
      final broll = t.tracksOf(TrackKind.video).single.elements.single as VideoElement;
      expect(broll.cover, isTrue);
      expect(broll.muted, isTrue);
    });

    test('effects, SFX (default length), AI voice and music', () {
      final p = v1(
        removed: [[0, 1000]],
        sfx: [
          SfxBlock(id: 'pop', type: SfxType.pop, startTime: d(milliseconds: 2000), volume: 0.7),
          SfxBlock(id: 'pop2', type: SfxType.pop, startTime: d(milliseconds: 2100)),
          SfxBlock(id: 'own', type: SfxType.ding, startTime: d(milliseconds: 5000),
              duration: d(milliseconds: 400), isCustom: true, customPath: '/a/own.wav',
              customName: 'mine', trimStart: d(milliseconds: 100)),
        ],
      )
        ..zoomEffects.add(ZoomEffect(id: 'z', startTime: d(milliseconds: 1500),
            endTime: d(milliseconds: 2500), keyframes: [
          ZoomKeyframe(timeMs: 1500, scale: 1),
          ZoomKeyframe(timeMs: 2500, scale: 1.4),
        ]))
        ..fadeEffects.add(FadeEffect(id: 'f', startTime: d(milliseconds: 9000),
            endTime: d(milliseconds: 10000), toBlack: true))
        ..shakeEffects.add(ShakeEffect(id: 'k', startTime: d(milliseconds: 200),
            endTime: d(milliseconds: 800)))
        ..aiVoicePath = '/a/voice.wav'
        ..aiVoiceDurationMs = 6000
        ..aiVoiceOffsetMs = 1000
        ..aiVoiceSpeed = 1.5
        ..aiVoiceVolume = 0.9
        ..bgMusicPath = '/a/music.mp3'
        ..bgMusicVolume = 0.3
        ..bgMusicDuck = true
        ..sfxVolume = 0.8;
      final r = migrateV1(p, newId: ids());
      final t = r.timeline;

      final z = t.find('z')!.$2 as EffectElement;
      expect((z.startMs, z.endMs), (500, 1500));
      expect((z.params['keyframes'] as List).map((k) => k['timeMs']), [0, 1000]);
      expect((t.find('f')!.$2 as EffectElement).params['toBlack'], isTrue);
      expect(t.find('k'), isNull); // inside the removed first second
      expect(r.droppedCount, 1);

      final pop = t.find('pop')!;
      expect(pop.$1.kind, TrackKind.sfx);
      expect(pop.$1.volume, 0.8);
      expect((pop.$2 as AudioElement).src, 'sfx:pop');
      expect(pop.$2.durationMs, SfxType.pop.defaultDuration.inMilliseconds);
      expect(t.find('pop2')!.$1.id, isNot(pop.$1.id)); // overlapping → second lane
      final own = t.find('own')!.$2 as AudioElement;
      expect((own.src, own.trimInMs, own.label, own.durationMs), ('/a/own.wav', 100, 'mine', 400));

      final voice = t.tracksOf(TrackKind.voice).single;
      expect(voice.volume, 0.9);
      final v = voice.elements.single as AudioElement;
      expect((v.startMs, v.durationMs, v.speed), (0, 4000, 1.5));

      final music = t.tracksOf(TrackKind.music).single;
      expect((music.volume, music.duck), (0.3, true));
      expect(music.elements.single.durationMs, t.mainTrack!.endMs);
    });

    test('settings keep project options but not structure', () {
      final p = v1()
        ..fontSize = 22
        ..isAutoCut = true
        ..bgBlur = true;
      final t = migrateV1(p, newId: ids()).timeline;
      expect(t.settings['fontSize'], 22);
      expect(t.settings['isAutoCut'], isTrue);
      expect(t.settings.containsKey('segments'), isFalse);
      expect(t.settings.keys.where((k) => k.startsWith('aiVoice')), isEmpty);
      expect(t.canvas.background, 'blur');
    });

    test('migration output round-trips through JSON', () {
      final t = migrateV1(
        v1(removed: [[2000, 3000]], segments: [seg('a', 100, 900)], splits: [5000]),
        newId: ids(),
      ).timeline;
      final json = jsonEncode(t.toJson());
      expect(jsonEncode(ProjectTimeline.fromJson(jsonDecode(json)).toJson()), json);
    });

    test('no video at all → no main track, nothing crashes', () {
      final p = SubtitleProject(id: 'x', name: 'x', selectedStyle: subtitlePresets.first,
          segments: [seg('a', 0, 1000)]);
      final t = migrateV1(p, newId: ids()).timeline;
      expect(t.mainTrack, isNull);
      expect(t.tracksOf(TrackKind.subtitle).single.elements.length, 1);
    });

    test('the v1 project is not modified', () {
      final p = v1(removed: [[0, 500]], segments: [seg('a', 1000, 2000)]);
      migrateV1(p, newId: ids());
      expect(p.segments.single.startTime.inMilliseconds, 1000);
      expect(p.removedRanges, [[0, 500]]);
    });
  });

  group('TimelineOps', () {
    ProjectTimeline base() => const ProjectTimeline(tracks: [
          Track(id: 'main', kind: TrackKind.mainVideo, elements: [
            VideoElement(id: 'c1', startMs: 0, durationMs: 3000, src: 'a.mp4'),
            VideoElement(id: 'c2', startMs: 3000, durationMs: 2000, src: 'b.mp4', trimInMs: 1000),
            VideoElement(id: 'c3', startMs: 5000, durationMs: 1000, src: 'c.mp4'),
          ]),
          Track(id: 'sub', kind: TrackKind.subtitle, elements: [
            SubtitleElement(id: 's1', startMs: 0, durationMs: 1000, text: 'a'),
            SubtitleElement(id: 's2', startMs: 2000, durationMs: 1000, text: 'b'),
          ]),
          Track(id: 'st', kind: TrackKind.sticker),
          Track(id: 'sfx', kind: TrackKind.sfx),
        ]);

    test('main track stays packed when a clip is removed', () {
      final t = TimelineOps.removeElement(base(), 'c2');
      expect(spans(t.mainTrack!), [(0, 3000), (3000, 4000)]);
    });

    test('add clip to main track inserts between clips and packs', () {
      final t = TimelineOps.addElement(base(), 'main',
          const VideoElement(id: 'n', startMs: 3100, durationMs: 500, src: 'n.mp4'));
      expect(t.mainTrack!.elements.map((e) => e.id), ['c1', 'n', 'c2', 'c3']);
      expect(spans(t.mainTrack!).last, (5500, 6500));
    });

    test('overlap on a normal track is refused', () {
      expect(
          () => TimelineOps.addElement(base(), 'sub',
              const SubtitleElement(id: 'x', startMs: 500, durationMs: 1000, text: 'x')),
          throwsA(isA<TimelineEditError>().having((e) => e.code, 'code', 'overlap')));
    });

    test('element type must match the track kind', () {
      expect(
          () => TimelineOps.addElement(base(), 'sfx',
              const ImageElement(id: 'x', startMs: 0, durationMs: 500, src: 'i.png')),
          throwsA(isA<TimelineEditError>().having((e) => e.code, 'code', 'wrongTrack')));
    });

    test('duplicate ids are refused', () {
      expect(
          () => TimelineOps.addElement(base(), 'st',
              const ImageElement(id: 's1', startMs: 0, durationMs: 500, src: 'i.png')),
          throwsA(isA<TimelineEditError>()));
    });

    test('ripple delete on a normal track pulls later elements left', () {
      final t = TimelineOps.removeElement(base(), 's1', ripple: true);
      expect(spans(t.track('sub')!), [(1000, 2000)]);
    });

    test('move within a track, across tracks, and reorder main clips', () {
      var t = TimelineOps.moveElement(base(), 's2', 'sub', 4000);
      expect(spans(t.track('sub')!), [(0, 1000), (4000, 5000)]);
      t = TimelineOps.addTrack(t, const Track(id: 'sub2', kind: TrackKind.subtitle));
      t = TimelineOps.moveElement(t, 's2', 'sub2', 500);
      expect(t.find('s2')!.$1.id, 'sub2');
      // Drag c3 to the front of the main track.
      t = TimelineOps.moveElement(t, 'c3', 'main', 0);
      expect(t.mainTrack!.elements.map((e) => e.id), ['c3', 'c1', 'c2']);
      expect(spans(t.mainTrack!), [(0, 1000), (1000, 4000), (4000, 6000)]);
    });

    test('trimming the left edge advances the source in-point', () {
      var t = TimelineOps.trimElement(base(), 'c2', newStartMs: 3500);
      final c2 = t.find('c2')!.$2 as VideoElement;
      expect(c2.trimInMs, 1500);
      expect(c2.durationMs, 1500);
      expect(spans(t.mainTrack!), [(0, 3000), (3000, 4500), (4500, 5500)]); // packed
      expect(() => TimelineOps.trimElement(base(), 'c1', newStartMs: -100),
          throwsA(isA<TimelineEditError>()));
      t = TimelineOps.trimElement(base(), 's2', newEndMs: 2150);
      expect(() => TimelineOps.trimElement(t, 's2', newEndMs: 2020),
          throwsA(isA<TimelineEditError>().having((e) => e.code, 'code', 'tooShort')));
    });

    test('trim at 2× speed moves the in-point twice as far', () {
      const t0 = ProjectTimeline(tracks: [
        Track(id: 'main', kind: TrackKind.mainVideo, elements: [
          VideoElement(id: 'v', startMs: 0, durationMs: 4000, src: 'a',
              speedSpec: SpeedSpec(constant: 2)),
        ]),
      ]);
      final t = TimelineOps.trimElement(t0, 'v', newStartMs: 1000);
      expect((t.find('v')!.$2 as VideoElement).trimInMs, 2000);
    });

    test('split divides media, keyframes and transitions correctly', () {
      var t = TimelineOps.setTransition(base(), 'c1', 'c2', 'dissolve', 400);
      t = TimelineOps.updateElement(t, (t.find('c1')!.$2 as VideoElement).copyWith(keyframes: const [
        Keyframe(0, ElementTransform(scale: 1)),
        Keyframe(2500, ElementTransform(scale: 2)),
      ]));
      t = TimelineOps.splitElement(t, 'c1', 1000, 'c1b');
      final a = t.find('c1')!.$2 as VideoElement;
      final b = t.find('c1b')!.$2 as VideoElement;
      expect((a.startMs, a.durationMs, a.trimInMs), (0, 1000, 0));
      expect((b.startMs, b.durationMs, b.trimInMs), (1000, 2000, 1000));
      expect(a.keyframes.map((k) => k.timeMs), [0]);
      expect(b.keyframes.map((k) => k.timeMs), [1500]);
      expect(t.transitions.single.fromId, 'c1b');
      expect(t.mainTrack!.elements.map((e) => e.id), ['c1', 'c1b', 'c2', 'c3']);
    });

    test('split too close to an edge is refused; subtitles aren\'t split here', () {
      expect(() => TimelineOps.splitElement(base(), 'c1', 50, 'x'), throwsA(isA<TimelineEditError>()));
      expect(() => TimelineOps.splitElement(base(), 's1', 500, 'x'), throwsA(isA<TimelineEditError>()));
    });

    test('duplicate goes right after, or to another lane when blocked', () {
      var (t, track) = TimelineOps.duplicateElement(base(), 's1', 's1c');
      expect(track, 'sub');
      expect((t.find('s1c')!.$2.startMs), 1000);
      // s2 is followed by nothing → also right after.
      (t, track) = TimelineOps.duplicateElement(t, 's1', 's1d'); // 1000..2000 taken now
      expect(track, isNot('sub'));
      expect(t.find('s1d')!.$2.startMs, 0);
      (t, _) = TimelineOps.duplicateElement(t, 'c2', 'c2c');
      expect(t.mainTrack!.elements.map((e) => e.id), ['c1', 'c2', 'c2c', 'c3']);
    });

    test('locked tracks refuse edits until unlocked', () {
      var t = TimelineOps.updateTrack(base(), 'sub', locked: true);
      expect(() => TimelineOps.removeElement(t, 's1'),
          throwsA(isA<TimelineEditError>().having((e) => e.code, 'code', 'locked')));
      t = TimelineOps.updateTrack(t, 'sub', locked: false);
      expect(TimelineOps.removeElement(t, 's1').find('s1'), isNull);
    });

    test('tracks: one main track only; it can\'t be removed', () {
      expect(() => TimelineOps.addTrack(base(), const Track(id: 'm2', kind: TrackKind.mainVideo)),
          throwsA(isA<TimelineEditError>()));
      expect(() => TimelineOps.removeTrack(base(), 'main'), throwsA(isA<TimelineEditError>()));
      final t = TimelineOps.removeTrack(base(), 'sub');
      expect(t.track('sub'), isNull);
    });

    test('transitions only between adjacent main clips, capped at half a clip', () {
      final t = TimelineOps.setTransition(base(), 'c2', 'c3', 'slideLeft', 5000);
      expect(t.transitions.single.durationMs, 500); // half of the 1 s clip
      expect(() => TimelineOps.setTransition(base(), 'c1', 'c3', 'x', 300),
          throwsA(isA<TimelineEditError>()));
      expect(TimelineOps.removeElement(t, 'c3').transitions, isEmpty);
    });

    test('snap points and snapping', () {
      final pts = TimelineOps.snapPoints(base(), excludeId: 's1', extra: [4200]);
      expect(pts, containsAll([0, 3000, 5000, 6000, 2000, 4200]));
      expect(pts.contains(1000), isFalse); // only s1 ends at 1000, and it's excluded
      expect(TimelineOps.snap(2960, pts, 80), 3000);
      expect(TimelineOps.snap(2800, pts, 80), 2800);
    });

    test('elementsAt lists what is visible at a time', () {
      final t = TimelineOps.updateTrack(base(), 'sub', hidden: true);
      expect(base().elementsAt(500).map((e) => e.id), ['c1', 's1']);
      expect(t.elementsAt(500).map((e) => e.id), ['c1']);
    });
  });

  group('TimelineHistory', () {
    ProjectTimeline t0() => const ProjectTimeline(tracks: [
          Track(id: 'sub', kind: TrackKind.subtitle, elements: [
            SubtitleElement(id: 's1', startMs: 0, durationMs: 1000, text: 'a'),
          ]),
        ]);

    test('undo / redo', () {
      final h = TimelineHistory(t0());
      h.run('move', (t) => TimelineOps.moveElement(t, 's1', 'sub', 500));
      h.run('trim', (t) => TimelineOps.trimElement(t, 's1', newEndMs: 2000));
      expect(h.current.find('s1')!.$2.endMs, 2000);
      expect(h.undoLabel, 'trim');
      h.undo();
      expect(h.current.find('s1')!.$2.endMs, 1500);
      h.undo();
      expect(h.current.find('s1')!.$2.startMs, 0);
      expect(h.canUndo, isFalse);
      h.redo();
      h.redo();
      expect(h.current.find('s1')!.$2.endMs, 2000);
      expect(h.canRedo, isFalse);
    });

    test('a new edit clears redo', () {
      final h = TimelineHistory(t0());
      h.run('a', (t) => TimelineOps.moveElement(t, 's1', 'sub', 500));
      h.undo();
      h.run('b', (t) => TimelineOps.moveElement(t, 's1', 'sub', 900));
      expect(h.canRedo, isFalse);
    });

    test('a failed edit changes nothing', () {
      final h = TimelineHistory(t0());
      expect(() => h.run('bad', (t) => TimelineOps.removeElement(t, 'nope')),
          throwsA(isA<TimelineEditError>()));
      expect(h.canUndo, isFalse);
      expect(identical(h.current, h.current), isTrue);
    });

    test('batch = one undo step (e.g. a drag)', () {
      final h = TimelineHistory(t0());
      h.beginBatch('drag');
      for (final ms in [100, 200, 300, 400]) {
        h.run('move', (t) => TimelineOps.moveElement(t, 's1', 'sub', ms));
      }
      h.endBatch();
      expect(h.undoLabel, 'drag');
      h.undo();
      expect(h.current.find('s1')!.$2.startMs, 0);
      expect(h.canUndo, isFalse);
    });

    test('cancelled batch restores the start; empty batch adds nothing', () {
      final h = TimelineHistory(t0());
      h.beginBatch('x');
      h.run('move', (t) => TimelineOps.moveElement(t, 's1', 'sub', 700));
      h.cancelBatch();
      expect(h.current.find('s1')!.$2.startMs, 0);
      h.beginBatch('y');
      h.endBatch();
      expect(h.canUndo, isFalse);
    });

    test('history is capped', () {
      final h = TimelineHistory(t0(), limit: 5);
      for (var i = 1; i <= 10; i++) {
        h.run('m$i', (t) => TimelineOps.moveElement(t, 's1', 'sub', i * 100));
      }
      var n = 0;
      while (h.undo()) {
        n++;
      }
      expect(n, 5);
      expect(h.current.find('s1')!.$2.startMs, 500);
    });

    test('undo steps share unchanged elements (no deep copies)', () {
      const big = ProjectTimeline(tracks: [
        Track(id: 'sub', kind: TrackKind.subtitle, elements: [
          SubtitleElement(id: 's1', startMs: 0, durationMs: 1000, text: 'a'),
        ]),
        Track(id: 'st', kind: TrackKind.sticker, elements: [
          ImageElement(id: 'i', startMs: 0, durationMs: 1000, src: 'x.png'),
        ]),
      ]);
      final h = TimelineHistory(big);
      final before = h.current.track('st')!;
      h.run('move', (t) => TimelineOps.moveElement(t, 's1', 'sub', 500));
      expect(identical(h.current.track('st'), before), isTrue);
    });
  });
}
