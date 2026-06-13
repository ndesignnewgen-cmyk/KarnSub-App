# -*- coding: utf-8 -*-
"""Build a SaRangHeYo-style (Korean skeleton) Lao TTF.

Per glyph: render with FreeType, thin to a 1px skeleton, trace into
paths/cycles/dots, simplify + axis-snap, then rebuild the glyph as a
union of uniform-width round-capped strokes (skia-pathops). Small closed
loops become perfect circles. Metrics and GSUB/GPOS come from the source
font, so Lao mark stacking keeps working.

Usage: python skeleton_font.py <in.ttf> <out.ttf> [stroke_ratio]
  stroke_ratio: stroke width relative to render size (default 0.12)
"""
import math
import sys

import freetype
import numpy as np
import pathops
from fontTools.misc.transform import Transform
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from skimage.morphology import skeletonize

from poc_skeleton import rdp, snap

FAMILY = "KarnSub Lao Annyeong"
PX = 256          # render size per glyph
SNAP_DEG = 40     # aggressive axis snapping -> blocky orthogonal strokes
K = 0.5522847498  # cubic circle constant


def neigh(p, S):
    y, x = p
    out = []
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy or dx:
                q = (y + dy, x + dx)
                if q in S:
                    out.append(q)
    return out


def extract(mask):
    """Trace skeleton into (open paths, closed cycles, isolated dots)."""
    S = {(int(y), int(x)) for y, x in zip(*np.nonzero(mask))}
    deg = {p: len(neigh(p, S)) for p in S}
    nodes = {p for p in S if deg[p] != 2}
    used, visited = set(), set()
    paths, cycles = [], []
    dots = [p for p in S if deg[p] == 0]

    def walk(start, first):
        path = [start, first]
        prev, cur = start, first
        while cur not in nodes:
            visited.add(cur)
            nxt = None
            for q in neigh(cur, S):
                if q != prev and (q in nodes or q not in visited):
                    nxt = q
                    break
            if nxt is None:
                return path
            path.append(nxt)
            prev, cur = cur, nxt
            if cur == start:
                return path
        return path

    for n in nodes:
        for nb in neigh(n, S):
            if (n, nb) in used:
                continue
            path = walk(n, nb)
            used.add((n, nb))
            if path[-1] in nodes:
                used.add((path[-1], path[-2]))
            paths.append(path)

    for p in S:
        if deg[p] == 2 and p not in visited and p not in nodes:
            cyc = [p]
            visited.add(p)
            prev, cur = p, neigh(p, S)[0]
            while cur != p:
                cyc.append(cur)
                visited.add(cur)
                nxt = None
                for q in neigh(cur, S):
                    if q != prev and (q == p or q not in visited):
                        nxt = q
                        break
                if nxt is None:
                    break
                prev, cur = cur, nxt
            cycles.append(cyc)
    return paths, cycles, dots


def prune_spurs(paths, min_len):
    """Drop short branches that hang off junctions (skeleton artifacts)."""
    if len(paths) < 2:
        return paths
    ends = {}
    for p in paths:
        for e in (p[0], p[-1]):
            ends[e] = ends.get(e, 0) + 1
    out = []
    for p in paths:
        shared = ends[p[0]] > 1 or ends[p[-1]] > 1
        if len(p) < min_len and shared:
            continue
        out.append(p)
    return out or paths


def add_rect(path, p0, p1, hw):
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    length = math.hypot(dx, dy)
    if length == 0:
        return
    nx, ny = -dy / length * hw, dx / length * hw
    # wound clockwise to match add_circle so nonzero-winding union fills solid
    path.moveTo(p0[0] + nx, p0[1] + ny)
    path.lineTo(p0[0] - nx, p0[1] - ny)
    path.lineTo(p1[0] - nx, p1[1] - ny)
    path.lineTo(p1[0] + nx, p1[1] + ny)
    path.close()


def add_circle(path, cx, cy, r, ccw=False):
    k = K * r
    segs = [
        ((cx + r, cy + k), (cx + k, cy + r), (cx, cy + r)),
        ((cx - k, cy + r), (cx - r, cy + k), (cx - r, cy)),
        ((cx - r, cy - k), (cx - k, cy - r), (cx, cy - r)),
        ((cx + k, cy - r), (cx + r, cy - k), (cx + r, cy)),
    ]
    if ccw:
        segs = [
            ((cx + r, cy - k), (cx + k, cy - r), (cx, cy - r)),
            ((cx - k, cy - r), (cx - r, cy - k), (cx - r, cy)),
            ((cx - r, cy + k), (cx - k, cy + r), (cx, cy + r)),
            ((cx + k, cy + r), (cx + r, cy + k), (cx + r, cy)),
        ]
    path.moveTo(cx + r, cy)
    for c1, c2, p in segs:
        path.cubicTo(*c1, *c2, *p)
    path.close()


def _extend(end, other, d):
    """Push `end` away from `other` by distance d (square-cap extension)."""
    dx, dy = end[0] - other[0], end[1] - other[1]
    length = math.hypot(dx, dy)
    if length == 0:
        return end
    return (end[0] + dx / length * d, end[1] + dy / length * d)


