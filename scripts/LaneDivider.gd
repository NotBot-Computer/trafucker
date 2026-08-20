extends Node2D
class_name LaneDivider

## A grass-and-trees median (same source art as the road), used to separate
## one player's road from the next so the boards read as clearly distinct
## lanes. Scrolls on its own timer using the same speed ramp as a board, so
## it stays roughly in sync with the traffic around it.

@export var width: float = 48.0
@export var height: float = 620.0

const MEDIAN_TEXTURE := preload("res://sprites/road/median_tile.png")
const BASE_SPEED := 160.0
const SPEED_PER_SECOND := 6.0

var elapsed: float = 0.0
var distance: float = 0.0

func reset() -> void:
	elapsed = 0.0
	distance = 0.0
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	var speed := BASE_SPEED + elapsed * SPEED_PER_SECOND
	distance += speed * delta
	queue_redraw()

func _draw() -> void:
	var scale_factor := width / MEDIAN_TEXTURE.get_width()
	var tile_h := MEDIAN_TEXTURE.get_height() * scale_factor
	var scroll := fmod(distance, tile_h)

	# Same anchoring as Road._draw(): slide toward +y (down, toward the
	# player) so the median matches the direction traffic moves in.
	var y := scroll - tile_h
	while y < height:
		draw_texture_rect(MEDIAN_TEXTURE, Rect2(0, y, width, tile_h), false)
		y += tile_h
