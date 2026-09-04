extends Node

# Which mode the menu flow is heading into. A plain int rather than an enum
# for the same reason bot_difficulty is one: this autoload loads before every
# gameplay script, so it must not name a type that lives in one. MainMenu
# sets it, PlayerSelect and SkinSelect route on it, and it decides which
# scene SkinSelect finally hands off to.
const MODE_RACE := 0  # Don't Crash — the split-screen dodge-traffic race
const MODE_TOWER := 1 # Pile Up — the shared-tower physics stacker
var mode: int = MODE_RACE

var player_count: int = 2

# Which player slots start a round driven by BotDriver instead of a keyboard.
# Set by PlayerSelect's single-player option and toggled per slot with the 1-4 keys
# (in SkinSelect, and live mid-round in Main). This is only the *starting*
# state for a round — a board can be handed to a bot or taken back at any
# moment, and PlayerBoard.bot is the truth while one is running.
var bot_flags: Array[bool] = [false, false, false, false]

# Index into BotDriver.PROFILES (0 = easy, 1 = normal, 2 = hard). Deliberately
# a plain int rather than BotDriver.Difficulty so this autoload — which loads
# before anything else — carries no dependency on a gameplay script; the
# screens that display it resolve the name through BotDriver themselves.
#
# Defaults to hard because that is the only profile anyone has actually
# played and signed off on, and because the bot's first job is playtesting:
# the longer it survives, the more of a round it exercises before you have
# to restart it. Easy and normal exist and are reachable with the 5 key, but
# nobody should get an unvalidated profile just by launching the game.
var bot_difficulty: int = 2

# 1-4 hand player 1-4's board to the AI, or take it back; 5 cycles the
# difficulty every bot runs at. Number-row digits rather than anything in
# PLAYER_CONFIGS deliberately: one person has to be able to reach all of them
# mid-round, and they must not collide with a binding somebody is holding at
# the time — the digit matching the player number is the mnemonic. These were
# F1-F5 first, which is wrong on this project's own dev machine and on every
# other Mac: the function row is media keys unless fn is held, so F3 opened
# Mission Control and took focus off the game instead of toggling anything.
# Both screens that honour them — SkinSelect before a round, Main during one
# — read this list, so the two can't drift apart.
const BOT_TOGGLE_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4]
const BOT_DIFFICULTY_KEY := KEY_5

func set_bot(slot: int, enabled: bool) -> void:
	if slot >= 0 and slot < bot_flags.size():
		bot_flags[slot] = enabled

func clear_bots() -> void:
	for i in range(bot_flags.size()):
		bot_flags[i] = false

# Selectable player car skins: shown in SkinSelect, then applied to the
# player's Car in Main. Order matters for the default index (P1=0, P2=1...).
# "color" is a flat approximation of each texture's dominant hue — used for
# UI/effects that need a plain Color rather than a sprite (e.g. the boost
# bar fill and boost exhaust flames in PlayerBoard.gd), since the real car
# art is a texture, not a tintable shape.
const PLAYER_SKINS: Array[Dictionary] = [
	{"name": "Blue", "texture": preload("res://sprites/cars/sedan_blue.png"), "color": Color(0.25, 0.48, 0.92)},
	{"name": "Red", "texture": preload("res://sprites/cars/sedan_red.png"), "color": Color(0.88, 0.22, 0.22)},
	{"name": "Green", "texture": preload("res://sprites/cars/sedan_green.png"), "color": Color(0.24, 0.68, 0.32)},
	{"name": "Yellow", "texture": preload("res://sprites/cars/sedan_yellow.png"), "color": Color(0.95, 0.78, 0.12)},
	{"name": "Purple", "texture": preload("res://sprites/cars/sedan_purple.png"), "color": Color(0.58, 0.32, 0.78)},
	{"name": "Orange", "texture": preload("res://sprites/cars/sedan_orange.png"), "color": Color(0.92, 0.52, 0.14)},
]

# Chosen texture/color per player, filled in by SkinSelect before Main starts.
var skins: Array[Texture2D] = [PLAYER_SKINS[0]["texture"], PLAYER_SKINS[1]["texture"]]
var skin_colors: Array[Color] = [PLAYER_SKINS[0]["color"], PLAYER_SKINS[1]["color"]]

