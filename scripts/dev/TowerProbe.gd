extends Node

## DEV ONLY — not part of the game. Nothing in the scene flow references it.
##
## Plays whole Pile Up matches headlessly, steering each brick to a seeded
## random position and rotation and then letting it descend on its own, and
## reports what the physics and the turn loop actually did. Run it after
## touching TowerMode's descent/settle logic, the kill planes, TowerPiece's
## physics setup, or the tetromino table:
##
##   godot --headless --fixed-fps 240 res://scenes/dev/TowerProbe.tscn
##
## `-- --spread=N` sets how much of the legal aim range a brick may be sent
## to. 1.0 is maximally sloppy — uniformly random across everything the
## clamp allows, including hanging a brick two cells past the platform edge
## on purpose. Nobody plays like that, so pass a smaller number to model a
## player who is actually trying:
##
##   godot --headless --fixed-fps 240 res://scenes/dev/TowerProbe.tscn -- --spread=0.3
##
## The two ends answer different questions. Spread 1.0 asks "does the turn
## loop survive nonsense" and 0.0-0.3 asks "does careful play actually build
## a tower". **Run both — the signal is the difference between them.** That
## comparison is what caught the drop-speed bug in PROJECT_STATE §5 session
## S: careful play was losing bricks at the same rate as terrible play,
## which no single run could have shown.
##
## What it is for is the three failures a compile check cannot see and a
## single playtest is unlikely to hit:
##
##  1. **A turn that never ends.** The turn boundary is "everything stopped
##     moving", which is a claim about a physics solver, not about code. A
##     tower that finds a slow perpetual wobble would hang the match on a
##     player's screen with no way out. SETTLE_TIMEOUT is the backstop, so
##     the number that matters here is how often it has to fire: often means
##     the thresholds are wrong, never-in-many-matches means they are sane.
##
##  2. **A match that never ends.** Lives only come off when a brick falls;
##     if bricks stop falling (say the aim clamp gets tightened past the
##     point where a bad drop is possible) a match runs forever.
##
##  3. **Bricks leaving through the floor.** A brick that tunnels through the
##     platform reads to a player exactly like one they knocked off, and
##     costs them a life either way — so it cannot be told apart from real
##     play. Here it can. See _physics_process for why the obvious version
##     of this test reports bugs that are not there.
##
## Note what it does NOT do. It sets the commanded position directly instead
## of pressing keys, so it exercises the collision-checked follow and the
## descent but says nothing about the feel of the half-cell step, the dash
## or the soft drop. And it says nothing at all about whether the mode is
## fun — same standing caveat as every other probe in this folder
## (docs/PROJECT_STATE.md §7).

const TOWER_SCENE := preload("res://scenes/TowerMode.tscn")

const SEEDS := 12
const PLAYER_COUNT := 4
const MAX_TURNS_PER_MATCH := 400 # a match that needs more than this is the bug, not a slow game
const DEFAULT_AIM_SPREAD := 1.0

var _rng := RandomNumberGenerator.new()
# Deliberately untyped: TowerMode declares no class_name, so naming a type
# here would turn every `_mode.SETTLE_TIMEOUT` into a parse error. Same
# reasoning as BotDriver.board — see PROJECT_STATE §7.
var _mode = null
var _seed_index: int = 0
var _aim_spread := DEFAULT_AIM_SPREAD

var _piloted_piece = null # the brick this turn's aim has already been set for
var _pending_height := 0
var _watching := false

var _turns := 0
var _last_fall_timer := 0.0
var _settle_timeouts := 0
var _falls := 0
var _lives_lost := 0
var _tallest := 0

var _rows: Array[String] = []
var _total_turns := 0
var _total_falls := 0
var _total_timeouts := 0
var _unfinished := 0
var _low_falls := 0
var _tunnels := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--spread="):
			_aim_spread = float(str(arg).split("=")[1])
	GameSettings.mode = GameSettings.MODE_TOWER
	GameSettings.player_count = PLAYER_COUNT
	var colors: Array[Color] = []
	for i in range(PLAYER_COUNT):
		colors.append(GameSettings.PLAYER_SKINS[i]["color"])
	GameSettings.skin_colors = colors
	print("TowerProbe — %d matches, %d players each, aim spread %.2f\n" % [SEEDS, PLAYER_COUNT, _aim_spread])
	_start_seed()

func _start_seed() -> void:
	if _mode != null:
		_mode.queue_free()
	# TowerMode picks its bricks with the global randi(), so the piece
	# sequence has to be seeded too or a "seed" reproduces only the aim and
	# runs disagree with each other (see LandingProbe's _ready).
	seed(90210 + _seed_index * 7919)
	_rng.seed = 90210 + _seed_index * 7919
	_turns = 0
	_falls = 0
	_settle_timeouts = 0
	_lives_lost = 0
	_tallest = 0
	_last_fall_timer = 0.0
	_piloted_piece = null
	_watching = false
	_mode = TOWER_SCENE.instantiate()
	add_child(_mode)

