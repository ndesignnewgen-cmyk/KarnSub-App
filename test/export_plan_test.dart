import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_app/models/subtitle_style_model.dart';
import 'package:subtitle_app/timeline/export_plan.dart';
import 'package:subtitle_app/timeline/migrate_v1.dart';
import 'package:subtitle_app/timeline/project_v1.dart';
import 'package:subtitle_app/timeline/timeline_model.dart';
import 'package:subtitle_app/timeline/timeline_ops.dart';

late Directory tmp;
String file(String n) => (File('${tmp.path}/$n')..writeAsStringSync('x')).path;

ProjectTimeline mainOnly(List<VideoElement> els, {List<Track> extra = const []}) =>
    ProjectTimeline(tracks: [
      Track(id: 'main', kind: TrackKind.mainVideo, elements: TimelineOps.pack(els)),
      ...extra,
    ]);

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('karnsub_plan_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('one source, pieces in order → file + removed ranges, no merge', () {
    final t = mainOnly(const [
      VideoElement(id: 'a', startMs: 0, durationMs: 2000, src: 'v', trimInMs: 1000, sourceMs: 10000),
      VideoElement(id: 'b', startMs: 0, durationMs: 3000, src: 'v', trimInMs: 5000, sourceMs: 10000),
    ]);
    final p = ExportPlan.of(t, const {})!;
    expect(p.needsMerge, isFalse);
    expect(p.videoPath, 'v');
    expect(p.removed, [[0, 1000], [3000, 5000], [8000, 10000]]);
    expect(p.originalMs, 10000);
    expect(p.toOriginal(0), 1000);
    expect(p.toOriginal(1999), 2999);
    expect(p.toOriginal(2000), 5000); // a time on the cut starts the next piece
    expect(p.toOriginalEnd(2000), 3000); // … but ends the previous one
    expect(p.toOriginal(4500), 7500);
  });

  test('re-ordered pieces of one file → merge (one entry per piece)', () {
    final t = mainOnly(const [
      VideoElement(id: 'a', startMs: 0, durationMs: 1000, src: 'v', trimInMs: 5000, sourceMs: 8000),
      VideoElement(id: 'b', startMs: 0, durationMs: 1000, src: 'v', trimInMs: 0, sourceMs: 8000),
    ]);
    final p = ExportPlan.of(t, const {})!;
    expect(p.needsMerge, isTrue);
    expect(p.mergePaths, ['v', 'v']);
    expect(p.removed, [[0, 5000], [6000, 8000], [9000, 16000]]);
    expect(p.toOriginal(0), 5000);
    expect(p.toOriginal(1000), 8000); // second copy of the file starts at 8000
    expect(p.originalMs, 16000);
  });

  test('several files → merged offsets use each file length (probe wins)', () {
    final t = mainOnly(const [
      VideoElement(id: 'a', startMs: 0, durationMs: 2000, src: 'x', sourceMs: 4000),
      VideoElement(id: 'b', startMs: 0, durationMs: 1000, src: 'y', trimInMs: 500),
    ]);
    final p = ExportPlan.of(t, const {'y': 3000})!;
    expect(p.mergePaths, ['x', 'y']);
    expect(p.removed, [[2000, 4000], [4000, 4500], [5500, 7000]]);
    expect(p.toOriginal(2500), 5000);
  });

  test('cut one video → save layout → re-migrate = the same edit', () {
    final v = file('v.mp4');
    final p1 = SubtitleProject(
      id: 'p',
      name: 'n',
      videoPath: v,
      videoDuration: const Duration(seconds: 10),
      selectedStyle: subtitlePresets.first,
      removedRanges: [[2000, 3000]],
      segments: [
        SubtitleSegment(id: 's1', text: 'a', startTime: const Duration(milliseconds: 500),
            endTime: const Duration(milliseconds: 1500)),
        SubtitleSegment(id: 's2', text: 'b', startTime: const Duration(milliseconds: 4000),
            endTime: const Duration(milliseconds: 5000),
            wordTimings: const [Duration(milliseconds: 4000), Duration(milliseconds: 4600)]),
      ],
    );
    var t = migrateV1(p1).timeline;
    // Another cut in the Pro Editor: trim 1 s off the end of the first piece.
    final first = t.mainTrack!.elements.first;
    final before = t;
    t = TimelineOps.trimElement(t, first.id, newEndMs: 1700);
    t = TimelineOps.relink(before, t); // what the editor does after main edits
    final plan = ExportPlan.of(t, const {})!;
    expect(plan.needsMerge, isFalse);
    final q = projectToV1(t, plan: plan).project;
    expect(q.clips, isEmpty);
    expect(q.videoPath, v);
    expect(q.removedRanges, [[1700, 3000]]);
    // Subtitles are back on the file's own clock.
    expect(q.segments.map((s) => (s.startTime.inMilliseconds, s.endTime.inMilliseconds)),
        [(500, 1500), (4000, 5000)]);
    expect(q.segments[1].wordTimings!.map((d) => d.inMilliseconds), [4000, 4600]);
    // Re-migrating that v1 gives the same cut timeline.
    final t2 = migrateV1(q).timeline;
    List<(int, int)> spans(ProjectTimeline x) =>
        [for (final e in x.mainTrack!.elements) (e.startMs, e.endMs)];
    expect(spans(t2), spans(t));
    List<(String, int, int)> subs(ProjectTimeline x) => [
          for (final e in x.tracksOf(TrackKind.subtitle).expand((tr) => tr.elements))
            (e.id, e.startMs, e.endMs),
        ];
    expect(subs(t2), subs(t));
  });

  test('transitions become fade / zoom / shake effects; others are reported', () {
    final v = file('v.mp4');
    var t = mainOnly([
      VideoElement(id: 'a', startMs: 0, durationMs: 2000, src: v, sourceMs: 6000),
      VideoElement(id: 'b', startMs: 0, durationMs: 2000, src: v, trimInMs: 2000, sourceMs: 6000),
      VideoElement(id: 'c', startMs: 0, durationMs: 2000, src: v, trimInMs: 4000, sourceMs: 6000),
    ]);
    t = TimelineOps.setTransition(t, 'a', 'b', 'fade', 600);
    t = TimelineOps.setTransition(t, 'b', 'c', 'zoom', 400);
    final q = projectToV1(t, plan: ExportPlan.of(t, const {})).project;
    expect(q.fadeEffects.map((f) => (f.startTime.inMilliseconds, f.endTime.inMilliseconds, f.toBlack)),
        [(1700, 2000, true), (2000, 2300, false)]);
    expect(q.zoomEffects.map((z) => (z.startTime.inMilliseconds, z.toScale)),
        [(3800, 1.35), (4000, 1.0)]);
    final t2 = TimelineOps.setTransition(t, 'a', 'b', 'flash', 400);
    expect(projectToV1(t2).lossy, contains('transitions'));
  });

  test('rendered text / shape / masked image export as image overlays', () {
    final v = file('v.mp4');
    final png = file('text.png');
    final mpng = file('masked.png');
    final img = file('photo.png');
    final t = mainOnly([
      VideoElement(id: 'a', startMs: 0, durationMs: 5000, src: v, sourceMs: 5000),
    ], extra: [
      const Track(id: 'tx', kind: TrackKind.text, elements: [
        TextElement(id: 'txt', startMs: 1000, durationMs: 2000, text: 'ໂປຣ 1 ແຖມ 1',
            transform: ElementTransform(x: 0.5, y: 0.2, scale: 0.6),
            keyframes: [Keyframe(0, ElementTransform(scale: 0.6), easing: 6)]),
      ]),
      Track(id: 'st', kind: TrackKind.sticker, elements: [
        ImageElement(id: 'm', startMs: 0, durationMs: 1000, src: img,
            mask: const MaskSpec(shape: 'heart')),
      ]),
    ]);
    final noRender = projectToV1(t, plan: ExportPlan.of(t, const {}));
    expect(noRender.lossy, containsAll(['text', 'maskBlend']));
    final r = projectToV1(t, plan: ExportPlan.of(t, const {}), rendered: {'txt': png, 'm': mpng});
    expect(r.lossy, isEmpty);
    final byPath = {for (final o in r.project.imageOverlays) o.path: o};
    expect(byPath[png]!.y, 0.2);
    expect(byPath[png]!.keyframes.single.easing, 3); // bezier → closest exporter easing
    expect(byPath.containsKey(mpng), isTrue);
  });
}
