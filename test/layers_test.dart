import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_app/models/subtitle_style_model.dart';
import 'package:subtitle_app/pro_editor/pro_editor_controller.dart';
import 'package:subtitle_app/timeline/layer_render.dart';
import 'package:subtitle_app/timeline/timeline_model.dart';

late Directory tmp;
String file(String n) => (File('${tmp.path}/$n')..writeAsStringSync('x')).path;

String Function() ids() {
  var n = 0;
  return () => 'n${n++}';
}

SubtitleProject project() => SubtitleProject(
      id: 'p',
      name: 'L',
      videoPath: file('v.mp4'),
      videoDuration: const Duration(seconds: 10),
      selectedStyle: subtitlePresets.first,
    );

Future<ui.Image> decode(Uint8List png) async =>
    (await (await ui.instantiateImageCodec(png)).getNextFrame()).image;

Future<int> alphaAt(ui.Image img, int x, int y) async {
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return data.getUint8((y * img.width + x) * 4 + 3);
}

/// A 100×100 opaque red PNG.
Future<String> redPng() async {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec).drawRect(const ui.Rect.fromLTWH(0, 0, 100, 100), ui.Paint()..color = const ui.Color(0xFFFF0000));
  final img = await rec.endRecording().toImage(100, 100);
  final f = File('${tmp.path}/red.png')
    ..writeAsBytesSync((await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
  return f.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final lao = File('assets/fonts/NotoSansLao.ttf').readAsBytesSync();
    await (FontLoader('NotoSansLao')..addFont(Future.value(ByteData.sublistView(lao)))).load();
  });
  setUp(() => tmp = Directory.systemTemp.createTempSync('karnsub_layers_'));
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('text layers', () {
    test('new text is sized from its nominal font size; editing keeps that size', () {
      final c = ProEditorController(project(), newId: ids());
      c.seek(1000);
      final id = c.addText('ໂປຣ')!;
      final e = c.timeline.find(id)!.$2 as TextElement;
      expect(c.timeline.find(id)!.$1.kind, TrackKind.text);
      expect((e.startMs, e.durationMs), (1000, 3000));
      expect(e.transform.scale, closeTo(TextLayer(e).naturalFraction(), 1e-9));
      c.updateText(id, text: 'ໂປຣ 1 ແຖມ 1 ທຸກວັນສຸກ');
      final e2 = c.timeline.find(id)!.$2 as TextElement;
      final k = TextLayer(e2).size.width / TextLayer(e).size.width;
      expect(e2.transform.scale, closeTo(e.transform.scale * k, 1e-6));
      c.updateText(id, style: {'color': 0xFFFF0000, 'bg': 0xFF000000});
      final e3 = c.timeline.find(id)!.$2 as TextElement;
      expect((e3.style['color'], e3.style['bg'], e3.text), (0xFFFF0000, 0xFF000000, 'ໂປຣ 1 ແຖມ 1 ທຸກວັນສຸກ'));
    });

    test('text renders to a PNG with transparent corners and ink in the middle', () async {
      final png = await renderTextPng(const TextElement(
          id: 't', startMs: 0, durationMs: 1, text: 'ສະບາຍດີ', style: {'color': 0xFFFFFFFF}));
      final img = await decode(png);
      expect(img.width, greaterThan(img.height));
      expect(await alphaAt(img, 0, 0), 0);
      var ink = 0;
      for (var x = img.width ~/ 4; x < img.width * 3 ~/ 4; x += 3) {
        if (await alphaAt(img, x, img.height ~/ 2) > 0) ink++;
      }
      expect(ink, greaterThan(0));
    });

    test('a background colour fills the box', () async {
      final png = await renderTextPng(const TextElement(
          id: 't', startMs: 0, durationMs: 1, text: 'A', style: {'bg': 0xFF2244FF}));
      final img = await decode(png);
      expect(await alphaAt(img, img.width ~/ 2, 4), 255);
    });
  });

  group('shapes & masks', () {
    test('shapes: added on a shape track, colours editable, rendered to PNG', () async {
      final c = ProEditorController(project(), newId: ids());
      final id = c.addShape('star')!;
      c.updateShape(id, fill: 0xFF00FF00, stroke: 0xFF000000, strokeWidth: 4);
      final e = c.timeline.find(id)!.$2 as ShapeElement;
      expect((e.fillColor, e.strokeWidth), (0xFF00FF00, 4.0));
      final img = await decode(await renderShapePng(e, size: 200));
      expect(await alphaAt(img, 100, 100), 255); // star centre filled
      expect(await alphaAt(img, 2, 2), 0); // corner empty
    });

    test('heart mask: corners cut away, centre kept; inverted does the opposite', () async {
      final src = await redPng();
      final img = await decode(await renderMaskedPng(src, const MaskSpec(shape: 'heart', size: 0.9)));
      expect((img.width, img.height), (100, 100));
      expect(await alphaAt(img, 2, 2), 0);
      expect(await alphaAt(img, 50, 55), 255);
      final inv = await decode(
          await renderMaskedPng(src, const MaskSpec(shape: 'heart', size: 0.9, inverted: true)));
      expect(await alphaAt(inv, 2, 2), 255);
      expect(await alphaAt(inv, 50, 55), 0);
    });

    test('setMask on an image, and clearing it', () async {
      final c = ProEditorController(project(), newId: ids());
      c.addOverlay(await redPng(), 2000, isVideo: false);
      final id = c.primary!;
      c.setMask(id, const MaskSpec(shape: 'ellipse', feather: 0.3));
      expect((c.timeline.find(id)!.$2 as ImageElement).mask!.shape, 'ellipse');
      c.setMask(id, const MaskSpec(shape: 'none'));
      expect((c.timeline.find(id)!.$2 as ImageElement).mask, isNull);
    });

    test('renderLayers writes PNGs once and reuses them', () async {
      final c = ProEditorController(project(), newId: ids());
      final t1 = c.addText('ສະບາຍດີ')!;
      final s1 = c.addShape('rect')!;
      c.addOverlay(await redPng(), 2000, isVideo: false);
      final img = c.primary!;
      c.setMask(img, const MaskSpec(shape: 'star'));
      final dir = Directory('${tmp.path}/layers');
      final a = await renderLayers(c.timeline, dir);
      expect(a.keys.toSet(), {t1, s1, img});
      expect(a.values.every((p) => File(p).existsSync()), isTrue);
      final b = await renderLayers(c.timeline, dir);
      expect(b, a);
      expect(dir.listSync().length, 3);
      c.updateText(t1, text: 'ປ່ຽນ');
      final d = await renderLayers(c.timeline, dir);
      expect(d[t1], isNot(a[t1]));
    });
  });

  group('keyframes', () {
    test('drag without keyframes moves the layer itself', () {
      final c = ProEditorController(project(), newId: ids());
      final id = c.addShape('rect')!;
      c.setTransform(id, const ElementTransform(x: 0.2, y: 0.7, scale: 0.5, rotation: 15));
      final e = c.timeline.find(id)!.$2 as ShapeElement;
      expect((e.transform.x, e.transform.rotation), (0.2, 15.0));
      expect(e.keyframes, isEmpty);
    });

    test('◆ adds keyframes (pinning the start), drag edits the one at the playhead', () {
      final c = ProEditorController(project(), newId: ids());
      final id = c.addShape('rect')!; // at 0–3000
      c.seek(1500);
      expect(c.toggleKeyframe(id), isTrue);
      var e = c.timeline.find(id)!.$2 as ShapeElement;
      expect(e.keyframes.map((k) => k.timeMs), [0, 1500]);
      expect(c.hasKeyframeNow(id), isTrue);
      c.setTransform(id, const ElementTransform(x: 0.9, scale: 0.3));
      e = c.timeline.find(id)!.$2 as ShapeElement;
      expect(e.keyframes[1].t.x, 0.9);
      expect(e.transform.x, 0.5); // base untouched
      c.seek(750);
      expect(c.transformNow(id)!.x, closeTo(0.7, 1e-9)); // halfway 0.5 → 0.9
      c.setTransform(id, const ElementTransform(x: 0.1)); // no kf here → adds one
      e = c.timeline.find(id)!.$2 as ShapeElement;
      expect(e.keyframes.map((k) => k.timeMs), [0, 750, 1500]);
      c.seek(1500);
      c.toggleKeyframe(id); // remove the one at the playhead
      e = c.timeline.find(id)!.$2 as ShapeElement;
      expect(e.keyframes.map((k) => k.timeMs), [0, 750]);
    });

    test('in/out animation becomes keyframes around the resting look', () {
      final c = ProEditorController(project(), newId: ids());
      final id = c.addShape('rect')!; // 0–3000
      final base = (c.timeline.find(id)!.$2 as ShapeElement).transform;
      expect(c.applyAnimation(id, inKind: 'pop', outKind: 'fade', ms: 500), isTrue);
      var e = c.timeline.find(id)!.$2 as ShapeElement;
      expect(e.keyframes.map((k) => k.timeMs), [0, 500, 2500, 3000]);
      expect(e.keyframes.first.t.opacity, 0);
      expect(e.keyframes.first.t.scale, closeTo(base.scale * 0.6, 1e-9));
      expect(e.keyframes[1].t.scale, base.scale);
      expect(e.keyframes.last.t.opacity, 0);
      expect(e.keyframes.last.t.scale, base.scale);
      c.seek(1500);
      expect(c.transformNow(id)!.opacity, 1); // fully visible in the middle

      // Durations clamp to half the layer; 'none' clears it.
      c.applyAnimation(id, inKind: 'slideUp', ms: 5000);
      e = c.timeline.find(id)!.$2 as ShapeElement;
      expect(e.keyframes.map((k) => k.timeMs), [0, 1500]);
      c.applyAnimation(id);
      expect((c.timeline.find(id)!.$2 as ShapeElement).keyframes, isEmpty);
    });

    test('easing applies to the keyframe before the playhead', () {
      final c = ProEditorController(project(), newId: ids());
      final id = c.addShape('rect')!;
      c.seek(2000);
      c.toggleKeyframe(id);
      c.seek(1000);
      c.setEasing(id, 6, bezier: const [0.4, 0, 0.6, 1]);
      final e = c.timeline.find(id)!.$2 as ShapeElement;
      expect(e.keyframes[0].easing, 6);
      expect(e.keyframes[0].bezier, [0.4, 0.0, 0.6, 1.0]);
      expect(e.keyframes[1].easing, 0);
    });

    test('copy & paste keyframes to another layer', () {
      final c = ProEditorController(project(), newId: ids());
      final a = c.addShape('rect')!;
      c.seek(1000);
      c.toggleKeyframe(a);
      c.copyKeyframes(a);
      c.seek(0);
      final b = c.addShape('ellipse')!;
      expect(c.pasteKeyframes(b), isTrue);
      expect((c.timeline.find(b)!.$2 as ShapeElement).keyframes.length, 2);
    });

    test('◆ on a subtitle is refused (not a visual layer)', () {
      final p = project()
        ..segments.add(SubtitleSegment(
            id: 's', text: 'x', startTime: Duration.zero, endTime: const Duration(seconds: 1)));
      final c = ProEditorController(p, newId: ids());
      expect(c.toggleKeyframe('s'), isFalse);
    });
  });

  group('transitions', () {
    test('set, replace, apply to all, remove', () {
      final c = ProEditorController(project(), newId: ids());
      c.seek(3000);
      c.splitAtPlayhead();
      c.seek(6000);
      c.clearSelection();
      c.splitAtPlayhead();
      final m = c.timeline.mainTrack!.elements;
      c.setTransition(m[0].id, m[1].id, 'fade', 600);
      expect(c.transitionBetween(m[0].id, m[1].id)!.kind, 'fade');
      c.setTransitionAll('zoom', 400);
      expect(c.timeline.transitions.map((x) => x.kind), ['zoom', 'zoom']);
      c.setTransition(m[0].id, m[1].id, 'none', 0);
      expect(c.timeline.transitions.length, 1);
      c.undo();
      expect(c.timeline.transitions.length, 2);
    });
  });
}
