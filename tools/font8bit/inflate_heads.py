# -*- coding: utf-8 -*-
"""Enlarge the round loop-heads of a looped Lao font.

Instead of distorting existing points (which kinks the head/stem junction),
this stamps a clean larger ring - a filled disc plus a circular hole - over
each detected head and unions it with the untouched glyph. The original
stroke merges into the disc, so the connection stays smooth and the head
reads as a clean circle. Only consonants are touched.

Usage: python inflate_heads.py <in.ttf> <out.ttf> [scale]
  scale : head outer radius multiplier (default 1.4)
"""
import math
import sys

import pathops
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
import freetype

from restyle_round import flatten, dedupe, FAMILY

DEFAULT_T = 80.0  # fallback ring thickness if no blob found


def bbox(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def signed_area(pts):
    a = 0.0
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        a += x0 * y1 - x1 * y0
    return a / 2


def roundish(pts, upem):
    x0, y0, x1, y1 = bbox(pts)
    bw, bh = x1 - x0, y1 - y0
    if bw <= 0 or bh <= 0 or max(bw, bh) > 0.45 * upem:
        return None
    if max(bw, bh) / min(bw, bh) > 2.3:
        return None
    return (x0 + x1) / 2, (y0 + y1) / 2, max(bw, bh) / 2


def find_heads(contours, upem):
    """Return [(cx, cy, outer_r, inner_r)] for each loop head."""
    if not contours:
        return []
    areas = [signed_area(c) for c in contours]
    main_sign = 1 if areas[max(range(len(contours)),
                               key=lambda i: abs(areas[i]))] > 0 else -1
    blobs, holes = [], []
    for c, a in zip(contours, areas):
        rd = roundish(c, upem)
        if rd is None:
            continue
        if (1 if a > 0 else -1) == main_sign:
            blobs.append(rd)          # filled island = head outer
        else:
            holes.append(rd)          # counter = head hole

    heads = []
    for hx, hy, hr in holes:
        blob = None
        for bx, by, br in blobs:
            if (hx - bx) ** 2 + (hy - by) ** 2 < br * br:
                if blob is None or br < blob[2]:
                    blob = (bx, by, br)
        if blob:
            heads.append((blob[0], blob[1], blob[2], hr))
        else:
            heads.append((hx, hy, hr + DEFAULT_T, hr))

    # merge heads sharing a location (keep the largest)
    merged = []
    for cx, cy, rb, rh in sorted(heads, key=lambda h: -h[2]):
        if any((cx - mx) ** 2 + (cy - my) ** 2 < (0.8 * mb) ** 2
               for mx, my, mb, _ in merged):
            continue
        merged.append((cx, cy, rb, rh))
    return merged


def draw_circle(path, cx, cy, r):
    n = 48
    pts = [(cx + r * math.cos(2 * math.pi * i / n),
            cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]
    path.moveTo(*pts[0])
    for p in pts[1:]:
        path.lineTo(*p)
    path.close()


def main():
    src, dst = sys.argv[1], sys.argv[2]
    scale = float(sys.argv[3]) if len(sys.argv) > 3 else 1.4

    font = TTFont(src)
    face = freetype.Face(src)
    upem = font["head"].unitsPerEm
    glyf = font["glyf"]

    cmap = font.getBestCmap()
    cps = list(range(0x0E81, 0x0EAF)) + list(range(0x0EDC, 0x0EE0))
    consonants = {cmap[cp] for cp in cps if cp in cmap}

    done = 0
    for gname in font.getGlyphOrder():
        g = glyf[gname]
        if g.isComposite() or g.numberOfContours == 0:
            continue
        contours = [dedupe(c) for c in flatten(face, font.getGlyphID(gname))]
        heads = find_heads(contours, upem) if gname in consonants else []

        sk = pathops.Path()
        for c in contours:                       # untouched original outline
            if len(c) < 3:
                continue
            sk.moveTo(*c[0])
            for p in c[1:]:
                sk.lineTo(*p)
            sk.close()
        sk = pathops.simplify(sk)

        if heads:
            discs, holes = pathops.Path(), pathops.Path()
            for i, (cx, cy, rb, rh) in enumerate(heads):
                t = rb - rh                      # keep ring thickness constant
                outer = rb * scale
                # don't let two heads in the same glyph (e.g. ຫ ໜ ໝ) collide:
                # cap growth to half the gap to the nearest other head.
                near = min((math.hypot(cx - ox, cy - oy)
                            for j, (ox, oy, _, _) in enumerate(heads)
                            if j != i), default=1e9)
                outer = max(rb, min(outer, near / 2 - 25))
                inner = max(rh, outer - t)
                draw_circle(discs, cx, cy, outer)
                draw_circle(holes, cx, cy, inner)
            # (glyph UNION discs) DIFFERENCE holes -> clean enlarged rings
            sk = pathops.op(sk, discs, pathops.PathOp.UNION)
            sk = pathops.op(sk, holes, pathops.PathOp.DIFFERENCE)

        pen = TTGlyphPen(None)
        sk.draw(pen)
        glyf[gname] = pen.glyph()
        done += 1

    name = font["name"]
    for nid, value in ((1, FAMILY), (3, FAMILY + " 1.0"), (4, FAMILY),
                       (6, FAMILY.replace(" ", "")), (16, FAMILY)):
        name.setName(value, nid, 3, 1, 0x409)
    name.removeNames(nameID=17)
    font.save(dst)
    print(f"stamped heads in {done} glyphs (scale={scale}) -> {dst}")


if __name__ == "__main__":
    main()
