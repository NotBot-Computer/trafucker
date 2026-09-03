extends SkillEffect

## MAKE WAY (catalog id "siren") — the player leans on the horn and the
## traffic in front of them pulls over.
##
## The two self skills that already exist both work by changing the *player*:
## Tank Mode makes them invincible and hands them a cannon, Nitro takes them
## off the road entirely at 2.85x. This one deliberately touches the player's
## car not at all — every physics hook stays at 1.0 — and changes the traffic
## instead. That difference is the whole reason it earns a slot in
## SELF_SKILLS rather than being a third flavour of "you are briefly better".
##
## ## It does not move any cars itself
##
## PlayerBoard already owns a lane-change state machine
## (_update_obstacle_lane_change, built in §5 session D): it slides a car from
## one lane center to the next with smoothstep easing, reserves the target
## lane in the car's `lane` meta for the whole maneuver so nothing else spawns
## or merges into it, and blinks the indicator on the way. All this file does
## is fill in that machine's metas and let it run — a siren merge is an
## ordinary merge that the player decided instead of randf(). Writing a second
## mover here was rejected outright: two systems driving one car's x is
## exactly the fight the taxi's own AI must be kept out of (hence the
## active_taxis skip in _sweep below), and the culling/movement loop keeps
## working untouched precisely because nothing new moves anything.
##
## ## What it does change is the merge's manners
##
## Ordinary traffic blinks for LANE_CHANGE_INDICATOR_WARNING (1.3s) without
## moving an inch, then takes LANE_CHANGE_DURATION (0.5s) over the slide.
## Neither is a per-car value, and neither may be edited from here. So:
##
##   * The warning is skipped by starting the car in "moving" rather than
##     "warning", with the indicator already lit. It signals and goes, which
##     is what a car does when something is howling at it — a 1.3s pause
##     would have made the skill look like it had failed for its first two
##     thirds of a second.
##   * The slide is shortened by handing that one car extra clock each frame
##     (see _hurry), NOT by pre-loading its lc_timer. Pre-loading looks like
##     the obvious trick and it is wrong: the machine lerps from lc_from_x by
##     the eased fraction, so a timer starting at 0.2 puts the car 35% of the
##     way across on its very first frame. That is a sideways teleport, and a
##     teleporting car reads as a bug, not as an effect. Feeding the same
##     machine a bigger delta only runs its clock faster; every frame in
##     between is still a real, eased, in-between position.
##
## ## The honest limit
##
## A car with nowhere safe to go stays exactly where it is. It is not
## despawned, not phased through anything, not shoved into an occupied lane.
## The skill opens the lane it can open; it does not promise a clear road, and
## a player who picks it while boxed in gets a horn and a light show. That is
## the design, and the next sweep will try that car again in case its
## neighbour has moved on by then.

# --- Timing and reach ------------------------------------------------------

# Long enough to drive through the hole it opens, short enough that it never
# becomes the whole round. Matches Tank Mode's 6s / Nitro's 5.3s bracket.
const DURATION := 5.0

# The corridor is rescanned this often rather than every frame. Traffic
# arrives at 160-560 px/s, so at 0.3s a car crosses at most ~170px between
# sweeps — well inside SIREN_REACH — and the whole scan is O(traffic on
# screen), which is a handful of nodes.
const SCAN_INTERVAL := 0.3

# How far up the road the horn is heard, in board px. The board is 620 tall
# and the player sits at ~560, so 400 — the value this shipped with — reached
# only about two thirds of the way up the visible road, and the top third of
# the lane stayed full of traffic that started moving aside only once it was
# already close. 720 clears the whole visible lane and a little of the strip
# above it: the player's y plus the largest vertical_margin the 3/4-player
# camera zoom adds (Main.set_vertical_margin), which is about where
# _spawn_obstacle puts a new car. In practice that means a car is pulled
# aside at or just before the moment it enters the board, and the corridor
# the skill paints is a corridor all the way to the horizon rather than one
# that dead-ends in a wall of cars.
#
# The timing argument for the old number gets better rather than worse: at
# the ramp's top speed (560 px/s road, ~0.85 closing fraction) a car 400px
# out had ~0.8s before it arrived, already more than twice the shortened
# slide below; at 720 it is ~1.5s. Nothing this picks up is short of time to
# finish getting out of the way — the reach was never limited by the physics,
# only by an initial guess at how strong the skill should be.
#
# What this does NOT change is the honest limit in the header: a car with
# nowhere safe to merge stays put. A longer reach finds more cars, not more
# room, so on a busy board this buys a longer corridor with the same number
# of stubborn cars standing in it.
const SIREN_REACH := 720.0

