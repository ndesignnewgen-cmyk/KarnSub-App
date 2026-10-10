import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_app/i18n/i18n.dart';
import 'package:subtitle_app/models/subtitle_style_model.dart';
import 'package:subtitle_app/pro_editor/pro_editor_screen.dart';
import 'package:subtitle_app/pro_editor/pro_timeline_view.dart';
import 'package:subtitle_app/providers/project_provider.dart';
import 'package:subtitle_app/services/project_store.dart';
import 'package:subtitle_app/services/storage_service.dart';
import 'package:subtitle_app/services/tap_sync_media.dart';
import 'package:subtitle_app/timeline/timeline_audio.dart';
import 'package:subtitle_app/timeline/timeline_model.dart';

late Directory tmp;
String file(String n) => (File('${tmp.path}/$n')..writeAsStringSync('x')).path;

class FakeMedia extends TapSyncMedia {
  int pos = 0;
  bool playing = false;
  @override
  int get durationMs => 60000;
  @override
  bool get isPlaying => playing;
  @override
  double get aspectRatio => 9 / 16;
  @override
  Future<void> init() async {}
  @override
  Future<int> positionMs() async => pos;
  @override
  Future<void> seek(int ms) async => pos = ms;
  @override
  Future<void> play() async => playing = true;
  @override
  Future<void> pause() async => playing = false;
  @override
  Future<void> setSpeed(double s) async {}
  @override
  Future<void> setVolume(double v) async {}
  @override
  Widget preview() => const ColoredBox(color: Colors.black);
  @override
  Future<void> dispose() async {}
  @override
  Future<TapSyncAnalysis> analyze() async => TapSyncAnalysis.empty;
}

const d = Duration.new;

SubtitleProject project() => SubtitleProject(
      id: 'p1',
      name: 'Test',
      videoPath: file('v.mp4'),
      videoDuration: d(milliseconds: 10000),
      selectedStyle: subtitlePresets.first,
      segments: [
        SubtitleSegment(id: 's1', text: 'ສະບາຍດີ', startTime: d(milliseconds: 1000),
            endTime: d(milliseconds: 2000)),
        SubtitleSegment(id: 's2', text: 'ທຸກຄົນ', startTime: d(milliseconds: 4000),
            endTime: d(milliseconds: 5000)),
      ],
    );