func _process(_delta: float) -> void:
	if _mode == null:
		return
	var state: String = _mode.state

	if state == "settling":
		_last_fall_timer = _mode.fall_timer
	elif state == "resolving" and _watching:
		if _last_fall_timer >= _mode.SETTLE_TIMEOUT - 0.05:
			_settle_timeouts += 1
		_tallest = max(_tallest, _mode.best_height)

	if state == "piloting":
		_take_turn()
	elif state == "gameover":
		_finish_seed(true)
	elif _turns >= MAX_TURNS_PER_MATCH:
		_finish_seed(false)

# Sets the commanded position once per brick and then leaves it alone — the
# brick descends by itself, which is the behaviour under test.
func _take_turn() -> void:
	var piece: TowerPiece = _mode.active_piece
	if piece == null or piece == _piloted_piece:
		return
	_piloted_piece = piece

	_mode.aim_steps = _rng.randi_range(0, 3)
	var limit: float = maxf(0.0,
		_mode.PLATFORM_CELLS * _mode.CELL * 0.5
		+ _mode.AIM_BOUND_CELLS * _mode.CELL
		- piece.aim_half_width(_mode.aim_steps))
	_mode.aim_x = _rng.randf_range(-limit, limit) * _aim_spread

	_pending_height = _mode.best_height
	_turns += 1

func _physics_process(_d: float) -> void:
	if _mode == null:
		return
	# Sampled every physics frame rather than at cull time: by the time a
	# brick is culled it has been freed, and its trajectory is the only thing
	# that says how it got past the slab.
	#
	# The test is "how far out did it ever get". The slab is solid from -w to
	# +w, so a brick can only reach the void below it by taking its centre
	# past that edge first — a brick tipping over the lip carries its centre
	# outward as it goes. A brick that is now well below the slab and whose
	# centre never once reached the edge did not go round it.
	#
	# The naive version of this check ("it is below the slab and inside the
	# footprint now") is not the same thing and reports false positives: a
	# brick that legitimately fell off the edge can be knocked back inward by
	# the next one on its way down, and lands in exactly that state.
	var half_w: float = _mode.PLATFORM_CELLS * _mode.CELL * 0.5
	for c in _mode.pieces.get_children():
		var p := c as TowerPiece
		if p == null or p.held:
			continue
		var pos: Vector2 = p.global_position
		var reach: float = maxf(p.get_meta("probe_max_x", 0.0), absf(pos.x))
		p.set_meta("probe_max_x", reach)
		if pos.y > _mode.LOST_Y and reach < half_w:
			if not p.has_meta("probe_tunnelled"):
				p.set_meta("probe_tunnelled", true)
				_tunnels += 1

	if _mode.state == "settling":
		_watching = true
		return
	if not _watching:
		return
	_watching = false
	var fell: int = _mode.fallen_this_turn
	if fell > 0:
		_falls += fell
		_lives_lost += 1
		if _pending_height <= 1:
			_low_falls += 1

func _finish_seed(ended: bool) -> void:
	var lives_text: String = ""
	for l in _mode.lives:
		lives_text += "%d" % l
	_rows.append("  seed %2d   %s  turns %3d   bricks lost %2d   lives lost %2d   tallest %2d   settle-timeouts %d   lives[%s]"
		% [_seed_index, "ended " if ended else "HUNG  ", _turns, _falls, _lives_lost, _tallest, _settle_timeouts, lives_text])
	_total_turns += _turns
	_total_falls += _falls
	_total_timeouts += _settle_timeouts
	if not ended:
		_unfinished += 1

	_seed_index += 1
	if _seed_index >= SEEDS:
		_report()
		get_tree().quit()
		return
	_start_seed()

func _report() -> void:
	for r in _rows:
		print(r)
	print("")
	print("matches that reached a winner : %d / %d" % [SEEDS - _unfinished, SEEDS])
	print("turns per match (mean)        : %.1f" % (float(_total_turns) / float(SEEDS)))
	print("bricks lost per match (mean)  : %.1f" % (float(_total_falls) / float(SEEDS)))
	print("settle timeouts (total)       : %d over %d turns" % [_total_timeouts, _total_turns])
	print("falls off a <=1-brick tower   : %d   (fair if the brick was steered off the edge)" % _low_falls)
	print("bricks that went THROUGH slab : %d   (any nonzero is a bug — see header, item 3)" % _tunnels)
	print("")
	if _tunnels > 0:
		print("FAIL: %d brick(s) passed through the platform." % _tunnels)
	elif _unfinished > 0:
		print("FAIL: %d match(es) hit the turn cap without ending." % _unfinished)
	elif _total_timeouts * 10 > _total_turns:
		print("WARN: settle timeout fired on >10%% of turns — SETTLE_* thresholds look wrong.")
	else:
		print("OK: every match terminated and settling resolved on its own.")
