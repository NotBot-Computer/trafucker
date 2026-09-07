extends TowerSkill

## TAILOR — the caster's NEXT brick is cut to fit the top of the tower.
##
## The draw is the one thing in Pile Up nobody controls: nineteen shapes,
## weighted toward the classics, and whatever comes down is what you get. This
## skill takes that turn away from the dice, once. When the caster's next turn
## comes round, the tower's top is measured and every shape in the set is
## tried in every quarter-turn at every lattice position the aim clamp allows;
## the one that fills the gaps best is the brick that spawns, and a ghost of it
## is drawn in the socket it was cut for so the player knows where the tailor
## meant it to go. The HUD's NEXT BRICK card will have shown something else —
## spawn_index_override() is a surprise by construction (TowerSkill's header)
## — and the toast at spawn says what arrived instead.
##
## It is deliberately the *next* brick and not this one. Both spawn hooks are
## read at the start of a turn, before the brick exists, and a self skill is
## cast with the caster's brick already in the air; so the effect lasts two of
## the caster's turns — the cast turn, on which it only measures, and the next,
## on which it delivers — and the blurb says so. In a three-player match that
## is two other turns of tower changing in between, which is why the fit is
## computed at the moment of the spawn rather than when the skill was cast:
## a shape tailored to a tower two bricks ago fits nothing.
##
## spawn_index_override() therefore does real work when TowerMode calls it —
## it reads the landed bricks under `mode.pieces` — but it depends on nothing
## activate() set: `mode` comes from setup(), and every landed brick is fair
## to read at any time. That keeps it safe for the hook's contract (constant,
## or own fields set in setup) while still answering for the tower as it is.
##
## Nothing here changes the mode. No node, no multiplier, no camera — the only
## thing the skill does to the world is choose one integer at spawn — so
## deactivate() has nothing to put back and is trivially idempotent.

# --- Tuning ----------------------------------------------------------------

# The cast turn plus the one the brick arrives on. See the header for why it
# cannot be one.
const TURNS := 2

# How the fit is scored. A placement rests the brick on the highest point
# under any of its columns; every other column is then hanging over a void,
# and the sum of those voids (in cell-areas) is the primary score — a brick
# that fills the gap has none. A column with nothing under it at all (past the
# platform's edge, or over a hole the tower has grown around) would score an
# infinite void, so it is capped: four cells of drop is already "do not put
# a brick here", and an uncapped value would let one overhanging cell decide
# everything about a placement that is otherwise perfect.
const GAP_CAP_CELLS := 4.0
# Secondary term: how ragged the profile is *after* the brick is in, over
# the brick's own columns and a cell either side. It exists for ties — on a
# flat top every shape has a zero-void placement somewhere, and without this
# the first in the table would win (a vertical I, which is the worst possible
# answer). Small, so it never outranks a real gap: a two-cell step costs less
# than one cell of void.
const ROUGH_WEIGHT := 0.35
# How many x positions inside each half-cell column the surface is sampled at
# when scoring. Landed bricks lean, and a leaning brick's corner is a point,
# not a column; three samples catch a corner that one at the centre misses.
const SCORE_SAMPLES := 3
# Surface value for a column with nothing in it. Anything at or above this is
# "open air" to every reader below.
const OPEN_AIR := 1.0e6
# Placements are only tried near the top first: the brick's bounding-box
# bottom no more than this far below the tower's highest point. Without it
# the search fills the basement — a vertical I5 standing on bare platform
# beside a seven-cell stack is a perfect zero-void fit, and was the first
# thing this picked — and the skill is about the top. Widened to everything
# only if nothing qualifies, which a single leaning corner sticking up past
# the usable top can cause.
const TOP_BAND_CELLS := 2.0
# A neighbouring column further below the brick's base than this is a cliff,
# not a step. No brick can fix it, so it does not count against the fit —
# otherwise every placement beside a tall drop scores the same roughness and
# the term stops choosing anything.
const CLIFF_CELLS := 3.0
# Half-cells either side of the brick the roughness is judged over: one cell,
# the width of the step a brick can actually be part of.
const ROUGH_MARGIN := 2

# The tape measure on the cast turn: how long it takes to run the width of the
# play column, how far above the surface it floats (so it reads as a tape
# laid over the tower rather than as the tower's own outline), and its ticks.
const TAPE_TIME := 1.1
const TAPE_LIFT := 4.0
const TICK_LEN := 6.0
const TICK_LEN_LONG := 10.0
const TAPE_WIDTH := 2.5
# The ghost on the delivery turn: a slow breathe, and a brighter first half
# second so the eye finds the socket at the moment the brick appears.
const PULSE_HZ := 1.2
const FLASH_TIME := 0.5
const GHOST_WIDTH := 2.0
# Contrast stroke under every coloured line. Everything here is drawn over
# a bright pixel-art sky (PROJECT_STATE §7: dark, not light), and a coloured
# hairline alone vanishes against it.
const UNDERLINE := Color(0.06, 0.08, 0.20, 0.55)

