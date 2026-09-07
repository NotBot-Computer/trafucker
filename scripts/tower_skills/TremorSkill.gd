extends TowerSkill

## TREMOR — the ground shakes for one turn of the victim's.
##
## A hex that does nothing to the victim's brick, their controls or their
## draw: it goes after the *tower*, and specifically after whatever in it
## is only standing because nothing has asked it not to. Godot puts a body
## that has stopped moving to sleep, and a sleeping brick balanced a hair
## past its edge stays balanced for ever. This skill keeps every brick
## awake for the victim's whole turn — humming the tower with small jolts
## while they steer, since a jolted brick is by definition not asleep —
## and lands one hard jolt at the exact instant their brick is handed to
## the solver — when it is sitting where they put it with nothing
## but friction holding it — followed by two smaller aftershocks. Whatever
## was precarious finds out, and the fault rule bills it to whoever is on
## the clock, which is the victim.
##
## The jolts are impulses on the landed bricks (TowerSkill's header lists
## apply_impulse on mode.pieces as fair game), sized as a *velocity* rather
## than a force — impulse = mass x kick — so a four-cell brick and a
## five-cell brick get the same kick, and applied at each brick's top edge
## rather than its centre. That lever is the point. A sideways impulse at
## the centre of a brick sitting on FRICTION 0.94 is stopped inside a
## frame having moved a tenth of a pixel: invisible and harmless. The same
## impulse at the top edge is also a torque, and rocks the brick. Rock a
## squat brick two degrees and it settles back; rock a brick whose centre
## of mass is already near its support edge and it goes over. That is what
## "finds the weak spot" means mechanically, and why a well-built tower
## shrugs the whole thing off — the hex punishes precarious building, it
## does not demolish sound towers, or it would be a life tax.
##
## Timing follows the fault rule and the settle. The jolts stop 0.7s after
## the landing so the tower can actually come to rest and the turn can
## resolve: SETTLE_HOLD needs a quiet quarter second and SETTLE_TIMEOUT is
## nine seconds of the whole table waiting, and a tremor that ran through
## settling would take every hexed turn to that timeout. Nothing runs
## before the victim's turn — the mode never activates a hex on the
## caster's turn, and this one would have the caster shaking bricks off
## on their own clock.
##
## Nothing is restored in deactivate(). Waking bricks and kicking them is
## tower state; the drawing is derived from a timer and a short list of
## recent jolts that die with the effect. The camera is deliberately not
## shaken, though TowerSkill allows it: the rock of the bricks is the real
## shake, and a camera shake on top of it would hide the thing the player
## most needs to see.

# --- Tuning ----------------------------------------------------------------

# Seconds of hum before the first foreshock: long enough for the tag, the
# dust and the cracks to land before anything moves, so the shake reads as
# a quake and not a physics glitch.
const RUMBLE_LEAD := 0.6
const FORESHOCK_EVERY := 0.45
# px/s, per brick, at its top edge. Foreshocks keep the tower awake and
# visibly uneasy without moving anything; the main jolt rocks an O about
# two degrees and tips a free-standing I; the aftershocks are the same jolt
# decaying. Calibrated with a throwaway rendered harness against an O
# resting on the end of a flat I: at 42 an O whose centre sat 10px inside
# its support edge survived a jolt in the tipping direction, so 42 was the
# coin-flip line rather than "finds the weak spot"; at 48 the same brick
# 4px inside goes over and a six-high column of centred Os does not move.
# MAIN_KICK is the difficulty knob and the first number to move: it decides
# how close to an edge counts as precarious.
const FORESHOCK_KICK := 12.0
const MAIN_KICK := 48.0
const AFTERSHOCK_AT: Array[float] = [0.35, 0.7] # seconds after the landing
const AFTERSHOCK_KICK: Array[float] = [22.0, 11.0]

# --- Visuals ---------------------------------------------------------------
# All dark over the bright sky (§7) and all derived from _t and _recent.

