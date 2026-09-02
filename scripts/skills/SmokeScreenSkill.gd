extends SkillEffect

## SMOKE SCREEN (catalog id "smoke") — an opponent skill that attacks the
## victim's *information*, and nothing else.
##
## The Taxi (§5 sessions I/L) is a rogue vehicle with its own AI; Oil Slick
## takes the victim's grip. Both change what the world *does*. This one
## changes what the victim can *see*:
## a bank of smoke rolls across the upper part of their board, traffic
## emerges from it far later than usual, and every gap has to be read in
## about half the time it normally gets. The road underneath is exactly as
## fast and exactly as crowded as it was a second ago; the car steers exactly
## as it did. The danger is only that the victim now finds out about each car
## late — and the restraint is the design: it is the one skill in the game
## that takes nothing away from the player except what they can see.
##
## WHAT IT DELIBERATELY DOES NOT TOUCH — every physics hook stays at the base
## class's default, and that is a statement, not an omission:
##  * road_speed_mult(): the traffic is not slower and not faster. Slowing
##    the road "to be fair" would hand back the reaction time the skill just
##    took, and speeding it up would make this a worse Nitro-for-others.
##  * steer_speed_mult() / grip_mult(): the car is not loose. That is Oil
##    Slick's whole identity, and two skills that both make you miss the gap
##    you aimed at are one skill with two icons.
##  * car_kind() / absorbs_crash(): nothing about the car changes and nothing
##    about a crash changes. A crash inside the smoke costs the same life it
##    would have cost in clear air — the smoke is why it happened, not a
##    modifier on what it costs.
## Everything this file does is drawing. It writes no field on the board,
## creates no node, and its deactivate() has nothing to undo except the
## overlay's own last frame (see there).
##
## THE HONEST LIMITATION: BotDriver is completely immune to this. The bot
## senses traffic from obstacle_container's children and their meta keys
## (see BotDriver's header), never from pixels, so a bot-driven board hit by
## this skill draws the smoke faithfully and plays exactly as well as before.
## That is not worth "fixing": the only way to do it would be to hand the
## bot an artificial handicap (a delayed or truncated sensing window) that
## is a *model* of being blinded rather than being blinded, and it would have
## to be tuned by feel against a human's actual reaction to smoke — a number
## nobody can measure. A single-player round against bots therefore gets no
## value out of picking this, and the next person to wonder why should be
## able to read it here rather than discover it. The other opponent skills
## do hit the bot (a taxi is a real car, a slick is a real grip change), so
## this is a property of this skill, not of the skill layer.
##
## ART: none. The whole in-round visual is procedural (draw_* calls on the
## overlay), like SkillPickup's glow and Oil Slick's spill field. The only
## file this skill owns is its choice-icon glyph, sprites/skills/icon_smoke.png,
## which the catalog already wires up.

# --- Timing -----------------------------------------------------------------

# Same bracket as Oil Slick (5.0) and Tank Mode (6.0), so the two sides of a
# skill choice feel like comparable spends. Five seconds is roughly the time
# the road takes to scroll the board past twice at mid-round speed, so at
# least two full waves of traffic arrive out of the smoke before it lifts —
# a two-second version could be survived by holding whatever lane happened
# to be clear when it landed, which makes it a moment of noise rather than
# an attack.
const DURATION := 5.0

# The smoke rolls in fast and thins out slower. In (0.4s): the band drops
# from the HUD strip to its full extent over this time (see _reach), which is
# what makes it read as an attack arriving rather than a filter switching on
# — but any slower and the first second of a five-second skill is spent
# still arriving. Out (0.7s): dissipating smoke is the one pleasant part of
# this skill and it deserves to be read, and the victim's HUD bar already
# tells them the exact moment it ends, so the visual can afford to lag it.
# Both are "a few tenths of a second": under ~0.25 either edge snaps and
# reads as a glitch; over ~1.0 the fade eats a fifth of the effect.
const FADE_IN := 0.4
const FADE_OUT := 0.7

