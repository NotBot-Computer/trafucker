extends RefCounted
class_name BotDriver

## Drives one PlayerBoard without a keyboard.
##
## The bot reads exactly what a human reads off that board — where the traffic
## is, how fast it is closing, which cars are blinking a merge — and writes
## exactly what a human writes: a steering hold, a dash, a boost hold, a skill
## pick. It never synthesises InputEvents and never touches the Input
## singleton, because those are global: a fake "A pressed" would be seen by
## every board bound to A and would fight a real player's fingers. Instead
## PlayerBoard routes its own input reads through _steer_held() / _press_steer()
## / _press_confirm(), and the bot calls those, so one board can be handed back
## and forth between a bot and a human mid-round (Main's 1-4 keys) with no other
## machinery involved.
##
## Everything it senses comes from obstacle_container's children and the same
## "lane"/"speed_mult"/"lc_*" meta keys the traffic systems already maintain
## (see PlayerBoard), so it stays correct for taxis and lane-changers for free
## instead of needing a parallel view of the world.
##
## `board` is deliberately left untyped: PlayerBoard names BotDriver as a
## field type, and naming PlayerBoard back here would make that a cyclic class
## reference.

enum Difficulty { EASY, NORMAL, HARD }

const DIFFICULTY_NAMES := ["EASY", "NORMAL", "HARD"]

# Per-difficulty knobs. These are what make a bot beatable rather than
# perfect: a bot with unlimited foresight and zero latency is no fun to race,
# so the levels differ in how far ahead it plans and how late and how sloppily
# it acts — not in what it is allowed to see.
#
#   decision_interval - seconds between routine "which lane do I want" passes
#   reaction_time     - floor on how fast an emergency can preempt that pass
#   panic_tti         - time-to-impact that counts as an emergency
#   horizon           - how far ahead it plans, in seconds; also the score cap
#   lookahead         - how many lane changes deep it plans (see _survival)
#   aim_error         - fraction of a lane width its chosen line is off by
#   blunder_chance    - odds a routine pass takes the 2nd-best lane instead
#   boost_min_tti     - how clear the road must look before it spends boost
#   skill_delay       - how long it dithers over a skill choice, in seconds
const PROFILES: Array[Dictionary] = [
	{
		"decision_interval": 0.32, "reaction_time": 0.30, "panic_tti": 0.60,
		"horizon": 2.0, "lookahead": 1, "aim_error": 0.22, "blunder_chance": 0.22,
		"use_dash": false, "use_boost": false, "boost_min_tti": 99.0,
		"weave_for_boost": false, "skill_delay": 1.4,
	},
	{
		"decision_interval": 0.15, "reaction_time": 0.13, "panic_tti": 0.95,
		"horizon": 3.6, "lookahead": 2, "aim_error": 0.08, "blunder_chance": 0.05,
		"use_dash": true, "use_boost": true, "boost_min_tti": 2.6,
		"weave_for_boost": false, "skill_delay": 0.8,
	},
	{
		"decision_interval": 0.08, "reaction_time": 0.06, "panic_tti": 1.30,
		"horizon": 5.2, "lookahead": 3, "aim_error": 0.015, "blunder_chance": 0.0,
		"use_dash": true, "use_boost": true, "boost_min_tti": 2.0,
		"weave_for_boost": true, "skill_delay": 0.35,
	},
]

const MAX_TTI := 99.0 # stands in for "nothing is coming" so scores stay comparable
const LATERAL_MARGIN := 5.0 # px of side clearance demanded on top of the two half-widths