const CRACK := Color(0.16, 0.11, 0.08)
const JITTER := Color(0.18, 0.14, 0.10)
const RING := Color(0.18, 0.14, 0.10)
const DUST := Color(0.62, 0.52, 0.38)
const FLASH := Color(0.06, 0.03, 0.02)
const RECENT := 8 # jolts kept for the drawing
const PUFFS := 5 # dust puffs per side per jolt
const DUST_LIFE := 0.8
const RING_LIFE := 0.5
const RING_SPEED := 640.0 # world px/s the shock ring expands
const FLASH_LIFE := 0.22
const SHAKE_DECAY := 7.0 # per second; how fast the drawn jitter dies after a jolt
const CRACK_TIME := 1.2 # seconds for the outcrop's cracks to reach the ground
const HUM := 3.0 # px of drawn jitter during the lead, before any jolt

var _t := 0.0
var _next_foreshock := 0.0
var _jolts := 0 # parity picks the direction, so no two jolts in a row push the same way
var _landed_at := -1.0
var _after_done := 0
var _recent: Array[Dictionary] = [] # {t, kick, dir}

func hud_tag() -> String:
	return "TREMOR"

# --- Lifecycle -------------------------------------------------------------

# The victim's brick has just spawned. `sleeping = false` here is a nudge,
# not the mechanism: Godot does not reset a body's still-time on a wake, so
# a brick at rest is asleep again on the next tick. It is the jolts below,
# each of which gives every brick a velocity above the sleep threshold,
# that keep the tower a live body for the whole turn.
func activate() -> void:
	_t = 0.0
	_next_foreshock = RUMBLE_LEAD
	_jolts = 0
	_landed_at = -1.0
	_after_done = 0
	_recent = []
	for c in mode.pieces.get_children():
		var p := c as TowerPiece
		if p == null or p.held or p.doomed:
			continue
		p.sleeping = false

func tick(delta: float) -> void:
	_t += delta
	match mode.state:
		"piloting":
			if _t >= _next_foreshock:
				_jolt(FORESHOCK_KICK)
				_next_foreshock = _t + FORESHOCK_EVERY
		"settling":
			if _landed_at >= 0.0 and _after_done < AFTERSHOCK_AT.size():
				if _t - _landed_at >= AFTERSHOCK_AT[_after_done]:
					_jolt(AFTERSHOCK_KICK[_after_done])
					_after_done += 1

# The main shock, at the instant the brick is a body in the tower. It is
# under mode.pieces and no longer held, so _jolt() reaches it too.
func on_release(_piece) -> void:
	_landed_at = _t
	_jolt(MAIN_KICK)

# One jolt: every landed brick gets the same sideways velocity at its top
# edge, all in the same direction, which is what a ground jerk does to a
# stack. apply_impulse wakes a sleeping body on its own.
func _jolt(kick: float) -> void:
	_jolts += 1
	var dir: float = 1.0 if (_jolts % 2) == 1 else -1.0
	for c in mode.pieces.get_children():
		var p := c as TowerPiece
		if p == null or p.held or p.doomed:
			continue
		var lever := Vector2(0.0, p.top_y() - p.global_position.y) # offset from the origin, world axes
		p.apply_impulse(Vector2(dir * kick * p.mass, 0.0), lever)
	_recent.append({"t": _t, "kick": kick, "dir": dir})
	while _recent.size() > RECENT:
		_recent.pop_front()

# Nothing to put back — see the header. The list is cleared so a retired
# effect draws nothing if anything ever asks it to.
func deactivate() -> void:
	_recent = []

# --- Drawing ---------------------------------------------------------------

func _px(width: float) -> float:
	return width / mode.cam_zoom

# Deterministic noise for the dust, so a puff is in the same place every
# frame of its life without the skill keeping a list of puffs.
func _noise(seed_v: int, k: int) -> float:
	var x: int = seed_v * 374761393 + k * 668265263
	x = (x ^ (x >> 13)) * 1274126177
	x = x ^ (x >> 16)
	return float(x & 0xFFFF) / 65535.0

# How hard the ground is visibly shaking right now: the last jolt, decaying,
# or the hum building up before the first one.
func _shake_amp() -> float:
	if _recent.is_empty():
		return HUM * clampf(_t / RUMBLE_LEAD, 0.0, 1.0)
	var last: Dictionary = _recent[_recent.size() - 1]
	return maxf(HUM * 0.5, float(last["kick"]) * 0.35 * exp(-(_t - float(last["t"])) * SHAKE_DECAY))

