import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'timeline_model.dart';

/// Draws text layers, shapes and masked images with dart:ui — the SAME code
/// paints the Pro Editor preview and the PNGs handed to the exporter (which
/// composites image overlays), so what you see is what you export. Text goes
/// through Flutter's shaper, so Lao vowels/tones stack correctly.

// ── Text ───────────────────────────────────────────────────────────────────

/// Text style keys (TextElement.style):
///   font: NotoSansLao | NotoSerifLao | NotoSansLaoLooped
///   color, bg, stroke: ARGB ints (bg/stroke optional)
///   align: left | center | right    bold, italic, shadow: bool
///   spacing: letter spacing (em)    size: nominal px on a 1080-wide canvas
class TextLayer {
  static const double refSize = 96; // drawing size; the overlay scales it
  final TextElement e;
  late final TextPainter _tp;
  late final TextPainter? _strokeTp;
  late final double pad;

  TextLayer(this.e) {
    final s = e.style;
    final color = Color((s['color'] as num?)?.toInt() ?? 0xFFFFFFFF);
    final stroke = (s['stroke'] as num?)?.toInt();
    TextStyle style(Paint? fg) => TextStyle(
          fontFamily: s['font'] as String? ?? 'NotoSansLao',
          fontSize: refSize,
          height: 1.25,
          fontWeight: s['bold'] == true ? FontWeight.w800 : FontWeight.w600,
          fontStyle: s['italic'] == true ? FontStyle.italic : FontStyle.normal,
          letterSpacing: ((s['spacing'] as num?)?.toDouble() ?? 0) * refSize,
          color: fg == null ? color : null,
          foreground: fg,
          shadows: fg == null && s['shadow'] == true
              ? const [Shadow(blurRadius: 10, offset: Offset(0, 4), color: Color(0xAA000000))]
              : null,
        );
    final align = switch (s['align']) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.center,
    };
    _tp = TextPainter(
      text: TextSpan(text: e.text.isEmpty ? ' ' : e.text, style: style(null)),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    _strokeTp = stroke == null
        ? null
        : (TextPainter(
            text: TextSpan(
              text: e.text.isEmpty ? ' ' : e.text,
              style: style(Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = refSize * 0.12
                ..strokeJoin = StrokeJoin.round
                ..color = Color(stroke)),
            ),
            textAlign: align,
            textDirection: TextDirection.ltr,
          )..layout());
    pad = s['bg'] != null ? refSize * 0.35 : refSize * 0.15;
  }

  /// Natural size at [refSize].
  Size get size => Size(_tp.width + pad * 2, _tp.height + pad * 2);

  /// Width as a fraction of a 1080-wide canvas at the nominal font size —
  /// the starting `transform.scale` for a new/edited text layer.
  double naturalFraction() {
    final nominal = (e.style['size'] as num?)?.toDouble() ?? 64;
    return (size.width * nominal / refSize / 1080).clamp(0.05, 1.5);
  }

  void paint(Canvas canvas, Size box) {
    final sz = size;
    final k = math.min(box.width / sz.width, box.height / sz.height);
    canvas.save();
    canvas.translate((box.width - sz.width * k) / 2, (box.height - sz.height * k) / 2);
    canvas.scale(k);
    final bg = (e.style['bg'] as num?)?.toInt();
    if (bg != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & sz, Radius.circular(refSize * 0.3)),
        Paint()..color = Color(bg),
      );
    }
    _strokeTp?.paint(canvas, Offset(pad, pad));
    _tp.paint(canvas, Offset(pad, pad));
    canvas.restore();
  }
}

// ── Shapes ─────────────────────────────────────────────────────────────────

const shapeKinds = ['rect', 'ellipse', 'pentagon', 'star', 'arrow'];