# "In or near the player's own lane", as a fraction of one lane width from
# car_x. At 0.9 a car sitting on the next lane's center (a full lane width
# away) is left alone, while one straddling the line into the player's lane
# is pulled out. It is deliberately a hair wider than the painted corridor:
# a car clipping the edge of the strip should move, not sit on the line.
const CORRIDOR_CATCH_FRAC := 0.9

# The painted corridor's width, as a fraction of a lane. Exactly one lane, so
# what is drawn reads as "this lane is being cleared" and not "these two".
const CORRIDOR_DRAW_FRAC := 1.0

# Clear px demanded between the merging car's bumper and the nearest vehicle
# already in the target lane. Traffic's own LANE_CHANGE_SAFE_GAP is 200px
# center-to-center, which for a 179px-long truck is barely 20px of daylight
# and for two sedans is a gap you could park in — one number cannot mean the
# same thing for both. This is measured between bumpers instead (see
# _merge_room) and set just above the taxi's TAXI_SIDE_GAP of 28: a car being
# sirened at squeezes harder than one changing lanes for its own reasons, but
# not as hard as a taxi driver.
const MERGE_GAP := 34.0

# Extra fraction of a frame's delta handed to a hurried car's lane-change
# clock, on top of the one PlayerBoard already gives it. At 0.7 the machine
# runs at 1.7x, so LANE_CHANGE_DURATION's 0.5s slide lands in ~0.29s — quick
# enough to read as "getting out of the way", still ~17 frames of eased
# movement at 60fps rather than a jump.
const HURRY_TIME_BONUS := 0.7

# --- The light show --------------------------------------------------------

# The player drives an actual police cruiser for the duration. Cut from the
# user's polis.png by scripts/dev/extract_police.py onto the *player-car*
# canvas (78x132, PLAYER_KIND's own aspect) — see that file for why the art
# was fitted to the footprint rather than the footprint to the art.
#
# It is a skin and nothing else. car_kind() is deliberately NOT claimed: the
# hitbox, the steering bounds, the dash clamp, the trail spacing and what the
# bot thinks fits in a gap all stay exactly what they were, so nothing about
# this changes how the round plays. A cruiser that was also a different size
# would be a second, unasked-for mechanic riding along with a costume.
#
# The strobing lamps below are drawn ON TOP of it and are not removed now
# that the sprite has a light bar painted on. The painted one is part of the
# car; the drawn ones are the skill running, they pulse on the same beat as
# the corridor and the HUD bar, and they are what says the horn is *live*
# rather than that the player happens to be in a police car.
const POLICE_TEXTURE := preload("res://sprites/cars/police.png")

# ...and drawn this much bigger than the footprint, which is a correction and
# not a size change. The texture is stretched to the whole 78x132 canvas, and
# the cruiser only fills 56px of that width where every player sedan fills
# 67 — it is a more slender car scaled to the same 121px length. At 1.0 the
# player therefore visibly *shrinks* the instant the horn goes on, which is
# what "the police car is small" means and is a costume changing the car.
#
# 67 / 56 = 1.196: the cruiser is drawn exactly as wide on screen as the
# sedan it replaced, which is the one anchor here that is measured rather
# than chosen (scripts/dev/extract_police.py prints both content boxes). Its
# length follows to ~1.10x the sedan's, because the art is a longer car and
# scaling it to match on both axes is not a thing that exists. That extra
# length is the only cost: the sprite overhangs its own hitbox by ~5px more
# at each end than a sedan's does, so a near miss at the nose looks fractionally
# closer than it was — forgiving, never punishing, and the alternative is a
# cruiser that is visibly narrower than the lane discipline the round is
# actually judged on.
#
# This is Car.sprite_scale_mult, via SkillEffect.car_texture_scale(): the
# Sprite2D only. The hitbox, steer_bounds(), the dash clamp and BotDriver's
# sense of what fits all still read car_size(), which has not moved — which
# is what keeps the paragraph above ("a skin and nothing else") true.
const CAR_SCALE := 1.196

