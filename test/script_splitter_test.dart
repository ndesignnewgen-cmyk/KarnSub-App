import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_app/services/script_splitter.dart';
import 'package:subtitle_app/services/tap_sync_calibration.dart';

/// Fake segmenter: words are separated by '|' in the test input; spaces are
/// dropped like ICU does.
Future<List<List<String>>> fakeSeg(List<String> texts, String locale) async =>
    texts
        .map((t) => t
            .replaceAll(' ', '|')
            .split('|')
            .where((w) => w.isNotEmpty)
            .toList())
        .toList();

void main() {
  group('ScriptSplitter.roughChunks', () {
    test('splits on new lines and sentence punctuation + space', () {
      expect(
        ScriptSplitter.roughChunks('ສະບາຍດີ. ມື້ນີ້ອາກາດດີ!\n\nໄປໃສມາ? ບໍ່ໄປໃສ'),
        ['ສະບາຍດີ.', 'ມື້ນີ້ອາກາດດີ!', 'ໄປໃສມາ?', 'ບໍ່ໄປໃສ'],
      );
    });

    test('keeps numbers and ໆ inside a sentence', () {
      expect(ScriptSplitter.roughChunks('ລາຄາ 25.000 ກີບ ໄວໆນີ້'),
          ['ລາຄາ 25.000 ກີບ ໄວໆນີ້']);
    });

    test('long runs of spaces and tabs split', () {
      expect(ScriptSplitter.roughChunks('ກ    ຂ\tຄ'), ['ກ', 'ຂ', 'ຄ']);
    });

    test('CRLF and blank lines are handled', () {
      expect(ScriptSplitter.roughChunks('a\r\n\r\nb\r\n'), ['a', 'b']);
    });
  });

  group('visibleLength', () {
    test('combining Lao marks are not counted', () {
      expect(ScriptSplitter.visibleLength('ກີ່'), 1); // ກ + ີ + ່
      expect(ScriptSplitter.visibleLength('ສະບາຍດີ'), 6); // ສ ະ ບ າ ຍ ດ (+ ີ)
      expect(ScriptSplitter.visibleLength('a b'), 2);
    });
  });

  group('wrapWords', () {
    test('never cuts inside a word', () {
      final r = ScriptSplitter.wrapWords(
          ['ສະບາຍດີ', 'ທຸກຄົນ', 'ມື້ນີ້', 'ພວກເຮົາ', 'ຈະມາ', 'ສອນ'], 12);
      for (final line in r) {
        expect(ScriptSplitter.visibleLength(line), lessThanOrEqualTo(12));
      }
      expect(r.join(), 'ສະບາຍດີທຸກຄົນມື້ນີ້ພວກເຮົາຈະມາສອນ');
    });

    test('a single word longer than the limit stays whole', () {
      expect(ScriptSplitter.wrapWords(['abcdefghijkl'], 5), ['abcdefghijkl']);
    });

    test('tiny last line pulls a word down from the line before', () {
      final r = ScriptSplitter.wrapWords(['abcd', 'efgh', 'ij'], 8);
      expect(r, ['abcd', 'efghij']);
    });

    test('tiny last line merges when nothing can be pulled down', () {
      final r = ScriptSplitter.wrapWords(['abcdefgh', 'ij'], 8);
      expect(r, ['abcdefghij']); // 10 ≤ 8 + 3
    });

    test('no merge when it would go far over the limit', () {
      final r = ScriptSplitter.wrapWords(['abcdefghijkl', 'mn'], 8);
      expect(r, ['abcdefghijkl', 'mn']);
    });
  });

  group('split (async)', () {
    test('short chunks are untouched, long ones wrap at words', () async {
      final r = await ScriptSplitter.split(
        'ສັ້ນໆ\naaaa|bbbb|cccc|dddd|eeee',
        maxChars: 10,
        segmenter: fakeSeg,
      );
      expect(r, ['ສັ້ນໆ', 'aaaabbbb', 'ccccdddd', 'eeee']);
    });

    test('spaces between words are kept', () async {
      final r = await ScriptSplitter.split(
        'hello there my good friend',
        maxChars: 12,
        segmenter: fakeSeg,
      );
      // Spaces don't count toward the limit, but they are kept in the text.
      expect(r, ['hello there my', 'good friend']);
    });
  });

  group('merge / split lines', () {
    test('mergeWithNext', () {
      expect(ScriptSplitter.mergeWithNext(['ກ', 'ຂ', 'ຄ'], 0), ['ກຂ', 'ຄ']);
      expect(ScriptSplitter.mergeWithNext(['ab', 'cd'], 0), ['ab cd']);
      expect(ScriptSplitter.mergeWithNext(['ກ'], 0), ['ກ']);
    });

    test('splitAt', () {
      expect(ScriptSplitter.splitAt(['ກຂຄງ'], 0, 2), ['ກຂ', 'ຄງ']);
      expect(ScriptSplitter.splitAt(['ກຂ'], 0, 0), ['ກຂ']);
    });
  });

  group('TapSyncCalibration', () {
    test('click WAV has a valid header and the right length', () {
      final wav = TapSyncCalibration.buildClickWav(
          clicks: [100], durationMs: 1000, rate: 8000);
      final b = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(b.getUint32(24, Endian.little), 8000);
      expect(wav.length, 44 + 8000 * 2);
      // Silence before the click, sound right after it.
      expect(b.getInt16(44 + 10 * 2, Endian.little), 0);
      final peak = List.generate(
              40, (i) => b.getInt16(44 + (800 + i) * 2, Endian.little).abs())
          .reduce((a, c) => a > c ? a : c);
      expect(peak, greaterThan(1000));
    });

    test('estimate = minus median delay', () {
      const clicks = TapSyncCalibration.clickTimesMs;
      final taps = [for (final c in clicks) c + 200];
      taps[2] = clicks[2] + 650; // one slow tap barely counts
      expect(TapSyncCalibration.estimateOffset(taps), -200);
    });

    test('too few matched taps → null', () {
      expect(TapSyncCalibration.estimateOffset([1300, 2400]), isNull);
      expect(TapSyncCalibration.estimateOffset([50, 60, 70, 80, 90]), isNull);
    });

    test('result is clamped to 0…−600', () {
      const clicks = TapSyncCalibration.clickTimesMs;
      final early = [for (final c in clicks) c - 50];
      expect(TapSyncCalibration.estimateOffset(early), 0);
    });
  });
}
