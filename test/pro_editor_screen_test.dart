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
    {Size size = const Size(390, 844), Future<String?> Function(String)? pick}) async {
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
    expect(saved.clips.length, 2); // the split shows in the classic editor too
    expect(saved.segments.length, 2);
  });
}
