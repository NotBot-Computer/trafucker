extends TowerSkill

## PETRIFY — the tower turns to stone until the caster's turn is over.
##
## Every landed brick is frozen where it stands — FREEZE_MODE_STATIC, so
## the solver treats the whole tower as one immovable shape for the rest of
## the turn. The caster's own brick is *not* included: it lands on the
## stone as an ordinary rigid body, and if they set it down half off a
## ledge it slides off on their clock like any other brick. Tower-proof,
## not brick-proof; that is what keeps this from being a free turn.
##
## What makes it more than "nothing can go wrong this turn" is the end.
## The stone breaks when the effect is retired, which is *after* the
## caster's falls have been counted (TowerMode._resolve_turn tallies, then
## calls on_turn_end and retires). Only then does the tower feel the new
## brick's weight for the first time, and only then does whatever was
## already leaning get to finish leaning. That collapse, if there is one,
## plays out through the resolve pause and into the next player's turn,
## and the fault rule bills it to whoever is on the clock then. A player
## holding this can place recklessly and hand the bill on. That is a
## mischievous thing for a "self" skill to do and it is the intended
## reading: the tower is shared, you inherit whatever the last player left
## you, and this lets you leave more of it.
##
## Frozen bodies read as sleeping to TowerMode._everything_at_rest(), so a
## turn under stone settles as soon as the caster's own brick does. The
## skill costs the table nothing in pace.
##
## deactivate() is the important half. It must unfreeze exactly the bricks
## it froze and nothing else, from any state: the turn running out, a cut
## at game over, a cut by a restart (which has already pulled every brick
## out of the tree — those are skipped, not touched), or a second call.
## Each brick's freeze_mode goes back to what it was rather than to a
## constant, because TowerPiece.set_held leaves it at KINEMATIC and this
## file should have no opinion about that. The unfrozen bricks are woken
## too, so a tower that was sleeping on a bad lean does not simply go on
## sleeping on it.
##
## The stone is drawn, not tinted: a wash and cracks over each frozen
## brick's own boxes in draw_over(), rebuilt from the brick's transform
## every frame, plus a front that sweeps up from the platform on the cast
## so the table sees it *happen*. Nothing is modulated, so nothing has to
## be un-modulated. During settling the cracks grow and pulse — the
## telegraph for the break, which cannot itself be drawn because
## deactivate() runs outside any _draw() and the effect is gone straight
## after (the CompactSkill lesson).

# --- Tuning ----------------------------------------------------------------

# World px/s the stone front climbs from the platform. A twenty-cell tower
# is stone in under a second, well inside the shortest descent.
const WAVE_SPEED := 900.0
const BAND := 30.0 # px over which a brick fades from brick to stone as the front crosses it

# --- Visuals ---------------------------------------------------------------
# All derived from _t (advanced in tick), _settled_at and the frozen bricks'
# own transforms. Nothing owned by the skill has to be freed.

const STONE := Color(0.56, 0.56, 0.60)
# Opaque enough to read as grey rock even over a yellow O (at 0.62 the
# blend came out khaki), thin enough that the brick shape still shows
# through its rim — the table still has to tell an I from an L.
const STONE_ALPHA := 0.72
const RIM := Color(0.88, 0.88, 0.92)
const CRACK := Color(0.16, 0.15, 0.19)
const CRACKS_PER_BOX := 2
const CRACK_GROW := 0.55 # of each crack's length while piloting; the rest grows in during settling
const CRACK_GROW_TIME := 0.6
const TELEGRAPH_HZ := 3.5

var _frozen: Array = [] # the bricks this effect froze; untyped, the tower can free them under us
var _modes: Array[int] = [] # their freeze_mode before, restored exactly
var _t := 0.0
var _settled_at := -1.0 # _t at which the caster's brick landed; < 0 while descending
var _restored := false

func hud_tag() -> String:
	return "STONE"

# --- Lifecycle -------------------------------------------------------------

# Mid-descent, the caster's brick in the air and out of the collision
# world. Everything else standing on the platform becomes static.
func activate() -> void:
	_restored = false
	_t = 0.0
	_settled_at = -1.0
	_frozen = []
	_modes = []
	for c in mode.pieces.get_children():
		var p := c as TowerPiece
		if p == null or p.held or p.doomed:
			continue
		_modes.append(p.freeze_mode)
		p.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		p.freeze = true
		_frozen.append(p)

func tick(delta: float) -> void:
	_t += delta
	if _settled_at < 0.0 and mode.state != "piloting":
		_settled_at = _t

# The break. Idempotent by the flag; safe against bricks that have been
# freed (is_instance_valid) or pulled out of the tree by a restart
# (is_inside_tree) — see the header.
func deactivate() -> void:
	if _restored:
		return
	_restored = true
	for i in range(_frozen.size()):
		var b = _frozen[i]
		if b == null or not is_instance_valid(b):
			continue
		var p: RigidBody2D = b
		if not p.is_inside_tree():
			continue
		p.freeze = false
		p.freeze_mode = _modes[i]
		p.sleeping = false
	_frozen = []
	_modes = []

