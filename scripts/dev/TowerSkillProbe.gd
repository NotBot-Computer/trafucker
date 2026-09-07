extends Node

## DEV ONLY — not part of the game. Nothing in the scene flow references it.
##
##   godot --headless --fixed-fps 240 res://scenes/dev/TowerSkillProbe.tscn
##
## Pile Up's counterpart to SkillProbe (Don't Crash's harness), and for the
## same reason: a clean compile proves a skill parses and nothing about the
## thing this project keeps getting wrong, which is a temporary change to a
## shared world that does not put the world back. Here the shared world is
## the whole mode — the descent's speeds, the controls, the camera, the
## canvases — and a skill that leaves a multiplier claimed or a node behind
## leaks it into every turn that follows, for every player.
##
## For every skill in TowerSkillCatalog it plays real turns (aiming the way
## TowerProbe does, by writing `aim_x` and letting the brick descend) and
## runs three lifecycles, demanding after each that the mode be *identical*
## to how it started:
##
##   1. Let it run its turns out. A self skill is cast on P1's turn and lives
##      on P1; an opponent skill is cast on P1's turn, waits for its target,
##      and lives on P2's (or on everyone else's) — so this case spans as many
##      turns as the skill claims, in a three-player match.
##   2. Cut it off mid-turn with _clear_skill_effects() — what game over does.
##   3. Cut it off with _start_match() — what pressing Enter does.
##
## "Identical" means: nothing live, nothing queued, every descent multiplier
## back at 1.0, no control flipped or locked, brick_scale at 1.0, the camera's
## zoom and offset and Engine.time_scale untouched, the space's gravity
## untouched, and no
## child node left under the mode, its Foreground or its HUD. Landed bricks
## are excluded from the node count on purpose: the tower is the shared board
## and a skill may leave a mark on it (TowerSkill's header).
##
## It also checks the plumbing the skills sit on: that every catalogue row is
## well-formed, that the charge actually grants after CHARGE_TO_SKILL clean
## drops, and that a cast outside the caster's own piloting is refused.
##
## What it cannot see: drawing (headless has no renderer, so draw_under /
## draw_over / draw_screen never run) and feel. Same standing caveat as every
## other probe here.

const TOWER := preload("res://scenes/TowerMode.tscn")

const PLAYERS := 3
const MAX_TURNS := 12 # turns a single lifecycle may take before it is declared stuck
const TURN_TIMEOUT := 20.0 # seconds of mode time one turn may take
const CUT_AFTER := 0.4 # seconds into a live effect's piloting the interrupted cases cut it
const SETTLE_FRAMES := 3

var _mode = null # untyped: TowerMode has no class_name
var _rng := RandomNumberGenerator.new()
var _failures: Array[String] = []

func _ready() -> void:
	seed(20260907)
	_rng.seed = 907
	GameSettings.mode = GameSettings.MODE_TOWER
	GameSettings.player_count = PLAYERS
	var cols: Array[Color] = [Color.RED, Color.BLUE, Color.GREEN]
	GameSettings.skin_colors = cols
	_mode = TOWER.instantiate()
	add_child(_mode)
	await _wait_piloting()

	print("=== 1. catalogue ===")
	_check_catalogue()

	print("=== 2. plumbing ===")
	await _check_cast_gating()
	await _check_charge_grants()

	print("=== 3. lifecycles ===")
	var ids: Array = TowerSkillCatalog.skills().keys()
	ids.sort()
	for id in ids:
		var skill_id: String = id
		await _run_case(skill_id, "runs out", -1.0, false)
		# An instant (duration_turns 0) is over before the cast returns, so
		# there is nothing to cut; the one case above is its whole life.
		var sample: TowerSkill = TowerSkillCatalog.make(skill_id, _mode, 0, 1)
		if sample != null and sample.duration_turns() <= 0:
			print("  %-12s %-16s (instant — nothing to cut)" % [skill_id, "cut cases"])
			continue
		await _run_case(skill_id, "cut mid-effect", CUT_AFTER, false)
		await _run_case(skill_id, "cut by restart", CUT_AFTER, true)

	print("=== 4. verdict ===")
	if _failures.is_empty():
		print("  OK — every skill ended clean, three ways, with the mode as it found it.")
	else:
		for f in _failures:
			print("  FAIL: " + f)
	get_tree().quit()

