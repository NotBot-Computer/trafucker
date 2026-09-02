extends SkillEffect

## DETOUR (catalog id "roadblock") — an opponent skill that closes the road.
##
## Roadworks barriers arrive on the victim's board in lines, each line
## shutting every lane but one, and the victim has to find the gap. Two or
## three lines over the skill's window, spaced out so each is its own problem
## rather than a wall of them at once.
##
## ## Why static geometry
##
## The Taxi (§5 sessions I/L) is the only other opponent skill that adds
## something to the rival's road, and it is a *vehicle*: it has an AI, it
## roams, it makes decisions. A second one of those with a different sprite
## would be the same idea twice. Oil Slick went the other way and added
## nothing to the world at all, attacking control instead. This one sits
## between them: it adds things to the road, but they are furniture, not
## traffic. A barrier does not drive, does not think and does not change its
## mind. The whole challenge is *reading* the line early enough to be in the
## right lane when it gets to you — which is a different skill from dodging
## a cab that is trying to be where you are.
##
## ## Every barrier is an ordinary Car, and that is the design
##
## Each barrier is built with board.CAR_SCENE.instantiate(), added to
## board.obstacle_container, textured with the barrier PNG and tagged with
## the same "lane"/"speed_mult" metas every other child of that container
## carries (the §7 invariant for anything living in there). Nothing in this
## file moves, culls or collides a barrier, ever. That is not laziness, it is
## the load-bearing decision of the skill:
##   * the shared obstacle loop in PlayerBoard._process scrolls them at
##     speed * speed_mult, exactly as it scrolls the traffic;
##   * the same loop culls them past OBSTACLE_DESPAWN_MARGIN;
##   * hitting one goes through _on_player_area_entered like hitting a van —
##     it costs a life, Tank Mode crushes it, Nitro flies over it, the
##     invulnerability window passes through it;
##   * BotDriver senses them as obstacles for free, because it reads that
##     container and those metas and nothing else;
##   * _lanes_used_near_top() sees a fresh barrier and holds traffic spawns
##     out of its lane while it is near the top — which is what leaves a
##     pocket of clear road *behind* every barrier for the victim to slide
##     into once they are through the gap;
##   * a taxi driving up into a barrier gets clamped by _taxi_follow_limit
##     to the barrier's mult and queues behind it, like a cab meeting
##     roadworks.
## The taxi's history (session I: "it was moving on a private code path, so
## it could not be fixed from within that path") is the reason no private
## path exists here. Anything bespoke written instead of the shared loop
## would be a second copy of that bug waiting for its session.
##
## speed_mult is 1.0 — the closing-speed *fraction* explained above
## GameSettings.TRAFFIC_KINDS. A vehicle at 1.0 would be parked; a barrier
## IS parked. It is bolted to the road and scrolls at exactly the road's own
## rate, the same value _spawn_skill_pickup gives a pickup, and for the same
## reason. That also makes a barrier the fastest-closing thing on the board,
## which is what most of the placement logic below is about.
##
## ## Fairness (§5 session D's rule: hard is fine, cheap is not)
##
##   1. There is always a gap. A line is never a full wall, and no code path
##      here can produce one — the gap lane is simply never given a barrier.
##   2. The gap walks. Consecutive gaps are within GAP_WALK_MAX lanes of each
##      other (and the first is within that of the victim's own lane), so the
##      victim can always get across in the time a line takes to arrive.
##   3. The gap is a real gap. Before a line is laid, the gap lane is checked
##      for traffic that would be level with the line when it reaches the
##      victim — a hole with a sedan parked in it is a wall with extra steps.
##      That check is not the 190px _lanes_used_near_top() strip, and the
##      comment on _lane_open_at_arrival says why.
##   4. Lines are spaced. LINE_INTERVAL seconds apart, timed rather than
##      spaced in pixels, so the victim's experience — how long they get
##      between problems — is the same at 160px/s as at 560.
##   5. Nothing is dropped into a crowd. A line that cannot be laid fairly
##      right now waits (see _slip), and a line that could not arrive before
##      the HUD bar runs out is not laid at all — the bar is a promise about
##      the road, not about the spawner.
##
## ## What deactivate() does not do
##
## Barriers already on the road are left there. They belong to the road the
## moment they are spawned, and the shared loop culls them off the bottom
## edge like everything else; freeing them from here would make a line
## vanish mid-screen when the bar ended, and on a round restart the whole
## container is wiped underneath us anyway. The only references this file
## keeps (one Car per in-flight line, for _hold_merges_near_lines) are read
## through is_instance_valid and dropped in deactivate(), so nothing here can
## outlive the round it was spawned in.

