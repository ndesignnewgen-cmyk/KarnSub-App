import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_app/i18n/i18n.dart';
import 'package:subtitle_app/models/subtitle_style_model.dart';
import 'package:subtitle_app/providers/project_provider.dart';
import 'package:subtitle_app/screens/tap_sync_screen.dart';
import 'package:subtitle_app/services/tap_sync_media.dart';
import 'package:subtitle_app/widgets/tap_sync_widgets.dart';

SubtitleProject _project({int segments = 3}) => SubtitleProject(
      id: 'p1',
      name: 'test',
      selectedStyle: subtitlePresets.first,
      segments: [
        for (int i = 0; i < segments; i++)
          SubtitleSegment(
            id: 's$i',
            text: 'ມື້ນີ້ພາມາຊີມກາເຟສົດ $i',
            startTime: Duration(milliseconds: i * 2000),
            endTime: Duration(milliseconds: i * 2000 + 1500),
          ),
      ],
    );

Future<void> _pump(WidgetTester tester, SubtitleProject p,
    {Size size = const Size(360, 780)}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final provider = ProjectProvider()..setCurrentProject(p);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: provider,
    child: const MaterialApp(home: TapSyncScreen()),
  ));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Native Tap Sync bridge (volume keys / Bluetooth) isn't there in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.anniekaydee.subtitle_app/tapsync'),
      (call) async => call.method == 'isBluetoothOutput' ? false : null,
    );
  });

  for (final lang in ['lo', 'th']) {
    testWidgets('setup screen renders without overflow ($lang)', (t) async {
      I18n.lang.value = lang;
      await _pump(t, _project());
      expect(find.text(tr('tap.title')), findsOneWidget);
      expect(find.text(tr('tap.mode.hold')), findsOneWidget);
      // No video in this project → the error is shown, start is disabled.
      expect(find.text(tr('tap.noVideo')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('small phone (320 wide) still lays out', (t) async {
    I18n.lang.value = 'lo';
    await _pump(t, _project(), size: const Size(320, 640));
    await t.drag(find.byType(ListView).first, const Offset(0, -800));
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('no subtitles → paste-script source preselected', (t) async {
    I18n.lang.value = 'lo';
    await _pump(t, _project(segments: 0));
    expect(find.text(tr('tap.script.next')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('word mode is PRO-gated for free users', (t) async {
    I18n.lang.value = 'lo';
    await _pump(t, _project());
    await t.tap(find.text(tr('tap.unit.word')));
    await t.pumpAndSettle();
    expect(find.text(tr('pro.dialogBody')), findsOneWidget);
  });

  testWidgets('TapBigButton reports press and release', (t) async {
    var downs = 0, ups = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: TapBigButton(
            active: false,
            color: Colors.green,
            icon: Icons.mic,
            title: 'hold',
            subtitle: '',
            onDown: () => downs++,
            onUp: () => ups++,
          ),
        ),
      ),
    ));
    final g = await t.startGesture(t.getCenter(find.byType(TapBigButton)));
    expect(downs, 1);
    expect(ups, 0);
    await g.up();
    expect(ups, 1);
  });

  flowTests();

  test('fmtTapTime', () {
    expect(fmtTapTime(7320), '07.32');
    expect(fmtTapTime(65400), '1:05.40');
    expect(fmtTapTime(0), '00.00');
  });
}

/// Fake player: the test moves [pos] by hand.
class FakeMedia extends TapSyncMedia {
  int pos = 0;
  bool playing = false;
  double speed = 1;
  final int dur;
  FakeMedia({this.dur = 10000});

  @override
  int get durationMs => dur;
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
  Future<void> setSpeed(double s) async => speed = s;
  @override
  Future<void> setVolume(double v) async {}
  @override
  Widget preview() => const SizedBox(
      width: 90, height: 160, child: ColoredBox(color: Colors.black));
  @override
  Future<void> dispose() async {}
  @override
  Future<TapSyncAnalysis> analyze() async => TapSyncAnalysis.empty;
}

/// Hosts the screen behind a launcher route so it can pop a result.
Future<(ProjectProvider, FakeMedia, List<bool?>)> _launch(
    WidgetTester t, SubtitleProject p) async {
  t.view.physicalSize = const Size(390, 844) * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final provider = ProjectProvider()..setCurrentProject(p);
  final media = FakeMedia();
  final results = <bool?>[];
  await t.pumpWidget(ChangeNotifierProvider.value(
    value: provider,
    child: MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await Navigator.push<bool>(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => TapSyncScreen(mediaFactory: (_) => media),
                  ),
                );
                results.add(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  return (provider, media, results);
}

/// Move the fake player to [ms] and let the screen's 100 ms poll pick it up.
Future<void> _at(WidgetTester t, FakeMedia m, int ms) async {
  m.pos = ms;
  await t.pump(const Duration(milliseconds: 150));
}

Future<void> _startRecording(WidgetTester t) async {
  await t.tap(find.text(tr('tap.startAt', {'n': 1})));
  await t.pump();
  await t.pump(const Duration(milliseconds: 2500)); // 3-2-1 countdown
}

void _near(int actual, int expected, {int tol = 40}) =>
    expect((actual - expected).abs() <= tol, isTrue,
        reason: 'expected ≈$expected, got $actual');

void flowTests() {
  // Default settings: hold mode, 0.75×, offset −180 ms → −135 ms of media.
  testWidgets('hold mode: record 2 lines → review → save (1 undo step)',
      (t) async {
    I18n.lang.value = 'lo';
    final (provider, media, results) = await _launch(t, _project(segments: 2));
    await _startRecording(t);
    expect(media.playing, isTrue);
    expect(media.speed, 0.75);

    final btn = find.byType(TapBigButton);
    await _at(t, media, 1000);
    var g = await t.startGesture(t.getCenter(btn));
    await _at(t, media, 2500);
    await g.up();
    await _at(t, media, 3000);
    g = await t.startGesture(t.getCenter(btn));
    await _at(t, media, 4200);
    await g.up();
    await t.pump(const Duration(milliseconds: 300));

    expect(find.text(tr('tap.review.title')), findsOneWidget);
    expect(media.speed, 1.0); // back to normal speed for review
    expect(t.takeException(), isNull);

    await t.tap(find.text(tr('common.save')));
    await t.pumpAndSettle();
    expect(results, [true]);
    final segs = provider.currentProject!.segments;
    _near(segs[0].startTime.inMilliseconds, 865);
    _near(segs[0].endTime.inMilliseconds, 2365);
    _near(segs[1].startTime.inMilliseconds, 2865);
    _near(segs[1].endTime.inMilliseconds, 4065);
    expect(provider.canUndo, isTrue);
    provider.undo();
    expect(provider.currentProject!.segments[0].startTime.inMilliseconds, 0);
  });

  testWidgets('hold mode: back button undoes a line and rewinds 2 s',
      (t) async {
    I18n.lang.value = 'lo';
    final (_, media, _) = await _launch(t, _project(segments: 3));
    await _startRecording(t);
    final btn = find.byType(TapBigButton);
    await _at(t, media, 5000);
    final g = await t.startGesture(t.getCenter(btn));
    await _at(t, media, 6000);
    await g.up();
    await t.pump();
    expect(find.text('2 / 3'), findsOneWidget);

    await t.tap(find.text(tr('tap.rec.back')));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('1 / 3'), findsOneWidget);
    _near(media.pos, 3000); // 5000 − 2000
    expect(t.takeException(), isNull);
  });

  testWidgets('tap mode: N+1 taps chain the lines', (t) async {
    SharedPreferences.setMockInitialValues({'tapsync.mode': 'tap'});
    I18n.lang.value = 'lo';
    final (provider, media, _) = await _launch(t, _project(segments: 2));
    await _startRecording(t);
    final btn = find.byType(TapBigButton);
    for (final ms in [1000, 2500, 4000]) {
      await _at(t, media, ms);
      await t.tap(btn);
    }
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(tr('tap.review.title')), findsOneWidget);
    await t.tap(find.text(tr('common.save')));
    await t.pumpAndSettle();
    final segs = provider.currentProject!.segments;
    _near(segs[0].startTime.inMilliseconds, 865);
    _near(segs[0].endTime.inMilliseconds, 2365);
    _near(segs[1].startTime.inMilliseconds, 2365);
    _near(segs[1].endTime.inMilliseconds, 3865);
  });

  testWidgets('review: +50 ms nudge changes the saved time', (t) async {
    I18n.lang.value = 'lo';
    final (provider, media, _) = await _launch(t, _project(segments: 1));
    await _startRecording(t);
    final btn = find.byType(TapBigButton);
    await _at(t, media, 2000);
    final g = await t.startGesture(t.getCenter(btn));
    await _at(t, media, 4000);
    await g.up();
    await t.pump(const Duration(milliseconds: 300));
    // First chevron_right = start +50 ms.
    await t.tap(find.byIcon(Icons.chevron_right).first);
    await t.pump();
    await t.tap(find.text(tr('common.save')));
    await t.pumpAndSettle();
    _near(provider.currentProject!.segments[0].startTime.inMilliseconds,
        1865 + 50);
  });

  testWidgets('karaoke (PRO): tap each word → wordTimings saved', (t) async {
    SharedPreferences.setMockInitialValues({
      'pro_expiry_date':
          DateTime.now().add(const Duration(days: 30)).toIso8601String(),
    });
    I18n.lang.value = 'lo';
    final p = _project(segments: 1);
    p.segments[0]
      ..text = 'ມື້ນີ້ພາມາຊີມ'
      ..words = ['ມື້ນີ້', 'ພາ', 'ມາ', 'ຊີມ'];
    final (provider, media, _) = await _launch(t, p);
    await t.tap(find.text(tr('tap.unit.word')));
    await t.pump();
    expect(find.text(tr('pro.dialogBody')), findsNothing); // PRO → allowed
    // Karaoke defaults to tap mode.
    expect(find.text(tr('tap.mode.tapHint')), findsOneWidget);
    await _startRecording(t);
    expect(find.text('ມື້ນີ້'), findsOneWidget); // word chips shown

    final btn = find.byType(TapBigButton);
    for (final ms in [1000, 1400, 1700, 2100, 2600]) {
      await _at(t, media, ms);
      await t.tap(btn);
    }
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(tr('tap.review.title')), findsOneWidget);
    await t.tap(find.text(tr('common.save')));
    await t.pumpAndSettle();

    final s = provider.currentProject!.segments[0];
    expect(s.words, ['ມື້ນີ້', 'ພາ', 'ມາ', 'ຊີມ']);
    final wt = s.wordTimings!.map((d) => d.inMilliseconds).toList();
    for (final (i, want) in [865, 1265, 1565, 1965].indexed) {
      _near(wt[i], want);
    }
    _near(s.startTime.inMilliseconds, 865);
    _near(s.endTime.inMilliseconds, 2465);
    expect(t.takeException(), isNull);
  });

  testWidgets('paste script → split → tap 1 line → rest filled after it',
      (t) async {
    I18n.lang.value = 'lo';
    final (provider, media, _) = await _launch(t, _project(segments: 0));
    await t.tap(find.text(tr('tap.script.next')));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'ສະບາຍດີ. ມື້ນີ້ອາກາດດີ!\nໄປໃສມາ?');
    await t.tap(find.text(tr('tap.script.split')));
    await t.pumpAndSettle();
    expect(find.text(tr('tap.script.lines', {'n': 3})), findsOneWidget);
    await t.tap(find.text(tr('tap.startAt', {'n': 1})).last);
    await t.pump();
    await t.pump(const Duration(milliseconds: 2500));

    final btn = find.byType(TapBigButton);
    await _at(t, media, 1000);
    final g = await t.startGesture(t.getCenter(btn));
    await _at(t, media, 2000);
    await g.up();
    await t.pump();
    await t.tap(find.text(tr('tap.rec.finish')));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(tr('tap.badge.none')), findsNWidgets(2));
    await t.tap(find.text(tr('common.save')));
    await t.pumpAndSettle();

    final segs = provider.currentProject!.segments;
    expect(segs.map((s) => s.text).toList(),
        ['ສະບາຍດີ.', 'ມື້ນີ້ອາກາດດີ!', 'ໄປໃສມາ?']);
    _near(segs[0].startTime.inMilliseconds, 865);
    expect(segs[1].startTime >= segs[0].endTime, isTrue);
    expect(segs[2].startTime >= segs[1].endTime, isTrue);
  });
}