# Emergency red and blue, kept saturated enough to stay legible as a wash at
# 10% alpha over grey asphalt.
const SIREN_RED := Color(1.0, 0.2, 0.24)
const SIREN_BLUE := Color(0.26, 0.5, 1.0)

# Radians/sec of the red/blue alternation — ~1.9 swaps a second, in the band
# a real light bar strobes at. Fast enough to be urgent, slow enough that it
# doesn't turn into a flicker on a small board.
const FLASH_SPEED := 12.0

# Where the two lamps are drawn on the car, in fractions of the DRAWN SPRITE
# — car_size() times CAR_SCALE, not car_size() (see _sprite_size). That
# distinction is the whole reason these numbers are what they are: the lamps
# have to sit on painted hardware, so they belong to the picture of the car,
# not to its footprint. Written against the footprint they would have stayed
# put while the sprite around them grew.
#
# They are MEASURED off police.png rather than guessed: its painted light bar
# sits at 0.504 down the car's own content box — dead centre of the 78x132
# canvas — with the blue lens centred 0.136 of the canvas width left of the
# middle. The canvas is what gets stretched to the drawn sprite, so those are
# already sprite fractions and the drawn lamps land on the painted lenses
# rather than floating over the roof in front of them (which is where the
# pre-skin numbers, 0.1 up and 0.26 apart, put them).
#
# LAMP_RADIUS_FRAC is deliberately bigger than the painted lens (which is
# only ~0.13 of the canvas wide, i.e. a radius of ~0.065): at a ~40px sprite
# a true-to-scale lens is under three pixels across and the strobe stops
# existing. This is the compromise — large enough to read, small enough to
# sit on the light bar rather than cover the roof. The floor keeps it visible
# if a skill shrinks the car (Compact takes it to 66% width).
const LAMP_Y_FRAC := 0.0 # of sprite height, from the sprite's centre; +y is down
const LAMP_SPREAD_FRAC := 0.136 # of sprite width, each side of centre — the painted lens
const LAMP_RADIUS_FRAC := 0.13 # of sprite width
const LAMP_RADIUS_MIN := 2.6 # px

const CHEVRON_SPACING := 44.0 # px between the arrows racing up the corridor
const CHEVRON_SPEED := 260.0 # px/sec they travel — faster than the road, so they read as the effect's own motion rather than as road markings
const CHEVRON_HEIGHT := 13.0 # how deep the ">" is folded, in px
const CORRIDOR_WASH_ALPHA := 0.1 # the flat tint over the lane; any heavier and the traffic in it stops reading

# Both ends are eased so the corridor doesn't pop into and out of existence.
# The tail is the longer of the two on purpose — the skill ending is
# information the player needs a moment to act on.
const FADE_IN := 0.18
const FADE_OUT := 0.5

var _scan_timer: float = 0.0
var _pulse: float = 0.0 # drives every animated thing here; only ever grows
# Cars mid-slide that this effect started, and is therefore still hurrying
# along. Not a meta on the car: a meta would have to be cleaned up in
# deactivate() on cars that may already be freed, and a stale one would be
# read by the next round's effect. A local list dies with the effect.
var _hurrying: Array[Car] = []

func duration() -> float:
	return DURATION

func activate() -> void:
	_pulse = 0.0
	_scan_timer = SCAN_INTERVAL
	# The effect is already in board.active_effects by the time this runs
	# (SkillEffect's lifecycle contract), so the board's own lookup finds this
	# skin rather than being answered as if the claim did not exist.
	board.refresh_car_texture()
	# Immediately, not on the next scan tick: the horn is pressed now and the
	# lane in front has to visibly answer now.
	_sweep()