# --- Catalogue --------------------------------------------------------------

func _check_catalogue() -> void:
	var table: Dictionary = TowerSkillCatalog.skills()
	if table.is_empty():
		print("  (no skills in any pack yet)")
	for id in table.keys():
		var row: Dictionary = table[id]
		var cat: String = row.get("category", "")
		var notes: Array[String] = []
		if cat != "self" and cat != "opponent":
			notes.append("category '%s' is neither self nor opponent" % cat)
		if str(row.get("title", "")) == "":
			notes.append("no title")
		if row.get("glyph", null) == null:
			notes.append("no glyph — the HUD slot would draw bare")
		var e: TowerSkill = TowerSkillCatalog.make(id, _mode, 0, 1)
		if e == null:
			notes.append("make() returned null")
		elif e.duration_turns() < 0:
			notes.append("duration_turns() is negative")
		print("  %-12s %-9s %-16s turns %s  glyph %s%s" % [
			id, cat, str(row.get("title", "")),
			str(e.duration_turns()) if e != null else "?",
			"yes" if row.get("glyph", null) != null else "MISSING",
			"" if notes.is_empty() else "  <-- " + ", ".join(notes)])
		for n in notes:
			_failures.append("catalogue '%s': %s" % [id, n])

# --- Plumbing ---------------------------------------------------------------

# A cast is only legal on the caster's own turn with their brick in the air.
func _check_cast_gating() -> void:
	var table: Dictionary = TowerSkillCatalog.skills()
	if table.is_empty():
		return
	var any_id: String = table.keys()[0]
	var cat: String = TowerSkillCatalog.category_of(any_id)
	await _wait_slot_piloting(0)
	# Someone else's key on P1's turn.
	_mode._grant(1, any_id)
	var wrong_turn: bool = _mode._cast(1, cat)
	# P1's key, but nothing held.
	var empty: bool = _mode._cast(0, cat)
	print("  cast on another's turn: %s   cast with an empty slot: %s" % [
		"refused" if not wrong_turn else "ACCEPTED", "refused" if not empty else "ACCEPTED"])
	if wrong_turn:
		_failures.append("a cast on somebody else's turn was accepted")
	if empty:
		_failures.append("a cast from an empty slot was accepted")
	_mode._drop_slot_skills(1)
	_mode._clear_skill_effects()

# Clean placements charge; CHARGE_TO_SKILL of them grant. Aimed dead centre
# so the first drops stack rather than fall, which is what "clean" needs.
func _check_charge_grants() -> void:
	if TowerSkillCatalog.skills().is_empty():
		print("  (charge check skipped — nothing to grant)")
		return
	_mode._start_match()
	await _wait_piloting()
	var need: int = int(_mode.CHARGE_TO_SKILL)
	var granted := false
	var clean_turns: Array[int] = [0, 0, 0]
	for turn in range(need * PLAYERS + 2):
		var slot: int = _mode.active_slot
		var fell: int = await _play_turn(0.0)
		if fell == 0:
			clean_turns[slot] += 1
		if _mode.held_self[slot] != "" or _mode.held_opponent[slot] != "":
			granted = true
			print("  P%d granted '%s' after %d clean drop(s) (need %d)" % [
				slot + 1,
				_mode.held_self[slot] if _mode.held_self[slot] != "" else _mode.held_opponent[slot],
				clean_turns[slot], need])
			break
	if not granted:
		_failures.append("no skill was granted in %d turns (clean drops per player: %s)" % [need * PLAYERS + 2, clean_turns])
		print("  no grant in %d turns — clean drops per player %s" % [need * PLAYERS + 2, clean_turns])
	_mode._start_match()
	await _wait_piloting()

# --- Lifecycles -------------------------------------------------------------

