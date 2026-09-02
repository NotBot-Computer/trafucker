extends Node
class_name SkillProbe

## Dev-only harness for the modular skills (scripts/skills/). Not part of the
## game — nothing in the shipped scene flow references it:
##
##   godot --headless --fixed-fps 240 res://scenes/dev/SkillProbe.tscn
##
## **What it is for.** A clean `godot --headless --quit` proves a skill parses.
## It proves nothing about the thing this project actually keeps getting wrong,
## which is a skill that does not put the board back: session G left a smoke
## sprite on screen that survived a round restart, and §12 records the general
## rule (a killed Tween skips the callback that was going to free something).
## Every skill here is a temporary change to a shared board, so "does it end
## cleanly" is the invariant worth a harness, and it is one that can be checked
## without a human watching.
##
## For each catalogued skill it runs three separate lifecycles and, after each,
## demands the board be *identical* to how it started:
##
##   1. Let it run out on its own clock.
##   2. Cut it off mid-effect (_clear_skill_effects — what an elimination does).
##   3. Cut it off with start_round() (what pressing Enter does).
##
## "Identical" means: no effects left live, the three physics multipliers back
## at exactly 1.0, the car back at its normal footprint and steering speed, and
## — the session G check — no child node left behind on the board.
##
## **The board is made invulnerable for every case.** An unattended board
## crashes within about a second and a half (TaxiProbe's header measured it),
## and a crash spends a heart pip — which frees a child node and shows up
## here as a *negative* leak. Compact's first run reported exactly that. With
## invuln_timer pinned high, _on_player_area_entered returns before
## _take_hit, so what the count reflects is the skill and nothing else. The
## cost is that absorbs_crash() is never exercised — no shipped skill uses
## it yet; the first one that does needs its own case with the pin removed.
##
## **What it cannot see.** Headless has no renderer, so draw_board() and
## draw_overlay() are never called: a skill whose *visuals* are broken passes
## this cleanly. Feel — whether Oil Slick is survivable, whether the Smoke
## Screen is fair — is not measurable here either. Both still need a human at
## the keyboard, exactly as CLAUDE.md says.

const MAIN := preload("res://scenes/Main.tscn")

const MAX_WAIT := 20.0 # seconds of board time before a skill is declared stuck
const CUT_AFTER := 0.5 # how far into an effect the interrupted runs cut it off
const SETTLE_FRAMES := 3 # queue_free() is deferred, so counts need a beat to be true
const NO_CRASHES := 1.0e9 # invuln_timer value that outlasts any case, see the header

# What a skill must visibly do to the board's *physics* while it is live —
# the restore checks alone would pass a skill that never did anything. Only
# the hooks a headless run can see are listed; Make Way changes traffic and
# Smoke Screen changes nothing but pixels, so they have no row and are only
# held to ending cleanly. "<" / ">" are against the pre-skill baseline.
const EXPECT := {
	"compact": {"car_w": "<", "steer": ">"},
	"slick": {"grip_mult": "<"},
}

var board: Node = null
var failures: Array[String] = []
# PlayerBoard's consts (pools, glyph table, MAX_LIVES) reached explicitly
# rather than as `board.SELF_SKILLS`: `board` is untyped here, and reading a
# script constant off an untyped instance is exactly the kind of thing that
# resolves at runtime or not depending on the engine version. The map is
# unambiguous.
var consts: Dictionary = {}

func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	board = main.get_node("BoardsContainer").get_child(0)
	# The round opens frozen behind the countdown (Countdown.gd, ~2.7s) and a
	# frozen board's _process early-returns, so nothing would ever tick.
	board.active = true
	board.alive = true
	consts = board.get_script().get_script_constant_map()
	await get_tree().process_frame

	print("=== 1. every pool entry resolves to something ===")
	_check_pools()

	print("=== 2. lifecycles ===")
	for id in SkillCatalog.SKILLS.keys():
		var skill_id: String = id
		await _run_case(skill_id, "runs out", -1.0, false)
		await _run_case(skill_id, "cut mid-effect", CUT_AFTER, false)
		await _run_case(skill_id, "cut by restart", CUT_AFTER, true)

	print("=== 3. re-picking does not stack ===")
	await _check_no_stacking()

	print("=== 4. pit stop refunds a life, or fills the bar ===")
	await _check_pitstop()

	print("=== 5. verdict ===")
	if failures.is_empty():
		print("  OK — every skill ended clean, three ways, with the board as it found it.")
	else:
		for f in failures:
			print("  FAIL: " + f)
	get_tree().quit()

