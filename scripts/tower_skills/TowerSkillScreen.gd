extends Control
class_name TowerSkillScreen

## Pile Up's SCREEN-space canvas for skills — a full-viewport Control on the
## HUD layer, placed before the HUD's own panels so a fog or a flash covers
## the world but never the cards, the next-brick panel or the toast.
##
## Like TowerSkillOverlay it holds no state and only fans out to
## draw_screen() on the live effects. Coordinates are the viewport's:
## (0,0) top-left, `size` is 1500x800 under the project's canvas_items
## stretch, whatever the window is.

var mode = null # TowerMode — untyped

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if mode == null:
		return
	for effect in mode.active_effects:
		effect.draw_screen(self)
