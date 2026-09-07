extends TowerSkill

## RUBBLE — a stray brick drops onto the tower at the start of the target's
## turn, a beat ahead of their own. Whatever it knocks off is on them, and
## whatever it leaves is what they have to build on.
##
## Pack C is about the draw and the tower — which brick a player gets, and
## what the tower is when they get it. Tailor bends the draw for the caster;
## Keystone takes a brick out of the tower on the target's clock. This one
## puts a brick *in*: one the target never drew, arriving from above at the
## moment the tower becomes their problem. It is not the target's brick — it
## is not steered, it is not on the NEXT card, it is not even in the
## caster's colour by accident (it is, on purpose: the landed-brick glow says
## whose it was). It is just a load the tower did not have a second ago,
## falling onto a top that was flat and now is not.
##
## Why the rubble itself is never scored. The fault rule bills every fall
## during a turn to whoever is on the clock, and a brick thrown by somebody
## else that bounces straight off would cost the target a life for a coin
## toss they had no part in. That is a stat, not a mechanic (KeystoneSkill's
## header makes the same argument about pulling the base). So while this
## effect is live, tick() marks the rubble `doomed` itself the frame it
## passes LOST_Y — before TowerMode._cull_fallen() runs in the same physics
## frame, which then skips it — and it costs nothing. What it *knocks off*
## is scored, as is everything that happens on the target's clock, and once
## the turn resolves the rubble is a brick like any other: on the tower for
## everyone to build on, and on whoever's clock it later falls.
##
## Where it goes. A random classic tetromino (never the I — a stick on end is
## a coin, not rubble), in a random quarter-turn over a random lattice column
## *inside the platform's width* — but only from the pairs of turn and column
## whose landing is within TOP_BAND of the tower's highest point AND would
## stand: the columns it would rest on span at least SUPPORT_SPAN cells and
## its centre of mass sits inside that span by SUPPORT_MARGIN. Over the
## platform, so a caster can never drop it past the edge for a free miss;
## near the top, so it is the top that changes; standing, because the first
## version chose a column blind and tilted the brick for chaos, and it
## bounced straight off nineteen times in twenty-six; the second asked for
## half the footprint to be supported, which an inverted L on its one-cell
## stem satisfies, and it bounced off thirty-four times in forty-eight. A
## brick that lands on a corner and tumbles away is a dud that took four
## seconds; one that stays is the whole skill — a T bar-down on the top
## course, an S leaving a one-cell step, are real problems for whoever has
## to build on them, and they are theirs for the rest of the match. The
## impact is still the impact: from anything over a fraction of a cell it
## arrives at the terminal cap in TowerPiece._integrate_forces, so
## DROP_CELLS is kept small and only decides how hard it hits — and a fresh
## load landing at speed on a leaning top still knocks things off. That risk
## is the sting; the coin toss was not.
##
## Timing. The target's brick spawns seven cells above the stack and takes
## about 2.5s to descend on its own, 0.62s under a soft drop. The rubble is
## telegraphed for WARN_TIME (a ghost of it sinks onto the drop point, a
## shadow sharpens on the surface below), then released and on the tower
## within about 0.4s more — before an ordinary descent gets there, and onto
## the just-landed brick if the player soft-dropped, which is still their
## clock: a body in motion keeps the settle open. If the turn has somehow
## already resolved, the drop is skipped, never moved onto the next player.
##
## The one thing that must never happen is the rubble sharing space with
## the held brick. A held brick is out of the collision world, so a rigid
## body falling *through* it meets nothing — but TowerMode's descent query
## would see the rubble under the held brick's feet and land it in mid-air,
## and release() would then put two overlapping bodies into the solver. So
## the drop waits, frame by frame, while the held brick's box overlaps the
## rubble's spawn box sideways and the rubble is not entirely below it. A
## held brick above the rubble is safe: on an ordinary descent the rubble
## pulls away from it (it is at terminal speed inside a quarter second, twice
## the descent), and under a soft drop the held brick catches it up and lands
## on it, touching, which is exactly what the queries are for — the player
## pressed down into a telegraphed brick. The vertical clearance is small
## on purpose (CLEAR_Y_CELLS): the first version asked for half a cell, and
## since a held brick keeps descending into the spawn box while the drop
## waits, any wait became a wait until landing — which put the rubble on
## the target's fresh, unsettled brick instead of on the resting tower, and
## that is where the worst collapses came from. The spawn is also
## shape-queried against the tower and raised half a cell at a time if
## anything is there, so a leaning corner the surface estimate missed can
## never be spawned into. During settling the surface must include the brick
## `mode.active_piece` still points at: it has landed, and skipping it put
## the spawn inside it and abandoned the drop.
##
## Nothing outside `mode.pieces` is changed. The rubble is tower state — the
## one thing a skill may leave behind (TowerSkill's header) — and every
## other field here is the skill's own, so deactivate() has only references
## to drop and is trivially idempotent.

