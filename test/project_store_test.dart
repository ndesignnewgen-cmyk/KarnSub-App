import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subtitle_app/models/subtitle_style_model.dart';
import 'package:subtitle_app/services/project_store.dart';
import 'package:subtitle_app/services/storage_service.dart';

late Directory tmp;
late Directory dir;

MapEntry<String, Map<String, dynamic>> e(String id, [String name = 'x']) =>
    MapEntry(id, {'id': id, 'name': name});

List<String> names(List<Map<String, dynamic>> l) =>
    l.map((m) => m['name'] as String).toList();

File f(String name) => File('${dir.path}/$name');

List<String> filesIn() =>
    dir.listSync().map((x) => x.uri.pathSegments.last).toList()..sort();

SubtitleProject project(String id, String name) => SubtitleProject(
      id: id,
      name: name,
      selectedStyle: subtitlePresets.first,
      segments: [
        SubtitleSegment(
          id: '$id-s1',
          text: 'ສະບາຍດີ',
          startTime: const Duration(milliseconds: 100),
          endTime: const Duration(milliseconds: 900),
          words: ['ສະບາຍ', 'ດີ'],
          wordTimings: const [
            Duration(milliseconds: 100),
            Duration(milliseconds: 500),
          ],
        ),
      ],
    );

void main() {
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('karnsub_store_');
    dir = Directory('${tmp.path}/projects');
  });
  tearDown(() {
    StorageService.debugStore = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('ProjectStore', () {
    test('save → load keeps every project in order', () async {
      final s = ProjectStore(dir);
      await s.save([e('b', 'B'), e('a', 'A'), e('c', 'C')]);
      final loaded = await ProjectStore(dir).load();
      expect(names(loaded), ['B', 'A', 'C']);
      expect(filesIn(), ['a.json', 'b.json', 'c.json', 'index.json']);
      final j = jsonDecode(f('a.json').readAsStringSync());
      expect(j['schemaVersion'], ProjectStore.schemaVersion);
    });

    test('unchanged projects are not rewritten; changed ones keep a .bak',
        () async {
      final s = ProjectStore(dir);
      await s.save([e('a', 'A1'), e('b', 'B')]);
      await s.save([e('a', 'A1'), e('b', 'B')]);
      expect(f('a.json.bak').existsSync(), isFalse);
      await s.save([e('a', 'A2'), e('b', 'B')]);
      expect(f('a.json.bak').existsSync(), isTrue);
      expect(f('b.json.bak').existsSync(), isFalse);
      expect(names(await ProjectStore(dir).load()), ['A2', 'B']);
    });

    test('deleting a project removes its files', () async {
      final s = ProjectStore(dir);
      await s.save([e('a'), e('b')]);
      await s.save([e('a', 'changed'), e('b')]); // creates a.json.bak
      await s.save([e('b')]);
      expect(filesIn(), ['b.json', 'index.json']);
    });

    test('a broken file costs only that project and is kept aside', () async {
      await ProjectStore(dir).save([e('a', 'A'), e('b', 'B'), e('c', 'C')]);
      f('b.json').writeAsStringSync('{ not json');
      final corrupt = <String>[];
      final loaded =
          await ProjectStore(dir).load(onCorrupt: (id, _) => corrupt.add(id));
      expect(names(loaded), ['A', 'C']);
      expect(corrupt, ['b']);
      expect(filesIn().any((n) => n.startsWith('b.json.corrupt-')), isTrue);
    });

    test('a broken file falls back to its .bak', () async {
      final s = ProjectStore(dir);
      await s.save([e('a', 'old')]);
      await s.save([e('a', 'new')]); // old → a.json.bak
      f('a.json').writeAsStringSync('');
      final loaded = await ProjectStore(dir).load();
      expect(names(loaded), ['old']);
      expect(f('a.json').existsSync(), isTrue); // restored
    });

    test('missing index still loads every project file', () async {
      await ProjectStore(dir).save([e('a', 'A'), e('b', 'B')]);
      f('index.json').deleteSync();
      final loaded = await ProjectStore(dir).load();
      expect(names(loaded)..sort(), ['A', 'B']);
    });

    test('files not in the index are still loaded (after listed ones)',
        () async {
      await ProjectStore(dir).save([e('a', 'A')]);
      f('z.json').writeAsStringSync(jsonEncode({
        'schemaVersion': 1,
        'project': {'id': 'z', 'name': 'Z'},
      }));
      expect(names(await ProjectStore(dir).load()), ['A', 'Z']);
    });

    test('newer-schema files are skipped, untouched and never deleted',
        () async {
      await ProjectStore(dir).save([e('a', 'A')]);
      const future = '{"schemaVersion": 99, "project": {"id": "n"}}';
      f('n.json').writeAsStringSync(future);
      final s = ProjectStore(dir);
      expect(names(await s.load()), ['A']);
      await s.save([e('a', 'A2')]);
      expect(f('n.json').readAsStringSync(), future);
    });

    test('rapid saves: the newest state wins', () async {
      final s = ProjectStore(dir);
      final futures = [
        for (int i = 0; i < 20; i++) s.save([e('a', 'v$i')]),
      ];
      await Future.wait(futures);
      expect(names(await ProjectStore(dir).load()), ['v19']);
    });

    test('quarantine sets a file aside; later saves leave it alone',
        () async {
      final s = ProjectStore(dir);
      await s.save([e('a'), e('b')]);
      await s.quarantine('b');
      await s.save([e('a', 'changed')]);
      expect(filesIn().any((n) => n.startsWith('b.json.corrupt-')), isTrue);
    });

    test('no temp files are left behind', () async {
      final s = ProjectStore(dir);
      await s.save([e('a'), e('b')]);
      await s.save([e('a', 'x2'), e('b', 'y2')]);
      expect(filesIn().where((n) => n.endsWith('.tmp')), isEmpty);
    });
  });

  group('StorageService (migration + decode)', () {
    test('project round-trips through JSON (segments, words, timings)', () {
      final p = project('p1', 'Lao');
      final back = StorageService.projectFromJson(
          jsonDecode(jsonEncode(StorageService.projectToJson(p))));
      expect(back.name, 'Lao');
      final s = back.segments.single;
      expect(s.text, 'ສະບາຍດີ');
      expect(s.words, ['ສະບາຍ', 'ດີ']);
      expect(s.wordTimings!.map((d) => d.inMilliseconds), [100, 500]);
    });

    test('old SharedPreferences data is migrated once, with a backup',
        () async {
      final legacy = jsonEncode([
        StorageService.projectToJson(project('p1', 'One')),
        StorageService.projectToJson(project('p2', 'Two')),
      ]);
      SharedPreferences.setMockInitialValues({'saved_projects': legacy});
      StorageService.debugStore = ProjectStore(dir);

      final loaded = await StorageService.loadProjects();
      expect(loaded.map((p) => p.name), ['One', 'Two']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('saved_projects'), isNull);
      expect(f(ProjectStore.legacyBackupName).readAsStringSync(), legacy);
      expect(f('index.json').existsSync(), isTrue);

      // A fresh start reads the files (no second migration).
      StorageService.debugStore = ProjectStore(dir);
      final again = await StorageService.loadProjects();
      expect(again.map((p) => p.name), ['One', 'Two']);
    });

    test('one broken legacy item does not lose the others', () async {
      final legacy = jsonEncode([
        StorageService.projectToJson(project('p1', 'One')),
        'garbage',
        StorageService.projectToJson(project('p3', 'Three')),
      ]);
      SharedPreferences.setMockInitialValues({'saved_projects': legacy});
      StorageService.debugStore = ProjectStore(dir);
      final loaded = await StorageService.loadProjects();
      expect(loaded.map((p) => p.name), ['One', 'Three']);
    });

    test('totally unreadable legacy data is kept in the backup file',
        () async {
      SharedPreferences.setMockInitialValues({'saved_projects': '{oops'});
      StorageService.debugStore = ProjectStore(dir);
      expect(await StorageService.loadProjects(), isEmpty);
      expect(f(ProjectStore.legacyBackupName).readAsStringSync(), '{oops');
    });

    test('a project that cannot be decoded is quarantined, others load',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = ProjectStore(dir);
      await store.save([
        MapEntry('p1', StorageService.projectToJson(project('p1', 'Good'))),
        const MapEntry('bad', {'id': 'bad', 'name': 'no style'}),
      ]);
      StorageService.debugStore = ProjectStore(dir);
      final loaded = await StorageService.loadProjects();
      expect(loaded.map((p) => p.name), ['Good']);
      await StorageService.saveProjects(loaded);
      expect(filesIn().any((n) => n.startsWith('bad.json.corrupt-')), isTrue);
    });

    test('saveProjects → loadProjects', () async {
      SharedPreferences.setMockInitialValues({});
      StorageService.debugStore = ProjectStore(dir);
      await StorageService.saveProjects(
          [project('a', 'A'), project('b', 'B')]);
      StorageService.debugStore = ProjectStore(dir);
      final loaded = await StorageService.loadProjects();
      expect(loaded.map((p) => p.name), ['A', 'B']);
    });
  });
}
