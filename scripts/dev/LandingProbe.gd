extends Node

## DEV ONLY — not part of the game. Nothing in the scene flow references it.
##
##   godot --headless --fixed-fps 240 res://scenes/dev/LandingProbe.tscn
##
## Measures the one thing a player notices immediately and no compile check
## can see: **at the moment the player stops being able to steer a brick, is
## there actually anything underneath it?**
##
## It exists because of a bug where there often was not. Descent was refused
## by a single question — "can the brick be in the space one step lower?" —
## and that question is also answered "no" when the brick has come up against
## the *flank* of a taller stack. So a brick sliding down beside a tower went
## limp in mid-air with a visible void under it, reported as "player looses
## control of the brick before it touches other bricks". Blocked and landed
## are different events; TowerPiece.foot_shapes is what tells them apart.
##
## Two traps in measuring this, both of which produced confident wrong
## numbers before the real one:
##
##  1. **Do not measure after the brick is released.** By then physics has
##     moved it, and the brick is back in the collision world — re-running
##     the landing query at that point reports the brick colliding with
##     itself. The first version of this probe did exactly that and blamed
##     the tower for a 42px mean gap that was entirely its own artifact.
##
##  2. **Do not measure the blocker.** The gap that matters is to the nearest
##     surface *beneath the brick's own x-span*, which is usually not the
##     thing that refused the move — when a brick is wedged, the blocker is
##     beside it and what is below is something else entirely.
##
## This probe runs before TowerMode each physics frame (parent before child),
## so it caches the brick's live held geometry every frame and reports the
## cached values on the frame control ends.

const TOWER := preload("res://scenes/TowerMode.tscn")

const TURNS := 16
const MEAN_LIMIT := 2.0 # px; a landing should be within a descent step of contact
const WORST_LIMIT := 8.0
# Wedged landings are excluded from those limits, because being unsupported
# is the whole definition of that path — see _report().
const MAX_WEDGE_FRACTION := 0.5

var _mode = null # untyped: TowerMode has no class_name (see TowerProbe's header)
var _rng := RandomNumberGenerator.new()
var _piloted = null
var _turns := 0
var _gaps: Array[float] = [] # supported landings only
var _worst := 0.0
var _wedge_landings := 0
var _wedge_worst := 0.0
var _touching_nothing := 0
var _missed := 0 # steered off the platform entirely — nothing to touch, correctly
var _side_only_early := 0 # ended on a flank WITHOUT the backstop expiring — the bug
var _pushing := false
var _push_dir := 1.0
var _cached: Dictionary = {}

func _ready() -> void:
	# TowerMode picks its bricks with the *global* randi(), so seeding only
	# _rng would leave the piece sequence free-running and two "identical"
	# runs would disagree. A probe you cannot reproduce cannot tell a
	# regression from variance — this one reported a 0.45px mean and a 7.52px
	# mean on consecutive runs before this line existed.
	seed(20260825)
	_rng.seed = 4242
	GameSettings.mode = GameSettings.MODE_TOWER
	GameSettings.player_count = 2
	var cols: Array[Color] = [Color.RED, Color.BLUE]
	GameSettings.skin_colors = cols
	_mode = TOWER.instantiate()
	add_child(_mode)

func _bounds_of(p, xform: Transform2D) -> Dictionary:
	var minx := INF
	var maxx := -INF
	var miny := INF
	var maxy := -INF
	for loop in p.box_outlines(xform):
		for v: Vector2 in loop:
			minx = minf(minx, v.x)
			maxx = maxf(maxx, v.x)
			miny = minf(miny, v.y)
			maxy = maxf(maxy, v.y)
	return {"minx": minx, "maxx": maxx, "miny": miny, "maxy": maxy}

func _physics_process(_delta: float) -> void:
	if _mode == null:
		return
	if _mode.state == "gameover" or _turns > TURNS:
		_report()
		return

	if _mode.state == "piloting" and _mode.active_piece != null:
		var p = _mode.active_piece
		if p != _piloted:
			_piloted = p
			# Aimed near the edges on purpose: hugging the stack is where a
			# brick ends up flush against something taller, which is the case
			# this probe exists for.
			_mode.aim_steps = _rng.randi_range(0, 3)
			# Every other turn is a "pusher": the command is pinned hard to
			# one side for the whole descent, modelling a player leaning on a
			# direction. Without it the probe never presses a brick against a
			# flank, and the wedge path — the only route left by which control
			# can end with nothing underneath — is never exercised at all.
			_pushing = (_turns % 2) == 1
			_push_dir = 1.0 if _rng.randf() < 0.5 else -1.0
			_mode.aim_x = (_push_dir * 9999.0) if _pushing else _rng.randf_range(-1.0, 1.0) * _mode.CELL * 1.6
			_turns += 1
			return
		if _pushing:
			_mode.aim_x = _push_dir * 9999.0 # keep leaning on it every frame
		_cached = _measure(p)
		return

	if _mode.state == "settling" and _piloted != null:
		_piloted = null
		if _cached.has("gap"):
			var backstopped: bool = _cached["wedge"] >= _mode.WEDGE_GRACE - 0.05
			if _cached["lost"]:
				_missed += 1
			elif not _cached["below"] and not _cached["side"]:
				_touching_nothing += 1
			elif not _cached["below"] and not backstopped:
				# Touching only a flank, and the backstop had not expired — so
				# the turn was ended at contact rather than at support. This
				# is the defect the probe exists for.
				_side_only_early += 1
			var g: float = maxf(0.0, _cached["gap"])
			# Two different populations, and averaging them together is
			# meaningless. A *supported* landing ended because something was
			# under the brick, and its gap should be within a descent step.
			# A *wedged* landing ended because WEDGE_GRACE ran out with the
			# brick held against a flank — unsupported by definition, so its
			# gap says nothing about the bug this probe guards. Only a timer
			# that actually ran out counts as wedged; brushing a flank for a
			# frame on the way down is ordinary and resolves itself.
			if _cached["wedge"] >= _mode.WEDGE_GRACE - 0.05:
				_wedge_landings += 1
				_wedge_worst = maxf(_wedge_worst, g)
			else:
				_gaps.append(g)
				_worst = maxf(_worst, g)
		_cached = {}

