extends Node2D
class_name TowerGround

## The near ground in Pile Up — the grass shelf the tower's outcrop rises out
## of, drawn from the bottom band of the same art `TowerBackground` uses.
##
## Two things make it worth having as its own node rather than more painting
## inside TowerMode.
##
## **It is a foreground layer.** It sits after PiecesContainer in the scene,
## so it draws *over* the bricks: a brick knocked off the tower slides down
## behind the grass and is gone, which is both how it should read and how the
## despawn gets hidden. Everything else TowerMode paints is background.
##
## **It moves at the world's rate, not the backdrop's.** The backdrop scrolls
## at a fraction of the camera so distance reads as distance (see
## TowerBackground); this ground is *where the tower actually stands*, so it
## has to track the camera exactly or the outcrop would slide out of the
## ground it is supposed to be growing from. The two are cut from one image
## and are aligned at the start of a match, then separate as the tower
## climbs — which is the parallax doing its job, near ground dropping away
## faster than far.

# Public: TowerMode cuts the outcrop's stone out of the same image, so the
# rock the tower stands on is the same rock the ground is made of.
const ART := preload("res://sprites/bg/tower_backdrop.png")

# The row in the source art where the near grass shelf's top edge sits,
# measured rather than guessed: it is where the fraction of the row that is
# grass jumps from ~0.43 to ~0.77 across the full width. Re-measure it if the
# art is ever replaced — TowerBackground anchors itself to the same row, and
# the two only line up because they agree about this number.
const GROUND_LINE_PX := 874.0

# Below the art's own bottom edge, in case a taller viewport ever sees past
# it. Sampled from the stone band the image ends on.
const UNDER_COLOR := Color8(74, 54, 48)

var ground_y: float = 170.0
var view_width: float = 1500.0

func configure(world_ground_y: float, width: float) -> void:
	ground_y = world_ground_y
	view_width = width
	queue_redraw()

func _draw() -> void:
	var tex_size: Vector2 = ART.get_size()
	var s: float = view_width / tex_size.x
	var src := Rect2(0.0, GROUND_LINE_PX, tex_size.x, tex_size.y - GROUND_LINE_PX)
	var band_h: float = src.size.y * s
	draw_texture_rect_region(ART, Rect2(-view_width * 0.5, ground_y, view_width, band_h), src)
	draw_rect(Rect2(-view_width * 0.5, ground_y + band_h, view_width, 1200.0), UNDER_COLOR, true)
