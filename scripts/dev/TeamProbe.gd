extends Node

## DEV ONLY — not part of the game. Nothing in the scene flow references it.
##
##   godot --headless --fixed-fps 240 res://scenes/dev/TeamProbe.tscn
##   godot --headless --fixed-fps 240 res://scenes/dev/TeamProbe.tscn -- --only=teams
##
## Pile Up's variants other than free-for-all, checked the way TowerProbe and
## TowerSkillProbe check the original — by playing them. Free-for-all is
## deliberately not here: it is "every player is a team of one", the other
## probes still cover it, and they reproduce their numbers to the digit.
##
## What a team variant can get wrong that free-for-all cannot, per section:
##
##   teams    — the turn order (teams alternate; members rotate inside a
##              team; 2v1 hands the lone player every other turn), the pool
##              (a fall costs the team that was on the clock and nobody
##              else), the end (one team left standing), and the skill
##              rules teams add: a support cast lands on the flyer, a hex
##              lands on the next RIVAL, never on a teammate.
##   copilot  — the split: the pilot's keys steer and the crew mate's keys
##              turn, and neither does the other's job; the roles swap every
##              crew turn; a clean drop pays both; and a skill on the crew
##              follows it across the swap instead of waiting for the same
##              person to steer again. Keys go through handle_key(), so this
##              is the real routing, but not real key *delivery*.
##   coop     — the goal line and the storm: a match ends in a win exactly
##              when a settled tower's top is over the line with a life left;
##              the storm casts every STORM_EVERY surviving turns (every
##              STORM_EVERY_HIGH past half the goal), as slot -1, at whoever
##              flies next; and nobody is ever granted a hex, since there is
##              no one on the tower to send it to. Also reports how often
##              blind aim reaches the line, which is the floor the goal and
##              the lives were set against.
##   race     — two whole TowerModes under TowerRace: separate physics worlds,
##              both flying at once, the same bricks in the same order, a hex
##              cast on one tower queued on the other, a real key press
##              (Input.parse_input_event) reaching the right tower through
##              the host, every race ending in exactly one result, and a
##              restart putting both towers back. Reports how races end —
##              by the line or by running out of lives.
##
## It aims the way TowerProbe does — by writing aim_x — so it says nothing
## about the keys, and nothing at all about whether any of this is fun.

const TOWER := preload("res://scenes/TowerMode.tscn")

const MATCHES := 8
const MAX_TURNS := 300
const TURN_TIMEOUT := 30.0

var _mode = null # untyped: TowerMode has no class_name
var _rng := RandomNumberGenerator.new()
var _failures: Array[String] = []
var _only: String = ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--only="):
			_only = str(arg).split("=")[1]

	if _wants("teams"):
		print("=== teams: matches ===")
		await _matches(GameSettings.TOWER_TEAMS, 4, 0.3)
		await _matches(GameSettings.TOWER_TEAMS, 4, 1.0)
		await _matches(GameSettings.TOWER_TEAMS, 3, 0.3)
		print("=== teams: skills ===")
		await _teams_skills()

	if _wants("copilot"):
		print("=== co-pilot: matches ===")
		await _matches(GameSettings.TOWER_COPILOT, 4, 0.3)
		await _matches(GameSettings.TOWER_COPILOT, 4, 1.0)
		print("=== co-pilot: the crew ===")
		await _copilot_crew()

	if _wants("coop"):
		print("=== co-op: matches ===")
		await _coop_matches(1, 0.3)
		await _coop_matches(2, 0.3)
		await _coop_matches(4, 0.3)
		await _coop_matches(4, 0.15)

	if _wants("race"):
		print("=== race: plumbing ===")
		await _race_plumbing()
		print("=== race: races ===")
		await _races(2, 0.3)
		await _races(4, 0.3)
		await _races(3, 0.3)

	print("=== verdict ===")
	if _failures.is_empty():
		print("  OK — every variant section passed.")
	else:
		for f in _failures:
			print("  FAIL: " + f)
	get_tree().quit()

func _wants(section: String) -> bool:
	return _only == "" or _only == section

func _fail(what: String) -> void:
	_failures.append(what)
	print("  <-- " + what)

# --- Setup ------------------------------------------------------------------