func refresh() -> void:
	# A second blast re-sweeps at once (whatever moved in front since the
	# first one gets shoved too), but _pulse keeps running so the beacon
	# doesn't restart mid-flash.
	_scan_timer = 0.0

func tick(delta: float) -> void:
	_pulse += delta
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		_sweep()
	_hurry(delta)

# Idempotent, and leaves the board exactly as found. Every car this touched
# was handed a complete set of lane-change metas, so dropping the list mid-
# effect simply returns those cars to the board's own 0.5s slide and its own
# indicator tail — the machine finishes them without this file existing. The
# only thing being given up is the extra clock.
func deactivate() -> void:
	_hurrying.clear()
	_scan_timer = 0.0
	_pulse = 0.0
	# Removed from active_effects before this runs, so the board resolves the
	# skin *without* this effect — back to the player's own car, or to the
	# tank if one is up, without this file having to know which.
	board.refresh_car_texture()

# --- Hooks -----------------------------------------------------------------

# The only board hook this skill touches. Every physics multiplier is left at
# the base class's 1.0 (the car is not faster, not slower, not grippier) and
# car_kind() is left empty on purpose — see POLICE_TEXTURE.
func car_texture() -> Texture2D:
	return POLICE_TEXTURE

# Sprite only — see CAR_SCALE. Nothing the round is played on moves.
func car_texture_scale() -> float:
	return CAR_SCALE

# --- Clearing the lane -----------------------------------------------------

# Finds everything currently in the corridor ahead of the player and asks it
# to move. Runs a few times a second, not every frame.
func _sweep() -> void:
	if board.lane_count <= 1:
		return
	var lane_w: float = board.road.lane_width()
	var corridor: float = lane_w * CORRIDOR_CATCH_FRAC
	# car_x, not player_car.position.x: that one carries Nitro's shudder, and
	# the corridor should not vibrate.
	var player_x: float = board.car_x
	# For y there is no steering-space equivalent, so the drawn position is
	# the reference. Nitro's lift moves it up to 105px up the board, which
	# only narrows the corridor while the player is airborne — and traffic
	# under an airborne player is being flown over, not dodged.
	var player_y: float = board.player_car.position.y
	for child in board.obstacle_container.get_children():
		# Skill pickups live in this same container. They are not vehicles,
		# they have no driver to scare, and they are something the player
		# wants left where it is.
		if not (child is Car):
			continue
		var car: Car = child
		# A taxi drives its own x every frame from its own AI (see
		# _update_taxi_steering). Handing it a lane change would put two
		# systems in charge of one car's position, and the taxi would win
		# every frame while the lane-change metas quietly disagreed.
		if board.active_taxis.has(car):
			continue
		# +y is down: ahead of the player is a smaller y.
		var gap: float = player_y - car.position.y
		if gap <= 0.0 or gap > SIREN_REACH:
			continue
		if abs(car.position.x - player_x) > corridor:
			continue
		# Only cars that are sitting on a lane center are taken over. "idle"
		# and "pending" both guarantee that; a car already warning, moving or
		# settling has its `lane` meta pointing at the lane it is heading for
		# rather than the one it is in, so seeding a fresh merge from it
		# would compute the direction against the wrong lane. It finishes
		# its own maneuver and the next sweep picks it up if it is still in
		# the way.
		var state: String = car.get_meta("lc_state", "idle")
		if state != "idle" and state != "pending":
			continue
		_pull_aside(car, player_x, corridor)