# Lane scoring. The headline term is survival time in seconds (see _survival),
# so everything else is expressed in seconds too and can just be added to it.
const TRAVEL_WEIGHT := 0.55 # how much the trip to a lane counts against it
const CROSS_MARGIN := 0.18 # slack demanded on top of the travel time itself
# Steering through a lane somebody is currently occupying is a certain crash,
# so this has to outweigh the very worst a dead end can score (a whole
# horizon's shortfall at DEAD_END_WEIGHT). It did not, once — and the bot
# reacted to being trapped in a lane by driving straight through the car in
# the next one, because a guaranteed collision was priced below a probable
# one. Never let these two scales overlap.
const BLOCKED_PENALTY := 100.0
const STAY_BONUS := 0.35 # inertia, so it doesn't dither between two equal lanes
const CENTER_BONUS := 0.4 # middle lanes leave an escape on both sides
const PICKUP_BONUS := 0.9 # only ever added to a lane that survives the full horizon
# How the two halves of a lane's worth combine. Room (its own time-to-impact)
# is the ranking signal, because it saturates at nothing and orders every
# lane on an open road. Survival is the veto: it saturates at the horizon, so
# on an open road it says the same thing about every lane and can only ever
# be a tie-break — an earlier version had it the other way round and the bot
# sat in a lane watching a car close on it from 1.7s to 0.1s, because leaving
# was worth nothing while staying was worth a 0.35 inertia bonus. What
# survival is genuinely good at is spotting the dead end: a lane whose branch
# runs out before the horizon is bad however roomy it looks this instant, and
# that shortfall is what gets charged for.
const DEAD_END_WEIGHT := 2.0
# An escape it can only just make is worth much less than one it can take at
# leisure. Without this the escape test is a step function — a lane looks
# perfectly safe right up to the frame the window to leave it shuts, and then
# loses a whole horizon of value at once. Charging for thin slack turns that
# cliff into a slope the bot can steer down, i.e. it leaves early.
const ESCAPE_SLACK_REF := 0.4 # slack (seconds) at which an escape is fully comfortable
const MARGINAL_ESCAPE_WEIGHT := 3.0

const STEER_DEADZONE_FRAC := 0.07 # fraction of a lane width that counts as "arrived"
const DASH_TTI := 0.75 # only worth burning a dash when it is this close
const BOOST_MIN_CHARGE := 0.15 # not worth starting a burn below this
const SKILL_PRESSURE_TTI := 1.2 # under this, take the skill that saves you

# Weaving inside your own lane is the only way to charge the boost bar (a
# drift needs a genuine velocity reversal — see PlayerBoard._try_start_drift),
# so a bot that wants boost has to wag the wheel for it exactly like a player
# farming the bar does. It has to stay strictly inside its own lane to be
# free, which is what the first two of these are for — an earlier version
# reversed on a fixed half-period instead, and at this steering response that
# let the car build up most of a lane width of swing and fling itself into the
# next lane. Reverse on distance travelled, never on a clock.
const WEAVE_AMPLITUDE_FRAC := 0.12 # fraction of a lane width the wag swings either side
const WEAVE_ABORT_FRAC := 0.22 # momentum carried further out than this: stop and re-centre
const WEAVE_MAX_HOLD := 0.4 # fallback flip, for the case where the car cannot move at all
const WEAVE_CLEARANCE_FRAC := 0.6 # how far either side must ALSO be clear before wagging
const WEAVE_MIN_TTI := 2.6 # only ever done on a genuinely empty road

var board # the PlayerBoard being driven — untyped on purpose, see above
var difficulty: int = Difficulty.NORMAL

var steer: int = 0 # -1 / 0 / 1, mirrors board.bot_steer
var target_x: float = 0.0 # the line it is currently driving toward
var decision_age: float = 0.0 # seconds since the last lane decision
var skill_timer: float = -1.0 # < 0 means "no choice pending"
var weave_dir: int = 1
var weave_timer: float = 0.0

func _init(target_board, level: int = Difficulty.NORMAL) -> void:
	board = target_board
	set_difficulty(level)
	reset()

func set_difficulty(level: int) -> void:
	difficulty = clampi(level, 0, PROFILES.size() - 1)

func difficulty_name() -> String:
	return DIFFICULTY_NAMES[difficulty]