# --- Timing -------------------------------------------------------------------

# The window during which lines are laid. Long enough for three lines at
# LINE_INTERVAL with a lead-in, and — because a line may only be laid if it
# will *arrive* inside the window (see _try_lay_line) — long enough that the
# third line still fits on a mid-round road. At the ramp's 160px/s opening
# speed a line takes ~3.7s to reach the victim, so the last line has to be
# born by about 3.3s in; at 560px/s it takes ~1.1s. Seven seconds gives three
# lines from roughly 25s into a round onward and two before that, which is
# the "two or three" the design asks for, decided by the road rather than a
# dice roll. Sits at the top of the Tank (6.0) / Slick (5.0) bracket because
# most of this window is *waiting for barriers to arrive*, not being hurt.
const DURATION := 7.0

# Lead-in before the first line. The landing flash (FLASH_DURATION) has to
# have been on screen long enough to be read as "something is coming" before
# the first barriers enter under it, or the flash explains nothing.
const FIRST_LINE_DELAY := 0.4

# Seconds between one line being laid and the next. Measured from the actual
# spawn (not the scheduled one), so a line that had to wait does not drag the
# next one in on top of it. 1.9s is: the previous line's travel to the
# victim (1.1–3.7s, so at high speed it has arrived and been solved, at low
# speed it is still descending but well separated), plus a two-lane move
# (~0.4s) plus reaction. Below ~1.4 two lines are on screen close enough to
# read as one object with two gaps in it, which is a puzzle, not a detour.
const LINE_INTERVAL := 1.9

# How long a due line may wait for the barrier lanes to be clear of traffic
# it would visibly drive through (the cosmetic constraint — see
# _barrier_lane_conflicts) before that constraint is dropped and the line is
# laid anyway. The *gap* constraint is never dropped, whatever the wait.
# 1.2s is about one traffic spawn interval mid-round: long enough for the
# lane picture to change, short enough that the skill still lands as three
# separate beats rather than one late pile.
const LINE_SLIP_MAX := 1.2

# --- The gap ------------------------------------------------------------------

# How far, in lanes, the next gap may sit from the last one (and the first
# from the victim's own lane). At the ramp's top speed a line crosses the
# board in ~1.1s; a two-lane move at MAX_STEER_SPEED is ~0.42s plus reaction,
# so two lanes is the widest walk the victim can always make. One would be
# fairer still but reads as a metronome — the gap steps one lane over every
# time and the victim stops looking.
const GAP_WALK_MAX := 2

# On a road this wide or wider a line leaves two adjacent lanes open instead
# of one. Five lanes with one gap is four barriers and one hole, which is
# already most of the road; on seven, one lane out of seven is a keyhole. The
# board ships at five, so today this never fires — it is here so lane_count
# can be raised without the skill silently becoming unfair.
const WIDE_BOARD_LANES := 7

# How long the gap must already be *visibly* open before the line reaches
# the victim, when a car in the gap lane is being left behind by the line
# (the line closes at 1.0, everything else at less, so the line overtakes
# every car ahead of it). A hole that opens the instant it is needed cannot
# be aimed for. 0.6s is two ordinary lane changes' worth of warning.
const GAP_OPEN_LEAD := 0.6

# The mirror case: a car in the gap lane that gets to the victim *before* the
# line does. The victim has to leave the lane to dodge it and be back in it
# when the line arrives, so the car must have passed this long before the
# line. Longer than GAP_OPEN_LEAD because it is two moves, not one.
const GAP_REENTER_LEAD := 0.8

# --- The barrier --------------------------------------------------------------

const BARRIER_TEXTURE := preload("res://sprites/skills/barrier.png")

