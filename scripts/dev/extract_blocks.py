"""Extract the seven car-part tetromino pieces from yenib.png as RGBA sprites.

The sheet draws each piece as a cluster of *self-contained square blocks* —
one wheel, one battery, one radiator per cell — rather than as one continuous
drawing of a car spread across the cells, which is what the previous sheet
(bloklar.png) did. That difference is what this script is built around, and
it is what makes the layout problem below solvable at all.

## Background

The art sits on a baked-in checkerboard (the alpha pattern flattened into
RGB: alternating ~248 and ~241 neutral greys), and there is no drop shadow —
an edge goes checkerboard, one or two antialiased pixels, then the block's
near-black outline. Removing it is the same reachability argument the old
sheet needed: bright neutral pixels form a single region touching the image
border, while a block's own bright neutral details (chrome, window glints)
are walled in by its outline. So the removable region is flood-filled in from
the border rather than thresholded, and the piece labels printed under each
cluster never come into it because every cut is made inside a piece's own
bounding box.

## Layout: the arrangement is rotated, the blocks are not

The game's piece shapes are fixed by GameSettings.TETROMINOES and are not up
for discussion here — this script exists to re-skin those shapes, not to
change them. Three of the sheet's clusters are drawn in a different
orientation than the game's own:

  * T — sheet has the stem pointing up, the game has it pointing down
  * J — sheet has the lone block over the left end, the game over the right
  * L — sheet draws it 3 wide and 2 tall, the game 2 wide and 3 tall

The tempting fix is to rotate or flip the extracted image, and it is wrong:
these blocks have an up. Rotating the L cluster a quarter turn to fit the
game's footprint puts a wheel on its side, hangs a headlight sideways and
stands a spoiler on end. Because each cell is its own complete little panel,
the arrangement can be rotated *without* rotating the art — cut the cells
apart, then place them into the footprint the game already defines, each one
still the right way up. That is what CELLS below encodes: **the run of three
stays a run of three and the lone block stays the lone block**, so an L's
horizontal bar becomes an L's vertical bar in the same reading order and the
odd block stays the odd block.

## Cell size

Each cluster is normalised to an exact cols x rows grid of CELL-square cells.
The sheet is not internally consistent about cell size — the I piece's cells
are 146px wide against the S piece's 127, and every block is drawn 10-30%
wider than it is tall — which is the same class of problem the old sheet had
and is normal for generated art (see PROJECT_STATE §8). Normalising here is
what lets TowerPiece.gd scale every piece by the single number `cell / 100`
and trust that a cell is a cell.
"""
from PIL import Image
import numpy as np
from scipy import ndimage
import os

SRC = "/Users/berkantkucukomer/Documents/yenib.png"
OUT = "/Users/berkantkucukomer/Desktop/traffic-tower/sprites/blocks"
CELL = 100  # exported px per cell; the game renders these downscaled, as it does the car fleet