# --- Tuning ----------------------------------------------------------------

# The telegraph. Shorter than a soft drop from spawn plus SETTLE_HOLD, like
# Keystone's, so the release can never land in the resolve pause.
const WARN_TIME := 0.45
# How far above the surface under it the rubble is released. See the header:
# the impact speed is the terminal cap from a fraction of a cell up, so this
# only sets the length of the fall.
const DROP_CELLS := 0.25
# Only placements whose landing height is within this of the tower's top
# are candidates; if none is (a top brick hanging past the platform's edge),
# any placement over the platform will do.
const TOP_BAND_CELLS := 2.0
# A half-cell column under the footprint counts as supporting if its floor
# is within SUPPORT_GAP of the one the brick actually rests on. The
# supporting columns must span SUPPORT_SPAN cells from first to last (a
# bridge over a hole is fine, a one-cell perch is not) and the brick's centre
# of mass must lie inside that span by SUPPORT_MARGIN either way. Relaxed to
# any near-top placement if nothing qualifies.
const SUPPORT_GAP_CELLS := 0.3
const SUPPORT_SPAN_CELLS := 2.0
const SUPPORT_MARGIN_CELLS := 0.35
# The tilt off square, either way. A hint that it was thrown, not placed;
# small enough that a supported landing stays one.
const TILT := 0.06
# Samples per half-cell column of the surface — a leaning brick's corner is
# a point, not a column, and one sample at the centre misses it.
const SURFACE_SAMPLES := 3
# If the spawn is inside something, try this many half cells higher first —
# enough to clear a vertical I5 landed under it during settling.
const RAISE_TRIES := 12
# Held-brick clearance: sideways only a few pixels (every sideways move the
# held brick makes is refused at exact contact anyway); vertically a gap an
# ordinary descent can never close against a body accelerating away from it
# (see the header for why not more).
const CLEAR_X_CELLS := 0.1
const CLEAR_Y_CELLS := 0.3
# Impact: the first frame the rubble's downward speed halves from its peak.
const IMPACT_MIN_VY := 60.0

# The ghost sinks onto the drop point from this far above it over WARN_TIME.
const GHOST_FROM_CELLS := 3.0
const GHOST_WIDTH := 2.0
const PULSE_HZ := 3.0
const GUIDE_DASH := 7.0
# The shadow: a band of dark just above the surface under the footprint,
# sharpening as the drop nears. Drawn UNDER the bricks so the rubble covers
# it as it lands; the band is above the surface, in the air, so it shows.
const SHADOW_DEPTH_CELLS := 0.22
const SHADOW_ALPHA_MIN := 0.14
const SHADOW_ALPHA_MAX := 0.62
const SHADOW_FADE := 0.3
const SHADOW := Color(0.06, 0.07, 0.16)
# Dust and chips at the impact, and a short flash under the HUD for the
# players who were not looking at the tower.
const DUST_TIME := 0.5
const DUST_CHIPS := 6
const FLASH_TIME := 0.18
const FLASH_ALPHA := 0.16
const UNDERLINE := Color(0.06, 0.08, 0.20, 0.55)

# --- State -----------------------------------------------------------------