# World space, under the bricks: the outcrop cracking, the rock face
# shuddering, and a shock ring plus dust for each jolt. Everything at the
# ground, because that is where a tremor comes from; the bricks themselves
# are drawn by their own rocking, which is real.
func draw_under() -> void:
	if mode == null or mode.active_slot != target:
		return
	var half_w: float = mode.PLATFORM_CELLS * mode.CELL * 0.5
	var ground: float = mode.GROUND_Y
	var amp: float = _shake_amp()

	# Cracks running down the rock from under the platform, growing in
	# over the lead so the quake is announced before it strikes.
	var grow: float = clampf(_t / CRACK_TIME, 0.0, 1.0)
	for side: float in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		var x: float = side * half_w * 0.35
		var y: float = 2.0
		var jog := 6.0
		var n := 0
		while y < ground * grow:
			pts.append(Vector2(x + sin(_t * 61.0 + float(n)) * amp * 0.3, y))
			x += jog * (1.0 if (n % 2) == 0 else -1.0) * side
			y += 18.0
			n += 1
		if pts.size() >= 2:
			mode.draw_polyline(pts, Color(CRACK.r, CRACK.g, CRACK.b, 0.85), _px(2.5))

	# Short dashes on the rock face that jitter with the shake.
	var dash_a: float = clampf(amp / 12.0, 0.25, 1.0)
	for i in range(8):
		var fx: float = (float(i) / 7.0 - 0.5) * half_w * 1.5
		var fy: float = 24.0 + fmod(float(i) * 37.0, ground - 34.0)
		var dx: float = sin(_t * 53.0 + float(i) * 1.7) * amp * 0.5
		mode.draw_line(
			Vector2(fx + dx - 7.0, fy), Vector2(fx + dx + 7.0, fy),
			Color(JITTER.r, JITTER.g, JITTER.b, 0.55 * dash_a), _px(2.0)
		)

	# Per jolt: a ring spreading up from the platform's centre and dust
	# thrown off both edges. Under the bricks, so the ring shows through
	# the gaps and beyond the tower's silhouette rather than over it.
	for r: Dictionary in _recent:
		var age: float = _t - float(r["t"])
		var strength: float = clampf(float(r["kick"]) / MAIN_KICK, 0.25, 1.0)
		if age < RING_LIFE:
			var k: float = age / RING_LIFE
			mode.draw_arc(
				Vector2.ZERO, 10.0 + age * RING_SPEED, PI, TAU, 40,
				Color(RING.r, RING.g, RING.b, 0.4 * (1.0 - k) * strength), _px(3.0)
			)
		if age < DUST_LIFE:
			var k: float = age / DUST_LIFE
			var seed_v: int = int(float(r["t"]) * 1000.0)
			for side: float in [-1.0, 1.0]:
				for i in range(PUFFS):
					var n0: float = _noise(seed_v, i * 2)
					var n1: float = _noise(seed_v, i * 2 + 1)
					var px: float = side * (half_w + 6.0 + float(i) * 9.0 + age * (20.0 + 30.0 * n0))
					var py: float = -(4.0 + age * (30.0 + 25.0 * n1))
					mode.draw_circle(
						Vector2(px, py), 3.0 + 9.0 * k,
						Color(DUST.r, DUST.g, DUST.b, 0.55 * (1.0 - k) * strength)
					)

# Screen space, under the HUD: a dark frame that thumps in on each jolt and
# fades. Stands in for the camera shake this skill chooses not to do.
func draw_screen(canvas: CanvasItem) -> void:
	if mode == null or mode.active_slot != target or _recent.is_empty():
		return
	var last: Dictionary = _recent[_recent.size() - 1]
	var age: float = _t - float(last["t"])
	if age >= FLASH_LIFE:
		return
	var strength: float = clampf(float(last["kick"]) / MAIN_KICK, 0.15, 1.0)
	var a: float = (1.0 - age / FLASH_LIFE) * 0.28 * strength
	var ctl := canvas as Control
	var sz: Vector2 = ctl.size if ctl != null else Vector2(1500.0, 800.0)
	var band: float = 26.0 + 30.0 * strength
	var c := Color(FLASH.r, FLASH.g, FLASH.b, a)
	canvas.draw_rect(Rect2(0.0, 0.0, sz.x, band), c, true)
	canvas.draw_rect(Rect2(0.0, sz.y - band, sz.x, band), c, true)
	canvas.draw_rect(Rect2(0.0, band, band, sz.y - band * 2.0), c, true)
	canvas.draw_rect(Rect2(sz.x - band, band, band, sz.y - band * 2.0), c, true)
