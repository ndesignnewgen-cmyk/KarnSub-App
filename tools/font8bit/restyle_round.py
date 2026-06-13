# -*- coding: utf-8 -*-
"""Clean vector restyle of a Lao TTF: round only the sharp corners.

Keeps Noto's correct letterforms (no simplify, no axis-snap, no raster) and
softens just the genuine corners into small fillet arcs - the smooth,
geometric-but-clean look of the reference. Curves stay curves because
tangent-continuous vertices turn too little to count as corners.

Usage: python restyle_round.py <in.ttf> <out.ttf> [radius] [corner_deg]
  radius     : fillet radius in font units (default 70)
  corner_deg : min turn angle to treat a vertex as a corner (default 32)
"""
import math
import sys

import freetype
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

CONIC_STEPS = 8
FAMILY = "KarnSub Lao Mono"


def flatten(face, gid):
    face.load_glyph(gid, freetype.FT_LOAD_NO_SCALE | freetype.FT_LOAD_NO_BITMAP)
    contours, cur = [], []

    def move_to(p, _):
        nonlocal cur
        if cur:
            contours.append(cur)
        cur = [(p.x, p.y)]

    def line_to(p, _):
        cur.append((p.x, p.y))

    def conic_to(c, p, _):
        x0, y0 = cur[-1]
        for i in range(1, CONIC_STEPS + 1):
            t = i / CONIC_STEPS
            mt = 1 - t
            cur.append((mt * mt * x0 + 2 * mt * t * c.x + t * t * p.x,
                        mt * mt * y0 + 2 * mt * t * c.y + t * t * p.y))

    def cubic_to(c1, c2, p, _):
        x0, y0 = cur[-1]
        for i in range(1, CONIC_STEPS + 1):
            t = i / CONIC_STEPS
            mt = 1 - t
            cur.append((mt**3 * x0 + 3 * mt*mt*t * c1.x + 3*mt*t*t * c2.x
                        + t**3 * p.x,
                        mt**3 * y0 + 3 * mt*mt*t * c1.y + 3*mt*t*t * c2.y
                        + t**3 * p.y))

    face.glyph.outline.decompose(None, move_to=move_to, line_to=line_to,
                                 conic_to=conic_to, cubic_to=cubic_to)
    if cur:
        contours.append(cur)
    return contours


def dedupe(pts):
    out = []
    for p in pts:
        if not out or abs(p[0] - out[-1][0]) > 1 or abs(p[1] - out[-1][1]) > 1:
            out.append(p)
    if len(out) > 1 and out[0] == out[-1]:
        out.pop()
    return out


def round_contour(pen, pts, r, corner_deg):
    pts = dedupe(pts)
    n = len(pts)
    if n < 3:
        return
    cmds = []  # ('L', pt) or ('Q', ctrl, end)
    for i in range(n):
        p0, p1, p2 = pts[(i - 1) % n], pts[i], pts[(i + 1) % n]
        ix, iy = p1[0] - p0[0], p1[1] - p0[1]
        ox, oy = p2[0] - p1[0], p2[1] - p1[1]
        li, lo = math.hypot(ix, iy), math.hypot(ox, oy)
        if li == 0 or lo == 0:
            cmds.append(("L", p1))
            continue
        turn = abs((math.degrees(math.atan2(oy, ox) - math.atan2(iy, ix))
                    + 180) % 360 - 180)
        if turn < corner_deg:
            cmds.append(("L", p1))
            continue
        rr = min(r, 0.45 * li, 0.45 * lo)
        a = (p1[0] - ix / li * rr, p1[1] - iy / li * rr)
        b = (p1[0] + ox / lo * rr, p1[1] + oy / lo * rr)
        cmds.append(("L", a))
        cmds.append(("Q", p1, b))

    def endpoint(c):
        return c[1] if c[0] == "L" else c[2]

    pen.moveTo(endpoint(cmds[-1]))
    for c in cmds:
        if c[0] == "L":
            pen.lineTo(c[1])
        else:
            pen.qCurveTo(c[1], c[2])
    pen.closePath()


def rename(font):
    name = font["name"]
    for nid, value in ((1, FAMILY), (3, FAMILY + " 1.0"), (4, FAMILY),
                       (6, FAMILY.replace(" ", "")), (16, FAMILY)):
        name.setName(value, nid, 3, 1, 0x409)
    name.removeNames(nameID=17)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    r = float(sys.argv[3]) if len(sys.argv) > 3 else 70.0
    corner_deg = float(sys.argv[4]) if len(sys.argv) > 4 else 32.0

    font = TTFont(src)
    face = freetype.Face(src)
    glyf = font["glyf"]
    done = 0
    for gname in font.getGlyphOrder():
        if glyf[gname].isComposite() or glyf[gname].numberOfContours == 0:
            continue
        contours = flatten(face, font.getGlyphID(gname))
        pen = TTGlyphPen(None)
        for c in contours:
            round_contour(pen, c, r, corner_deg)
        glyf[gname] = pen.glyph()
        done += 1

    rename(font)
    font.save(dst)
    print(f"rounded {done} glyphs (r={r}, corner>{corner_deg}deg) -> {dst}")


if __name__ == "__main__":
    main()
