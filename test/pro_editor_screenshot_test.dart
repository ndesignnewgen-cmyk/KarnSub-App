// Renders the Pro Editor to PNGs for a visual check against design 01/02.
// Run: flutter test test/pro_editor_screenshot_test.dart --dart-define=SHOT_DIR=<dir>
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

const shotDir = String.fromEnvironment('SHOT_DIR');
const materialFonts = String.fromEnvironment('MATERIAL_FONTS');

class _Media extends TapSyncMedia {
  @override
  int get durationMs => 45000;
  @override
  bool get isPlaying => false;
  @override
  double get aspectRatio => 9 / 16;
  @override
  Future<void> init() async {}
  @override
  Future<int> positionMs() async => 0;
  @override
  Future<void> seek(int ms) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> setSpeed(double s) async {}
  @override
  Future<void> setVolume(double v) async {}
  @override
  Widget preview() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF253247), Color(0xFF3A2E28)],
          ),
        ),
      );
  @override
  Future<void> dispose() async {}
  @override
  Future<TapSyncAnalysis> analyze() async => TapSyncAnalysis.empty;
}

Future<void> _font(String family, String file) async {
  final data = File('assets/fonts/$file').readAsBytesSync();
  await (FontLoader(family)..addFont(Future.value(ByteData.sublistView(data)))).load();
}

/// A small JPEG-like frame: solid PNG we write ourselves.
Future<String> _frame(Directory dir, int i, Color c) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 60, 80), Paint()..color = c);
  canvas.drawCircle(Offset(20 + i * 3.0, 40), 14, Paint()..color = const Color(0xFFE9DFD3));
  final img = await rec.endRecording().toImage(60, 80);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  final f = File('${dir.path}/frame_$i.png')..writeAsBytesSync(png!.buffer.asUint8List());
  return f.path;
}

void main() {
  testWidgets('Pro Editor screenshots', timeout: const Timeout(Duration(seconds: 90)), (t) async {
    if (shotDir.isEmpty) return; // only when asked
    final tmp = Directory.systemTemp.createTempSync('karnsub_shot_');
    SharedPreferences.setMockInitialValues({});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.anniekaydee.subtitle_app/tapsync'), (_) async => null);
    I18n.lang.value = 'lo';

    late List<({int ms, String path})> frames;
    await t.runAsync(() async {
      await _font('NotoSansLao', 'NotoSansLao.ttf');
      await _font('monospace', 'NotoSansLao.ttf'); // digits for the time labels
      if (materialFonts.isNotEmpty) {
        final icons = File('$materialFonts/materialicons-regular.otf').readAsBytesSync();
        await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons)))).load();
      }
      frames = [
        for (var i = 0; i < 12; i++)
          (ms: i * 1000, path: await _frame(tmp, i, i < 6 ? const Color(0xFF2E3B52) : const Color(0xFF4A3A55))),
      ];
      // Decode now (real time) so the screen finds them in the image cache.
      for (final fr in frames.map((x) => x.path).toSet()) {
        final done = Completer<void>();
        FileImage(File(fr)).resolve(ImageConfiguration.empty).addListener(
            ImageStreamListener((_, _) { if (!done.isCompleted) done.complete(); }));
        await done.future;
      }
    });

    File f(String n) => File('${tmp.path}/$n')..writeAsStringSync('x');
    final p = SubtitleProject(
      id: 'p',
      name: 'Shot',
      videoPath: f('a.mp4').path,
      videoDuration: const Duration(seconds: 12),
      selectedStyle: subtitlePresets.first,
      bgMusicPath: f('lofi.mp3').path,
      bgMusicDuck: true,
      aiVoicePath: f('voice.wav').path,
      aiVoiceDurationMs: 7000,
      segments: [
        for (final (i, s) in ['ສະບາຍດີ', 'ມື້ນີ້ພາມາ', 'ຊີມກາເຟ', 'ລົດຊາດເຂັ້ມ'].indexed)
          SubtitleSegment(
              id: 's$i',
              text: s,
              startTime: Duration(milliseconds: 300 + i * 1100),
              endTime: Duration(milliseconds: 1250 + i * 1100)),
      ],
      imageOverlays: [
        ImageOverlay(id: 'st', path: f('st.png').path, startTime: const Duration(milliseconds: 200),
            endTime: const Duration(milliseconds: 2400)),
      ],
      zoomEffects: [
        ZoomEffect(id: 'z', startTime: const Duration(milliseconds: 600), endTime: const Duration(milliseconds: 1400)),
      ],
      sfxBlocks: [
        SfxBlock(id: 'x1', type: SfxType.pop, startTime: const Duration(milliseconds: 700)),
        SfxBlock(id: 'x2', type: SfxType.ding, startTime: const Duration(milliseconds: 3500)),
      ],
    );
    debugPrint('SHOT: saving');
    await t.runAsync(() async {
      // Created in real time: its save queue must not live on the fake clock.
      StorageService.debugStore = ProjectStore(Directory('${tmp.path}/projects'));
      await StorageService.saveProjects([p]);
    });
    debugPrint('SHOT: saved');
    final provider = ProjectProvider();
    await t.runAsync(provider.loadFromStorage);
    provider.setCurrentProject(provider.projects.single);

    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'NotoSansLao', brightness: Brightness.dark),
          home: ProEditorScreen(
            mediaFactory: (_) => _Media(),
            thumbnailLoader: (_) async => frames,
            pickFile: (_) async => null,
            probeDurationMs: (_) async => 3000,
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    debugPrint('SHOT: pumped');
    final c = t.widget<ProTimelineView>(find.byType(ProTimelineView)).c;
    c.seek(2600);
    c.splitAtPlayhead();
    c.clearSelection();
    c.seek(2000);
    await t.pumpAndSettle();

    Future<void> shot(String name) async {
      await t.runAsync(() async {
        debugPrint('SHOT: precache');
      });
      await t.pumpAndSettle();
      await t.runAsync(() async {
        debugPrint('SHOT: toImage');
        final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await boundary.toImage(pixelRatio: 2);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory(shotDir).createSync(recursive: true);
        File('$shotDir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    debugPrint('SHOT: before shot 1');
    await shot('pe_01_main');
    debugPrint('SHOT: after shot 1');
    // Design 02: a clip selected.
    c.select(c.timeline.mainTrack!.elements[1].id);
    await t.pumpAndSettle();
    await shot('pe_02_selected');
    StorageService.debugStore = null;
  });
}