# Fed to board._car_size() like a TRAFFIC_KINDS entry. width_frac is a
# fraction of lane width; height_frac multiplies the *computed width* (not the
# lane), so it is the art's own aspect ratio and nothing else — the sprite is
# 48x20, 20/48 = 0.4167, and Car._rebuild() scales each axis independently so
# any other number stretches the stripes.
#
# width_frac 1.0, edge to edge, and that is deliberate: a lane closure spans
# its lane, and two neighbouring barriers meeting end to end is what a real
# row of them looks like. Car's collision box is 80% of the drawn width, so
# the hit boxes of two adjacent barriers leave a ~11px seam on a 53px lane —
# far less than the player's own 27px box, so straddling the line between
# two closed lanes is not a way through. (The painted shoulder is a
# different matter, and not this file's to fix — see the note in
# _lay_line.)
const BARRIER_KIND := {"width_frac": 1.0, "height_frac": 0.4167}

# Vertical clearance above the barrier's own height that the spawn point
# sits past the visible top edge. Matches the 40px _spawn_obstacle() and
# _spawn_skill_pickup() both use (as a literal there, so this is a copy by
# necessity rather than by preference — if it ever gets a name in
# PlayerBoard, read that instead).
const SPAWN_CLEARANCE := 40.0

# --- The warning flash --------------------------------------------------------

# A hazard-stripe band across the top edge of the road that pulses as the
# skill lands, then fades. It is the only tell before the first barriers
# enter, and it is deliberately short and deliberately at the top: it says
# *where to look*, and then gets out of the way so the barriers can be the
# message. 0.9s with three pulses reads as an alarm; one long fade read as a
# UI element that had failed to go away.
const FLASH_DURATION := 0.9
const FLASH_PULSES := 3.0

# A shorter, single pulse of the same band each time a further line is laid,
# so the victim who is busy threading the first one still gets told another
# is entering. Quieter than the landing flash (see FLASH_LINE_PEAK) because
# by then they know what the band means.
const LINE_FLASH_DURATION := 0.35

const BAND_HEIGHT := 14.0
const STRIPE_PITCH := 18.0 # px from one yellow stripe to the next
const STRIPE_SLANT := 8.0 # how far each stripe's bottom edge leads its top — the hazard slash
const HAZARD_YELLOW := Color(1.0, 0.82, 0.1)
const HAZARD_BLACK := Color(0.08, 0.07, 0.06)
const FLASH_PEAK := 0.85 # alpha at the top of a landing pulse
const FLASH_LINE_PEAK := 0.55 # alpha at the top of a per-line pulse

# HUD bar. Roadworks orange: distinct from tank olive (0.42, 0.5, 0.22),
# nitro blue (0.35, 0.72, 1.0), Slick's violet, Compact's mint and Siren's
# red/blue — every bar this one can end up stacked with.
const BAR := Color(0.96, 0.52, 0.1, 0.95)

# --- State ------------------------------------------------------------------

# Seconds since activate(). Not derived from time_left, because refresh()
# resets time_left and the landing flash must not replay on a refresh — the
# victim already knows; more barriers are simply on the way.
var _age: float = 0.0

# Counts down to the next line. Reset to LINE_INTERVAL when a line is
# actually laid, not when it was due, so spacing survives a wait.
var _line_timer: float = FIRST_LINE_DELAY

# How long the current line has been due and unlaid. Drives the cosmetic
# relaxation at LINE_SLIP_MAX.
var _slip: float = 0.0

# Lane index of the last gap laid, or -1 before the first line. Persists
# through refresh() so the walk constraint spans an extension too.
var _last_gap: int = -1

# Set once a line could not arrive before the bar runs out. Nothing more
# will be laid, so nothing more is scanned — a refresh clears it.
var _exhausted: bool = false

# Remaining seconds of the per-line pulse.
var _line_flash: float = 0.0

# One record per line still above the victim: {"ref": Car, "gap_lo": int,
# "gap_hi": int}. The Car is the first barrier of the line and is only used
# as the line's y; it is read through is_instance_valid every time, because
# the shared loop (or a crash into it) can free it at any moment.
var _inflight: Array[Dictionary] = []

# --- Lifecycle --------------------------------------------------------------

func duration() -> float:
	return DURATION

func activate() -> void:
	_age = 0.0
	_line_timer = FIRST_LINE_DELAY
	_slip = 0.0
	_last_gap = -1
	_exhausted = false
	_line_flash = 0.0
	_inflight.clear()

