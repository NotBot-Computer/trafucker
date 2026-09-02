#!/usr/bin/env python3
"""Generates the PLACEHOLDER art for the modular skills (scripts/skills/).

Dev only — nothing in the game runs this, it writes files into sprites/skills/
and those files are what ship.

**Why this exists.** Every other sprite in this project is real art the user
supplied and a script cropped (see the extract_*.py siblings). These six
icons and the barrier are not: the session that built the skills had no image
generator reachable, so it drew stand-ins in code rather than shipping skills
with no glyph at all. They are deliberately blunt 16x16 (24x10 for the
barrier) pixel maps nearest-neighbour-doubled — chunky, high-contrast, and
readable at the ~28px the choice icons actually draw at.

**Replacing them with real art needs no code change**: drop a PNG at the same
path under sprites/skills/ and SkillCatalog picks it up. Keep the aspect
ratios (icons square, barrier ~2.4:1 wide) or the icon/car scaling will
letterbox. docs/SKILL_ART_BRIEF.md is the per-skill brief to generate from.

Run:  python3 scripts/dev/make_placeholder_skill_icons.py
"""

import os
from PIL import Image

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "sprites", "skills")

# Every map is a list of equal-length rows; "." is transparent. Palettes are
# per-icon so the same letter can mean different things in different maps.
ICONS = {
    # Make Way: a beacon on a dark bar, throwing beams to either side.
    "icon_siren": (
        [
            "................",
            "................",
            ".......ww.......",
            "......wRRw......",
            ".b...wRRRRw...b.",
            "..b.wRRRRRRw.b..",
            ".b..wRRRRRRw..b.",
            "....wwwwwwww....",
            "...KKKKKKKKKK...",
            "...KKKKKKKKKK...",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................",
        ],
        {
            "w": (250, 244, 230, 255),
            "R": (214, 58, 58, 255),
            "K": (38, 38, 46, 255),
            "b": (110, 220, 255, 255),
        },
    ),
    # Pit Stop: a heart with a repair cross cut out of it.
    "icon_pitstop": (
        [
            "................",
            "..RRRR....RRRR..",
            ".RRRRRR..RRRRRR.",
            "RRRRRRRwwRRRRRRR",
            "RRRRRRRwwRRRRRRR",
            "RRRRwwwwwwwwRRRR",
            "RRRRwwwwwwwwRRRR",
            ".RRRRRRwwRRRRRR.",
            "..RRRRRwwRRRRR..",
            "...RRRRwwRRRR...",
            "....RRRRRRRR....",
            ".....RRRRRR.....",
            "......RRRR......",
            ".......RR.......",
            "................",
            "................",
        ],
        {"R": (222, 62, 68, 255), "w": (250, 244, 230, 255)},
    ),
    # Compact: a car with the road closing in on it from both sides.
    "icon_compact": (
        [
            "................",
            "................",
            "................",
            "......C..C......",
            ".....CCCCCC.....",
            ".....CwwwwC.....",
            "g....CCCCCC....g",
            "gg...CCCCCC...gg",
            "ggg..CCCCCC..ggg",
            "gg...CwwwwC...gg",
            "g....CCCCCC....g",
            "......CCCC......",
            "......C..C......",
            "................",
            "................",
            "................",
        ],
        {
            "C": (90, 170, 235, 255),
            "w": (232, 244, 252, 255),
            "g": (110, 214, 128, 255),
        },
    ),
    # Detour: a striped roadworks barrier on its legs.
    "icon_roadblock": (
        [
            "................",
            "................",
            "................",
            ".KKKKKKKKKKKKKK.",
            ".OwwOOwwOOwwOOw.",
            ".wOOwwOOwwOOwwO.",
            ".OwwOOwwOOwwOOw.",
            ".KKKKKKKKKKKKKK.",
            "....K......K....",
            "....K......K....",
            "...KKK....KKK...",
            "................",
            "................",
            "................",
            "................",
            "................",
        ],
        {
            "K": (44, 42, 48, 255),
            "O": (240, 145, 40, 255),
            "w": (245, 240, 232, 255),
        },
    ),
    # Oil Slick: a spill with two drips still falling into it.
    "icon_slick": (
        [
            "................",
            ".......d........",
            "......ddd.......",
            ".......d........",
            "...........d....",
            "..........ddd...",
            "...........d....",
            "...KKKKKKKK.....",
            "..KKKKKKKKKKK...",
            ".KKKKwwKKKKKKKK.",
            ".KKKKwwKKKKKKKK.",
            ".KKKKKKKKKKKKK..",
            "..KKKKKKKKKK....",
            "....KKKKK.......",
            "................",
            "................",
        ],
        {
            "K": (28, 26, 34, 255),
            "w": (150, 190, 215, 255),
            "d": (52, 50, 62, 255),
        },
    ),
    # Smoke Screen: a bank of smoke, lit from inside.
    "icon_smoke": (
        [
            "................",
            "................",
            "......gggg......",
            "....gggggggg....",
            "...gglllllggg...",
            "..ggllllllllgg..",
            ".gggllllllllggg.",
            ".ggllllllllllgg.",
            ".gggllllllllggg.",
            "..ggggllllgggg..",
            "...gggggggggg...",
            "....gg....gg....",
            "................",
            "................",
            "................",
            "................",
        ],
        {"g": (128, 133, 146, 255), "l": (196, 200, 210, 255)},
    ),
    # The Detour barrier as it appears ON the road — a wide, short obstacle,
    # spawned as an ordinary Car so it collides and is sensed like traffic.
    # Aspect is ~2.4:1 to match RoadblockSkill's own BARRIER_KIND.
    "barrier": (
        [
            "........................",
            ".KKKKKKKKKKKKKKKKKKKKKK.",
            ".OOwwOOwwOOwwOOwwOOwwOO.",
            ".OwwOOwwOOwwOOwwOOwwOOw.",
            ".wwOOwwOOwwOOwwOOwwOOww.",
            ".KKKKKKKKKKKKKKKKKKKKKK.",
            "....K..............K....",
            "....K..............K....",
            "...KKK............KKK...",
            "........................",
        ],
        {
            "K": (44, 42, 48, 255),
            "O": (240, 145, 40, 255),
            "w": (245, 240, 232, 255),
        },
    ),
}

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
    for name, (rows, palette) in ICONS.items():
        img = build(rows, palette)
        path = os.path.join(out, name + ".png")
        img.save(path)
        print("%-18s %dx%d  -> %s" % (name, img.width, img.height, path))


if __name__ == "__main__":
    main()
