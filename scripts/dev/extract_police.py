#!/usr/bin/env python3
"""Cuts `sprites/cars/police.png` — the car the player drives while MAKE WAY
is up — out of the user's `polis.png`.

The source is a single top-down pixel-art cruiser on a flat opaque grey
(125,125,124) with a soft drop shadow down its right and bottom edges, at
about 5.7x the resolution the art was drawn at. Three things here are
load-bearing:

  * **The shadow is excluded by threshold, not by hand.** The car's own dark
    parts (roof, glass, tyres) sit ~80-95 away from the background grey; the
    drop shadow only ever gets ~40 away. CORE_DELTA at 55 therefore takes the
    body and leaves the shadow behind, with no geometry assumed about where
    the shadow falls. Taking the largest connected component after filling
    holes then drops the stray flecks the threshold picks up inside the
    lighter panels.

  * **The antialiased fringe is grown back, not kept.** A 55 threshold cuts
    the blend pixels along the outline, which at this upscale is a couple of
    real pixels of the artist's own edge. Dilating the solid body by
    FRINGE_GROW and keeping only what is still clearly not background
    (FRINGE_DELTA) restores the outline without letting the dilation walk out
    into the shadow.

  * **The canvas is the player-car canvas, and the art is NOT stretched to
    fill it.** `Car._rebuild()` scales a texture to `width x height`
    independently on each axis, and those come from `PlayerBoard.PLAYER_KIND`
    (width_frac 0.62, height_frac 1.69) — so a texture at any other aspect
    ratio is visibly distorted on screen. The output is therefore the same
    78x132 as `sedan_blue.png`, and the cruiser is scaled to the same
    CONTENT_H (121px) the stock sedans use and centred in it. Its own body is
    more slender than theirs (h/w 2.15 against 1.81), so it ends up ~56px
    wide against their 67 — a narrower car of exactly the same length, rather
    than a squashed one. Fitting by width instead would need 144px of height
    in a 132px canvas.

    This is why MAKE WAY does not claim `car_kind()`: the swap is cosmetic,
    the hitbox is the ordinary player hitbox, and the art is fitted to that
    rather than the other way round.

Run from the repo root:
    python3 scripts/dev/extract_police.py
"""

import os

import numpy as np
from PIL import Image
from scipy import ndimage

SRC = os.path.expanduser("~/Documents/polis.png")
DST = os.path.join(os.path.dirname(__file__), "..", "..", "sprites", "cars", "police.png")

CORE_DELTA = 55    # max-channel distance from the background grey that means "car body"
FRINGE_DELTA = 22  # ...and that means "still not background", for the outline
FRINGE_GROW = 3    # px the solid body is dilated by to recover that outline

# Matched to sprites/cars/sedan_blue.png: a 78x132 canvas (PLAYER_KIND's own
# aspect) with the car 121px long inside it.
CANVAS = (78, 132)
CONTENT_H = 121


def main() -> None:
    src = Image.open(SRC).convert("RGB")
    rgb = np.array(src).astype(np.int16)

    # The background colour is read off the border rather than assumed, so a
    # re-export on a different grey still works.
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    bg = np.median(border, axis=0)
    delta = np.abs(rgb - bg).max(axis=2)

    body = _largest(ndimage.binary_fill_holes(delta > CORE_DELTA))
    grown = ndimage.binary_dilation(body, np.ones((3, 3), bool), iterations=FRINGE_GROW)
    mask = _largest(ndimage.binary_fill_holes(grown & (delta > FRINGE_DELTA)))

    cut = np.zeros((*mask.shape, 4), np.uint8)
    cut[:, :, :3] = rgb
    cut[:, :, 3] = np.where(mask, 255, 0)
    ys, xs = np.nonzero(mask)
    car = Image.fromarray(cut[ys.min():ys.max() + 1, xs.min():xs.max() + 1], "RGBA")

    scale = CONTENT_H / float(car.height)
    car = _resize_premultiplied(car, (max(1, round(car.width * scale)), CONTENT_H))

    out = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    out.alpha_composite(car, ((CANVAS[0] - car.width) // 2, (CANVAS[1] - car.height) // 2))
    out.save(DST)
    print(f"police.png  {CANVAS[0]}x{CANVAS[1]}, car {car.width}x{car.height} centred")


def _largest(mask: np.ndarray) -> np.ndarray:
    labels, count = ndimage.label(mask)
    if count == 0:
        raise SystemExit("nothing found — is the background still a flat colour?")
    sizes = ndimage.sum(mask, labels, range(1, count + 1))
    return labels == int(np.argmax(sizes)) + 1


def _resize_premultiplied(img: Image.Image, size: tuple) -> Image.Image:
    """Lanczos in premultiplied space — see scripts/dev/extract_oil.py for why
    straight-alpha resampling drags the transparent pixels' colour into the
    edges."""
    a = np.array(img).astype(np.float32)
    alpha = a[:, :, 3:4] / 255.0
    a[:, :, :3] *= alpha
    small = np.array(
        Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA").resize(size, Image.LANCZOS)
    ).astype(np.float32)
    out_a = small[:, :, 3:4] / 255.0
    small[:, :, :3] = np.where(out_a > 0.0, small[:, :, :3] / np.maximum(out_a, 1e-4), 0.0)
    return Image.fromarray(np.clip(small, 0, 255).astype(np.uint8), "RGBA")


if __name__ == "__main__":
    main()