Future<ProjectProvider> pump(WidgetTester t,
    {Size size = const Size(390, 844),
    Future<String?> Function(String)? pick,
    ProEditorScreenTestHooks? hooks,
    Future<List<({int ms, String path})>> Function(String)? thumbs,
    WidgetBuilder? exportScreen,
    Future<String> Function(List<String>)? merge}) async {
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  // Seed the provider the way the app does: from storage.
  final p = project();
  await t.runAsync(() async {
    await StorageService.saveProjects([p]);
  });
  final provider = ProjectProvider();
  await t.runAsync(provider.loadFromStorage);
  provider.setCurrentProject(provider.projects.single);
  await t.pumpWidget(ChangeNotifierProvider.value(
    value: provider,
    child: MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) => ProEditorScreen(
                    mediaFactory: (_) => FakeMedia(),
                    pickFile: pick ?? (_) async => null,
                    probeDurationMs: (_) async => 3000,
                    audioRenderer: hooks?.renderer,
                    processingBuilder: hooks?.processing,
                    tempDir: hooks?.tempDir,
                    thumbnailLoader: thumbs ?? (_) async => const [],
                    // Layer PNGs need real file IO; covered by layers_test.dart.
                    layerDir: () async => throw UnsupportedError('no layer files in widget tests'),
                    exportScreen: exportScreen,
                    merge: merge,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return provider;
}

Finder el(String id) => find.byKey(Key('pe_el_$id'));
Finder tool(String k) => find.byKey(Key('pe_tool_$k'));

/// Scrub by dragging an empty part of the timeline (left = forward in time).
Future<void> scrubBy(WidgetTester t, double dx) async {
  final box = t.getRect(find.byType(ProTimelineView));
  await t.dragFrom(Offset(box.left + 60, box.bottom - 12), Offset(dx, 0));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('karnsub_pe_');
    SharedPreferences.setMockInitialValues({});
    StorageService.debugStore = ProjectStore(Directory('${tmp.path}/projects'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.anniekaydee.subtitle_app/tapsync'),
      (call) async => null,
    );
  });
  tearDown(() {
    StorageService.debugStore = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  for (final lang in ['lo', 'th']) {
    testWidgets('opens with tracks and the main toolbar ($lang)', (t) async {
      I18n.lang.value = lang;
      await pump(t);
      expect(find.byType(ProTimelineView), findsOneWidget);
      expect(el('s1'), findsOneWidget); // subtitle block visible near playhead
      expect(tool('split'), findsOneWidget);
      expect(tool('overlay'), findsOneWidget);
      expect(tool('delete'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('small phone (320×640) lays out', (t) async {
    I18n.lang.value = 'lo';
    await pump(t, size: const Size(320, 640));
    expect(t.takeException(), isNull);
  });

  testWidgets('tap block → selection tools → delete → undo', (t) async {
    I18n.lang.value = 'lo';
    await pump(t);
    await t.tap(el('s1'));
    await t.pump();
    expect(tool('delete'), findsOneWidget);
    expect(find.byKey(const Key('pe_trimR_s1')), findsOneWidget);
    await t.tap(tool('delete'));
    await t.pump();
    expect(el('s1'), findsNothing);
    expect(tool('delete'), findsNothing); // back to main tools
    await t.tap(find.byKey(const Key('pe_undo')));
    await t.pump();
    expect(el('s1'), findsOneWidget);
  });

  testWidgets('scrub then split the main clip', (t) async {
    I18n.lang.value = 'lo';
    await pump(t);
    await scrubBy(t, -240); // 80 px/s → ~+3 s (minus the touch slop)
    final view = t.widget<ProTimelineView>(find.byType(ProTimelineView));
    final at = view.c.playhead.value;
    expect(at, inInclusiveRange(2500, 3000));
    await t.tap(tool('split'));
    await t.pump();
    final main = view.c.timeline.mainTrack!.elements;
    expect(main.length, 2);
    expect(main.first.endMs, at); // split exactly at the playhead
  });

  testWidgets('drag the right trim handle to lengthen a subtitle', (t) async {
    I18n.lang.value = 'lo';
    await pump(t);
    await t.tap(el('s1'));
    await t.pump();
    final view = t.widget<ProTimelineView>(find.byType(ProTimelineView));
    view.c.snapping = false;
    final h = find.byKey(const Key('pe_trimR_s1'));
    await t.drag(h, const Offset(40, 0)); // 40 px at 80 px/s = +500 ms
    await t.pump();
    final end = view.c.timeline.find('s1')!.$2.endMs;
    expect((end - 2500).abs() <= 40, isTrue, reason: 'end=$end');
    // The whole drag is one undo step.
    await t.tap(find.byKey(const Key('pe_undo')));
    await t.pump();
    expect(view.c.timeline.find('s1')!.$2.endMs, 2000);
  });

  testWidgets('“+” appends a picked clip to the main track', (t) async {
    I18n.lang.value = 'lo';
    final clip = file('more.mp4');
    await pump(t, pick: (kind) async => kind == 'video' ? clip : null);
    final view = t.widget<ProTimelineView>(find.byType(ProTimelineView));
    view.c.zoom(0.1); // zoom out so the end of the track (and “+”) is visible
    await t.pump();
    await t.tap(find.byKey(const Key('pe_addClip')));
    await t.pumpAndSettle();
    final main = view.c.timeline.mainTrack!.elements;
    expect(main.length, 2);
    expect((main.last.startMs, main.last.durationMs), (10000, 3000));
  });

  testWidgets('mute the main track from its gutter', (t) async {
    I18n.lang.value = 'lo';
    await pump(t);
    await t.tap(find.byKey(const Key('pe_mainGutter')));
    await t.pump();
    final view = t.widget<ProTimelineView>(find.byType(ProTimelineView));
    expect(view.c.timeline.mainTrack!.muted, isTrue);
  });

  testWidgets('play/pause button', (t) async {
    I18n.lang.value = 'lo';
    await pump(t);
    await t.tap(find.byKey(const Key('pe_play')));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await t.tap(find.byKey(const Key('pe_play')));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.byIcon(Icons.play_arrow), findsWidgets);
  });

  testWidgets('ຊັບ AI: edited audio → AI → subtitles on the timeline', (t) async {
    I18n.lang.value = 'lo';
    String? renderedWav;
    String? usedEngine;
    final view = ProEditorScreenTestHooks(
      renderer: _StubRenderer(),
      processing: (wav, engine, onResult) {
        renderedWav = wav;
        usedEngine = engine;
        return _FakeProcessing(onResult: onResult);
      },
      tempDir: () async => tmp,
    );
    final provider = await pump(t, hooks: view);
    await scrubBy(t, -240);
    await t.tap(tool('split')); // edit first …
    await t.pump();
    await t.tap(tool('back')); // deselect the new clip
    await t.pump();
    await t.tap(tool('aisubs')); // … subtitles later
    await t.pumpAndSettle();
    await t.tap(find.text('ໄທ').first); // spoken Thai → Lao subtitles
    await t.pump();
    await t.tap(find.byKey(const Key('pe_ai_go')));
    await t.pump();
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 500))); // real file IO
    await t.pumpAndSettle();
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();

    expect(renderedWav, isNotNull);
    expect(renderedWav, endsWith('pro_timeline_audio.wav'));
    expect(usedEngine, 'gemini');
    final c = t.widget<ProTimelineView>(find.byType(ProTimelineView)).c;
    final subs = c.timeline.tracksOf(TrackKind.subtitle).single.elements;
    expect(subs.map((e) => (e as SubtitleElement).text), ['ສະບາຍດີ ຈາກ AI']);
    expect(c.timeline.settings['sourceLanguage'], 'th');
    expect(c.timeline.settings['translateMode'], TranslateMode.translate.index);
    expect(provider.currentProject, isNotNull);
  });

  testWidgets('design 01: video frames on clips + transition marker after a split', (t) async {
    I18n.lang.value = 'lo';
    final frame = file('f.jpg');
    await pump(t, thumbs: (_) async => [for (var i = 0; i < 10; i++) (ms: i * 1000, path: frame)]);
    await t.pump();
    final view = find.byType(ProTimelineView);
    expect(find.descendant(of: view, matching: find.byType(Image)), findsWidgets);
    expect(find.text('ປິດສຽງ'), findsOneWidget);
    expect(find.text('ໜ້າປົກ'), findsOneWidget);
    await scrubBy(t, -240);
    await t.tap(tool('split'));
    await t.pump();
    final c = t.widget<ProTimelineView>(view).c;
    final first = c.timeline.mainTrack!.elements.first.id;
    expect(find.byKey(Key('pe_tr_$first')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('selecting a clip dims the other tracks and shows clip tools', (t) async {
    I18n.lang.value = 'lo';
    await pump(t);
    final c = t.widget<ProTimelineView>(find.byType(ProTimelineView)).c;
    final r = t.getRect(find.byKey(Key('pe_el_${c.timeline.mainTrack!.elements.first.id}')));
    await t.tapAt(Offset(r.left + 30, r.center.dy)); // its visible part
    await t.pumpAndSettle();
    final sub = t.widget<AnimatedOpacity>(
        find.descendant(of: el('s1'), matching: find.byType(AnimatedOpacity)));
    expect(sub.opacity, lessThan(0.5));
    for (final k in ['split', 'speed', 'volume', 'anim', 'delete', 'mask']) {
      expect(tool(k), findsOneWidget, reason: k);
    }
    expect(find.byKey(const Key('pe_keyframe')), findsOneWidget);
  });

  testWidgets('fullscreen hides the timeline and comes back', (t) async {
    I18n.lang.value = 'lo';
    await pump(t);
    await t.tap(find.byKey(const Key('pe_fullscreen')));
    await t.pump();
    expect(find.byType(ProTimelineView), findsNothing);
    await t.tap(find.byKey(const Key('pe_fullscreen')));
    await t.pump();
    expect(find.byType(ProTimelineView), findsOneWidget);
  });

  testWidgets('ຂໍ້ຄວາມ: add text, edit it in the sheet, it shows on the video', (t) async {
    I18n.lang.value = 'lo';
    await pump(t);
    await t.tap(tool('text'));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('pe_text_field')), findsOneWidget);
    await t.enterText(find.byKey(const Key('pe_text_field')), 'ໂປຣ 1 ແຖມ 1');
    await t.tap(find.byKey(const Key('pe_text_bold'))); // bold off (on by default)
    await t.pump();
    await t.tap(find.byKey(const Key('pe_sheet_done')));
    await t.pumpAndSettle();
    final c = t.widget<ProTimelineView>(find.byType(ProTimelineView)).c;
    final txt = c.timeline.tracksOf(TrackKind.text).single.elements.single as TextElement;
    expect(txt.text, 'ໂປຣ 1 ແຖມ 1');
    expect(txt.style['bold'], false);
    expect(find.byKey(ValueKey('pv_${txt.id}')), findsOneWidget); // drawn in the preview
    expect(tool('editText'), findsOneWidget); // text tools for the selected layer
    expect(tool('curve'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('drag the selected layer on the video to move it', (t) async {
    I18n.lang.value = 'lo';
    await pump(t);
    final c = t.widget<ProTimelineView>(find.byType(ProTimelineView)).c;
    final id = c.addShape('star')!;
    await t.pump();
    final before = (c.timeline.find(id)!.$2 as ShapeElement).transform;
    await t.drag(find.byKey(ValueKey('pv_$id')), const Offset(40, 30));
    await t.pump();
    final after = (c.timeline.find(id)!.$2 as ShapeElement).transform;
    expect(after.x, greaterThan(before.x));
    expect(after.y, greaterThan(before.y));
    c.undo(); // the whole drag is one step
    expect((c.timeline.find(id)!.$2 as ShapeElement).transform.x, before.x);
  });

  testWidgets('Mask sheet: pick a heart for a photo', (t) async {
    I18n.lang.value = 'lo';
    await pump(t);
    final c = t.widget<ProTimelineView>(find.byType(ProTimelineView)).c;
    c.addOverlay(file('photo.png'), 2000, isVideo: false);
    await t.pump();
    await t.tap(tool('mask'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pe_mask_heart')));
    await t.pump();
    expect((c.timeline.find(c.primary!)!.$2 as ImageElement).mask!.shape, 'heart');
    expect(find.byType(Slider), findsWidgets); // feather / size / rotate
  });

  testWidgets('◆ adds a keyframe; Keyframe sheet sets the curve', (t) async {
    I18n.lang.value = 'lo';
    await pump(t);
    final c = t.widget<ProTimelineView>(find.byType(ProTimelineView)).c;
    final id = c.addShape('rect')!;
    c.seek(1500);
    await t.pump();
    await t.tap(find.byKey(const Key('pe_keyframe')));
    await t.pump();
    expect((c.timeline.find(id)!.$2 as ShapeElement).keyframes.length, 2);
    await t.tap(tool('curve'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pe_ease_3')));
    await t.pump();
    expect((c.timeline.find(id)!.$2 as ShapeElement).keyframes.first.easing, 3);
  });

  testWidgets('Animation sheet: pop in a shape layer', (t) async {
    I18n.lang.value = 'lo';
    await pump(t);
    final c = t.widget<ProTimelineView>(find.byType(ProTimelineView)).c;
    final id = c.addShape('rect')!;
    await t.pump();
    await t.tap(tool('anim'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pe_anim_in_pop')));
    await t.pump();
    final e = c.timeline.find(id)!.$2 as ShapeElement;
    expect(e.keyframes.length, 2);
    expect(e.keyframes.first.t.opacity, 0);
    expect(t.takeException(), isNull);
  });

  testWidgets('Transition sheet: fade between two clips, then apply to all', (t) async {
    I18n.lang.value = 'lo';
    await pump(t);
    final c = t.widget<ProTimelineView>(find.byType(ProTimelineView)).c;
    c.seek(1500);
    c.splitAtPlayhead();
    c.clearSelection();
    c.seek(2500);
    c.splitAtPlayhead();
    c.clearSelection();
    c.seek(1500);
    await t.pumpAndSettle();
    final first = c.timeline.mainTrack!.elements.first.id;
    await t.tap(find.byKey(Key('pe_tr_$first')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pe_tr_fade')));
    await t.pump();
    expect(c.timeline.transitions.single.kind, 'fade');
    await t.tap(find.byKey(const Key('pe_tr_glitch'))); // not exportable yet
    await t.pump();
    expect(c.timeline.transitions.single.kind, 'fade');
    await t.tap(find.byKey(const Key('pe_tr_all')));
    await t.pump();
    expect(c.timeline.transitions.map((x) => x.kind), ['fade', 'fade']);
  });

  testWidgets('export hands the exporter ONE file + removed ranges, then restores', (t) async {
    I18n.lang.value = 'lo';
    SubtitleProject? seen;
    late ProjectProvider provider;
    provider = await pump(t, exportScreen: (ctx) {
      seen = provider.currentProject;
      return const Scaffold(body: Text('export screen'));
    });
    final c = t.widget<ProTimelineView>(find.byType(ProTimelineView)).c;
    c.snapping = false;
    c.trimTo(c.timeline.mainTrack!.elements.single.id, leftEdge: true, ms: 2000); // cut 0–2 s
    await t.pump();
    await t.tap(find.byKey(const Key('pe_export')));
    await t.pumpAndSettle();
    expect(find.text('export screen'), findsOneWidget);
    expect(seen!.clips, isEmpty);
    expect(seen!.removedRanges, [[0, 2000]]);
    expect(seen!.segments.map((s) => s.startTime.inMilliseconds), [4000]); // s1 was cut away
    Navigator.of(t.element(find.text('export screen'))).pop();
    await t.pumpAndSettle();
    expect(provider.currentProject!.clips, isEmpty);
    expect(provider.currentProject!.timelineV2, isNotNull); // the saved project again
  });

  testWidgets('closing saves v1 + the v2 timeline into the provider', (t) async {
    I18n.lang.value = 'lo';
    final provider = await pump(t);
    await scrubBy(t, -240);
    await t.tap(tool('split'));
    await t.pump();
    await t.tap(find.byKey(const Key('pe_close')));
    await t.pumpAndSettle();
    expect(find.text('open'), findsOneWidget); // back on the launcher
    final saved = provider.projects.firstWhere((x) => x.id == 'p1');
    expect(saved.timelineV2, isNotNull);
    expect(saved.clips, isEmpty); // one source → file + removed ranges
    expect((saved.timelineV2!['tracks'] as List).first['elements'].length, 2);
    expect(saved.segments.length, 2);
  });
}

class ProEditorScreenTestHooks {
  final TimelineAudioRenderer renderer;
  final Widget Function(String, String, void Function(List<SubtitleSegment>)) processing;
  final Future<Directory> Function() tempDir;
  ProEditorScreenTestHooks({required this.renderer, required this.processing, required this.tempDir});
}

/// Stands in for ProcessingScreen: returns one subtitle and closes.
class _FakeProcessing extends StatefulWidget {
  final void Function(List<SubtitleSegment>) onResult;
  const _FakeProcessing({required this.onResult});
  @override
  State<_FakeProcessing> createState() => _FakeProcessingState();
}

class _FakeProcessingState extends State<_FakeProcessing> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onResult([
        SubtitleSegment(id: 'ai1', text: 'ສະບາຍດີ ຈາກ AI',
            startTime: const Duration(milliseconds: 400), endTime: const Duration(milliseconds: 1800)),
      ]);
      Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('processing'));
}

/// Wiring-only stand-in (the real renderer's file IO has its own unit tests).
class _StubRenderer extends TimelineAudioRenderer {
  _StubRenderer() : super((_, _) async {});
  @override
  Future<int?> render(ProjectTimeline t, String outPath, String workDir,
      {void Function(double progress)? onProgress}) async {
    onProgress?.call(1);
    return t.mainTrack!.endMs;
  }
}
