extends Node2D
class_name Road

@export var width: float = 360.0
@export var height: float = 620.0
@export var lane_count: int = 5

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
	var y := scroll - tile_h
	while y < height:
		draw_texture_rect(ROAD_TEXTURE, Rect2(0, y, width, tile_h), false)
		y += tile_h