# Seconds into the target's turn; advanced in tick(), which only runs on it.
var _t := 0.0
# The rubble as chosen at activate(): BRICKS index, world rotation, lattice
# centre x, rotated footprint width in whole cells.
var _index := -1
var _steps := 0
var _rot := 0.0
var _x := 0.0
var _w := 1
# Where it is released; from the surface at activate(), redone at the drop.
var _spawn := Vector2.ZERO
# The rubble's collision boxes as plain shapes, for the spawn-space query.
# Resources, never nodes: refcounted away with the effect.
var _shapes: Array[RectangleShape2D] = []
var _locals: Array[Transform2D] = []
var _dropped := false
var _skipped := false
# Untyped on purpose (PROJECT_STATE §12): it is a landed brick the mode may
# cull and free while this effect still holds it.
var _rubble = null
var _peak_vy := 0.0
# Seconds since the impact; negative until it happens.
var _impact_t := -1.0
var _impact_at := Vector2.ZERO

# --- Lifecycle -------------------------------------------------------------

func activate() -> void:
	_t = 0.0
	_dropped = false
	_skipped = false
	_rubble = null
	_peak_vy = 0.0
	_impact_t = -1.0
	_choose()
	var who: String = GameSettings.PLAYER_CONFIGS[target]["name"]
	var from: String = GameSettings.PLAYER_CONFIGS[caster]["name"]
	var c: Color = mode._slot_color(caster)
	mode.hud.show_message("%s — RUBBLE INCOMING FROM %s" % [who, from], Color(c.r, c.g, c.b, 1.0))

func tick(delta: float) -> void:
	_t += delta
	if not _dropped and _t >= WARN_TIME:
		_try_drop()
	if _impact_t >= 0.0:
		_impact_t += delta
	if _rubble == null:
		return
	if not is_instance_valid(_rubble):
		_rubble = null
		return
	var r := _rubble as TowerPiece
	if r == null:
		_rubble = null
		return
	# The exemption: off the tower on the target's clock, but never theirs.
	# Runs before TowerMode._cull_fallen() in the same physics frame, which
	# then finds it already doomed and does not count it.
	var pos: Vector2 = r.global_position
	if not r.doomed and (pos.y > float(mode.LOST_Y) or absf(pos.x) > float(mode.LOST_X)):
		r.doomed = true
	if _impact_t < 0.0:
		var vy: float = r.linear_velocity.y
		_peak_vy = maxf(_peak_vy, vy)
		if _peak_vy > IMPACT_MIN_VY and vy < _peak_vy * 0.5:
			_impact_t = 0.0
			var box: Rect2 = _aabb(r.box_outlines(r.global_transform))
			_impact_at = Vector2(box.get_center().x, box.end.y)

func deactivate() -> void:
	# The rubble is the tower's now; only the reference is dropped.
	_rubble = null
	_dropped = true
	_shapes = []
	_locals = []

func hud_tag() -> String:
	if _skipped:
		return ""
	return "RUBBLED" if _dropped else "INCOMING"

# --- The choice ------------------------------------------------------------

# Half-cell columns across the platform, and the world x of their left edge.
func _columns() -> int:
	return int(round(float(mode.PLATFORM_CELLS) * 2.0))

func _column_left() -> float:
	return -float(mode.PLATFORM_CELLS) * float(mode.CELL) * 0.5

