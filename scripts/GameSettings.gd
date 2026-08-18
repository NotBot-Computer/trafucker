extends Node

var player_count: int = 2

# Selectable player car skins: shown in SkinSelect, then applied to the
# player's Car in Main. Order matters for the default index (P1=0, P2=1...).
const PLAYER_SKINS: Array[Dictionary] = [
	{"name": "Blue", "texture": preload("res://sprites/cars/sedan_blue.png")},
	{"name": "Red", "texture": preload("res://sprites/cars/sedan_red.png")},
	{"name": "Green", "texture": preload("res://sprites/cars/sedan_green.png")},
	{"name": "Yellow", "texture": preload("res://sprites/cars/sedan_yellow.png")},
	{"name": "Purple", "texture": preload("res://sprites/cars/sedan_purple.png")},
	{"name": "Orange", "texture": preload("res://sprites/cars/sedan_orange.png")},
]

# Chosen texture per player, filled in by SkinSelect before Main starts.
var skins: Array[Texture2D] = [PLAYER_SKINS[0]["texture"], PLAYER_SKINS[1]["texture"]]

# Traffic vehicle kinds. width_frac is a fraction of lane width; height is
# width * height_frac. weight controls how often a kind is picked relative
# to the others (see PlayerBoard._pick_traffic_kind).
const TRAFFIC_KINDS: Array[Dictionary] = [
	{
		"kind": "sedan", "width_frac": 0.62, "height_frac": 1.7, "weight": 34,
		"textures": [
			preload("res://sprites/cars/sedan_white.png"),
			preload("res://sprites/cars/sedan_black.png"),
			preload("res://sprites/cars/sedan_silver.png"),
			preload("res://sprites/cars/sedan_slate.png"),
			preload("res://sprites/cars/sedan_tan.png"),
			preload("res://sprites/cars/sedan_maroon.png"),
		],
	},
	{
		"kind": "suv", "width_frac": 0.68, "height_frac": 1.8, "weight": 20,
		"textures": [
			preload("res://sprites/cars/suv_tan.png"),
			preload("res://sprites/cars/suv_gray.png"),
			preload("res://sprites/cars/suv_blue.png"),
			preload("res://sprites/cars/suv_white.png"),
		],
	},
	{
		"kind": "pickup", "width_frac": 0.62, "height_frac": 1.95, "weight": 14,
		"textures": [
			preload("res://sprites/cars/pickup_red.png"),
			preload("res://sprites/cars/pickup_olive.png"),
			preload("res://sprites/cars/pickup_teal.png"),
			preload("res://sprites/cars/pickup_white.png"),
		],
	},
	{
		"kind": "van", "width_frac": 0.58, "height_frac": 2.2, "weight": 10,
		"textures": [
			preload("res://sprites/cars/van_white.png"),
			preload("res://sprites/cars/van_blue.png"),
			preload("res://sprites/cars/van_red.png"),
		],
	},
	{
		"kind": "truck", "width_frac": 0.56, "height_frac": 2.6, "weight": 10,
		"textures": [
			preload("res://sprites/cars/truck_white.png"),
			preload("res://sprites/cars/truck_tan.png"),
			preload("res://sprites/cars/truck_bluegray.png"),
		],
	},
	{
		"kind": "bus", "width_frac": 0.60, "height_frac": 3.0, "weight": 6,
		"textures": [
			preload("res://sprites/cars/bus_transit.png"),
			preload("res://sprites/cars/bus_coach.png"),
		],
	},
	{
		"kind": "motorcycle", "width_frac": 0.30, "height_frac": 2.05, "weight": 6,
		"textures": [
			preload("res://sprites/cars/moto_red.png"),
			preload("res://sprites/cars/moto_maroon.png"),
			preload("res://sprites/cars/moto_teal.png"),
		],
	},
]

# One steering + confirm binding per player slot. Keeps 4 players on a single
# keyboard: three WASD-shaped clusters (A/D+W, F/H+T, J/L+I) plus arrows.
const PLAYER_CONFIGS: Array[Dictionary] = [
	{"name": "P1", "left": KEY_A, "right": KEY_D, "confirm": KEY_W, "steer_label": "A / D", "confirm_label": "W"},
	{"name": "P2", "left": KEY_LEFT, "right": KEY_RIGHT, "confirm": KEY_UP, "steer_label": "Left / Right", "confirm_label": "Up"},
	{"name": "P3", "left": KEY_F, "right": KEY_H, "confirm": KEY_T, "steer_label": "F / H", "confirm_label": "T"},
	{"name": "P4", "left": KEY_J, "right": KEY_L, "confirm": KEY_I, "steer_label": "J / L", "confirm_label": "I"},
]
