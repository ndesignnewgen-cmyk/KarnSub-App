# -*- coding: utf-8 -*-
"""Render a Lao text sample with a font, applying real OpenType shaping
(uharfbuzz for GSUB/GPOS) so mark positioning is what apps will show.

Usage: python preview.py <font.ttf> <out.png> [text] [px]
"""
import sys

import freetype
import uharfbuzz as hb
from PIL import Image

DEFAULT_TEXT = "ສະບາຍດີ ຂ້ອຍຮັກພາສາລາວ\nກີ່ ເຈົ້າ ນໍ້າ ຫຼິ້ນ ໑໒໓໔໕\nຟອນ 8bit ໂດຍ KarnSub"


def render_line(face, font, text, px):
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(font, buf)

    upm = font.face.upem
    s = px / upm
    pen_x = 0.0
    placed = []  # (gid, x, y)
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        placed.append((info.codepoint,
                       pen_x + pos.x_offset * s,
                       pos.y_offset * s))
        pen_x += pos.x_advance * s

    w = int(pen_x) + 8
    h = int(px * 2.2)
    baseline = int(px * 1.5)
    img = Image.new("L", (w, h), 255)
    pix = img.load()
    for gid, gx, gy in placed:
        face.load_glyph(gid, freetype.FT_LOAD_RENDER)
        slot = face.glyph
        bm = slot.bitmap
        ox = int(gx) + slot.bitmap_left
        oy = baseline - int(gy) - slot.bitmap_top
        for r in range(bm.rows):
            for c in range(bm.width):
                v = bm.buffer[r * bm.pitch + c]
                if v > 32:
                    x, y = ox + c, oy + r
                    if 0 <= x < w and 0 <= y < h:
                        pix[x, y] = min(pix[x, y], 255 - v)
    return img


def main():
    path, out = sys.argv[1], sys.argv[2]
    text = sys.argv[3] if len(sys.argv) > 3 else DEFAULT_TEXT
    px = int(sys.argv[4]) if len(sys.argv) > 4 else 64

    blob = hb.Blob.from_file_path(path)
    hb_face = hb.Face(blob)
    hb_font = hb.Font(hb_face)

    ft = freetype.Face(path)
    ft.set_pixel_sizes(0, px)

    lines = [render_line(ft, hb_font, ln, px) for ln in text.split("\n")]
    w = max(im.width for im in lines)
    h = sum(im.height for im in lines)
    sheet = Image.new("L", (w, h), 255)
    y = 0
    for im in lines:
        sheet.paste(im, (0, y))
        y += im.height
    sheet.convert("RGB").save(out)
    print(f"saved {out} ({w}x{h})")


if __name__ == "__main__":
    main()
