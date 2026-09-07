"""Placeholder icons for Pile Up skill pack A (scripts/tower_skills/packs/TowerSkillsA.gd).

Picked up by scripts/dev/make_tower_skill_icons.py — see its header. Three
16x16 maps, one per skill in the pack, named tower_<id>. The HUD draws a
self skill on a green disc and an opponent skill on a red one, so neither
colour leads here: brick reds sit on green, stone greys on green, and the
quake is bone-white cracks on dark rock, on red.
"""

ICONS = {
    # Cement: two courses of brick with a fat cement seam between them,
    # still wet enough to drip.
    "tower_cement": (
        [
            "................",
            "..bbbbbbbbbbbb..",
            "..bbbbbbbbbbbb..",
            "..bbbbbbbbbbbb..",
            "..dddddddddddd..",
            ".mmmmmmmmmmmmmm.",
            ".mwwmmmmmmmwwmm.",
            ".mmmmmmmmmmmmmm.",
            "..mmbbbbbbbbmm..",
            "..mmbbbbbbbbmm..",
            "...bbbbbbbbbbb..",
            "...bbbbbbbbbbb..",
            "...ddddddddddd..",
            "................",
            "................",
            "................",
        ],
        {
            "b": (196, 92, 60, 255),
            "d": (150, 62, 40, 255),
            "m": (190, 186, 178, 255),
            "w": (235, 233, 228, 255),
        },
    ),
    # Tremor: a slab of ground split by a crack, with two shock arcs
    # rising off it.
    "tower_tremor": (
        [
            "................",
            "....s......s....",
            "...s........s...",
            "...s........s...",
            "..s..........s..",
            "................",
            ".ggggggggcggggg.",
            ".gggggggcgggggg.",
            ".ggggggggcggggg.",
            ".gggggggggcgggg.",
            ".ggggggggcggggg.",
            ".gggggggcgggggg.",
            ".rrrrrrrcrrrrrr.",
            "..rr..rrcrr..r..",
            "................",
            "................",
        ],
        {
            "g": (70, 62, 58, 255),
            "r": (120, 110, 100, 255),
            "c": (245, 230, 190, 255),
            "s": (255, 244, 210, 255),
        },
    ),
    # Petrify: a brick gone to stone — grey block, a lit top edge, cracks.
    "tower_petrify": (
        [
            "................",
            "................",
            "..llllllllllll..",
            "..ssssssssssss..",
            "..sssksssssskss.",
            "..ssksssssssks..",
            "..sskssssssksss.",
            "..ssskssskkssss.",
            "..sssskkkssssss.",
            "..ssssskssssss..",
            "..sssssskssssss.",
            "..ssssssskskkss.",
            "..ddddddddddddd.",
            "................",
            "................",
            "................",
        ],
        {
            "s": (150, 150, 158, 255),
            "l": (204, 204, 212, 255),
            "d": (96, 96, 106, 255),
            "k": (50, 48, 58, 255),
        },
    ),
}
