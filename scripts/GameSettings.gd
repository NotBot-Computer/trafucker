extends Node

var player_count: int = 2

var default_skins: Array[Color] = [
	Color(0.231, 0.435, 0.878), # Blue
	Color(0.878, 0.278, 0.231), # Red
	Color(0.204, 0.780, 0.349), # Green
	Color(0.949, 0.788, 0.204), # Yellow
	Color(0.788, 0.204, 0.788), # Purple
	Color(0.976, 0.541, 0.075), # Orange
]

var skins: Array[Color] = [Color(0.231, 0.435, 0.878), Color(0.878, 0.278, 0.231)]

# One steering + confirm binding per player slot. Keeps 4 players on a single
# keyboard: three WASD-shaped clusters (A/D+W, F/H+T, J/L+I) plus arrows.
const PLAYER_CONFIGS: Array[Dictionary] = [
	{"name": "P1", "left": KEY_A, "right": KEY_D, "confirm": KEY_W, "steer_label": "A / D", "confirm_label": "W"},
	{"name": "P2", "left": KEY_LEFT, "right": KEY_RIGHT, "confirm": KEY_UP, "steer_label": "Left / Right", "confirm_label": "Up"},
	{"name": "P3", "left": KEY_F, "right": KEY_H, "confirm": KEY_T, "steer_label": "F / H", "confirm_label": "T"},
	{"name": "P4", "left": KEY_J, "right": KEY_L, "confirm": KEY_I, "steer_label": "J / L", "confirm_label": "I"},
]
