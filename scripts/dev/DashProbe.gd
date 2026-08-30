extends Node

## DEV ONLY — not part of the game. Nothing in the scene flow references it.
##
##   godot --headless --fixed-fps 60 res://scenes/dev/DashProbe.tscn
##
## Drives Pile Up's lateral input through TowerMode's own entry points and
## reports what the dash button does against what two ordinary presses do.
##
## It exists because of one bug, which is worth understanding before changing
## anything it measures. The dash shipped moving the brick a whole cell —
## correctly — by adding the second half of a cell to the half the first tap
## had already moved, at the ordinary follow speed. So a double-tap and two
## slow taps produced *the same distance at the same pace*. The mechanic
## worked perfectly and was completely imperceptible, which from the outside
## is indistinguishable from the input being broken, and that is exactly how
## it was reported: "i cant dash".
##
## (The dash was a double-tap then, and is now a chord of the dash key and a
## direction key, either one held while the other is pressed. It moved
## because a double-tap and two deliberate half-steps are the same
## keypresses, so the game had to guess from timing. The measurement below is
## unchanged by any of that: it still asks whether dashing differs from not
## dashing, which is why it calls `_dash()` with the direction already
## decided. Which keys choose that direction is DashFeelProbe's question.)
##
## The lesson generalises past this one input. **A feature whose output is
## identical to something the player can already do has not been added**, and
## no amount of reading the code says so — both paths look right, because
## both are right. The only thing that catches it is measuring the two
## against each other, which is what this does.
##
## So the assertion here is not "the dash moves one cell". It is "the dash is
## distinguishable from not dashing": a whole cell instead of half, at a
## faster follow, with a visible afterimage. If a future change makes those
## two rows match again, the dash has silently stopped existing.

const TOWER := preload("res://scenes/TowerMode.tscn")

var _mode = null # untyped: TowerMode has no class_name (see TowerProbe's header)
var _stage := 0
var _wait := 0
var _start_x := 0.0
var _fast: Dictionary = {}

func _ready() -> void:
	seed(20260825) # the brick this lands on shouldn't vary between runs
	GameSettings.mode = GameSettings.MODE_TOWER
	GameSettings.player_count = 2
	_mode = TOWER.instantiate()
	add_child(_mode)

func _sample(moved: float) -> Dictionary:
	return {
		"cells": moved / float(_mode.CELL),
		"dashing": _mode.dash_active,
		"ghost": _mode.dash_ghost_timer,
		"follow": _mode.DASH_FOLLOW_SPEED if _mode.dash_active else _mode.FOLLOW_SPEED,
	}

func _row(label: String, d: Dictionary) -> String:
	return "  %-26s %5.2f cells   follow %4d px/s   trail %s" % [
		label, d["cells"], int(d["follow"]), "%.2fs" % d["ghost"] if d["ghost"] > 0.0 else "none"
	]

func _physics_process(_delta: float) -> void:
	if _mode == null or _mode.state != "piloting":
		return
	if _wait > 0:
		_wait -= 1
		return
	match _stage:
		0:
			_start_x = _mode.aim_x
			_mode._dash(1) # direction given: how it is chosen is DashFeelProbe's job
			_fast = _sample(_mode.aim_x - _start_x)
			_wait = 2
			_stage = 1
		1:
			_mode.aim_x = 0.0
			_mode.dash_active = false
			_mode.dash_ghost_timer = 0.0
			_wait = 40
			_stage = 2
		2:
			_start_x = _mode.aim_x
			_mode._press_steer(1)
			_wait = 40 # ~660ms, well outside DASH_WINDOW
			_stage = 3
		3:
			_mode._press_steer(1) # a second ordinary press
			var slow: Dictionary = _sample(_mode.aim_x - _start_x)
			print("DashProbe — STEP_CELLS %.2f, DASH_CELLS %.2f\n"
				% [_mode.STEP_CELLS, _mode.DASH_CELLS])
			print(_row("dash button", _fast))
			print(_row("two ordinary presses", slow))
			print("")
			var same_speed: bool = is_equal_approx(_fast["follow"], slow["follow"])
			var no_trail: bool = _fast["ghost"] <= 0.0
			if same_speed and no_trail:
				print("FAIL: a dash is indistinguishable from two ordinary taps — see this file's header.")
			elif not is_equal_approx(_fast["cells"], _mode.DASH_CELLS):
				print("FAIL: a dash moved %.2f cells, expected DASH_CELLS (%.2f)." % [_fast["cells"], _mode.DASH_CELLS])
			else:
				print("OK: a dash covers DASH_CELLS at %dx the follow speed, with a trail."
					% int(_fast["follow"] / slow["follow"]))
			get_tree().quit()