func _spawn(variant: int, count: int, seed_value: int) -> void:
	if _mode != null:
		_mode.queue_free()
		_mode = null
		await get_tree().physics_frame
	# Bricks come from the global randi(), so the global RNG is seeded too
	# (PROJECT_STATE §7).
	seed(seed_value)
	_rng.seed = seed_value
	GameSettings.mode = GameSettings.MODE_TOWER
	GameSettings.tower_variant = variant
	GameSettings.player_count = count
	var cols: Array[Color] = []
	for i in range(count):
		cols.append(GameSettings.PLAYER_SKINS[i]["color"])
	GameSettings.skin_colors = cols
	_mode = TOWER.instantiate()
	add_child(_mode)
	await _wait_piloting()

func _wait_piloting() -> void:
	var t := 0.0
	while not (_mode.state == "piloting" and _mode.active_piece != null) and _mode.state != "gameover" and t < TURN_TIMEOUT:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _aim(spread: float) -> void:
	var piece = _mode.active_piece
	if piece == null:
		return
	_mode.aim_steps = _rng.randi_range(0, 3)
	var limit: float = maxf(0.0,
		_mode.PLATFORM_CELLS * _mode.CELL * 0.5
		+ _mode.AIM_BOUND_CELLS * _mode.CELL
		- piece.aim_half_width(_mode.aim_steps))
	_mode.aim_x = _rng.randf_range(-limit, limit) * spread

# Plays the current turn to its resolution and returns the bricks that fell
# on it. Reads `fallen_this_turn` on the first frame out of settling, which
# is the frame after _resolve_turn() charged it — physics_frame fires before
# the mode's own _physics_process, so nothing has been added since.
func _finish_turn() -> int:
	var t := 0.0
	while _mode.state == "piloting" and t < TURN_TIMEOUT:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	while _mode.state == "settling" and t < TURN_TIMEOUT * 2.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return int(_mode.fallen_this_turn)

# --- Matches ----------------------------------------------------------------

func _matches(variant: int, count: int, spread: float) -> void:
	var total_turns := 0
	var ended := 0
	for m in range(MATCHES):
		await _spawn(variant, count, 4400 + m * 977 + count)
		var r: Dictionary = await _play_match(spread)
		total_turns += int(r["turns"])
		if r["ended"]:
			ended += 1
		var label: String = "%s %dp spread %.1f seed %d" % [GameSettings.tower_variant_info(variant)["title"], count, spread, m]
		for n: String in r["notes"]:
			_fail("%s: %s" % [label, n])
	print("  %-10s %dp spread %.1f   ended %d/%d   turns per match %.1f" % [
		GameSettings.tower_variant_info(variant)["title"], count, spread, ended, MATCHES, float(total_turns) / float(MATCHES)])

func _play_match(spread: float) -> Dictionary:
	var notes: Array[String] = []
	var turns := 0
	var last_team := -1
	var last_flyer := {} # team -> the slot that flew its previous turn
	while turns < MAX_TURNS:
		await _wait_piloting()
		if _mode.state == "gameover":
			break
		if _mode.state != "piloting":
			notes.append("hung between turns after %d" % turns)
			break
		var slot: int = _mode.active_slot
		var team: int = _mode.team_of[slot]

		# Teams alternate whenever there is more than one left to alternate.
		if _mode._living_teams() > 1 and team == last_team:
			notes.append("turn %d: team %d flew twice running" % [turns, team])
		# Members rotate inside a team.
		if last_flyer.has(team) and _mode._team_members(team).size() > 1 and last_flyer[team] == slot:
			notes.append("turn %d: P%d flew two of their team's turns running" % [turns, slot + 1])
		last_flyer[team] = slot
		last_team = team

		var before: Array = _mode.lives.duplicate()
		_aim(spread)
		var fell: int = await _finish_turn()
		turns += 1

		# The pool: only the team on the clock pays, one life, and only if
		# something fell.
		for i in range(before.size()):
			var want: int = maxi(0, int(before[i]) - (1 if i == team and fell > 0 else 0))
			if int(_mode.lives[i]) != want:
				notes.append("turn %d: team %d lives %d -> %d, expected %d (fell %d, team on clock %d)" % [
					turns, i, before[i], _mode.lives[i], want, fell, team])

	var ended: bool = _mode.state == "gameover"
	if not ended:
		notes.append("no result after %d turns" % turns)
	else:
		var alive: Array[int] = []
		for t in _mode._teams_here():
			if int(_mode.lives[t]) > 0:
				alive.append(t)
		if alive.size() > 1:
			notes.append("match ended with %d teams still alive" % alive.size())
		var want_title: String = "NOBODY WINS" if alive.is_empty() else "%s WINS" % GameSettings.tower_team_name(alive[0])
		if _mode.overlay_title.text != want_title:
			notes.append("overlay says '%s', expected '%s'" % [_mode.overlay_title.text, want_title])
	return {"turns": turns, "ended": ended, "notes": notes}