func refresh() -> void:
	# Re-picked while running — two rivals spent DETOUR on this board at
	# once (Main's fan-out is cumulative on purpose, §5 session L). The rule
	# is refresh-not-stack, and here refreshing already means more: time_left
	# is back to DURATION, so the periodic schedule simply keeps laying lines
	# into the longer window at the same spacing. Not restarting _line_timer
	# is what keeps the spacing honest across the join; not clearing
	# _last_gap keeps the walk continuous; clearing _exhausted lets a line
	# that was refused for arriving too late be reconsidered now that there
	# is time again.
	_exhausted = false

func tick(delta: float) -> void:
	_age += delta
	_line_flash = max(0.0, _line_flash - delta)

	_line_timer -= delta
	if _line_timer <= 0.0 and not _exhausted:
		if _try_lay_line(_slip >= LINE_SLIP_MAX):
			_line_timer = LINE_INTERVAL
			_slip = 0.0
			_line_flash = LINE_FLASH_DURATION
		else:
			# Due and not laid: keep the timer pinned at zero so this is
			# tried again next frame, and count how long that has been so.
			_line_timer = 0.0
			_slip += delta

	# After laying, not before: a line laid this frame gets its merge-hold
	# applied before the lane-change machine runs (tick() precedes the
	# obstacle loop in _process), so no car can decide to merge into a fresh
	# gap in the one frame between.
	_hold_merges_near_lines()

func deactivate() -> void:
	# The barriers stay — see the header. What is put back is only this
	# object's own bookkeeping, so a second call finds nothing to do and a
	# start_round() that wipes the container underneath us leaves no dangling
	# Car in _inflight. is_instance_valid guards the reads in the meantime.
	_inflight.clear()
	_exhausted = true
	_line_flash = 0.0

# --- Laying a line ----------------------------------------------------------

# Attempts to lay one line now. Returns false if no fair placement exists at
# this moment — the caller retries next frame. `relax_cosmetic` drops the
# barrier-lane clearance constraint (a line may then be laid through traffic
# it will overtake on screen); the gap constraint is never dropped.
func _try_lay_line(relax_cosmetic: bool) -> bool:
	var lanes: int = board.lane_count
	var width: int = _gap_width()
	if lanes <= width:
		_exhausted = true # a road that is all gap has nothing to close
		return false

	var spawn_y: float = _spawn_y()
	var speed: float = max(board.current_speed(), 1.0)
	var player_y: float = board.player_car.position.y
	# A line that would still be on its way when the HUD bar empties is not
	# laid. Estimated at the current road speed, which includes the victim's
	# own boost or nitro — a boost that ends mid-flight makes the estimate
	# optimistic by a few tenths, which is an acceptable lie against the
	# alternative of tracking every barrier's progress.
	var travel: float = (player_y - spawn_y) / speed
	if travel > time_left:
		_exhausted = true
		return false

	# The walk anchors on the last gap, or — for the first line — on the
	# lane the victim is in right now, which is the same fairness argument:
	# wherever they were last, the next hole is reachable from there. The
	# anchor itself is excluded: a gap in the lane you are already in is a
	# free pass, and the skill is called DETOUR.
	var last_start: int = lanes - width
	var anchor: int = _last_gap
	if anchor < 0:
		anchor = board._nearest_lane(board.car_x)
	anchor = clamp(anchor, 0, last_start)

	var candidates: Array[int] = []
	for g: int in range(0, last_start + 1):
		if g == anchor:
			continue
		if abs(g - anchor) > GAP_WALK_MAX:
			continue
		candidates.append(g)
	candidates.shuffle() # ties below break randomly rather than always low-lane first

	# Scored, not merely filtered: every candidate that passes the gap test
	# is fair; among those, the one whose barrier lanes contain the least
	# traffic the barriers would visibly drive through is the one to lay.
	var best_gap: int = -1
	var best_conflicts: int = 0
	for g: int in candidates:
		if not _gap_open(g, width, spawn_y):
			continue
		var conflicts: int = _barrier_lane_conflicts(g, width, spawn_y)
		if best_gap < 0 or conflicts < best_conflicts:
			best_gap = g
			best_conflicts = conflicts
	if best_gap < 0:
		return false
	if best_conflicts > 0 and not relax_cosmetic:
		return false

	_lay_line(best_gap, width, spawn_y)
	_last_gap = best_gap
	return true

