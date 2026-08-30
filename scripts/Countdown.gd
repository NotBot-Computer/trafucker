extends Control
class_name Countdown

## The "3 — 2 — 1 — GO!" that opens a round, in both modes.
##
## Lives in a mode's HUD CanvasLayer and draws in screen space, so it is
## unaffected by either mode's camera — Don't Crash zooms its camera out to
## fit wider player counts and Pile Up pans its up the tower, and a countdown
## that scaled or slid with either of those would be wrong.
##
## **This node does not pause anything, and it does not tick itself.** It
## draws, and it emits `finished` when the owner has advanced it far enough.
##
## Holding the game at the line is the caller's job, and each mode already
## has a natural way to do it (Main leaves its boards' `active` false,
## TowerMode sits in a `countdown` state before the first turn). A countdown
## that reached into the game to freeze it would have to know what "frozen"
## means in two modes that share no update loop at all.
##
## The clock is the caller's job for a sharper reason. **The two modes run on
## different clocks**: Don't Crash lives in `_process`, and Pile Up moved its
## whole model into `_physics_process` because the shape queries it steers by
## are only valid there. If this node ticked itself in `_process`, Pile Up's
## first brick would be created from an idle frame — a frame later than the
## physics step that everything else about a turn happens on. That is not a
## bug you can see, but it is one you can measure: it shifted TowerProbe's
## matches by a frame at turn one and, through ordinary chaotic divergence,
## every tower after it. So `advance()` is called by the owner, from
## whichever loop that mode's own state lives in.
##
## Art is `sprites/ui/count_[123].png` and `count_go.png`, cut from the
## user's sayım.png by scripts/dev/extract_countdown.py. The three digits are
## the same size with the numeral dead centre in each (the extractor centres
## them on the numeral rather than on their own bounding box), so the count
## ticks in place instead of shuffling sideways from 3 to 2 to 1.

signal finished

const STEPS := [
	preload("res://sprites/ui/count_3.png"),
	preload("res://sprites/ui/count_2.png"),
	preload("res://sprites/ui/count_1.png"),
	preload("res://sprites/ui/count_go.png"),
]

const STEP_TIME := 0.68 # per digit
const GO_TIME := 0.62

# Sized off the *shorter* of the two fits so a wide glyph on a narrow window
# can't run off the sides: GO! is 1156x571 against a digit's 536x414, so
# height alone would let it grow past the frame at low aspect ratios.
const HEIGHT_FRAC := 0.34
const WIDTH_FRAC := 0.52
const CENTER_FRAC := 0.45 # a little above centre: dead centre sits on Pile Up's platform

# It arrives oversized and slams down to full size, rather than growing into
# place — the impact is the whole reason a countdown reads as a countdown and
# not as a caption. It then leaves the other way, growing slightly as it
# fades, so consecutive digits never look like the same image reappearing.
const POP_TIME := 0.13
const POP_SCALE := 1.7
const POP_EASE := 0.34 # < 1 is ease-out: most of the travel in the first few frames
const EXIT_TIME := 0.15
const EXIT_SCALE := 1.22

# A wash over the playfield, so "the round has not started" is legible from
# the screen rather than only from the fact that nothing is moving. It clears
# across GO! itself, which is what makes GO! read as the release.
const DIM_COLOR := Color(0.04, 0.05, 0.09)
const DIM_ALPHA := 0.34

var running := false

var _index := 0
var _timer := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	resized.connect(queue_redraw)

func start() -> void:
	_index = 0
	_timer = 0.0
	running = true
	visible = true
	queue_redraw()

## Ends the count immediately without emitting `finished` — for a mode
## tearing down a round mid-countdown, not for skipping ahead.
func cancel() -> void:
	running = false
	visible = false

func _step_time(i: int) -> float:
	return GO_TIME if i == STEPS.size() - 1 else STEP_TIME

## Moves the count on. Call from the owning mode's own update loop — see the
## header for why this is not a `_process`.
func advance(delta: float) -> void:
	if not running:
		return
	_timer += delta
	while running and _timer >= _step_time(_index):
		_timer -= _step_time(_index)
		_index += 1
		if _index >= STEPS.size():
			running = false
			visible = false
			finished.emit()
			return
	queue_redraw()

func _draw() -> void:
	if not running:
		return
	var dur: float = _step_time(_index)
	var t: float = clampf(_timer, 0.0, dur)
	var last: bool = _index == STEPS.size() - 1

	var dim: float = DIM_ALPHA * (1.0 - t / dur) if last else DIM_ALPHA
	if dim > 0.001:
		draw_rect(Rect2(Vector2.ZERO, size), Color(DIM_COLOR.r, DIM_COLOR.g, DIM_COLOR.b, dim), true)

	var scale := 1.0
	var alpha := 1.0
	if t < POP_TIME:
		scale = lerpf(POP_SCALE, 1.0, ease(t / POP_TIME, POP_EASE))
	elif t > dur - EXIT_TIME:
		var k: float = (t - (dur - EXIT_TIME)) / EXIT_TIME
		scale = lerpf(1.0, EXIT_SCALE, k)
		alpha = 1.0 - k

	var tex: Texture2D = STEPS[_index]
	var tex_size: Vector2 = tex.get_size()
	var fit: float = minf(size.y * HEIGHT_FRAC / tex_size.y, size.x * WIDTH_FRAC / tex_size.x)
	var draw_size: Vector2 = tex_size * fit * scale
	var at := Vector2(
		(size.x - draw_size.x) * 0.5,
		size.y * CENTER_FRAC - draw_size.y * 0.5
	)
	draw_texture_rect(tex, Rect2(at, draw_size), false, Color(1.0, 1.0, 1.0, alpha))