func _choose() -> void:
	var cell: float = mode.CELL
	var pool: Array[int] = []
	for i in range(GameSettings.BRICKS.size()):
		var b: Dictionary = GameSettings.BRICKS[i]
		if b["classic"] and str(b["name"]) != "I":
			pool.append(i)
	_index = pool[randi() % pool.size()]
	var data: Dictionary = GameSettings.BRICKS[_index]

	_shapes = []
	_locals = []
	var half := Vector2(float(data["cols"]), float(data["rows"])) * cell * 0.5
	for b: Rect2 in data["boxes"]:
		var rect := RectangleShape2D.new()
		rect.size = b.size * cell
		_shapes.append(rect)
		_locals.append(Transform2D(0.0, (b.position + b.size * 0.5) * cell - half))

	# Every quarter-turn at every lattice centre that keeps the footprint
	# over the platform, each scored for where it would rest and how much of
	# it would be resting; then a random one of the good ones.
	var n: int = _columns()
	var surface: PackedFloat32Array = _surface(SURFACE_SAMPLES)
	var top: float = float(mode.stack_top_y)
	var base: Array = _grid_of(data)
	var any: Array = []
	var near: Array = []
	var good: Array = []
	for steps in range(4):
		var grid: Array = _rotated(base, steps)
		var w: int = grid[0]
		var under: PackedInt32Array = _under(grid)
		var com: float = _com_x(grid) * 2.0 # in half-cells from the footprint's left edge
		var limit: int = (n >> 1) - w
		for i in range(-limit, limit + 1):
			var k0: int = i - w + (n >> 1)
			var y_bot := INF
			for k in range(k0, k0 + 2 * w):
				y_bot = minf(y_bot, surface[k] + float(under[(k - k0) >> 1]) * cell)
			var first := -1
			var last := -1
			for k in range(k0, k0 + 2 * w):
				if surface[k] + float(under[(k - k0) >> 1]) * cell - y_bot < SUPPORT_GAP_CELLS * cell:
					if first < 0:
						first = k - k0
					last = k - k0
			var cand: Array = [steps, i]
			any.append(cand)
			if y_bot <= top + TOP_BAND_CELLS * cell:
				near.append(cand)
				var span: float = float(last - first + 1) * 0.5
				var margin: float = SUPPORT_MARGIN_CELLS * 2.0
				if span >= SUPPORT_SPAN_CELLS and com >= float(first) + margin and com <= float(last + 1) - margin:
					good.append(cand)
	var from: Array = good if not good.is_empty() else (near if not near.is_empty() else any)
	var pick: Array = from[randi() % from.size()]
	_steps = pick[0]
	_rot = float(_steps) * PI * 0.5 + randf_range(-TILT, TILT)
	_w = int(data["cols"]) if _steps % 2 == 0 else int(data["rows"])
	_x = float(pick[1]) * cell * 0.5
	_spawn = _spawn_for(_floor_of(surface, pick[1]))

# A brick's cells as a flat grid: [width, height, PackedByteArray row-major].
func _grid_of(data: Dictionary) -> Array:
	var w: int = data["cols"]
	var h: int = data["rows"]
	var cells := PackedByteArray()
	cells.resize(w * h)
	for b: Rect2 in data["boxes"]:
		for r in range(int(b.position.y), int(b.position.y + b.size.y)):
			for c in range(int(b.position.x), int(b.position.x + b.size.x)):
				cells[r * w + c] = 1
	return [w, h, cells]

# The grid turned `steps` quarter-turns the way TowerMode turns a brick:
# Transform2D(PI/2) maps +x to +y, clockwise on a y-down screen, so a cell
# at (c, r) in a w x h grid lands at (h-1-r, c) in an h x w one.
func _rotated(grid: Array, steps: int) -> Array:
	var g: Array = grid
	for _s in range(steps):
		var w: int = g[0]
		var h: int = g[1]
		var cells: PackedByteArray = g[2]
		var out := PackedByteArray()
		out.resize(w * h)
		for r in range(h):
			for c in range(w):
				if cells[r * w + c] == 1:
					out[c * h + (h - 1 - r)] = 1
		g = [h, w, out]
	return g

# The centre of mass of a grid's filled cells, in cells from its left edge.
# Every cell weighs the same (TowerPiece.MASS_PER_CELL), so it is the mean.
func _com_x(grid: Array) -> float:
	var w: int = grid[0]
	var h: int = grid[1]
	var cells: PackedByteArray = grid[2]
	var sum := 0.0
	var count := 0
	for r in range(h):
		for c in range(w):
			if cells[r * w + c] == 1:
				sum += float(c) + 0.5
				count += 1
	return sum / float(maxi(count, 1))

# Per cell-column of a rotated grid: empty cells beneath its lowest filled
# cell. A bounding box is tight, so every column has one.
func _under(grid: Array) -> PackedInt32Array:
	var w: int = grid[0]
	var h: int = grid[1]
	var cells: PackedByteArray = grid[2]
	var out := PackedInt32Array()
	out.resize(w)
	for j in range(w):
		var lowest := 0
		for r in range(h):
			if cells[r * w + j] == 1:
				lowest = r
		out[j] = h - 1 - lowest
	return out

