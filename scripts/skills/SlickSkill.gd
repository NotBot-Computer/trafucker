extends SkillEffect

## OIL SLICK — an opponent skill that attacks the victim's *control*, not
## their road.
##
## The Taxi (§5 sessions I/L) is the only other opponent skill, and it works
## by putting a new, badly-behaved *vehicle* on the rival's board. Doing that
## again with a different sprite would give this mode two skills that are the
## same idea twice. So this one deliberately adds nothing to the world: no
## vehicle, no hazard, no change to the traffic, no change to the road speed.
## The rival's board looks exactly as dangerous as it did a second ago — the
## danger is that they can no longer place their car in it.
##
## Everything it does is one number: grip, the rate at which `car_vx` (the
## car's real lateral momentum) chases the steering input in PlayerBoard's
## steering block. Collapse that and the car overshoots the lane it was aimed
## at, arrives late at the one it was fleeing to, and keeps coasting sideways
## long after the key came up. Traffic the player could thread at full grip
## is suddenly traffic they can only survive by leaving themselves a lane of
## slack — which is exactly the tax this skill is meant to charge.
##
## WHAT IT DELIBERATELY DOES NOT TOUCH:
##  * steer_top_speed(). The steering block says it in as many words —
##    "drifting is about losing grip, not going faster" — and the same is
##    true in reverse here. An oiled car is not a slower car and it is not a
##    faster one; cutting the top speed would read as the engine being sick
##    rather than the tyres being greasy, and it would also hand BotDriver a
##    correct new picture of its own agility (steer_top_speed() is what the
##    bot reads), which is not what a handicap should do.
##  * road_speed_mult(). Scoring distance is not this skill's business.
##  * is_drifting / drift_sliding. Those belong to the drift session's own
##    state machine (§7, and the four-iteration reasoning trail in §5 session
##    B for why the session and the grip are two separate states). Forcing
##    either from out here would fight it. Composition is by multiplication
##    instead, which the board already does for free in _effect_grip_mult():
##    a victim who drifts while slicked gets 0.48 * GRIP_MULT and a genuinely
##    horrible slide, and that is a fair price for choosing to drift on oil.
##  * The victim's car, position, size, or any other board state. This effect
##    writes exactly one field, `car_vx`, and only ever as an acceleration —
##    see _apply_fishtail.
##
## VISUALS are procedural, in draw_board() (above the road, under the traffic
## and the car, so a spill can never hide an oncoming vehicle — this skill
## handicaps control, not vision). No art asset exists for it; the choice-icon
## glyph sprites/skills/icon_slick.png is the only file it owns.

# --- Tuning -----------------------------------------------------------------

# Long enough to span several waves of traffic — a two-second version would
# be survivable by holding a straight line until it passed, which makes it a
# moment of noise rather than a handicap. Kept in the same ballpark as
# TANK_MODE_DURATION (6.0s) so the two sides of the skill choice feel like
# comparable spends, and a shade under it because "you cannot steer" is a
# harsher thing to sit through than "you cannot die".
const DURATION := 5.0

# The whole skill. STEER_RESPONSE is 9.0, i.e. car_vx closes on the steering
# input with a time constant of 1/9 = 0.111s. A drift already multiplies that
# by DRIFT_GRIP_MULT (0.48) -> 0.231s, which is this codebase's own reference
# point for "this now feels like a slide". 0.34 puts the time constant at
# 0.327s: about 3x normal and about 1.4x a drift, so it is unmistakably worse
# than anything the player can do to themselves, without being a different
# order of magnitude from it.
#
# What that buys, in the units that actually matter on a 5-lane 360px board
# (lane width ~53px, MAX_STEER_SPEED 460):
#   * A one-lane change takes ~0.33s instead of ~0.21s — you have to commit
#     to a gap noticeably earlier than you are used to.
#   * Coasting after the key comes up carries ~150px instead of ~51px, so the
#     default mistake becomes overshooting by two lanes: a mistake the player
#     can see happening and learn to lead against inside five seconds.
# Below ~0.25 the coast runs wider than the road, at which point the shoulder
# clamp is doing the driving and no input the player makes matters — unfair
# rather than hard. Above ~0.45 it is hard to tell from an ordinary drift and
# reads as a bug rather than a skill.
const GRIP_MULT := 0.34