# --- Where the band sits -----------------------------------------------------
#
# Three hard constraints, in order of how badly it goes if one is broken:
#  1. It must not cover the HUD strip at the top. The overlay draws ABOVE
#     PlayerBoard._draw() (SkillOverlay.OVERLAY_Z, above even Nitro's
#     energy), so it would paint straight over the boost bar and every timer
#     stacked under it. A player who cannot see their own boost charge will
#     think the game broke, not that they were attacked.
#  2. It must not cover the player's own car near the bottom. Taking away the
#     thing they steer reads as a rendering bug.
#  3. It must be dense enough to matter and thin enough to survive — see the
#     density block below.

# Clear pixels kept between the *bottom* of the boost bar and the first
# wisp. The bar's own position is read live off the board
# (BOOST_BAR_MARGIN_TOP + BOOST_BAR_HEIGHT, see _band_top) so the smoke
# follows the HUD if it ever moves; this reserve is for what stacks UNDER
# the bar, which _draw() decides frame by frame and this file cannot know:
# the tank timer (4 + 6), the nitro timer (4 + 6), and one 4 + 6 skill bar
# per live modular effect. Tank + Nitro + three skill bars is 50px, which is
# already more than any real round stacks; 56 leaves that a little room, and
# the top feather (below) is thin for its first TOP_FEATHER_PX anyway. The
# "BOT · NORMAL" tag (BOT_TAG_Y 49) sits inside this reserve too.
#
# A consequence worth knowing: the strip above the band is clear road, and
# the camera can see above y = 0 by vertical_margin besides, so a car
# entering at the top (_spawn_obstacle puts it at -car height - 40) is
# visible for its first ~120px of travel — a glimpse of a quarter second
# at mid-round speed — before the smoke swallows it. That is accepted, and
# arguably better than a band that starts at the very top edge: the victim
# is shown which lane each car is in and then made to *remember* it, which
# is a harder and more interesting thing to fail at than never having seen
# it. Covering that strip would also mean painting over the HUD, which is
# constraint 1 above and not negotiable.
const HUD_CLEAR_RESERVE := 56.0

# The band's top edge is feathered too, over this many px, so it does not
# start on a hard line under the HUD. Short, because the strip above it is
# busy with bars and a soft edge is all that is needed to stop it looking
# like a panel.
const TOP_FEATHER_PX := 28.0

# Fractions of board_height. The core (full density) runs from the HUD strip
# down to CORE_BOTTOM_FRAC; below that it feathers out to nothing at
# BAND_BOTTOM_FRAC. On the 620px board that is a core ending at 236px and
# clear road from 322px. The player's car roof sits at ~540px
# (board_height - CAR_BOTTOM_MARGIN - car height), so the victim gets ~218px
# of clear approach instead of the ~540 they are used to — 40% of it — plus
# the 86px feather where a car is half-legible and the faint silhouettes
# inside the core. Call that "read in half the time", which is the brief.
# The car itself stays clear by a wide margin in every state: Tank Mode's
# taller roof is at ~513px, and Nitro lifts the car 105px to ~435px, still
# 113px under the band — and while airborne the victim is not reading gaps
# anyway. Lowering BAND_BOTTOM_FRAC past ~0.6 starts closing on the nitro
# roof; raising CORE_BOTTOM_FRAC past ~0.45 leaves less than a car length of
# clear road per lane change and stops being fair.
const CORE_BOTTOM_FRAC := 0.38
const BAND_BOTTOM_FRAC := 0.52

# The bottom feather is drawn as this many stacked gradient slices rather
# than one (ScreenMask's technique, split). A single linear ramp meets the
# clear road on a visible crease — it is the change in slope the eye
# catches, not the value — and three slices sampled off smoothstep bend it
# into a curve at the cost of two extra polygons.
const FEATHER_STEPS := 3

