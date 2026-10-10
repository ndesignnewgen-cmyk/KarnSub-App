import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_app/models/subtitle_style_model.dart';
import 'package:subtitle_app/pro_editor/pro_editor_controller.dart';
import 'package:subtitle_app/timeline/timeline_model.dart';
import 'package:subtitle_app/timeline/v2_store.dart';

late Directory tmp;
String file(String n) => (File('${tmp.path}/$n')..writeAsStringSync('x')).path;

String Function() ids() {
  var n = 0;
  return () => 'n${n++}';
}

const d = Duration.new;

SubtitleProject project() => SubtitleProject(
      id: 'p1',
      name: 'Test',
      videoPath: file('v.mp4'),
      videoDuration: d(milliseconds: 10000),
      selectedStyle: subtitlePresets.first,
      segments: [
        SubtitleSegment(id: 's1', text: 'a', startTime: d(milliseconds: 1000), endTime: d(milliseconds: 2000)),
        SubtitleSegment(id: 's2', text: 'b', startTime: d(milliseconds: 4000), endTime: d(milliseconds: 5000)),
      ],
    );

String mainId(ProEditorController c) => c.timeline.mainTrack!.elements.first.id;

void main() {
  setUp(() => tmp = Directory.systemTemp.createTempSync('karnsub_pro_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('opens a v1 project as a multi-track timeline', () {
    final c = ProEditorController(project(), newId: ids());
    expect(c.timeline.mainTrack!.elements.length, 1);
    expect(c.timeline.tracksOf(TrackKind.subtitle).single.elements.length, 2);
    expect(c.durationMs, 10000);
  });

  test('split at playhead with nothing selected cuts the main clip', () {
    final c = ProEditorController(project(), newId: ids());
    c.seek(3000);
    expect(c.splitAtPlayhead(), isTrue);
    final main = c.timeline.mainTrack!.elements;
    expect(main.map((e) => (e.startMs, e.endMs)), [(0, 3000), (3000, 10000)]);
    expect(c.selected, {main[1].id}); // the right half is selected
    c.undo();
    expect(c.timeline.mainTrack!.elements.length, 1);
  });

  test('split outside any clip reports why', () {
    final c = ProEditorController(project(), newId: ids());
    c.seek(10000);
    expect(c.splitAtPlayhead(), isFalse);
    expect(c.lastError, 'nothingHere');
  });

  test('delete main clip packs the track; delete subtitle with ripple', () {
    final c = ProEditorController(project(), newId: ids());
    c.seek(3000);
    c.splitAtPlayhead();
    c.clearSelection();
    c.select(mainId(c));
    c.deleteSelected();
    expect(c.timeline.mainTrack!.elements.single.startMs, 0);
    expect(c.timeline.mainTrack!.elements.single.durationMs, 7000);

    // Subtitles follow their content: s1 was over the deleted clip → gone;
    // s2 (4.0–5.0 s of the video) moves up with the remaining clip.
    expect(c.timeline.find('s1'), isNull);
    final s2 = c.timeline.find('s2')!.$2;
    expect((s2.startMs, s2.endMs), (1000, 2000));

    // Ripple delete of a subtitle pulls the later ones left.
    final c2 = ProEditorController(project(), newId: ids());
    c2.ripple = true;
    c2.select('s1');
    c2.deleteSelected();
    expect(c2.timeline.find('s2')!.$2.startMs, 3000);
  });

  group('subtitles follow their clip', () {
    test('trimming a clip start shifts its subtitles with the content', () {
      final c = ProEditorController(project(), newId: ids());
      c.snapping = false;
      c.trimTo(mainId(c), leftEdge: true, ms: 1500); // cut the first 1.5 s
      expect(c.timeline.find('s1')!.$2.startMs, 0); // 1.0–2.0 s → partly cut
      expect(c.timeline.find('s1')!.$2.endMs, 500);
      expect(c.timeline.find('s2')!.$2.startMs, 2500); // 4.0 s → 2.5 s
    });

    test('content cut away mid-drag comes back when dragged back', () {
      final c = ProEditorController(project(), newId: ids());
      c.snapping = false;
      c.beginDrag('trim');
      c.trimTo(mainId(c), leftEdge: true, ms: 2500); // s1 fully cut away
      expect(c.timeline.find('s1'), isNull);
      c.trimTo(mainId(c), leftEdge: true, ms: 500); // drag back
      c.endDrag();
      final s1 = c.timeline.find('s1')!.$2;
      expect((s1.startMs, s1.endMs), (500, 1500));
      c.undo();
      expect(c.timeline.find('s1')!.$2.startMs, 1000); // one undo step
    });

    test('re-ordering clips takes their subtitles along', () {
      final c = ProEditorController(project(), newId: ids());
      c.seek(3000);
      c.splitAtPlayhead(); // [0–3 s][3–10 s]; s2 (4–5 s) is in the second
      final second = c.timeline.mainTrack!.elements[1].id;
      c.moveTo(second, 'main', 0); // second clip to the front
      final s2 = c.timeline.find('s2')!.$2;
      expect((s2.startMs, s2.endMs), (1000, 2000));
      final s1 = c.timeline.find('s1')!.$2;
      expect((s1.startMs, s1.endMs), (8000, 9000)); // first clip now starts at 7 s
    });

    test('stickers and music stay where they are (not linked)', () {
      final c = ProEditorController(project(), newId: ids());
      c.seek(4000);
      c.addOverlay(file('st.png'), 1000, isVideo: false);
      final st = c.primary!;
      c.clearSelection();
      c.snapping = false;
      c.trimTo(mainId(c), leftEdge: true, ms: 2000);
      expect(c.timeline.find(st)!.$2.startMs, 4000);
    });
  });

  test('trim snaps to the playhead and other edges', () {
    final c = ProEditorController(project(), newId: ids());
    c.pxPerSec = 100; // 10 px = 100 ms tolerance
    c.seek(2500);
    c.select('s1');
    c.beginDrag('trim');
    c.trimTo('s1', leftEdge: false, ms: 2460); // within 100 ms of the playhead
    c.trimTo('s1', leftEdge: false, ms: 2470);
    c.endDrag();
    expect(c.timeline.find('s1')!.$2.endMs, 2500);
    c.undo(); // the whole drag is one step
    expect(c.timeline.find('s1')!.$2.endMs, 2000);
    c.snapping = false;
    c.trimTo('s1', leftEdge: false, ms: 2460);
    expect(c.timeline.find('s1')!.$2.endMs, 2460);
  });

  test('move snaps the end to another element\'s start', () {
    final c = ProEditorController(project(), newId: ids());
    c.pxPerSec = 100;
    final sub = c.timeline.find('s1')!.$1.id;
    c.moveTo('s1', sub, 2950); // end would be 3950 → snaps to s2 start 4000
    expect((c.timeline.find('s1')!.$2.startMs, c.timeline.find('s1')!.$2.endMs), (3000, 4000));
  });

  test('refused move keeps the timeline and tells why', () {
    final c = ProEditorController(project(), newId: ids());
    c.snapping = false;
    final sub = c.timeline.find('s1')!.$1.id;
    expect(c.moveTo('s1', sub, 4200), isFalse);
    expect(c.lastError, 'overlap');
    expect(c.timeline.find('s1')!.$2.startMs, 1000);
  });

  test('duplicate, copy & paste at the playhead', () {
    final c = ProEditorController(project(), newId: ids());
    c.select('s2');
    c.duplicateSelected();
    final dup = c.timeline.find(c.primary!)!.$2;
    expect((dup.startMs, dup.endMs), (5000, 6000));

    c.select('s1');
    c.copySelected();
    c.seek(8000);
    expect(c.paste(), isTrue);
    final pasted = c.timeline.find(c.primary!)!.$2 as SubtitleElement;
    expect((pasted.startMs, pasted.text), (8000, 'a'));
    // Paste again at the same spot → goes to a second subtitle track.
    c.paste();
    expect(c.timeline.tracksOf(TrackKind.subtitle).length, 2);
  });

  test('multi-select delete is one undo step', () {
    final c = ProEditorController(project(), newId: ids());
    c.select('s1');
    c.select('s2', additive: true);
    c.deleteSelected();
    expect(c.timeline.tracksOf(TrackKind.subtitle).single.elements, isEmpty);
    c.undo();
    expect(c.timeline.tracksOf(TrackKind.subtitle).single.elements.length, 2);
  });

  test('locked track refuses edits', () {
    final c = ProEditorController(project(), newId: ids());
    final sub = c.timeline.find('s1')!.$1.id;
    c.setTrack(sub, locked: true);
    c.select('s1');
    expect(c.deleteSelected(), isFalse);
    expect(c.lastError, 'locked');
  });

  test('bookmarks toggle at the playhead', () {
    final c = ProEditorController(project(), newId: ids());
    c.seek(1234);
    c.toggleBookmark();
    expect(c.timeline.bookmarksMs, [1234]);
    c.seek(1240); // close enough → removes it
    c.toggleBookmark();
    expect(c.timeline.bookmarksMs, isEmpty);
  });

  test('add clip at the end, PiP overlays stack on free tracks', () {
    final c = ProEditorController(project(), newId: ids());
    c.addMainClip(file('b.mp4'), 3000);
    expect(c.timeline.mainTrack!.elements.last.startMs, 10000);
    expect(c.durationMs, 13000);
    c.seek(1000);
    c.addOverlay(file('p1.mp4'), 2000, isVideo: true);
    c.addOverlay(file('p2.mp4'), 2000, isVideo: true);
    expect(c.timeline.tracksOf(TrackKind.video).length, 2);
    expect(c.pipLayersAt(1500), 2);
    c.addOverlay(file('s.gif'), 2000, isVideo: false);
    expect((c.timeline.find(c.primary!)!.$2 as ImageElement).animated, isTrue);
  });

  test('volume on clips and sounds', () {
    final c = ProEditorController(project(), newId: ids());
    expect(c.setVolume(mainId(c), 0.4), isTrue);
    expect((c.timeline.mainTrack!.elements.first as VideoElement).volume, 0.4);
    expect(c.setVolume('s1', 0.4), isFalse); // subtitles have no sound
  });

  test('zoom is clamped', () {
    final c = ProEditorController(project(), newId: ids());
    c.zoom(1000);
    expect(c.pxPerSec, ProEditorController.maxPxPerSec);
    c.zoom(0.00001);
    expect(c.pxPerSec, ProEditorController.minPxPerSec);
  });

  test('save → reopen keeps v2-only content; classic edits rebuild it', () {
    final p = project();
    final c = ProEditorController(p, newId: ids());
    c.seek(3000);
    c.splitAtPlayhead();
    c.addOverlay(file('st.png'), 1500, isVideo: false);
    final saved = c.toProject();
    expect(saved.id, 'p1');
    expect(saved.name, 'Test');
    // One source → saved as the file + removed ranges (exportable as-is).
    expect(saved.clips, isEmpty);
    expect(saved.videoPath, isNotNull);
    expect(saved.removedRanges, isEmpty); // a split removes nothing
    expect(saved.timelineV2, isNotNull);
    expect(saved.timelineV2Base, v1Fingerprint(saved));

    final again = ProEditorController(saved, newId: ids());
    expect(again.timeline.mainTrack!.elements.length, 2);
    expect(again.timeline.tracksOf(TrackKind.sticker).single.elements.length, 1);

    // The classic editor moves a subtitle → fingerprint changes → rebuild.
    saved.segments.first.startTime = d(milliseconds: 1100);
    final rebuilt = timelineFor(saved, newId: ids());
    expect(rebuilt.find('s1')!.$2.startMs, 1100);
  });

  test('AI subtitles replace the old ones on one subtitle track (one undo)', () {
    final c = ProEditorController(project(), newId: ids());
    c.replaceSubtitles([
      SubtitleSegment(id: 'n2', text: 'ສອງ', startTime: d(milliseconds: 3000),
          endTime: d(milliseconds: 4000)),
      SubtitleSegment(id: 'n1', text: 'ໜຶ່ງ', startTime: d(milliseconds: 500),
          endTime: d(milliseconds: 2000), words: ['ໜຶ່ງ', 'x'],
          wordTimings: [d(milliseconds: 500), d(milliseconds: 1200)]),
      SubtitleSegment(id: 'overlap', text: 'ທັບ', startTime: d(milliseconds: 3500),
          endTime: d(milliseconds: 3800)),
    ]);
    final subs = c.timeline.tracksOf(TrackKind.subtitle);
    expect(subs.length, 1);
    final els = subs.single.elements.cast<SubtitleElement>();
    expect(els.map((e) => e.id), ['n1', 'n2']); // sorted; overlapping one dropped
    expect(els.first.wordStartsMs, [0, 700]);
    expect(c.timeline.find('s1'), isNull); // old subtitles gone
    c.undo();
    expect(c.timeline.find('s1'), isNotNull);
    expect(c.timeline.find('n1'), isNull);
  });

  test('settings changes are saved into the project', () {
    final c = ProEditorController(project(), newId: ids());
    c.updateSettings({'language': 'th', 'sourceLanguage': 'th'});
    final p = c.toProject();
    expect((p.language, p.sourceLanguage), ('th', 'th'));
  });

  test('renaming does not invalidate the saved timeline', () {
    final c = ProEditorController(project(), newId: ids());
    final saved = c.toProject();
    final before = saved.timelineV2Base;
    saved.name = 'New name';
    expect(v1Fingerprint(saved), before);
  });
}