# The highest surface point under the footprint centred on lattice `i`.
func _floor_of(surface: PackedFloat32Array, i: int) -> float:
	var n: int = _columns()
	var k0: int = i - _w + (n >> 1)
	var out := INF
	for k in range(k0, k0 + 2 * _w):
		if k >= 0 and k < n:
			out = minf(out, surface[k])
	return out

# The release point whose bounding box sits DROP_CELLS above `floor_y`.
func _spawn_for(floor_y: float) -> Vector2:
	var box: Rect2 = _aabb(_outlines(Transform2D(_rot, Vector2(_x, 0.0))))
	return Vector2(_x, floor_y - DROP_CELLS * float(mode.CELL) - box.end.y)

# --- The drop --------------------------------------------------------------

func _try_drop() -> void:
	if mode.state == "resolving" or mode.state == "gameover":
		_dropped = true
		_skipped = true
		return
	var cell: float = mode.CELL
	var surface: PackedFloat32Array = _surface(SURFACE_SAMPLES)
	var at: Vector2 = _spawn_for(_floor_of(surface, int(round(_x / (cell * 0.5)))))
	var clear := false
	for _i in range(RAISE_TRIES):
		if not _occupied(Transform2D(_rot, at)):
			clear = true
			break
		at.y -= cell * 0.5
	if not clear:
		_dropped = true
		_skipped = true
		var who: String = GameSettings.PLAYER_CONFIGS[target]["name"]
		var c: Color = mode._slot_color(caster)
		mode.hud.show_message("%s — RUBBLE: NOWHERE TO FALL" % who, Color(c.r, c.g, c.b, 1.0))
		return
	_spawn = at

	# Never into, or above, the held brick. See the header.
	var ap = mode.active_piece
	if ap != null and is_instance_valid(ap):
		var held := ap as TowerPiece
		if held != null and held.held:
			var hb: Rect2 = _aabb(held.box_outlines(held.global_transform))
			var rb: Rect2 = _aabb(_outlines(Transform2D(_rot, at)))
			var mx: float = cell * CLEAR_X_CELLS
			var my: float = cell * CLEAR_Y_CELLS
			var beside: bool = rb.end.x + mx <= hb.position.x or rb.position.x - mx >= hb.end.x
			var below: bool = rb.position.y >= hb.end.y + my
			if not beside and not below:
				return # wait; the held brick is on its way down

	var piece: TowerPiece = mode.PIECE_SCENE.instantiate()
	mode.pieces.add_child(piece) # before setup(): it reaches its @onready Sprite2D
	piece.setup(_index, cell, caster, mode._slot_color(caster))
	piece.rotation = _rot
	piece.global_position = at
	piece.release()
	_rubble = piece
	_dropped = true

# Is anything in the collision world where the rubble would appear? Only
# valid from the physics step, which tick() is.
func _occupied(xf: Transform2D) -> bool:
	var space: PhysicsDirectSpaceState2D = mode.get_world_2d().direct_space_state
	var q := PhysicsShapeQueryParameters2D.new()
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.margin = 0.0
	for i in range(_shapes.size()):
		q.shape = _shapes[i]
		q.transform = xf * _locals[i]
		if not space.intersect_shape(q, 1).is_empty():
			return true
	return false

# --- Geometry --------------------------------------------------------------

# The rubble's silhouette, one closed loop per collision box, at `xf` —
# TowerPiece.box_outlines() for a brick that does not exist yet.
func _outlines(xf: Transform2D) -> Array[PackedVector2Array]:
	var data: Dictionary = GameSettings.BRICKS[_index]
	var cell: float = mode.CELL
	var half := Vector2(float(data["cols"]), float(data["rows"])) * cell * 0.5
	var out: Array[PackedVector2Array] = []
	for b: Rect2 in data["boxes"]:
		var p: Vector2 = b.position * cell - half
		var s: Vector2 = b.size * cell
		var corners: Array[Vector2] = [p, p + Vector2(s.x, 0.0), p + s, p + Vector2(0.0, s.y)]
		var pts := PackedVector2Array()
		for c: Vector2 in corners:
			pts.append(xf * c)
		pts.append(xf * corners[0])
		out.append(pts)
	return out