# --- Density ----------------------------------------------------------------
#
# Partial occlusion, not a blindfold. Alpha composes as 1 - Π(1 - a), so the
# numbers below are chosen for what they add up to, not for what each is:
#   * BASE_ALPHA alone (the thinnest spot, between puffs):        0.44
#   * base + one puff halo (the typical spot):                    ~0.51
#   * base + halo + core (a puff centred on you):                 ~0.61
#   * base + three halos + two cores (the thickest knot):         ~0.76
# At 0.76 a dark car on grey asphalt keeps about a quarter of its contrast:
# enough to know *something* is in that lane, not enough to see whether its
# indicator is lit or which way it is sliding — which is exactly the
# information this skill exists to take. Above ~0.85 the road is simply gone
# and the victim stops steering and starts praying, which is not a skill,
# it is a coin flip; below ~0.5 everywhere, cars read through it fine and
# the skill is not felt at all. The unevenness itself is deliberate: a slab
# of one alpha is a filter, a curtain of varying density is weather, and a
# thin spot the victim can peer through for a moment is the kind of thing
# they will remember and try to use.
const BASE_ALPHA := 0.44
const PUFF_HALO_ALPHA := 0.12
const PUFF_CORE_ALPHA := 0.20

# A light, slightly warm grey — smoke, not fog. The road texture under it is
# a mid grey, so the band has to be *lighter* than the asphalt to read as a
# thing in the air rather than a shadow on the ground. Puff cores are lifted
# a little further so the knots look lit from above, and each puff is shaded
# +/- PUFF_SHADE_SPREAD so the bank has depth instead of being one value.
const SMOKE := Color(0.74, 0.72, 0.70)
const PUFF_CORE_LIFT := 0.08 # added to each channel for the core
const PUFF_SHADE_SPREAD := 0.06 # per-puff +/- on every channel

# --- Puff field -------------------------------------------------------------
#
# The band's motion. The base slices are static geometry (they are *where*
# the smoke is); the puffs are the smoke moving through that geometry. They
# scroll down the board at the road's own rate, wrapping from the bottom of
# the band back to the top of it, so the bank belongs to the world — it is
# hanging over the road and the road is coming at the player — rather than
# being a filter stuck to the glass.

# Count is picked for coverage arithmetic, not by eye, since this file could
# not be run while it was written. The band is ~360 x 243px ≈ 87,000px²; a
# mean puff (radius ~56px) is ~9,900px² of halo, so 14 of them cover the band
# ~1.6 times over. That puts a typical point under one or two halos and
# leaves real gaps between them, which is the varying density described
# above. At 8 the coverage drops under 1.0 and the base slab shows through
# everywhere; at 24 it passes 2.5 and tiles into a uniform sheet for twice
# the draw calls. Cost at 14
# is 28 draw_circle calls plus 5 polygons per board per frame — 132 calls
# across four boards, the same ballpark as Oil Slick's spill field, and
# nothing here allocates per frame.
const PUFF_COUNT := 14
# Radii as fractions of lane width (~53px on the 5-lane board): a small puff
# is two thirds of a lane, a big one is nearly a lane and a half. Sized off
# the lane rather than the board so a puff is always "about a car and a
# bit" — enough to hide one car, never enough to hide a whole row, whatever
# the lane count.
const PUFF_RADIUS_MIN_FRAC := 0.65
const PUFF_RADIUS_MAX_FRAC := 1.45
const PUFF_CORE_FRAC := 0.62 # the denser inner circle, as a fraction of the halo
# Each puff scrolls at its own multiple of the road rate, spread about 1.0.
# That spread IS the internal motion: at a mid-round road speed of ~400px/s
# it is +/-70px/s of relative drift, so puffs overtake and slide past each
# other and the knots where they overlap keep forming and breaking. Wider
# than +/-20% and the slow ones visibly hang in the air while the road
# leaves them behind; narrower and the bank scrolls as one rigid sheet.
const PUFF_SPEED_MIN := 0.82
const PUFF_SPEED_MAX := 1.18
# Sideways sway, as a sine of the effect's own clock. Amplitude is a third of
# a lane so a puff can drift from over one car to over the next but never
# leave the lane pair it started between; rates give periods of 8-18s, so
# inside a five-second effect each puff completes a quarter to a half
# swing — a lean, not an oscillation.
const PUFF_SWAY_FRAC := 0.35 # of lane width
const PUFF_SWAY_RATE_MIN := 0.35 # rad/s
const PUFF_SWAY_RATE_MAX := 0.8
# Radius breathing, +/- this fraction. Small on purpose: it is there so a
# puff that happens to be scrolling at exactly the road rate still looks
# alive, not so the bank pulses.
const PUFF_BREATH_FRAC := 0.07
const PUFF_BREATH_RATE_MIN := 0.6 # rad/s
const PUFF_BREATH_RATE_MAX := 1.1

