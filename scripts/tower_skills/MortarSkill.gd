extends TowerSkill

## MORTAR — the tower sets solid for the rest of the caster's turn, and cures
## when that turn ends. On the next player's clock.
##
## Every landed brick is frozen where it stands, so nothing the caster lands
## on can shift, lean or topple while they are on the clock: they can put
## their brick on the very lip of an overhang that would have gone over, and
## it will not go over. That is the benefit, and it is real — but it is only
## half of the skill. The freeze is lifted in deactivate(), which for a skill
## that ran its turn out is inside TowerMode._resolve_turn(), after the
## caster's falls have been counted and before the next player's brick
## spawns. The tower then resumes with every load the caster put on it
## applied at once, and the fault rule scores whatever moves against whoever
## is on the clock next. A player who drops a brick on the edge under mortar
## is handing the collapse to the next chair. The blurb says so, in as many
## words, because a skill whose sting arrives a turn later with no warning
## would read as the game cheating rather than as a player being clever.
##
## Mechanically it is `freeze = true` on each brick, and nothing else. The
## bricks keep the FREEZE_MODE_KINEMATIC TowerPiece.set_held() left them
## with, which makes a frozen brick an infinite-mass body the caster's brick
## rests on exactly as it would rest on the platform; the landing query in
## TowerMode._blocked() sees it because it is still in the collision world.
## Velocities are zeroed first — the tower is at rest when a turn begins, so
## nothing is lost, and TowerMode._everything_at_rest() then reads the frozen
## bricks as still rather than as a stale wobble.
##
## What is put back: exactly the bricks this instance froze, and only those
## that were not frozen already (so two effects that both freeze can never
## thaw each other's), and only if they still exist — a restart frees the
## whole tower before it asks the skill to stand down. Unfreezing sets the
## body active again, and `sleeping = false` is written too so a brick whose
## support the caster's own placement changed re-checks it rather than
## hanging on a stale sleep. deactivate() empties its list as it goes, which
## is what makes a second call a no-op.

# --- Tuning ----------------------------------------------------------------

# The set: a bright line sweeps up the tower from the platform over this
# long, and each brick turns to stone as it passes. Short, because the freeze
# is already in force from the first frame and the sweep is only reporting
# it — a slow one would suggest the lower bricks set before the upper ones.
const SET_TIME := 0.55
# Cracks spread across the stone from the moment the caster's brick lands.
# They are the telegraph for the thaw: deactivate() cannot draw, and the end
# of a self skill's turn is not on a timer, so "the mortar is about to give"
# has to be shown from the one event that always precedes it.
const CRACK_TIME := 0.9
const CRACKS_PER_BRICK := 2
const CRACK_SEGMENTS := 4
# Stone, over the bricks' own art. Cool grey so it reads as set concrete
# against the warm pixel-art sky, opaque enough to say "not a brick any
# more" while the shape underneath still shows through.
const STONE_FILL := Color(0.58, 0.60, 0.66, 0.46)
const STONE_LINE := Color(0.90, 0.91, 0.94, 0.85)
const STONE_WIDTH := 2.0
const SWEEP_COLOR := Color(0.97, 0.98, 1.0, 0.9)
const SWEEP_WIDTH := 3.0
const CRACK_COLOR := Color(0.13, 0.13, 0.17, 0.85)
const CRACK_WIDTH := 1.6
const SHIMMER_HZ := 0.7
const UNDERLINE := Color(0.06, 0.08, 0.20, 0.55)

# --- State -----------------------------------------------------------------

# The bricks this instance froze, untyped (PROJECT_STATE §12: a freed node is
# only safely inspectable through an untyped reference). Emptied by
# deactivate().
var _frozen: Array = []
# Per frozen brick, CRACKS_PER_BRICK polylines in the brick's own local
# space, generated once at activate() from a seeded RNG so they are the same
# every frame. Parallel to _frozen.
var _cracks: Array = []
var _t := 0.0
var _crack_t := 0.0
# The stack top at the moment of the set, for the sweep's end point.
var _set_top := 0.0

# --- Lifecycle -------------------------------------------------------------

func activate() -> void:
	_t = 0.0
	_crack_t = 0.0
	_frozen = []
	_cracks = []
	_set_top = float(mode.stack_top_y)
	var ap = mode.active_piece
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id) + caster * 7919
	for c in mode.pieces.get_children():
		var p := c as TowerPiece
		if p == null or p.held or p.doomed or p == ap or p.freeze:
			continue
		p.linear_velocity = Vector2.ZERO
		p.angular_velocity = 0.0
		p.freeze = true
		_frozen.append(p)
		_cracks.append(_make_cracks(p, rng))

func tick(delta: float) -> void:
	_t += delta
	if mode.state != "piloting":
		_crack_t += delta

