# -*- coding: utf-8 -*-
"""Pixelate a Lao TTF into an 8-bit style font.

Renders every simple glyph at a low pixel size with FreeType, then rebuilds
its outline as a grid of squares (merged into horizontal-run rectangles).
Composite glyphs, advance widths, GSUB/GPOS (mark positioning) are kept from
the source font, so Lao vowels/tones still stack correctly.

Usage: python pixelate_font.py <in.ttf> <out.ttf> [ppem]
"""
import sys

import freetype
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen

FAMILY = "KarnSub Lao 8Bit"


def bitmap_to_rows(bitmap):
    """Return list of rows, each a list of booleans (pixel on/off)."""
    rows = []
    pitch = bitmap.pitch
    buf = bitmap.buffer
    for r in range(bitmap.rows):
        row = []
        for c in range(bitmap.width):
            row.append(buf[r * pitch + c] >= 96)
        rows.append(row)
    return rows


def runs(row):
    """Yield (start, end) column runs of consecutive on-pixels."""
    start = None
    for i, on in enumerate(row):
        if on and start is None:
            start = i
        elif not on and start is not None:
            yield start, i
            start = None
    if start is not None:
        yield start, len(row)


def pixelate_glyph(face, gid, scale, glyf_table, glyph_name):
    face.load_glyph(gid, freetype.FT_LOAD_RENDER)
    slot = face.glyph
    rows = bitmap_to_rows(slot.bitmap)
    left = slot.bitmap_left
    top = slot.bitmap_top

    pen = TTGlyphPen(None)
    for r, row in enumerate(rows):
        y_top = round((top - r) * scale)
        y_bot = round((top - r - 1) * scale)
        for c0, c1 in runs(row):
            x0 = round((left + c0) * scale)
            x1 = round((left + c1) * scale)
            pen.moveTo((x0, y_bot))
            pen.lineTo((x1, y_bot))
            pen.lineTo((x1, y_top))
            pen.lineTo((x0, y_top))
            pen.closePath()
    glyf_table[glyph_name] = pen.glyph()


def rename(font):
    name = font["name"]
    for nid, value in ((1, FAMILY), (3, FAMILY + " 1.0"), (4, FAMILY),
                       (6, FAMILY.replace(" ", "")), (16, FAMILY)):
        name.setName(value, nid, 3, 1, 0x409)
    # drop subfamily-style overrides that could conflict
    for nid in (17,):
        name.removeNames(nameID=nid)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    ppem = int(sys.argv[3]) if len(sys.argv) > 3 else 16

    font = TTFont(src)
    upm = font["head"].unitsPerEm
    scale = upm / ppem

    face = freetype.Face(src)
    face.set_pixel_sizes(0, ppem)

    glyf = font["glyf"]
    order = font.getGlyphOrder()
    done = 0
    for gname in order:
        glyph = glyf[gname]
        if glyph.isComposite():
            continue  # components get pixelated; offsets stay in font units
        gid = font.getGlyphID(gname)
        pixelate_glyph(face, gid, scale, glyf, gname)
        done += 1

    rename(font)
    font.save(dst)
    print(f"pixelated {done} simple glyphs at {ppem}ppem -> {dst}")


if __name__ == "__main__":
    main()