# Hands one car to PlayerBoard's lane-change machine, already in motion.
# Silently does nothing if neither side is safe — that is the honest limit in
# the header, not an oversight.
func _pull_aside(car: Car, player_x: float, corridor: float) -> void:
	var cur_lane: int = car.get_meta("lane", 0)
	var dirs: Array[int] = []
	if cur_lane > 0:
		dirs.append(-1)
	if cur_lane < board.lane_count - 1:
		dirs.append(1)
	if dirs.is_empty():
		return

	# Preferred side is away from the player, so a car that is already
	# drifting off the player's line keeps going that way instead of being
	# swung back across their nose. Dead center is a genuine tie, broken
	# toward whichever side has more road left.
	var away: int = 1 if car.position.x > player_x else -1
	if is_equal_approx(car.position.x, player_x):
		away = 1 if (board.lane_count - 1 - cur_lane) >= cur_lane else -1
	if dirs.size() == 2 and dirs[0] != away:
		dirs.reverse()

	for dir in dirs:
		var target: int = cur_lane + dir
		# Never merge into the corridor being cleared. Written as an overlap
		# test against the same corridor the sweep selects with, rather than
		# as "not the player's lane", so that a player straddling two lanes
		# is protected in both of them — they are occupying both.
		if abs(board.road.lane_center_x(target) - player_x) <= corridor:
			continue
		if not _merge_room(car, target):
			continue
		# Exactly the metas _update_obstacle_lane_change's "moving" branch
		# reads, in the same order it decides them, with two differences from
		# an ordinary merge: the state starts at "moving" instead of
		# "warning" (no 1.3s dawdle) and lc_timer starts at 0.0 so the first
		# frame's lerp lands on lc_from_x — i.e. the car does not move at all
		# on the frame it is told to, and every frame after that is eased.
		# The lane is reserved now, not when the slide ends, which is what
		# stops a spawn or another merge claiming the hole it is heading for.
		car.set_meta("lane", target)
		car.set_meta("lc_from_x", car.position.x)
		car.set_meta("lc_to_x", board.road.lane_center_x(target))
		car.set_meta("lc_timer", 0.0)
		car.set_meta("lc_state", "moving")
		car.start_indicator(dir)
		_hurrying.append(car)
		return

# Bumper-to-bumper clearance in the target lane, measured against real
# vehicle lengths rather than a flat center-to-center number — traffic here
# runs from a 56px sedan to a 179px truck, and one constant cannot describe
# a safe gap for both. Every obstacle_container child carries a `lane` meta
# (the §7 invariant), including skill pickups, which are given room too so a
# merging car never parks on top of one.
func _merge_room(car: Car, lane: int) -> bool:
	for other in board.obstacle_container.get_children():
		if other == car:
			continue
		if int(other.get_meta("lane", -1)) != lane:
			continue
		var other_half: float = 0.0
		if other is Car:
			var other_car: Car = other
			other_half = other_car.height * 0.5
		elif other is SkillPickup:
			var pickup: SkillPickup = other
			other_half = pickup.radius
		if abs(other.position.y - car.position.y) < MERGE_GAP + car.height * 0.5 + other_half:
			return false
	return true

# The extra clock described in the header. Runs from tick(), which
# PlayerBoard calls before its own obstacle loop, so a hurried car gets this
# delta and then the board's own in the same frame — both through the same
# function, both producing an eased in-between position.
func _hurry(delta: float) -> void:
	if _hurrying.is_empty():
		return
	var still: Array[Car] = []
	for car in _hurrying:
		if not is_instance_valid(car):
			continue # crushed, shot, or despawned off the bottom
		var state: String = car.get_meta("lc_state", "idle")
		if state != "moving":
			continue # already across; the indicator tail is the board's business
		board._update_obstacle_lane_change(car, delta * HURRY_TIME_BONUS)
		var after: String = car.get_meta("lc_state", "idle")
		if after == "moving":
			still.append(car)
	_hurrying = still

# --- Drawing ---------------------------------------------------------------

# Both ends of the effect eased, as one 0..1 scalar every draw call multiplies
# through.
func _fade() -> float:
	var spent: float = DURATION - time_left
	return clamp(min(spent / FADE_IN, time_left / FADE_OUT), 0.0, 1.0)

# How lit one lamp is right now, 0..1, `phase` radians out of the beat.
# Squared so the peak is short and the trough is long — a linear sine reads
# as a slow throb, and this needs to read as a strobe.
func _lit(phase: float) -> float:
	var s: float = 0.5 + 0.5 * sin(_pulse * FLASH_SPEED + phase)
	return s * s

