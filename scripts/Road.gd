extends Node2D
class_name Road

@export var width: float = 360.0
@export var height: float = 620.0
@export var lane_count: int = 5
# How far past [0, height] to keep drawing tiles, in this board's own local
# space. Set by Main (via PlayerBoard.set_vertical_margin) whenever the
# camera has to zoom out to fit a wider player count — that zoom-out widens
# the vertical slice the camera can see without changing board_height, and
# without this margin that extra strip above/below the board shows bare
# background instead of road.
@export var render_margin: float = 0.0

var distance: float = 0.0

# Matches the road/shoulder proportions baked into ROAD_TEXTURE, so the
# gray asphalt in the image lines up with where lane_center_x() actually
# lets cars drive.
const SHOULDER_RATIO := 0.1287

const ROAD_TEXTURE := preload("res://sprites/road/road_tile.png")

func lane_width() -> float:
	var shoulder := width * SHOULDER_RATIO
	return (width - shoulder * 2.0) / float(lane_count)

func lane_center_x(lane: int) -> float:
	var shoulder := width * SHOULDER_RATIO
	var lw := lane_width()
	return shoulder + lw * lane + lw * 0.5

func _draw() -> void:
	var scale_factor := width / ROAD_TEXTURE.get_width()
	var tile_h := ROAD_TEXTURE.get_height() * scale_factor
	var scroll := fmod(distance, tile_h)

	# Tiles anchor just above the top edge and slide toward +y (down, toward
	# the player) as distance grows, matching the direction traffic moves in.
	# render_margin extends both bounds so tiling still fully covers the
	# camera's visible area even when it sees past [0, height] (see the field
	# comment above) — with render_margin at its default 0, this is identical
	# to the original fixed [0, height] loop.
	var top_edge := -render_margin
	var bottom_edge := height + render_margin
	var y := scroll - tile_h
	while y > top_edge:
		y -= tile_h
	while y < bottom_edge:
		draw_texture_rect(ROAD_TEXTURE, Rect2(0, y, width, tile_h), false)
		y += tile_h