# --- Teams: the skill rules -------------------------------------------------

func _teams_skills() -> void:
	await _spawn(GameSettings.TOWER_TEAMS, 4, 51)
	if _mode.active_slot != 0:
		_fail("teams: the first brick went to P%d, not P1" % (_mode.active_slot + 1))
		return

	# A teammate's self skill goes onto the flyer's brick.
	_mode._grant(2, "plumb")
	var support: bool = _mode._cast(2, "self")
	var landed_on := -1
	for e in _mode.active_effects:
		if e.caster == 2:
			landed_on = e.target
	_report("support cast by P3 on P1's turn", support, true)
	if landed_on != 0:
		_fail("teams: P3's support cast attached to P%d, not the flyer P1" % (landed_on + 1))

	# A rival's self skill cannot be cast on your turn, and a teammate cannot
	# send a hex — choosing when to hex is the flyer's call.
	_mode._grant(1, "cement")
	_report("rival P2 casting a self skill on P1's turn", _mode._cast(1, "self"), false)
	_mode._grant(2, "tremor")
	_report("teammate P3 casting a hex on P1's turn", _mode._cast(2, "opponent"), false)

	# The flyer's hex lands on the next RIVAL up, never the teammate.
	_mode._grant(0, "tremor")
	var hexed: bool = _mode._cast(0, "opponent")
	_report("flyer P1 casting a hex", hexed, true)
	var hex_target := -1
	if not _mode.queued_effects.is_empty():
		hex_target = _mode.queued_effects.back().target
	if hex_target != 1:
		_fail("teams: P1's hex queued on P%d, expected P2 (the next rival up)" % (hex_target + 1))
	var all: Array[int] = _mode._hex_targets(0, true)
	if all != [1, 3]:
		_fail("teams: an all-opponents hex from the left team targets %s, expected [1, 3]" % [all])
	print("  hex from P1 -> P%d; all-opponents from the left team -> %s" % [hex_target + 1, all])
	_mode._clear_skill_effects()
	for s in range(4):
		_mode._drop_slot_skills(s)

	# 2v1: the lone right-team player is every other turn, and a hex from
	# them goes to whichever left-team member flies next.
	await _spawn(GameSettings.TOWER_TEAMS, 3, 52)
	var order: Array[int] = []
	for i in range(6):
		await _wait_piloting()
		order.append(_mode.active_slot)
		if _mode.active_slot == 1 and i == 3:
			_mode._grant(1, "tremor")
			_mode._cast(1, "opponent")
			var tgt: int = _mode.queued_effects.back().target if not _mode.queued_effects.is_empty() else -1
			if tgt != _mode._pilot_of(0):
				_fail("2v1: P2's hex went to P%d, but P%d flies the left team's next brick" % [tgt + 1, _mode._pilot_of(0) + 1])
		_mode.aim_x = 0.0
		_mode.aim_steps = 0
		await _finish_turn()
	print("  2v1 order: %s" % [order.map(func(s): return "P%d" % (s + 1))])
	if order != [0, 1, 2, 1, 0, 1] and _mode.state != "gameover":
		_fail("2v1: turn order %s, expected P1 P2 P3 P2 P1 P2" % [order])
	_mode._clear_skill_effects()

	# Every self skill, cast in support, must end clean — the support path
	# only changes who the caster is, but caster != target is new to them.
	for id in TowerSkillCatalog.ids_in("self"):
		await _spawn(GameSettings.TOWER_TEAMS, 4, 60 + id.length())
		_mode._grant(2, id)
		if not _mode._cast(2, "self"):
			_fail("support %s: refused" % id)
			continue
		var turns := 0
		while not _mode.active_effects.is_empty() and turns < 10 and _mode.state != "gameover":
			_mode.aim_x = 0.0
			_mode.aim_steps = 0
			await _finish_turn()
			await _wait_piloting()
			turns += 1
		var notes: Array[String] = []
		if not _mode.active_effects.is_empty():
			notes.append("still live after %d turns" % turns)
		if absf(_mode._effect_descend_mult() - 1.0) > 0.0001 or absf(_mode._effect_follow_mult() - 1.0) > 0.0001:
			notes.append("a speed multiplier left claimed")
		if _mode._effect_steer_flipped() or _mode._effect_rotation_locked() or _mode._effect_dash_locked():
			notes.append("a control left flipped or locked")
		print("  support %-8s ended over %d turn(s)%s" % [id, turns, "" if notes.is_empty() else "  <-- " + ", ".join(notes)])
		for n in notes:
			_failures.append("support %s: %s" % [id, n])