# Cycling lives here rather than in GameSettings so the number of profiles
# stays this file's business alone — both screens that offer the difficulty key
# just hand their stored level through it.
static func next_difficulty(level: int) -> int:
	return (level + 1) % PROFILES.size()

func profile() -> Dictionary:
	return PROFILES[difficulty]

# Called from PlayerBoard.start_round() so a bot doesn't carry a stale plan
# (or a held steering direction) across a restart.
func reset() -> void:
	steer = 0
	if board != null:
		board.bot_steer = 0
		target_x = board.car_x
	decision_age = 999.0 # forces a decision on the very first tick
	skill_timer = -1.0
	weave_timer = 0.0

# One frame of thinking, called from PlayerBoard._process BEFORE that frame's
# steering/physics reads any of it.
func tick(delta: float) -> void:
	if board == null:
		return
	var ctx := _context()

	_update_skill_choice(delta, ctx)

	# A dash is a committed, uninterruptible one-lane hop that ignores
	# steering entirely while it runs — nothing to decide until it lands.
	if board.is_dashing:
		return

	_update_plan(delta, ctx)
	_update_steering(delta, ctx)
	_update_actions(ctx)

# --- Sensing ---------------------------------------------------------------

# Everything one tick's worth of thinking needs, gathered once. The traffic
# snapshot matters most: the planner below replays it forward in time over and
# over, and re-reading the live nodes for each replay would be both slower and
# wrong — they are only ever at t = 0.
func _context() -> Dictionary:
	var speed: float = board.current_speed()
	var snap: Array = []
	for child in board.obstacle_container.get_children():
		# SkillPickups share this container but are collectibles, not hazards
		# (see PlayerBoard._on_player_area_entered) — they are scored
		# separately in _pickup_in_lane.
		if not (child is Car):
			continue
		# A blinking car is telling you where it is about to be, and planning
		# against that instead of where it currently sits is most of what
		# makes this look like it saw the merge coming. Both positions count
		# as occupied for the whole maneuver, which is the conservative read.
		var merge_x: float = child.position.x
		var lc: String = child.get_meta("lc_state", "idle")
		if lc == "warning" or lc == "moving":
			merge_x = float(child.get_meta("lc_to_x", child.position.x))
		snap.append({
			"x": child.position.x, "merge_x": merge_x, "y": child.position.y,
			"hw": child.width * 0.5, "hh": child.height * 0.5,
			# Traffic runs a positive mult and closes from above; a taxi runs a
			# negative one and closes from behind (see PlayerBoard's TAXI_
			# constants). Keeping the sign here means the rest of the planner
			# never has to care which kind it is looking at.
			"vy": speed * float(child.get_meta("speed_mult", 1.0)),
		})
	return {
		"sz": board.car_size(),
		"car_y": board.player_car.position.y,
		"lane_w": board.road.lane_width(),
		"top_speed": max(board.steer_top_speed(), 1.0),
		"horizon": float(profile()["horizon"]),
		"snap": snap,
	}

# Seconds from time `t` until a car parked at x would be hit, replaying the
# snapshot forward to that moment. 0.0 means x is occupied at t already.
func _threat_at(x: float, t: float, ctx: Dictionary) -> float:
	var sz: Vector2 = ctx["sz"]
	var car_y: float = ctx["car_y"]
	var front: float = car_y - sz.y * 0.5
	var back: float = car_y + sz.y * 0.5
	var worst := MAX_TTI
	for o in ctx["snap"]:
		var reach: float = float(o["hw"]) + sz.x * 0.5 + LATERAL_MARGIN
		if abs(float(o["x"]) - x) >= reach and abs(float(o["merge_x"]) - x) >= reach:
			continue
		var vy: float = float(o["vy"])
		var hh: float = float(o["hh"])
		var y: float = float(o["y"]) + vy * t
		var gap_ahead: float = front - (y + hh)
		var gap_behind: float = (y - hh) - back
		var tti: float
		if gap_ahead <= 0.0 and gap_behind <= 0.0:
			tti = 0.0 # level with us at time t — this line is taken
		elif gap_ahead > 0.0:
			tti = MAX_TTI if vy <= 0.0 else gap_ahead / vy
		else:
			tti = MAX_TTI if vy >= 0.0 else gap_behind / -vy
		if tti < worst:
			worst = tti
			if worst <= 0.0:
				break
	return worst

