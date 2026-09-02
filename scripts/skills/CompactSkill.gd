extends SkillEffect

## COMPACT — the player's car shrinks for a few seconds.
##
## The other two self skills change the player's *relationship* to the road:
## Tank Mode makes them untouchable, Nitro takes them off it altogether. This
## one leaves that relationship alone and changes the geometry instead. The
## traffic is untouched, the road is untouched, the player's speed is
## untouched — the car is simply narrower than the gaps it could not thread a
## second ago, and that is the whole benefit. It is deliberately not a third
## flavour of "you cannot lose for N seconds": a compact car that drives into
## a bus still dies.
##
## Mechanically it is one hook. car_kind() reports a smaller footprint and
## every consumer of the player's size re-reads that on its own — the dash's
## shoulder clamp, steer_bounds(), the drift trail width, the skill-choice
## icon offset, the collision box, and BotDriver's sense of what fits in a
## gap (§7: the bot reads car_size()/steer_bounds()/steer_top_speed() as real
## methods rather than copying constants, so a bot-driven board gets all of
## this for free). Everything else in this file is the housekeeping needed to
## make the drawn world agree with that hook at both ends of the timer, plus
## the visuals.
##
## Tank Mode outranks this in PlayerBoard._current_kind(). Pick "self" twice
## and land a tank while compact is still running, and the tank's footprint
## wins for as long as it lasts, after which this one resumes (that is what
## the refresh_car_size() call at the end of _deactivate_tank_mode() is for).
## That precedence is correct — a vehicle that is invincible and crushes what
## it hits has no business also being pocket-sized — so nothing here fights
## it. The visuals below simply stand down while some other footprint is in
## force rather than drawing a slack readout that is not true. Please leave
## that alone; it is a decision, not an oversight.
##
## Re-picking compact while it is already running resets time_left to
## duration() before refresh() is called, and every animation here is derived
## from time_left rather than from a Tween or a counter of its own — so a
## re-pick replays the shrink flash and re-arms the grow-back telegraph with
## no code. That is also why there is no Tween anywhere in this file: killing
## one skips its remaining callbacks, which is exactly how session G leaked a
## smoke sprite into the next round (§5/§12).

# --- Tuning ----------------------------------------------------------------

# One second longer than TANK_MODE_DURATION (6.0), because this skill does
# not remove the threat — it only makes gaps passable, and the player still
# has to find a gap and commit to it. A tank can simply drive at whatever is
# in front of it, so it needs less time to be worth picking. Still under
# SKILL_PICKUP_INTERVAL_MIN (9.0), so a compact has normally expired before
# the next pickup can even appear and a player rarely has to read two of
# these timers at once.
const DURATION := 7.0

# PlayerBoard.PLAYER_KIND's own two numbers, copied rather than referenced.
# Naming PlayerBoard from here would close a cycle — PlayerBoard preloads
# SkillCatalog, which preloads this file — the same cyclic-class-reference
# rule that keeps SkillEffect.board and BotDriver.board untyped (§7). If
# PLAYER_KIND is ever retuned, these two have to follow it by hand.
const NORMAL_WIDTH_FRAC := 0.62
const NORMAL_HEIGHT_FRAC := 1.69

# Fraction of the normal car's WIDTH the compact car keeps. Only the width
# moves: height_frac in PlayerBoard._car_size() is a multiplier on the
# computed width, not an independent fraction of the lane, so scaling the
# width alone shrinks the car uniformly and the sprite keeps its aspect
# ratio. Touching height_frac would squash or stretch the same texture, which
# reads as a rendering fault rather than as a smaller car.
#
# 0.66 sits in the middle of the usable band. At the default 5 lanes the car
# goes from ~0.62 of a lane wide to ~0.41, so it loses a third of its width:
# unmistakably smaller at a glance, and a gap that was a hair too tight
# becomes comfortably passable, while the silhouette is still obviously the
# same car and not a different, tiny vehicle. Much below this and the car
# stops reading as the player's own; much above and nothing that was closed
# actually opens, which would leave the skill a no-op that only looks
# different.
const SHRINK := 0.66
const COMPACT_WIDTH_FRAC := NORMAL_WIDTH_FRAC * SHRINK
const COMPACT_KIND := {"width_frac": COMPACT_WIDTH_FRAC, "height_frac": NORMAL_HEIGHT_FRAC}