func _aabb(outlines: Array[PackedVector2Array]) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for pts: PackedVector2Array in outlines:
		for q: Vector2 in pts:
			lo = lo.min(q)
			hi = hi.max(q)
	return Rect2(lo, hi - lo)

# The tower's top profile over the platform, one value per half-cell column:
# the highest world y of anything landed there, the platform's top (0) where
# nothing is. From the bricks' real rotated silhouettes, so it is valid from
# a draw as well as from the physics step. Held and doomed bricks are
# skipped — NOT `mode.active_piece`, which during settling is a landed brick
# (see the header) — and so is the rubble itself, so the shadow stays where
# it was aimed rather than riding the rubble down.
func _surface(samples: int) -> PackedFloat32Array:
	var n: int = _columns()
	var half: float = float(mode.CELL) * 0.5
	var left: float = _column_left()
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(0.0)
	for c in mode.pieces.get_children():
		var p := c as TowerPiece
		if p == null or p.held or p.doomed or p == _rubble:
			continue
		for pts: PackedVector2Array in p.box_outlines(p.global_transform):
			var x0 := INF
			var x1 := -INF
			for q: Vector2 in pts:
				x0 = minf(x0, q.x)
				x1 = maxf(x1, q.x)
			if x1 < left or x0 > left + float(n) * half:
				continue
			var k0: int = clampi(int(floor((x0 - left) / half)), 0, n - 1)
			var k1: int = clampi(int(floor((x1 - left) / half)), 0, n - 1)
			for k in range(k0, k1 + 1):
				for s in range(samples):
					var x: float = left + float(k) * half + half * (float(s) + 0.5) / float(samples)
					var y: float = _top_at(pts, x)
					if y < out[k]:
						out[k] = y
	return out

# Where a vertical line at `x` first meets a closed 4-corner outline, from
# above. INF if it misses.
func _top_at(pts: PackedVector2Array, x: float) -> float:
	var best := INF
	for i in range(4):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var lo: float = minf(a.x, b.x)
		var hi: float = maxf(a.x, b.x)
		if x < lo or x > hi:
			continue
		if hi - lo < 1.0e-4:
			best = minf(best, minf(a.y, b.y))
		else:
			best = minf(best, a.y + (b.y - a.y) * ((x - a.x) / (b.x - a.x)))
	return best

# --- Drawing ---------------------------------------------------------------

func _px(width: float) -> float:
	return width / float(mode.cam_zoom)

# Under the bricks: the shadow on the surface under the footprint. It
# darkens through the warning, holds through the fall, and fades once the
# rubble is down.
func draw_under() -> void:
	if mode.active_slot != target or _skipped:
		return
	var alpha: float
	if not _dropped:
		alpha = lerpf(SHADOW_ALPHA_MIN, SHADOW_ALPHA_MAX, clampf(_t / WARN_TIME, 0.0, 1.0))
	elif _impact_t < 0.0:
		alpha = SHADOW_ALPHA_MAX
	elif _impact_t < SHADOW_FADE:
		alpha = SHADOW_ALPHA_MAX * (1.0 - _impact_t / SHADOW_FADE)
	else:
		return
	var cell: float = mode.CELL
	var half: float = cell * 0.5
	var n: int = _columns()
	var left: float = _column_left()
	var surface: PackedFloat32Array = _surface(1)
	var k0: int = int(round(_x / half)) - _w + (n >> 1)
	var depth: float = cell * SHADOW_DEPTH_CELLS
	for k in range(k0, k0 + 2 * _w):
		if k < 0 or k >= n:
			continue
		var y: float = surface[k]
		mode.draw_rect(Rect2(left + float(k) * half, y - depth, half, depth), Color(SHADOW.r, SHADOW.g, SHADOW.b, alpha), true)
		mode.draw_rect(Rect2(left + float(k) * half, y - depth * 0.35, half, depth * 0.35), Color(SHADOW.r, SHADOW.g, SHADOW.b, alpha * 0.6), true)