# The cure, announced. This runs inside TowerMode._resolve_turn() with the
# effect still live — after the caster's own falls were counted, just before
# deactivate() lifts the freeze — so the toast is on screen through the
# resolve pause and into the next player's turn, which is when the tower
# moves. A collapse that arrives with no caption reads as the game glitching;
# with one it reads as what it is. A life-loss toast from the same resolve
# is left alone: it is the more important of the two.
func on_turn_end() -> void:
	if int(mode.fallen_this_turn) > 0:
		return
	var who: String = GameSettings.PLAYER_CONFIGS[caster]["name"]
	var c: Color = mode._slot_color(caster)
	mode.hud.show_message("%s's MORTAR CURES — THE TOWER IS LOOSE" % who, Color(c.r, c.g, c.b, 1.0))

func deactivate() -> void:
	for c in _frozen:
		if not is_instance_valid(c):
			continue
		var p := c as TowerPiece
		if p == null:
			continue
		p.freeze = false
		p.sleeping = false
	_frozen = []
	_cracks = []

func hud_tag() -> String:
	return "MORTARED"

# --- Cracks ----------------------------------------------------------------

# A few jagged polylines in the brick's local frame, each starting inside one
# of its collision boxes and wandering CRACK_SEGMENTS steps of about a third
# of a cell. Local space, so they ride the brick if it is ever moved.
func _make_cracks(p: TowerPiece, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var half := Vector2(float(p.cols), float(p.rows)) * p.cell * 0.5
	for _i in range(CRACKS_PER_BRICK):
		var b: Rect2 = p.boxes[rng.randi() % p.boxes.size()]
		var start: Vector2 = (b.position + Vector2(rng.randf(), rng.randf()) * b.size) * p.cell - half
		var angle: float = rng.randf() * TAU
		var pts := PackedVector2Array([start])
		var at: Vector2 = start
		for _s in range(CRACK_SEGMENTS):
			angle += rng.randf_range(-1.1, 1.1)
			at += Vector2.from_angle(angle) * p.cell * rng.randf_range(0.22, 0.4)
			pts.append(at)
		out.append(pts)
	return out

# --- Drawing ---------------------------------------------------------------

func _px(width: float) -> float:
	return width / float(mode.cam_zoom)

# Above the bricks: the stone wash, the set line, and the cracks.
func draw_over(canvas: CanvasItem) -> void:
	if mode.active_slot != target:
		return
	var cell: float = mode.CELL
	var set_u: float = clampf(_t / SET_TIME, 0.0, 1.0)
	# The sweep rises from the platform's surface to just over the stack top.
	# -y is up, so lerping toward a more negative y is climbing.
	var sweep_y: float = lerpf(0.0, _set_top - cell, set_u)
	var shimmer: float = 0.92 + 0.08 * sin(_t * TAU * SHIMMER_HZ)
	var crack_u: float = clampf(_crack_t / CRACK_TIME, 0.0, 1.0)

	for i in range(_frozen.size()):
		var c = _frozen[i]
		if not is_instance_valid(c):
			continue
		var p := c as TowerPiece
		if p == null:
			continue
		var xf: Transform2D = p.global_transform
		# A brick sets as the line passes its centre.
		if xf.origin.y < sweep_y:
			continue
		var fill := Color(STONE_FILL.r, STONE_FILL.g, STONE_FILL.b, STONE_FILL.a * shimmer)
		for pts: PackedVector2Array in p.box_outlines(xf):
			canvas.draw_colored_polygon(pts.slice(0, 4), fill)
			canvas.draw_polyline(pts, UNDERLINE, _px(STONE_WIDTH + 2.0))
			canvas.draw_polyline(pts, STONE_LINE, _px(STONE_WIDTH))
		if crack_u > 0.0 and i < _cracks.size():
			_draw_cracks(canvas, xf, _cracks[i], crack_u)

	if set_u < 1.0:
		# The set line, the width of the play column, with a soft band under
		# it so it reads as a wave passing rather than a ruled line.
		var reach: float = (float(mode.PLATFORM_CELLS) * 0.5 + float(mode.AIM_BOUND_CELLS)) * cell
		canvas.draw_rect(Rect2(-reach, sweep_y, reach * 2.0, cell * 0.6), Color(SWEEP_COLOR.r, SWEEP_COLOR.g, SWEEP_COLOR.b, 0.18), true)
		canvas.draw_line(Vector2(-reach, sweep_y), Vector2(reach, sweep_y), UNDERLINE, _px(SWEEP_WIDTH + 2.0))
		canvas.draw_line(Vector2(-reach, sweep_y), Vector2(reach, sweep_y), SWEEP_COLOR, _px(SWEEP_WIDTH))

# Each crack grows segment by segment with `u`, the last one partial.
func _draw_cracks(canvas: CanvasItem, xf: Transform2D, cracks: Array, u: float) -> void:
	for local: PackedVector2Array in cracks:
		var segs: int = local.size() - 1
		var grown: float = u * float(segs)
		var whole: int = int(floor(grown))
		var pts := PackedVector2Array()
		for k in range(mini(whole, segs) + 1):
			pts.append(xf * local[k])
		if whole < segs:
			pts.append(xf * local[whole].lerp(local[whole + 1], grown - float(whole)))
		if pts.size() >= 2:
			canvas.draw_polyline(pts, CRACK_COLOR, _px(CRACK_WIDTH))
