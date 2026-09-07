#!/usr/bin/env python3
"""Generates the PLACEHOLDER icons for Pile Up's skills (scripts/tower_skills/).

Dev only — writes sprites/skills/tower_<id>.png, and those files are what
ship. Same scheme as make_placeholder_skill_icons.py (Don't Crash's icons,
see its header for why placeholders exist at all): blunt 16x16 pixel maps,
nearest-neighbour doubled, readable at the ~26px the HUD slots draw at.

**Per-author pixel maps, not one table.** Each skill pack was written by a
different session at the same time, so the maps live one file per pack under
scripts/dev/tower_icons/ — any *.py there defining `ICONS = {name: (rows,
palette)}` is picked up — and nobody edits a shared file (PROJECT_STATE §12).
Name a map `tower_<id>` and the pack's glyph preload finds it.

Replacing a placeholder with real art needs no code change: drop a PNG at the
same path. Keep it square, keep a real alpha channel, and note the HUD draws
self skills on a green disc and opponent skills on a red one — a glyph
whose dominant colour is that green or red vanishes into its own slot.

Run:  python3 scripts/dev/make_tower_skill_icons.py
"""

import glob
import os
import runpy

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
MAPS_DIR = os.path.join(HERE, "tower_icons")
OUT_DIR = os.path.join(HERE, "..", "..", "sprites", "skills")
SCALE = 2  # nearest-neighbour, so the result is still honest pixel art


def build(rows, palette):
    width = len(rows[0])
    for r in rows:
        assert len(r) == width, "ragged pixel map row: %r" % r
    img = Image.new("RGBA", (width, len(rows)), (0, 0, 0, 0))
    px = img.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == ".":
                continue
            assert ch in palette, "no palette entry for %r" % ch
            px[x, y] = palette[ch]
    return img.resize((width * SCALE, len(rows) * SCALE), Image.NEAREST)


def main():
    out = os.path.abspath(OUT_DIR)
    os.makedirs(out, exist_ok=True)
    os.makedirs(MAPS_DIR, exist_ok=True)
    files = sorted(glob.glob(os.path.join(MAPS_DIR, "*.py")))
    if not files:
        print("no pixel maps under %s — nothing to do" % MAPS_DIR)
        return
    seen = {}
    for path in files:
        icons = runpy.run_path(path).get("ICONS", {})
        for name, (rows, palette) in icons.items():
            assert name.startswith("tower_"), "%s: icon %r must be named tower_<id>" % (path, name)
            assert name not in seen, "icon %r defined in both %s and %s" % (name, seen[name], path)
            seen[name] = path
            img = build(rows, palette)
            dest = os.path.join(out, name + ".png")
            img.save(dest)
            print("%-22s %dx%d  <- %s" % (name, img.width, img.height, os.path.basename(path)))


if __name__ == "__main__":
    main()
