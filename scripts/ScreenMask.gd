extends Control
class_name ScreenMask

## Screen-space top/bottom vignette, drawn over the whole viewport from
## inside HUD (a CanvasLayer, so it's unaffected by the game camera's zoom).
## Exists to hide the letterboxed strip that appears above/below the boards
## whenever Main zooms the camera out to fit a wider player count (see
## Main._build_boards) — without this, that strip shows bare background with
## a visible hard edge where the road tiles stop. Fading to the same color
## as the viewport background turns that hard edge into a soft vignette.

@export var mask_color: Color = Color(0.078, 0.086, 0.165, 1.0)
var fade_height: float = 24.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_fade_height(px: float) -> void:
	fade_height = px
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	var fade: float = min(fade_height, h * 0.5)
	if fade <= 0.0:
		return
	var transparent := Color(mask_color.r, mask_color.g, mask_color.b, 0.0)

	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, fade), Vector2(0, fade)]),
		PackedColorArray([mask_color, mask_color, transparent, transparent])
	)
	draw_polygon(
		PackedVector2Array([Vector2(0, h - fade), Vector2(w, h - fade), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([transparent, transparent, mask_color, mask_color])
	)
