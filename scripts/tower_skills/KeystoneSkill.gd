extends TowerSkill

## KEYSTONE — a brick is pulled out from under the top of the tower, on the
## target's turn. Whatever comes down is on them.
##
## Every other way of hurting somebody in this mode works on *their* brick —
## the one in the air. This one works on the tower itself, which is the thing
## every player built together and the thing the fault rule is about: falls
## are scored against whoever is on the clock, so a brick removed at the start
## of the target's turn makes the tower's next few seconds their problem. The
## removed brick is not scored — it never passes LOST_Y, it simply ceases to
## exist — so a pull from a well-bonded tower costs nothing but a course of
## height, and a pull from a stack of I pieces costs a life. Which of those the
## table has been building is the whole outcome, and it was decided over the
## last ten turns by everyone at once.
##
## Why "under the top" and not the base: pulling the bottom brick brings the
## whole tower down every time, and a hex that always costs exactly one life
## is a stat, not a mechanic. The candidates are the few bricks directly under
## the topmost one, chosen at random, so the load above the hole is one to
## three courses — enough to shift, not always enough to fall — and the target
## is left placing a brick on a tower that has just settled into a new shape.
##
## Timing inside the turn: the victim is marked for WARN_TIME first, so the
## table sees which brick is going before it goes, then pulled. The warning is
## kept under the fastest possible landing (a soft drop from spawn takes about
## 0.62s, plus SETTLE_HOLD) so the pull always lands in piloting or settling —
## never in the resolve pause, where a collapse would spill unpaid into the
## next player's turn. If the turn has somehow already resolved, the pull is
## skipped rather than moved.
##
## The pull is done the way TowerMode._cull_fallen() frees a brick — out of
## `mode.pieces` and queue_free() — which is the one permanent change to the
## world a skill is allowed to leave (TowerSkill's header). Everything else it
## touches is put back: the camera's `offset` carries the jolt and is zeroed
## when the shake ends and again in deactivate(), so a cut mid-shake leaves
## the camera exactly where TowerMode's own `position` puts it.

# --- Tuning ----------------------------------------------------------------

# See the header: shorter than a soft drop from spawn plus the settle hold.
const WARN_TIME := 0.55
# How many bricks under the topmost one may be chosen from. Three courses is
# the band in which a pull is usually survivable and never free.
const UNDER_TOP := 3
# The ghost of the pulled brick slides this far sideways, out of the tower,
# and is gone. Long enough to read as "taken", short enough that it is off
# the tower before the bricks above have finished dropping into the hole.
const PULL_TIME := 0.45
const PULL_CELLS := 5.0
const PULL_LIFT_CELLS := 0.35
const DUST_TIME := 0.6
const DUST_RINGS := 3
# The jolt. Camera2D.offset is in world units under the camera's zoom, so
# nine world pixels is about six on screen at VISIBLE_CELLS' pull-back.
const SHAKE_TIME := 0.35
const SHAKE_AMP := 9.0
# A short full-screen flash in the caster's colour at the instant of the pull,
# under the HUD. It is what makes the moment land for the players who were
# not looking at the tower.
const FLASH_TIME := 0.22
const FLASH_ALPHA := 0.22
# The marker: the victim's outline breathes, and a chevron beside it bobs
# outward in the direction it will be pulled.
const MARK_HZ := 2.2
const MARK_WIDTH := 3.0
const UNDERLINE := Color(0.06, 0.08, 0.20, 0.55)

# --- State -----------------------------------------------------------------

var _t := 0.0
# Untyped on purpose: it is freed at the pull, and a freed node read through
# an untyped reference is the only form that survives long enough to be
# checked with is_instance_valid() (PROJECT_STATE §12).
var _victim = null
var _pulled := false
# Seconds since the pull; negative until it happens (or if it was skipped).
var _pull_t := -1.0
# Captured at the pull, for the ghost: the brick's silhouette, its centre and
# the way it went.
var _outlines: Array[PackedVector2Array] = []
var _hole := Vector2.ZERO
var _dir := 1.0
var _shake_t := 0.0

# --- Lifecycle -------------------------------------------------------------

func activate() -> void:
	_t = 0.0
	_pulled = false
	_pull_t = -1.0
	_shake_t = 0.0
	_outlines = []
	_victim = _choose()
	if _victim == null:
		var who: String = GameSettings.PLAYER_CONFIGS[caster]["name"]
		var c: Color = mode._slot_color(caster)
		mode.hud.show_message("%s — KEYSTONE: NOTHING TO PULL" % who, Color(c.r, c.g, c.b, 1.0))
		_pulled = true # nothing to do this turn; the effect just runs out
	else:
		_dir = 1.0 if float(_victim.global_position.x) >= 0.0 else -1.0

func tick(delta: float) -> void:
	_t += delta
	if not _pulled and _t >= WARN_TIME:
		_pull()
	if _pull_t >= 0.0:
		_pull_t += delta
	if _shake_t > 0.0:
		_shake_t = maxf(0.0, _shake_t - delta)
		var k: float = _shake_t / SHAKE_TIME
		var amp: float = SHAKE_AMP * k * k
		if _shake_t <= 0.0:
			mode.camera.offset = Vector2.ZERO
		else:
			mode.camera.offset = Vector2(sin(_t * 71.0), cos(_t * 53.0)) * amp

func deactivate() -> void:
	_shake_t = 0.0
	if mode != null and is_instance_valid(mode.camera):
		mode.camera.offset = Vector2.ZERO
	_victim = null
	_outlines = []

