"""Pixel maps for pack B's three Pile Up skills (scripts/tower_skills/packs/
TowerSkillsB.gd) — Plumb Line, Crosswind, Nightfall.

Picked up by scripts/dev/make_tower_skill_icons.py; see its header for the
format and for why each pack keeps its own file. The HUD draws a self skill
on a green disc and an opponent skill on a red one, so none of these leans on
either colour: Plumb Line is grey stone and a brass bob, Crosswind is pale
sky-blue streaks, Nightfall is a cream moon over a navy cloud.
"""

ICONS = {
    # Plumb Line (self): a brick hanging above its landing spot, the line
    # between them, and the brass bob on the end of it.
    "tower_plumb": (
        [
            "................",
            "....SSSSSSSS....",
            "....SllllllS....",
            "....SllllllS....",
            "....SSSSSSSS....",
            ".......ww.......",
            ".......ww.......",
            ".......ww.......",
            ".......ww.......",
            "......bBBb......",
            ".....bBBBBb.....",
            "......bBBb......",
            ".......bb.......",
            "..dddddddddddd..",
            "..dddddddddddd..",
            "................",
        ],
        {
            "S": (58, 62, 78, 255),
            "l": (150, 156, 176, 255),
            "w": (250, 244, 230, 255),
            "B": (236, 190, 74, 255),
            "b": (176, 128, 40, 255),
            "d": (58, 62, 78, 255),
        },
    ),
    # Crosswind (opponent): three streaks blowing left to right, the leading
    # one tipped with an arrow head, and two flecks caught in it.
    "tower_crosswind": (
        [
            "................",
            "................",
            "..wwwwwwww......",
            "..........ww....",
            "............w...",
            ".wwwwwwwwwwwwl..",
            ".............ll.",
            ".wwwwwwwwwwwwlll",
            ".............ll.",
            "............l...",
            "...wwwwwwwww....",
            "................",
            ".....f...f......",
            "........f.......",
            "................",
            "................",
        ],
        {
            "w": (232, 244, 252, 255),
            "l": (150, 214, 255, 255),
            "f": (250, 244, 230, 255),
        },
    ),
    # Nightfall (opponent): a crescent moon and two stars over a bank of
    # night cloud.
    "tower_nightfall": (
        [
            "................",
            "......mmm.......",
            ".....mmmmm...s..",
            "....mmmm........",
            "....mmm.........",
            "....mmm.....s...",
            "....mmmm...sss..",
            ".....mmmmm..s...",
            "......mmm.......",
            "................",
            "...nnnn..nnn....",
            "..nnnnnnnnnnnn..",
            ".nnnnnnnnnnnnnn.",
            ".nnnnnnnnnnnnnn.",
            "..nnnnnnnnnnnn..",
            "................",
        ],
        {
            "m": (250, 238, 190, 255),
            "s": (250, 244, 230, 255),
            "n": (30, 34, 68, 255),
        },
    ),
}