# A lighter car turns in a little quicker. Deliberately small: the real
# agility win here is already geometric — a narrower car has less distance to
# cover before its flank clears the car beside it, and narrower bodywork
# widens steer_bounds() at both shoulders — so this number exists to make the
# handling *feel* like it followed the bodywork, not to make this a speed
# skill. For scale, Tank Mode pulls the same lever nearly four times as hard
# in the other direction (TANK_STEER_SPEED_MULT 0.72), and steer_top_speed()
# multiplies every live effect's hook together, so anything larger here would
# compound badly with a future skill that also touches steering.
const STEER_MULT := 1.08

# --- Visuals ---------------------------------------------------------------
# All procedural (draw_* calls), like SkillPickup's glow and PlayerBoard's
# boost flame — this skill has no in-round art asset, only its choice-icon
# glyph. Everything below is derived from time_left, so there is no clock,
# no node and no tween to leak.

# Mint. Deliberately not Tank's olive (0.42, 0.5, 0.22), Nitro's blue
# (0.35, 0.72, 1.0) or the pickup's gold — a player glancing at another
# board should be able to name the skill from the colour alone, and this is
# the fourth one in that set.
const TINT := Color(0.42, 0.98, 0.76)

const IMPLODE_TIME := 0.26 # ring collapsing full-size -> compact, at the moment of the shrink
const EXPAND_TIME := 0.34 # the same ring running outward, timed to arrive exactly as the car grows back
const WARN_LEAD := 1.1 # how long before the end the ghost outline starts blinking urgently
const BREATHE_HZ := 0.9 # slow idle pulse of the glow/ghost while there is plenty of time left
const WARN_HZ := 4.5 # ...and what that pulse accelerates to as the clock runs out
const RING_WIDTH := 2.5
const GHOST_WIDTH := 2.0
const CORNER_FRAC := 0.28 # length of each ghost corner tick, as a fraction of the ghost box's own side
const GLOW_LAYERS := 3 # nested translucent rects standing in for a soft falloff, same trick SkillPickup uses with circles

# Set the instant deactivate() starts, before it asks the board to recompute
# anything, and what makes deactivate() idempotent — see there.
var _retired: bool = false

func duration() -> float:
	return DURATION

# --- Hooks -----------------------------------------------------------------

# A retired effect claims nothing. PlayerBoard drops an effect out of
# active_effects before calling deactivate(), so by the time the board is
# asked to put the car back this hook is no longer consulted at all — the
# guard is belt and braces for the idempotency deactivate() promises, and
# for any future caller that reaches a finished effect directly.
func car_kind() -> Dictionary:
	if _retired:
		return {}
	return COMPACT_KIND

func steer_speed_mult() -> float:
	if _retired:
		return 1.0
	return STEER_MULT

func activate() -> void:
	_retired = false
	# PlayerBoard lists an effect in active_effects before calling this, so
	# the board's _current_kind() already answers COMPACT_KIND here — one
	# refresh lands the shrink on the sprite and its collision box in the
	# same frame as the pick, before the steering block reads car_size() and
	# long before anything is drawn. Every other reader of the footprint
	# (steer_bounds, the dash clamp, the bot) is live and needs no poke;
	# Car.set_size is the one consumer that does not re-read it on its own.
	# Going through refresh_car_size() rather than set_size() by hand is
	# what keeps _current_kind()'s Tank-first precedence in one place.
	board.refresh_car_size()

