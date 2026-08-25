extends Control
class_name TowerBackground

## Pile Up's backdrop, drawn in screen space from its own CanvasLayer behind
## everything else.
##
## It is deliberately *not* a world-space node the camera moves over. The
## camera pans up without limit as the tower grows, so a fixed piece of world
## art would be left behind within a few bricks; instead TowerMode pushes a
## `scroll` value derived from the camera and the backdrop slides down at a
## fraction of that rate. The parallax is the point rather than decoration —
## it is the only thing on screen that says the tower is *climbing*, since
## the tower's own top is pinned to a fixed height in frame by design and the
## height guide lines are far too sparse to read as motion on their own.
##
## Above the art's own top edge the sky simply continues in the image's own
## sky colour, so a tall tower scrolls into open sky instead of into a hard
## edge with the clear colour behind it.
##
## It is anchored by its *ground line* rather than by its bottom edge, so it
## can be lined up with TowerGround — the near-ground band cut from the same
## image and drawn in world space at the foot of the tower's outcrop. Both
## refer to TowerGround.GROUND_LINE_PX; at the start of a match they coincide
## exactly and read as one continuous picture, and they separate as the tower
## climbs because the near ground falls away faster than the far one. Losing
## a little of the art off the bottom of the screen is the price, and it is
## the stone band nobody looks at.

const BACKDROP := preload("res://sprites/bg/tower_backdrop.png")

# Sampled from the source image's own top rows and bottom rows, so the
# continuations above and below are seamless with the art rather than
# approximately similar to it. If the backdrop is ever replaced, re-sample
# these — they are not derived at runtime.
const SKY_COLOR := Color8(46, 141, 248)
const GROUND_COLOR := Color8(59, 55, 51)

# The backdrop is bright, busy pixel art and the bricks are bright, busy
# pixel art. Without a scrim the tower does not separate from the trees
# behind it. Kept light: the user chose this background, and washing it out
# to make the foreground easy would be solving the wrong problem.
const SCRIM := Color(0.05, 0.06, 0.16, 0.13)

var scroll: float = 0.0
# Where the art's ground line should sit on screen before any scrolling —
# pushed in by TowerMode, which is the only thing that knows where the world
# origin lands in frame.
var ground_screen_y: float = 746.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func set_ground_screen_y(value: float) -> void:
	if is_equal_approx(value, ground_screen_y):
		return
	ground_screen_y = value
	queue_redraw()

func set_scroll(value: float) -> void:
	if is_equal_approx(value, scroll):
		return
	scroll = value
	queue_redraw()

func _draw() -> void:
	var tex_size: Vector2 = BACKDROP.get_size()
	# Fit to width and let the height fall where it does: the art is 3:2 and
	# the viewport is closer to 15:8, so fitting to width always overfills
	# vertically, which is what leaves headroom to scroll through.
	var draw_w: float = size.x
	var scale_f: float = draw_w / tex_size.x
	var draw_h: float = tex_size.y * scale_f
	# Anchored so the art's own ground line lands where TowerGround draws the
	# near ground, not so its bottom edge meets the bottom of the screen.
	var top: float = ground_screen_y - TowerGround.GROUND_LINE_PX * scale_f + scroll

	if top > 0.0:
		draw_rect(Rect2(0.0, 0.0, size.x, top), SKY_COLOR, true)
	draw_texture_rect(BACKDROP, Rect2(0.0, top, draw_w, draw_h), false)
	var bottom: float = top + draw_h
	if bottom < size.y:
		draw_rect(Rect2(0.0, bottom, size.x, size.y - bottom), GROUND_COLOR, true)

	draw_rect(Rect2(Vector2.ZERO, size), SCRIM, true)