# --- HUD --------------------------------------------------------------------

# The timer bar under the boost bar. The victim needs to know how long they
# are blind for, and the bar is the only readout that survives the effect
# (it is inside the HUD strip the band stays clear of). Light warm grey — the
# smoke's own colour — which nothing else stacks in: tank is olive, nitro is
# blue, slick is purple, compact is mint, siren strobes red/blue. Alpha held
# constant rather than enveloped, for the reason Siren gives: a readout must
# stay legible while the thing it reads out is fading.
const BAR := Color(0.80, 0.78, 0.74, 0.95)

# --- State ------------------------------------------------------------------

# Road-space scroll for the puff field, accumulated from the board's own
# odometer — see tick() for why not from current_speed() integrated here.
var _scroll: float = 0.0
var _last_distance: float = 0.0

# Bottom edge of the boost bar in board px, resolved once in activate() —
# see _resolve_hud_bottom for how and why it is not simply
# board.BOOST_BAR_MARGIN_TOP.
var _hud_bottom: float = 0.0

# Seconds since activate(), NOT derived from time_left. refresh() puts
# time_left back to DURATION when the skill is re-applied mid-effect, and a
# fade-in computed from time_left would make the whole bank blink out and
# roll in again at that moment. _age keeps running through a refresh, so a
# second smoke lands as more smoke, not as the same smoke starting over.
var _age: float = 0.0

# Clock for the sway and breathing. Seeded randomly so two boards hit by the
# same broadcast do not sway in lockstep — the same reason SkillPickup
# randomizes _pulse_t and Oil Slick its _phase.
var _clock: float = randf() * 100.0

# One entry per puff: {x0, y0, r, speed, sway, sway_rate, sway_phase,
# breath_rate, breath_phase, shade}. Built once in activate() and only read
# afterwards, so each puff keeps its identity as it scrolls instead of being
# re-rolled every frame into static.
var _puffs: Array[Dictionary] = []

# --- Lifecycle --------------------------------------------------------------

func duration() -> float:
	return DURATION

func activate() -> void:
	_last_distance = board.distance
	_hud_bottom = _resolve_hud_bottom()
	_build_puffs()

func refresh() -> void:
	# Re-picked while already running. The puff field and _age are left
	# exactly as they are: the air is already full of smoke, someone has just
	# added more. time_left was reset by the caller before this ran, and that
	# is the entire effect of a refresh here.
	pass

func tick(delta: float) -> void:
	_age += delta
	_clock += delta

	# Scroll from the *board's odometer delta*, not from current_speed()
	# integrated locally, even though current_speed() is exactly the rate
	# wanted. This is the §7 invariant ("scrolling scenery must derive its
	# distance from a board's odometer, never integrate its own"), and it
	# buys something real: `distance` already has boost, nitro, tank recoil
	# and the post-crash crawl folded into it through current_speed(), so
	# following it keeps the smoke welded to the road through all four
	# without this file knowing any of them exist. tick() runs before the
	# board advances `distance` for this frame, so what is read is the
	# previous frame's increment — in phase, one frame of lag, invisible.
	var travelled: float = board.distance - _last_distance
	_last_distance = board.distance
	# Guarded so that a distance reset under a live effect could only ever
	# cost one frame of scroll rather than hurl the whole bank back up.
	if travelled > 0.0:
		_scroll += travelled