def add_square(path, cx, cy, hw):
    """Axis-aligned square (side = stroke width), wound clockwise."""
    path.moveTo(cx - hw, cy - hw)
    path.lineTo(cx + hw, cy - hw)
    path.lineTo(cx + hw, cy + hw)
    path.lineTo(cx - hw, cy + hw)
    path.close()


def add_box(path, x0, y0, x1, y1, ccw=False):
    """Axis-aligned rectangle; CW by default, CCW to punch a hole."""
    if ccw:
        path.moveTo(x0, y0)
        path.lineTo(x0, y1)
        path.lineTo(x1, y1)
        path.lineTo(x1, y0)
    else:
        path.moveTo(x0, y0)
        path.lineTo(x1, y0)
        path.lineTo(x1, y1)
        path.lineTo(x0, y1)
    path.close()


def add_polyline(path, pts, hw, closed=False, square_caps=True, joint="square"):
    n = len(pts)
    fill = add_square if joint == "square" else add_circle
    if n == 1:
        fill(path, pts[0][0], pts[0][1], hw)
        return
    # fill interior vertices (all if closed) so corners never gap; for
    # axis-aligned strokes a square join yields a sharp 90-degree corner.
    interior = range(n) if closed else range(1, n - 1)
    for i in interior:
        fill(path, pts[i][0], pts[i][1], hw)
    last = n if closed else n - 1
    for i in range(last):
        a, b = pts[i], pts[(i + 1) % n]
        if square_caps and not closed:
            if i == 0:
                a = _extend(a, b, hw)
            if i == last - 1:
                b = _extend(b, pts[i], hw)
        add_rect(path, a, b, hw)


def build_glyph(face, gid, stroke_ratio):
    face.load_glyph(gid, freetype.FT_LOAD_RENDER)
    slot = face.glyph
    bm = slot.bitmap
    if bm.width == 0 or bm.rows == 0:
        return TTGlyphPen(None).glyph()

    # bm.buffer is a freetype-py property that copies the whole C buffer on
    # every access - grab it ONCE and reshape with numpy (pitch may > width).
    arr = np.array(bm.buffer, dtype=np.uint8).reshape(bm.rows, bm.pitch)
    mask = arr[:, :bm.width] > 127

    skel = skeletonize(mask)
    paths, cycles, dots = extract(skel)
    paths = prune_spurs(paths, min_len=10)

    base_w = PX * stroke_ratio
    cap = max(5.0, 0.75 * min(bm.width, bm.rows))
    w = min(base_w, cap)
    hw = w / 2
    eps = PX * 0.03
    circle_max = PX * 0.45

    sk = pathops.Path()

    def xy(seq):
        return [(p[1], p[0]) for p in seq]

    drew = False
    for p in paths:
        if len(p) < 3:
            continue
        pts = snap(rdp(xy(p), eps), SNAP_DEG)
        add_polyline(sk, pts, hw)
        drew = True

    for cyc in cycles:
        xs = [p[1] for p in cyc]
        ys = [p[0] for p in cyc]
        bw, bh = max(xs) - min(xs), max(ys) - min(ys)
        cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
        if max(bw, bh) <= circle_max:
            rx, ry = bw / 2, bh / 2
            add_box(sk, cx - rx - hw, cy - ry - hw,
                    cx + rx + hw, cy + ry + hw)
            if rx - hw > 2 and ry - hw > 2:
                add_box(sk, cx - rx + hw, cy - ry + hw,
                        cx + rx - hw, cy + ry - hw, ccw=True)
        else:
            pts = snap(rdp(xy(cyc + [cyc[0]]), eps), SNAP_DEG)
            add_polyline(sk, pts[:-1], hw, closed=True)
        drew = True

    for (dy, dx) in dots:
        add_circle(sk, dx, dy, hw)
        drew = True

    if not drew:
        # ink exists but skeleton degenerated: draw one dot at the center
        ys, xs = np.nonzero(mask)
        add_circle(sk, float(xs.mean()), float(ys.mean()), hw)

    sk = pathops.simplify(sk)

    # bitmap pixel coords -> font units (flip y)
    s = face.units_per_EM / PX
    t = Transform(s, 0, 0, -s, slot.bitmap_left * s, slot.bitmap_top * s)
    tt_pen = TTGlyphPen(None)
    sk.draw(TransformPen(Cu2QuPen(tt_pen, max_err=3.0), t))
    return tt_pen.glyph()


def rename(font):
    name = font["name"]
    for nid, value in ((1, FAMILY), (3, FAMILY + " 1.0"), (4, FAMILY),
                       (6, FAMILY.replace(" ", "")), (16, FAMILY)):
        name.setName(value, nid, 3, 1, 0x409)
    name.removeNames(nameID=17)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    stroke_ratio = float(sys.argv[3]) if len(sys.argv) > 3 else 0.12

    font = TTFont(src)
    face = freetype.Face(src)
    face.set_pixel_sizes(0, PX)

    glyf = font["glyf"]
    done = 0
    for gname in font.getGlyphOrder():
        if glyf[gname].isComposite():
            continue
        glyf[gname] = build_glyph(face, font.getGlyphID(gname), stroke_ratio)
        done += 1
        if done % 50 == 0:
            print(f"  {done} glyphs...")

    rename(font)
    font.save(dst)
    print(f"rebuilt {done} simple glyphs (stroke {stroke_ratio}) -> {dst}")


if __name__ == "__main__":
    main()