func _pickup_in_lane(x: float, ctx: Dictionary) -> bool:
	var sz: Vector2 = ctx["sz"]
	for child in board.obstacle_container.get_children():
		if not (child is SkillPickup):
			continue
		if child.position.y > float(ctx["car_y"]): # already gone past
			continue
		if abs(child.position.x - x) < sz.x * 0.5 + child.radius:
			return true
	return false

# --- Planning --------------------------------------------------------------

# How long the bot can stay alive starting from x at time t, allowed `depth`
# more lane changes, capped at the horizon.
#
# This is the whole difference between a bot that races and one that dies
# staring at the road: scoring a lane by its own time-to-impact alone is a
# greedy read that happily parks in the roomiest lane while the lanes either
# side of it fill in, and then has nowhere to go. Asking instead "and when
# that car finally reaches me, is there anywhere left to be?" is what makes it
# leave a comfortable lane early, while there is still a way out of it.
#
# Only single-lane hops are explored, so no branch can quietly assume it may
# cut across a lane nobody checked — the same thing _corridor_penalty guards
# against for the opening move.
func _survival(x: float, t: float, depth: int, ctx: Dictionary) -> float:
	var horizon: float = ctx["horizon"]
	var tti: float = _threat_at(x, t, ctx)
	var fails_at: float = t + tti
	if fails_at >= horizon or depth <= 0:
		return min(fails_at, horizon)

	var lane_w: float = ctx["lane_w"]
	var top_speed: float = ctx["top_speed"]
	var best := fails_at
	for lane in range(board.lane_count):
		var lx: float = board.road.lane_center_x(lane)
		var step: float = abs(lx - x)
		if step < 1.0 or step > lane_w * 1.6:
			continue
		var slack: float = tti - (step / top_speed + CROSS_MARGIN)
		if slack < 0.0:
			continue # no time left to get out that way
		var escaped: float = _survival(lx, fails_at, depth - 1, ctx)
		escaped -= max(0.0, ESCAPE_SLACK_REF - slack) * MARGINAL_ESCAPE_WEIGHT
		if escaped > best:
			best = escaped
			if best >= horizon:
				break
	return min(best, horizon)

func _update_plan(delta: float, ctx: Dictionary) -> void:
	decision_age += delta
	var p := profile()
	var due: bool = decision_age >= float(p["decision_interval"])
	var urgent: bool = _threat_at(target_x, 0.0, ctx) < float(p["panic_tti"])
	# Routine passes run on the interval; something suddenly closing on the
	# line it had already committed to can jump the queue, but never faster
	# than the profile's reaction time — that floor is the whole reason an
	# EASY bot is survivable to race against.
	if not due and not (urgent and decision_age >= float(p["reaction_time"])):
		return
	decision_age = 0.0
	target_x = _choose_target_x(ctx)