# Traffic vehicle kinds. width_frac is a fraction of lane width; height is
# width * height_frac (matched to each kind's real sprite aspect ratio so
# nothing looks stretched). weight controls how often a kind is picked
# relative to the others (see PlayerBoard._pick_traffic_kind).
#
# speed_frac_min/max bound how fast each kind closes the gap to the player,
# as a fraction of the road's own scroll speed (see PlayerBoard._process).
# This must stay below 1.0: at 1.0 a vehicle's own forward speed would be
# zero (a parked car matches the road's scroll exactly), and anything at or
# above 1.0 would mean it's closing faster than a stationary object could —
# i.e. driving backward — which reads as the car sliding the wrong way
# across the lane markings. Heavier/slower-driving kinds (trucks, trailers,
# buses) sit near the top of that range so you catch up to them quickly;
# nimbler kinds (sports cars, motorcycles) sit near the bottom so they roughly
# keep pace with you.
#
# The weights below total 100, so each one reads directly as a percentage, and
# adding a kind forces an explicit decision about what it displaces rather than
# quietly diluting everything. Session AB's four service vehicles cost 9 points,
# taken 4 from `sedan` and 1 each from `suv`/`pickup`/`van`/`sports`/`trailer`:
# the first five because they are the bulk of traffic and the shape of the
# distribution should survive, `trailer` because it is the closest thing in the
# table to what was added (a long, slow, lane-filling vehicle) and so it is the
# one that should give up share rather than accumulate it.
const TRAFFIC_KINDS: Array[Dictionary] = [
	{
		"kind": "sedan", "width_frac": 0.62, "height_frac": 1.69, "weight": 26,
		"speed_frac_min": 0.55, "speed_frac_max": 0.85,
		"textures": [
			preload("res://sprites/cars/sedan_silver.png"),
			preload("res://sprites/cars/sedan_brown.png"),
			preload("res://sprites/cars/sedan_sage.png"),
			preload("res://sprites/cars/sedan_darkbrown.png"),
			preload("res://sprites/cars/sedan_teal.png"),
			preload("res://sprites/cars/sedan_cream.png"),
		],
	},
	{
		"kind": "suv", "width_frac": 0.68, "height_frac": 1.98, "weight": 15,
		"speed_frac_min": 0.55, "speed_frac_max": 0.85,
		"textures": [
			preload("res://sprites/cars/suv_white.png"),
			preload("res://sprites/cars/suv_black.png"),
			preload("res://sprites/cars/suv_silver.png"),
			preload("res://sprites/cars/suv_green.png"),
			preload("res://sprites/cars/suv_tan.png"),
			preload("res://sprites/cars/suv_navy.png"),
			preload("res://sprites/cars/suv_forest.png"),
			preload("res://sprites/cars/suv_red.png"),
			preload("res://sprites/cars/suv_slate.png"),
			preload("res://sprites/cars/suv_cream.png"),
		],
	},
	{
		"kind": "pickup", "width_frac": 0.62, "height_frac": 2.23, "weight": 11,
		"speed_frac_min": 0.6, "speed_frac_max": 0.9,
		"textures": [
			preload("res://sprites/cars/pickup_red.png"),
			preload("res://sprites/cars/pickup_blue.png"),
			preload("res://sprites/cars/pickup_white.png"),
			preload("res://sprites/cars/pickup_charcoal.png"),
			preload("res://sprites/cars/pickup_tan.png"),
		],
	},
	{
		"kind": "van", "width_frac": 0.58, "height_frac": 1.55, "weight": 10,
		"speed_frac_min": 0.6, "speed_frac_max": 0.9,
		"textures": [
			preload("res://sprites/cars/van_blue.png"),
			preload("res://sprites/cars/van_white.png"),
			preload("res://sprites/cars/van_silver.png"),
			preload("res://sprites/cars/van_lavender.png"),
			preload("res://sprites/cars/van_cyan.png"),
			preload("res://sprites/cars/van_red.png"),
			preload("res://sprites/cars/van_cream_box.png"),
			preload("res://sprites/cars/van_navy_box.png"),
			preload("res://sprites/cars/van_darkgray_box.png"),
		],
	},
	{
		"kind": "sports", "width_frac": 0.6, "height_frac": 2.09, "weight": 8,
		"speed_frac_min": 0.35, "speed_frac_max": 0.6,
		# The quickest thing on the road, so it sits at the *bottom* of the speed_frac
		# band with the motorcycles: a low fraction means it closes on you slowly,
		# i.e. it is nearly keeping pace. See the block comment above.
		"textures": [
			preload("res://sprites/cars/sports_red.png"),
			preload("res://sprites/cars/sports_blue.png"),
			preload("res://sprites/cars/sports_silver.png"),
			preload("res://sprites/cars/sports_yellow.png"),
			preload("res://sprites/cars/sports_purple.png"),
		],
	},
	{
		"kind": "truck", "width_frac": 0.66, "height_frac": 3.67, "weight": 7,
		"speed_frac_min": 0.75, "speed_frac_max": 0.95,
		# Re-skinned from the user's tırlar.png in session AB
		# (scripts/dev/extract_semis.py). Six bodies instead of five, and the
		# cargo varies now — box, tank, timber — where every old sprite was the
		# same grey trailer behind a differently-coloured cab.
		#
		# **height_frac fell 5.07 -> 3.67, and that is a difficulty change, not
		# a cosmetic one:** a semi is 130px of a 620px board now, down from 179.
		# 3.67 is the new art's own aspect (the six sprites run 3.62-3.73, worst
		# stretch 1.6%) and stretching it back to 5.07 is the §8 mistake — the
		# ribs coarsen and the vehicle reads as a zoomed sprite rather than a
		# longer truck. Session Q's 40% lengthening was compensation for a
		# trailer drawn *narrower than its own tractor*, which this art does not
		# have; the defect it was correcting left with the sprite.
		# width_frac stays at 0.66 so exactly one number moves — this sheet's
		# own ruler would put these at 0.74 (see the script), and width_frac is
		# the one knob §9 says not to reach for.
		"textures": [
			preload("res://sprites/cars/truck_red.png"),
			preload("res://sprites/cars/truck_blue.png"),
			preload("res://sprites/cars/truck_white.png"),
			preload("res://sprites/cars/truck_silver.png"),
			preload("res://sprites/cars/truck_tanker.png"),
			preload("res://sprites/cars/truck_logger.png"),
		],
	},
	{
		"kind": "trailer", "width_frac": 0.62, "height_frac": 3.74, "weight": 4,
		"speed_frac_min": 0.78, "speed_frac_max": 0.95,
		# A pickup towing something (boat / camper / flatbed / cargo box / jet-ski).
		# Nearly as long as a semi and the slowest-driving kind in the table, which is
		# the point of it: a rolling roadblock you have to commit to going around.
		"textures": [
			preload("res://sprites/cars/trailer_boat.png"),
			preload("res://sprites/cars/trailer_camper.png"),
			preload("res://sprites/cars/trailer_atv.png"),
			preload("res://sprites/cars/trailer_cargo.png"),
			preload("res://sprites/cars/trailer_jetski.png"),
		],
	},
	{
		"kind": "bus", "width_frac": 0.6, "height_frac": 2.43, "weight": 3,
		"speed_frac_min": 0.75, "speed_frac_max": 0.95,
		# Transit and coach are two entries rather than two textures under one,
		# because a coach really is the longer vehicle: 115x320 (aspect 2.78)
		# against the transit's 115x279 (2.43). height_frac is per-kind and
		# Car._rebuild() scales each axis independently, so one number cannot
		# serve both — the one that fits the transit squashed every coach by
		# 14.5% from 9eb90db until FleetProbe measured it (docs §5 session R).
		# Same reasoning that kept the 3.74-aspect trailers out of the pickup
		# entry. width_frac stays 0.6 for both: the two sprites are the same
		# 115px wide, so they differ in length only. The single entry's old
		# weight of 5 is split 3/2, so the table still totals 100.
		"textures": [
			preload("res://sprites/cars/bus_transit.png"),
		],
	},
	{
		"kind": "coach", "width_frac": 0.6, "height_frac": 2.78, "weight": 2,
		"speed_frac_min": 0.75, "speed_frac_max": 0.95,
		"textures": [
			preload("res://sprites/cars/bus_coach.png"),
		],
	},

	# --- The four service vehicles off buyuka.png (session AB) --------------
	#
	# One kind each, one texture each, for the reason session R split `coach`
	# out of `bus`: their aspects run 3.20 to 3.39, so any single height_frac
	# would squash one of them by up to 5% — and each has its own speed band
	# anyway, which is most of what makes them read as different vehicles.
	# Every height_frac below is its sprite's exact aspect, so FleetProbe
	# reports 0.0% stretch on all four.
	#
	# **width_frac is measured off the sheet, not chosen.** buyuka.png also
	# draws a police car and a taxi — two vehicles this game already draws at
	# width_frac 0.62 — so their 204px in that sheet is the ruler every other
	# vehicle on it is scaled against (see scripts/dev/extract_service.py).
	# That is why the fire truck ends up the widest thing in the fleet at 0.70:
	# it is what the artist drew, not a guess. Its sprite is 97px for a 37px
	# on-road vehicle, the same pixels-per-lane-fraction as the semis, so it
	# carries no more detail than anything around it.
	#
	# The sheet's police car and taxi are deliberately *not* imported: both
	# kinds already exist, and `taxi.png` in particular is a derivative of
	# sedan_yellow.png specifically so it belongs to the fleet (§7).
	{
		"kind": "ambulance", "width_frac": 0.64, "height_frac": 3.39, "weight": 2,
		# Quicker than the trucks it is shaped like — an ambulance that trundles
		# along at the semis' 0.75-0.95 reads as a van with a cross painted on
		# it. This is the same argument the sports car's low band is made from.
		"speed_frac_min": 0.55, "speed_frac_max": 0.80,
		"textures": [
			preload("res://sprites/cars/ambulance.png"),
		],
	},
	{
		"kind": "fire_truck", "width_frac": 0.70, "height_frac": 3.20, "weight": 2,
		"speed_frac_min": 0.72, "speed_frac_max": 0.92,
		"textures": [
			preload("res://sprites/cars/fire_truck.png"),
		],
	},
	{
		"kind": "garbage_truck", "width_frac": 0.69, "height_frac": 3.22, "weight": 2,
		# The slowest-driving thing in the table, one notch past the trailer's
		# 0.78 — a rear-loader that stops every thirty metres is the one vehicle
		# on a motorway you genuinely come up behind, and `trailer`'s comment
		# explains what that is worth as an obstacle.
		"speed_frac_min": 0.80, "speed_frac_max": 0.96,
		"textures": [
			preload("res://sprites/cars/garbage_truck.png"),
		],
	},
	{
		# Distinct from `van`'s three box vans, which are 1.55-aspect panel vans
		# — this is a 3.28-aspect box body on a cab chassis, more than twice as
		# long on the road (111px against 48).
		"kind": "box_truck", "width_frac": 0.63, "height_frac": 3.28, "weight": 3,
		"speed_frac_min": 0.68, "speed_frac_max": 0.90,
		"textures": [
			preload("res://sprites/cars/box_truck.png"),
		],
	},
	{
		# Still the original top-down bikes. motorlu.png (session Q) is drawn as a
		# front elevation — you are looking at the rider's face, with the headlight
		# and front wheel at the bottom of the frame — so in a top-down game its
		# bikes ride straight at the player while every other vehicle drives away.
		# No transform fixes that: rotating 180 puts the rider upside down, and a
		# flipped front view is not a rear view. It needs top-down art, not a
		# different transform of these.
		"kind": "motorcycle", "width_frac": 0.30, "height_frac": 2.07, "weight": 5,
		"speed_frac_min": 0.35, "speed_frac_max": 0.65,
		"textures": [
			preload("res://sprites/cars/moto_red.png"),
			preload("res://sprites/cars/moto_maroon.png"),
			preload("res://sprites/cars/moto_teal.png"),
		],
	},
]

