import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A user-imported font file (.ttf/.otf) that lives in the app's storage and is
/// available both in the editor preview and the native video exporter.
class CustomFont {
  final String id; // unique key; stored on a project as `custom:<id>`
  final String name; // display name (the original file name, no extension)
  final String path; // absolute file path inside the app's support directory

  CustomFont({required this.id, required this.name, required this.path});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'path': path};

  factory CustomFont.fromJson(Map<String, dynamic> j) => CustomFont(
        id: j['id'] as String,
        name: j['name'] as String,
        path: j['path'] as String,
      );
}

/// Manages fonts the user imports from their device, CapCut-style.
///
/// Files are copied into `<appSupport>/custom_fonts/` so they survive app
/// restarts, the metadata list is persisted in SharedPreferences, and each font
/// is registered with the Flutter engine (via [FontLoader]) for the preview.
/// The exporter uses the stored file path directly.
class CustomFontService {
  static const _prefsKey = 'custom_fonts_v1';
  static const familyPrefix = 'customfont_';
  static const idPrefix = 'custom:';

  static final List<CustomFont> _fonts = [];
  static final Map<String, String> _loaded = {}; // id -> engine family ('' = failed)
  static bool _inited = false;

  static List<CustomFont> get fonts => List.unmodifiable(_fonts);

  static bool isCustom(String fontFamily) => fontFamily.startsWith(idPrefix);
  static String idOf(String fontFamily) => fontFamily.substring(idPrefix.length);
  static String familyKey(String id) => '$idPrefix$id';

  static CustomFont? byId(String id) {
    for (final f in _fonts) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Engine family registered for the preview, or null if not loaded yet.
  static String? previewFamily(String id) {
    final v = _loaded[id];
    return (v == null || v.isEmpty) ? null : v;
  }

  /// File path the native exporter should burn with, or null if missing.
  static String? exportPath(String id) {
    final f = byId(id);
    if (f == null) return null;
    return File(f.path).existsSync() ? f.path : null;
  }

  /// Load the saved font list and register every font with the engine.
  static Future<void> init() async {
    if (_inited) return;
    _inited = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List<dynamic>)
            .map((j) => CustomFont.fromJson(j as Map<String, dynamic>))
            .where((f) => File(f.path).existsSync())
            .toList();
        _fonts
          ..clear()
          ..addAll(list);
      } catch (_) {}
    }
    for (final f in _fonts) {
      await _register(f);
    }
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_fonts.map((f) => f.toJson()).toList()),
    );
  }

  /// Register a font file with the Flutter engine for the preview.
  static Future<void> _register(CustomFont f) async {
    if (_loaded.containsKey(f.id)) return;
    try {
      final bytes = await File(f.path).readAsBytes();
      final family = '$familyPrefix${f.id}';
      final loader = FontLoader(family)
        ..addFont(Future.value(bytes.buffer.asByteData()));
      await loader.load();
      _loaded[f.id] = family;
    } catch (_) {
      _loaded[f.id] = '';
    }
  }

  /// Open the system picker, import the chosen .ttf/.otf, register it and save.
  /// Returns the imported font, or null if the user cancelled / it failed.
  static Future<CustomFont?> importFromPicker() async {
    // Use FileType.any then validate the extension ourselves — many Android
    // file providers reject the .ttf/.otf custom filter ("Unsupported filter").
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.single;
    final srcPath = picked.path;
    if (srcPath == null) return null;

    final ext = p.extension(srcPath).toLowerCase();
    if (ext != '.ttf' && ext != '.otf') {
      throw const FormatException('ກະລຸນາເລືອກໄຟລ໌ .ttf ຫຼື .otf ເທົ່ານັ້ນ');
    }

    final supportDir = await getApplicationSupportDirectory();
    final fontsDir = Directory(p.join(supportDir.path, 'custom_fonts'));
    if (!fontsDir.existsSync()) fontsDir.createSync(recursive: true);

    final baseName = p.basenameWithoutExtension(srcPath);
    final id = '${DateTime.now().millisecondsSinceEpoch}';
    final destPath = p.join(fontsDir.path, '$id$ext');
    await File(srcPath).copy(destPath);

    final font = CustomFont(id: id, name: baseName, path: destPath);
    await _register(font);
    _fonts.insert(0, font);
    await _persist();
    return font;
  }

  /// Remove an imported font (deletes the file + metadata).
  static Future<void> remove(String id) async {
    final f = byId(id);
    if (f == null) return;
    try {
      final file = File(f.path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
    _fonts.removeWhere((e) => e.id == id);
    _loaded.remove(id);
    await _persist();
  }
}