# --- State -----------------------------------------------------------------

# Seconds into the current live turn of the caster's; advanced in tick(),
# which only runs on their turns, so it never moves while others are playing.
var _t := 0.0
# "measure" on the cast turn, "fit" from the moment the tailored brick spawns.
var _phase := "measure"
# What the fit chose, set inside spawn_index_override(): the BRICKS index, the
# quarter-turns from upright, and the world centre of the bounding box.
var _pick := -1
var _pick_steps := 0
var _pick_centre := Vector2.ZERO
# True once on_turn_start() has confirmed the brick in the air really is the
# tailored one. Another effect on the same player can claim the spawn first
# (first live claim wins in TowerMode._effect_spawn_index) or resize it, and
# a ghost drawn for a brick that is not the one falling would be a lie.
var _ghost_ok := false

func duration_turns() -> int:
	return TURNS

# --- Lifecycle -------------------------------------------------------------

func activate() -> void:
	_t = 0.0
	_phase = "measure"
	_pick = -1
	_ghost_ok = false

func tick(delta: float) -> void:
	_t += delta

# Consulted by TowerMode._begin_turn() at the start of the caster's next turn,
# after _recompute_stack_top() and before the brick is built. The new
# TowerPiece node is already under mode.pieces at this point but has not been
# set up — its `held` is still the default true, so _surface() skips it.
func spawn_index_override() -> int:
	if mode == null:
		return -1
	_compute_fit()
	return _pick

func on_turn_start() -> void:
	_phase = "fit"
	_t = 0.0
	_ghost_ok = false
	var ap = mode.active_piece
	if ap == null or not is_instance_valid(ap) or _pick < 0:
		return
	var piece := ap as TowerPiece
	if piece == null or not piece.held:
		return
	# Same shape and same size as the fit was scored for; a 2x brick from
	# another effect would not sit in a socket measured for a 1x one.
	if piece.shape_index != _pick or not is_equal_approx(piece.cell, float(mode.CELL)):
		return
	_ghost_ok = true
	var who: String = GameSettings.PLAYER_CONFIGS[caster]["name"]
	var c: Color = mode._slot_color(caster)
	mode.hud.show_message("%s — CUT TO FIT: %s" % [who, str(GameSettings.BRICKS[_pick]["name"])], Color(c.r, c.g, c.b, 1.0))

func deactivate() -> void:
	# Nothing in the mode was changed, so there is nothing to restore; the
	# flag only stops a stale ghost if a draw ever ran on a retired effect.
	_ghost_ok = false

func hud_tag() -> String:
	if _phase == "measure":
		return "MEASURING"
	return "TAILORED" if _ghost_ok else ""

# --- The fit ---------------------------------------------------------------

# Half-cell columns across the whole play column. Every command in this mode
# lands on a half-cell lattice, so a brick's cell edges can sit on any half
# cell and the surface has to be known at that resolution.
func _columns() -> int:
	return int(round((float(mode.PLATFORM_CELLS) * 0.5 + float(mode.AIM_BOUND_CELLS)) * 4.0))

func _column_left(n: int) -> float:
	return -float(n) * float(mode.CELL) * 0.25

# The tower's top profile: for each half-cell column, the highest world y
# (smallest, -y is up) of anything landed in it, the platform's top (0) where
# the platform is, and OPEN_AIR where there is nothing at all. Built from the
# bricks' real rotated silhouettes rather than from a physics query, so it is
# valid from a draw as well as from the physics step.
func _surface(n: int, samples: int) -> PackedFloat32Array:
	var cell: float = mode.CELL
	var half: float = cell * 0.5
	var left: float = _column_left(n)
	var platform_half: float = float(mode.PLATFORM_CELLS) * cell * 0.5
	var out := PackedFloat32Array()
	out.resize(n)
	for k in range(n):
		var xc: float = left + (float(k) + 0.5) * half
		out[k] = 0.0 if absf(xc) < platform_half else OPEN_AIR
	var ap = mode.active_piece
	for c in mode.pieces.get_children():
		var p := c as TowerPiece
		if p == null or p.held or p.doomed or p == ap:
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
# Transform2D(PI/2) maps +x to +y, which on a y-down screen is clockwise, so
# a cell at (c, r) in a w x h grid lands at (h-1-r, c) in an h x w one.
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

# Lattice centres tried nearest-first, so a tie between equally good
# placements goes to the one that needs the least steering.
func _centre_order(limit: int) -> Array[int]:
	var out: Array[int] = [0]
	for i in range(1, limit + 1):
		out.append(-i)
		out.append(i)
	return out

