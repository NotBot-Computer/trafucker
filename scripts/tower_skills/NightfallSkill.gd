extends TowerSkill

## NIGHTFALL (pack B, id "nightfall") — an opponent skill that attacks the
## victim's *eyes*, and nothing else.
##
## Night falls on their next turn. The screen goes dark except for a lantern
## of light around the held brick, so the tower they are meant to land on is
## not there to be seen — only remembered from the moment before the lights
## went down, and from the flickers. As the brick descends the lantern brings
## the top of the stack into view for the last few cells, which is enough to
## make one correction and not enough to plan the shot. Their brick steers
## exactly as it did, falls exactly as fast, weighs exactly as much; the
## only thing taken is what they can see, which is the same restraint Don't
## Crash's Smoke Screen makes and for the same reason — a hex that both
## blinds you and changes your controls is two skills with one icon.
##
## Three things keep it a skill and not a coin flip:
##   * The dark ARRIVES. It fades in over FADE_IN from the start of the turn,
##     so the victim sees the tower with the new brick already above it and
##     gets one honest look. A blackout that was total from frame one would
##     be scored against a player who never had a chance to look.
##   * The lights FLICKER. Every second or two the dark drops to a glimpse
##     for a fraction of a second, stuttering like a bad bulb — a moment to
##     check the line against memory. Timed from a list drawn at activation,
##     so a player cannot count on the beat.
##   * The LANTERN is the brick's. It follows the held brick, so the last
##     LANTERN_CLEAR_CELLS of the descent are in the light and a landing is
##     always seen as it happens. The fault rule needs that: what falls on
##     this turn is the victim's, and they should watch it.
##
## The dark is SCREEN-space (draw_screen): it sits above the world and below
## the HUD panels, so the cards, the next brick and the toast stay readable,
## and the world underneath is not moved, tinted or hidden by anything but
## alpha. It is also strictly the victim's — it is only drawn while their
## slot is on the clock, and it fades out the instant the brick lands so the
## table watches the tower settle (or not) in daylight. Between activate()
## and the first tick the envelope is 0, so a queued hex never darkens
## anybody else's turn.
##
## Nothing is written on the mode. The two gradient textures are Resources
## owned by this effect, refcounted away with it (per-instance rather than
## static — PROJECT_STATE §12, the ObjectDB leak a `static var` causes in
## headless runs). deactivate() has nothing to free and nothing to undo.

# --- Timing -----------------------------------------------------------------

# The lights going down. Long enough for the look described above, short
# enough that a soft-dropping victim is in the dark before the stack.
const FADE_IN := 0.6
# And back up, from the moment the brick is out of the victim's hands.
const FADE_OUT := 0.3
# Glimpses: the first after GLIMPSE_FIRST seconds of piloting, then every
# GLIMPSE_GAP_MIN..MAX. Each lasts GLIMPSE_LEN and is a stutter, not a
# clean flash: on, off, on (see _glimpse). During one the dark is
# multiplied down to GLIMPSE_DARK of itself — the tower is plainly visible
# for about a tenth of a second, which is enough to see and not enough to
# act on without having already decided.
const GLIMPSE_FIRST := 1.1
const GLIMPSE_GAP_MIN := 1.3
const GLIMPSE_GAP_MAX := 2.2
const GLIMPSE_LEN := 0.18
const GLIMPSE_DARK := 0.3
const GLIMPSE_HORIZON := 14.0 # seconds of glimpses drawn at activation; a wedged brick lasts 6s at most past an ordinary descent

# --- The dark -----------------------------------------------------------------

# Night blue, not black: black over a pixel-art sky reads as a rendering
# fault, a deep blue reads as night. 0.94 hides the bricks' colour outright
# while a keen eye can still make out that *something* is there — which is
# the right amount of cruelty; total black would make the flicker the only
# information and the turn a memory test.
const DARK := Color(0.02, 0.03, 0.09)
const DARK_ALPHA := 0.94