# --- Co-op: the goal and the storm --------------------------------------------

func _coop_matches(count: int, spread: float) -> void:
	var wins := 0
	var total_turns := 0
	var total_storms := 0
	var heights: Array[int] = []
	for m in range(MATCHES):
		await _spawn(GameSettings.TOWER_COOP, count, 8800 + m * 613 + count)
		var notes: Array[String] = []
		var turns := 0
		var survived := 0 # resolved turns the crew came through with a life left
		var last_storm_at := 0
		while turns < MAX_TURNS:
			await _wait_piloting()
			if _mode.state != "piloting":
				break
			var expected: int = _mode.active_slot
			var storms_before: int = int(_mode.storms)
			_aim(spread)
			await _finish_turn()
			turns += 1
			if int(_mode.held_opponent.count("")) != count:
				notes.append("turn %d: a hex was granted on a tower with nobody to hex" % turns)
			if int(_mode.lives[0]) > 0 and _mode.winner_team < 0:
				survived += 1
			if int(_mode.storms) > storms_before:
				# A storm: cast as -1, at whoever flies next, on the beat.
				var e = _mode.queued_effects.back()
				var gap: int = survived - last_storm_at
				last_storm_at = survived
				if e.caster != -1:
					notes.append("turn %d: the storm's hex has caster %d, not -1" % [turns, e.caster])
				if e.target != _mode._next_turn_slot():
					notes.append("turn %d: the storm hexed P%d but P%d is up next" % [turns, e.target + 1, _mode._next_turn_slot() + 1])
				if gap != _mode.STORM_EVERY and gap != _mode.STORM_EVERY_HIGH:
					notes.append("turn %d: the storm came %d surviving turns after the last one" % [turns, gap])
				if _mode.slot_name(e.caster) != "THE STORM":
					notes.append("the storm is called '%s'" % _mode.slot_name(e.caster))
		var ended: bool = _mode.state == "gameover"
		var won: bool = _mode.winner_team == 0
		var height: float = _mode._height_cells()
		if not ended:
			notes.append("no result after %d turns" % turns)
		elif won and (int(_mode.lives[0]) <= 0 or height < _mode.goal_cells - _mode.GOAL_SLACK_CELLS):
			notes.append("won at height %.2f with %d lives" % [height, _mode.lives[0]])
		elif not won and int(_mode.lives[0]) > 0:
			notes.append("lost with %d lives left at height %.2f" % [_mode.lives[0], height])
		var want_title: String = "TOWER COMPLETE!" if won else "THE STORM WINS"
		if ended and _mode.overlay_title.text != want_title:
			notes.append("overlay says '%s', expected '%s'" % [_mode.overlay_title.text, want_title])
		if won:
			wins += 1
		total_turns += turns
		total_storms += int(_mode.storms)
		heights.append(int(_mode.best_height))
		for n in notes:
			_fail("co-op %dp seed %d: %s" % [count, m, n])
	print("  CO-OP %dp spread %.2f   reached the line %d/%d   turns %.1f   storms %.1f   best heights %s" % [
		count, spread, wins, MATCHES, float(total_turns) / MATCHES, float(total_storms) / MATCHES, heights])

# --- Race ---------------------------------------------------------------------

const RACE := preload("res://scenes/TowerRace.tscn")
var _race = null

