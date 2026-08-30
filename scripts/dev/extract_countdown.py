"""Cut the countdown glyphs (3, 2, 1, GO!) out of sayım.png as RGBA sprites.

This sheet is much easier than yenib.png next door, and the reason is worth
recording so nobody re-derives the hard version of the problem: **it already
has a real alpha channel.** Measured, alpha is bimodal — 833k pixels at ~0
and 720k at ~255 — and the black *outlines* around each glyph are opaque
(alpha 254) while the black *background* behind them is alpha 0. So there is
no background to remove, no flood fill, and no threshold that has to tell an
outline apart from the dark it sits on. Every cut below is made on the alpha
channel alone.

## Segmentation

Connected components of `alpha > 16`, split into a top row (the three digits,
each a numeral plus a scatter of separate burst marks) and a bottom row (GO!,
whose starburst is one connected blob plus a few loose sparks). The top row's
components are then grouped left-to-right on x-gaps: the gaps *between*
digits are 36px and 24px, while the gaps between a digit and its own burst
marks are single digits, so any threshold in between separates them cleanly.

## Every crop is masked to its own components

A box centred on the numeral and wide enough for the widest digit's burst
marks also reaches about 20px into the *next* digit's leftmost spark — the
digits are 36px apart and their bursts are not. So the crop is not a plain
rectangle of the sheet: everything outside the group's own connected
components is cleared to alpha 0 first. Without that, the 1 sprite carries a
sliver of the 2 along its right edge, which is invisible at thumbnail size
and shows up on screen as a stray glinting pixel beside the numeral.

## Why the digits are centred on the numeral, not on their own bounding box

Each digit's burst marks are not symmetric about the numeral — the 1's
bounding box centre sits 22px left of the 1 itself. Cropping to the bounding
box would therefore make the numeral jump sideways between 3, 2 and 1, which
is exactly the kind of thing nobody can name but everybody sees. So the crop
is built symmetric about the *numeral's* centre (the largest component in the
group) and padded out until it contains every burst mark. All three digits
come out the same size with the numeral dead centre, so the countdown ticks
in place.

GO! is shown once and has nothing to line up against, so it is simply cropped
to its own content.
"""
from PIL import Image
import numpy as np
from scipy import ndimage
import os

SRC = "/Users/berkantkucukomer/Documents/sayım.png"
OUT = "/Users/berkantkucukomer/Desktop/traffic-tower/sprites/ui"

ALPHA_FLOOR = 16    # below this is background glow, not art
ROW_SPLIT_Y = 440   # digits above, GO! below
DIGIT_GAP = 15      # px of empty column that separates one digit group from the next
PAD = 18            # breathing room so no burst mark sits flush against the edge


def components(mask):
    lab, _n = ndimage.label(mask, structure=np.ones((3, 3)))
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        ys, xs = sl
        out.append({
            "label": i, "area": int((lab[sl] == i).sum()),
            "x0": xs.start, "x1": xs.stop, "y0": ys.start, "y1": ys.stop,
        })
    return lab, out


def group_by_x_gap(comps, gap):
    comps = sorted(comps, key=lambda c: c["x0"])
    groups = [[comps[0]]]
    for c in comps[1:]:
        if c["x0"] - max(g["x1"] for g in groups[-1]) > gap:
            groups.append([c])
        else:
            groups[-1].append(c)
    return groups


def union(comps):
    return (min(c["x0"] for c in comps), min(c["y0"] for c in comps),
            max(c["x1"] for c in comps), max(c["y1"] for c in comps))


def masked_to(rgba, lab, comps):
    """A copy of the sheet with everything outside these components erased."""
    keep = np.isin(lab, [c["label"] for c in comps])
    out = rgba.copy()
    out[..., 3] = np.where(keep, out[..., 3], 0)
    return out


def assert_clear_border(img, name):
    """Nothing may touch the edge of a crop.

    A clipped burst mark is invisible in a thumbnail and obvious in motion,
    and the failure is silent — the sprite still loads and still draws. So
    the border ring is checked rather than eyeballed.
    """
    a = np.asarray(img)[..., 3]
    ring = max(a[0].max(), a[-1].max(), a[:, 0].max(), a[:, -1].max())
    if ring > ALPHA_FLOOR:
        raise SystemExit("%s: art reaches the crop edge (border alpha %d) — raise PAD" % (name, ring))


def main():
    im = Image.open(SRC).convert("RGBA")
    rgba = np.asarray(im).copy()
    lab, comps = components(rgba[..., 3] > ALPHA_FLOOR)

    top = [c for c in comps if (c["y0"] + c["y1"]) * 0.5 < ROW_SPLIT_Y]
    bottom = [c for c in comps if (c["y0"] + c["y1"]) * 0.5 >= ROW_SPLIT_Y]

    groups = group_by_x_gap(top, DIGIT_GAP)
    if len(groups) != 3:
        raise SystemExit("expected 3 digit groups, found %d — DIGIT_GAP or the sheet changed" % len(groups))

    # One box for all three digits: symmetric about each numeral, and wide and
    # tall enough for the most generous group's burst marks.
    half_w = half_h = 0
    centres = []
    for g in groups:
        body = max(g, key=lambda c: c["area"])
        cx = (body["x0"] + body["x1"]) * 0.5
        cy = (body["y0"] + body["y1"]) * 0.5
        centres.append((cx, cy))
        x0, y0, x1, y1 = union(g)
        half_w = max(half_w, cx - x0, x1 - cx)
        half_h = max(half_h, cy - y0, y1 - cy)
    half_w += PAD
    half_h += PAD

    names = ["count_1", "count_2", "count_3"] # groups run left to right on the sheet
    os.makedirs(OUT, exist_ok=True)
    for name, group, (cx, cy) in zip(names, groups, centres):
        box = (int(round(cx - half_w)), int(round(cy - half_h)),
               int(round(cx + half_w)), int(round(cy + half_h)))
        crop = Image.fromarray(masked_to(rgba, lab, group)).crop(box)
        assert_clear_border(crop, name)
        crop.save(os.path.join(OUT, name + ".png"))
        print("%-9s %4dx%-4d  from %s" % (name, crop.width, crop.height, box))

    x0, y0, x1, y1 = union(bottom)
    box = (x0 - PAD, y0 - PAD, x1 + PAD, y1 + PAD)
    go = Image.fromarray(masked_to(rgba, lab, bottom)).crop(box)
    assert_clear_border(go, "count_go")
    go.save(os.path.join(OUT, "count_go.png"))
    print("%-9s %4dx%-4d  from %s" % ("count_go", go.width, go.height, box))


if __name__ == "__main__":
    main()