# The search: every shape, every quarter-turn, every lattice centre the aim
# clamp allows, scored by _score(). Tried first within TOP_BAND of the tower's
# highest point and only then anywhere, see that constant.
func _compute_fit() -> void:
	_pick = -1
	var cell: float = mode.CELL
	var n: int = _columns()
	var surface: PackedFloat32Array = _surface(n, SCORE_SAMPLES)
	var top: float = float(mode.stack_top_y)
	for band: float in [TOP_BAND_CELLS * cell, INF]:
		var best := INF
		for index in range(GameSettings.BRICKS.size()):
			var base: Array = _grid_of(GameSettings.BRICKS[index])
			for steps in range(4):
				var grid: Array = _rotated(base, steps)
				var w: int = grid[0]
				# TowerMode._command_to() clamps the centre to +-(reach -
				# half width); in half-cells that is reach - w, exact on the
				# lattice because w is a whole number of cells.
				var limit: int = (n >> 1) - w
				if limit < 0:
					continue
				var profile: Array = _profile(grid)
				if profile.is_empty():
					continue
				for i: int in _centre_order(limit):
					var r: Array = _score(surface, n, grid, profile, i, top + band)
					if r.is_empty():
						continue
					if float(r[0]) < best - 1.0e-6:
						best = r[0]
						_pick = index
						_pick_steps = steps
						_pick_centre = r[1]
		if _pick >= 0:
			return

# Per cell-column of a rotated grid: [under, crown] — empty cells beneath the
# lowest filled cell, and the row of the highest. A bounding box is tight, so
# every column has a cell; an empty one returns [] and the shape is skipped.
func _profile(grid: Array) -> Array:
	var w: int = grid[0]
	var h: int = grid[1]
	var cells: PackedByteArray = grid[2]
	var under := PackedInt32Array()
	var crown := PackedInt32Array()
	under.resize(w)
	crown.resize(w)
	for j in range(w):
		var lowest := -1
		var highest := -1
		for r in range(h):
			if cells[r * w + j] == 1:
				if highest < 0:
					highest = r
				lowest = r
		if lowest < 0:
			return []
		under[j] = h - 1 - lowest
		crown[j] = highest
	return [under, crown]

# One placement — the grid centred on lattice half-cell `i` — scored against
# the surface. Returns [score, bounding-box centre], or [] if the brick would
# rest on nothing or its bottom would sit below `max_bot`.
func _score(surface: PackedFloat32Array, n: int, grid: Array, profile: Array, i: int, max_bot: float) -> Array:
	var cell: float = mode.CELL
	var half: float = cell * 0.5
	var w: int = grid[0]
	var h: int = grid[1]
	var under: PackedInt32Array = profile[0]
	var crown: PackedInt32Array = profile[1]
	var k_left: int = i - w + (n >> 1)
	var k_right: int = k_left + 2 * w

	# The brick rests on whichever column stops it first.
	var y_bot := INF
	for k in range(k_left, k_right):
		var s: float = surface[k]
		if s >= OPEN_AIR:
			continue
		y_bot = minf(y_bot, s + float(under[(k - k_left) >> 1]) * cell)
	if is_inf(y_bot) or y_bot > max_bot:
		return []

	# Void under it, in cell-areas (half-columns are half a cell wide).
	var void_cells := 0.0
	for k in range(k_left, k_right):
		var floor_y: float = surface[k] + float(under[(k - k_left) >> 1]) * cell
		void_cells += minf(floor_y - y_bot, GAP_CAP_CELLS * cell) / cell * 0.5

	# The profile once it is in: the brick's own tops, then ROUGH_MARGIN
	# half-cells either side — but a neighbour more than CLIFF_CELLS below
	# the brick's BASE is a cliff, not a step, and is left out. The base,
	# not the new top: measured against the top, a tall thin brick turns
	# every neighbour into a cliff and scores a perfect zero standing on end,
	# which is how a vertical I got picked for a flat top.
	var lo := INF
	var hi := -INF
	var base := -INF
	for k in range(k_left, k_right):
		var y: float = y_bot - float(h - crown[(k - k_left) >> 1]) * cell
		lo = minf(lo, y)
		hi = maxf(hi, y)
		if surface[k] < OPEN_AIR:
			base = maxf(base, surface[k])
	for k in range(k_left - ROUGH_MARGIN, k_right + ROUGH_MARGIN):
		if k < 0 or k >= n or (k >= k_left and k < k_right):
			continue
		var y: float = surface[k]
		if y >= OPEN_AIR or y > base + CLIFF_CELLS * cell:
			continue
		lo = minf(lo, y)
		hi = maxf(hi, y)
	var rough: float = (hi - lo) / cell

	return [void_cells + ROUGH_WEIGHT * rough, Vector2(float(i) * half, y_bot - float(h) * cell * 0.5)]

