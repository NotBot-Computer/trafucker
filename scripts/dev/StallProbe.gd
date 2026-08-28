extends Node

## DEV ONLY — not part of the game. Nothing in the scene flow references it.
##
##   godot --headless --fixed-fps 240 res://scenes/dev/StallProbe.tscn
##
## Asks one question the other tower probes cannot: **does a brick ever stop
## descending in mid-air, part way down, and stay stopped?**
##
## LandingProbe only ever looks at the frame control *ends*, so a brick that
## hangs for a second half way down and then carries on is invisible to it —
## the landing it eventually makes is perfectly good. That is exactly the
## shape of the bug reported from play ("bricks stop when they cross a line
## and I need to move right or left to continue"), so it needed its own
## measurement.
##
## The other reason the existing probes miss it is that they aim with
## `randf()`. The real game moves in half cells from x=0, so a brick's faces
## land *exactly* flush with the faces of the bricks already stacked — and
## Godot's intersect_shape counts two exactly-touching rectangles as a hit.
## A continuous random aim practically never reproduces that; a player
## reproduces it constantly. So this probe steers the way the keyboard does,
## through _press_steer(), and only ever commands lattice positions.

const TOWER := preload("res://scenes/TowerMode.tscn")

const TURNS := 60
# A brick descends at DESCEND_SPEED, so "not moving" is measured against what
# one frame of that ought to cover rather than against zero.
const MOVE_EPSILON := 0.05
# How long a brick may sit still before it counts as a stall rather than a
# frame of jitter. A quarter second is already visible to a player.
const STALL_REPORT := 0.25
# A stall with something under the brick is a landing that has not been
# declared yet; a stall with air under it is the bug.
const AIR_GAP := 4.0

var _mode = null # untyped: TowerMode has no class_name (see TowerProbe's header)
var _rng := RandomNumberGenerator.new()
var _piloted = null
var _turns := 0
var _prev_y := 0.0
var _stall := 0.0
var _target_x := 0.0

var _air_stalls := 0 # stalls in mid-air — the defect
var _air_worst := 0.0 # longest such stall, seconds
var _air_worst_gap := 0.0 # how much clear air was under the brick during it
var _rest_stalls := 0 # stalls with something genuinely underneath
var _turns_with_air_stall := 0
var _flagged_this_turn := false

func _ready() -> void:
	# TowerMode draws its pieces from the global randi(); see LandingProbe.
	seed(20260828)
	_rng.seed = 90210
	GameSettings.mode = GameSettings.MODE_TOWER
	# Four players, because lives are what bound the match and this probe
	# needs a tower tall enough to have flanks to fall past.
	GameSettings.player_count = 4
	var cols: Array[Color] = [Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW]
	GameSettings.skin_colors = cols
	_mode = TOWER.instantiate()
	add_child(_mode)

func _physics_process(delta: float) -> void:
	if _mode == null:
		return
	if _mode.state == "gameover" or _turns > TURNS:
		_report()
		return
	if _mode.state != "piloting" or _mode.active_piece == null:
		_piloted = null
		return

	var p = _mode.active_piece
	if p != _piloted:
		_piloted = p
		_turns += 1
		# Lives topped up so the match cannot end early. This probe is
		# measuring the descent, not the scoring, and a tower needs to get
		# tall before it has flanks worth falling past — a 2-player match
		# eliminates everyone at about thirteen turns, well before the
		# interesting geometry exists.
		for i in range(_mode.lives.size()):
			_mode.lives[i] = 3
		_stall = 0.0
		_flagged_this_turn = false
		_prev_y = p.global_position.y
		_mode.aim_steps = _rng.randi_range(0, 3)
		# A lattice column, chosen so bricks routinely come down flush against
		# what is already stacked — that is the case under test, and aiming at
		# a random real number would step around it.
		_target_x = float(_rng.randi_range(-4, 4)) * _mode.CELL * _mode.STEP_CELLS
		return

	# Steer with the keyboard's own entry point, one press per frame, so the
	# commanded position is only ever a multiple of half a cell.
	var diff: float = _target_x - _mode.aim_x
	if absf(diff) >= _mode.CELL * _mode.STEP_CELLS - 0.01:
		_mode._press_steer(1 if diff > 0.0 else -1)

	var y: float = p.global_position.y
	if y - _prev_y < MOVE_EPSILON:
		_stall += delta
		if _stall >= STALL_REPORT:
			var gap: float = _gap_under(p)
			if gap > AIR_GAP:
				# Counted once per turn, but measured every frame it lasts:
				# this probe keeps steering toward its target column, and
				# steering is exactly what shakes a brick loose again — so
				# taking the duration at the moment of the first flag would
				# report the probe's own reflexes rather than how long the
				# brick would have hung there.
				if not _flagged_this_turn:
					_air_stalls += 1
					_turns_with_air_stall += 1
					_flagged_this_turn = true
				if _stall > _air_worst:
					_air_worst = _stall
					_air_worst_gap = gap
			elif not _flagged_this_turn:
				_rest_stalls += 1
				_flagged_this_turn = true
	else:
		_stall = 0.0
	_prev_y = y

# Clear air beneath the brick, measured from bounds arithmetic rather than by
# asking TowerMode._supported() — a probe that checks an implementation by
# calling that same implementation proves nothing. Same rule as LandingProbe:
# per collision box, and ignoring anything whose top is above that box's
# underside, because that is a flank and not a floor.
func _gap_under(p) -> float:
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
			var o := _bounds_of(c)
			if o["maxx"] <= minx + 1.0 or o["minx"] >= maxx - 1.0:
				continue
			if o["miny"] < maxy - 1.0:
				continue
			surface = minf(surface, o["miny"])
		if surface < INF:
			best = minf(best, surface - maxy)
	return 0.0 if best == INF else maxf(0.0, best)

func _bounds_of(p) -> Dictionary:
	var minx := INF
	var maxx := -INF
	var miny := INF
	var maxy := -INF
	for loop in p.box_outlines(p.global_transform):
		for v: Vector2 in loop:
			minx = minf(minx, v.x)
			maxx = maxf(maxx, v.x)
			miny = minf(miny, v.y)
			maxy = maxf(maxy, v.y)
	return {"minx": minx, "maxx": maxx, "miny": miny, "maxy": maxy}

func _report() -> void:
	print("StallProbe — %d turns steered on the half-cell lattice\n" % _turns)
	print("  turns where the brick hung in MID-AIR >= %.2fs : %d" % [STALL_REPORT, _turns_with_air_stall])
	print("    longest such stall : %.2f s, with %.1f px (%.2f cells) of air under it" % [
		_air_worst, _air_worst_gap, _air_worst_gap / float(_mode.CELL)])
	print("  turns that paused with something underneath    : %d  (a landing about to be declared)" % _rest_stalls)
	print("")
	if _air_stalls > 0:
		print("FAIL: a brick stopped descending with nothing under it — the player has to")
		print("      steer sideways to get it moving again. See this file's header.")
	else:
		print("OK: no brick stopped descending in clear air.")
	get_tree().quit()