# --- Drawing ---------------------------------------------------------------

func _px(width: float) -> float:
	return width / mode.cam_zoom

# Deterministic per brick and box, so the cracks are the same every frame
# without a list of them being kept anywhere.
func _noise(seed_v: int, k: int) -> float:
	var x: int = seed_v * 374761393 + k * 668265263
	x = (x ^ (x >> 13)) * 1274126177
	x = x ^ (x >> 16)
	return float(x & 0xFFFF) / 65535.0

# World space, above the bricks: the stone wash, its rim and its cracks on
# every frozen brick the front has reached, and the front itself while it
# is still climbing.
func draw_over(canvas: CanvasItem) -> void:
	if mode == null or _restored or _frozen.is_empty():
		return
	var front_y: float = -WAVE_SPEED * _t # climbs from the platform (y = 0) toward -y
	var grow: float = CRACK_GROW
	if _settled_at >= 0.0:
		grow = lerpf(CRACK_GROW, 1.0, clampf((_t - _settled_at) / CRACK_GROW_TIME, 0.0, 1.0))
	var pulse: float = 0.5 + 0.5 * sin(_t * TAU * TELEGRAPH_HZ)
	var crack_a: float = lerpf(0.75, 1.0, pulse) if _settled_at >= 0.0 else 0.6
	var rim_a: float = lerpf(0.45, 0.9, pulse) if _settled_at >= 0.0 else 0.45

	for b in _frozen:
		if b == null or not is_instance_valid(b):
			continue
		var p: TowerPiece = b
		if not p.is_inside_tree() or p.doomed:
			continue
		# How far past this brick the front is, as 0..1 over BAND.
		var k: float = clampf((p.global_position.y - front_y) / BAND, 0.0, 1.0)
		if k <= 0.0:
			continue
		var xf: Transform2D = p.global_transform
		var half := Vector2(float(p.cols), float(p.rows)) * p.cell * 0.5
		var loops: Array[PackedVector2Array] = p.box_outlines(xf)
		for i in range(loops.size()):
			canvas.draw_colored_polygon(loops[i].slice(0, 4), Color(STONE.r, STONE.g, STONE.b, STONE_ALPHA * k))
			canvas.draw_polyline(loops[i], Color(RIM.r, RIM.g, RIM.b, rim_a * k), _px(1.5))
			var box: Rect2 = p.boxes[i]
			_draw_cracks(canvas, xf, Rect2(box.position * p.cell - half, box.size * p.cell),
				p.get_instance_id(), i, grow, crack_a * k)

	# The front, while there is still tower above it.
	if front_y > mode.stack_top_y - mode.CELL:
		var reach: float = mode.PLATFORM_CELLS * mode.CELL * 0.5 + mode.AIM_BOUND_CELLS * mode.CELL
		canvas.draw_line(Vector2(-reach, front_y), Vector2(reach, front_y), Color(RIM.r, RIM.g, RIM.b, 0.7), _px(3.0))
		canvas.draw_line(Vector2(-reach, front_y), Vector2(reach, front_y), Color(RIM.r, RIM.g, RIM.b, 0.2), _px(9.0))

# Two cracks per box, each a three-point line from one edge to the far one
# with a jog in the middle, drawn up to `grow` of its length. Points are in
# the brick's frame and carried through its transform, so they lean with
# it. Even cracks run top to bottom, odd ones side to side.
func _draw_cracks(canvas: CanvasItem, xf: Transform2D, r: Rect2, seed_v: int, box_i: int, grow: float, alpha: float) -> void:
	var w: float = _px(1.5)
	var c := Color(CRACK.r, CRACK.g, CRACK.b, alpha)
	for n in range(CRACKS_PER_BOX):
		var base: int = box_i * 16 + n * 4
		var s0: float = 0.15 + 0.7 * _noise(seed_v, base)
		var s1: float = 0.15 + 0.7 * _noise(seed_v, base + 1)
		var s2: float = 0.15 + 0.7 * _noise(seed_v, base + 2)
		var p0: Vector2
		var p1: Vector2
		var p2: Vector2
		if (n % 2) == 0:
			p0 = Vector2(r.position.x + r.size.x * s0, r.position.y)
			p1 = Vector2(r.position.x + r.size.x * s1, r.position.y + r.size.y * 0.5)
			p2 = Vector2(r.position.x + r.size.x * s2, r.end.y)
		else:
			p0 = Vector2(r.position.x, r.position.y + r.size.y * s0)
			p1 = Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * s1)
			p2 = Vector2(r.end.x, r.position.y + r.size.y * s2)
		var u: float = grow * 2.0
		var pts := PackedVector2Array()
		pts.append(xf * p0)
		if u <= 1.0:
			pts.append(xf * p0.lerp(p1, u))
		else:
			pts.append(xf * p1)
			pts.append(xf * p1.lerp(p2, u - 1.0))
		canvas.draw_polyline(pts, c, w)