# Every id in either pool must be applicable: either the catalog knows it, or
# it is one of the three that predate the catalog and still live as branches
# in PlayerBoard. An id in a pool with neither is a skill that silently grants
# nothing, which is exactly what _roll_pending_skills exists to make visible.
func _check_pools() -> void:
	var legacy := ["tank", "nitro", "taxi"]
	for pool_name in ["SELF_SKILLS", "OPPONENT_SKILLS"]:
		var pool: Array = consts[pool_name]
		for entry in pool:
			var skill_id: String = entry
			var known: bool = SkillCatalog.has_skill(skill_id) or legacy.has(skill_id)
			var glyphs: Dictionary = consts["SKILL_GLYPHS"]
			var glyph: Texture2D = glyphs.get(skill_id, null)
			if glyph == null:
				glyph = SkillCatalog.glyph_of(skill_id)
			print("  %-10s %-9s %s  glyph %s" % [
				pool_name.substr(0, 4).to_lower(), skill_id,
				"catalog" if SkillCatalog.has_skill(skill_id) else "inline ",
				"yes" if glyph != null else "MISSING"])
			if not known:
				failures.append("%s entry '%s' is applied by nothing" % [pool_name, skill_id])
			if glyph == null:
				failures.append("'%s' has no choice-icon glyph — the icon would draw bare" % skill_id)
			# A catalogued skill must be filed under the pool it is actually in.
			if SkillCatalog.has_skill(skill_id):
				var want: String = "self" if pool_name == "SELF_SKILLS" else "opponent"
				if SkillCatalog.category_of(skill_id) != want:
					failures.append("'%s' is in %s but its catalog row says category '%s'"
						% [skill_id, pool_name, SkillCatalog.category_of(skill_id)])

func _snapshot() -> Dictionary:
	return {
		"children": board.get_child_count(),
		"car_w": board.car_size().x,
		"car_h": board.car_size().y,
		"steer": board.steer_top_speed(),
		"speed_mult": board._effect_speed_mult(),
		"steer_mult": board._effect_steer_mult(),
		"grip_mult": board._effect_grip_mult(),
		"lives": board.lives,
		"boost": board.boost_charge,
	}