func _spawn_race(count: int, seed_value: int) -> void:
	if _mode != null:
		_mode.queue_free()
		_mode = null
	if _race != null:
		_race.queue_free()
		_race = null
	await get_tree().physics_frame
	seed(seed_value)
	_rng.seed = seed_value
	GameSettings.mode = GameSettings.MODE_TOWER
	GameSettings.tower_variant = GameSettings.TOWER_RACE
	GameSettings.player_count = count
	var cols: Array[Color] = []
	for i in range(count):
		cols.append(GameSettings.PLAYER_SKINS[i]["color"])
	GameSettings.skin_colors = cols
	_race = RACE.instantiate()
	add_child(_race)
	await _wait_both_piloting()

func _wait_both_piloting() -> void:
	var t := 0.0
	while t < TURN_TIMEOUT:
		var ok := true
		for tw in _race.towers:
			if not (tw.state == "piloting" and tw.active_piece != null):
				ok = false
		if ok:
			return
		await get_tree().physics_frame
		t += get_physics_process_delta_time()

func _race_plumbing() -> void:
	await _spawn_race(4, 91)
	var L = _race.towers[0]
	var R = _race.towers[1]
	print("  members: left %s  right %s" % [L.members, R.members])
	if L.members != [0, 2] or R.members != [1, 3]:
		_fail("race: 4p towers hold %s and %s, expected [0, 2] and [1, 3]" % [L.members, R.members])
	if L.get_world_2d() == R.get_world_2d():
		_fail("race: both towers share one World2D — their bricks would collide")
	print("  separate worlds: %s   both flying at once: %s" % [
		L.get_world_2d() != R.get_world_2d(), L.state == "piloting" and R.state == "piloting"])
	if not (L.state == "piloting" and R.state == "piloting"):
		_fail("race: the towers are not both piloting after the countdown (%s / %s)" % [L.state, R.state])

	# A real key, through the real input pipeline: P1's right on the left
	# tower moves P1's brick and nobody else's.
	var lx: float = L.aim_x
	var rx: float = R.aim_x
	var ev := InputEventKey.new()
	ev.keycode = GameSettings.PLAYER_CONFIGS[0]["right"]
	ev.physical_keycode = ev.keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().physics_frame
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame
	var moved_l: bool = is_equal_approx(L.aim_x, lx + L.CELL * 0.5)
	var moved_r: bool = not is_equal_approx(R.aim_x, rx)
	print("  P1's right key: left tower %s, right tower %s" % ["moved half a cell" if moved_l else "DID NOT MOVE", "MOVED" if moved_r else "untouched"])
	if not moved_l or moved_r:
		_fail("race: a real key press did not reach exactly the left tower through the host")

	# A hex cast on the left lands on the right, on its next brick.
	L._grant(L.active_slot, "tremor")
	var cast: bool = L._cast(L.active_slot, "opponent")
	var landed: Array = []
	for e in R.queued_effects:
		landed.append("P%d from P%d" % [e.target + 1, e.caster + 1])
		if e.mode != R:
			_fail("race: the relayed hex is wired to the wrong tower")
	print("  hex from the left: cast %s, queued on the right %s, left queue %d" % [cast, landed, L.queued_effects.size()])
	if not cast or R.queued_effects.size() != 1 or not L.queued_effects.is_empty():
		_fail("race: a hex cast on the left did not land on (only) the right tower")
	elif R.queued_effects[0].target != R._next_turn_slot():
		_fail("race: the hex sits on P%d, but P%d flies the right tower's next brick" % [R.queued_effects[0].target + 1, R._next_turn_slot() + 1])

	# Same bricks, same order, on both towers. Each tower's spawns are logged
	# on its own clock — they do not take turns in step — and the common
	# prefix compared. Tremor rides the right tower's turn but never changes
	# a spawn, so it cannot excuse a difference.
	var seqs: Array = [[], []]
	var seen: Array = [null, null]
	# Dropped dead centre, three upright bricks can clear the line, which
	# ends the race before there is a sequence worth comparing — so the line
	# is moved out of reach for this check only.
	for tw in _race.towers:
		tw.goal_cells = 1000.0
	var t := 0.0
	while not _race.over and t < 120.0 and (seqs[0].size() < 8 or seqs[1].size() < 8):
		for side in range(2):
			var tw = _race.towers[side]
			if tw.state == "piloting" and tw.active_piece != null and tw.active_piece != seen[side]:
				seen[side] = tw.active_piece
				seqs[side].append(tw.active_piece.shape_index)
				tw.aim_x = 0.0
				tw.aim_steps = 0
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	var n: int = mini(seqs[0].size(), seqs[1].size())
	print("  bricks left  %s\n  bricks right %s" % [seqs[0], seqs[1]])
	if n < 3:
		_fail("race: only %d bricks to compare" % n)
	elif seqs[0].slice(0, n) != seqs[1].slice(0, n):
		_fail("race: the towers were dealt different bricks")

	# Restart: both towers back to the start, a new deal.
	_race.tower_finished(L) # stop it here, as a decided race would
	var seed_before: int = L.brick_seed
	_race._restart()
	await _wait_both_piloting()
	var clean: bool = L.lives[0] == L.RACE_LIVES and R.lives[1] == R.RACE_LIVES \
		and L.queued_effects.is_empty() and R.queued_effects.is_empty() and not _race.over \
		and L.brick_seed == R.brick_seed
	print("  restart: both flying %s, lives reset and queues empty %s, new deal %s" % [
		L.state == "piloting" and R.state == "piloting", clean, L.brick_seed != seed_before])
	if not clean:
		_fail("race: a restart did not put both towers back")

