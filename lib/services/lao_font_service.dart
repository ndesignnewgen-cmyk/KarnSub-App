import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'custom_font_service.dart';

/// Keeps the editor preview and the native exporter on the SAME font file so
/// the on-screen preview matches the burned-in subtitles.
///
/// Priority for each font family:
///   1. A bundled asset in `assets/fonts/<family>.ttf` (best — variable font,
///      full weight range, identical on every device).
///   2. An Android system Lao font in `/system/fonts/`.
///   3. Google Fonts fallback (handled by the caller in the preview only).
class LaoFontService {
  static final Map<String, String> _previewFamily = {}; // family -> loaded name ('' = none)
  static final Set<String> _loading = {};
  static final Map<String, String?> _exportPathCache = {};

  /// Asset path for a family, or null if that family has no bundled asset slot.
  static String _assetFor(String fontFamily) {
    switch (fontFamily) {
      case 'NotoSerifLao':
        return 'assets/fonts/NotoSerifLao.ttf';
      case 'NotoSansLaoLooped':
        return 'assets/fonts/NotoSansLaoLooped.ttf';
      // ── Thai families ──────────────────────────────────────────────
      case 'NotoSansThai':
        return 'assets/fonts/NotoSansThai.ttf';
      case 'NotoSansThaiLooped':
        return 'assets/fonts/NotoSansThaiLooped.ttf';
      case 'NotoSerifThai':
        return 'assets/fonts/NotoSerifThai.ttf';
      default: // NotoSansLao / Default
        return 'assets/fonts/NotoSansLao.ttf';
    }
  }

  /// True for the bundled Thai font families.
  static bool isThaiFamily(String fontFamily) =>
      fontFamily == 'NotoSansThai' ||
      fontFamily == 'NotoSansThaiLooped' ||
      fontFamily == 'NotoSerifThai';

  static Future<bool> _assetExists(String asset) async {
    try {
      await rootBundle.load(asset);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// System font file the exporter would fall back to (mirrors export logic).
  static String? systemFontPath(String fontFamily) {
    final candidates = <String>[];
    // ── Thai families → prefer Thai system fonts ──────────────────────
    if (isThaiFamily(fontFamily)) {
      if (fontFamily == 'NotoSerifThai') {
        candidates.addAll([
          '/system/fonts/NotoSerifThai-Regular.ttf',
          '/system/fonts/NotoSerifThai.ttf',
        ]);
      }
      if (fontFamily == 'NotoSansThaiLooped') {
        candidates.addAll([
          '/system/fonts/NotoSansThaiLooped-Regular.ttf',
          '/system/fonts/NotoSansThaiLooped.ttf',
        ]);
      }
      candidates.addAll([
        '/system/fonts/NotoSansThai-Regular.ttf',
        '/system/fonts/NotoSansThai.ttf',
        '/system/fonts/NotoSansThaiUI-Regular.ttf',
        '/system/fonts/DroidSansThai.ttf',
        '/system/fonts/Thonburi.ttf',
      ]);
      for (final p in candidates) {
        if (File(p).existsSync()) return p;
      }
      return null;
    }
    if (fontFamily == 'NotoSerifLao') {
      candidates.addAll([
        '/system/fonts/NotoSerifLao-Regular.ttf',
        '/system/fonts/NotoSerifLao.ttf',
      ]);
    }
    if (fontFamily == 'NotoSansLaoLooped') {
      candidates.addAll([
        '/system/fonts/NotoSansLaoLooped-Regular.ttf',
        '/system/fonts/NotoSansLaoLooped.ttf',
      ]);
    }
    candidates.addAll([
      '/system/fonts/NotoSansLao-Regular.ttf',
      '/system/fonts/NotoSansLao.ttf',
      '/system/fonts/DroidSansLao.ttf',
    ]);
    for (final p in candidates) {
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  /// File path the native exporter should use for [fontFamily]. If a bundled
  /// asset exists it is copied to a temp file (native needs a real path);
  /// otherwise the system font path is returned. May be null.
  static Future<String?> resolveExportFontPath(String fontFamily) async {
    // User-imported font → burn with the stored file directly.
    if (CustomFontService.isCustom(fontFamily)) {
      return CustomFontService.exportPath(CustomFontService.idOf(fontFamily));
    }
    if (_exportPathCache.containsKey(fontFamily)) {
      return _exportPathCache[fontFamily];
    }
    String? result;
    final asset = _assetFor(fontFamily);
    if (await _assetExists(asset)) {
      try {
        final bytes = await rootBundle.load(asset);
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/font_${fontFamily.replaceAll('/', '_')}.ttf');
        await f.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        result = f.path;
      } catch (_) {
        result = systemFontPath(fontFamily);
      }
    } else {
      result = systemFontPath(fontFamily);
    }
    _exportPathCache[fontFamily] = result;
    return result;
  }

  /// Flutter family name loaded for preview, or null to use Google Fonts.
  static String? familyFor(String fontFamily) {
    if (CustomFontService.isCustom(fontFamily)) {
      return CustomFontService.previewFamily(CustomFontService.idOf(fontFamily));
    }
    final v = _previewFamily[fontFamily];
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Load the bundled-or-system font into the engine for the preview.
  static Future<void> ensureLoaded(String fontFamily) async {
    // Custom fonts are registered by CustomFontService.init()/import.
    if (CustomFontService.isCustom(fontFamily)) return;
    if (_previewFamily.containsKey(fontFamily) || _loading.contains(fontFamily)) {
      return;
    }
    _loading.add(fontFamily);
    try {
      final family = 'lao_$fontFamily';
      final asset = _assetFor(fontFamily);
      if (await _assetExists(asset)) {
        final loader = FontLoader(family)..addFont(rootBundle.load(asset));
        await loader.load();
        _previewFamily[fontFamily] = family;
        return;
      }
      final sysPath = systemFontPath(fontFamily);
      if (sysPath != null) {
        final bytes = await File(sysPath).readAsBytes();
        final loader = FontLoader(family)
          ..addFont(Future.value(bytes.buffer.asByteData()));
        await loader.load();
        _previewFamily[fontFamily] = family;
        return;
      }
      _previewFamily[fontFamily] = '';
    } catch (_) {
      _previewFamily[fontFamily] = '';
    } finally {
      _loading.remove(fontFamily);
    }
  }
}