func _snapshot() -> Dictionary:
	var space: RID = _mode.get_world_2d().space
	return {
		"mode_children": _mode.get_child_count(),
		"fg_children": _mode.get_node("Foreground").get_child_count(),
		"hud_children": _mode.get_node("HUD").get_child_count(),
		"overlay_children": _mode.skill_overlay.get_child_count(),
		"screen_children": _mode.skill_screen.get_child_count(),
		"descend": _mode._effect_descend_mult(),
		"soft": _mode._effect_soft_drop_mult(),
		"follow": _mode._effect_follow_mult(),
		"mass": _mode._effect_mass_mult(),
		"gravity": _mode._effect_gravity_mult(),
		"friction": _mode._effect_friction(),
		"flipped": _mode._effect_steer_flipped(),
		"rot_locked": _mode._effect_rotation_locked(),
		"dash_locked": _mode._effect_dash_locked(),
		"soft_locked": _mode._effect_soft_drop_locked(),
		"scale": _mode._effect_brick_scale(),
		"zoom": _mode.camera.zoom.x,
		# The offset is the sanctioned lever for a shake, and exactly the kind
		# of thing a skill puts back from a tick() that never gets its last
		# frame when the effect is cut. Pack C's keystone was the first to use it.
		"cam_offset": _mode.camera.offset,
		"time_scale": Engine.time_scale,
		"gravity_mag": PhysicsServer2D.area_get_param(space, PhysicsServer2D.AREA_PARAM_GRAVITY),
		"live": _mode.active_effects.size(),
		"queued": _mode.queued_effects.size(),
	}

# cut_at < 0: let it run its turns out. Otherwise cut CUT_AFTER seconds into
# the first turn the effect is live for — through _clear_skill_effects() or,
# with `restart`, through _start_match(), which are two different real paths.
func _run_case(skill_id: String, label: String, cut_at: float, restart: bool) -> void:
	var cat: String = TowerSkillCatalog.category_of(skill_id)
	_mode._start_match()
	await _wait_slot_piloting(0)
	var before := _snapshot()

	_mode._grant(0, skill_id)
	var cast: bool = _mode._cast(0, cat)
	if not cast:
		_failures.append("%s [%s]: cast refused on the caster's own turn" % [skill_id, label])
		print("  %-12s %-16s CAST REFUSED" % [skill_id, label])
		return
	var live_target: int = 0 if cat == "self" else -1
	var mid: Dictionary = {}
	var turns := 0
	var cut := false
	var observed := ""

	# Drive turns until nothing of the effect remains, or the case cuts it.
	while turns < MAX_TURNS:
		var t := 0.0
		# One turn: aim, then wait for it to end.
		if _mode.state == "piloting" and _mode.active_piece != null:
			_mode.aim_x = _rng.randf_range(-1.0, 1.0) * _mode.CELL * 0.5
			_mode.aim_steps = _rng.randi_range(0, 3)
		var was_live: bool = _is_live_now()
		while _mode.state == "piloting" and t < TURN_TIMEOUT:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if _is_live_now():
				if mid.is_empty():
					mid = _snapshot()
					live_target = _mode.active_slot
					observed = _describe_live(mid)
				if cut_at >= 0.0 and t >= cut_at:
					if restart:
						_mode._start_match()
						await _wait_piloting()
					else:
						_mode._clear_skill_effects()
					cut = true
					break
		if cut:
			break
		if _mode.state == "piloting" and t >= TURN_TIMEOUT:
			_failures.append("%s [%s]: a turn never ended (%.0fs)" % [skill_id, label, TURN_TIMEOUT])
			break
		# Let the turn resolve and the next begin.
		while _mode.state != "piloting" and _mode.state != "gameover" and t < TURN_TIMEOUT:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		turns += 1
		if _mode.state == "gameover":
			break
		if not was_live and not _is_live_now() and mid.is_empty() and _mode.queued_effects.is_empty():
			break # an instant: came and went inside the cast
		if not _is_live_now() and _mode.queued_effects.is_empty():
			break

	if cut_at < 0.0 and turns >= MAX_TURNS and (_is_live_now() or not _mode.queued_effects.is_empty()):
		_failures.append("%s [%s]: still live after %d turns — its turns never ran out" % [skill_id, label, MAX_TURNS])
	if cut_at >= 0.0 and not cut and mid.is_empty():
		_failures.append("%s [%s]: the effect never came live, so nothing was cut" % [skill_id, label])

	for i in range(SETTLE_FRAMES):
		await get_tree().physics_frame
	var after := _snapshot()

	var notes: Array[String] = []
	if int(after["live"]) != 0:
		notes.append("%d effect(s) still live" % int(after["live"]))
	if int(after["queued"]) != 0:
		notes.append("%d effect(s) still queued" % int(after["queued"]))
	for key in ["mode_children", "fg_children", "hud_children", "overlay_children", "screen_children"]:
		var k: String = key
		if int(after[k]) != int(before[k]):
			var diff: int = int(after[k]) - int(before[k])
			notes.append("%s %+d node(s)" % [k, diff])
	for key in ["descend", "soft", "follow", "mass", "gravity", "scale"]:
		var k: String = key
		if absf(float(after[k]) - 1.0) > 0.0001:
			notes.append("%s left at %.3f" % [k, after[k]])
	if float(after["friction"]) >= 0.0:
		notes.append("friction override left at %.2f" % float(after["friction"]))
	for key in ["flipped", "rot_locked", "dash_locked", "soft_locked"]:
		var k: String = key
		if bool(after[k]):
			notes.append("%s left true" % k)
	if not is_equal_approx(float(after["zoom"]), float(before["zoom"])):
		notes.append("camera zoom left at %.3f, was %.3f" % [after["zoom"], before["zoom"]])
	if not (after["cam_offset"] as Vector2).is_equal_approx(before["cam_offset"] as Vector2):
		notes.append("camera offset left at %s" % [after["cam_offset"]])
	if not is_equal_approx(float(after["time_scale"]), float(before["time_scale"])):
		notes.append("Engine.time_scale left at %.3f" % float(after["time_scale"]))
	if not is_equal_approx(float(after["gravity_mag"]), float(before["gravity_mag"])):
		notes.append("space gravity left at %.1f, was %.1f" % [after["gravity_mag"], before["gravity_mag"]])
	for i in range(PLAYERS):
		if int(_mode.lives[i]) < 0 or int(_mode.lives[i]) > int(_mode.START_LIVES):
			notes.append("P%d lives out of range at %d" % [i + 1, _mode.lives[i]])
		if int(_mode.charge[i]) < 0 or int(_mode.charge[i]) > int(_mode.CHARGE_TO_SKILL):
			notes.append("P%d charge out of range at %d" % [i + 1, _mode.charge[i]])

	print("  %-12s %-16s %s over %d turn(s)%s%s" % [
		skill_id, label,
		"instant" if mid.is_empty() and cut_at < 0.0 else ("cut" if cut else "ran out"),
		turns,
		"" if observed == "" else "  live on P%d: %s" % [live_target + 1, observed],
		"" if notes.is_empty() else "  <-- " + ", ".join(notes)])
	for n in notes:
		_failures.append("%s [%s]: %s" % [skill_id, label, n])