# The fishtail: a slow sideways *force* from the surface, in px/s^2, added to
# car_vx. Deliberately an acceleration and not a velocity offset — the
# steering block's own exponential pull toward target_vx then acts as the
# restoring spring, so the wander is self-limiting instead of something this
# file has to remember to take back out. (That is also why deactivate() has
# nothing to undo; see there.)
#
# Amplitude sized off that equilibrium rather than guessed: with grip at
# STEER_RESPONSE * GRIP_MULT = 3.06/s and the slow component at ~2.9 rad/s, a
# force of A px/s^2 settles into a lateral wander of roughly A/12 px of
# amplitude. 140 therefore wanders about +/-12px — under half a lane
# peak-to-peak. A player holding a lane can hold it; a player threading a
# car-width gap cannot do it casually. Converted to velocity it is only ~7%
# of MAX_STEER_SPEED, so it never fights an active input — it is what you
# feel when you stop giving one.
const FISHTAIL_ACCEL := 140.0

# Two sine components rather than one, at a deliberately awkward ratio
# (0.74 / 0.46, near the golden ratio), so the pattern does not repeat inside
# the five seconds the effect lasts. A single sine reads as a metronome and
# the player learns to count it; per-frame randf() reads as a broken
# controller and cannot be leaned against at all. This is the middle:
# unpredictable, but smooth, and always leadable if you are paying attention.
const FISHTAIL_RATE_SLOW := 0.46 # cycles/sec — the wander you actually steer against
const FISHTAIL_RATE_FAST := 0.74 # cycles/sec — breaks up the rhythm of the slow one
const FISHTAIL_BLEND := 0.6 # weight of the slow component; the fast one takes the rest

# The spill fades in fast and out slow. Fast in (0.3s) because the grip loss
# itself is instant and the tell must not lag behind the handicap — the
# player has to be told why before they get as far as wondering. Slow out
# (0.9s) because the oil drying up is the only pleasant part of this skill
# and it deserves to be read, and because a spill that vanished on the same
# frame grip returned looked like a rendering glitch rather than an ending.
const FADE_IN := 0.3
const FADE_OUT := 0.9

# Spill field. The count is picked for coverage rather than density: at 9,
# three or four are on screen at any moment, which is enough for the road to
# read as contaminated without tiling into a solid dark sheet that would make
# the asphalt — and the lane stripes the player navigates by — hard to read.
const SPILL_COUNT := 9
const SPILL_VERTS := 11 # enough for an irregular puddle, few enough to stay a cheap polygon
const SPILL_RADIUS_MIN_FRAC := 0.45 # of lane width
const SPILL_RADIUS_MAX_FRAC := 1.05 # of lane width — a big one covers a lane, never two
const SPILL_STRETCH_Y := 1.5 # spills are streaked along the direction of travel, not round
const SPILL_WRAP_PAD := 140.0 # px of off-screen room above/below, so nothing pops in mid-view

# Kept dark and translucent rather than opaque black: the road texture has to
# survive underneath, or the spill stops reading as something *on* the
# asphalt and starts reading as a hole in it.
const SPILL_BODY := Color(0.045, 0.04, 0.06, 0.58)
const SPILL_SHEEN_ALPHA := 0.3 # the rainbow film, drawn small and inside the body
const SPILL_SHEEN_SCALE := 0.58 # sheen patch size as a fraction of the spill
const SHEEN_HUE_RATE := 0.09 # hue cycles/sec — slow enough to look like a film, not a disco
const SPILL_GLINT := Color(0.85, 0.9, 1.0, 0.22) # wet highlight along the spill's upper edge
const SPILL_GLINT_WIDTH := 1.5

# Tyre smear at the car — the local half of the tell. The spill says the road
# is oiled; this says *your* tyres are the ones on it.
# SMEAR_TRACK_FRAC matches the drift trail's own DRIFT_MARK_OFFSET by eye so
# the two effects agree about where the rear wheels are, but it is kept as its
# own number on purpose: that one is a drawing choice belonging to the drift
# trail, and copying a PlayerBoard constant into a skill file is the exact
# duplication trap §7 names. If they ever disagree visibly, this is the one
# that should move.
const SMEAR_TRACK_FRAC := 0.22 # fraction of car width, rear-wheel spacing
const SMEAR_LEN_FRAC := 0.85 # fraction of car height — how far back the smear trails
const SMEAR_WIDTH_FRAC := 0.13 # fraction of car width at the tyre; it tapers to a point
const SMEAR_KICK_FRAC := 0.5 # of car width — how far the far end lags sideways at full slide
const SMEAR_COLOR := Color(0.06, 0.05, 0.08, 0.5)