# The corridor itself, on the asphalt and under the traffic — traffic that
# has not moved yet is visibly standing *in* it, which is what makes the
# skill's one real limitation legible instead of looking broken.
func draw_board() -> void:
	var fade: float = _fade()
	if fade <= 0.0:
		return
	var half: float = board.road.lane_width() * CORRIDOR_DRAW_FRAC * 0.5
	var x: float = board.car_x
	var bottom: float = board.board_height
	# Clamped to the top of what the camera can actually see, not to 0. The
	# board draws past [0, board_height] by vertical_margin (the same strip
	# Road.render_margin exists for, §5 session E), and traffic is visible up
	# there — so with a reach that now extends into that strip, stopping the
	# paint at y = 0 would leave cars being visibly shoved aside above the end
	# of the corridor that is shoving them.
	var top: float = max(-board.vertical_margin, board.player_car.position.y - SIREN_REACH)
	if bottom - top <= 1.0:
		return

	# The wash slides between the two colours rather than cutting, so the
	# lane never goes flat grey between flashes.
	var wash: Color = SIREN_RED.lerp(SIREN_BLUE, 0.5 + 0.5 * sin(_pulse * FLASH_SPEED))
	board.draw_rect(Rect2(x - half, top, half * 2.0, bottom - top), Color(wash.r, wash.g, wash.b, CORRIDOR_WASH_ALPHA * fade), true)

	# Red down the left edge and blue down the right, strobing out of phase
	# with each other and in phase with the matching lamp on the car's roof —
	# so the corridor is visibly this car's light being thrown up the road,
	# not a marking that was already painted there.
	var red_lit: float = _lit(0.0)
	var blue_lit: float = _lit(PI)
	board.draw_line(Vector2(x - half, top), Vector2(x - half, bottom), Color(SIREN_RED.r, SIREN_RED.g, SIREN_RED.b, (0.25 + 0.55 * red_lit) * fade), 2.5)
	board.draw_line(Vector2(x + half, top), Vector2(x + half, bottom), Color(SIREN_BLUE.r, SIREN_BLUE.g, SIREN_BLUE.b, (0.25 + 0.55 * blue_lit) * fade), 2.5)

	# Chevrons racing up the lane, fading out at the far end so the corridor
	# dissolves into the road instead of stopping on a hard line.
	var travelled: float = _pulse * CHEVRON_SPEED
	var offset: float = fmod(travelled, CHEVRON_SPACING)
	var scrolled: int = int(travelled / CHEVRON_SPACING)
	var count: int = int((bottom - top) / CHEVRON_SPACING) + 1
	for i in range(count):
		var cy: float = bottom - offset - float(i) * CHEVRON_SPACING
		if cy < top:
			break
		var depth: float = clamp((cy - top) / (bottom - top), 0.0, 1.0)
		# Parity counted from a scroll-corrected index, not from i: i alone
		# is a fixed screen slot, so the colours would sit still while the
		# arrows moved through them. `i - scrolled` travels with the arrow.
		var col: Color = SIREN_RED if posmod(i - scrolled, 2) == 0 else SIREN_BLUE
		var pts := PackedVector2Array([
			Vector2(x - half * 0.62, cy + CHEVRON_HEIGHT),
			Vector2(x, cy),
			Vector2(x + half * 0.62, cy + CHEVRON_HEIGHT),
		])
		board.draw_polyline(pts, Color(col.r, col.g, col.b, 0.75 * depth * fade), 3.0)

