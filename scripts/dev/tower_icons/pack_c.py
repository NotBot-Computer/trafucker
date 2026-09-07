"""Pixel maps for Pile Up skill pack C's placeholder icons.

Picked up by scripts/dev/make_tower_skill_icons.py (see its header): each
entry is `tower_<id>: (rows, palette)`, 16x16, "." transparent. The HUD draws
self skills on a green disc and opponent skills on a red one, so tailor
(self) avoids green and keystone and rubble (opponent) avoid red.
"""

ICONS = {
    # Tailor: a brick above a measuring tape, with the cut line between them.
    "tower_tailor": (
        [
            "................",
            "................",
            "....CCCCCCCC....",
            "....CCCCCCCC....",
            "......CCCC......",
            "......CCCC......",
            "................",
            ".y.y.y.y.y.y.y..",
            "................",
            ".KKKKKKKKKKKKKK.",
            ".KYYYYYYYYYYYYK.",
            ".KYkYYkYYkYYkYK.",
            ".KYYYYYYYYYYYYK.",
            ".KKKKKKKKKKKKKK.",
            "................",
            "................",
        ],
        {
            "C": (92, 190, 236, 255),
            "y": (255, 226, 96, 255),
            "K": (44, 42, 48, 255),
            "Y": (250, 208, 70, 255),
            "k": (70, 56, 30, 255),
        },
    ),
    # Keystone: a stone arch with its keystone lifted out of the crown.
    "tower_keystone": (
        [
            "......wwww......",
            ".......YY.......",
            "......YYYY......",
            "................",
            "....GG....GG....",
            "...GGG....GGG...",
            "..GGG......GGG..",
            "..GG........GG..",
            ".GGG........GGG.",
            ".GG..........GG.",
            ".GG..........GG.",
            ".GG..........GG.",
            ".GG..........GG.",
            "................",
            "................",
            "................",
        ],
        {
            "G": (176, 178, 188, 255),
            "Y": (255, 200, 72, 255),
            "w": (250, 244, 230, 255),
        },
    ),
    # Rubble: a chunk tumbling out of the sky, its shadow already on the
    # top course of the tower below.
    "tower_rubble": (
        [
            "..w.......w.....",
            "...w.AAA.w......",
            ".....AAAAA......",
            "......AAAA......",
            ".......AA.......",
            "................",
            "................",
            "....ssssssss....",
            "...ssssssssss...",
            ".GGGGwGGGGGwGGG.",
            ".GGGGwGGGGGwGGG.",
            ".wwwwwwwwwwwwww.",
            ".GGwGGGGGwGGGGG.",
            ".GGwGGGGGwGGGGG.",
            "................",
            "................",
        ],
        {
            "A": (236, 176, 74, 255),
            "w": (236, 237, 242, 255),
            "s": (34, 36, 48, 230),
            "G": (118, 122, 136, 255),
        },
    ),
}