# Above the bricks: the ghost sinking onto the drop point with a dashed
# guide down to the shadow, then dust and chips at the impact.
func draw_over(canvas: CanvasItem) -> void:
	if mode.active_slot != target or _skipped:
		return
	var c: Color = mode._slot_color(caster)
	var cell: float = mode.CELL

	if not _dropped:
		var u: float = clampf(_t / WARN_TIME, 0.0, 1.0)
		var e: float = u * u # eased in: it arrives faster than it set off
		var y: float = lerpf(_spawn.y - GHOST_FROM_CELLS * cell, _spawn.y, e)
		var pulse: float = 0.5 + 0.5 * sin(_t * TAU * PULSE_HZ)
		var xf := Transform2D(_rot, Vector2(_x, y))
		var outlines: Array[PackedVector2Array] = _outlines(xf)
		var fill := Color(c.r, c.g, c.b, 0.10 + 0.28 * u)
		var edge := Color(c.r, c.g, c.b, 0.55 + 0.45 * pulse)
		for pts: PackedVector2Array in outlines:
			canvas.draw_colored_polygon(pts.slice(0, 4), fill)
			canvas.draw_polyline(pts, UNDERLINE, _px(GHOST_WIDTH + 2.0))
			canvas.draw_polyline(pts, edge, _px(GHOST_WIDTH))
		# The guide: dashed, from under the ghost to the surface it is aimed
		# at, marching downward so the direction reads even when still.
		var box: Rect2 = _aabb(outlines)
		var floor_y: float = _floor_of(_surface(1), int(round(_x / (cell * 0.5))))
		var top: float = box.end.y + cell * 0.15
		var phase: float = fmod(_t * cell * 2.0, GUIDE_DASH * 2.0)
		var yy: float = top - GUIDE_DASH * 2.0 + phase
		while yy < floor_y:
			var a: float = maxf(yy, top)
			var b: float = minf(yy + GUIDE_DASH, floor_y)
			if b > a:
				canvas.draw_line(Vector2(_x, a), Vector2(_x, b), UNDERLINE, _px(3.5))
				canvas.draw_line(Vector2(_x, a), Vector2(_x, b), Color(c.r, c.g, c.b, 0.85), _px(1.5))
			yy += GUIDE_DASH * 2.0
		return

	if _impact_t < 0.0 or _impact_t >= DUST_TIME:
		return
	# Dust: one ring running outward along the surface, and chips thrown up
	# in a fan, shrinking as they go.
	var d: float = _impact_t / DUST_TIME
	var ring := Color(0.95, 0.93, 0.88, 0.5 * (1.0 - d))
	canvas.draw_arc(_impact_at, cell * (0.3 + 1.4 * d), PI, TAU, 20, ring, _px(2.5))
	for i in range(DUST_CHIPS):
		var ang: float = PI + PI * (float(i) + 0.5) / float(DUST_CHIPS)
		var dir := Vector2.from_angle(ang)
		var at: Vector2 = _impact_at + dir * cell * (0.25 + 1.1 * d) + Vector2(0.0, cell * 0.9 * d * d)
		var s: float = cell * 0.13 * (1.0 - d)
		var spin: float = ang + d * 4.0
		var pts := PackedVector2Array()
		for j in range(4):
			pts.append(at + Vector2.from_angle(spin + float(j) * PI * 0.5) * s)
		canvas.draw_colored_polygon(pts, Color(c.r, c.g, c.b, 0.9 * (1.0 - d)))

# Screen space, under the HUD: the flash at the impact.
func draw_screen(canvas: CanvasItem) -> void:
	if mode.active_slot != target or _impact_t < 0.0 or _impact_t >= FLASH_TIME:
		return
	var c: Color = mode._slot_color(caster)
	var a: float = FLASH_ALPHA * (1.0 - _impact_t / FLASH_TIME)
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.get_viewport_rect().size), Color(c.r, c.g, c.b, a), true)
