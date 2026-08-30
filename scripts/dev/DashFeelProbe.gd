extends Node

## DEV ONLY — not part of the game. Nothing in the scene flow references it.
##
##   godot --headless --fixed-fps 60 res://scenes/dev/DashFeelProbe.tscn
##
## Presses real keys and measures how fast and how far the brick actually
## moves. DashProbe next door answers a different question and cannot answer
## this one: it calls `_press_dash()` and samples `dash_active` on the same
## frame, so it reports the dash's *intent* — the flag, the constant that
## would be used, the trail timer — and never lets `_update_piloting()` run.
## Everything that happens to a dash after the button goes down is invisible
## to it. This probe drives `Input.parse_input_event()` instead, so the whole
## keyboard path runs, and records the brick's per-frame lateral movement.
##
## Two bugs came out of that gap, both in code that reads correctly:
##
## 1. **The hold-repeat cancelled dashes in flight.** Every repeat tick
##    cleared `dash_active`, and the repeat runs before the follow in the
##    same frame. A dash needs about two frames and a tick lands every five,
##    so a dash pressed at the wrong moment lost some or all of its fast
##    frames. Measured across the six phases of one repeat tick, one of them
##    covered the whole cell at 620px/s — peak speed identical to simply
##    holding the key. That is the §7 invariant failing outright: the dash's
##    distance is deliberately the same as ordinary steering, so **speed and
##    trail are the entire mechanic**, and one sixth of dashes had neither.
##
## 2. **A dash with no direction held did nothing at all.** The direction was
##    remembered for 0.45s after a steer press; past that the button was
##    inert — 0.00 cells, no trail, no feedback of any kind. The dash is now
##    a chord instead: hold either key and press the other. Pressing the dash
##    key alone is still 0.00 cells, but it is no longer a dead input, it is
##    the first half of a gesture, so the two orders below must agree.
##
## Both are the shape of defect this mode keeps producing (§8): the code is
## right, and the *behaviour* is wrong, and only a comparison between two
## measured behaviours shows it. So the assertions below are comparative —
## every dash must outrun ordinary steering, in every repeat phase — rather
## than "the dash moves one cell", which was true throughout both bugs.

const TOWER := preload("res://scenes/TowerMode.tscn")
const HOVER_Y := -420.0 # hold the brick in clear air; no turn ends mid-measurement
const WINDOW := 12 # frames sampled per gesture
const PHASES := 6 # offsets across one HOLD_REPEAT_INTERVAL

var _mode = null # untyped: TowerMode has no class_name (see TowerProbe's header)
var _script: Array = []
var _step := 0
var _wait := 0
var _label := ""
var _recording := false
var _last_x := 0.0
var _samples: PackedFloat64Array = PackedFloat64Array()
var _rows: Array[Dictionary] = []

func _ready() -> void:
	seed(20260825) # the brick this lands on shouldn't vary between runs
	GameSettings.mode = GameSettings.MODE_TOWER
	GameSettings.player_count = 2
	_mode = TOWER.instantiate()
	add_child(_mode)
	_build_script()

# Each entry is [callable, frames to wait afterwards]. Written as a flat list
# rather than a match on a stage counter because the phase sweep would
# otherwise need a case per phase.
func _build_script() -> void:
	_add(func(): _begin("one ordinary tap"), 0)
	_add(func(): _tap("right"), WINDOW)
	_add(_end, 30)

	_add(func(): _hold("right"), 30) # let the repeat get going
	_add(func(): _begin("holding, no dash"), WINDOW)
	_add(func(): _release("right"), 0)
	_add(_end, 30)

	_add(func(): _hold("right"), 2) # dash before the first repeat tick
	_add(func(): _begin("dash: hold dir, press dash"), 0)
	_add(func(): _tap("confirm"), WINDOW)
	_add(func(): _release("right"), 0)
	_add(_end, 30)

	# The other half of the chord, and the one a player is most likely to
	# reach for when the brick is already where they were steering: the dash
	# key goes down first and the direction key picks the way.
	_add(func(): _hold("confirm"), 2)
	_add(func(): _begin("dash: hold dash, press dir"), 0)
	_add(func(): _tap("right"), WINDOW)
	_add(func(): _release("confirm"), 0)
	_add(_end, 30)

	# Still holding the dash key, a second direction press is a second dash —
	# it must not decay into an ordinary half-cell step.
	_add(func(): _hold("confirm"), 2)
	_add(func(): _tap("right"), 8)
	_add(func(): _begin("dash: second press, dash held"), 0)
	_add(func(): _tap("right"), WINDOW)
	_add(func(): _release("confirm"), 0)
	_add(_end, 30)

	# The chord read the other way round, held long enough for the repeat to
	# be running: pressing dash must still dash, not be eaten by the repeat.
	for p in range(PHASES):
		_add(func(): _hold("right"), 30 + p)
		_add(func(): _begin("dash: hold dir, repeat phase %d" % p), 0)
		_add(func(): _tap("confirm"), WINDOW)
		_add(func(): _release("right"), 0)
		_add(_end, 30)

	# Half a chord is not a dash. Neither of these may move the brick, and
	# neither may guess a direction — before or after steering.
	_add(func(): _begin("no-op: dash key alone, cold"), 0)
	_add(func(): _tap("confirm"), WINDOW)
	_add(_end, 20)

	_add(func(): _tap("right"), 60) # steer, wait a second, then dash key alone
	_add(func(): _begin("no-op: dash key alone, after steering"), 0)
	_add(func(): _tap("confirm"), WINDOW)
	_add(_end, 0)

	_add(_report, 0)

