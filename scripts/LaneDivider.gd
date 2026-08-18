extends Node2D
class_name LaneDivider

## A grass median with a scrolling row of trees, used to separate one
## player's road from the next so the boards read as clearly distinct lanes.

@export var width: float = 48.0
@export var height: float = 620.0

const GRASS_COLOR := Color(0.361, 0.478, 0.235, 1.0)
const TRUNK_COLOR := Color(0.365, 0.243, 0.129, 1.0)
const CANOPY_COLOR := Color(0.176, 0.376, 0.176, 1.0)
const CANOPY_HIGHLIGHT := Color(0.243, 0.478, 0.227, 1.0)

const TREE_SPACING := 130.0
const SCROLL_SPEED := 90.0

var offset: float = 0.0

func _process(delta: float) -> void:
	offset = fmod(offset + SCROLL_SPEED * delta, TREE_SPACING)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(0, 0, width, height), GRASS_COLOR)

	var cx := width / 2.0
	var y := -TREE_SPACING + offset
	while y < height + TREE_SPACING:
		_draw_tree(cx, y)
		y += TREE_SPACING

func _draw_tree(cx: float, cy: float) -> void:
	var trunk_w := width * 0.14
	var trunk_h := width * 0.24
	draw_rect(Rect2(cx - trunk_w / 2.0, cy, trunk_w, trunk_h), TRUNK_COLOR)

	var canopy_r := width * 0.34
	draw_circle(Vector2(cx, cy - canopy_r * 0.5), canopy_r, CANOPY_COLOR)
	draw_circle(Vector2(cx - canopy_r * 0.3, cy - canopy_r * 0.75), canopy_r * 0.5, CANOPY_HIGHLIGHT)