Path shapePath(String kind, Rect r) {
  final c = r.center;
  final rad = math.min(r.width, r.height) / 2;
  Path poly(int n, {double inner = 0, double rot = -math.pi / 2}) {
    final p = Path();
    final pts = inner > 0 ? n * 2 : n;
    for (var i = 0; i < pts; i++) {
      final rr = inner > 0 && i.isOdd ? rad * inner : rad;
      final a = rot + i * 2 * math.pi / pts;
      final o = Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a));
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }

  switch (kind) {
    case 'ellipse':
      return Path()..addOval(r);
    case 'pentagon':
      return poly(5);
    case 'star':
      return poly(5, inner: 0.45);
    case 'arrow':
      final h = r.height, w = r.width;
      return Path()
        ..moveTo(r.left, r.top + h * 0.38)
        ..lineTo(r.left + w * 0.6, r.top + h * 0.38)
        ..lineTo(r.left + w * 0.6, r.top + h * 0.18)
        ..lineTo(r.right, r.top + h * 0.5)
        ..lineTo(r.left + w * 0.6, r.top + h * 0.82)
        ..lineTo(r.left + w * 0.6, r.top + h * 0.62)
        ..lineTo(r.left, r.top + h * 0.62)
        ..close();
    default:
      return Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(rad * 0.12)));
  }
}

void paintShape(Canvas canvas, Size box, ShapeElement e) {
  final inset = e.strokeWidth > 0 ? e.strokeWidth * box.width / 100 : 0.0;
  final r = (Offset.zero & box).deflate(inset / 2 + 1);
  final path = shapePath(e.shape, r);
  canvas.drawPath(path, Paint()..color = Color(e.fillColor));
  if (e.strokeWidth > 0) {
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = inset
          ..strokeJoin = StrokeJoin.round
          ..color = Color(e.strokeColor));
  }
}

// ── Masks ──────────────────────────────────────────────────────────────────

/// Mask shapes the exporter can bake into an image (design screen 04).
const maskKinds = ['none', 'rect', 'ellipse', 'heart', 'star', 'diamond', 'split', 'band'];

Path maskPath(MaskSpec m, Size s) {
  final side = math.min(s.width, s.height) * m.size.clamp(0.05, 1.0);
  final c = Offset(s.width / 2, s.height / 2);
  final r = Rect.fromCenter(center: c, width: side, height: side);
  Path p;
  switch (m.shape) {
    case 'rect':
      p = Path()..addRect(Rect.fromCenter(center: c, width: s.width * m.size, height: s.height * m.size));
    case 'ellipse':
      p = Path()..addOval(r);
    case 'heart':
      final w = r.width, h = r.height, x = r.left, y = r.top;
      p = Path()
        ..moveTo(x + w / 2, y + h * 0.95)
        ..cubicTo(x - w * 0.15, y + h * 0.55, x + w * 0.05, y - h * 0.05, x + w / 2, y + h * 0.25)
        ..cubicTo(x + w * 0.95, y - h * 0.05, x + w * 1.15, y + h * 0.55, x + w / 2, y + h * 0.95)
        ..close();
    case 'star':
      p = shapePath('star', r);
    case 'diamond':
      p = Path()
        ..moveTo(c.dx, r.top)
        ..lineTo(r.right, c.dy)
        ..lineTo(c.dx, r.bottom)
        ..lineTo(r.left, c.dy)
        ..close();
    case 'split':
      p = Path()..addRect(Rect.fromLTWH(0, 0, s.width * m.size, s.height));
    case 'band':
      final bh = s.height * m.size * 0.6;
      p = Path()..addRect(Rect.fromLTWH(0, c.dy - bh / 2, s.width, bh));
    default:
      p = Path()..addRect(Offset.zero & s);
  }
  if (m.rotation != 0) {
    final rot = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..rotateZ(m.rotation * math.pi / 180)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
    p = p.transform(rot.storage);
  }
  return p;
}

