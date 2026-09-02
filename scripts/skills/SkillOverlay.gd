extends Node2D
class_name SkillOverlay

## One child node PlayerBoard adds to itself so a skill can draw ABOVE the
## traffic and the player car.
##
## PlayerBoard's own _draw() cannot: a CanvasItem draws itself before its
## children, so everything drawn there lands under ObstacleContainer and
## PlayerCar (the boost bar has always been behind passing traffic for
## exactly this reason). Road sits at z_index -10 and Nitro's car/energy at
## 3/2, so OVERLAY_Z is picked to clear all of them.
##
## Holds no state of its own — it just calls draw_overlay() on whatever the
## board currently has live, in the same order they were applied.

const OVERLAY_Z := 6

var board = null # PlayerBoard — untyped, same cyclic-reference rule as SkillEffect

func _ready() -> void:
	z_index = OVERLAY_Z

func _draw() -> void:
	if board == null:
		return
	for effect in board.active_effects:
		effect.draw_overlay()