func hud_tag() -> String:
	return "PULLED" if _pull_t >= 0.0 else "MARKED"

# --- The pull --------------------------------------------------------------

# The bricks directly under the topmost one; the topmost itself only when it
# is alone (a one-brick tower has no "under the top", and leaving the target
# a bare platform is a fair, if gentle, outcome). Held, doomed and the brick
# in the air are never candidates.
func _choose():
	var ap = mode.active_piece
	var landed: Array = []
	for c in mode.pieces.get_children():
		var p := c as TowerPiece
		if p == null or p.held or p.doomed or p == ap:
			continue
		landed.append(p)
	if landed.is_empty():
		return null
	landed.sort_custom(func(a, b) -> bool: return a.top_y() < b.top_y())
	if landed.size() == 1:
		return landed[0]
	var pool: Array = landed.slice(1, mini(landed.size(), 1 + UNDER_TOP))
	return pool[randi() % pool.size()]

func _pull() -> void:
	_pulled = true
	if _victim == null or not is_instance_valid(_victim):
		return
	var p := _victim as TowerPiece
	if p == null or p.held or p.doomed or mode.state == "resolving":
		_victim = null
		return
	_outlines = p.box_outlines(p.global_transform)
	_hole = p.global_position
	mode.pieces.remove_child(p)
	p.queue_free()
	_victim = null
	# The bricks that rested on it are asleep and would not necessarily
	# notice their support has gone. Wake the whole tower; the ones with
	# something under them go straight back to sleep.
	for c in mode.pieces.get_children():
		var q := c as TowerPiece
		if q == null or q.held or q.doomed:
			continue
		q.sleeping = false
	_pull_t = 0.0
	_shake_t = SHAKE_TIME

# --- Drawing ---------------------------------------------------------------

func _px(width: float) -> float:
	return width / float(mode.cam_zoom)

# Above the bricks: the mark before, the ghost and the dust after.
func draw_over(canvas: CanvasItem) -> void:
	if mode.active_slot != target:
		return
	var c: Color = mode._slot_color(caster)
	var cell: float = mode.CELL

	if not _pulled and _victim != null and is_instance_valid(_victim):
		var p := _victim as TowerPiece
		if p == null:
			return
		var pulse: float = 0.5 + 0.5 * sin(_t * TAU * MARK_HZ)
		var fill := Color(c.r, c.g, c.b, 0.22 + 0.18 * pulse)
		var edge := Color(c.r, c.g, c.b, 0.6 + 0.4 * pulse)
		var xf: Transform2D = p.global_transform
		for pts: PackedVector2Array in p.box_outlines(xf):
			canvas.draw_colored_polygon(pts.slice(0, 4), fill)
			canvas.draw_polyline(pts, UNDERLINE, _px(MARK_WIDTH + 2.0))
			canvas.draw_polyline(pts, edge, _px(MARK_WIDTH))
		# The chevron: beside the brick's outer flank, pointing the way it
		# will go, bobbing outward.
		var half_w: float = float(p.cols) * cell * 0.5 + cell * 0.25
		var at: Vector2 = xf.origin + Vector2(_dir * (half_w + cell * 0.3 * pulse), 0.0)
		var tip: Vector2 = at + Vector2(_dir * cell * 0.4, 0.0)
		canvas.draw_colored_polygon(PackedVector2Array([
			tip, at + Vector2(0.0, -cell * 0.28), at + Vector2(0.0, cell * 0.28),
		]), Color(1.0, 1.0, 1.0, 0.7 + 0.3 * pulse))
		return

	if _pull_t < 0.0:
		return
	# The ghost of the brick leaving: its own silhouette, slid out of the
	# tower and lifted a little, fading as it goes. Eased so the first frames
	# are the fastest — it is reporting a yank, not performing a slide.
	if _pull_t < PULL_TIME:
		var u: float = clampf(_pull_t / PULL_TIME, 0.0, 1.0)
		var e: float = 1.0 - pow(1.0 - u, 3.0)
		var shift := Vector2(_dir * e * PULL_CELLS * cell, -e * PULL_LIFT_CELLS * cell)
		var fill := Color(c.r, c.g, c.b, 0.45 * (1.0 - u))
		var edge := Color(1.0, 1.0, 1.0, 0.9 * (1.0 - u))
		for pts: PackedVector2Array in _outlines:
			var moved := PackedVector2Array()
			for q: Vector2 in pts:
				moved.append(q + shift)
			canvas.draw_colored_polygon(moved.slice(0, 4), fill)
			canvas.draw_polyline(moved, edge, _px(2.0))
	# Dust at the hole: rings running outward from where the brick was.
	if _pull_t < DUST_TIME:
		for i in range(DUST_RINGS):
			var d: float = _pull_t / DUST_TIME - float(i) * 0.18
			if d <= 0.0 or d >= 1.0:
				continue
			var r: float = cell * (0.25 + 1.3 * d)
			canvas.draw_arc(_hole, r, 0.0, TAU, 28, Color(0.95, 0.93, 0.88, 0.55 * (1.0 - d)), _px(2.5))

# Screen space, under the HUD: the flash at the instant of the pull.
func draw_screen(canvas: CanvasItem) -> void:
	if mode.active_slot != target or _pull_t < 0.0 or _pull_t >= FLASH_TIME:
		return
	var c: Color = mode._slot_color(caster)
	var a: float = FLASH_ALPHA * (1.0 - _pull_t / FLASH_TIME)
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.get_viewport_rect().size), Color(c.r, c.g, c.b, a), true)
