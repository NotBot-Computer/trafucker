#!/usr/bin/env python3
"""Cuts the six `sprites/cars/truck_*.png` semis out of the user's `tırlar.png`.

The sheet is 12 vehicles in two rows on a flat opaque grey (121,121,120) with a
soft drop shadow down each vehicle's right and bottom edges. **Only the bottom
row is taken** — those are the semis this replaces. The top row is four sedans
and two pickups, kinds that already have art nobody asked to change; they are
located and measured here (they are the sheet's own ruler, see below) and then
left alone.

Four things here are load-bearing:

  * **The background is removed by flood fill from the border, never by a
    global colour key** (the §7 rule). Two of the six trailers are near-white
    (212 and 205 against a 121 background) and one is a bare silver tank whose
    shaded flank sits at 103 — a global "anything grey-ish is background" test
    eats the tank. Enclosed by the vehicle's own dark outline, those pixels are
    simply never reached from the border, so connectivity protects them for
    free.

  * **The drop shadow is part of what the flood fill removes, not a separate
    step.** It is a flat darkening of the background to 80-87, so widening the
    "background-like" band to cover 76-130 lets the same fill swallow it. That
    works because the darkening is *uniform*: no vehicle pixel is a neutral
    grey in that band and outside the outline. Measured before it was relied
    on — the shadow's own delta from the background tops out at 44, the body's
    darkest edge pixel starts at 50.

  * **The mask is binary and the antialiasing comes from the downsample.**
    Same as extract_police.py: a hard mask at source resolution, then one
    premultiplied Lanczos resize to the output size, which is what draws the
    soft edge. Resampling a soft mask would blur it twice.

  * **The output is tight-cropped and its aspect is the art's own**, matching
    the five sprites it replaces (which are also edge-to-edge, 92x467). This is
    what lets `GameSettings.TRAFFIC_KINDS`' `truck` entry set `height_frac` to
    the measured aspect and have `FleetProbe` report ~0% stretch. Do not pad
    these to a common canvas: `Car._rebuild()` scales a texture to
    `width x height` on each axis independently, so padding renders as a
    smaller vehicle inside an unchanged hitbox.

`SPRITE_W` (92px) is deliberately the same width the outgoing sprites had, so
the new semis carry exactly the pixel density the rest of the fleet does — the
other half of the session-I taxi failure (see docs/PROJECT_STATE.md §5 session
Q). It is also the number `extract_service.py` derives its own scale from, via
the pixels-per-`width_frac` ratio the two sheets have to agree on.

Run from the repo root:
    python3 scripts/dev/extract_semis.py
"""

import os

import numpy as np
from PIL import Image
from scipy import ndimage

SRC = os.path.expanduser("~/Documents/tırlar.png")
DST_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "sprites", "cars")

# "Background-like": neutral within NEUTRAL_TOL and inside VALUE_BAND. The band
# spans the flat background (121) and its drop shadow (80-87) in one, with the
# floor set below the shadow and above nothing the vehicles contain outside
# their own outline. Only pixels reachable from the image border through this
# set are removed, so a near-white trailer or a mid-grey tank is safe.
NEUTRAL_TOL = 8
VALUE_BAND = (76.0, 130.0)

# Output width, in the sheet's left-to-right order. The sixth column is a
# second near-white box trailer, ribbed and with its rear doors drawn — a
# different vehicle from the third column's plain smooth box, which is why both
# ship.
SPRITE_W = 92
NAMES = [
    "truck_blue",    # dark blue cab + ribbed blue box
    "truck_red",     # red cab + ribbed red box
    "truck_white",   # white cab + plain white box
    "truck_tanker",  # grey cab + silver cylindrical tank
    "truck_logger",  # brown cab + flatbed of timber
    "truck_silver",  # white cab + ribbed light-grey box
]

# The row split: everything above this y is the sedan/pickup row we do not take.
ROW_SPLIT_Y = 340


def main() -> None:
    src = Image.open(SRC).convert("RGB")
    rgb = np.array(src).astype(np.int16)
    mask = _foreground(rgb)

    labels, count = ndimage.label(mask)
    sizes = ndimage.sum(mask, labels, range(1, count + 1))
    boxes = ndimage.find_objects(labels)

    top, bottom = [], []
    for i in range(count):
        if sizes[i] < 3000:  # 124 stray specks, 428px in total, all noise
            continue
        sy, sx = boxes[i]
        (bottom if sy.start >= ROW_SPLIT_Y else top).append((sx.start, i + 1, sy, sx))
    top.sort()
    bottom.sort()
    if len(top) != 6 or len(bottom) != 6:
        raise SystemExit("expected 6+6 vehicles, found %d+%d" % (len(top), len(bottom)))

    # The sheet's own ruler. Its sedans are the kind the game already draws at
    # width_frac 0.62, so their width in these pixels is what any width_frac
    # taken off this sheet has to be measured against. Printed rather than used
    # — `truck`'s width_frac is deliberately left where it has always been (see
    # docs/PROJECT_STATE.md §9) — but it is what makes the semis' own
    # proportions checkable against the fleet they are joining.
    ruler = float(np.median([sx.stop - sx.start for _, _, _, sx in top[:4]]))
    print("sheet ruler: sedan %.0fpx wide == width_frac 0.62" % ruler)

    aspects = []
    for name, (_, lbl, sy, sx) in zip(NAMES, bottom):
        cut = np.zeros((sy.stop - sy.start, sx.stop - sx.start, 4), np.uint8)
        cut[:, :, :3] = rgb[sy, sx]
        cut[:, :, 3] = np.where(labels[sy, sx] == lbl, 255, 0)
        car = Image.fromarray(cut, "RGBA")

        aspect = car.height / float(car.width)
        out = _resize_premultiplied(car, (SPRITE_W, max(1, round(SPRITE_W * aspect))))
        out.save(os.path.join(DST_DIR, name + ".png"))
        aspects.append(out.height / float(out.width))
        print(
            "  %-13s %3dx%3d from %3dx%3d  aspect %.4f  implied width_frac %.3f"
            % (name, out.width, out.height, car.width, car.height, aspects[-1],
               (sx.stop - sx.start) / ruler * 0.62)
        )

    lo, hi, mean = min(aspects), max(aspects), sum(aspects) / len(aspects)
    print("height_frac for the `truck` entry: %.2f  (art runs %.4f-%.4f, worst stretch %.1f%%)"
          % (mean, lo, hi, 100.0 * max(hi - mean, mean - lo) / mean))


def _foreground(rgb: np.ndarray) -> np.ndarray:
    """Everything the border's flood fill cannot reach — see the docstring."""
    neutral = (rgb.max(axis=2) - rgb.min(axis=2)) <= NEUTRAL_TOL
    value = rgb.mean(axis=2)
    bg_like = neutral & (value >= VALUE_BAND[0]) & (value <= VALUE_BAND[1])

    seed = np.zeros(bg_like.shape, bool)
    seed[0, :] = seed[-1, :] = True
    seed[:, 0] = seed[:, -1] = True
    background = ndimage.binary_propagation(seed & bg_like, mask=bg_like)
    return ndimage.binary_fill_holes(~background)


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
