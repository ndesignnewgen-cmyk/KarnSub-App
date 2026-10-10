import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_app/models/subtitle_style_model.dart';
import 'package:subtitle_app/services/tap_sync_session.dart';

List<TapLine> lines(int n, {bool withOrig = false}) => List.generate(
      n,
      (i) => TapLine('line $i',
          origStartMs: withOrig ? i * 3000 : null,
          origEndMs: withOrig ? i * 3000 + 2000 : null),
    );

void main() {
  group('offset', () {
    test('reaction offset moves times earlier', () {
      final s = TapSyncSession(lines: lines(1), offsetMs: -180);
      s.press(1000);
      s.release(3000);
      expect(s.lines[0].startMs, 820);
      expect(s.lines[0].endMs, 2820);
      expect(s.lines[0].rawStartMs, 1000);
    });

    test('offset is scaled by playback speed (0.5x)', () {
      final s = TapSyncSession(lines: lines(1), offsetMs: -180, speed: 0.5);
      s.press(1000);
      s.release(3000);
      expect(s.lines[0].startMs, 910); // 180 ms wall = 90 ms media
      expect(s.lines[0].endMs, 2910);
    });

    test('never goes below zero', () {
      final s = TapSyncSession(lines: lines(1), offsetMs: -180);
      s.press(50);
      s.release(900);
      expect(s.lines[0].startMs, 0);
    });
  });

  group('hold mode', () {
    test('press/release walks through lines', () {
      final s = TapSyncSession(lines: lines(3), offsetMs: 0);
      expect(s.index, 0);
      s.press(1000);
      expect(s.inProgress, isTrue);
      s.release(2000);
      expect(s.index, 1);
      s.press(2500);
      s.release(4000);
      s.press(4500);
      s.release(6000);
      expect(s.isDone, isTrue);
      expect(s.tappedCount, 3);
    });

    test('release without press is ignored; double press is ignored', () {
      final s = TapSyncSession(lines: lines(2), offsetMs: 0);
      s.release(500);
      expect(s.index, 0);
      s.press(1000);
      s.press(1500);
      expect(s.lines[0].rawStartMs, 1000);
    });

    test('very short hold is stretched to minimum duration', () {
      final s = TapSyncSession(lines: lines(1), offsetMs: 0, minDurMs: 300);
      s.press(1000);
      s.release(1050);
      expect(s.lines[0].endMs, 1300);
    });

    test('tap() does nothing in hold mode', () {
      final s = TapSyncSession(lines: lines(1), offsetMs: 0);
      s.tap(1000);
      expect(s.lines[0].rawStartMs, isNull);
    });
  });

  group('tap mode', () {
    test('N lines need N+1 taps, lines are chained', () {
      final s =
          TapSyncSession(lines: lines(3), mode: TapMode.tap, offsetMs: 0);
      s.tap(1000); // start 0
      expect(s.inProgress, isTrue);
      s.tap(2000); // end 0, start 1
      s.tap(3500); // end 1, start 2
      expect(s.isDone, isFalse);
      s.tap(5000); // end 2
      expect(s.isDone, isTrue);
      expect([s.lines[0].startMs, s.lines[0].endMs], [1000, 2000]);
      expect([s.lines[1].startMs, s.lines[1].endMs], [2000, 3500]);
      expect([s.lines[2].startMs, s.lines[2].endMs], [3500, 5000]);
    });

    test('extra taps after done are ignored', () {
      final s =
          TapSyncSession(lines: lines(1), mode: TapMode.tap, offsetMs: 0);
      s.tap(1000);
      s.tap(2000);
      s.tap(3000);
      expect(s.lines[0].endMs, 2000);
    });
  });

  group('snap', () {
    test('start snaps to onset (with lead), end snaps to speech end', () {
      final s = TapSyncSession(
        lines: lines(1),
        offsetMs: 0,
        snap: true,
        onsets: [900, 5000],
        speechEnds: [2950, 8000],
        snapLeadMs: 60,
      );
      s.press(1100);
      s.release(2800);
      expect(s.lines[0].startMs, 840);
      expect(s.lines[0].snappedStart, isTrue);
      expect(s.lines[0].endMs, 2950);
      expect(s.lines[0].snappedEnd, isTrue);
    });

    test('no snap when nothing within the window', () {
      final s = TapSyncSession(
        lines: lines(1),
        offsetMs: 0,
        snap: true,
        onsets: [100],
        speechEnds: [9000],
        snapWindowMs: 300,
      );
      s.press(1000);
      s.release(3000);
      expect(s.lines[0].startMs, 1000);
      expect(s.lines[0].snappedStart, isFalse);
      expect(s.lines[0].endMs, 3000);
      expect(s.lines[0].snappedEnd, isFalse);
    });

    test('snap applies after the offset', () {
      final s = TapSyncSession(
        lines: lines(1),
        offsetMs: -200,
        snap: true,
        onsets: [800],
        snapLeadMs: 0,
        snapWindowMs: 50,
      );
      s.press(1000); // shifted → 800 → exactly on the onset
      expect(s.lines[0].startMs, 800);
      expect(s.lines[0].snappedStart, isTrue);
    });

    test('nearest() picks the closest value and respects the window', () {
      expect(TapSyncSession.nearest([100, 500, 900], 620, 300), 500);
      expect(TapSyncSession.nearest([100, 500, 900], 760, 300), 900);
      expect(TapSyncSession.nearest([100, 500, 900], 2000, 300), isNull);
      expect(TapSyncSession.nearest([], 10, 300), isNull);
      expect(TapSyncSession.nearest([1000], 0, 1000), 1000);
    });
  });

  group('undo', () {
    test('hold: undo while holding clears the start', () {
      final s = TapSyncSession(lines: lines(2), offsetMs: 0);
      s.press(5000);
      expect(s.undo(), 3000);
      expect(s.inProgress, isFalse);
      expect(s.lines[0].rawStartMs, isNull);
    });

    test('hold: undo after a release goes back one line', () {
      final s = TapSyncSession(lines: lines(2), offsetMs: 0);
      s.press(5000);
      s.release(7000);
      expect(s.index, 1);
      expect(s.undo(), 3000);
      expect(s.index, 0);
      expect(s.lines[0].isTapped, isFalse);
    });

    test('hold: undo at the very beginning returns null', () {
      final s = TapSyncSession(lines: lines(2), offsetMs: 0);
      expect(s.undo(), isNull);
    });

    test('tap: undo reopens the previous line', () {
      final s =
          TapSyncSession(lines: lines(3), mode: TapMode.tap, offsetMs: 0);
      s.tap(1000);
      s.tap(4000); // line 0 = 1000..4000, line 1 starts at 4000
      final seek = s.undo();
      expect(seek, 2000); // 2 s before the end being redone
      expect(s.index, 0);
      expect(s.inProgress, isTrue);
      expect(s.lines[0].endMs, isNull);
      expect(s.lines[1].rawStartMs, isNull);
      s.tap(4200); // re-end line 0, start line 1
      expect(s.lines[0].endMs, 4200);
      expect(s.lines[1].startMs, 4200);
    });

    test('tap: undo of the first start clears it', () {
      final s =
          TapSyncSession(lines: lines(2), mode: TapMode.tap, offsetMs: 0);
      s.tap(3000);
      expect(s.undo(), 1000);
      expect(s.lines[0].rawStartMs, isNull);
    });

    test('tap: undo when done reopens the last line', () {
      final s =
          TapSyncSession(lines: lines(1), mode: TapMode.tap, offsetMs: 0);
      s.tap(1000);
      s.tap(3000);
      expect(s.isDone, isTrue);
      expect(s.undo(), 1000);
      expect(s.isDone, isFalse);
      expect(s.inProgress, isTrue);
    });

    test('preroll never seeks below zero', () {
      final s = TapSyncSession(lines: lines(1), offsetMs: 0);
      s.press(500);
      expect(s.undo(), 0);
    });
  });

  group('skip', () {
    test('skip keeps the original timing', () {
      final s =
          TapSyncSession(lines: lines(2, withOrig: true), offsetMs: 0);
      s.skip();
      expect(s.index, 1);
      expect(s.lines[0].skipped, isTrue);
      expect(s.lines[0].effStartMs, 0);
      expect(s.lines[0].effEndMs, 2000);
    });

    test('skip is ignored while holding', () {
      final s = TapSyncSession(lines: lines(2), offsetMs: 0);
      s.press(1000);
      s.skip();
      expect(s.index, 0);
    });

    test('tap mode: after a skip the next tap starts the next line', () {
      final s = TapSyncSession(
          lines: lines(3, withOrig: true), mode: TapMode.tap, offsetMs: 0);
      s.skip();
      s.tap(3100);
      expect(s.lines[1].startMs, 3100);
    });
  });

  group('finalize rules', () {
    test('overlap with the previous line is trimmed', () {
      final s = TapSyncSession(lines: lines(2), offsetMs: 0, minShowMs: 0);
      s.press(1000);
      s.release(3000);
      s.press(2500); // starts before line 0 ended (e.g. after a seek)
      s.release(4000);
      s.finalize();
      expect(s.lines[0].endMs, 2500);
      expect(s.lines[1].startMs, 2500);
    });

    test('tapped lines push against kept original lines', () {
      final ls = lines(2, withOrig: true); // line1 orig 3000..5000
      final s = TapSyncSession(lines: ls, offsetMs: 0, minShowMs: 0);
      s.press(1000);
      s.release(3600); // runs into line 1's original start
      s.finalize();
      expect(s.lines[0].endMs, 3000);
      expect(s.lines[1].effStartMs, 3000);
    });

    test('minimum on-screen time without hitting the next line', () {
      final s = TapSyncSession(
          lines: lines(2), offsetMs: 0, minDurMs: 100, minShowMs: 700);
      s.press(1000);
      s.release(1200);
      s.press(1500);
      s.release(3000);
      s.finalize();
      expect(s.lines[0].endMs, 1500); // wanted 1700, capped by next start
    });

    test('minimum on-screen time extends when there is room', () {
      final s = TapSyncSession(
          lines: lines(1), offsetMs: 0, minDurMs: 100, minShowMs: 700);
      s.press(1000);
      s.release(1200);
      s.finalize();
      expect(s.lines[0].endMs, 1700);
    });

    test('too-fast lines are flagged', () {
      final s = TapSyncSession(
          lines: [TapLine('ກຂຄງຈສຊຍດຕຖທນບປຜຝພຟມຢຣລວ')], offsetMs: 0);
      s.press(0);
      s.release(1000); // 25 chars in 1 s
      s.finalize();
      expect(s.isTooFast(s.lines[0]), isTrue);
    });

    test('fillUntimed places untapped script lines after the last one', () {
      final s = TapSyncSession(lines: lines(3), offsetMs: 0);
      s.press(1000);
      s.release(2000);
      s.finalize();
      s.fillUntimed(defaultMs: 2000, gapMs: 100);
      expect([s.lines[1].effStartMs, s.lines[1].effEndMs], [2100, 4100]);
      expect([s.lines[2].effStartMs, s.lines[2].effEndMs], [4200, 6200]);
    });
  });

  group('TapSyncApply', () {
    SubtitleSegment seg() => SubtitleSegment(
          id: 'a',
          text: 'abc',
          startTime: const Duration(milliseconds: 1000),
          endTime: const Duration(milliseconds: 3000),
          words: ['a', 'b', 'c'],
          wordTimings: const [
            Duration(milliseconds: 1000),
            Duration(milliseconds: 1500),
            Duration(milliseconds: 2000),
          ],
        );

    test('retime stretches word timings into the new span', () {
      final s = seg();
      TapSyncApply.retime(s, 2000, 6000);
      expect(s.startTime.inMilliseconds, 2000);
      expect(s.endTime.inMilliseconds, 6000);
      expect(s.wordTimings!.map((d) => d.inMilliseconds).toList(),
          [2000, 3000, 4000]);
    });

    test('applyWords writes karaoke word starts and caps the tail', () {
      final s = seg();
      final w = [TapLine('a'), TapLine('b'), TapLine('c')];
      final sess =
          TapSyncSession(lines: w, mode: TapMode.tap, offsetMs: 0);
      sess.tap(1100);
      sess.tap(1400);
      sess.tap(1900);
      sess.tap(6000); // long pause before the next sentence
      TapSyncApply.applyWords(s, w, maxTailMs: 1500);
      expect(s.words, ['a', 'b', 'c']);
      expect(s.wordTimings!.map((d) => d.inMilliseconds).toList(),
          [1100, 1400, 1900]);
      expect(s.startTime.inMilliseconds, 1100);
      expect(s.endTime.inMilliseconds, 3400);
    });
  });
}
