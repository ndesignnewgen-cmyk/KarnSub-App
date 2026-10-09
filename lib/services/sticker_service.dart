import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Stickers = emoji & icons pulled from the free **Iconify** API and rasterised
/// to PNG so they drop straight into the existing [ImageOverlay] pipeline
/// (preview + native export reuse the bitmap path — no new render code).
///
/// - Emoji: the colourful **Twemoji** set (`twemoji:` prefix). Names below are
///   verified against the live Iconify API.
/// - Icons: free search across every open Iconify set (mostly MIT/Apache),
///   tinted white so monochrome icons read on top of video.
class StickerService {
  static const String _base = 'https://api.iconify.design';

  /// Curated, browse-able emoji grouped into a few tabs. Each value is a list
  /// of Twemoji icon names (the part after `twemoji:`).
  static const Map<String, List<String>> emojiCategories = {
    // ໜ້າ — smileys / faces
    'faces': [
      'grinning-face', 'face-with-tears-of-joy', 'rolling-on-the-floor-laughing',
      'smiling-face-with-heart-eyes', 'smiling-face-with-hearts',
      'smiling-face-with-sunglasses', 'star-struck', 'partying-face',
      'winking-face', 'grinning-face-with-sweat', 'smirking-face',
      'face-with-rolling-eyes', 'thinking-face', 'face-with-monocle',
      'nerd-face', 'zany-face', 'drooling-face', 'sleeping-face',
      'pleading-face', 'loudly-crying-face', 'face-screaming-in-fear',
      'exploding-head', 'enraged-face', 'hot-face', 'cold-face',
      'cowboy-hat-face', 'face-blowing-a-kiss', 'ghost', 'skull',
    ],
    // ມື — hands / gestures
    'gestures': [
      'thumbs-up', 'thumbs-down', 'clapping-hands', 'raising-hands',
      'folded-hands', 'ok-hand', 'victory-hand', 'waving-hand',
      'flexed-biceps', 'eyes',
    ],
    // ເດັ່ນ — emphasis: fire, stars, hearts, money, hype
    'hot': [
      'fire', 'hundred-points', 'collision', 'high-voltage', 'sparkles',
      'star', 'glowing-star', 'party-popper', 'balloon', 'birthday-cake',
      'trophy', 'crown', 'rocket', 'bullseye', 'red-heart', 'beating-heart',
      'sparkling-heart', 'broken-heart', 'money-bag', 'money-with-wings',
      'dollar-banknote',
    ],
    // ສັນຍາລັກ — symbols
    'symbols': [
      'check-mark-button', 'cross-mark', 'check-mark', 'heavy-check-mark',
      'warning', 'red-exclamation-mark', 'double-exclamation-mark',
      'question-mark', 'light-bulb',
    ],
    // ສິ່ງຂອງ — objects / media
    'objects': [
      'camera', 'video-camera', 'musical-note', 'musical-notes', 'headphone',
      'megaphone', 'loudspeaker', 'bell', 'alarm-clock',
    ],
  };

  /// SVG url for a Twemoji emoji name (colourful, no tint).
  static String twemojiSvgUrl(String name) => '$_base/twemoji/$name.svg';

  /// SVG url for an Iconify id ("prefix:name"). [color] tints monochrome icons
  /// (ignored by already-coloured sets like emoji).
  static String iconifySvgUrl(String id, {String? color}) {
    final parts = id.split(':');
    final prefix = parts.first;
    final name = parts.length > 1 ? parts[1] : '';
    final q = color != null ? '?color=${Uri.encodeComponent(color)}' : '';
    return '$_base/$prefix/$name.svg$q';
  }

  /// Free icon search across all Iconify sets → list of "prefix:name" ids.
  static Future<List<String>> searchIcons(String query, {int limit = 60}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    try {
      final uri = Uri.parse('$_base/search')
          .replace(queryParameters: {'query': q, 'limit': '$limit'});
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['icons'] as List?)?.cast<String>() ?? [];
    } catch (_) {
      return [];
    }
  }

  /// Download an SVG (Iconify/Twemoji) and rasterise it to a PNG file in the
  /// `overlays` support dir, returning the absolute path. [size] = target px.
  static Future<String?> downloadAsPng(String svgUrl,
      {int size = 320, String prefix = 'sticker'}) async {
    try {
      final res = await http.get(Uri.parse(svgUrl), headers: {
        'User-Agent': 'KarnSub/1.1 (subtitle app)',
      }).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final svg = utf8.decode(res.bodyBytes);
      if (!svg.contains('<svg')) return null;
      final png = await _rasterize(svg, size);
      if (png == null) return null;

      final supportDir = await getApplicationSupportDirectory();
      final dir = Directory(p.join(supportDir.path, 'overlays'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final dest = p.join(
          dir.path, '${prefix}_${DateTime.now().millisecondsSinceEpoch}.png');
      await File(dest).writeAsBytes(png, flush: true);
      return dest;
    } catch (_) {
      return null;
    }
  }

  /// SVG string → PNG bytes at [target] px (longest side), preserving aspect.
  static Future<Uint8List?> _rasterize(String svg, int target) async {
    ui.Picture? scaled;
    ui.Image? img;
    try {
      final PictureInfo info = await vg.loadPicture(SvgStringLoader(svg), null);
      final ui.Size sz = info.size;
      final double base = sz.width >= sz.height ? sz.width : sz.height;
      final double scale = base <= 0 ? 1.0 : target / base;
      final int w = (sz.width * scale).round().clamp(1, 2048);
      final int h = (sz.height * scale).round().clamp(1, 2048);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(scale);
      canvas.drawPicture(info.picture);
      scaled = recorder.endRecording();
      info.picture.dispose();

      img = await scaled.toImage(w, h);
      final ByteData? bytes =
          await img.toByteData(format: ui.ImageByteFormat.png);
      return bytes?.buffer.asUint8List();
    } catch (_) {
      return null;
    } finally {
      scaled?.dispose();
      img?.dispose();
    }
  }
}