func _choose_target_x(ctx: Dictionary) -> float:
	var p := profile()
	var depth: int = int(p["lookahead"])
	var lane_w: float = ctx["lane_w"]
	var top_speed: float = ctx["top_speed"]
	var horizon: float = ctx["horizon"]
	var car_x: float = board.car_x
	var half_board: float = max(board.board_width * 0.5, 1.0)

	var scored: Array = []
	for lane in range(board.lane_count):
		var lx: float = board.road.lane_center_x(lane)
		var travel: float = abs(lx - car_x) / top_speed
		var here: float = _threat_at(lx, 0.0, ctx)
		# Room to breathe, minus what the lookahead says this lane costs you
		# later — see DEAD_END_WEIGHT for why it is this way round.
		var score: float = min(here, horizon)
		score -= (horizon - _survival(lx, 0.0, depth, ctx)) * DEAD_END_WEIGHT
		# You cannot take a gap you cannot physically reach before it shuts...
		if here < travel + CROSS_MARGIN:
			score -= BLOCKED_PENALTY
		# ...nor one whose only route runs through somebody's back bumper.
		score -= _corridor_penalty(lane, ctx)
		score -= travel * TRAVEL_WEIGHT
		if abs(lx - car_x) < lane_w * 0.5:
			score += STAY_BONUS
		score += CENTER_BONUS * (1.0 - abs(lx - half_board) / half_board)
		# Only chase a pickup down a lane that was already going to hold up.
		if here >= horizon - 0.01 and _pickup_in_lane(lx, ctx):
			score += PICKUP_BONUS
		scored.append({"x": lx, "score": score})

	scored.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var pick: Dictionary = scored[0]
	if scored.size() > 1 and randf() < float(p["blunder_chance"]):
		pick = scored[1]

	# Settling a little off the lane center (rather than dead on it every
	# single time) is what stops a bot reading as a machine, and on the
	# easier profiles it is also what eventually gets it killed.
	var aim: float = float(pick["x"]) + randf_range(-1.0, 1.0) * float(p["aim_error"]) * lane_w
	var bounds: Vector2 = board.steer_bounds()
	return clamp(aim, bounds.x, bounds.y)

# Cost of the lanes it would have to cross on the way, which is what stops it
# aiming at a lovely empty lane three over with a truck parked in between.
func _corridor_penalty(target_lane: int, ctx: Dictionary) -> float:
	var cur_lane: int = board._nearest_lane(board.car_x)
	if abs(target_lane - cur_lane) < 2:
		return 0.0
	var top_speed: float = ctx["top_speed"]
	var step: int = signi(target_lane - cur_lane)
	var penalty := 0.0
	var lane: int = cur_lane + step
	while lane != target_lane:
		var lx: float = board.road.lane_center_x(lane)
		var cross_t: float = abs(lx - board.car_x) / top_speed
		if _threat_at(lx, 0.0, ctx) < cross_t + CROSS_MARGIN:
			penalty += BLOCKED_PENALTY
		lane += step
	return penalty

# --- Acting ----------------------------------------------------------------

func _update_steering(delta: float, ctx: Dictionary) -> void:
	var p := profile()
	var lane_w: float = ctx["lane_w"]
	# Steer against where the car is *going* to be, not where it is: momentum
	# keeps carrying it for steer_coast_time() after the input stops, and
	# aiming at the present position instead just oscillates around the lane.
	var predicted: float = board.car_x + board.car_vx * board.steer_coast_time()
	var err: float = target_x - predicted
	var offset: float = board.car_x - target_x
	var side: float = lane_w * WEAVE_CLEARANCE_FRAC
	# Both shoulders of the wag have to be clear, not just the line it is
	# sitting on — a wag between two occupied lanes is just a slow crash.
	var can_weave: bool = bool(p["weave_for_boost"]) \
		and abs(offset) < lane_w * WEAVE_ABORT_FRAC \
		and board.boost_charge < 1.0 and not board.boost_active \
		and not board.tank_mode_active \
		and _threat_at(board.car_x, 0.0, ctx) > WEAVE_MIN_TTI \
		and _threat_at(board.car_x - side, 0.0, ctx) > WEAVE_MIN_TTI \
		and _threat_at(board.car_x + side, 0.0, ctx) > WEAVE_MIN_TTI
	if can_weave:
		weave_timer += delta
		if offset * float(weave_dir) > lane_w * WEAVE_AMPLITUDE_FRAC or weave_timer > WEAVE_MAX_HOLD:
			weave_dir = -weave_dir
			weave_timer = 0.0
		_set_steer(weave_dir)
		return
	weave_timer = 0.0

	if abs(err) <= lane_w * STEER_DEADZONE_FRAC:
		_set_steer(0)
	else:
		_set_steer(1 if err > 0.0 else -1)