# Spawns the barriers of one line: every lane except [gap, gap + width).
func _lay_line(gap: int, width: int, spawn_y: float) -> void:
	var sz: Vector2 = board._car_size(BARRIER_KIND)
	var first: Car = null
	for lane: int in range(board.lane_count):
		if lane >= gap and lane < gap + width:
			continue
		# Built exactly the way _spawn_obstacle builds a vehicle, for the
		# reasons in the header: from here on this node is traffic as far as
		# every system on the board is concerned. set_size before
		# set_texture matches that function's order (_rebuild runs on both,
		# the second call is the one that sizes the sprite).
		var barrier: Car = board.CAR_SCENE.instantiate()
		board.obstacle_container.add_child(barrier)
		barrier.set_size(sz.x, sz.y)
		barrier.set_texture(BARRIER_TEXTURE)
		barrier.set_meta("lane", lane)
		# Parked on the road: scrolls at exactly the road's rate. See the
		# header and the TRAFFIC_KINDS comment for why 1.0 is right for a
		# fixture and wrong for anything with an engine.
		barrier.set_meta("speed_mult", 1.0)
		barrier.set_meta("is_barrier", true)
		# Opts the barrier out of PlayerBoard's lane-change machine and of
		# any skill that seeds it. _update_obstacle_lane_change only acts on
		# the states it knows and falls through anything else, and Siren's
		# sweep only takes over cars that are "idle" or "pending" — so a
		# state neither recognises makes a barrier something nobody will
		# ever try to merge. Without this a victim leaning on MAKE WAY could
		# slide a barrier sideways into the gap, which is the one outcome
		# this whole file exists to prevent. (The machine's default for an
		# absent key is "idle", which is why the key has to be set at all.)
		barrier.set_meta("lc_state", "fixture")
		# Same spawn-y convention as traffic and pickups — above the visible
		# top by its own height plus clearance, pushed out further by
		# vertical_margin so it still enters off-screen on a zoomed-out
		# four-player camera. Never on screen at birth.
		barrier.position = Vector2(board.road.lane_center_x(lane), spawn_y)
		# NOTE on the shoulder: steer_bounds() lets the player's centre in to
		# 6% of the board width, but the painted shoulder (Road.SHOULDER_RATIO)
		# is 12.87%, so a car can drive on the paint. With width_frac 1.0 a
		# lane-0/lane-4 barrier's hit box reaches to within about half a
		# pixel of the furthest the player's box can go — closed in practice,
		# but by geometry rather than intent. Ordinary edge-lane traffic is
		# passable on the shoulder by a clearer margin already; it is a
		# board-level mismatch, not one a skill should paper over.
		if first == null:
			first = barrier
	if first != null:
		_inflight.append({"ref": first, "gap_lo": gap, "gap_hi": gap + width - 1})

# Above the visible top edge by the barrier's own height plus clearance —
# the _spawn_obstacle() formula with the barrier's size in it.
func _spawn_y() -> float:
	var sz: Vector2 = board._car_size(BARRIER_KIND)
	return -sz.y - SPAWN_CLEARANCE - board.vertical_margin

func _gap_width() -> int:
	return 2 if int(board.lane_count) >= WIDE_BOARD_LANES else 1

# --- Placement checks -----------------------------------------------------------

# Will every lane of the gap be genuinely passable at the moment a line laid
# at spawn_y is level with the victim?
#
# Why this is not _lanes_used_near_top(): that scan asks "is anything in the
# top 190px" and was sized for traffic spawning behind traffic, where the
# spread of closing speeds is small and a car that is there now is roughly
# where it will still be relative to the newcomer. A barrier closes at 1.0,
# faster than everything, so what matters is not where a car is now but
# where it will be *when the line gets to the player* — a sedan at y=250 is
# outside that strip and would be sitting exactly in the hole at arrival.
# So each car is played forward by the line's travel time instead.
func _gap_open(gap: int, width: int, spawn_y: float) -> bool:
	for lane: int in range(gap, gap + width):
		if not _lane_open_at_arrival(lane, spawn_y):
			return false
	return true

