extends TowerSkill

## PLUMB LINE (pack B, id "plumb") — a self skill about the caster's eyes and
## hands, and nothing about the tower.
##
## Judging a drop in this mode is done by eye against a leaning stack, from
## seven cells up, with the brick coming down at nearly three cells a second.
## The mode's own drop guide helps — a translucent column and a line at the
## stack top — but it answers "which column am I over", not "what will my
## brick actually be resting on when it stops". This skill answers the second
## question, literally: a plumb line drops from the brick to a ghost of its
## own silhouette drawn *exactly where the descent will end*, found by asking
## the physics space the same question TowerMode's own landing check asks,
## and every foot of that ghost is marked as either standing on something or
## hanging in the air. A corner over nothing is red before the brick gets
## there, which is the thing a player cannot see for themselves on a tower
## that is three bricks of lean away from level.
##
## The other half is the hands: the descent runs at half speed for the turn
## (descend_speed_mult), so there is time to act on what the line shows. The
## soft drop is deliberately left at full speed — once the line says the
## shot is good, the player should be able to commit to it as fast as ever,
## and a skill that slowed *that* would be taking time away with one hand
## while giving it with the other.
##
## What it does NOT do, on purpose: it does not steer, snap or auto-align
## anything. The mode's whole feel is that every half-cell is the player's
## own press, and a skill that moved the brick for them would be a different
## game for one turn. The ghost is information; acting on it is still the
## player's job.
##
## Nothing here writes a field on the mode or adds a node. The scan runs in
## tick() — inside _physics_process, the only place a shape query is valid —
## and caches its answer in fields below; draw_over() only reads them. The
## scratch shapes and the query object are Resources owned by this effect
## and are refcounted away with it, so deactivate() has nothing to free.

# --- Tuning ----------------------------------------------------------------

# Half speed. At DESCEND_SPEED (105px/s, ~2.8 cells/s) the seven-cell fall
# takes ~2.5s; at half that it is ~5s, which is long enough to read the
# ghost, step twice and turn once, and still well under TowerSkillProbe's
# 20s turn ceiling. Lower than this and a turn under Plumb Line stalls the
# table — the other players are watching a brick hang in the air.
const DESCEND_MULT := 0.5

# The scan steps the brick's silhouette down from where it is until a query
# says the space is taken, then bisects. A quarter cell (9.5px) is finer
# than the mode's own soft-drop step (~7px/frame at 60Hz), so no ledge the
# real descent would stop on is stepped over; six halvings bring the answer
# to ~0.15px, which is below anything the eye can see at this zoom.
const SCAN_STEP_CELLS := 0.25
const SCAN_REFINE := 6
const SCAN_GUARD := 400 # steps before the scan gives up; ~95 cells of clear air, more than any tower

# Feet are cut along each box's world-space bottom edge in half-cell
# segments, inset by TowerPiece.FOOT_INSET like the mode's own support
# probes so a wall pressed flat against the brick's side cannot count as
# holding it up. FOOT_GAP is the gap left between neighbouring segments so
# two adjacent feet read as two.
const FOOT_CELLS := 0.5
const FOOT_GAP := 3.0

# --- Visuals ----------------------------------------------------------------
# All procedural, in world space over the bricks (draw_over): the line and
# the ghost have to sit *on* the tower to say anything about it. Line widths
# are in screen pixels and divided by the camera zoom, the way TowerMode's
# own _px() does, so a hairline stays a hairline when the camera pulls back.

# Brass, for the bob and the tag. Deliberately not the owner's colour: the
# line is *about* the owner's brick and takes its colour from it, and the bob
# is the tool on the end of it.
const BRASS := Color(0.93, 0.75, 0.29)
const HANG := Color(1.0, 0.36, 0.30) # a foot with nothing under it
# Every stroke is the owner's colour over a dark rim. The backdrop is a
# bright pixel-art sky and the owner colours include a yellow; a single
# light stroke over that is invisible (PROJECT_STATE §7 — anything drawn
# over this backdrop must be dark, not light), and the ghost is the one
# thing here that has to be read at a glance.
const RIM := Color(0.08, 0.09, 0.16)
const LINE_ALPHA := 0.75
const GHOST_FILL_ALPHA := 0.22
const GHOST_LINE_ALPHA := 0.85
const LINE_WIDTH := 2.0 # screen px
const GHOST_WIDTH := 2.0
const RIM_EXTRA := 2.0 # px the rim stroke is wider than the stroke it backs
const FOOT_WIDTH := 4.0
const BOB_SIZE := 9.0 # screen px, half-height of the diamond
const FOOT_DROP := 3.0 # px below the ghost's underside the foot marks are drawn
# Feet ABOVE the ghost's lowest edge are the shape's own overhangs — an S's
# upper arm, a T's crossbar — and hang by construction wherever the brick
# lands. They are drawn but quiet; only the feet at the lowest level, the
# ones that decide whether the brick is standing on anything, get the full
# colour and the pulse.
const UPPER_FOOT_ALPHA := 0.35
const LOWEST_TOLERANCE := 2.0 # px: feet within this of the lowest are "lowest"