# The gap under the *nearest-supported part* of the brick, not under its
# lowest point.
#
# That distinction is the whole measurement. Most tetrominoes decompose into
# boxes at two different depths — J, T, S and Z all have one box a cell lower
# than the other — so a brick can legitimately come to rest on its shallower
# box with a cell of air under the deeper one. Measuring only the lowest
# point calls that a 38px failure when it is an ordinary, correct landing.
#
# Deliberately computed from bounds arithmetic rather than by asking
# TowerMode._supported(): a probe that checks an implementation by calling
# that same implementation proves nothing.
func _measure(p) -> Dictionary:
	var xform := Transform2D(p.rotation, p.global_position)
	var hw: float = _mode.PLATFORM_CELLS * _mode.CELL * 0.5
	var best := INF

	for loop in p.box_outlines(xform):
		var minx := INF
		var maxx := -INF
		var maxy := -INF
		for v: Vector2 in loop:
			minx = minf(minx, v.x)
			maxx = maxf(maxx, v.x)
			maxy = maxf(maxy, v.y)

		var surface := INF
		if maxx > -hw and minx < hw:
			surface = 0.0
		for c in _mode.pieces.get_children():
			if c == p or c.held or c.doomed:
				continue
			var o: Dictionary = _bounds_of(c, c.global_transform)
			if o["maxx"] <= minx + 1.0 or o["minx"] >= maxx - 1.0:
				continue
			if o["miny"] < maxy - 1.0:
				continue # its top is above this box's underside: a flank, not a floor
			surface = minf(surface, o["miny"])
		if surface < INF:
			best = minf(best, surface - maxy)

	# The player's own rule, tested literally: is the brick in contact with
	# anything at all right now — below it or beside it?
	#
	# Asked of the brick's real collision boxes rather than through _blocked(),
	# which trims them by QUERY_SKIN so that grazing the tower is not treated
	# as being inside it. That tolerance is right for deciding whether a move
	# is legal and wrong for this question: "is it touching" means touching.
	var touching_below: bool = _touching(p, Vector2(0.0, 2.0))
	var touching_side: bool = _touching(p, Vector2(2.0, 0.0)) or _touching(p, Vector2(-2.0, 0.0))
	return {
		"gap": best if best < INF else 0.0,
		"wedge": _mode.wedge_timer,
		"below": touching_below,
		"side": touching_side,
		# Steered clean off the platform: it has missed everything and is
		# falling into open sky. Control ends with nothing touched, and that
		# is correct — there is nothing left for it to touch.
		# One frame of lookahead: this probe samples before TowerMode moves the
		# brick, so the crossing itself happens on the frame after the last
		# one cached here.
		"lost": p.global_position.y + 4.0 > _mode.LOST_Y,
	}

func _touching(p, offset: Vector2) -> bool:
	return _mode._query_hits(
		p.body_shapes, p.body_xforms, Transform2D(p.rotation, p.global_position + offset)
	)

func _report() -> void:
	var mean := 0.0
	for g in _gaps:
		mean += g
	mean /= maxf(1.0, float(_gaps.size()))
	var total: int = _gaps.size() + _wedge_landings
	var wedge_frac: float = float(_wedge_landings) / maxf(1.0, float(total))

	print("LandingProbe — %d landings (%d supported, %d wedged)\n" % [total, _gaps.size(), _wedge_landings])
	print("  supported landings — gap under the brick when control ended")
	print("    mean  %6.2f px" % mean)
	print("    worst %6.2f px  (%.2f cells)" % [_worst, _worst / float(_mode.CELL)])
	print("  one descent step        : %.2f px" % (_mode.DESCEND_SPEED / 60.0))
	print("  wedged landings         : %d of %d (%.0f%%), worst gap %.1f px" % [
		_wedge_landings, total, wedge_frac * 100.0, _wedge_worst])
	print("  steered off the platform (no landing)    : %d  (correct — nothing to touch)" % _missed)
	print("  control ended while touching NOTHING     : %d" % _touching_nothing)
	print("  control ended on a FLANK before backstop : %d" % _side_only_early)
	print("    (The anti-deadlock backstop expired with the brick held against")
	print("     a flank. This probe leans on a direction and never backs off, so")
	print("     it reaches the backstop where a player would simply steer away.)")
	print("")
	if _touching_nothing > 0:
		print("FAIL: %d turn(s) ended with the brick touching nothing at all." % _touching_nothing)
	elif _side_only_early > 0:
		print("FAIL: %d turn(s) ended on a flank before the backstop — control taken at contact, not at support." % _side_only_early)
	elif _gaps.is_empty():
		print("FAIL: no supported landings measured.")
	elif mean > MEAN_LIMIT or _worst > WORST_LIMIT:
		print("FAIL: control is ending before the brick is supported — see this file's header.")
	elif wedge_frac > MAX_WEDGE_FRACTION:
		print("WARN: %.0f%% of landings timed out wedged — the descent may be too easy to jam." % (wedge_frac * 100.0))
	else:
		print("OK: control ends within a descent step of real support.")
	get_tree().quit()
