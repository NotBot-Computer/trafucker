#!/usr/bin/env python3
"""Cuts the eight oil puddles of `sprites/skills/oil_1..8.png` out of the
user's `yag.png` — the real art for OIL SLICK, replacing the procedural
polygons SlickSkill.gd drew before it.

The source is a 1536x1024 sheet of eight rainbow-sheened spills, already on a
transparent background, so unlike the pixel-art extractors here (extract_heart,
extract_blocks) there is no grid to measure and nothing to quantise — this is
a segmentation job. Three things are load-bearing:

  * **The blobs are found, not hand-typed.** Threshold at alpha > 100 (the
    puddle bodies sit at 200-255), dilate by 14px so each puddle's ring of
    splash droplets is labelled with the puddle it belongs to rather than as
    a dozen extra components, then take the connected components. Eight in,
    eight out; hand-typed rectangles would have to be re-typed if the sheet
    is ever re-exported.

  * **The background haze is floored away.** The sheet's "transparent"
    background is not blank — it carries a dark smoke gradient at alpha 1-8,
    which is invisible over black in a preview and a grey film over the road
    in game. ALPHA_FLOOR drops it. It is set well under the antialiased edge
    values (32+) so no puddle outline is eaten.

  * **The resample is done premultiplied.** Straight-alpha RGBA through
    Lanczos pulls the transparent pixels' colour (here: near-black) into
    every edge, which on art whose whole point is a bright rim would ring
    each puddle with a dark halo. Premultiply, resize, unpremultiply.

Output is capped at MAX_W px wide: a spill draws at ~50-110 board px and the
2-player camera zoom roughly doubles that, so 256 is about 2x the largest size
it is ever rasterised at — enough not to soften, small enough not to shimmer
without mipmaps.

Run from the repo root:
    python3 scripts/dev/extract_oil.py
"""

import os

import numpy as np
from PIL import Image
from scipy import ndimage

SRC = os.path.expanduser("~/Documents/yag.png")
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "sprites", "skills")

BODY_ALPHA = 100   # at or above this a pixel is puddle body, not edge or haze
JOIN_RADIUS = 14   # px of dilation, to adopt each puddle's splash droplets
ALPHA_FLOOR = 12   # below this a pixel is the sheet's background haze -> cleared
MAX_W = 256        # px; longest edge of a written sprite


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    arr = np.array(src).astype(np.uint8)
    alpha = arr[:, :, 3]

    body = alpha >= BODY_ALPHA
    joined = ndimage.binary_dilation(
        body, structure=np.ones((3, 3), bool), iterations=JOIN_RADIUS
    )
    labels, count = ndimage.label(joined)
    print(f"{count} puddles found in {os.path.basename(SRC)}")

    # Reading order (top row left-to-right, then down), so the numbering is
    # stable against a re-run and matches how the sheet looks.
    boxes = ndimage.find_objects(labels)
    order = sorted(
        range(1, count + 1),
        key=lambda i: (boxes[i - 1][0].start // 300, boxes[i - 1][1].start),
    )

    for n, label in enumerate(order, start=1):
        cell = np.zeros_like(arr)
        keep = (labels == label) & (alpha >= ALPHA_FLOOR)
        cell[keep] = arr[keep]

        ys, xs = np.nonzero(cell[:, :, 3])
        crop = cell[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        img = Image.fromarray(crop, "RGBA")

        if img.width > MAX_W or img.height > MAX_W:
            scale = MAX_W / float(max(img.width, img.height))
            size = (max(1, round(img.width * scale)), max(1, round(img.height * scale)))
            img = _resize_premultiplied(img, size)

        dst = os.path.join(OUT_DIR, f"oil_{n}.png")
        img.save(dst)
        print(f"  oil_{n}.png  {img.width}x{img.height}")


def _resize_premultiplied(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Lanczos in premultiplied space, so transparent pixels contribute their
    weight but not their colour to the edges (see the module docstring)."""
    a = np.array(img).astype(np.float32)
    alpha = a[:, :, 3:4] / 255.0
    a[:, :, :3] *= alpha
    small = np.array(
        Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA").resize(
            size, Image.LANCZOS
        )
    ).astype(np.float32)
    out_a = small[:, :, 3:4] / 255.0
    small[:, :, :3] = np.where(out_a > 0.0, small[:, :, :3] / np.maximum(out_a, 1e-4), 0.0)
    return Image.fromarray(np.clip(small, 0, 255).astype(np.uint8), "RGBA")


if __name__ == "__main__":
    main()