# The bob swings in from the side when the line is first dropped and settles
# on the vertical: a damped pendulum, amplitude in radians. Purely charm, and
# derived from _age so it plays out the same from any state. Damped hard
# enough that after ~1.5s the swing is under a pixel and the line is the
# true vertical for the rest of the turn — a plumb line that kept swinging
# would be lying about where the brick lands.
const SWING_A0 := 0.35
const SWING_HZ := 1.6
const SWING_DAMP := 2.6

# A hanging foot pulses so it is seen, not just present.
const HANG_PULSE_HZ := 2.2

# --- State ------------------------------------------------------------------

var _retired: bool = false
var _age: float = 0.0

# The scan's answer, refreshed every physics frame of the caster's piloting.
# _valid is false until the first tick after activate() (activate() runs from
# the input handler, outside the physics step, so it does not scan).
var _valid: bool = false
var _miss: bool = false # nothing under the brick at all: it descends to LOST_Y and is gone
var _landing: Vector2 = Vector2.ZERO # the brick's origin at the moment the descent would end
var _landing_rot: float = 0.0
# One entry per foot: {"a": Vector2, "b": Vector2, "ok": bool}, world space.
var _feet: Array[Dictionary] = []

# Query scratch. The mode keeps its own on the piece and reuses them per
# call; these are this effect's, so the two never trample each other's
# sizes mid-frame.
var _query: PhysicsShapeQueryParameters2D = null
var _scratch: Array[RectangleShape2D] = []
var _foot_probe: RectangleShape2D = null

# --- Hooks ------------------------------------------------------------------

func descend_speed_mult() -> float:
	return 1.0 if _retired else DESCEND_MULT

func hud_tag() -> String:
	return "PLUMB"

# --- Lifecycle --------------------------------------------------------------

func activate() -> void:
	_retired = false
	_age = 0.0
	_valid = false
	_feet = []
	if _query == null:
		_query = PhysicsShapeQueryParameters2D.new()
		_query.collision_mask = 1
		_query.collide_with_bodies = true
		_query.collide_with_areas = false
		_query.margin = 0.0
	if _foot_probe == null:
		_foot_probe = RectangleShape2D.new()

func tick(delta: float) -> void:
	if _retired or mode == null:
		return
	_age += delta
	var piece = mode.active_piece
	if mode.state != "piloting" or piece == null or not is_instance_valid(piece) or not piece.held:
		_valid = false
		return
	_scan(piece)

# Nothing was changed outside this object: no multiplier is stored on the
# mode (the hook simply stops answering once _retired), no node was added,
# and the scratch resources die with the effect. Safe from any state and
# twice in a row — a second call finds _retired already true and the caches
# already empty.
func deactivate() -> void:
	_retired = true
	_valid = false
	_feet = []

# --- The scan ---------------------------------------------------------------

# Where the descent ends, asked the way TowerMode._update_piloting asks it:
# the brick's collision boxes, trimmed by QUERY_SKIN *across* the direction
# of travel (so a face flush against a neighbour does not count — the whole
# reason that constant exists), moved straight down until the space says no.
# Only the world's bodies are queried, on layer 1; the held brick itself is
# on no layer while it is flown, so it can never block its own ghost.
func _scan(piece) -> void:
	var space: PhysicsDirectSpaceState2D = mode.get_world_2d().direct_space_state
	var rot: float = piece.rotation
	var here: Vector2 = piece.global_position
	var cell: float = float(mode.CELL)
	var lost: float = float(mode.LOST_Y)
	_size_scratch(piece, rot)

	var step: float = cell * SCAN_STEP_CELLS
	var y: float = here.y
	var hit := false
	var guard := 0
	while y < lost and guard < SCAN_GUARD:
		y += step
		if _hits(space, piece, Transform2D(rot, Vector2(here.x, y))):
			hit = true
			break
		guard += 1

	_valid = true
	_landing_rot = rot
	if not hit:
		# Steered clean off the slab: the real descent ends at LOST_Y with the
		# brick counted as fallen. The line is drawn down to there, in red.
		_miss = true
		_landing = Vector2(here.x, lost)
		_feet = []
		return
	_miss = false
	# Bisect between the last free step and the first blocked one.
	var lo: float = y - step
	var hi: float = y
	for _i in range(SCAN_REFINE):
		var mid: float = (lo + hi) * 0.5
		if _hits(space, piece, Transform2D(rot, Vector2(here.x, mid))):
			hi = mid
		else:
			lo = mid
	_landing = Vector2(here.x, lo)
	_probe_feet(space, piece, Transform2D(rot, _landing))