func _races(count: int, spread: float) -> void:
	var by_line := 0
	var by_lives := 0
	var seconds := 0.0
	for m in range(MATCHES):
		await _spawn_race(count, 9900 + m * 131 + count)
		var aimed := {} # tower -> the piece already aimed
		var t := 0.0
		while not _race.over and t < 900.0:
			for tw in _race.towers:
				if tw.state == "piloting" and tw.active_piece != null and aimed.get(tw) != tw.active_piece:
					aimed[tw] = tw.active_piece
					var keep = _mode
					_mode = tw
					_aim(spread)
					_mode = keep
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		seconds += t
		if not _race.over:
			_fail("race %dp seed %d: no result after %.0fs" % [count, m, t])
			continue
		var L = _race.towers[0]
		var R = _race.towers[1]
		var reached: Array[bool] = [L.winner_team >= 0, R.winner_team >= 0]
		var out: Array[bool] = [L._living_teams() == 0, R._living_teams() == 0]
		if reached.count(true) + out.count(true) != 1:
			_fail("race %dp seed %d: %d tower(s) reached the line and %d ran out — expected exactly one result" % [
				count, m, reached.count(true), out.count(true)])
		if reached.has(true):
			by_line += 1
		else:
			by_lives += 1
		if L.state != "gameover" or R.state != "gameover":
			_fail("race %dp seed %d: a tower is still running after the result (%s / %s)" % [count, m, L.state, R.state])
		var want_side: int = reached.find(true) if reached.has(true) else out.find(false)
		var want: String = "%s WINS" % GameSettings.tower_team_name(want_side, GameSettings.TOWER_RACE)
		if _race.overlay_title.text != want or not _race.overlay.visible:
			_fail("race %dp seed %d: overlay '%s' (visible %s), expected '%s'" % [count, m, _race.overlay_title.text, _race.overlay.visible, want])
	print("  RACE %dp spread %.1f   decided by the line %d, by lives %d   %.0fs of play a race" % [
		count, spread, by_line, by_lives, seconds / MATCHES])

# --- Co-pilot: the crew -----------------------------------------------------

func _key(slot: int, action: String) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = GameSettings.PLAYER_CONFIGS[slot][action]
	ev.physical_keycode = ev.keycode
	_mode.handle_key(ev)