# HUD bar. Oil-film violet: distinct at a glance from tank olive
# (0.42, 0.5, 0.22) and nitro blue (0.35, 0.72, 1.0), which are the two bars
# it can end up stacked with.
const BAR := Color(0.34, 0.26, 0.5, 0.95)

# --- State ------------------------------------------------------------------

# Road-space scroll offset for the spill field, accumulated from the board's
# own odometer — see tick() for why it is not integrated from current_speed()
# here.
var _scroll: float = 0.0
var _last_distance: float = 0.0

# Seconds since activate(), NOT derived from time_left. refresh() puts
# time_left back to DURATION when the skill is re-applied mid-effect, and if
# the fade-in were computed from time_left the whole spill would blink out
# and fade back in at that moment. _age keeps running through a refresh, so a
# re-application extends the slick instead of restarting it.
var _age: float = 0.0

# Fishtail clock. Seeded randomly so two boards hit by the same broadcast do
# not wander in lockstep — the same reason SkillPickup randomizes _pulse_t.
var _phase: float = randf() * 100.0

# One entry per spill: {x, y, rx, ry, hue, shape}. Built once in activate()
# and only read afterwards, so the puddles keep their identity as they scroll
# instead of being re-randomized every frame into TV static.
var _spills: Array[Dictionary] = []

# --- Lifecycle --------------------------------------------------------------

func duration() -> float:
	return DURATION

func activate() -> void:
	_last_distance = board.distance
	_build_spills()

func refresh() -> void:
	# Re-picked while already running. The spill field and _age are left
	# exactly as they are: the road is already oily, someone has just poured
	# more on it. time_left was reset by the caller before this ran, and that
	# is the entire effect of a refresh here.
	pass

func tick(delta: float) -> void:
	_age += delta
	_phase += delta

	# Scroll from the *board's odometer delta*, not from current_speed()
	# integrated locally. This is the §7 invariant ("scrolling scenery must
	# derive its distance from a board's odometer, never integrate its own"),
	# and it is not pedantry here: `distance` already has boost, nitro, tank
	# recoil and the post-crash crawl folded into it through current_speed(),
	# so following it keeps the spill welded to the asphalt through all four
	# without this file knowing any of them exist. tick() runs before the
	# board advances `distance` for this frame, so what is read is the
	# previous frame's increment — in phase, one frame of lag, invisible.
	var travelled: float = board.distance - _last_distance
	_last_distance = board.distance
	# It cannot go backwards in normal play; guarded anyway so that a
	# distance reset under a live effect could only ever cost one frame of
	# scroll rather than hurl the whole field back up the board.
	if travelled > 0.0:
		_scroll += travelled

	_apply_fishtail(delta)

func deactivate() -> void:
	# Nothing to put back, and that is a property of the design rather than
	# an oversight:
	#   * grip_mult() is a pure function of nothing. The frame after this
	#     effect leaves active_effects, _effect_grip_mult() stops multiplying
	#     by it and the car has full grip again. There is no saved
	#     STEER_RESPONSE to restore, because nothing was ever overwritten.
	#   * The fishtail went into car_vx as an acceleration, so what it leaves
	#     behind is ordinary lateral momentum — indistinguishable from
	#     momentum the player put there by steering, and bled off by the
	#     steering block's own approach within ~0.1s at restored grip. There
	#     is no "correct" car_vx to subtract back out, and subtracting one
	#     would be the actual bug.
	#   * No nodes are created, so there is nothing to free and no repeat of
	#     the session G tank-smoke leak.
	# It is therefore idempotent by construction, which is what start_round()
	# and elimination both need, possibly mid-effect.
	pass

# --- Physics hooks ----------------------------------------------------------

func grip_mult() -> float:
	# Flat, not enveloped. Ramping grip in and out with the visual was
	# considered and rejected: the HUD bar promises an exact window, and a
	# ramped grip would make the last second of that bar a lie. The visual
	# fade exists to stop the spill popping, not to gate the physics — see
	# FADE_IN for why the two are allowed to disagree. Nothing lurches at
	# either edge in any case: only the response *rate* changes, never
	# car_vx itself.
	return GRIP_MULT

# steer_speed_mult() and road_speed_mult() are deliberately left at the base
# class's 1.0 — see the header. The car is not slower. It is just loose.

# --- The fishtail -----------------------------------------------------------

# -1..1, the surface's sideways push right now. Reaches 1.0 only when both
# components align.
func _fishtail_norm() -> float:
	var slow: float = sin(TAU * FISHTAIL_RATE_SLOW * _phase)
	# Phase-offset so the two components do not both cross zero together,
	# which would give every slick the same dead opening.
	var fast: float = sin(TAU * FISHTAIL_RATE_FAST * _phase + 1.3)
	return slow * FISHTAIL_BLEND + fast * (1.0 - FISHTAIL_BLEND)

