"""Cut the countdown's burst frames out of sayımaa.png as sprite strips.

`extract_countdown.py` next door cuts the four countdown *stills* (3, 2, 1,
GO!) from `sayım.png`. This sheet animates them: each step gets seven frames,
where a spark appears at the centre and blooms outward over frames 1-6, and on
frame 7 the glyph lands inside the fully spread burst. **Only frames 1-6 are
extracted.** Frame 7 is the same pose as the corresponding still, and the still
wins: sayımaa.png is a redraw of the same artwork at a third of the resolution
(a numeral is 127px tall here against 377px there), so using its frame 7 would
have replaced a sprite the game draws sharp with one it has to magnify 2x.

Output is one strip per step (`sprites/ui/count_[123]_burst.png`,
`count_go_burst.png`), six equal cells wide, drawn by `scripts/Countdown.gd`.

## The cell size *is* the scale — there is no constant to keep in sync

The burst is drawn at the same size on screen as the still it precedes, and the
two sheets are drawn at different scales, so something has to carry the ratio
between them. Rather than print a number for Countdown.gd to hold, each cell is
cropped to **the still's canvas divided by that ratio**, so drawing a cell into
the exact rectangle the still occupies magnifies it by precisely the right
amount. `Countdown.gd` therefore reuses one rect for both and knows nothing
about either sheet's scale.

The ratio is measured glyph to glyph — the largest component of the still
against the largest component of frame 7 — because that is the pair the two
sheets actually agree on. Their *bursts* do not: sayım.png's static sparks sit
noticeably further out than this sheet's frame 7 sparks and are not even
symmetric about the numeral the same way, so measuring on the full artwork
would have scaled the animation to the wrong body.

**The three digits share one ratio (their mean).** Measured separately they
come out 2.97, 3.18 and 3.20, because this sheet's numerals differ in height
while the stills' were normalised to 377-378px by the other extractor. Using
each digit's own ratio would make the burst 7% larger on 3 than on 1 — sizing
the sparks to a numeral that is not on screen yet, which is exactly backwards.
One ratio makes all three bursts identical, which is what a count that ticks in
place wants.

## This sheet has no alpha — unlike sayım.png

`sayım.png` arrived with a real alpha channel and every cut there is made on
it. `sayımaa.png` is plain RGB on white with soft edges (a 4-6px ramp, so it is
a resampled render, not native pixel art). White is keyed out the way a white
matte comes out — for art containing no white,

    alpha  = (255 - min(R, G, B)) / 255
    colour = (observed - (1 - alpha) * 255) / alpha

which inverts compositing over white, so a black outline's antialiased ramp
un-mattes back to black rather than to grey. The art *does* contain white
highlights, but every one is enclosed by a black outline, so the solid mask has
its holes filled first and those pixels are then opaque. That order matters:
un-mattes on a near-white pixel divide by a near-zero alpha, and doing it
before the fill turned every highlight into amplified compression noise.

## Segmentation

Connected components of the solid mask, then:

- **the frame labels ("1.", "2.", ...) are dropped by saturation.** They are the
  only grey things on the sheet: measured, every label component peaks at
  saturation <= 6 while the faintest piece of art peaks at 21. This has to
  happen first, because two rows of labels sit *inside* the vertical span of the
  art they label and would fuse those rows together.
- **rows are cut at the 4 largest y-gaps, frames at the 7 largest x-gaps.**
  A fixed gap threshold does not work here: on the digit rows the four sparks of
  frame 3 are 33px apart, while GO!'s frames 6 and 7 are only 36px apart, so no
  single threshold separates every frame without also splitting one. The
  *counts* are known (5 rows, 8 groups per row), so the cut is made at the n
  largest gaps instead, and how clear that cut was is checked.
- **row 5 (the standalone "!") is not extracted.** GO! already contains its own
  exclamation mark; that row is a spare the game has no use for.
- **each row's leftmost image is the artist's clean reference glyph**, not a
  frame, and is skipped.

## Every cell is masked to its own components

The cells are sized off the still, which is far wider than an early spark, so
frame 1's cell reaches into frame 2 and frame 6's cell reaches into frame 7. A
cell is therefore not a plain rectangle of the sheet: everything outside that
frame's own connected components is cleared to alpha 0 first.
"""
from PIL import Image
import numpy as np
from scipy import ndimage
import os

SRC = "/Users/berkantkucukomer/Documents/sayımaa.png"
OUT = "/Users/berkantkucukomer/Desktop/traffic-tower/sprites/ui"

SOLID = 0.35        # alpha above this is body, not an antialiased edge
ALPHA_FLOOR = 0.06  # below this is compression noise in the white background
MIN_AREA = 24       # a component smaller than this is noise, not art
LABEL_SAT = 15      # peak saturation below this is a grey "1." "2." label
ROWS = 5            # 1, 2, 3, GO!, and the spare "!"
FRAMES = 7          # per row, after the leftmost reference glyph
BURST = 6           # of those, the ones with no glyph in them

NAMES = ["count_1", "count_2", "count_3", "count_go"]
DIGITS = 3          # the first three share one scale — see the header


def unmatte(rgb):
    """Straight-alpha RGBA from art composited over a white background."""
    a = (255.0 - rgb.min(axis=2)) / 255.0
    solid = ndimage.binary_fill_holes(a > SOLID)  # enclosed highlights are art
    a = np.maximum(a, solid)
    a[a < ALPHA_FLOOR] = 0.0
    safe = np.where(a > 0, a, 1.0)[..., None]
    c = (rgb - (1.0 - safe) * 255.0) / safe
    out = np.zeros(rgb.shape[:2] + (4,), dtype=np.uint8)
    out[..., :3] = np.clip(c, 0, 255).astype(np.uint8)
    out[..., 3] = np.clip(a * 255.0, 0, 255).astype(np.uint8)
    return out, solid