func _lane_open_at_arrival(lane: int, spawn_y: float) -> bool:
	var speed: float = max(board.current_speed(), 1.0)
	# The drawn car's y, as Siren reads it: it carries Nitro's lift, and a
	# victim in the air is flying over the line anyway.
	var player_y: float = board.player_car.position.y
	var player_h: float = board.car_size().y
	var travel: float = (player_y - spawn_y) / speed
	for child in board.obstacle_container.get_children():
		# Pickups share the container and are not in anyone's way.
		if not (child is Car):
			continue
		var car: Car = child
		# `lane` is the lane a car is *committed* to: a merging car reserves
		# its destination the moment it decides (§5 session D), so a car
		# heading into this lane counts and one heading out does not — it
		# has 0.5s of slide left and the line is at least a second away.
		if int(car.get_meta("lane", -1)) != lane:
			continue
		var mult: float = float(car.get_meta("speed_mult", 1.0))
		# Where it will be when the line is level with the victim.
		var y_then: float = car.position.y + mult * speed * travel
		var half_sum: float = (car.height + player_h) * 0.5
		# Behind the line at that moment (smaller y): the line has overtaken
		# it, and the hole must have been visibly open for GAP_OPEN_LEAD by
		# then. The two separate at (1 - mult) * speed, so that lead is this
		# many px of extra clearance. A taxi (mult < 0) separates faster
		# still; the formula is already right for it.
		var lead_behind: float = half_sum + max(1.0 - mult, 0.0) * speed * GAP_OPEN_LEAD
		# Ahead of the line (larger y): it passed the victim first, and must
		# have done so GAP_REENTER_LEAD before the line arrives. It travels
		# past at mult * speed, so that lead is this many px beyond.
		var lead_ahead: float = half_sum + max(mult, 0.0) * speed * GAP_REENTER_LEAD
		if y_then > player_y - lead_behind and y_then < player_y + lead_ahead:
			return false
	return true

# How many cars in the closed lanes a line laid at spawn_y would visibly
# drive through. Cosmetic: a barrier that overtakes a car on screen passes
# straight through it for a few frames, the same overlap fast traffic behind
# slow traffic already produces, only guaranteed rather than occasional
# because a barrier is the fastest closer on the road. It does not touch
# fairness — that lane was closed by the car before the barrier got there —
# so it is a score to minimise and, after LINE_SLIP_MAX, to accept.
func _barrier_lane_conflicts(gap: int, width: int, spawn_y: float) -> int:
	var barrier_h: float = board._car_size(BARRIER_KIND).y
	var visible_bottom: float = board.board_height + board.vertical_margin
	var conflicts: int = 0
	for child in board.obstacle_container.get_children():
		if not (child is Car):
			continue
		var car: Car = child
		var lane: int = int(car.get_meta("lane", -1))
		if lane < 0 or (lane >= gap and lane < gap + width):
			continue
		var mult: float = float(car.get_meta("speed_mult", 1.0))
		# At 1.0 or above nothing is ever caught; at or below zero it is a
		# taxi, which drives up into the barrier and gets queued by its own
		# follow limit — the right outcome, not a conflict.
		if mult >= 1.0 or mult <= 0.0:
			continue
		# Behind the spawn point from birth: it can only ever trail.
		if car.position.y <= spawn_y:
			continue
		var half_sum: float = (car.height + barrier_h) * 0.5
		# The barrier closes the gap between them at (1 - mult) * speed and
		# the car keeps moving at mult * speed meanwhile, so it is caught
		# after covering mult / (1 - mult) of the distance between them.
		# Speed cancels; this is pure geometry.
		var overtake_y: float = car.position.y + (mult / (1.0 - mult)) * (car.position.y - spawn_y - half_sum)
		if overtake_y < visible_bottom + car.height * 0.5:
			conflicts += 1
	return conflicts

# --- Keeping a laid gap open ------------------------------------------------------