# cut_at < 0 means "let it finish". restart routes the interruption through
# start_round() instead of _clear_skill_effects(), because those are two
# different real code paths (Enter on the game-over screen, and a board being
# eliminated) and a skill can restore correctly through one and not the other.
func _run_case(skill_id: String, label: String, cut_at: float, restart: bool) -> void:
	board.lives = int(consts["MAX_LIVES"])
	board.invuln_timer = NO_CRASHES
	var before := _snapshot()

	board._apply_skill_effect(skill_id)
	var applied: bool = not board.active_effects.is_empty()
	var mid: Dictionary = {}
	var t := 0.0
	while t < MAX_WAIT:
		await get_tree().process_frame
		t += get_process_delta_time()
		if mid.is_empty():
			mid = _snapshot() # one tick in: what the skill is actually doing
		if board.active_effects.is_empty():
			break
		if cut_at >= 0.0 and t >= cut_at:
			if restart:
				board.start_round()
				board.active = true
				board.invuln_timer = NO_CRASHES
			else:
				board._clear_skill_effects()
			break

	if applied and cut_at < 0.0 and t >= MAX_WAIT:
		failures.append("%s [%s]: still running after %.0fs — its clock never ran out" % [skill_id, label, MAX_WAIT])

	for i in range(SETTLE_FRAMES):
		await get_tree().process_frame
	# Everything a skill can legitimately leave on the road (Detour's
	# barriers) lives in the obstacle container, which the shared loop culls
	# and start_round wipes — so it is cleared here rather than counted as a
	# leak, and the board's own children are what must balance.
	for child in board.obstacle_container.get_children():
		child.free()
	var after := _snapshot()

	var notes: Array[String] = []
	if not board.active_effects.is_empty():
		notes.append("%d effect(s) still live" % board.active_effects.size())
	if after["children"] != before["children"]:
		var diff: int = int(after["children"]) - int(before["children"])
		notes.append("leaked %d child node(s)" % diff if diff > 0 else "board lost %d child node(s)" % -diff)
	for key in ["speed_mult", "steer_mult", "grip_mult"]:
		var k: String = key
		if abs(float(after[k]) - 1.0) > 0.0001:
			notes.append("%s left at %.3f" % [k, after[k]])
	if abs(float(after["car_w"]) - float(before["car_w"])) > 0.01 or abs(float(after["car_h"]) - float(before["car_h"])) > 0.01:
		notes.append("car left at %.1fx%.1f, was %.1fx%.1f" % [after["car_w"], after["car_h"], before["car_w"], before["car_h"]])
	if abs(float(after["steer"]) - float(before["steer"])) > 0.01:
		notes.append("steer top speed left at %.1f, was %.1f" % [after["steer"], before["steer"]])
	if int(board.lives) > int(consts["MAX_LIVES"]) or int(board.lives) < 0:
		notes.append("lives out of range at %d" % board.lives)
	# Only judged on the uninterrupted run: the cut cases exist to test the
	# ending, and the skill was live for the same first frame either way.
	if cut_at < 0.0 and EXPECT.has(skill_id) and not mid.is_empty():
		var expect: Dictionary = EXPECT[skill_id]
		for key in expect.keys():
			var k: String = key
			var want: String = expect[k]
			var was: float = float(before[k])
			var now: float = float(mid[k])
			var ok: bool = (now < was - 0.001) if want == "<" else (now > was + 0.001)
			if not ok:
				notes.append("while live, %s was %.3f against a baseline of %.3f — expected %s" % [k, now, was, want])
	if board.boost_charge < 0.0 or board.boost_charge > 1.0:
		notes.append("boost_charge out of range at %.2f" % board.boost_charge)

	var live: String = ""
	if applied and not mid.is_empty():
		live = "  live: car %.0fpx steer %.0f grip x%.2f speed x%.2f" % [mid["car_w"], mid["steer"], mid["grip_mult"], mid["speed_mult"]]
	print("  %-10s %-16s %s after %.2fs%s%s" % [
		skill_id, label,
		"applied" if applied else "instant",
		t, live, "" if notes.is_empty() else "  <-- " + ", ".join(notes)])
	for n in notes:
		failures.append("%s [%s]: %s" % [skill_id, label, n])

	# Whatever the case did to the board, hand the next one a clean one.
	board.start_round()
	board.active = true
	await get_tree().process_frame