func deactivate() -> void:
	# There is no board state to put back — this effect never wrote any: no
	# multiplier, no field, no node (so no repeat of the session G tank-smoke
	# leak, which is a pointed thing to be able to say about a smoke effect).
	#
	# The one thing that WOULD outlive it is the overlay's last drawn frame.
	# A CanvasItem keeps its draw list until it is next redrawn, and
	# PlayerBoard only asks skill_overlay to redraw while active_effects is
	# non-empty. So the frame after the last effect leaves the list, the
	# overlay still shows whatever that effect drew last: a faint residue on
	# natural expiry (the final frame's alpha), but on a round restart or an
	# elimination mid-effect — both of which reach here through
	# _clear_skill_effects() — a FULL-density smoke bank, permanently, until
	# some later skill happens to trigger a redraw. That is exactly the leak
	# the base class warns about. PlayerBoard now does this itself for every
	# effect that leaves the list (_redraw_skill_layers, added when this
	# file reported the residue) — the request below is kept as belt and
	# braces, and as the record of why the board's version exists. The board
	# removes this effect from active_effects before calling deactivate(),
	# so a redraw requested here runs without it and paints nothing of it.
	# Idempotent: a second call just requests the same empty redraw again.
	if board == null:
		return
	# Untyped on purpose: assigning a freed instance to a typed variable is
	# itself a runtime error, and is_instance_valid() is the check that is
	# meant to run first. (The overlay is freed with the board, so this
	# should never be reached with a dead one — but the cost of the guard is
	# nothing and the cost of being wrong is an error on every restart.)
	var overlay = board.skill_overlay
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_redraw()

# --- Physics hooks ----------------------------------------------------------
#
# None. road_speed_mult(), steer_speed_mult(), grip_mult(), car_kind() and
# absorbs_crash() are all left at the base class's defaults on purpose — see
# the header. The victim's car and road are untouched; only their view is.

# --- Envelope and geometry --------------------------------------------------

# Shared fade, 0..1. Rises off _age (not time_left — see _age) and falls off
# time_left, so the bank thins out over the last FADE_OUT seconds of the bar.
func _envelope() -> float:
	var rise: float = clamp(_age / FADE_IN, 0.0, 1.0)
	var fall: float = clamp(time_left / FADE_OUT, 0.0, 1.0)
	return min(rise, fall)

# How far down the board the band has rolled, 0..1. The bank arrives from
# the top over FADE_IN rather than fading up in place: at 0.5 the band's
# bottom edges are halfway to their final positions. Smoothstepped so the
# leading edge decelerates into place instead of stopping dead. Stays at 1.0
# through a refresh (it is off _age) and through the fade-out (the bank
# thins where it is; it does not retreat).
func _reach() -> float:
	return smoothstep(0.0, 1.0, clamp(_age / FADE_IN, 0.0, 1.0))

# Top edge of the band: just under whatever the HUD stacks below the boost
# bar.
func _band_top() -> float:
	return _hud_bottom + HUD_CLEAR_RESERVE

# Where the boost bar ends, read off PlayerBoard's own constants rather than
# copied here — copying a PlayerBoard constant into a skill file is the
# duplication trap §7 records BASE_SPEED falling into, and this one is
# load-bearing: it is what keeps the smoke off the HUD.
#
# Read through the script's constant map rather than as
# `board.BOOST_BAR_MARGIN_TOP`. `board` is untyped (the cyclic-reference
# rule), and scripts/dev/SkillProbe.gd records that reading a script
# constant off an untyped instance is the kind of access that resolves at
# runtime or not depending on the engine version; get_script_constant_map()
# is a documented Script API and does not have that doubt. It builds a
# Dictionary each call, which is why this is resolved once in activate()
# and cached, not read per frame. The fallbacks are the values at the time
# of writing (14 + 9) and are only reached if the constants are renamed —
# in which case the band lands where the bar used to be rather than
# erroring inside every draw.
func _resolve_hud_bottom() -> float:
	var consts: Dictionary = {}
	var board_script: Script = board.get_script()
	if board_script != null:
		consts = board_script.get_script_constant_map()
	var margin_top: float = float(consts.get("BOOST_BAR_MARGIN_TOP", 14.0))
	var bar_h: float = float(consts.get("BOOST_BAR_HEIGHT", 9.0))
	return margin_top + bar_h

# The band's final (fully rolled-in) bottom edges. Used both for the drawn
# geometry (scaled by _reach) and as the fixed wrap span for the puffs —
# fixed, because a wrap span that grew with _reach would move every puff's
# fmod boundary during the roll-in and teleport them.
func _core_bottom_final() -> float:
	return float(board.board_height) * CORE_BOTTOM_FRAC

func _band_bottom_final() -> float:
	return float(board.board_height) * BAND_BOTTOM_FRAC