func _apply_fishtail(delta: float) -> void:
	# Written straight into car_vx as an acceleration, from tick(), which the
	# board calls immediately *before* its steering block — so this frame's
	# push is integrated into car_x by the same code that integrates the
	# player's own steering, and lands under the same steer_bounds() clamp.
	# That clamp is why no amount of this can push the car off the road: at a
	# shoulder the block pins car_x and zeroes car_vx outright.
	#
	# During a dash the steering block ignores car_vx entirely and drives
	# car_x from the dash curve, so a push applied mid-dash simply sits in
	# car_vx until the dash ends. At 140px/s^2 across a 0.14s dash that is
	# under 20px/s of inherited momentum — the car comes out of the dash
	# already sliding slightly, which is right for the surface it dashed on.
	# Not special-cased, for that reason.
	board.car_vx += _fishtail_norm() * FISHTAIL_ACCEL * _envelope() * delta

# Shared fade envelope, 0..1. Rises off _age (not time_left — see _age) and
# falls off time_left.
func _envelope() -> float:
	var rise: float = clamp(_age / FADE_IN, 0.0, 1.0)
	var fall: float = clamp(time_left / FADE_OUT, 0.0, 1.0)
	return min(rise, fall)

# --- Spill field ------------------------------------------------------------

func _build_spills() -> void:
	_spills.clear()
	var lane_w: float = board.road.lane_width()
	var span: float = _wrap_span()
	for i: int in range(SPILL_COUNT):
		# Placed on a lane centre rather than anywhere across the width, so a
		# spill reads as something a vehicle leaked while driving a lane —
		# and so it never sits mostly on the shoulder, where the player never
		# goes and the tell would be wasted.
		var lane: int = randi() % max(int(board.lane_count), 1)
		var jitter: float = randf_range(-lane_w * 0.35, lane_w * 0.35)
		var radius: float = lane_w * randf_range(SPILL_RADIUS_MIN_FRAC, SPILL_RADIUS_MAX_FRAC)
		var shape := PackedVector2Array()
		for v: int in range(SPILL_VERTS):
			var a: float = TAU * float(v) / float(SPILL_VERTS)
			# Per-vertex radius jitter is what makes it a puddle rather than a
			# polygon. Kept above 0.7 so no vertex folds in far enough for the
			# outline to self-intersect, which draw_colored_polygon renders as
			# a visible pinch.
			var r: float = randf_range(0.72, 1.0)
			shape.append(Vector2(cos(a), sin(a)) * r)
		_spills.append({
			"x": board.road.lane_center_x(lane) + jitter,
			"y": randf() * span,
			"rx": radius,
			"ry": radius * SPILL_STRETCH_Y,
			# Each spill's sheen starts somewhere different in the hue cycle,
			# so the field shimmers as a scatter of colours rather than
			# pulsing as one block.
			"hue": randf(),
			"shape": shape,
		})

# Vertical distance a spill travels before it wraps back to the top. Covers
# the board plus whatever extra strip the camera can see once it has zoomed
# out for a wider player count (vertical_margin — the same reason
# Road.render_margin exists), plus a pad at each end so a spill is fully
# off-screen at the moment it teleports.
func _wrap_span() -> float:
	return board.board_height + 2.0 * board.vertical_margin + 2.0 * SPILL_WRAP_PAD

# --- Drawing ----------------------------------------------------------------

# Above the road, below the traffic and the car. That layering is the point: a
# spill that could cover an oncoming vehicle would be handicapping the
# player's *vision*, and there is a different skill for that.
func draw_board() -> void:
	var alpha: float = _envelope()
	if alpha <= 0.0:
		return
	_draw_spills(alpha)
	_draw_tyre_smears(alpha)