func _hits(space: PhysicsDirectSpaceState2D, piece, xform: Transform2D) -> bool:
	for i in range(_scratch.size()):
		_query.shape = _scratch[i]
		_query.transform = xform * piece.body_xforms[i]
		if not space.intersect_shape(_query, 1).is_empty():
			return true
	return false

# The mode's _skinned_shapes, for a downward move: the world-x axis brought
# into the brick's frame decides which local axis loses the skin. At a
# quarter turn that is an exact swap; mid-rotation it splits between them.
func _size_scratch(piece, rot: float) -> void:
	var boxes: Array = piece.boxes
	while _scratch.size() < boxes.size():
		_scratch.append(RectangleShape2D.new())
	while _scratch.size() > boxes.size():
		_scratch.pop_back()
	var skin: float = float(mode.QUERY_SKIN)
	var across: Vector2 = Transform2D(rot, Vector2.ZERO).basis_xform_inv(Vector2(1.0, 0.0)).normalized()
	var trim := Vector2(skin * absf(across.x), skin * absf(across.y))
	for i in range(boxes.size()):
		var b: Rect2 = boxes[i]
		var size_px: Vector2 = b.size * float(piece.cell)
		_scratch[i].size = Vector2(
			maxf(2.0, size_px.x - trim.x * 2.0),
			maxf(2.0, size_px.y - trim.y * 2.0)
		)

# Feet under the ghost, one per half cell of each box's world-space bottom
# edge, placed the way TowerMode._supported places its probes (against the
# world axes, not the brick's, so a turned brick still probes downward).
# A foot whose probe sits *inside* another box of the same brick — the
# underside of a T's crossbar where the stem is — is an interior face, not
# a foot, and is skipped rather than shown hanging: the held brick is on no
# collision layer, so the probe would never find the stem and would mark
# the brick's own middle as unsupported.
func _probe_feet(space: PhysicsDirectSpaceState2D, piece, xform: Transform2D) -> void:
	_feet = []
	var cell: float = float(piece.cell)
	var boxes: Array = piece.boxes
	var half := Vector2(float(piece.cols), float(piece.rows)) * cell * 0.5
	var inv: Transform2D = xform.affine_inverse()
	var c: float = absf(cos(xform.get_rotation()))
	var sn: float = absf(sin(xform.get_rotation()))
	var inset: float = float(TowerPiece.FOOT_INSET)
	var depth: float = float(TowerPiece.FOOT_DEPTH)
	for i in range(boxes.size()):
		var b: Rect2 = boxes[i]
		var size_px: Vector2 = b.size * cell
		var world_w: float = size_px.x * c + size_px.y * sn
		var world_h: float = size_px.x * sn + size_px.y * c
		var centre: Vector2 = xform * piece.body_xforms[i].origin
		var span: float = world_w - inset
		if span <= 4.0:
			continue
		var n: int = maxi(1, int(round(span / (cell * FOOT_CELLS))))
		var seg: float = span / float(n)
		var probe_y: float = centre.y + world_h * 0.5 + depth * 0.4
		var draw_y: float = centre.y + world_h * 0.5 + FOOT_DROP
		for k in range(n):
			var x0: float = centre.x - span * 0.5 + seg * float(k)
			var mid := Vector2(x0 + seg * 0.5, probe_y)
			if _inside_own_box(piece, inv * mid, half, cell, i):
				continue
			_foot_probe.size = Vector2(maxf(4.0, seg - FOOT_GAP), depth)
			_query.shape = _foot_probe
			_query.transform = Transform2D(0.0, mid)
			var ok: bool = not space.intersect_shape(_query, 1).is_empty()
			_feet.append({
				"a": Vector2(x0 + FOOT_GAP * 0.5, draw_y),
				"b": Vector2(x0 + seg - FOOT_GAP * 0.5, draw_y),
				"ok": ok,
			})

func _inside_own_box(piece, local: Vector2, half: Vector2, cell: float, skip: int) -> bool:
	var boxes: Array = piece.boxes
	for j in range(boxes.size()):
		if j == skip:
			continue
		var b: Rect2 = boxes[j]
		var r := Rect2(b.position * cell - half, b.size * cell)
		if r.has_point(local):
			return true
	return false

# --- Drawing ----------------------------------------------------------------