# name -> (source bbox y0,y1,x0,x1 | source cols,rows | dest cols,rows | cells)
#
# `cells` maps (source row, source col) -> (dest row, dest col). Dest cols/rows
# and the dest cells must match GameSettings.TETROMINOES exactly, piece for
# piece — the shapes are the game's, only the art is being replaced. Where the
# two agree the mapping is the identity and the piece is simply cut in place.
PIECES = [
    # HERO. 4x1 both sides; the four blocks read left to right as one van, so
    # this is the one cluster whose cells genuinely must not be reordered.
    ("i", (141, 252, 685, 1267), 4, 1, 4, 1,
     {(0, 0): (0, 0), (0, 1): (0, 1), (0, 2): (0, 2), (0, 3): (0, 3)}),
    # SMASHBOY. Square either way.
    ("o", (646, 858, 794, 1037), 2, 2, 2, 2,
     {(0, 0): (0, 0), (0, 1): (0, 1), (1, 0): (1, 0), (1, 1): (1, 1)}),
    # TEEWEE. Sheet points the stem up, the game points it down: the bar moves
    # to the top row and the spoiler becomes the stem under its middle.
    ("t", (345, 575, 732, 1153), 3, 2, 3, 2,
     {(1, 0): (0, 0), (1, 1): (0, 1), (1, 2): (0, 2), (0, 1): (1, 1)}),
    # RHODE ISLAND Z. Already the game's S.
    ("s", (904, 1105, 171, 551), 3, 2, 3, 2,
     {(0, 1): (0, 1), (0, 2): (0, 2), (1, 0): (1, 0), (1, 1): (1, 1)}),
    # CLEVELAND Z. Already the game's Z.
    ("z", (639, 851, 150, 535), 3, 2, 3, 2,
     {(0, 0): (0, 0), (0, 1): (0, 1), (1, 1): (1, 1), (1, 2): (1, 2)}),
    # ORANGE RICKY. The arrangement turns a quarter turn clockwise and the
    # blocks do not: the bar's left-to-right order becomes top-to-bottom, and
    # the turbo stays the block that sticks out.
    ("l", (40, 260, 145, 561), 3, 2, 2, 3,
     {(1, 0): (0, 0), (1, 1): (1, 0), (1, 2): (2, 0), (0, 2): (2, 1)}),
    # BLUE RICKY. Bar stays put; the wheel crosses to the other end.
    ("j", (353, 574, 141, 528), 3, 2, 3, 2,
     {(1, 0): (1, 0), (1, 1): (1, 1), (1, 2): (1, 2), (0, 0): (0, 2)}),
]

full = np.array(Image.open(SRC).convert("RGB")).astype(int)
hi, lo = full.max(axis=2), full.min(axis=2)
# The checkerboard is neutral and bright. 150 rather than 200 so the one or
# two antialiased pixels at a block's edge go with it instead of leaving a
# pale fringe around every block.
removable = ((hi - lo) < 14) & (hi > 150)
lab, _ = ndimage.label(removable)
border = set(lab[0, :]) | set(lab[-1, :]) | set(lab[:, 0]) | set(lab[:, -1])
border.discard(0)
alpha = np.where(np.isin(lab, list(border)), 0, 255).astype(np.uint8)
sheet = np.dstack([full.astype(np.uint8), alpha])

os.makedirs(OUT, exist_ok=True)

def square(cell_rgba):
    """One source cell, resampled to CELL x CELL.

    Premultiplied, so the transparent side of an edge pixel cannot bleed
    black into the outline — unpremultiplied RGBA resampling haloes.
    """
    f = cell_rgba.astype(np.float32)
    f[:, :, :3] *= (f[:, :, 3:4] / 255.0)
    r = np.array(Image.fromarray(f.astype(np.uint8), "RGBA")
                 .resize((CELL, CELL), Image.LANCZOS)).astype(np.float32)
    av = np.clip(r[:, :, 3:4], 1.0, 255.0)
    r[:, :, :3] = np.clip(r[:, :, :3] / (av / 255.0), 0, 255)
    return r.astype(np.uint8)

for name, (y0, y1, x0, x1), scols, srows, dcols, drows, cells in PIECES:
    a = sheet[y0:y1 + 1, x0:x1 + 1]
    h, w = a.shape[:2]
    out = np.zeros((drows * CELL, dcols * CELL, 4), np.uint8)
    for (sr, sc), (dr, dc) in cells.items():
        cy0, cy1 = round(h * sr / srows), round(h * (sr + 1) / srows)
        cx0, cx1 = round(w * sc / scols), round(w * (sc + 1) / scols)
        out[dr * CELL:(dr + 1) * CELL, dc * CELL:(dc + 1) * CELL] = square(a[cy0:cy1, cx0:cx1])
    Image.fromarray(out, "RGBA").save("%s/piece_%s.png" % (OUT, name))
    moved = sum(1 for k, v in cells.items() if k != v)
    print("piece_%s.png  %dx%d  %d cells (%d re-laid)  source cell %dx%d"
          % (name, dcols * CELL, drows * CELL, len(cells), moved, w // scols, h // srows))
