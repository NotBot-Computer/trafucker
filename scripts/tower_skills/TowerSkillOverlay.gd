extends Node2D
class_name TowerSkillOverlay

## Pile Up's world-space canvas ABOVE the bricks and the near ground, for
## skills. TowerMode's own _draw() lands under everything (a CanvasItem
## draws before its children — the same reason Don't Crash has SkillOverlay),
## so anything a skill wants painted *on* the tower goes through here. Sits
## after Ground in Foreground, so it is the last world-space thing drawn.
##
## Holds no state: it calls draw_over() on whatever the mode has live, in
## the order they were applied, and TowerMode asks it to redraw every frame
## an effect is live plus one frame after the last one leaves (a CanvasItem
## keeps its last draw list until asked again).

var mode = null # TowerMode — untyped, same cyclic-reference rule as TowerSkill.mode

func _draw() -> void:
	if mode == null:
		return
	for effect in mode.active_effects:
		effect.draw_over(self)