func _set_steer(direction: int) -> void:
	if direction == steer:
		return
	steer = direction
	board.bot_steer = direction
	if direction != 0:
		# Exactly what the keyboard path does on a key going down: sets the
		# both-keys tiebreak and starts a drift on a genuine reversal. Dash
		# taps are suppressed because the bot asks for a dash outright below
		# — otherwise its own corrections (and its weaving) would keep firing
		# unwanted ones off through _register_tap's double-tap window.
		board._press_steer(direction, false)

func _update_actions(ctx: Dictionary) -> void:
	var p := profile()

	if board.tank_mode_active:
		# While transformed, confirm is the cannon rather than boost (see
		# PlayerBoard._press_confirm) — so shoot whatever is in front.
		if board.cannon_ready and board._find_cannon_target() != null:
			board._press_confirm()
		return

	var here: float = _threat_at(board.car_x, 0.0, ctx)

	# A dash is a fast eased hop exactly one lane over — the right tool only
	# when the gap it wants is one lane away and there is no longer time to
	# steer there normally. Drifting blocks it anyway (see _try_start_dash),
	# so don't bother asking mid-slide.
	var lane_w: float = ctx["lane_w"]
	var gap: float = target_x - board.car_x
	if bool(p["use_dash"]) and not board.is_drifting and board.dash_cooldown_timer <= 0.0 \
		and here < DASH_TTI and abs(gap) > lane_w * 0.55 and abs(gap) < lane_w * 1.6:
		board._try_start_dash(1 if gap > 0.0 else -1)
		return

	# Boost multiplies the whole road speed, which also means the traffic
	# arrives sooner — so it is only spent on a lane that already looks clear
	# well past the profile's own horizon. current_speed() already includes
	# the multiplier while burning, so `here` shrinks as it goes and the burn
	# calls itself off before it runs the bot into anything.
	var want_boost: bool = bool(p["use_boost"]) and board.boost_charge > BOOST_MIN_CHARGE \
		and here > float(p["boost_min_tti"])
	if want_boost and not board.boost_active:
		board._press_confirm()
	elif not want_boost and board.boost_active:
		board._release_confirm()

func _update_skill_choice(delta: float, ctx: Dictionary) -> void:
	if not board.choosing_skill:
		skill_timer = -1.0
		return
	if skill_timer < 0.0:
		# A choice never expires (a deliberate design rule — see
		# PROJECT_STATE §6/§7), so the bot is free to think about it. Taking
		# a beat also means anyone watching actually gets to see the icons
		# come up instead of them blinking straight back out.
		skill_timer = float(profile()["skill_delay"]) * randf_range(0.7, 1.3)
	skill_timer -= delta
	if skill_timer > 0.0:
		return
	skill_timer = -1.0
	# Boxed in, take the side that might save you; with room to breathe,
	# spend it on the others. This was written when SELF_SKILLS held one
	# entry and "self" meant Tank Mode, i.e. certain temporary
	# invincibility. It is now a five-entry pool and the roll is made before
	# the pick (_roll_pending_skills), so "self" is a rescue only some of the
	# time — the bot does not read pending_self_skill to find out. Left as a
	# coin-weighting rather than a lookup on purpose: it plays the odds the
	# way a player who hasn't looked at the icon would, and nothing about
	# this heuristic has been tuned against real skills yet.
	var pressured: bool = _threat_at(board.car_x, 0.0, ctx) < SKILL_PRESSURE_TTI
	board._resolve_skill_choice("self" if pressured or randf() < 0.45 else "opponent")