/// Draw [img] into [box] keeping only what the mask lets through (feathered,
/// optionally inverted).
void paintMasked(Canvas canvas, Size box, ui.Image img, MaskSpec m) {
  final dst = Offset.zero & box;
  canvas.saveLayer(dst, Paint());
  paintImage(canvas: canvas, rect: dst, image: img, fit: BoxFit.fill, filterQuality: FilterQuality.medium);
  final feather = m.feather.clamp(0.0, 1.0) * math.min(box.width, box.height) * 0.08;
  // The mask is its own full-size layer: composited with dstIn/dstOut over
  // the WHOLE picture, so everything outside the shape is cut too (drawing
  // the path directly would only affect the pixels it covers).
  canvas.saveLayer(dst, Paint()..blendMode = m.inverted ? BlendMode.dstOut : BlendMode.dstIn);
  canvas.drawPath(
    maskPath(m, box),
    Paint()..maskFilter = feather > 0.5 ? MaskFilter.blur(BlurStyle.normal, feather) : null,
  );
  canvas.restore();
  canvas.restore();
}

// ── Export: render to PNG files (cached by content) ────────────────────────

Future<Uint8List> _png(void Function(Canvas c) draw, int w, int h) async {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec));
  final img = await rec.endRecording().toImage(math.max(1, w), math.max(1, h));
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return bytes!.buffer.asUint8List();
}

Future<Uint8List> renderTextPng(TextElement e) async {
  final layer = TextLayer(e);
  final s = layer.size;
  return _png((c) => layer.paint(c, s), s.width.ceil(), s.height.ceil());
}

Future<Uint8List> renderShapePng(ShapeElement e, {int size = 512}) =>
    _png((c) => paintShape(c, Size(size.toDouble(), size.toDouble()), e), size, size);

Future<ui.Image> decodeImageFile(String path, {int maxSide = 1600}) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  var img = frame.image;
  final big = math.max(img.width, img.height);
  if (big > maxSide) {
    final k = maxSide / big;
    final c2 = await ui.instantiateImageCodec(bytes,
        targetWidth: (img.width * k).round(), targetHeight: (img.height * k).round());
    img.dispose();
    img = (await c2.getNextFrame()).image;
  }
  return img;
}

Future<Uint8List> renderMaskedPng(String src, MaskSpec m) async {
  final img = await decodeImageFile(src);
  final w = img.width, h = img.height;
  final out = await _png((c) => paintMasked(c, Size(w.toDouble(), h.toDouble()), img, m), w, h);
  img.dispose();
  return out;
}

/// Render every text layer, shape and masked image of [t] to PNGs in [dir]
/// (reused when nothing changed) → element id → PNG path, for the exporter.
Future<Map<String, String>> renderLayers(ProjectTimeline t, Directory dir) async {
  await dir.create(recursive: true);
  final out = <String, String>{};
  Future<void> put(String id, String key, Future<Uint8List> Function() make) async {
    final name = '${_hash(key)}.png';
    final f = File('${dir.path}/$name');
    if (!await f.exists()) await f.writeAsBytes(await make(), flush: true);
    out[id] = f.path;
  }

  for (final tr in t.tracks) {
    if (tr.hidden) continue;
    for (final e in tr.elements) {
      switch (e) {
        case TextElement():
          await put(e.id, 'text|${e.text}|${jsonEncode(e.style)}', () => renderTextPng(e));
        case ShapeElement():
          await put(e.id, 'shape|${e.shape}|${e.fillColor}|${e.strokeColor}|${e.strokeWidth}',
              () => renderShapePng(e));
        case ImageElement(mask: final m?) when m.shape != 'none':
          final stat = await File(e.src).stat().catchError((_) => FileStat.statSync(e.src));
          await put(e.id, 'mask|${e.src}|${stat.modified.millisecondsSinceEpoch}|${jsonEncode(m.toJson())}',
              () => renderMaskedPng(e.src, m));
        default:
          break;
      }
    }
  }
  return out;
}

String _hash(String s) {
  var h = -3750763034362895579; // FNV-1a 64
  for (final c in s.codeUnits) {
    h ^= c;
    h *= 0x100000001b3;
  }
  return h.toUnsigned(64).toRadixString(16);
}
