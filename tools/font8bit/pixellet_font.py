# -*- coding: utf-8 -*-
"""Build a Pixellet-style (dot-matrix) Lao font from a source TTF.

Like pixelate_font.py, but each on-pixel becomes a separate rounded dot
with a gap around it, giving the LED / "bead pixel" look of Thai fonts
such as Pixellet. GSUB/GPOS mark positioning is kept from the source.

Usage: python pixellet_font.py <in.ttf> <out.ttf> [ppem] [dot_ratio]
  dot_ratio: dot diameter as a fraction of the grid cell (default 0.88)
"""
import sys

import freetype
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen

FAMILY = "KarnSub Lao PixelDot"


def bitmap_to_rows(bitmap):
    rows = []
    pitch = bitmap.pitch
    buf = bitmap.buffer
    for r in range(bitmap.rows):
        rows.append([buf[r * pitch + c] >= 96 for c in range(bitmap.width)])
    return rows


def draw_dot(pen, cx, cy, r):
    """Quadratic approximation of a circle: 4 on-curve + 4 off-curve points."""
    k = round(r)
    cx, cy = round(cx), round(cy)
    pen.moveTo((cx, cy + k))
    pen.qCurveTo((cx + k, cy + k), (cx + k, cy))
    pen.qCurveTo((cx + k, cy - k), (cx, cy - k))
    pen.qCurveTo((cx - k, cy - k), (cx - k, cy))
    pen.qCurveTo((cx - k, cy + k), (cx, cy + k))
    pen.closePath()


def pixellet_glyph(face, gid, scale, dot_ratio, glyf_table, glyph_name):
    face.load_glyph(gid, freetype.FT_LOAD_RENDER)
    slot = face.glyph
    rows = bitmap_to_rows(slot.bitmap)
    left = slot.bitmap_left
    top = slot.bitmap_top
    r = scale * dot_ratio / 2

    pen = TTGlyphPen(None)
    for row_i, row in enumerate(rows):
        cy = (top - row_i - 0.5) * scale
        for col_i, on in enumerate(row):
            if on:
                cx = (left + col_i + 0.5) * scale
                draw_dot(pen, cx, cy, r)
    glyf_table[glyph_name] = pen.glyph()


def rename(font):
    name = font["name"]
    for nid, value in ((1, FAMILY), (3, FAMILY + " 1.0"), (4, FAMILY),
                       (6, FAMILY.replace(" ", "")), (16, FAMILY)):
        name.setName(value, nid, 3, 1, 0x409)
    name.removeNames(nameID=17)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    ppem = int(sys.argv[3]) if len(sys.argv) > 3 else 16
    dot_ratio = float(sys.argv[4]) if len(sys.argv) > 4 else 0.88

    font = TTFont(src)
    upm = font["head"].unitsPerEm
    scale = upm / ppem

    face = freetype.Face(src)
    face.set_pixel_sizes(0, ppem)

    glyf = font["glyf"]
    done = 0
    for gname in font.getGlyphOrder():
        if glyf[gname].isComposite():
            continue
        pixellet_glyph(face, font.getGlyphID(gname), scale, dot_ratio,
                       glyf, gname)
        done += 1

    rename(font)
    font.save(dst)
    print(f"dotted {done} simple glyphs at {ppem}ppem "
          f"(dot {dot_ratio:.2f}) -> {dst}")


if __name__ == "__main__":
    main()