func _is_live_now() -> bool:
	return not _mode.active_effects.is_empty()

# What the effect visibly did to the mode's physics while live, for the eye.
# Not asserted — only the author knows what their skill should change.
func _describe_live(mid: Dictionary) -> String:
	var parts: Array[String] = []
	for key in ["descend", "soft", "follow", "mass", "gravity", "scale"]:
		var k: String = key
		if absf(float(mid[k]) - 1.0) > 0.0001:
			parts.append("%s x%.2f" % [k, mid[k]])
	if float(mid["friction"]) >= 0.0:
		parts.append("friction %.2f" % float(mid["friction"]))
	for key in ["flipped", "rot_locked", "dash_locked", "soft_locked"]:
		var k: String = key
		if bool(mid[k]):
			parts.append(k)
	if int(mid["queued"]) > 0:
		parts.append("%d queued" % int(mid["queued"]))
	return "no physics hook claimed" if parts.is_empty() else ", ".join(parts)

# --- Turn driving -----------------------------------------------------------

func _wait_piloting() -> void:
	var t := 0.0
	while not (_mode.state == "piloting" and _mode.active_piece != null) and t < TURN_TIMEOUT:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _wait_slot_piloting(slot: int) -> void:
	await _wait_piloting()
	var guard := 0
	while _mode.active_slot != slot and guard < PLAYERS + 1:
		await _play_turn(0.0)
		await _wait_piloting()
		guard += 1

# Plays the current turn to its end at the given aim and returns how many
# bricks fell during it.
func _play_turn(aim: float) -> int:
	await _wait_piloting()
	_mode.aim_x = aim
	_mode.aim_steps = 0
	var t := 0.0
	while _mode.state == "piloting" and t < TURN_TIMEOUT:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var fell: int = 0
	while _mode.state != "piloting" and _mode.state != "gameover" and t < TURN_TIMEOUT:
		fell = _mode.fallen_this_turn
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return fell