# The lantern, in cells: fully clear out to CLEAR, falling to full dark at
# EDGE. 2.6 clear cells around the brick's centre lights the brick itself
# (the longest is 2.5 cells from centre to tip) and nothing else while it is
# high; at ~2.8 cells/s the stack top enters the soft edge about 1.7s before
# contact and the clear zone about 0.9s before — one step, maybe a turn.
const LANTERN_CLEAR_CELLS := 2.6
const LANTERN_EDGE_CELLS := 4.8
const LANTERN_MID_ALPHA := 0.55 # the soft edge's midpoint, so the falloff curves rather than ramps
const LANTERN_TEX_SIZE := 256 # the on-screen square is ~265px at this zoom; filtered, so this is plenty
# A warm cast inside the lantern, so the hole reads as light and not as a
# hole. Faint: it is over the brick the player is trying to read.
const WARM := Color(1.0, 0.78, 0.45)
const WARM_ALPHA := 0.10
const WARM_FRAC := 0.75 # of the lantern's edge radius

# Stars. Pure dressing, tiny, and kept between the HUD columns so none is
# ever half under a card; they fade near the lantern like real ones would.
const STAR_COUNT := 30
const STAR_X_MIN := 280.0
const STAR_X_MAX := 1220.0
const STAR_Y_MAX := 520.0
const STAR_SIZE_MIN := 1.0
const STAR_SIZE_MAX := 2.2
const STAR_ALPHA := 0.7
const STAR_TWINKLE_HZ_MIN := 0.4
const STAR_TWINKLE_HZ_MAX := 1.3
const STAR_COLOR := Color(1.0, 0.98, 0.9)

# --- State ------------------------------------------------------------------

var _retired: bool = false
var _age: float = 0.0 # seconds since activate(); the flicker clock
var _dark: float = 0.0 # envelope, 0..1, advanced in tick()
var _glimpses: Array[float] = []
var _stars: Array[Dictionary] = [] # {"pos": Vector2, "size": float, "hz": float, "phase": float}
# The held brick's world position, cached in tick(): the camera moves in
# _process, so the screen position is resolved at draw time from this.
var _brick_world: Vector2 = Vector2.ZERO
var _have_brick: bool = false
var _lantern_tex: GradientTexture2D = null
var _warm_tex: GradientTexture2D = null

# --- Hooks ------------------------------------------------------------------

func hud_tag() -> String:
	return "DARK"

# --- Lifecycle --------------------------------------------------------------

func activate() -> void:
	_retired = false
	_age = 0.0
	_dark = 0.0
	_have_brick = false
	_glimpses = []
	var t: float = GLIMPSE_FIRST
	while t < GLIMPSE_HORIZON:
		_glimpses.append(t)
		t += randf_range(GLIMPSE_GAP_MIN, GLIMPSE_GAP_MAX)
	_stars = []
	for _i in range(STAR_COUNT):
		_stars.append({
			"pos": Vector2(randf_range(STAR_X_MIN, STAR_X_MAX), randf_range(0.0, STAR_Y_MAX)),
			"size": randf_range(STAR_SIZE_MIN, STAR_SIZE_MAX),
			"hz": randf_range(STAR_TWINKLE_HZ_MIN, STAR_TWINKLE_HZ_MAX),
			"phase": randf() * TAU,
		})

func tick(delta: float) -> void:
	if _retired or mode == null:
		return
	_age += delta
	var piece = mode.active_piece
	var piloting: bool = mode.state == "piloting" and piece != null and is_instance_valid(piece)
	if piece != null and is_instance_valid(piece):
		_brick_world = piece.global_position
		_have_brick = true
	_dark = move_toward(_dark, 1.0 if piloting else 0.0, delta / (FADE_IN if piloting else FADE_OUT))

# Nothing on the mode to undo. The envelope is zeroed so a draw call that
# somehow lands between retirement and the canvas's next redraw paints
# nothing (TowerMode redraws both skill canvases every frame regardless).
# Idempotent by construction.
func deactivate() -> void:
	_retired = true
	_dark = 0.0
	_have_brick = false

# --- Flicker ------------------------------------------------------------------

# 0 outside a glimpse; inside one, the stutter — bright, a dip, bright — as
# a factor of how far the dark is pulled back. Derived from _age and the
# list drawn at activation, so it never needs a timer reset.
func _glimpse() -> float:
	for t0: float in _glimpses:
		var u: float = _age - t0
		if u < 0.0:
			return 0.0 # the list is in order; nothing later has started either
		if u < GLIMPSE_LEN:
			var f: float = u / GLIMPSE_LEN
			return 0.45 if (f > 0.35 and f < 0.6) else 1.0
	return 0.0

