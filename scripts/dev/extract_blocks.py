"""Extract Pile Up's eighteen bricks from the user's tat1.png - tat6.png.

## The sheets

Six sheets, not one, and each holds two to six pieces scattered around it at
whatever size and position the generator felt like. Together they cover the
seven tetrominoes (tat5, tat6) and eleven of the twelve pentominoes (tat1 -
tat4). There is a nineteenth shape in the bottom-right corner of tat1 that
runs off both the right and bottom edges of the image: it is a *reflection*
of the L pentomino tat1 already supplies, so nothing is lost by leaving it
out, and there is no way to extract art that was never drawn. It is skipped
deliberately, not overlooked.

The art is a world away from the car-part sheet this script used to read
(`yenib.png`, see git history): each brick is one flat saturated fill inside
a heavy near-black outline, drawn as a single continuous shape rather than as
a cluster of self-contained per-cell panels. Two consequences, and they are
what this version is built around:

  * **Nothing here has an "up".** The old sheet's cells were little upright
    drawings — a wheel, a battery — so its extractor had to re-lay cells to
    fit the game's footprints rather than rotate them. A flat coloured
    polyomino has no such constraint, so the shapes below are simply the
    shapes as drawn, and `GameSettings.TETROMINOES` was rewritten to match
    the art instead of the art being rearranged to match it.
  * **A piece must not be cut into cells.** The outline is continuous across
    cell boundaries. Resampling each cell separately (which the old sheet
    needed, and could afford) would put a seam down the middle of every
    straight edge. Each piece is therefore resized *whole*, in one pass.

## Background removal

The background is plain white, with no baked checkerboard and no drop shadow,
so this is the easy version of the old problem: bright neutral pixels are
flood-filled in from the border and everything else is kept. Reachability
rather than a threshold, still, because a bright neutral region enclosed by a
piece's own outline (the hole in the U pentomino) is background by colour and
must not be — cutting it out would leave a piece you can see through.

`hi > 150` rather than 200 so the grey antialiased pixels between white and
outline go with the background instead of leaving a pale fringe; the outline
itself is far below that, and every fill is saturated, so neither is at risk.

## Cell size

Each piece is normalised to an exact `cols x rows` grid of CELL-square cells.
The sheets are not internally consistent — a cell is 142px in tat5 and 268px
in tat2, and within one piece the drawn cell is up to 14% wider than it is
tall — which is the same class of problem every generated sheet on this
project has had (PROJECT_STATE §8). Normalising is what lets `TowerPiece.gd`
scale any brick by the single factor `cell / 100` and trust that a cell is a
cell, and it is what "everything in the same proportion as the base block"
means in practice. The resize is therefore anisotropic on purpose: the point
is a square *cell*, not a preserved source aspect.

Outline weight survives that: measured across the six sheets it runs 7.4% to
9.4% of a cell, so normalising cell size normalises line weight along with
it, to within a spread too small to see.

## GRID is the source of truth

`GameSettings.TETROMINOES` must agree with the grids below, piece for piece —
the collision boxes are cell-unit rectangles laid over exactly this art, so a
disagreement puts collision where there is no brick and brick where there is
no collision. Nothing checks that at runtime, so this script checks it here:
every piece's measured cell occupancy is compared against its declared grid
and a mismatch is reported. It also prints each piece's rectangle
decomposition in GDScript form, which is what the `boxes` entries were
generated from.
"""
from PIL import Image
import numpy as np
from scipy import ndimage
import os

SRC_DIR = "/Users/berkantkucukomer/Documents"
OUT = "/Users/berkantkucukomer/Desktop/traffic-tower/sprites/blocks"
CELL = 100  # exported px per cell; the game renders these downscaled, as it does the car fleet

# name -> sheet, an (x, y) point inside the piece (used to pick it out of the
# sheet's components — position on the sheet is the only thing that
# distinguishes two pieces of the same colour), and the shape as drawn.
#
# '#' is a filled cell. These grids ARE the game's piece shapes: see the
# module docstring.
PIECES = [
    # --- tetrominoes: tat5 and tat6 -------------------------------------
    ("i",  5, (700,  300), ["#",
                            "#",
                            "#",
                            "#"]),
    ("o",  5, (270,  440), ["##",
                            "##"]),
    ("s",  5, (1200, 350), [".##",
                            "##."]),
    ("z",  5, (1700, 350), ["##.",
                            ".##"]),
    ("l",  6, (300,  200), ["#.",
                            "#.",
                            "##"]),
    ("j",  6, (1200, 200), [".#",
                            ".#",
                            "##"]),
    ("t",  6, (1600, 300), ["###",
                            ".#."]),
    # --- pentominoes: tat1 - tat4 ---------------------------------------
    ("l5", 1, (200,  200), ["#.",
                            "#.",
                            "#.",
                            "##"]),
    ("n",  1, (500,  250), ["#.",
                            "##",
                            ".#",
                            ".#"]),
    ("i5", 1, (900,  400), ["#",
                            "#",
                            "#",
                            "#",
                            "#"]),
    ("y",  1, (200,  900), ["#.",
                            "##",
                            "#.",
                            "#."]),
    ("f",  1, (600,  1100), [".#.",
                             "###",
                             "#.."]),
    ("v",  2, (800,  200), ["..#",
                            "..#",
                            "###"]),
    ("u",  2, (200,  1000), ["###",
                             "#.#"]),
    ("p",  3, (900,  200), ["##",
                            "##",
                            ".#"]),
    ("t5", 3, (300,  700), [".#.",
                            ".#.",
                            "###"]),
    ("z5", 3, (700,  1000), ["..#",
                             "###",
                             "#.."]),
    ("x",  4, (1100, 450), [".#.",
                            "###",
                            ".#."]),
    ("w",  4, (300,  300), ["#..",
                            "##.",
                            ".##"]),
]


