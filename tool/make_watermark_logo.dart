/// Generates a TRANSPARENT watermark logo from the app icon.
///
/// The app icon (assets/icon/icon.png) is a white logo on a solid BLACK
/// background. For a video watermark we want the white logo on TRANSPARENT.
/// This maps each pixel's brightness to alpha (white→opaque, black→clear) and
/// forces the colour to white, giving clean anti-aliased white strokes.
///
/// Run:  dart run tool/make_watermark_logo.dart
/// Output: assets/icon/watermark_logo.png
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() {
  const srcPath = 'assets/icon/icon.png';
  const outPath = 'assets/icon/watermark_logo.png';

  final src = img.decodePng(File(srcPath).readAsBytesSync());
  if (src == null) {
    stderr.writeln('Could not decode $srcPath');
    exit(1);
  }

  // Downscale first — the source icon is huge (e.g. 8000²); a watermark only
  // needs ~256px, and decoding the full image per export wastes memory.
  final scaled = src.width > 256
      ? img.copyResize(src, width: 256, interpolation: img.Interpolation.average)
      : src;

  final out =
      img.Image(width: scaled.width, height: scaled.height, numChannels: 4);
  for (int y = 0; y < scaled.height; y++) {
    for (int x = 0; x < scaled.width; x++) {
      final p = scaled.getPixel(x, y);
      // Brightness of the source = alpha of the white logo.
      final lum = math.max(p.r, math.max(p.g, p.b)).round().clamp(0, 255);
      out.setPixelRgba(x, y, 255, 255, 255, lum);
    }
  }

  File(outPath).writeAsBytesSync(img.encodePng(out));
  stdout.writeln('Wrote $outPath (${out.width}x${out.height}, transparent).');
}
