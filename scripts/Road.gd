extends Node2D
class_name Road

@export var width: float = 360.0
@export var height: float = 620.0
@export var lane_count: int = 5

var distance: float = 0.0

const SHOULDER_RATIO := 0.06
const SHOULDER_COLOR := Color(0.361, 0.478, 0.235)
const ROAD_COLOR := Color(0.541, 0.561, 0.596)
const MARKER_COLOR := Color(0.227, 0.247, 0.2)
const LINE_COLOR := Color(0.949, 0.949, 0.949)

func lane_width() -> float:
	var shoulder := width * SHOULDER_RATIO
	return (width - shoulder * 2.0) / float(lane_count)

func lane_center_x(lane: int) -> float:
	var shoulder := width * SHOULDER_RATIO
	var lw := lane_width()
	return shoulder + lw * lane + lw * 0.5

func _draw() -> void:
	var shoulder := width * SHOULDER_RATIO
	draw_rect(Rect2(0, 0, width, height), SHOULDER_COLOR)
	draw_rect(Rect2(shoulder, 0, width - shoulder * 2.0, height), ROAD_COLOR)

	var dash_len := 22.0
	var gap_len := 18.0
	var offset := fmod(distance * 0.5, dash_len + gap_len)
	var lw := lane_width()
	var line_width: float = max(2.0, width * 0.01)

	for lane in range(1, lane_count):
		var lx := shoulder + lw * lane
		var y := -dash_len + offset
		while y < height + dash_len:
			draw_line(Vector2(lx, y), Vector2(lx, y + dash_len), LINE_COLOR, line_width)
			y += dash_len + gap_len

	for i in range(6):
		var gy: float = fmod(i * 130.0 + offset * 2.0, height + 60.0) - 30.0
		draw_rect(Rect2(shoulder * 0.3, gy, shoulder * 0.4, 18.0), MARKER_COLOR)
		draw_rect(Rect2(width - shoulder * 0.7, gy + 40.0, shoulder * 0.4, 18.0), MARKER_COLOR)
