# -*- coding: utf-8 -*-
"""Restyle a Lao TTF toward a Korean Gothic (Hangul) look.

Flattens every contour to a polyline, simplifies it (Ramer-Douglas-Peucker,
epsilon proportional to contour size so big curves turn angular while small
loops stay round), then snaps near-horizontal/vertical segments to exact
axis alignment - giving the squared, geometric feel of Hangul gothic fonts.
Advance widths and GSUB/GPOS mark positioning are untouched.

Usage: python hangul_style.py <in.ttf> <out.ttf> [eps_pct] [snap_deg] [round_r]
  eps_pct : RDP epsilon as %% of contour perimeter (default 0.9)
  snap_deg: max angle from axis to snap a segment (default 14)
  round_r : corner rounding radius in font units (default 0 = sharp)
"""
import math
import sys

import freetype
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen

FAMILY = "KarnSub Lao Seoul"
CONIC_STEPS = 10


def flatten_glyph(face, gid):
    """Return list of contours, each a list of (x, y) points in font units."""
    face.load_glyph(gid, freetype.FT_LOAD_NO_SCALE | freetype.FT_LOAD_NO_BITMAP)
    contours = []
    cur = []

    def move_to(pt, _):
        nonlocal cur
        if cur:
            contours.append(cur)
        cur = [(pt.x, pt.y)]

    def line_to(pt, _):
        cur.append((pt.x, pt.y))

    def conic_to(c, pt, _):
        x0, y0 = cur[-1]
        for i in range(1, CONIC_STEPS + 1):
            t = i / CONIC_STEPS
            mt = 1 - t
            x = mt * mt * x0 + 2 * mt * t * c.x + t * t * pt.x
            y = mt * mt * y0 + 2 * mt * t * c.y + t * t * pt.y
            cur.append((x, y))

    def cubic_to(c1, c2, pt, _):
        x0, y0 = cur[-1]
        for i in range(1, CONIC_STEPS + 1):
            t = i / CONIC_STEPS
            mt = 1 - t
            x = (mt**3 * x0 + 3 * mt * mt * t * c1.x
                 + 3 * mt * t * t * c2.x + t**3 * pt.x)
            y = (mt**3 * y0 + 3 * mt * mt * t * c1.y
                 + 3 * mt * t * t * c2.y + t**3 * pt.y)
            cur.append((x, y))

    face.glyph.outline.decompose(None, move_to=move_to, line_to=line_to,
                                 conic_to=conic_to, cubic_to=cubic_to)
    if cur:
        contours.append(cur)
    return contours


def rdp(points, eps):
    if len(points) < 3:
        return points
    (x0, y0), (x1, y1) = points[0], points[-1]
    dx, dy = x1 - x0, y1 - y0
    norm = math.hypot(dx, dy)
    dmax, idx = -1.0, 0
    for i in range(1, len(points) - 1):
        px, py = points[i]
        if norm == 0:
            d = math.hypot(px - x0, py - y0)
        else:
            d = abs(dy * px - dx * py + x1 * y0 - y1 * x0) / norm
        if d > dmax:
            dmax, idx = d, i
    if dmax > eps:
        left = rdp(points[:idx + 1], eps)
        right = rdp(points[idx:], eps)
        return left[:-1] + right
    return [points[0], points[-1]]


def simplify_closed(points, eps):
    """RDP for a closed contour: cut at the two most distant-ish points."""
    if len(points) < 4:
        return points
    # split at index of point farthest from point 0 for stability
    far = max(range(len(points)),
              key=lambda i: (points[i][0] - points[0][0]) ** 2
                            + (points[i][1] - points[0][1]) ** 2)
    if far == 0:
        return points
    a = rdp(points[:far + 1], eps)
    b = rdp(points[far:] + [points[0]], eps)
    return a[:-1] + b[:-1]