# One steering + confirm binding per player slot. Keeps 4 players on a single
# keyboard: three WASD-shaped clusters (A/D+W, F/H+T, J/L+I) plus arrows.
#
# `down` is Pile Up's soft drop — hold it and the descending brick falls
# faster. Each one is the key physically below that player's confirm key and
# between their two steering keys (A-S-D, F-G-H, J-K-L, and the arrow
# cluster's own Down), so "down" means down on the keyboard as well as in
# the game. Don't Crash does not read it.
# skill_opponent/skill_self are the two skill-choice-pickup buttons (see
# PlayerBoard.gd) — deliberately separate keys from steering, not reused
# left/right, since a skill choice never pauses driving. This project targets
# PS5 eventually (steering -> stick, skill_opponent/self -> a pair of
# shoulder/face buttons), so these keyboard bindings are just a placeholder
# stand-in and don't need to be especially ergonomic — chosen to flank each
# player's own confirm key on the keyboard (Q/W/E, ,/Up/., R/T/Y, U/I/O) only
# as a mnemonic, not because that positioning matters long-term.
const PLAYER_CONFIGS: Array[Dictionary] = [
	{"name": "P1", "left": KEY_A, "right": KEY_D, "down": KEY_S, "confirm": KEY_W, "skill_opponent": KEY_Q, "skill_self": KEY_E, "steer_label": "A / D", "confirm_label": "W"},
	{"name": "P2", "left": KEY_LEFT, "right": KEY_RIGHT, "down": KEY_DOWN, "confirm": KEY_UP, "skill_opponent": KEY_COMMA, "skill_self": KEY_PERIOD, "steer_label": "Left / Right", "confirm_label": "Up"},
	{"name": "P3", "left": KEY_F, "right": KEY_H, "down": KEY_G, "confirm": KEY_T, "skill_opponent": KEY_R, "skill_self": KEY_Y, "steer_label": "F / H", "confirm_label": "T"},
	{"name": "P4", "left": KEY_J, "right": KEY_L, "down": KEY_K, "confirm": KEY_I, "skill_opponent": KEY_U, "skill_self": KEY_O, "steer_label": "J / L", "confirm_label": "I"},
]