# --- Drawing ---------------------------------------------------------------

func _px(width: float) -> float:
	return width / float(mode.cam_zoom)

# Above the bricks: the tape measure, on the cast turn only. It unrolls left
# to right along the tower's real top profile — steps and all — with a tick
# every half cell and a longer one every whole cell, and a cursor at the tip.
# Purely a telegraph: the tower will change before the fit is computed, so
# nothing here is the answer, it is the tailor at work.
func draw_over(canvas: CanvasItem) -> void:
	if _phase != "measure" or mode.active_slot != target or mode.state != "piloting":
		return
	var cell: float = mode.CELL
	var half: float = cell * 0.5
	var n: int = _columns()
	var left: float = _column_left(n)
	var surface: PackedFloat32Array = _surface(n, 1)
	var c: Color = mode._slot_color(caster)
	var u: float = clampf(_t / TAPE_TIME, 0.0, 1.0)
	var reach: float = u * float(n) # columns unrolled, fractional
	var m: int = int(floor(reach))
	# Once unrolled, a slow breathe so it reads as live rather than painted.
	var settled: float = 0.85 + 0.15 * sin((_t - TAPE_TIME) * TAU * PULSE_HZ) if u >= 1.0 else 1.0
	var line := Color(c.r, c.g, c.b, 0.95 * settled)

	var run := PackedVector2Array()
	var tip := Vector2.ZERO
	var have_tip := false
	for k in range(n):
		if k > m:
			break
		var y: float = surface[k]
		if y >= OPEN_AIR:
			_stroke(canvas, run, line, TAPE_WIDTH)
			run = PackedVector2Array()
			continue
		var xl: float = left + float(k) * half
		var xr: float = xl + half
		var yy: float = y - TAPE_LIFT
		run.append(Vector2(xl, yy))
		if k < m:
			run.append(Vector2(xr, yy))
			var tick: float = TICK_LEN_LONG if k % 2 == 0 else TICK_LEN
			canvas.draw_line(Vector2(xl, yy), Vector2(xl, yy - tick), line, _px(1.5))
		else:
			tip = Vector2(lerpf(xl, xr, reach - float(m)), yy)
			run.append(tip)
			have_tip = true
	_stroke(canvas, run, line, TAPE_WIDTH)

	if have_tip and u < 1.0:
		# The tip: a small pointer riding the end of the tape.
		var bob: float = 2.0 * sin(_t * TAU * 3.0)
		var apex := tip + Vector2(0.0, -TAPE_LIFT - 4.0 + bob)
		canvas.draw_colored_polygon(PackedVector2Array([
			apex + Vector2(-5.0, -8.0), apex + Vector2(5.0, -8.0), apex,
		]), line)

# One polyline with a dark contrast stroke under it. Needs two points.
func _stroke(canvas: CanvasItem, pts: PackedVector2Array, color: Color, width: float) -> void:
	if pts.size() < 2:
		return
	canvas.draw_polyline(pts, UNDERLINE, _px(width + 2.0))
	canvas.draw_polyline(pts, color, _px(width))

# Under the bricks: the ghost of the fit, on the delivery turn. Drawn on the
# mode's own canvas so the descending brick passes OVER it and covers it when
# they coincide — which is exactly the feedback the player wants: the ghost
# disappears as the brick fills it. It brightens to white when the commanded
# position and rotation already match, so "lined up" can be read before the
# brick has finished chasing the command.
func draw_under() -> void:
	if _phase != "fit" or not _ghost_ok or mode.active_slot != target or mode.state != "piloting":
		return
	var ap = mode.active_piece
	if ap == null or not is_instance_valid(ap):
		return
	var piece := ap as TowerPiece
	if piece == null or not piece.held:
		return
	var c: Color = mode._slot_color(caster)
	var xf := Transform2D(float(_pick_steps) * PI * 0.5, _pick_centre)
	var lined: bool = posmod(int(mode.aim_steps), 4) == _pick_steps and absf(float(mode.aim_x) - _pick_centre.x) < 0.5
	var pulse: float = 0.5 + 0.5 * sin(_t * TAU * PULSE_HZ)
	var flash: float = clampf(1.0 - _t / FLASH_TIME, 0.0, 1.0)
	var fill := Color(c.r, c.g, c.b, 0.14 + 0.08 * pulse + 0.22 * flash)
	var edge := Color(1.0, 1.0, 1.0, 0.9) if lined else Color(c.r, c.g, c.b, 0.5 + 0.35 * pulse)
	for pts: PackedVector2Array in piece.box_outlines(xf):
		mode.draw_colored_polygon(pts.slice(0, 4), fill)
		mode.draw_polyline(pts, UNDERLINE, _px(GHOST_WIDTH + 2.0))
		mode.draw_polyline(pts, edge, _px(GHOST_WIDTH))