# The lifecycle cases pin lives at MAX_LIVES, so every one of them sent Pit
# Stop down its boost-fill fallback and none ever exercised the refund — the
# half its author called the fiddly part. This does: spend a life the way a
# crash does (_take_hit with no vehicle), then refund it and demand the
# invariant _spend_heart() relies on — exactly `lives` valid pips in the
# first `lives` slots — so the *next* crash still spends the right one.
func _check_pitstop() -> void:
	var max_lives: int = int(consts["MAX_LIVES"])
	board.start_round()
	board.active = true
	board._take_hit(null)
	# The spent pip is not freed on the hit: _spend_heart pops it over
	# HeartPips.LOSS_DURATION and frees it from the tween's last callback.
	# Counting before that lands would count the pip being spent as still
	# present, and then blame Pit Stop for the difference — which the first
	# version of this case did.
	await _wait_for_pip_loss()
	var lives_after_hit: int = board.lives
	var children_after_hit: int = board.get_child_count()
	board.invuln_timer = NO_CRASHES
	board._apply_skill_effect("pitstop")
	# Let the flourish run its whole course, so what is checked is the
	# resting state and not a pip mid-animation.
	var t := 0.0
	while not board.active_effects.is_empty() and t < MAX_WAIT:
		await get_tree().process_frame
		t += get_process_delta_time()
	for i in range(SETTLE_FRAMES):
		await get_tree().process_frame
	var valid_pips: int = 0
	var valid_in_order: bool = true
	for i in range(board.heart_sprites.size()):
		# Untyped on purpose: a spent slot holds a freed pip, and assigning
		# that to a typed local through the untyped `board` is itself an
		# error — see §12 and PitStopSkill._restore_pip.
		var heart = board.heart_sprites[i]
		var ok: bool = is_instance_valid(heart)
		if ok:
			valid_pips += 1
		if ok != (i < board.lives):
			valid_in_order = false
	print("  refund: lives %d -> %d, board children %d -> %d, valid pips %d (%s)" % [
		lives_after_hit, board.lives, children_after_hit, board.get_child_count(), valid_pips,
		"in the first %d slots" % board.lives if valid_in_order else "OUT OF ORDER"])
	if lives_after_hit != max_lives - 1:
		failures.append("pitstop setup: _take_hit left lives at %d, expected %d" % [lives_after_hit, max_lives - 1])
	if board.lives != max_lives:
		failures.append("pitstop: lives %d after refund, expected %d" % [board.lives, max_lives])
	if board.get_child_count() != children_after_hit + 1:
		failures.append("pitstop: board children %d -> %d, expected exactly one pip back" % [children_after_hit, board.get_child_count()])
	if valid_pips != board.lives or not valid_in_order:
		failures.append("pitstop: %d valid pips for %d lives, in order: %s" % [valid_pips, board.lives, valid_in_order])
	# A pip that came back must also be spendable: crash again and the count
	# must drop by exactly one sprite, from the top slot.
	board.invuln_timer = 0.0
	board._take_hit(null)
	await _wait_for_pip_loss()
	if board.get_child_count() != children_after_hit:
		failures.append("pitstop: a refunded pip did not spend cleanly (children %d, expected %d)" % [board.get_child_count(), children_after_hit])
	print("  spend it again: lives %d, children %d (expected %d)" % [board.lives, board.get_child_count(), children_after_hit])

	# The fallback: at full lives the boost bar fills instead.
	board.start_round()
	board.active = true
	board.invuln_timer = NO_CRASHES
	board.boost_charge = 0.0
	board._apply_skill_effect("pitstop")
	await get_tree().process_frame
	print("  at full lives: boost_charge %.2f, lives %d" % [board.boost_charge, board.lives])
	if board.boost_charge < 0.999:
		failures.append("pitstop at full lives: boost_charge %.2f, expected 1.0" % board.boost_charge)
	if board.lives != max_lives:
		failures.append("pitstop at full lives: lives moved to %d" % board.lives)
	while not board.active_effects.is_empty():
		await get_tree().process_frame
	board.start_round()

# Board time, not frames: --fixed-fps sets the delta, so a frame count would
# be a different wait at a different rate.
func _wait_for_pip_loss() -> void:
	var t := 0.0
	while t < HeartPips.LOSS_DURATION + 0.1:
		await get_tree().process_frame
		t += get_process_delta_time()
	for i in range(SETTLE_FRAMES):
		await get_tree().process_frame

# The stated rule everywhere in this codebase (the pickup, Tank Mode,
# _apply_skill_effect) is that re-triggering refreshes rather than stacks. Two
# copies of one skill both multiplying the same grip figure is how a 0.35 grip
# quietly becomes 0.12.
func _check_no_stacking() -> void:
	for id in SkillCatalog.SKILLS.keys():
		var skill_id: String = id
		board.start_round()
		board.active = true
		await get_tree().process_frame
		board._apply_skill_effect(skill_id)
		var after_first: int = board.active_effects.size()
		board._apply_skill_effect(skill_id)
		var after_second: int = board.active_effects.size()
		if after_second > after_first:
			failures.append("%s: re-picking stacked a second copy (%d -> %d)" % [skill_id, after_first, after_second])
		print("  %-10s %d -> %d live" % [skill_id, after_first, after_second])
	board.start_round()