# --- Pile Up (MODE_TOWER) --------------------------------------------------

# The seven car-part tetromino bricks, extracted from the user's yenib.png by
# scripts/dev/extract_blocks.py. Every sprite is normalised there to an exact
# `cols x rows` grid of square cells, so one scale factor (cell / 100) fits
# any of them and nothing here needs a per-piece fudge.
#
# The sheet draws three of the pieces in a different orientation than the
# shapes below, and the art is *not* rotated to fit: each cell is its own
# upright little panel (a wheel, a battery, a radiator), so the extractor
# rearranges the cells and leaves every block the right way up. `boxes` and
# `cols`/`rows` here are the source of truth and the art is fitted to them —
# extract_blocks.py's CELLS table has to be updated to match if these ever
# change, and nothing checks that for you at runtime.
#
# `boxes` is the piece's collision, in cell units measured from the top-left
# of its own bounding box. It is deliberately *merged rectangles* rather than
# one box per cell: a stack of four separate unit boxes presents internal
# edges that a neighbouring brick's corner can catch on, which reads as a
# tower snagging on nothing. Every tetromino decomposes into one or two
# rectangles, so the merged form costs nothing and is strictly more stable.
#
# `color` is a flat approximation of each sprite's body hue, for the UI bits
# that need a plain Color rather than the texture (the next-piece card, the
# landing flash) — same role, and same caveat about not updating itself, as
# PLAYER_SKINS' own "color" entry.
const TETROMINOES: Array[Dictionary] = [
	{
		"name": "I", "cols": 4, "rows": 1, "color": Color(0.30, 0.79, 0.80),
		"texture": preload("res://sprites/blocks/piece_i.png"),
		"boxes": [Rect2(0, 0, 4, 1)],
	},
	{
		"name": "O", "cols": 2, "rows": 2, "color": Color(0.96, 0.79, 0.15),
		"texture": preload("res://sprites/blocks/piece_o.png"),
		"boxes": [Rect2(0, 0, 2, 2)],
	},
	{
		"name": "T", "cols": 3, "rows": 2, "color": Color(0.70, 0.40, 0.80),
		"texture": preload("res://sprites/blocks/piece_t.png"),
		"boxes": [Rect2(0, 0, 3, 1), Rect2(1, 1, 1, 1)],
	},
	{
		"name": "S", "cols": 3, "rows": 2, "color": Color(0.47, 0.72, 0.27),
		"texture": preload("res://sprites/blocks/piece_s.png"),
		"boxes": [Rect2(1, 0, 2, 1), Rect2(0, 1, 2, 1)],
	},
	{
		"name": "Z", "cols": 3, "rows": 2, "color": Color(0.85, 0.24, 0.21),
		"texture": preload("res://sprites/blocks/piece_z.png"),
		"boxes": [Rect2(0, 0, 2, 1), Rect2(1, 1, 2, 1)],
	},
	{
		"name": "L", "cols": 2, "rows": 3, "color": Color(0.94, 0.55, 0.14),
		"texture": preload("res://sprites/blocks/piece_l.png"),
		"boxes": [Rect2(0, 0, 1, 3), Rect2(1, 2, 1, 1)],
	},
	{
		"name": "J", "cols": 3, "rows": 2, "color": Color(0.20, 0.35, 0.75),
		"texture": preload("res://sprites/blocks/piece_j.png"),
		"boxes": [Rect2(2, 0, 1, 1), Rect2(0, 1, 3, 1)],
	},
]