# Called on the timer running out, on a round restart, and on elimination —
# possibly mid-effect, which is why every step here is written to be safe on
# a car that was never actually shrunk.
func deactivate() -> void:
	if _retired:
		return
	# Retract the claim before asking the board for anything. PlayerBoard
	# has already dropped this effect from active_effects by the time it
	# calls deactivate(), so refresh_car_size() and steer_bounds() below
	# answer for the full-size car regardless — the flag is what keeps that
	# true if this is ever reached from anywhere else, and what makes a
	# second call a no-op.
	_retired = true
	board.refresh_car_size()

	# The dangerous half. A wider car has narrower steer_bounds(), so the x
	# the player was legally holding a frame ago can now be over the shoulder.
	var bounds: Vector2 = board.steer_bounds()
	board.car_x = clamp(board.car_x, bounds.x, bounds.y)
	if board.is_dashing:
		# The board's steering block re-clamps car_x every frame on its own,
		# so for a car that is steering the line above is belt and braces.
		# A dash is not steering: while is_dashing, _process writes car_x
		# straight from lerp(dash_from, dash_to) and never consults the
		# bounds again — dash_to was computed against the compact car's
		# wider bounds back when the dash started, so the clamp above would
		# be undone on the very next frame and the car would ride the
		# shoulder for the rest of the dash.
		#
		# Re-clamping both endpoints re-targets the dash in flight instead.
		# The eased lerp between them stays continuous in t, so the rest of
		# the dash still moves smoothly; only the current frame jumps, and
		# it has to — the car got bigger while sitting somewhere a bigger
		# car cannot sit, so something must move.
		#
		# Rejected: cancelling the dash outright. It throws away an input
		# the player has already committed to, in the middle of a gap, at
		# the exact moment their car grew — and it would mean reaching in to
		# set is_dashing and dash_cooldown_timer by hand, duplicating the
		# end-of-dash bookkeeping in _process. A shortened dash is a much
		# smaller lie than a cancelled one.
		board.dash_from = clamp(board.dash_from, bounds.x, bounds.y)
		board.dash_to = clamp(board.dash_to, bounds.x, bounds.y)
	# Two things are deliberately left alone. car_vx: if it is still pointing
	# at the shoulder, the board's own steering clamp zeroes it next frame,
	# which is the same treatment any other bounds violation gets. And an
	# in-flight drift's trail width, which _begin_drift_trails() fixed at the
	# compact car's width when the slide started — re-widening a Line2D
	# mid-trail would put a visible step in a mark that is meant to be one
	# continuous skid, and the trail ends on its own shortly anyway.

# --- Drawing ---------------------------------------------------------------

# True only while THIS effect's footprint is the one actually in force. Tank
# Mode outranks car_kind() outright, and any resize that claimed before this
# one wins by first-claim (see PlayerBoard._effect_car_kind), in which case a
# slack readout drawn around a car that is not compact would be a straight
# lie about how much room the player has — so the whole effect goes quiet
# instead. Tested by comparing the live width rather than the kind
# dictionaries, which match by reference and would answer wrongly.
func _is_in_force() -> bool:
	if _retired or board == null:
		return false
	var live: Vector2 = board.car_size()
	return is_equal_approx(live.x, board.road.lane_width() * COMPACT_WIDTH_FRAC)

# x comes from car_x (steering space) and not from player_car.position, whose
# x carries Nitro's per-frame shudder — a bracket that vibrates would read as
# the rendering being broken, which is the one thing an effect about the car
# looking wrong-sized must never look like. y does come from the car node, so
# the readout stays welded to the car through Nitro's lift and Tank's recoil
# instead of sliding off it onto bare asphalt.
func _car_center() -> Vector2:
	return Vector2(board.car_x, board.player_car.position.y)

# The box the car occupies at a given width fraction, centred on the car.
# Rebuilt from lane_width() each call rather than cached because the board
# can be resized between rounds (Main pushes width down per player count).
func _box(width_frac: float) -> Rect2:
	var w: float = board.road.lane_width() * width_frac
	var size := Vector2(w, w * NORMAL_HEIGHT_FRAC)
	return Rect2(_car_center() - size * 0.5, size)

# Road-surface layer: under the traffic, so cars pass OVER these marks and
# they read as paint on the asphalt rather than as something stuck to the
# lens. That is the point of putting the steady-state readout here and the
# two flashes in the air above.
func draw_board() -> void:
	if not _is_in_force():
		return
	var small := _box(COMPACT_WIDTH_FRAC)
	var full := _box(NORMAL_WIDTH_FRAC)
	# One phase driving everything: a slow idle pulse that accelerates into a
	# blink over the last WARN_LEAD seconds, so the grow-back is visible
	# coming on the road as well as on the HUD bar. Derived from time_left,
	# never accumulated, so a re-pick restarts it cleanly.
	var urgency: float = 1.0 - clamp(time_left / WARN_LEAD, 0.0, 1.0)
	var hz: float = lerp(BREATHE_HZ, WARN_HZ, urgency)
	var pulse: float = 0.5 + 0.5 * sin((DURATION - time_left) * TAU * hz)

	# Low glow hugging the reduced silhouette: nested translucent rects
	# standing in for a soft falloff (the same cheap trick SkillPickup uses
	# with circles). It hugs the SMALL box on purpose — the glow's job is to
	# say "this size is deliberate", so it has to trace the body the car
	# actually has.
	for i: int in range(GLOW_LAYERS):
		var t: float = float(i) / float(GLOW_LAYERS)
		var spread: float = small.size.x * (0.16 + 0.55 * t) * (0.88 + 0.12 * pulse)
		board.draw_rect(small.grow(spread), Color(TINT.r, TINT.g, TINT.b, 0.12 * (1.0 - t)), true)

	# The ghost of the car's own full-size body, drawn where the bodywork
	# used to be. The gap between it and the car IS the skill: anything that
	# fits between the ghost's edge and a passing car is room the player did
	# not have a moment ago, and it is measured rather than asserted. Corner
	# ticks only, not a closed outline — a second full rectangle around the
	# car reads as a second car.
	_draw_corners(full, Color(TINT.r, TINT.g, TINT.b, lerp(0.28, 0.8, pulse)))