def perimeter(points):
    total = 0.0
    for i in range(len(points)):
        x0, y0 = points[i - 1]
        x1, y1 = points[i]
        total += math.hypot(x1 - x0, y1 - y0)
    return total


def snap_axes(points, max_deg):
    """Make nearly-horizontal/vertical segments exactly axis-aligned."""
    pts = [list(p) for p in points]
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        dx, dy = x1 - x0, y1 - y0
        if dx == 0 and dy == 0:
            continue
        ang = math.degrees(math.atan2(abs(dy), abs(dx)))
        if ang <= max_deg:  # nearly horizontal
            ym = (y0 + y1) / 2
            pts[i][1] = ym
            pts[(i + 1) % n][1] = ym
        elif ang >= 90 - max_deg:  # nearly vertical
            xm = (x0 + x1) / 2
            pts[i][0] = xm
            pts[(i + 1) % n][0] = xm
    return [(round(x), round(y)) for x, y in pts]


def draw_rounded(pen, pts, round_r):
    """Draw closed polygon with each corner replaced by a small quadratic."""
    n = len(pts)
    ins, outs, ctrs = [], [], []
    for i in range(n):
        px, py = pts[i - 1]
        cx, cy = pts[i]
        nx, ny = pts[(i + 1) % n]
        l1 = math.hypot(cx - px, cy - py)
        l2 = math.hypot(nx - cx, ny - cy)
        r = min(round_r, l1 / 3, l2 / 3)
        if r < 2 or l1 == 0 or l2 == 0:
            ins.append((cx, cy))
            outs.append(None)  # sharp corner
            ctrs.append(None)
            continue
        ins.append((round(cx + (px - cx) * r / l1),
                    round(cy + (py - cy) * r / l1)))
        outs.append((round(cx + (nx - cx) * r / l2),
                     round(cy + (ny - cy) * r / l2)))
        ctrs.append((cx, cy))
    pen.moveTo(ins[0])
    for i in range(n):
        if i > 0:
            pen.lineTo(ins[i])
        if outs[i] is not None:
            pen.qCurveTo(ctrs[i], outs[i])
    pen.closePath()


def restyle_glyph(face, gid, eps_pct, snap_deg, round_r,
                  glyf_table, glyph_name):
    contours = flatten_glyph(face, gid)
    pen = TTGlyphPen(None)
    for pts in contours:
        eps = perimeter(pts) * eps_pct / 100.0
        simple = simplify_closed(pts, eps)
        if len(simple) < 3:
            continue
        snapped = snap_axes(simple, snap_deg)
        if round_r > 0:
            draw_rounded(pen, snapped, round_r)
        else:
            pen.moveTo(snapped[0])
            for p in snapped[1:]:
                pen.lineTo(p)
            pen.closePath()
    glyf_table[glyph_name] = pen.glyph()


def rename(font):
    name = font["name"]
    for nid, value in ((1, FAMILY), (3, FAMILY + " 1.0"), (4, FAMILY),
                       (6, FAMILY.replace(" ", "")), (16, FAMILY)):
        name.setName(value, nid, 3, 1, 0x409)
    name.removeNames(nameID=17)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    eps_pct = float(sys.argv[3]) if len(sys.argv) > 3 else 0.9
    snap_deg = float(sys.argv[4]) if len(sys.argv) > 4 else 14.0
    round_r = float(sys.argv[5]) if len(sys.argv) > 5 else 0.0

    font = TTFont(src)
    face = freetype.Face(src)

    glyf = font["glyf"]
    done = 0
    for gname in font.getGlyphOrder():
        if glyf[gname].isComposite():
            continue
        restyle_glyph(face, font.getGlyphID(gname), eps_pct, snap_deg,
                      round_r, glyf, gname)
        done += 1

    rename(font)
    font.save(dst)
    print(f"restyled {done} simple glyphs "
          f"(eps {eps_pct}%, snap {snap_deg} deg, round {round_r}) -> {dst}")


if __name__ == "__main__":
    main()
