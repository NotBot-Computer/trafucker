#!/usr/bin/env python3
"""Cuts `sprites/ui/heart.png` — Don't Crash's life pip — out of the user's
`kalp.png`.

The source is an 18x18 pixel-art heart blown up to ~1151x1028 with a soft
resampler, so every "pixel" of the original arrives as a ~64x57 block with
antialiased seams and a little compression noise inside it. Rescaling that
with any filter keeps the mush; what we want back is the 18x18 the artist
actually drew, so this samples one point at the centre of each cell of the
detected grid and writes those 324 pixels out.

Two things here are load-bearing rather than tidiness:

  * **The cell grid is measured, not assumed.** The alpha bounding box is
    divided into GRID x GRID cells and each cell read at its centre, which is
    the furthest point from the antialiased seams on all four sides. Nearest-
    neighbour resizing the whole image instead lands its sample points
    wherever the ratio puts them — sometimes on a seam — and a single seam
    sample turns one block of the heart a different colour.

  * **The saturated pixels are normalised to full value.** `PlayerBoard`
    re-hues those pixels into each player's own car colour at runtime and
    keeps each pixel's own brightness so the art's shading survives the swap
    (see `_tint_heart_texture`). That multiply only lands on the intended
    colour if the brightest body pixel here is 1.0, so the normalisation is
    what lets the game side hold no constant about this particular PNG. The
    outline (black) and the highlight (white) are unsaturated and are left
    exactly as they are — they are what keeps a tinted heart readable.

Run from the repo root:
    python3 scripts/dev/extract_heart.py
"""

import colorsys
import os

from PIL import Image

SRC = os.path.expanduser("~/Documents/kalp.png")
DST = os.path.join(os.path.dirname(__file__), "..", "..", "sprites", "ui", "heart.png")

GRID = 18  # the source art's own resolution, measured off its cell seams
BODY_SAT = 0.25  # at or above this a pixel is heart body; below it is outline/highlight


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    box = src.getbbox()
    if box is None:
        raise SystemExit("kalp.png is fully transparent")
    left, top, right, bottom = box
    cell_w = (right - left) / GRID
    cell_h = (bottom - top) / GRID

    out = Image.new("RGBA", (GRID, GRID), (0, 0, 0, 0))
    peak = 0.0
    cells = []
    for gy in range(GRID):
        for gx in range(GRID):
            x = int(left + (gx + 0.5) * cell_w)
            y = int(top + (gy + 0.5) * cell_h)
            r, g, b, a = src.getpixel((x, y))
            h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if a > 0 and s >= BODY_SAT:
                peak = max(peak, v)
            cells.append((gx, gy, h, s, v, a))

    if peak <= 0.0:
        raise SystemExit("no saturated pixels found — check BODY_SAT / the source art")

    for gx, gy, h, s, v, a in cells:
        if a > 0 and s >= BODY_SAT:
            v = min(1.0, v / peak)  # see the module docstring
        r, g, b = colorsys.hsv_to_rgb(h, s, v)
        out.putpixel((gx, gy), (round(r * 255), round(g * 255), round(b * 255), a))

    out.save(os.path.normpath(DST))
    print("wrote %s (%dx%d, body peak value %.3f normalised to 1.0)"
          % (os.path.normpath(DST), GRID, GRID, peak))


if __name__ == "__main__":
    main()