func _draw_spills(alpha: float) -> void:
	var span: float = _wrap_span()
	var top: float = -(board.vertical_margin + SPILL_WRAP_PAD)
	for spill: Dictionary in _spills:
		var shape: PackedVector2Array = spill["shape"]
		var cx: float = spill["x"]
		var rx: float = spill["rx"]
		var ry: float = spill["ry"]
		# +_scroll, so the field slides toward +y as distance grows — the
		# same direction the road tiles and the traffic move (§5 session A,
		# fix 2, is the entry on what happens when a layer disagrees). fposmod
		# rather than fmod because the offset is only ever positive today but
		# would silently mirror the field if that stopped being true.
		var cy: float = top + fposmod(float(spill["y"]) + _scroll, span)

		var body := PackedVector2Array()
		body.resize(shape.size())
		for i: int in range(shape.size()):
			body[i] = Vector2(cx + shape[i].x * rx, cy + shape[i].y * ry)
		board.draw_colored_polygon(body, _faded(SPILL_BODY, alpha))

		# The oily film: a smaller copy of the same outline, pushed up and
		# left inside the body so it reads as a highlight lying on the puddle
		# rather than as a second puddle. The hue crawls, and each spill
		# starts at its own point in the cycle.
		var sheen_hue: float = fposmod(float(spill["hue"]) + _phase * SHEEN_HUE_RATE, 1.0)
		var sheen_color: Color = Color.from_hsv(sheen_hue, 0.55, 1.0, SPILL_SHEEN_ALPHA)
		var sx: float = cx - rx * 0.16
		var sy: float = cy - ry * 0.1
		var sheen := PackedVector2Array()
		sheen.resize(shape.size())
		for i: int in range(shape.size()):
			sheen[i] = Vector2(
				sx + shape[i].x * rx * SPILL_SHEEN_SCALE,
				sy + shape[i].y * ry * SPILL_SHEEN_SCALE
			)
		board.draw_colored_polygon(sheen, _faded(sheen_color, alpha))

		# Wet glint along the upper edge only. In Godot 2D +y is down, so the
		# upper half of the outline is the vertices whose sin() is negative —
		# the back half of the vertex ring, indices n/2..n-1. Lighting one
		# edge is what sells "liquid" over "dark paint".
		var glint := PackedVector2Array()
		for i: int in range(int(shape.size() / 2), shape.size()):
			glint.append(body[i])
		if glint.size() >= 2:
			board.draw_polyline(glint, _faded(SPILL_GLINT, alpha), SPILL_GLINT_WIDTH)

func _draw_tyre_smears(alpha: float) -> void:
	var sz: Vector2 = board.car_size()
	# x comes from car_x, the steering-space position — deliberately not
	# player_car.position.x, which carries nitro's per-frame shudder and would
	# put a second, much faster wobble on the one visual whose entire job is
	# to explain the slow one. y does come from the drawn car, so the smear
	# stays attached to the tyres it belongs to (and rides up with nitro's
	# lift, which is correct: an airborne car is not scrubbing anything). The
	# alternative, anchoring to the board's own ground line, needs PlayerBoard's
	# CAR_BOTTOM_MARGIN, and copying that number into this file is the
	# duplication §7 warns about.
	var cx: float = board.car_x
	var cy: float = board.player_car.position.y

	# How sideways the car currently is, -1..1, measured against the steering
	# top speed actually in force (so a tank on oil is judged on a tank's own
	# scale). This is what makes the smear a readout rather than decoration:
	# it kicks out hardest exactly when the player has lost the back end.
	var slide: float = clamp(board.car_vx / max(board.steer_top_speed(), 1.0), -1.0, 1.0)
	var push: float = _fishtail_norm()
	# Always faintly present, so the player can see they are on the oil even
	# while travelling straight, and strongest when either the car is actually
	# sliding or the surface is shoving hardest.
	var strength: float = clamp(0.3 + 0.7 * abs(slide) + 0.3 * abs(push), 0.0, 1.0)

	var half_w: float = sz.x * SMEAR_WIDTH_FRAC * 0.5
	var length: float = sz.y * SMEAR_LEN_FRAC
	var kick: float = -slide * sz.x * SMEAR_KICK_FRAC
	for side: int in [-1, 1]:
		var wheel_x: float = cx + float(side) * sz.x * SMEAR_TRACK_FRAC
		var wheel_y: float = cy + sz.y * 0.4
		# A tapered triangle: full width at the tyre, pinched to a point at
		# the far end, and that far end displaced *opposite* the slide — the
		# mark is where the tyre has been, and the car has moved sideways
		# since it was laid.
		var smear := PackedVector2Array([
			Vector2(wheel_x - half_w, wheel_y),
			Vector2(wheel_x + half_w, wheel_y),
			Vector2(wheel_x + kick, wheel_y + length),
		])
		board.draw_colored_polygon(smear, _faded(SMEAR_COLOR, alpha * strength))

# One place the fade envelope is folded into a colour, so no call site can
# forget it and leave a spill snapping on or off at full opacity.
func _faded(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, c.a * alpha)

# --- HUD --------------------------------------------------------------------

func bar_color() -> Color:
	return BAR
