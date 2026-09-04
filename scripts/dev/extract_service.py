#!/usr/bin/env python3
"""Cuts four service vehicles — ambulance, fire truck, garbage truck, box truck
— out of the user's `buyuka.png`.

The sheet holds six vehicles; **the police car and the taxi are deliberately not
exported.** Both kinds already exist in the game (`sprites/cars/police.png` from
`polis.png`, and `sprites/cars/taxi.png`, which is a derivative of
`sedan_yellow.png` precisely so it belongs to the fleet — see
docs/PROJECT_STATE.md §7). They are still *located and measured* here, because
they are the sheet's ruler: both are vehicles the game draws at `width_frac`
0.62, so their width in this sheet's pixels is what every `width_frac` taken off
it is derived from rather than guessed. They measure 203 and 202px, which is a
tight enough agreement to trust.

Two things about the source, and two about the output:

  * **This sheet's alpha is real, and is the one supplied for this project that
    is.** §7's rule exists because five sheets in session Q had a checkerboard
    baked into opaque RGB. Here `Image.open(...).mode` is `RGBA` and the alpha
    histogram is sharply bimodal — 812k pixels under 8, 725k over 247, and only
    ~12k in between, every one of which sits within 4px of a solid pixel. That
    is antialiasing, not the coloured halo `motorlu.png` had, so the alpha is
    used as drawn rather than thresholded flat.

  * **The dark radial glow behind each vehicle is entirely at alpha 0**, so it
    costs nothing to ignore. What *is* removed is anything outside each
    vehicle's own connected component, which is what stops a stray speck of
    glow travelling with a sprite.

  * **One scale for the whole sheet, anchored to `extract_semis.py`.** The
    semis come off `tırlar.png` at 92px for `width_frac` 0.66, i.e. 139.4px of
    sprite per unit of `width_frac`; every vehicle here is scaled so it lands on
    that same ratio. That makes pixel density a property of the fleet rather
    than of whichever sheet a vehicle came from — the half of the session-I taxi
    failure that is about detail rather than style (§5 session Q).

  * **Tight-cropped, aspect untouched**, same as the semis: each of these kinds
    holds exactly one texture, so `GameSettings.TRAFFIC_KINDS` can set
    `height_frac` to the sprite's own aspect and `FleetProbe` reports 0.0%
    stretch. Padding to a common canvas would render a smaller vehicle inside an
    unchanged hitbox, because `Car._rebuild()` scales each axis independently.

Run from the repo root:
    python3 scripts/dev/extract_service.py
"""

import os

import numpy as np
from PIL import Image
from scipy import ndimage

SRC = os.path.expanduser("~/Documents/buyuka.png")
DST_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "sprites", "cars")

SOLID_ALPHA = 128  # what counts as body when finding each vehicle's component
FRINGE_GROW = 2    # px the component is grown by to re-admit the artist's own antialiasing
# ...and the floor that fringe has to clear. The edge itself is about one pixel
# wide (alpha runs 1, 2, 3, 13, 149, 252 across it), but under it lies a tail of
# alpha 1-5 reaching four or five pixels out — 2% opacity, invisible, and enough
# to inflate every bounding box by 8px if it is measured as part of the vehicle.
# Since the bounding box is what both width_frac and height_frac are derived
# from, that tail has to go before anything is measured, not after.
FRINGE_ALPHA = 24

# Pixels of sprite per unit of width_frac, taken from extract_semis.py's
# SPRITE_W (92) over the `truck` entry's width_frac (0.66). Change one and the
# two sheets stop agreeing about detail density.
PX_PER_WIDTH_FRAC = 92.0 / 0.66

RULER_WIDTH_FRAC = 0.62  # what the game draws the sheet's police car and taxi at

# Left to right across the sheet. None = present in the source, already in the
# game, not re-imported; it serves as the ruler instead.
NAMES = [
    None,             # police cruiser  -> sprites/cars/police.png already exists
    "ambulance",      # white box ambulance, light bar + red cross
    "fire_truck",     # red pumper with a roof ladder
    None,             # taxi            -> sprites/cars/taxi.png already exists
    "garbage_truck",  # green rear-loader
    "box_truck",      # white cab + white box body, rear doors drawn
]


def main() -> None:
    src = Image.open(SRC)
    if src.mode != "RGBA":
        raise SystemExit("expected a real alpha channel, got mode %s" % src.mode)
    rgba = np.array(src)
    alpha = rgba[:, :, 3]

    labels, count = ndimage.label(alpha >= SOLID_ALPHA)
    if count != len(NAMES):
        raise SystemExit("expected %d vehicles, found %d" % (len(NAMES), count))
    starts = [b[1].start for b in ndimage.find_objects(labels)]
    order = sorted(range(count), key=lambda i: starts[i])

    # Every vehicle is cut first and measured afterwards — including the two
    # that are not exported — so the ruler and the things measured against it
    # come off exactly the same silhouette.
    cuts = [_cut(rgba, alpha, labels, i) for i in order]
    ruler = float(np.median([c.width for name, c in zip(NAMES, cuts) if name is None]))
    print("sheet ruler: police/taxi %.0fpx wide == width_frac %.2f" % (ruler, RULER_WIDTH_FRAC))

    for name, vehicle in zip(NAMES, cuts):
        if name is None:
            print("  %-14s %3dx%3d  (already in the fleet — ruler only)"
                  % ("<skipped>", vehicle.width, vehicle.height))
            continue

        width_frac = vehicle.width / ruler * RULER_WIDTH_FRAC
        sprite_w = max(1, round(width_frac * PX_PER_WIDTH_FRAC))
        aspect = vehicle.height / float(vehicle.width)
        out = _resize_premultiplied(vehicle, (sprite_w, max(1, round(sprite_w * aspect))))
        out.save(os.path.join(DST_DIR, name + ".png"))
        print("  %-14s %3dx%3d from %3dx%3d   width_frac %.2f  height_frac %.2f  (aspect %.4f)"
              % (name, out.width, out.height, vehicle.width, vehicle.height,
                 width_frac, out.height / float(out.width), aspect))


def _cut(rgba: np.ndarray, alpha: np.ndarray, labels: np.ndarray, i: int) -> Image.Image:
    """One vehicle, tight-cropped, with its own antialiasing kept and everything
    outside its connected component (and under FRINGE_ALPHA) dropped."""
    keep = ndimage.binary_dilation(labels == i + 1, np.ones((3, 3), bool), iterations=FRINGE_GROW)
    cut = rgba.copy()
    cut[:, :, 3] = np.where(keep & (alpha >= FRINGE_ALPHA), alpha, 0)
    ys, xs = np.nonzero(cut[:, :, 3] > 0)
    return Image.fromarray(cut[ys.min():ys.max() + 1, xs.min():xs.max() + 1], "RGBA")


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
