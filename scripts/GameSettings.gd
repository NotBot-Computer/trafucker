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

# Traffic car textures, picked at random by PlayerBoard when spawning.
const TRAFFIC_SEDAN_TEXTURES: Array[Texture2D] = [
	preload("res://sprites/cars/sedan_white.png"),
	preload("res://sprites/cars/sedan_black.png"),
	preload("res://sprites/cars/sedan_silver.png"),
	preload("res://sprites/cars/sedan_slate.png"),
	preload("res://sprites/cars/sedan_tan.png"),
	preload("res://sprites/cars/sedan_maroon.png"),
]

const TRAFFIC_TRUCK_TEXTURES: Array[Texture2D] = [
	preload("res://sprites/cars/truck_white.png"),
	preload("res://sprites/cars/truck_tan.png"),
	preload("res://sprites/cars/truck_bluegray.png"),
]

# One steering + confirm binding per player slot. Keeps 4 players on a single
# keyboard: three WASD-shaped clusters (A/D+W, F/H+T, J/L+I) plus arrows.
const PLAYER_CONFIGS: Array[Dictionary] = [
	{"name": "P1", "left": KEY_A, "right": KEY_D, "confirm": KEY_W, "steer_label": "A / D", "confirm_label": "W"},
	{"name": "P2", "left": KEY_LEFT, "right": KEY_RIGHT, "confirm": KEY_UP, "steer_label": "Left / Right", "confirm_label": "Up"},
	{"name": "P3", "left": KEY_F, "right": KEY_H, "confirm": KEY_T, "steer_label": "F / H", "confirm_label": "T"},
	{"name": "P4", "left": KEY_J, "right": KEY_L, "confirm": KEY_I, "steer_label": "J / L", "confirm_label": "I"},
]