func _copilot_crew() -> void:
	await _spawn(GameSettings.TOWER_COPILOT, 4, 71)

	# Who steers and who turns, over four crew turns: the left crew, the
	# right crew, then both again the other way round.
	var crews: Array[String] = []
	for i in range(4):
		await _wait_piloting()
		crews.append("P%d+P%d" % [_mode.active_slot + 1, _mode.crew_mate + 1])
		if i == 0:
			await _copilot_keys()
		_mode.aim_x = 0.0
		_mode.aim_steps = 0
		var before: Array = _mode.charge.duplicate()
		var pilot: int = _mode.active_slot
		var mate: int = _mode.crew_mate
		var fell: int = await _finish_turn()
		if i == 0:
			print("  first crew drop: %s — charge P%d %d->%d, P%d %d->%d" % [
				"clean" if fell == 0 else "%d fell" % fell, pilot + 1, before[pilot], _mode.charge[pilot], mate + 1, before[mate], _mode.charge[mate]])
		if fell == 0 and i == 0:
			if int(_mode.charge[pilot]) != int(before[pilot]) + 1 or int(_mode.charge[mate]) != int(before[mate]) + 1:
				_fail("co-pilot: a clean drop paid P%d %d->%d and P%d %d->%d, expected both +1" % [
					pilot + 1, before[pilot], _mode.charge[pilot], mate + 1, before[mate], _mode.charge[mate]])
	print("  crews (steer+turn): %s" % [crews])
	if crews != ["P1+P3", "P2+P4", "P3+P1", "P4+P2"]:
		_fail("co-pilot: crews went %s, expected P1+P3, P2+P4, P3+P1, P4+P2" % [crews])
	if _mode._hex_targets(0, true) != [_mode._pilot_of(1)]:
		_fail("co-pilot: an all-opponents hex hit %s, expected one copy on the right crew's next pilot" % [_mode._hex_targets(0, true)])

	# A two-turn skill cast by the crew mate rides the crew's *next* turn
	# too, though the other member is steering it by then.
	await _spawn(GameSettings.TOWER_COPILOT, 4, 72)
	await _wait_piloting()
	_mode._grant(2, "tailor")
	var cast: bool = _mode._cast(2, "self") # P3 turning, P1 steering
	if not cast:
		_fail("co-pilot: the crew mate's self cast was refused")
		return
	var seen_on: Array[String] = []
	for i in range(4):
		await _wait_piloting()
		for e in _mode.active_effects:
			if e.id == "tailor":
				seen_on.append("turn %d on P%d (steering P%d)" % [i, e.target + 1, _mode.active_slot + 1])
				if _mode.team_of[_mode.active_slot] == 0 and e.target != _mode.active_slot:
					_fail("co-pilot: on the left crew's turn %d the tailor sat on P%d, not the pilot P%d" % [i, e.target + 1, _mode.active_slot + 1])
		_mode.aim_x = 0.0
		_mode.aim_steps = 0
		await _finish_turn()
	print("  tailor cast by P3: %s" % [seen_on])
	var left_turns_seen := 0
	for s in seen_on:
		if s.contains("steering P1") or s.contains("steering P3"):
			left_turns_seen += 1
	if left_turns_seen != 2:
		_fail("co-pilot: a two-turn skill was live on %d of the crew's turns, expected 2" % left_turns_seen)
	if not _mode.active_effects.is_empty():
		_fail("co-pilot: %d effect(s) still live after the crew's two turns" % _mode.active_effects.size())

# P1 steers and P3 turns. Each one's keys for the other job must do nothing.
func _copilot_keys() -> void:
	var cell: float = _mode.CELL
	var x0: float = _mode.aim_x
	var r0: int = _mode.aim_steps
	_key(0, "skill_self") # the pilot's own rotate key
	var pilot_rotated: bool = _mode.aim_steps != r0
	_key(2, "skill_self") # the crew mate's
	var mate_rotated: bool = _mode.aim_steps == r0 + 1
	_key(2, "right") # the crew mate's steer key
	var mate_steered: bool = not is_equal_approx(_mode.aim_x, x0)
	_key(0, "right") # the pilot's
	var pilot_steered: bool = is_equal_approx(_mode.aim_x, x0 + cell * 0.5)
	print("  pilot P1 rotate key: %s   crew mate P3 rotate key: %s" % ["TURNED" if pilot_rotated else "ignored", "turned" if mate_rotated else "IGNORED"])
	print("  crew mate P3 steer key: %s   pilot P1 steer key: %s" % ["MOVED" if mate_steered else "ignored", "moved half a cell" if pilot_steered else "DID NOT MOVE"])
	if pilot_rotated or not mate_rotated or mate_steered or not pilot_steered:
		_fail("co-pilot: the key split is wrong (see the two lines above)")

func _report(what: String, got: bool, want: bool) -> void:
	print("  %-46s %s" % [what, "accepted" if got else "refused"])
	if got != want:
		_fail("teams: %s was %s" % [what, "accepted" if got else "refused"])