# Eight short lines: an L at each corner of `rect`, pointing inward.
func _draw_corners(rect: Rect2, color: Color) -> void:
	var arm_x: float = rect.size.x * CORNER_FRAC
	var arm_y: float = rect.size.y * CORNER_FRAC
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			# sx/sy of -1 is the low edge (left/top), +1 the high edge, and
			# subtracting the signed arm from the corner always walks back
			# into the box whichever corner this is.
			var px: float = rect.position.x if sx < 0.0 else rect.position.x + rect.size.x
			var py: float = rect.position.y if sy < 0.0 else rect.position.y + rect.size.y
			board.draw_line(Vector2(px, py), Vector2(px - sx * arm_x, py), color, GHOST_WIDTH)
			board.draw_line(Vector2(px, py), Vector2(px, py - sy * arm_y), color, GHOST_WIDTH)

# Above everything, including Nitro's energy — the two moments, as opposed to
# the steady state on the road below.
func draw_overlay() -> void:
	if not _is_in_force():
		return
	# NOT board.draw_*, unlike draw_board() above. This hook is called from
	# SkillOverlay._draw(), a separate CanvasItem child of the board — that
	# is the entire reason SkillOverlay exists, since a parent draws beneath
	# its own children and PlayerBoard._draw() can therefore never get above
	# the traffic. Godot only permits draw calls on the canvas item that is
	# currently drawing, so a board.draw_*() from in here would fail at
	# runtime and paint nothing. The overlay sits at the board's origin, so
	# the coordinates are the same board-local ones draw_board() uses.
	var canvas: CanvasItem = board.skill_overlay
	if canvas == null:
		return
	var small := _box(COMPACT_WIDTH_FRAC)
	var full := _box(NORMAL_WIDTH_FRAC)
	var elapsed: float = DURATION - time_left

	if elapsed < IMPLODE_TIME:
		# The shrink, seen: a ring collapsing from the body the car had onto
		# the body it now has. Eased so it is fastest at the first frame,
		# which is the frame the car actually changed size on — the ring is
		# reporting that event, not performing it.
		var t_in: float = clamp(elapsed / IMPLODE_TIME, 0.0, 1.0)
		_draw_ring(canvas, full, small, 1.0 - pow(1.0 - t_in, 3.0), 1.0 - t_in)
	elif time_left < EXPAND_TIME:
		# The grow-back, telegraphed rather than reported: the same ring runs
		# outward and reaches the full-size outline at the exact moment the
		# car does. It has to be drawn ahead of the event because
		# deactivate() cannot draw at all — it is called once, from outside
		# any _draw(), and the effect is dropped immediately after — and
		# because a warning that arrives after the car is already wide is
		# not a warning. Accelerating (t squared) so it lands on the beat.
		var t_out: float = clamp(1.0 - time_left / EXPAND_TIME, 0.0, 1.0)
		_draw_ring(canvas, small, full, t_out * t_out, t_out)

# One rect outline interpolated between two boxes, plus a fainter one just
# outside it for a bit of bloom. Drawn on `canvas` rather than on the board,
# see draw_overlay().
func _draw_ring(canvas: CanvasItem, from_box: Rect2, to_box: Rect2, t: float, alpha: float) -> void:
	var ring := Rect2(from_box.position.lerp(to_box.position, t), from_box.size.lerp(to_box.size, t))
	canvas.draw_rect(ring, Color(TINT.r, TINT.g, TINT.b, 0.9 * alpha), false, RING_WIDTH)
	canvas.draw_rect(ring.grow(RING_WIDTH * 1.6), Color(TINT.r, TINT.g, TINT.b, 0.22 * alpha), false, RING_WIDTH)

# The HUD timer bar, stacked under the boost bar with Tank's and Nitro's.
# Worth having even though the road-surface ghost already blinks: the bar is
# where a player already looks for "how long have I got", and the grow-back
# is the moment this skill can kill you — you can be sitting in a gap that
# stops existing.
func bar_color() -> Color:
	return Color(TINT.r, TINT.g, TINT.b, 0.95)