def sheet(n):
    """One tat sheet as RGBA, background flood-filled away, plus its labels."""
    rgb = np.array(Image.open("%s/tat%d.png" % (SRC_DIR, n)).convert("RGB")).astype(int)
    hi, lo = rgb.max(axis=2), rgb.min(axis=2)
    removable = ((hi - lo) < 20) & (hi > 150)
    lab, _ = ndimage.label(removable)
    border = set(lab[0, :]) | set(lab[-1, :]) | set(lab[:, 0]) | set(lab[:, -1])
    border.discard(0)
    fg = ~np.isin(lab, list(border))
    # 8-connectivity: a piece's outline meets itself diagonally at the inside
    # of every notch, and 4-connectivity splits some pieces in two there.
    plab, _ = ndimage.label(fg, structure=np.ones((3, 3)))
    return rgb, plab


def decompose(grid):
    """Filled cells as non-overlapping rectangles, largest first.

    Merged rectangles rather than one box per cell, for the reason in
    TowerPiece.gd's header: a column of separate unit boxes presents internal
    edges a neighbouring brick's corner can catch on, and a tower that snags
    on nothing reads as a bug. Greedy-largest is enough — every shape here
    comes out in two or three boxes.
    """
    rows, cols = len(grid), len(grid[0])
    left = [[c == "#" for c in row] for row in grid]
    out = []
    while any(any(r) for r in left):
        best = None
        for y in range(rows):
            for x in range(cols):
                if not left[y][x]:
                    continue
                w = 0
                while x + w < cols and left[y][x + w]:
                    w += 1
                for ww in range(1, w + 1):
                    h = 0
                    while y + h < rows and all(left[y + h][x + i] for i in range(ww)):
                        h += 1
                    key = (ww * h, ww)  # ties go to the wider box, then to the earlier start
                    if best is None or key > best[0]:
                        best = (key, x, y, ww, h)
        _, x, y, w, h = best
        for dy in range(h):
            for dx in range(w):
                left[y + dy][x + dx] = False
        out.append((x, y, w, h))
    return out


os.makedirs(OUT, exist_ok=True)
sheets = {}
bad = 0

for name, n, (px, py), grid in PIECES:
    if n not in sheets:
        sheets[n] = sheet(n)
    rgb, plab = sheets[n]
    idx = plab[py, px]
    assert idx != 0, "%s: (%d, %d) is background on tat%d.png" % (name, px, py, n)
    ys, xs = ndimage.find_objects(plab, max_label=idx)[idx - 1]
    # Masked to this component, so an overlapping neighbour's bounding box
    # (tat1 and tat3 both have pairs that interleave) cannot bleed in.
    m = (plab[ys, xs] == idx)
    cropped = np.dstack([rgb[ys, xs].astype(np.uint8),
                         np.where(m, 255, 0).astype(np.uint8)])
    h, w = m.shape
    cols, rows = len(grid[0]), len(grid)

    # Check the art against the declared grid before trusting either.
    for r in range(rows):
        for c in range(cols):
            y0, y1 = round(h * r / rows), round(h * (r + 1) / rows)
            x0, x1 = round(w * c / cols), round(w * (c + 1) / cols)
            frac = m[y0:y1, x0:x1].mean()
            want = grid[r][c] == "#"
            if (frac > 0.5) != want:
                print("  !! %s cell (%d,%d) is %.0f%% covered, grid says %s"
                      % (name, r, c, 100 * frac, "filled" if want else "empty"))
                bad += 1

    # Premultiplied, so the transparent side of an edge pixel cannot bleed
    # white into the outline — unpremultiplied RGBA resampling haloes.
    f = cropped.astype(np.float32)
    f[:, :, :3] *= (f[:, :, 3:4] / 255.0)
    r = np.array(Image.fromarray(f.astype(np.uint8), "RGBA")
                 .resize((cols * CELL, rows * CELL), Image.LANCZOS)).astype(np.float32)
    av = np.clip(r[:, :, 3:4], 1.0, 255.0)
    r[:, :, :3] = np.clip(r[:, :, :3] / (av / 255.0), 0, 255)
    Image.fromarray(r.astype(np.uint8), "RGBA").save("%s/piece_%s.png" % (OUT, name))

    # The flat body hue GameSettings carries alongside the texture, for the
    # UI bits that need a plain Color (the next-piece card's underline, the
    # landing flash). Median of the saturated pixels, so the outline and the
    # antialiasing are not averaged into it.
    body = rgb[ys, xs][m]
    sat = body[(body.max(axis=1) - body.min(axis=1)) > 60]
    col = np.median(sat if len(sat) else body, axis=0) / 255.0
    boxes = ", ".join("Rect2(%d, %d, %d, %d)" % (x, y, bw, bh)
                      for x, y, bw, bh in decompose(grid))
    print('piece_%s.png  %dx%d  tat%d  cell %dx%d  Color(%.2f, %.2f, %.2f)  [%s]'
          % (name, cols * CELL, rows * CELL, n, w // cols, h // rows,
             col[0], col[1], col[2], boxes))

print("%d pieces, %d cell mismatches" % (len(PIECES), bad))
