extends Node

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
var bot_difficulty: int = 1

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
# across the lane markings. Heavier/slower-driving kinds (trucks, buses) sit
# near the top of that range so you catch up to them quickly; nimbler kinds
# (motorcycles) sit near the bottom so they roughly keep pace with you.
const TRAFFIC_KINDS: Array[Dictionary] = [
	{
		"kind": "sedan", "width_frac": 0.62, "height_frac": 1.69, "weight": 30,
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
		"kind": "suv", "width_frac": 0.68, "height_frac": 1.79, "weight": 18,
		"speed_frac_min": 0.55, "speed_frac_max": 0.85,
		"textures": [
			preload("res://sprites/cars/suv_gold.png"),
			preload("res://sprites/cars/suv_silver.png"),
			preload("res://sprites/cars/suv_blue.png"),
			preload("res://sprites/cars/suv_olive.png"),
			preload("res://sprites/cars/suv_white.png"),
			preload("res://sprites/cars/suv_gray.png"),
		],
	},
	{
		"kind": "pickup", "width_frac": 0.62, "height_frac": 1.52, "weight": 14,
		"speed_frac_min": 0.6, "speed_frac_max": 0.9,
		"textures": [
			preload("res://sprites/cars/pickup_red.png"),
			preload("res://sprites/cars/pickup_green.png"),
			preload("res://sprites/cars/pickup_olivedark.png"),
			preload("res://sprites/cars/pickup_blue.png"),
			preload("res://sprites/cars/pickup_bluedark.png"),
			preload("res://sprites/cars/pickup_brown.png"),
			preload("res://sprites/cars/pickup_teal.png"),
			preload("res://sprites/cars/pickup_olive.png"),
		],
	},
	{
		"kind": "van", "width_frac": 0.58, "height_frac": 1.55, "weight": 12,
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
		"kind": "truck", "width_frac": 0.66, "height_frac": 4.34, "weight": 8,
		"speed_frac_min": 0.75, "speed_frac_max": 0.95,
		"textures": [
			preload("res://sprites/cars/truck_blue.png"),
			preload("res://sprites/cars/truck_red.png"),
			preload("res://sprites/cars/truck_white.png"),
			preload("res://sprites/cars/truck_black.png"),
		],
	},
	{
		"kind": "bus", "width_frac": 0.60, "height_frac": 2.43, "weight": 6,
		"speed_frac_min": 0.75, "speed_frac_max": 0.95,
		"textures": [
			preload("res://sprites/cars/bus_transit.png"),
			preload("res://sprites/cars/bus_coach.png"),
		],
	},
	{
		"kind": "motorcycle", "width_frac": 0.30, "height_frac": 2.07, "weight": 6,
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
# skill_opponent/skill_self are the two skill-choice-pickup buttons (see
# PlayerBoard.gd) — deliberately separate keys from steering, not reused
# left/right, since a skill choice never pauses driving. This project targets
# PS5 eventually (steering -> stick, skill_opponent/self -> a pair of
# shoulder/face buttons), so these keyboard bindings are just a placeholder
# stand-in and don't need to be especially ergonomic — chosen to flank each
# player's own confirm key on the keyboard (Q/W/E, ,/Up/., R/T/Y, U/I/O) only
# as a mnemonic, not because that positioning matters long-term.
const PLAYER_CONFIGS: Array[Dictionary] = [
	{"name": "P1", "left": KEY_A, "right": KEY_D, "confirm": KEY_W, "skill_opponent": KEY_Q, "skill_self": KEY_E, "steer_label": "A / D", "confirm_label": "W"},
	{"name": "P2", "left": KEY_LEFT, "right": KEY_RIGHT, "confirm": KEY_UP, "skill_opponent": KEY_COMMA, "skill_self": KEY_PERIOD, "steer_label": "Left / Right", "confirm_label": "Up"},
	{"name": "P3", "left": KEY_F, "right": KEY_H, "confirm": KEY_T, "skill_opponent": KEY_R, "skill_self": KEY_Y, "steer_label": "F / H", "confirm_label": "T"},
	{"name": "P4", "left": KEY_J, "right": KEY_L, "confirm": KEY_I, "skill_opponent": KEY_U, "skill_self": KEY_O, "steer_label": "J / L", "confirm_label": "I"},
]