# Density profile of the band at height y, 0..1: zero above the top edge,
# up through the top feather, one across the core, down through the bottom
# feather to zero at the band's bottom. The base slices draw this shape
# directly; the puffs multiply their alpha by it at their centre, which is
# what makes them dissolve into clear road at the bottom instead of
# scrolling out of the band as hard-edged discs.
func _profile(y: float, top: float, feather_top: float, core_bottom: float, band_bottom: float) -> float:
	if y <= top or y >= band_bottom:
		return 0.0
	if y < feather_top:
		return smoothstep(0.0, 1.0, (y - top) / max(feather_top - top, 0.001))
	if y <= core_bottom:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (y - core_bottom) / max(band_bottom - core_bottom, 0.001))

# --- Puff field -------------------------------------------------------------

func _build_puffs() -> void:
	_puffs.clear()
	var lane_w: float = board.road.lane_width()
	var w: float = board.board_width
	var span: float = _wrap_span()
	for i: int in range(PUFF_COUNT):
		var r: float = lane_w * randf_range(PUFF_RADIUS_MIN_FRAC, PUFF_RADIUS_MAX_FRAC)
		# Kept fully inside the board's width. The board's edge is also the
		# gutter between it and its neighbour (Main.BOARD_GAP), and smoke
		# drifting into that gutter reads as a rendering leak rather than as
		# weather; the base slices cover the shoulders out to the edge, so
		# nothing is lost by holding the puffs in.
		var x0: float = randf_range(min(r, w * 0.5), max(w - r, w * 0.5))
		_puffs.append({
			"x0": x0,
			# Spread over the whole wrap span so the bank is already full of
			# puffs when it rolls in, rather than starting empty and filling
			# from the top over the first second.
			"y0": randf() * span,
			"r": r,
			"speed": randf_range(PUFF_SPEED_MIN, PUFF_SPEED_MAX),
			"sway": lane_w * PUFF_SWAY_FRAC,
			"sway_rate": randf_range(PUFF_SWAY_RATE_MIN, PUFF_SWAY_RATE_MAX),
			"sway_phase": randf() * TAU,
			"breath_rate": randf_range(PUFF_BREATH_RATE_MIN, PUFF_BREATH_RATE_MAX),
			"breath_phase": randf() * TAU,
			"shade": randf_range(-PUFF_SHADE_SPREAD, PUFF_SHADE_SPREAD),
		})
	# Sorted largest first, so the small puffs are drawn last and sit on top
	# of the big ones — small bright knots over broad faint halos is how
	# smoke layers; the reverse looks like bubbles.
	_puffs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["r"]) > float(b["r"]))

# Vertical distance a puff travels before wrapping: the band's full extent
# plus the largest possible radius above and below, so a puff is entirely
# outside the profile (alpha 0) at the moment it teleports.
func _wrap_span() -> float:
	var pad: float = board.road.lane_width() * PUFF_RADIUS_MAX_FRAC
	return (_band_bottom_final() + pad) - (_band_top() - pad)

# --- Drawing ----------------------------------------------------------------

# Nothing on the road surface. This skill's whole point is that it sits
# between the traffic and the player's eyes, which only draw_overlay() can.
func draw_board() -> void:
	pass

# NOTE: this hook runs inside SkillOverlay._draw(), not PlayerBoard._draw(),
# so every draw_* call goes to board.skill_overlay — Godot refuses draw_*
# on any CanvasItem other than the one currently drawing. The overlay is a
# child of the board at its origin, so the coordinates are the board's own.
func draw_overlay() -> void:
	var fade: float = _envelope()
	if fade <= 0.0:
		return
	var canvas: CanvasItem = board.skill_overlay
	if canvas == null:
		return

	var w: float = board.board_width
	var top: float = _band_top()
	var reach: float = _reach()
	# Rolled-in geometry: both bottom edges travel from the top edge to their
	# final positions with _reach. The feather is proportionally shorter
	# while the bank is still arriving, which is right — the leading edge of
	# rolling smoke is its densest part.
	var core_bottom: float = lerp(top, _core_bottom_final(), reach)
	var band_bottom: float = lerp(top, _band_bottom_final(), reach)
	var feather_top: float = min(top + TOP_FEATHER_PX, core_bottom)
	if band_bottom - top < 1.0:
		return

	_draw_base(canvas, w, top, feather_top, core_bottom, band_bottom, fade)
	_draw_puffs(canvas, w, top, feather_top, core_bottom, band_bottom, fade)

