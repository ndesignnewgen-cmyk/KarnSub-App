# -*- coding: utf-8 -*-
"""Proof of concept: SaRangHeYo-style Lao via skeleton extraction.

Renders shaped Lao text, thins it to a 1px skeleton, simplifies the
skeleton into straight axis-snapped strokes (small closed loops become
perfect circles), then re-strokes everything with a uniform-width
round-capped pen - the construction Korean-style fonts actually use.

Usage: python poc_skeleton.py <font.ttf> <out.png> [text] [px]
"""
import math
import sys

import freetype
import numpy as np
import uharfbuzz as hb
from PIL import Image, ImageDraw
from skimage.morphology import skeletonize


def shape_mask(font_path, hb_font, text, px):
    """Shape text with HarfBuzz and rasterize to a boolean ink mask."""
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(hb_font, buf)

    ft = freetype.Face(font_path)
    ft.set_pixel_sizes(0, px)
    s = px / hb_font.face.upem

    pen_x = 0.0
    placed = []
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        placed.append((info.codepoint,
                       pen_x + pos.x_offset * s, pos.y_offset * s))
        pen_x += pos.x_advance * s

    w, h = int(pen_x) + 24, int(px * 2.2)
    base = int(px * 1.5)
    img = np.zeros((h, w), bool)
    for gid, gx, gy in placed:
        ft.load_glyph(gid, freetype.FT_LOAD_RENDER)
        bm = ft.glyph.bitmap
        ox = int(gx) + ft.glyph.bitmap_left
        oy = base - int(gy) - ft.glyph.bitmap_top
        for r in range(bm.rows):
            for c in range(bm.width):
                if bm.buffer[r * bm.pitch + c] > 127:
                    y, x = oy + r, ox + c
                    if 0 <= y < h and 0 <= x < w:
                        img[y, x] = True
    return img


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


def extract_paths(mask):
    """Trace a 1px skeleton into open paths and closed cycles."""
    S = {(int(y), int(x)) for y, x in zip(*np.nonzero(mask))}
    deg = {p: len(neigh(p, S)) for p in S}
    nodes = {p for p in S if deg[p] != 2}
    used = set()      # directed edges already walked
    visited = set()   # mid-path pixels consumed
    paths, cycles = [], []

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
                return path, None
            path.append(nxt)
            prev, cur = cur, nxt
            if cur == start:
                return path, start
        return path, cur

    for n in nodes:
        for nb in neigh(n, S):
            if (n, nb) in used:
                continue
            path, end = walk(n, nb)
            used.add((n, nb))
            if end in nodes:
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
    return paths, cycles


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
        a = rdp(points[:idx + 1], eps)
        b = rdp(points[idx:], eps)
        return a[:-1] + b
    return [points[0], points[-1]]


def snap(pts, max_deg):
    pts = [list(p) for p in pts]
    for i in range(len(pts) - 1):
        x0, y0 = pts[i]
        x1, y1 = pts[i + 1]
        dx, dy = x1 - x0, y1 - y0
        if dx == 0 and dy == 0:
            continue
        ang = math.degrees(math.atan2(abs(dy), abs(dx)))
        if ang <= max_deg:
            ym = (y0 + y1) / 2
            pts[i][1] = pts[i + 1][1] = ym
        elif ang >= 90 - max_deg:
            xm = (x0 + x1) / 2
            pts[i][0] = pts[i + 1][0] = xm
    return [tuple(p) for p in pts]


def main():
    font_path, out = sys.argv[1], sys.argv[2]
    text = sys.argv[3] if len(sys.argv) > 3 else "ສະບາຍດີ ກີ່ ເຈົ້າ"
    px = int(sys.argv[4]) if len(sys.argv) > 4 else 160

    blob = hb.Blob.from_file_path(font_path)
    hb_font = hb.Font(hb.Face(blob))

    stroke_w = max(6, int(px * 0.10))
    eps = px * 0.02
    snap_deg = 25
    circle_max = px * 0.45

    sheets = []
    for line in text.split("\n"):
        mask = shape_mask(font_path, hb_font, line, px)
        skel = skeletonize(mask)
        paths, cycles = extract_paths(skel)

        h, w = mask.shape
        img = Image.new("L", (w, h), 255)
        d = ImageDraw.Draw(img)

        def yx_to_xy(seq):
            return [(p[1], p[0]) for p in seq]

        for path in paths:
            if len(path) < 3:
                continue
            pts = snap(rdp(yx_to_xy(path), eps), snap_deg)
            d.line(pts, fill=0, width=stroke_w, joint="curve")
            for (cx, cy) in (pts[0], pts[-1]):
                r = stroke_w / 2
                d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=0)

        for cyc in cycles:
            xs = [p[1] for p in cyc]
            ys = [p[0] for p in cyc]
            bw, bh = max(xs) - min(xs), max(ys) - min(ys)
            cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
            if max(bw, bh) <= circle_max:
                r = (bw + bh) / 4 + stroke_w / 2
                d.ellipse([cx - r, cy - r, cx + r, cy + r],
                          outline=0, width=stroke_w)
            else:
                pts = snap(rdp(yx_to_xy(cyc + [cyc[0]]), eps), snap_deg)
                d.line(pts, fill=0, width=stroke_w, joint="curve")
        sheets.append(img)

    w = max(im.width for im in sheets)
    h = sum(im.height for im in sheets)
    sheet = Image.new("L", (w, h), 255)
    y = 0
    for im in sheets:
        sheet.paste(im, (0, y))
        y += im.height
    sheet.convert("RGB").save(out)
    print(f"saved {out}")


if __name__ == "__main__":
    main()
