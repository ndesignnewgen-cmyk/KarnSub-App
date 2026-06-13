# -*- coding: utf-8 -*-
"""Hand-drawn clean Lao glyphs from deliberate vector strokes.

Each glyph is a list of strokes (polylines + arcs) of even width with
round caps/joins. Because every coordinate is placed by hand (not traced
from a raster), the outline is crisp - the cleanness the skeleton method
could not reach. This file renders a high-res preview sheet to calibrate
style/proportions on a few glyphs before drawing the whole alphabet.

Coordinate space: em 1000, baseline y=0, y up. Round body sits ~0..480,
stems/ascenders to ~720. Supersampled raster preview.

Usage: python handdraw.py <out.png>
"""
import math
import sys

from PIL import Image, ImageDraw

SS = 2                 # supersample factor
EM = 1000
W = 118                # stroke width (even weight)
PAD = 80
COLS = 6


# ---- stroke primitives (in em space, y up) -------------------------------

def line(p0, p1):
    return ("line", p0, p1)


def arc(cx, cy, r, a0, a1):
    """Arc center (cx,cy) radius r from angle a0 to a1 (degrees, ccw)."""
    return ("arc", (cx, cy), r, a0, a1)


def polyline(*pts):
    return [line(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]


def circle(cx, cy, r):
    return [arc(cx, cy, r, 0, 360)]


# ---- glyph definitions ---------------------------------------------------
# Lao body height ~480 for the loop; stems rise to ~720.

def g_o():            # ອ  (sara o-like loop with inner curl)
    s = circle(500, 300, 250)
    # small inner hook at top-right opening
    s += [arc(640, 470, 90, 200, 20)]
    return s


def g_zero():         # ໐
    return [arc(500, 300, 250, 0, 360)]


def g_wo():           # ວ  open bowl with a curl tail
    s = [arc(500, 300, 250, 300, 250)]  # near-full bowl, small gap top
    s += polyline((640, 470), (640, 560))
    return s


def g_bo():           # ບ  bowl + right stem rising with a top curl
    s = [arc(420, 250, 200, 0, 360)]            # bottom loop
    s += polyline((620, 250), (620, 660))       # right stem
    s += [arc(560, 660, 60, 0, 170)]            # small top curl left
    return s


def g_do():           # ດ  loop bottom-left, tall stem with flag
    s = [arc(360, 220, 175, 0, 360)]
    s += polyline((535, 220), (535, 690), (440, 690))
    return s


def g_ko():           # ກ  left curl + tall right stem
    s = polyline((360, 470), (360, 250))        # left short vertical
    s += [arc(440, 250, 80, 180, 360)]          # bottom curve to right
    s += polyline((520, 250), (520, 690))       # right tall stem
    s += [arc(470, 690, 50, 0, 170)]            # tiny top hook
    return s


GLYPHS = [
    ("ກ ko", g_ko()),
    ("ບ bo", g_bo()),
    ("ດ do", g_do()),
    ("ອ o", g_o()),
    ("ວ wo", g_wo()),
    ("໐ 0", g_zero()),
]


# ---- rendering -----------------------------------------------------------

def to_px(p, ox, oy):
    return (ox + p[0] * SS, oy + (EM - p[1]) * SS)


def draw_stroke(d, st, ox, oy):
    w = W * SS
    r = w / 2
    if st[0] == "line":
        a = to_px(st[1], ox, oy)
        b = to_px(st[2], ox, oy)
        d.line([a, b], fill=0, width=int(w))
        for c in (a, b):
            d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=0)
    else:  # arc
        (cx, cy), rr, a0, a1 = st[1], st[2], st[3], st[4]
        pts = []
        n = max(8, int(abs(a1 - a0) / 6))
        for i in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * i / n)
            pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
        ppx = [to_px(p, ox, oy) for p in pts]
        d.line(ppx, fill=0, width=int(w), joint="curve")
        for c in (ppx[0], ppx[-1]):
            d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=0)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "handdraw.png"
    rows = (len(GLYPHS) + COLS - 1) // COLS
    cell = EM + PAD
    W_px = COLS * cell * SS
    H_px = rows * cell * SS
    img = Image.new("L", (W_px, H_px), 255)
    d = ImageDraw.Draw(img)

    for idx, (name, strokes) in enumerate(GLYPHS):
        r, c = divmod(idx, COLS)
        ox = c * cell * SS + PAD * SS // 2
        oy = r * cell * SS + PAD * SS // 2
        for st in strokes:
            draw_stroke(d, st, ox, oy)

    img = img.resize((W_px // SS, H_px // SS), Image.LANCZOS)
    img.convert("RGB").save(out)
    print(f"saved {out} ({img.width}x{img.height})")


if __name__ == "__main__":
    main()