# The spawn-time check cannot see a merge that has not been decided yet:
# ~22% of traffic is flagged to change lanes somewhere in the top half of
# the board, and a car in the lane next to the gap that picks the gap side
# after the line is laid can arrive in the hole together with the line.
# So while a line is above the victim, cars ahead of it (between it and the
# victim) in the lanes adjacent to its gap have any still-undecided merge
# cancelled — set to "idle", which is exactly what the machine itself does
# to a car that finds no safe lane. Only "pending" is touched: nothing has
# been reserved, no indicator lit, no timer started, so there is nothing to
# unwind. A car already "warning" has reserved its lane, and the spawn-time
# check counted it there. Cars behind the line are left alone — whatever
# they do lands behind the barriers. Physically: traffic holds its lane
# through the roadworks.
func _hold_merges_near_lines() -> void:
	if _inflight.is_empty():
		return
	var player_y: float = board.player_car.position.y
	var survivors: Array[Dictionary] = []
	for line: Dictionary in _inflight:
		var ref = line["ref"] # untyped on purpose: it may be a freed instance
		if not is_instance_valid(ref):
			continue
		var line_y: float = ref.position.y
		# Past the victim: the gap has been taken or it has not; nothing is
		# left to protect and the record can go.
		if line_y > player_y:
			continue
		survivors.append(line)
		var lo: int = line["gap_lo"]
		var hi: int = line["gap_hi"]
		for child in board.obstacle_container.get_children():
			if not (child is Car):
				continue
			var car: Car = child
			if car.position.y <= line_y:
				continue
			var state: String = car.get_meta("lc_state", "idle")
			if state != "pending":
				continue
			var lane: int = int(car.get_meta("lane", -1))
			# Only the lanes that can reach the gap in one move: a car
			# changes lanes at most once, and only to a neighbour.
			if lane != lo - 1 and lane != hi + 1:
				continue
			car.set_meta("lc_state", "idle")
	_inflight = survivors

# --- Drawing ----------------------------------------------------------------

# Above everything, on the overlay: the band sits at the very top edge,
# where traffic enters, and must not be hidden by the first car that does.
func draw_overlay() -> void:
	var canvas: CanvasItem = board.skill_overlay
	if canvas == null:
		return
	var alpha: float = _flash_alpha()
	if alpha <= 0.0:
		return

	var width: float = board.board_width
	# At the visible top edge, not the board's y=0: on a zoomed-out camera
	# the strip above 0 is on screen (vertical_margin, see Road.render_margin)
	# and a band at 0 would float a little way down the road.
	var top: float = -float(board.vertical_margin)
	var bottom: float = top + BAND_HEIGHT
	canvas.draw_rect(Rect2(0.0, top, width, BAND_HEIGHT), _faded(HAZARD_BLACK, alpha))

	# Yellow slashes, every STRIPE_PITCH, each a parallelogram whose bottom
	# edge leads its top by STRIPE_SLANT. Vertices are clamped to the board's
	# width rather than clipped properly: a clamped corner turns the end
	# stripes into trapezoids, which at 14px tall is invisible, and it keeps
	# the band out of the gutter between two boards.
	var half: float = STRIPE_PITCH * 0.5
	var x: float = -STRIPE_SLANT
	while x < width + STRIPE_PITCH:
		var stripe := PackedVector2Array([
			Vector2(clamp(x, 0.0, width), top),
			Vector2(clamp(x + half, 0.0, width), top),
			Vector2(clamp(x + half + STRIPE_SLANT, 0.0, width), bottom),
			Vector2(clamp(x + STRIPE_SLANT, 0.0, width), bottom),
		])
		canvas.draw_colored_polygon(stripe, _faded(HAZARD_YELLOW, alpha))
		x += STRIPE_PITCH

	# A hairline under the band so it reads as a strip laid on the road
	# rather than the top of the screen having been painted.
	canvas.draw_line(Vector2(0.0, bottom), Vector2(width, bottom), _faded(HAZARD_BLACK, alpha), 1.0)

# The band's alpha right now: the landing flash (three pulses dying away
# over FLASH_DURATION, off _age so a refresh does not replay it) or the
# per-line pulse, whichever is brighter.
func _flash_alpha() -> float:
	var landing: float = 0.0
	if _age < FLASH_DURATION:
		var t: float = _age / FLASH_DURATION
		var pulse: float = 0.5 + 0.5 * cos(TAU * FLASH_PULSES * t)
		landing = (1.0 - t) * pulse * FLASH_PEAK
	var line: float = 0.0
	if _line_flash > 0.0:
		line = (_line_flash / LINE_FLASH_DURATION) * FLASH_LINE_PEAK
	return max(landing, line)

func _faded(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * alpha)

# --- HUD --------------------------------------------------------------------

func bar_color() -> Color:
	return BAR
