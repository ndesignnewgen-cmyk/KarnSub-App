import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// File-based project storage — one JSON file per project.
///
/// Replaces the old single SharedPreferences string, where one parse error
/// returned [] and every project was lost.
///
/// Layout in [dir]:
///   index.json          {"schemaVersion": 1, "order": [id, ...]}
///   `<id>.json`           {"schemaVersion": 1, "project": {...}}
///   `<id>.json.bak`       previous version of the project (fallback)
///   `<id>.json.corrupt-*` a file that could not be read (kept, never deleted)
///   legacy_prefs_backup.json   raw copy of the old SharedPreferences data
///
/// Safety rules:
///   * every write goes to a temp file first, then is renamed into place, so a
///     crash mid-write leaves the old file intact;
///   * a broken file only costs THAT project (and we try its .bak first);
///   * project files not listed in the index are still loaded (nothing is
///     dropped if the index write was interrupted).
///
/// The store works on already-encoded project maps; turning them into
/// [SubtitleProject]s is the caller's job (see StorageService).
class ProjectStore {
  static const int schemaVersion = 1;
  static const _indexName = 'index.json';
  static const legacyBackupName = 'legacy_prefs_backup.json';

  final Directory dir;
  ProjectStore(this.dir);

  /// Last JSON written per id — only changed projects are rewritten.
  final Map<String, String> _written = {};
  List<String> _writtenOrder = const [];

  Future<void> _queue = Future.value();
  List<MapEntry<String, String>>? _pending;

  File _file(String id) => File('${dir.path}/$id.json');
  File get _index => File('${dir.path}/$_indexName');

  bool get hasIndex => _index.existsSync();

  static String _safeId(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  // ── Writing ──────────────────────────────────────────────────────────────

  static Future<void> writeAtomic(File f, String content,
      {bool keepBackup = false}) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    if (keepBackup && await f.exists()) {
      final bak = File('${f.path}.bak');
      try {
        if (await bak.exists()) await bak.delete();
        await f.rename(bak.path);
      } catch (_) {
        // A missing backup is not worth failing the save over.
      }
    }
    await tmp.rename(f.path);
  }

  /// Save [projects] (id → encoded project map, in display order).
  /// Calls are serialized; if saves arrive faster than the disk, only the
  /// newest state is written (intermediate states are skipped).
  Future<void> save(List<MapEntry<String, Map<String, dynamic>>> projects) {
    // Encode now, so later in-memory edits can't leak into this save.
    _pending = [
      for (final e in projects)
        MapEntry(
          _safeId(e.key),
          jsonEncode({'schemaVersion': schemaVersion, 'project': e.value}),
        ),
    ];
    final done = Completer<void>();
    _queue = _queue.then((_) async {
      final batch = _pending;
      _pending = null;
      if (batch != null) {
        try {
          await _writeBatch(batch);
        } catch (e) {
          debugPrint('[ProjectStore] save failed: $e');
        }
      }
      done.complete();
    });
    return done.future;
  }

  Future<void> _writeBatch(List<MapEntry<String, String>> batch) async {
    await dir.create(recursive: true);
    final ids = <String>[];
    for (final e in batch) {
      ids.add(e.key);
      if (_written[e.key] == e.value) continue;
      await writeAtomic(_file(e.key), e.value, keepBackup: true);
      _written[e.key] = e.value;
    }
    if (!listEquals(ids, _writtenOrder) || !hasIndex) {
      await writeAtomic(
        _index,
        jsonEncode({'schemaVersion': schemaVersion, 'order': ids}),
      );
      _writtenOrder = List.of(ids);
    }
    // Projects deleted by the user: remove their files (and backups).
    final keep = ids.toSet();
    for (final id in _written.keys.toList()) {
      if (keep.contains(id)) continue;
      _written.remove(id);
      for (final f in [_file(id), File('${_file(id).path}.bak')]) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  /// Wait for all queued saves (tests, app shutdown).
  Future<void> flush() => _queue;

  // ── Reading ──────────────────────────────────────────────────────────────

  /// Load every readable project map, in index order (unlisted files last,
  /// oldest first by file time). [onCorrupt] is told about each file that
  /// had to be set aside.
  Future<List<Map<String, dynamic>>> load({
    void Function(String id, Object error)? onCorrupt,
  }) async {
    if (!await dir.exists()) return [];
    var order = <String>[];
    try {
      final j = jsonDecode(await _index.readAsString()) as Map<String, dynamic>;
      order = (j['order'] as List).map((e) => e.toString()).toList();
    } catch (_) {
      // Missing/broken index → fall back to whatever project files exist.
    }
    final onDisk = <String, File>{};
    await for (final f in dir.list()) {
      if (f is! File) continue;
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.json') ||
          name == _indexName ||
          name == legacyBackupName) {
        continue;
      }
      onDisk[name.substring(0, name.length - 5)] = f;
    }
    final unlisted = onDisk.keys.where((id) => !order.contains(id)).toList()
      ..sort((a, b) => onDisk[a]!
          .lastModifiedSync()
          .compareTo(onDisk[b]!.lastModifiedSync()));
    final ids = [...order.where(onDisk.containsKey), ...unlisted];

    final out = <Map<String, dynamic>>[];
    for (final id in ids) {
      final m = await _readProject(id, onCorrupt);
      if (m != null) out.add(m);
    }
    _writtenOrder = List.of(ids.where((id) => _written.containsKey(id)));
    return out;
  }

  Future<Map<String, dynamic>?> _readProject(
      String id, void Function(String, Object)? onCorrupt) async {
    final f = _file(id);
    try {
      final raw = await f.readAsString();
      final m = _unwrap(raw);
      _written[id] = raw;
      return m;
    } on NewerSchemaException catch (e) {
      // Written by a newer app version: leave the file alone (not corrupt).
      // It is not in [_written], so saves will never touch or delete it.
      onCorrupt?.call(id, e);
      return null;
    } catch (e) {
      onCorrupt?.call(id, e);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      try {
        await f.rename('${f.path}.corrupt-$stamp');
      } catch (_) {}
      // Fall back to the previous version.
      final bak = File('${f.path}.bak');
      try {
        if (await bak.exists()) {
          final raw = await bak.readAsString();
          final m = _unwrap(raw);
          await writeAtomic(f, raw);
          _written[id] = raw;
          return m;
        }
      } catch (e2) {
        onCorrupt?.call('$id.bak', e2);
      }
      return null;
    }
  }

  static Map<String, dynamic> _unwrap(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final v = (j['schemaVersion'] as num?)?.toInt() ?? 0;
    if (v > schemaVersion) throw NewerSchemaException(v);
    return j['project'] as Map<String, dynamic>;
  }

  /// Set a project file aside (renamed to `.corrupt-*`, never deleted) when
  /// the caller can't turn its map into a project. It is forgotten by the
  /// store, so later saves won't delete it either.
  Future<void> quarantine(String id) async {
    final safe = _safeId(id);
    _written.remove(safe);
    final f = _file(safe);
    try {
      if (await f.exists()) {
        await f.rename(
            '${f.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      }
    } catch (_) {}
  }
}

class NewerSchemaException implements Exception {
  final int version;
  NewerSchemaException(this.version);
  @override
  String toString() =>
      'project schema $version is newer than ${ProjectStore.schemaVersion}';
}