# --- Drawing ----------------------------------------------------------------

# Screen space (TowerSkillScreen): above the world, below the HUD panels.
# The dark is four rectangles around a square, and the square is a radial
# gradient whose corners are opaque — the gradient clamps to its last stop
# past the radius — so the five pieces join without a seam and the lantern
# has no edge but its own falloff.
func draw_screen(canvas: CanvasItem) -> void:
	if _retired or mode == null or _dark <= 0.001 or not _have_brick:
		return
	if mode.active_slot != target:
		return
	var size: Vector2 = canvas.get_viewport_rect().size
	var zoom: float = float(mode.camera.zoom.x)
	var centre: Vector2 = mode.get_viewport().get_canvas_transform() * _brick_world
	var glimpse: float = _glimpse()
	var alpha: float = DARK_ALPHA * _dark * (1.0 - glimpse * (1.0 - GLIMPSE_DARK))
	var dark := Color(DARK.r, DARK.g, DARK.b, alpha)

	var r: float = LANTERN_EDGE_CELLS * float(mode.CELL) * zoom
	var sq := Rect2(centre - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
	var top: float = clampf(sq.position.y, 0.0, size.y)
	var bottom: float = clampf(sq.end.y, 0.0, size.y)
	if top > 0.0:
		canvas.draw_rect(Rect2(0.0, 0.0, size.x, top), dark, true)
	if bottom < size.y:
		canvas.draw_rect(Rect2(0.0, bottom, size.x, size.y - bottom), dark, true)
	if bottom > top:
		if sq.position.x > 0.0:
			canvas.draw_rect(Rect2(0.0, top, minf(sq.position.x, size.x), bottom - top), dark, true)
		if sq.end.x < size.x:
			canvas.draw_rect(Rect2(maxf(sq.end.x, 0.0), top, size.x - maxf(sq.end.x, 0.0), bottom - top), dark, true)
	canvas.draw_texture_rect(_lantern(), sq, false, dark)

	# The warm cast, and the stars, both scaled by how dark it actually is
	# right now so a glimpse lifts them with everything else.
	var lit: float = _dark * (1.0 - glimpse)
	var wr: float = r * WARM_FRAC
	canvas.draw_texture_rect(_warm(), Rect2(centre - Vector2(wr, wr), Vector2(wr * 2.0, wr * 2.0)), false,
		Color(WARM.r, WARM.g, WARM.b, WARM_ALPHA * lit))
	for s: Dictionary in _stars:
		var p: Vector2 = s["pos"]
		var near: float = clampf((p.distance_to(centre) - r * 0.8) / (r * 0.5), 0.0, 1.0)
		if near <= 0.0:
			continue
		var tw: float = 0.55 + 0.45 * sin(_age * TAU * float(s["hz"]) + float(s["phase"]))
		canvas.draw_circle(p, float(s["size"]), Color(STAR_COLOR.r, STAR_COLOR.g, STAR_COLOR.b, STAR_ALPHA * tw * near * lit))

# White with an alpha profile — clear to LANTERN_CLEAR, curving up to opaque
# at the rim — so the modulate colour above is what colours it. Built on
# first use, per effect (see the header on why not static).
func _lantern() -> GradientTexture2D:
	if _lantern_tex != null:
		return _lantern_tex
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1.0, 1.0, 1.0, 1.0))
	var clear: float = LANTERN_CLEAR_CELLS / LANTERN_EDGE_CELLS
	g.add_point(clear, Color(1.0, 1.0, 1.0, 0.0))
	g.add_point(clear + (1.0 - clear) * 0.55, Color(1.0, 1.0, 1.0, LANTERN_MID_ALPHA))
	_lantern_tex = _radial(g)
	return _lantern_tex

func _warm() -> GradientTexture2D:
	if _warm_tex != null:
		return _warm_tex
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_warm_tex = _radial(g)
	return _warm_tex

# Centre to the middle of the right edge: a radius of half the texture, so
# the circle is inscribed in the rect it is drawn into.
func _radial(g: Gradient) -> GradientTexture2D:
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = LANTERN_TEX_SIZE
	t.height = LANTERN_TEX_SIZE
	return t