func _add(fn: Callable, wait: int) -> void:
	_script.append([fn, wait])

# --- input -----------------------------------------------------------------

func _cfg(k: String) -> int:
	return GameSettings.PLAYER_CONFIGS[_mode.active_slot][k]

func _key(k: String, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = _cfg(k)
	e.physical_keycode = _cfg(k) # _aim_held() reads the physical key state
	e.pressed = pressed
	Input.parse_input_event(e)

func _tap(k: String) -> void:
	_key(k, true)
	_key(k, false)

func _hold(k: String) -> void:
	_key(k, true)

func _release(k: String) -> void:
	_key(k, false)

# --- measurement -----------------------------------------------------------

func _begin(label: String) -> void:
	_label = label
	_samples = PackedFloat64Array()
	_recording = true

func _end() -> void:
	_recording = false
	var total := 0.0
	var fast := 0.0
	var peak := 0.0
	for s in _samples:
		total += s
		peak = maxf(peak, absf(s) * 60.0)
		if absf(s) * 60.0 > _mode.FOLLOW_SPEED + 1.0:
			fast += absf(s)
	_rows.append({
		"label": _label,
		"cells": total / float(_mode.CELL),
		"fast_cells": fast / float(_mode.CELL),
		"peak": peak,
	})
	# Back to a clean slate: the next gesture must not inherit this one's
	# aim, its direction memory or its half-finished travel.
	_mode.aim_x = 0.0
	_mode.dash_active = false
	_mode.dash_target_x = 0.0
	_mode.dash_dir = 0
	_mode.dash_ghost_timer = 0.0
	_mode.hold_dir = 0
	_mode.hold_timer = 0.0
	_mode.active_piece.global_position.x = 0.0
	_last_x = 0.0

func _report() -> void:
	print("DashFeelProbe — real key events, %d Hz physics, P%d's bindings\n"
		% [Engine.physics_ticks_per_second, _mode.active_slot + 1])
	for r in _rows:
		print("  %-30s %5.2f cells   peak %6.1f px/s   %4.2f cells above the ordinary follow"
			% [r["label"], r["cells"], r["peak"], r["fast_cells"]])
	print("")

	var failures: Array[String] = []
	for r in _rows:
		if r["label"].begins_with("dash:"):
			if r["peak"] < _mode.DASH_FOLLOW_SPEED - 1.0:
				failures.append("%s peaked at %.0f px/s, never reaching DASH_FOLLOW_SPEED (%.0f) — "
					% [r["label"], r["peak"], _mode.DASH_FOLLOW_SPEED]
					+ "this dash is the same speed as ordinary steering")
			if r["fast_cells"] < _mode.DASH_CELLS - 0.01:
				failures.append("%s carried only %.2f cells at dash speed, expected at least DASH_CELLS (%.2f)"
					% [r["label"], r["fast_cells"], _mode.DASH_CELLS])
		elif r["label"].begins_with("no-op:") and absf(r["cells"]) > 0.01:
			failures.append("%s moved %.2f cells — half a chord has become a dash, or a direction was guessed"
				% [r["label"], r["cells"]])

	# The two orders of the same chord have to agree, or the player has two
	# dashes to learn instead of one.
	var a: float = _row_named("dash: hold dir, press dash")["fast_cells"]
	var b: float = _row_named("dash: hold dash, press dir")["fast_cells"]
	if not is_equal_approx(a, b):
		failures.append("the chord is worth %.2f cells one way round and %.2f the other" % [a, b])

	if failures.is_empty():
		print("OK: both orders of the chord dash DASH_CELLS above the ordinary follow, "
			+ "in every repeat phase; half a chord moves nothing.")
	else:
		for f in failures:
			print("FAIL: %s" % f)
	get_tree().quit()

func _row_named(label: String) -> Dictionary:
	for r in _rows:
		if r["label"] == label:
			return r
	return {}

func _physics_process(_delta: float) -> void:
	if _mode == null or _mode.state != "piloting" or _mode.active_piece == null:
		return
	_mode.active_piece.global_position.y = HOVER_Y

	var x: float = _mode.active_piece.global_position.x
	if _recording:
		_samples.append(x - _last_x)
	_last_x = x

	if _wait > 0:
		_wait -= 1
		return
	if _step >= _script.size():
		return
	var entry: Array = _script[_step]
	_step += 1
	(entry[0] as Callable).call()
	_wait = entry[1]