def components(mask):
    lab, _n = ndimage.label(mask, structure=np.ones((3, 3)))
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        ys, xs = sl
        out.append({
            "label": i, "area": int((lab[sl] == i).sum()), "slice": sl,
            "x0": xs.start, "x1": xs.stop, "y0": ys.start, "y1": ys.stop,
        })
    return lab, out


def split_at_largest_gaps(comps, key0, key1, n_groups, what):
    """Cut a run of components into exactly `n_groups` at its widest gaps.

    Gaps are measured against the running maximum edge, not the previous
    component's, so one wide or tall component spanning several smaller ones
    cannot open a false gap behind itself.
    """
    comps = sorted(comps, key=lambda c: c[key0])
    gaps = []
    reach = comps[0][key1]
    for i, c in enumerate(comps[1:], start=1):
        gaps.append((c[key0] - reach, i))
        reach = max(reach, c[key1])
    gaps.sort(reverse=True)
    if len(gaps) < n_groups - 1:
        raise SystemExit("%s: only %d gaps for %d groups — the sheet changed" % (what, len(gaps), n_groups))
    if n_groups - 1 < len(gaps):
        keep, drop = gaps[n_groups - 2][0], gaps[n_groups - 1][0]
        if keep <= drop:
            raise SystemExit("%s: the last gap kept (%dpx) is no clearer than the first dropped "
                             "(%dpx) — the sheet changed" % (what, keep, drop))
    cuts = sorted(i for _g, i in gaps[:n_groups - 1])
    return [comps[a:b] for a, b in zip([0] + cuts, cuts + [len(comps)])]


def union(comps):
    return (min(c["x0"] for c in comps), min(c["y0"] for c in comps),
            max(c["x1"] for c in comps), max(c["y1"] for c in comps))


def centre(comps):
    x0, y0, x1, y1 = union(comps)
    return ((x0 + x1) * 0.5, (y0 + y1) * 0.5)


def glyph_height(comps):
    body = max(comps, key=lambda c: c["area"])
    return body["y1"] - body["y0"]


def still_glyph_height(name):
    """Height of the numeral (or of GO!'s body) in the already-cut still."""
    a = np.asarray(Image.open(os.path.join(OUT, name + ".png")).convert("RGBA"))
    _lab, comps = components(a[..., 3] > 16)
    return glyph_height(comps)


def assert_clear_border(img, name):
    """Nothing may touch the edge of a cell.

    A clipped spark is invisible in a thumbnail and obvious in motion, and the
    failure is silent — the strip still loads and still draws. So the border
    ring is checked rather than eyeballed.
    """
    a = np.asarray(img)[..., 3]
    ring = max(a[0].max(), a[-1].max(), a[:, 0].max(), a[:, -1].max())
    if ring > ALPHA_FLOOR * 255:
        raise SystemExit("%s: art reaches the cell edge (border alpha %d) — the burst has outgrown "
                         "the still's canvas at this scale" % (name, ring))


def build_strip(rgba, lab, frames, cell, name):
    w, h = cell
    strip = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        cx, cy = centre(f)  # a burst is radially symmetric, so its box centres it
        keep = np.isin(lab, [c["label"] for c in f])
        cut = rgba.copy()
        cut[..., 3] = np.where(keep, cut[..., 3], 0)
        x0, y0 = int(round(cx - w * 0.5)), int(round(cy - h * 0.5))
        img = Image.fromarray(cut).crop((x0, y0, x0 + w, y0 + h))
        assert_clear_border(img, "%s frame %d" % (name, i + 1))
        strip.paste(img, (i * w, 0))
    return strip


def main():
    rgb = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float64)
    rgba, solid = unmatte(rgb)

    lab, comps = components(solid)
    sat = rgb.max(axis=2) - rgb.min(axis=2)
    art = []
    for c in comps:
        if c["area"] < MIN_AREA:
            continue
        if sat[c["slice"]][lab[c["slice"]] == c["label"]].max() < LABEL_SAT:
            continue  # a frame label, not art
        art.append(c)

    # Rows run 1, 2, 3, GO!, "!" down the sheet; the spare "!" is dropped.
    rows = split_at_largest_gaps(art, "y0", "y1", ROWS, "rows")[:len(NAMES)]
    per_row = [split_at_largest_gaps(r, "x0", "x1", FRAMES + 1, n)[1:]
               for n, r in zip(NAMES, rows)]  # [0] is the reference glyph

    stills = {n: Image.open(os.path.join(OUT, n + ".png")).size for n in NAMES}
    ratios = [still_glyph_height(n) / glyph_height(f[FRAMES - 1])
              for n, f in zip(NAMES, per_row)]
    digit_ratio = sum(ratios[:DIGITS]) / DIGITS
    ratios[:DIGITS] = [digit_ratio] * DIGITS

    for name, frames, ratio in zip(NAMES, per_row, ratios):
        sw, sh = stills[name]
        cell = (int(round(sw / ratio)), int(round(sh / ratio)))
        strip = build_strip(rgba, lab, frames[:BURST], cell, name)
        strip.save(os.path.join(OUT, name + "_burst.png"))
        print("%-9s %d cells of %dx%d   x%.2f into the %dx%d still" % (
            name, BURST, cell[0], cell[1], ratio, sw, sh))


if __name__ == "__main__":
    main()