# Above the bricks (TowerSkillOverlay, world space): the ghost has to be
# readable *through* the tower it is about to join, and the line has to
# cross whatever is between the brick and its landing.
func draw_over(canvas: CanvasItem) -> void:
	if _retired or mode == null or not _valid:
		return
	if mode.active_slot != target or mode.state != "piloting":
		return
	var piece = mode.active_piece
	if piece == null or not is_instance_valid(piece) or not piece.held:
		return
	var px: float = 1.0 / float(mode.camera.zoom.x)
	var owner: Color = piece.owner_color
	var here: Vector2 = piece.global_position

	# The line, from the brick's centre to the bob. While the bob is still
	# swinging the line follows it; once it has settled this is the true
	# vertical, which _landing already is (the scan only ever moves in y).
	var length: float = maxf(0.0, _landing.y - here.y)
	var swing: float = SWING_A0 * exp(-SWING_DAMP * _age) * cos(SWING_HZ * TAU * _age)
	var bob: Vector2 = here + Vector2(sin(swing), cos(swing)) * length
	var line_c: Color = HANG if _miss else Color(owner.r, owner.g, owner.b, LINE_ALPHA)
	if _miss:
		_draw_dashed(canvas, here, bob, Color(RIM.r, RIM.g, RIM.b, LINE_ALPHA), (LINE_WIDTH + RIM_EXTRA) * px, 7.0 * px)
		_draw_dashed(canvas, here, bob, Color(HANG.r, HANG.g, HANG.b, LINE_ALPHA), LINE_WIDTH * px, 7.0 * px)
	elif length > 1.0:
		canvas.draw_line(here, bob, Color(RIM.r, RIM.g, RIM.b, LINE_ALPHA * 0.8), (LINE_WIDTH + RIM_EXTRA) * px)
		canvas.draw_line(here, bob, line_c, LINE_WIDTH * px)

	if not _miss:
		# The ghost: the brick's own outline at the landing transform, faintly
		# filled so it reads as a place rather than a wireframe. Fill first,
		# then every rim, then every stroke, so a rim never crosses a
		# neighbouring box's stroke.
		var xform := Transform2D(_landing_rot, _landing)
		var outlines: Array[PackedVector2Array] = piece.box_outlines(xform)
		for pts: PackedVector2Array in outlines:
			canvas.draw_colored_polygon(pts.slice(0, 4), Color(owner.r, owner.g, owner.b, GHOST_FILL_ALPHA))
		for pts: PackedVector2Array in outlines:
			canvas.draw_polyline(pts, Color(RIM.r, RIM.g, RIM.b, GHOST_LINE_ALPHA), (GHOST_WIDTH + RIM_EXTRA) * px)
		for pts: PackedVector2Array in outlines:
			canvas.draw_polyline(pts, Color(owner.r, owner.g, owner.b, GHOST_LINE_ALPHA), GHOST_WIDTH * px)
		# The feet. A standing foot is a quiet bar in the owner's colour; a
		# hanging one is red and pulses — that is the whole readout. Feet
		# above the lowest level are dimmed (see UPPER_FOOT_ALPHA).
		var lowest: float = -INF
		for f: Dictionary in _feet:
			lowest = maxf(lowest, (f["a"] as Vector2).y)
		var pulse: float = 0.6 + 0.4 * sin(_age * TAU * HANG_PULSE_HZ)
		for f: Dictionary in _feet:
			var a: Vector2 = f["a"]
			var b: Vector2 = f["b"]
			var on_floor: bool = a.y >= lowest - LOWEST_TOLERANCE
			var dim: float = 1.0 if on_floor else UPPER_FOOT_ALPHA
			canvas.draw_line(a, b, Color(RIM.r, RIM.g, RIM.b, 0.8 * dim), (FOOT_WIDTH + RIM_EXTRA) * px)
			if bool(f["ok"]):
				canvas.draw_line(a, b, Color(owner.r, owner.g, owner.b, 0.9 * dim), FOOT_WIDTH * px)
			else:
				var glow: float = (0.55 + 0.45 * pulse) if on_floor else 1.0
				canvas.draw_line(a, b, Color(HANG.r, HANG.g, HANG.b, glow * dim), FOOT_WIDTH * px)

	# The bob: a brass diamond with a dark rim, red when the line reaches
	# nothing at all.
	var s: float = BOB_SIZE * px
	var diamond := PackedVector2Array([
		bob + Vector2(0.0, -s), bob + Vector2(s * 0.6, 0.0),
		bob + Vector2(0.0, s), bob + Vector2(-s * 0.6, 0.0),
	])
	var fill: Color = HANG if _miss else BRASS
	canvas.draw_colored_polygon(diamond, fill)
	var rim := diamond.duplicate()
	rim.append(diamond[0])
	canvas.draw_polyline(rim, Color(0.10, 0.10, 0.16, 0.85), 1.5 * px)

func _draw_dashed(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color, width: float, dash: float) -> void:
	var total: float = from.distance_to(to)
	if total < 1.0:
		return
	var dir: Vector2 = (to - from) / total
	var d: float = 0.0
	while d < total:
		var e: float = minf(total, d + dash)
		canvas.draw_line(from + dir * d, from + dir * e, color, width)
		d += dash * 2.0