# The band's floor: the density every point gets before any puff lands on
# it. Five gradient slices — top feather, core, and FEATHER_STEPS pieces of
# bottom feather — built exactly the way ScreenMask builds its vignette, as
# polygons with per-vertex colours.
func _draw_base(canvas: CanvasItem, w: float, top: float, feather_top: float, core_bottom: float, band_bottom: float, fade: float) -> void:
	var a: float = BASE_ALPHA * fade
	_draw_slice(canvas, w, top, feather_top, 0.0, a)
	_draw_slice(canvas, w, feather_top, core_bottom, a, a)
	var step_h: float = (band_bottom - core_bottom) / float(FEATHER_STEPS)
	for i: int in range(FEATHER_STEPS):
		var y0: float = core_bottom + step_h * float(i)
		var a0: float = 1.0 - smoothstep(0.0, 1.0, float(i) / float(FEATHER_STEPS))
		var a1: float = 1.0 - smoothstep(0.0, 1.0, float(i + 1) / float(FEATHER_STEPS))
		_draw_slice(canvas, w, y0, y0 + step_h, a * a0, a * a1)

# One full-width horizontal slice with a vertical alpha gradient.
func _draw_slice(canvas: CanvasItem, w: float, y0: float, y1: float, alpha_top: float, alpha_bottom: float) -> void:
	if y1 - y0 < 0.5:
		return
	var c_top := Color(SMOKE.r, SMOKE.g, SMOKE.b, alpha_top)
	var c_bottom := Color(SMOKE.r, SMOKE.g, SMOKE.b, alpha_bottom)
	canvas.draw_polygon(
		PackedVector2Array([Vector2(0.0, y0), Vector2(w, y0), Vector2(w, y1), Vector2(0.0, y1)]),
		PackedColorArray([c_top, c_top, c_bottom, c_bottom])
	)

func _draw_puffs(canvas: CanvasItem, w: float, top: float, feather_top: float, core_bottom: float, band_bottom: float, fade: float) -> void:
	var span: float = _wrap_span()
	var pad: float = board.road.lane_width() * PUFF_RADIUS_MAX_FRAC
	var wrap_top: float = top - pad
	for puff: Dictionary in _puffs:
		var r0: float = puff["r"]
		var speed: float = puff["speed"]
		# Position is a pure function of the scroll and the clock — no
		# per-puff state is mutated per frame, so a refresh, a long effect,
		# or a hitch in the frame rate can never accumulate drift between
		# puffs and the road.
		var y: float = wrap_top + fmod(float(puff["y0"]) + _scroll * speed, span)
		var a: float = _profile(y, top, feather_top, core_bottom, band_bottom) * fade
		if a <= 0.01:
			continue
		var sway: float = sin(_clock * float(puff["sway_rate"]) + float(puff["sway_phase"])) * float(puff["sway"])
		var x: float = clamp(float(puff["x0"]) + sway, min(r0, w * 0.5), max(w - r0, w * 0.5))
		var breath: float = 1.0 + PUFF_BREATH_FRAC * sin(_clock * float(puff["breath_rate"]) + float(puff["breath_phase"]))
		var r: float = r0 * breath
		var shade: float = puff["shade"]
		var at := Vector2(x, y)
		canvas.draw_circle(at, r, Color(SMOKE.r + shade, SMOKE.g + shade, SMOKE.b + shade, PUFF_HALO_ALPHA * a))
		canvas.draw_circle(at, r * PUFF_CORE_FRAC, Color(SMOKE.r + shade + PUFF_CORE_LIFT, SMOKE.g + shade + PUFF_CORE_LIFT, SMOKE.b + shade + PUFF_CORE_LIFT, PUFF_CORE_ALPHA * a))

# --- HUD --------------------------------------------------------------------

func bar_color() -> Color:
	return BAR