# The light bar on the roof, above everything including Nitro's energy.
#
# NOTE: this hook runs inside SkillOverlay._draw(), not PlayerBoard._draw().
# Godot only accepts draw_* calls on the CanvasItem currently drawing, so
# board.draw_*() here would be refused at runtime ("Drawing is only allowed
# inside NOTIFICATION_DRAW"). The overlay is a child of the board at (0,0),
# so its local space is the board's and every coordinate below is figured the
# same way draw_board() figures its own.
func draw_overlay() -> void:
	var fade: float = _fade()
	if fade <= 0.0:
		return
	var canvas: CanvasItem = board.skill_overlay
	if canvas == null:
		return

	# The DRAWN sprite, not the footprint — the lamps sit on painted hardware
	# and the beams leave a painted nose, so every number below is measured
	# against the picture of the car rather than against its hitbox.
	var sz: Vector2 = _sprite_size()
	# player_car.position, not the steering position: the beacon is bolted to
	# the car, so it should ride Nitro's lift and shudder with it.
	var roof: Vector2 = board.player_car.position + Vector2(0.0, sz.y * LAMP_Y_FRAC)
	var lamp_r: float = max(LAMP_RADIUS_MIN, sz.x * LAMP_RADIUS_FRAC)
	var spread: float = sz.x * LAMP_SPREAD_FRAC

	# There used to be a dark housing rectangle drawn under the lamps, so the
	# two glows read as mounted hardware rather than as something the car was
	# on fire with. It is gone: the car IS a police cruiser now
	# (POLICE_TEXTURE) and has a real light bar painted on it, which the fake
	# housing did nothing but cover up. Blue on the left and red on the right,
	# matching the painted bar rather than the corridor's edges.
	# The beams are thrown from the NOSE of the car, not from the lens. The
	# lamps sit at the car's middle now that they are on its painted light
	# bar, and a beam starting there washes red and blue over the bonnet the
	# player is trying to look past. Light leaves the car; it does not sit on
	# it.
	var nose_y: float = board.player_car.position.y - sz.y * 0.5
	_draw_lamp(canvas, roof + Vector2(-spread, 0.0), nose_y, lamp_r, SIREN_BLUE, _lit(PI), fade, sz)
	_draw_lamp(canvas, roof + Vector2(spread, 0.0), nose_y, lamp_r, SIREN_RED, _lit(0.0), fade, sz)

# The size the cruiser is actually drawn at: the footprint scaled by
# CAR_SCALE, which is what Car.sprite_scale_mult does to the Sprite2D. Both
# factors are read live rather than cached, so Compact shrinking the car or
# Nitro doing nothing at all are both already handled.
#
# Everything in draw_overlay() is figured off this and NOT off car_size(),
# which is the hitbox and is deliberately a different, smaller thing (see
# CAR_SCALE). draw_board()'s corridor is the other way round — it is a lane
# being cleared, so it is measured against the road, not against the car.
func _sprite_size() -> Vector2:
	return board.car_size() * CAR_SCALE

# One lamp: a beam thrown forward up the road, a soft halo, the lens, and a
# white-hot center. Kept faint (the beams especially) because this layer sits
# over the traffic the player is trying to read.
func _draw_lamp(canvas: CanvasItem, at: Vector2, beam_y: float, r: float, col: Color, lit: float, fade: float, sz: Vector2) -> void:
	var beam_len: float = sz.y * 2.4
	var beam_half: float = r * 2.6
	# Widening toward -y, which is up the road, which is where the traffic
	# being shouted at is. The two beams overlap in the middle and the
	# red/blue mix there is exactly what a real light bar throws. The base
	# sits at beam_y (the car's nose) while the lens stays at `at`, so the
	# beam reads as leaving the car rather than as painted on it.
	var beam := PackedVector2Array([
		Vector2(at.x - r * 0.5, beam_y),
		Vector2(at.x + r * 0.5, beam_y),
		Vector2(at.x + beam_half, beam_y - beam_len),
		Vector2(at.x - beam_half, beam_y - beam_len),
	])
	canvas.draw_colored_polygon(beam, Color(col.r, col.g, col.b, 0.13 * lit * fade))
	canvas.draw_circle(at, r * 2.4, Color(col.r, col.g, col.b, 0.16 * lit * fade))
	canvas.draw_circle(at, r, Color(col.r, col.g, col.b, (0.35 + 0.6 * lit) * fade))
	canvas.draw_circle(at, r * 0.42, Color(1.0, 1.0, 1.0, (0.25 + 0.7 * lit) * fade))

# The HUD bar shifts between the two siren colours on the same beat as the
# lamps, so the timer under the boost bar is identifiably this skill's
# without needing a label. Its alpha is held constant — the bar is a readout
# and must stay legible while the effect itself is fading out.
func bar_color() -> Color:
	var col: Color = SIREN_RED.lerp(SIREN_BLUE, 0.5 + 0.5 * sin(_pulse * FLASH_SPEED))
	return Color(col.r, col.g, col.b, 0.95)
