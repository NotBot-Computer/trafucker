"""Extract the seven car-tetromino pieces from bloklar.png as RGBA sprites.

The sheet draws each piece on a flat gray field (~73,73,74) with a soft drop
shadow (~42,42,42) offset down-right. Both have to go, and the art's own
outline is near-black, so no brightness threshold separates "shadow" from
"the black outline of a car" — the cars' dark windows and tyres sit in the
same value band as the shadow.

What does separate them is *reachability*: shadow and background form a
single region touching the image border, while every dark pixel inside a car
is walled in by that car's outline. So the removable region is flood-filled
in from the border over "neutral gray, brighter than an outline" — the same
technique PROJECT_STATE §7 records for the tank art's baked-in checkerboard.

Each piece is then normalised to an exact `cols x rows` grid of CELL-square
cells. The sheet is not pixel-consistent about cell size (the I piece's cars
are drawn 113px tall against the L piece's 105, a 7% disagreement, and every
piece is 4-14% taller than it is wide) which is normal for a generated sheet
— see PROJECT_STATE §8 on the tank sheet. Baking the correction in here
means TowerPiece.gd can scale every piece by one number and trust that a
cell is a cell, instead of carrying a per-piece fudge factor.
"""
from PIL import Image
import numpy as np
from scipy import ndimage
import os

SRC = "/Users/berkantkucukomer/Documents/bloklar.png"
OUT = "/Users/berkantkucukomer/Desktop/traffic-tower/sprites/blocks"
CELL = 100  # exported px per cell; the game renders these downscaled, as it does the car fleet

# (name, cols, rows, generous search bbox y0,y1,x0,x1)
PIECES = [
    ("i", 4, 1, (200, 346, 49, 458)),
    ("o", 2, 2, (98, 346, 525, 747)),
    ("t", 3, 2, (98, 346, 835, 1154)),
    ("s", 3, 2, (525, 765, 117, 437)),
    ("z", 3, 2, (524, 765, 506, 825)),
    ("l", 2, 3, (480, 825, 852, 1072)),
    ("j", 3, 2, (863, 1104, 460, 785)),
]

full = np.array(Image.open(SRC).convert("RGB")).astype(int)
os.makedirs(OUT, exist_ok=True)

for name, cols, rows, (y0, y1, x0, x1) in PIECES:
    a = full[y0:y1, x0:x1]
    hi, lo = a.max(axis=2), a.min(axis=2)
    # Background (~73) and shadow (~42) are both neutral and above 28; a car
    # outline is at or near 0 and its darkest interior detail stays under it.
    removable = ((hi - lo) < 16) & (hi > 28) & (hi < 110)

    lab, _ = ndimage.label(removable)
    border = set(lab[0, :]) | set(lab[-1, :]) | set(lab[:, 0]) | set(lab[:, -1])
    border.discard(0)
    alpha = np.where(np.isin(lab, list(border)), 0, 255).astype(np.uint8)

    ys, xs = np.nonzero(alpha)
    crop = np.dstack([a.astype(np.uint8), alpha])[ys.min():ys.max() + 1, xs.min():xs.max() + 1]

    # Resize premultiplied so the transparent side of an edge pixel can't
    # bleed black into the outline (unpremultiplied RGBA resampling halos).
    f = crop.astype(np.float32)
    f[:, :, :3] *= (f[:, :, 3:4] / 255.0)
    r = np.array(Image.fromarray(f.astype(np.uint8), "RGBA")
                 .resize((cols * CELL, rows * CELL), Image.LANCZOS)).astype(np.float32)
    av = np.clip(r[:, :, 3:4], 1.0, 255.0)
    r[:, :, :3] = np.clip(r[:, :, :3] / (av / 255.0), 0, 255)
    Image.fromarray(r.astype(np.uint8), "RGBA").save("%s/piece_%s.png" % (OUT, name))
    print("piece_%s.png  %dx%d  from %dx%d  (%d x %d cells)"
          % (name, cols * CELL, rows * CELL, crop.shape[1], crop.shape[0], cols, rows))
