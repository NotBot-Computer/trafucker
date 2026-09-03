extends SkillEffect

## SMOKE SCREEN (catalog id "smoke") — an opponent skill that attacks the
## victim's *information*, and nothing else.
##
## The Taxi (§5 sessions I/L) is a rogue vehicle with its own AI; Oil Slick
## takes the victim's grip. Both change what the world *does*. This one
## changes what the victim can *see*:
## a bank of smoke rolls across the upper part of their board, traffic
## emerges from it very late, and every gap has to be read in roughly a
## quarter of the road it normally gets. The road underneath is exactly as
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
#  1. The HUD strip at the top must stay READABLE. The overlay draws ABOVE
#     PlayerBoard._draw() (SkillOverlay.OVERLAY_Z, above even Nitro's
#     energy), so it paints straight over the boost bar and every timer
#     stacked under it. A player who cannot see their own boost charge will
#     think the game broke, not that they were attacked.
#  2. It must not cover the player's own car near the bottom. Taking away the
#     thing they steer reads as a rendering bug.
#  3. It must be dense enough to matter and thin enough to survive — see the
#     density block below.
#
# Constraint 1 used to be met by starting the band BELOW the HUD, leaving the
# strip completely clear. That was wrong, and playing it is what showed why:
# the camera sees above y = 0 by vertical_margin (up to ~107px at the
# 4-player zoom), so the band had clear road above it and clear road below
# it, four straight edges, and read as a grey slab parked on the road rather
# than as weather. It is now met by thinning the smoke over that strip
# instead — see HUD_VEIL_ALPHA. The band runs off the top of the visible road
# and the top edge is gone.

# How far ABOVE the top of the visible road the band begins, in px. It exists
# so the top feather finishes before the first pixel anyone can see: the band
# is at full density everywhere on screen and simply has no top edge. The
# visible top is -vertical_margin, which changes with the player count, so
# this is measured from there rather than from y = 0.
const BAND_TOP_OVERSHOOT := 44.0

# The top feather, over this many px — entirely inside the overshoot above,
# so it is never on screen. It is kept because the roll-in (see _reach)
# lerps the band's bottom edges up toward the top edge, and a band caught
# mid-roll with a hard top would flash one.
const TOP_FEATHER_PX := 28.0

# The HUD strip is veiled, not skipped: over the bars the band's density is
# multiplied down to HUD_VEIL_ALPHA, ramped in and out at every edge so it
# reads as a thin patch of smoke rather than a rectangular hole. At 0.52 the
# smoke over the boost bar comes to ~0.42 alpha. A saturated bar on a black
# outline keeps well over half its contrast through that and stays perfectly
# legible; a grey car passing through the same patch does not. 0.26 and 0.40
# were both tried and both left the window a peephole traffic read through —
# this is the thickest the bars will take.
#
# **The veil is a WINDOW, not a stripe.** A full-width thin band was tried
# first and it is worse than the hole it replaced: it spans every lane, so
# traffic scrolling down through it lights up for ~50px and then vanishes
# again, which reads as the smoke flickering rather than as smoke. The bars
# only occupy the middle BOOST_BAR_WIDTH_FRAC (0.5) of the board, so the
# window is that wide plus HUD_VEIL_SIDE_PAD, centred — the outer lanes stay
# at full density, and the middle ones give up a short stretch of road that
# happens to be where the player's own readouts are.
#
# Its bottom is the boost bar's own position (read live off the board, see
# _resolve_hud) plus HUD_VEIL_RESERVE, which covers what stacks UNDER the bar
# and which this file cannot know frame by frame: the tank timer (4 + 6), the
# nitro timer (4 + 6), and one 4 + 6 skill bar per live modular effect. Tank
# + Nitro + three skill bars is 50px, more than any real round stacks; 56
# leaves room. The "BOT · NORMAL" tag (BOT_TAG_Y 49) sits inside it too. The
# top is a few px above y = 0 so the veil covers the bar's own margin without
# eating into the road above the board.
const HUD_VEIL_RESERVE := 56.0
const HUD_VEIL_TOP := -6.0
const HUD_VEIL_ALPHA := 0.52
const HUD_VEIL_FADE := 16.0 # px of ramp at the top and bottom edges
const HUD_VEIL_SIDE_PAD := 16.0 # px each side of the bars the window also covers
const HUD_VEIL_SIDE_FADE := 26.0 # px of ramp at the left and right edges

# Fractions of board_height. The core (full density) runs from the HUD strip
# down to CORE_BOTTOM_FRAC; below that it feathers out to nothing at
# BAND_BOTTOM_FRAC. On the 620px board that is a core ending at 310px and
# clear road from 409px. The player's car roof sits at ~540px
# (board_height - CAR_BOTTOM_MARGIN - car height), so the victim gets ~131px
# of clear approach instead of the ~540 they are used to — under a quarter of
# it, about a third of a second at mid-round road speed — plus the 99px
# feather where a car is a half-legible smudge.
#
# These were 0.38/0.52 on the first pass, which left 218px of clear road and
# played as an inconvenience rather than a blindfold. The brief then was
# "read in half the time"; the ask after playing it was for smoke you
# genuinely cannot see through, and reading distance is half of that (density
# below is the other half). Cutting the approach is what makes the victim
# commit to a lane on memory instead of on sight.
#
# The band's bottom edge is the one number here with a hard ceiling, and it
# is the player's own car rather than fairness: Nitro lifts the car 105px, to
# a roof at ~435px, and BAND_BOTTOM_FRAC * 620 = 409 clears that by 26px. Any
# further down and a nitro-boosting victim is inside their own smoke, which
# reads as a bug rather than as weather. Tank Mode's taller roof (~513px) and
# the ordinary car both sit far below it.
const CORE_BOTTOM_FRAC := 0.50
const BAND_BOTTOM_FRAC := 0.66

# The band's floor is drawn as a BASE_ROWS x BASE_COLS grid of quads with
# per-vertex alpha, rather than the five full-width gradient slices it used
# to be. Two reasons, both learned from looking at it:
#
#   * The old five slices could only vary down the board, so the floor was a
#     constant value across the full 360px width at any given height. That is
#     the definition of a slab, and no amount of puffs on top of it hides
#     that the thing underneath them is rectangular. The grid samples a
#     drifting 2D function (see _wobble) at every corner, so the floor is
#     never the same twice across a row.
#   * The veil over the HUD strip is a shape the five fixed slices could not
#     express at all.
#
# 16 x 5 is 80 quads per board per frame. That is more than five and still
# nothing: they are flat polygons with no texture and no overdraw beyond
# each other. Fewer rows and the vertical gradient starts showing its facets
# where the profile curves hardest (the bottom feather); fewer columns and
# the wobble reads as vertical stripes rather than as drift.
const BASE_ROWS := 16
const BASE_COLS := 5

# How far the floor's density wanders either side of BASE_ALPHA, as a
# fraction of it, and how fast. Two sine components at an awkward ratio in
# both axes (the same trick Oil Slick's fishtail uses, for the same reason: a
# single one is a pattern the eye locks onto).
#
# 0.16 rather than the 0.20 this shipped with, and the reason is arithmetic
# rather than taste: BASE_ALPHA * (1 + BASE_VARIATION) must stay under 1.0 or
# the thick half of the drift clips flat against opaque (see _draw_base,
# where the clamp used to sit in the wrong place and did exactly that). At
# BASE_ALPHA 0.86 that ceiling is 0.163. The band lost nothing by the trade:
# the floor's real range is 0.72-1.00 where it used to be 0.64-0.80, so both
# the thin spots and the knots moved the way the ask wanted and the spread
# between them is *wider* than before, not narrower.
#
# The floor is still the thing that is true everywhere and the puffs are
# still what carry the big variation; much past this the thin spots start
# reading as holes rather than as thin spots.
const BASE_VARIATION := 0.16
const WOBBLE_X_SCALE := 0.0091 # rad/px across the board
const WOBBLE_Y_SCALE := 0.0063 # rad/px down it
const WOBBLE_DRIFT := 0.27 # rad/s — the whole field creeps, so it never sets

# --- Density ----------------------------------------------------------------
#
# Alpha composes as 1 - Π(1 - a), so the numbers below are chosen for what
# they add up to, not for what each is. What actually matters is the
# *transmission* (1 - alpha) — the fraction of a car's contrast that survives
# — so it is in the right-hand column, because that is the thing that halved:
#
#                                                        now      was
#   * the floor at its thinnest, 0.86 * (1 - 0.16):      0.72     0.64
#   * the floor at its thickest, 0.86 * (1 + 0.16):      1.00     0.80 (clipped, see _draw_base)
#   * a thin spot under one halo:                       ~0.77    ~0.70   (23% / 30% left)
#   * the typical spot, floor + ~2.5 halos + a core:    ~0.93    ~0.86   ( 7% / 14% left)
#   * the thickest knots:                               ~0.99    ~0.98
#
# This has now been raised three times against play, and the file's original
# caution — that above ~0.85 "the road is simply gone and the victim stops
# steering and starts praying" — has been overruled every time by the person
# playing it. The first pass ran 0.44 / 0.12 / 0.20 and was barely felt; the
# second ran 0.72 / 0.30 / 0.34 and was still asked to go further; this one
# is the answer to "make it even harder to see, make it denser", and it is
# aimed at the *thin* spots rather than at the average, because a curtain is
# only as opaque as the places you can see through. Half of the gain here is
# not a number at all — it is the clamp in _draw_base that was quietly
# discarding the thick half of the floor's own drift.
#
# What keeps this a skill rather than a coin flip is geometry, not alpha: the
# band stops 131px short of the car (see CORE_BOTTOM_FRAC), so every vehicle
# emerges into clear road before it arrives and the victim who was tracking
# lanes by memory still gets to act on what they see. That is the trade this
# file makes — take the reading distance, not the reaction. It is also why
# there is no more room below the band: CORE_BOTTOM_FRAC and
# BAND_BOTTOM_FRAC are pinned by Nitro's roof, so density is the only axis
# this could still move along, and the next ask would have to spend the
# clear approach.
#
# If this ever needs pulling back, BASE_ALPHA is still the honest lever: it
# is the floor, so it sets what the thinnest spot costs, and everything else
# is texture on top of it. Pull BASE_VARIATION with it — the two have a
# ceiling to respect together (see BASE_VARIATION).
#
# The unevenness itself is still deliberate, and matters more at these
# values, not less: a slab of one alpha is a filter, a curtain of varying
# density is weather, and a thin spot the victim can peer through for a
# moment is the kind of thing they will remember and try to use.
const BASE_ALPHA := 0.86
# Both puff alphas are PEAK values, at the centre of the puff, falling to
# zero at its rim (see PUFF_GRADIENT). They are higher than a flat disc would
# need for the same table above because most of a soft puff's area is below
# its peak — which is the point of it: area-weighted, this gradient averages
# 0.48 of its peak, so a halo is worth ~0.17 where it lands.
const PUFF_HALO_ALPHA := 0.36
const PUFF_CORE_ALPHA := 0.44

# A puff is a radial gradient, not a flat disc. draw_circle() gives a hard
# rim, which at the first pass's 0.12/0.20 was faint enough not to matter and
# at these alphas is not: 22 legible circles read as a raft of soap bubbles,
# which is a worse look than the thin smoke this change was made to replace.
# One shared GradientTexture2D drawn as a rect costs exactly what draw_circle
# did (one call) and has no edge at all.
#
# The gradient is not linear. It holds near-full alpha out to PUFF_PLATEAU of
# the radius and only then falls away, so a puff still has a solid middle to
# hide a car behind — a pure linear falloff averages a third of its peak and
# turns the whole bank into haze. Sizes: 96px is far more resolution than a
# ~60px-radius puff drawn at ~1x zoom needs, and the texture is built once
# for the whole game.
const PUFF_TEX_SIZE := 96
const PUFF_PLATEAU := 0.45
const PUFF_PLATEAU_ALPHA := 0.86

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

# Count is picked for coverage arithmetic, not by eye, and it has to be
# re-run every time the band's extent moves — which is the whole reason this
# is written down. The band runs from above the visible road down to
# BAND_BOTTOM_FRAC, ~360 x 516px of it on screen ≈ 186,000px²; a mean puff
# (E[r²] over the radius range, so ~11,800px² of halo) covers it 2.55 times
# over at 40. A typical point therefore sits under about two and a half
# halos, which is where the ~0.93 in the density table comes from.
#
# The history is the argument for keeping the arithmetic: 14 puffs over the
# original 87,000px² band was ~1.6x; the same 14 over the taller band would
# have been ~0.8x, i.e. *thinning* the smoke in the change meant to thicken
# it. Past ~2.5x the knots stop being knots and the bank flattens into one
# value, which is the filter look this file exists to avoid — so 40 sits at
# the top of that range and not beyond it, and the density asked for on this
# pass was bought from the floor and from the puffs' own alpha instead, both
# of which get denser without getting flatter. The gap between a thin spot
# (0.77) and a knot (0.99) is wider now than it was at 34, which is the
# number to watch if this is ever pushed again: when it closes, the bank has
# become the filter.
#
# Cost at 40 is 80 textured quads plus ~75 floor quads per board per frame.
# Flat 2D polygons with no overdraw beyond each other; nothing here allocates
# per frame.
const PUFF_COUNT := 40
# Radii as fractions of lane width (~53px on the 5-lane board): a small puff
# is two thirds of a lane, a big one is over a lane and a half. Sized off
# the lane rather than the board so a puff is always "about a car and a
# bit" — enough to hide one car, never enough to hide a whole row, whatever
# the lane count.
const PUFF_RADIUS_MIN_FRAC := 0.65
const PUFF_RADIUS_MAX_FRAC := 1.60
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

# The HUD's geometry in board px, resolved once in activate(): the bottom
# edge of the boost bar, and half the width of the veil window over the bars.
# See _resolve_hud for how and why they are not simply
# board.BOOST_BAR_MARGIN_TOP and friends.
var _hud_bottom: float = 0.0
var _veil_half_w: float = 0.0

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
	_resolve_hud()
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

# Top edge of the band, above the top of what the camera can see — so the
# band has no visible top edge at all. See BAND_TOP_OVERSHOOT.
func _band_top() -> float:
	return -(float(board.vertical_margin) + BAND_TOP_OVERSHOOT)

# Bottom of the strip the HUD_VEIL_ALPHA thinning covers.
func _veil_bottom() -> float:
	return _hud_bottom + HUD_VEIL_RESERVE

# 1.0 everywhere except inside the window over the HUD bars, where it falls
# to HUD_VEIL_ALPHA with a smooth ramp on all four edges. Multiplied into the
# density so it thins both the floor and the puffs — a veil that only thinned
# the floor would leave a puff drifting over the boost bar at full strength,
# which is the one place the smoke is not allowed to win.
func _hud_veil(x: float, y: float) -> float:
	var w: float = _window(y, HUD_VEIL_TOP, _veil_bottom(), HUD_VEIL_FADE)
	if w <= 0.0:
		return 1.0
	var centre: float = float(board.board_width) * 0.5
	w *= _window(x, centre - _veil_half_w, centre + _veil_half_w, HUD_VEIL_SIDE_FADE)
	return lerp(1.0, HUD_VEIL_ALPHA, w)

# 1 inside [lo, hi], 0 outside it by `fade`, smoothstepped between. One
# function for both axes so the window's corners are the product of two
# identical ramps and no edge is harder than another.
func _window(v: float, lo: float, hi: float, fade: float) -> float:
	if v <= lo - fade or v >= hi + fade:
		return 0.0
	if v < lo:
		return smoothstep(0.0, 1.0, (v - (lo - fade)) / fade)
	if v > hi:
		return 1.0 - smoothstep(0.0, 1.0, (v - hi) / fade)
	return 1.0

# The floor's own drift, ~1.0 +/- BASE_VARIATION. Two sines per axis at an
# awkward ratio so the pattern does not tile inside the five seconds the
# effect lasts, plus a slow crawl on _clock so it is never the same field
# twice. This is what stops the band being a rectangle of one value; see
# BASE_VARIATION.
func _wobble(x: float, y: float) -> float:
	var t: float = _clock * WOBBLE_DRIFT
	var a: float = sin(x * WOBBLE_X_SCALE + y * WOBBLE_Y_SCALE + t)
	var b: float = sin(x * WOBBLE_X_SCALE * 1.63 - y * WOBBLE_Y_SCALE * 0.71 + t * 1.31 + 2.2)
	return 1.0 + BASE_VARIATION * (0.6 * a + 0.4 * b)

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
func _resolve_hud() -> void:
	var consts: Dictionary = {}
	var board_script: Script = board.get_script()
	if board_script != null:
		consts = board_script.get_script_constant_map()
	var margin_top: float = float(consts.get("BOOST_BAR_MARGIN_TOP", 14.0))
	var bar_h: float = float(consts.get("BOOST_BAR_HEIGHT", 9.0))
	_hud_bottom = margin_top + bar_h
	var bar_frac: float = float(consts.get("BOOST_BAR_WIDTH_FRAC", 0.5))
	_veil_half_w = float(board.board_width) * bar_frac * 0.5 + HUD_VEIL_SIDE_PAD

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
func _profile(x: float, y: float, top: float, feather_top: float, core_bottom: float, band_bottom: float) -> float:
	if y <= top or y >= band_bottom:
		return 0.0
	var shape: float
	if y < feather_top:
		shape = smoothstep(0.0, 1.0, (y - top) / max(feather_top - top, 0.001))
	elif y <= core_bottom:
		shape = 1.0
	else:
		shape = 1.0 - smoothstep(0.0, 1.0, (y - core_bottom) / max(band_bottom - core_bottom, 0.001))
	return shape * _hud_veil(x, y)

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

# The band's floor: the density every point gets before any puff lands on it.
# A BASE_ROWS x BASE_COLS grid of quads with per-vertex colours (ScreenMask's
# technique, in two dimensions instead of one), each corner sampled from the
# vertical profile times the drifting wobble. Corners are sampled once per
# grid line and reused by the quads on both sides of it, so neighbours agree
# exactly and the grid is invisible — what shows is a smooth field.
func _draw_base(canvas: CanvasItem, w: float, top: float, feather_top: float, core_bottom: float, band_bottom: float, fade: float) -> void:
	var rows: int = BASE_ROWS
	var cols: int = BASE_COLS
	var h: float = band_bottom - top
	if h < 1.0:
		return
	# Vertex grid, (rows + 1) x (cols + 1): positions and their alphas.
	var xs := PackedFloat32Array()
	for c: int in range(cols + 1):
		xs.append(w * float(c) / float(cols))
	var ys := PackedFloat32Array()
	for r: int in range(rows + 1):
		ys.append(top + h * float(r) / float(rows))
	var alphas := PackedFloat32Array()
	for r: int in range(rows + 1):
		var y: float = ys[r]
		for c: int in range(cols + 1):
			# The wobble multiplies the profile rather than being added to
			# it, so it cannot lift the band above its own top edge or below
			# its own bottom one — at profile 0 the floor is 0 however the
			# wobble is leaning.
			#
			# BASE_ALPHA is inside the clamp, not outside it. Outside, the
			# clamp bit at profile * wobble = 1.0 — which across the whole
			# core (profile 1.0) is wobble = 1.0, i.e. the entire thick half
			# of the drift was flattened off and the floor was BASE_ALPHA
			# with dents in it and no knots at all. BASE_VARIATION was
			# therefore a one-sided *thinner*, which is the opposite of what
			# it is documented to be and made the honest range 0.64-0.80
			# rather than the 0.64-0.96 the density table claimed. Inside,
			# the clamp only bites where the floor would actually pass
			# opaque, and BASE_ALPHA * (1 + BASE_VARIATION) is kept just
			# under 1.0 so that never happens either.
			var profile: float = _profile(xs[c], y, top, feather_top, core_bottom, band_bottom)
			alphas.append(clamp(profile * _wobble(xs[c], y) * BASE_ALPHA, 0.0, 1.0) * fade)

	var quad := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	var cols_v: PackedColorArray = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	for r: int in range(rows):
		for c: int in range(cols):
			var tl: int = r * (cols + 1) + c
			var bl: int = tl + cols + 1
			# Wholly transparent quads are skipped rather than submitted:
			# above the visible road and below the feather that is most of
			# the grid, and a transparent polygon still costs a draw call.
			if alphas[tl] <= 0.002 and alphas[tl + 1] <= 0.002 and alphas[bl] <= 0.002 and alphas[bl + 1] <= 0.002:
				continue
			quad[0] = Vector2(xs[c], ys[r])
			quad[1] = Vector2(xs[c + 1], ys[r])
			quad[2] = Vector2(xs[c + 1], ys[r + 1])
			quad[3] = Vector2(xs[c], ys[r + 1])
			cols_v[0] = Color(SMOKE.r, SMOKE.g, SMOKE.b, alphas[tl])
			cols_v[1] = Color(SMOKE.r, SMOKE.g, SMOKE.b, alphas[tl + 1])
			cols_v[2] = Color(SMOKE.r, SMOKE.g, SMOKE.b, alphas[bl + 1])
			cols_v[3] = Color(SMOKE.r, SMOKE.g, SMOKE.b, alphas[bl])
			canvas.draw_polygon(quad, cols_v)

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
		# x is resolved before the alpha, not after: the density is now a
		# function of both axes (the veil window over the HUD bars is not
		# full width), so a puff has to be asked about its own position
		# rather than about its row.
		var sway: float = sin(_clock * float(puff["sway_rate"]) + float(puff["sway_phase"])) * float(puff["sway"])
		var x: float = clamp(float(puff["x0"]) + sway, min(r0, w * 0.5), max(w - r0, w * 0.5))
		var a: float = _profile(x, y, top, feather_top, core_bottom, band_bottom) * fade
		if a <= 0.01:
			continue
		var breath: float = 1.0 + PUFF_BREATH_FRAC * sin(_clock * float(puff["breath_rate"]) + float(puff["breath_phase"]))
		var r: float = r0 * breath
		var shade: float = puff["shade"]
		var tex: Texture2D = _puff_texture()
		var halo := Color(SMOKE.r + shade, SMOKE.g + shade, SMOKE.b + shade, PUFF_HALO_ALPHA * a)
		var lift: float = shade + PUFF_CORE_LIFT
		var core := Color(SMOKE.r + lift, SMOKE.g + lift, SMOKE.b + lift, PUFF_CORE_ALPHA * a)
		# The gradient's circle is inscribed in the texture, so a rect of side
		# 2r puts its rim exactly on radius r — the same geometry draw_circle
		# had.
		canvas.draw_texture_rect(tex, Rect2(x - r, y - r, r * 2.0, r * 2.0), false, halo)
		var cr: float = r * PUFF_CORE_FRAC
		canvas.draw_texture_rect(tex, Rect2(x - cr, y - cr, cr * 2.0, cr * 2.0), false, core)

# One radial-gradient puff, white so the per-puff tint above is what colours
# it. Built on first draw and held for the life of this effect.
#
# It depends on nothing about the board or the effect, so the obvious form is
# a `static var` shared by every live effect in the process — four boards
# building four identical 96x96 gradients is waste. That was written and
# backed out: in Godot 4.7 a `static var` on a GDScript makes the engine
# report "N ObjectDB instances were leaked at exit" on a plain
# `godot --headless --quit res://scenes/Main.tscn`, holding null, with
# nothing ever assigned to it. Measured both ways — the same file with the
# `static` keywords removed exits clean. The storage for a script's statics
# evidently outlives the leak check.
#
# That check is this project's only automated validation (CLAUDE.md), and its
# entire value is that a clean run means clean. Trading that for three
# textures nobody will ever notice is a bad trade, so this is per-effect. It
# is a Resource, not a Node: it is refcounted away with the effect itself,
# there is nothing for deactivate() to free, and the session-G leak SkillProbe
# watches for (a child node left on the board) is not possible here.
var _puff_tex: GradientTexture2D = null

func _puff_texture() -> GradientTexture2D:
	if _puff_tex != null:
		return _puff_tex
	var g := Gradient.new()
	# A fresh Gradient already has two points; set those and insert the
	# plateau between them, rather than assigning the offsets and colors
	# arrays, which have to stay the same length through the assignment.
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	g.set_offset(1, 1.0)
	g.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	g.add_point(PUFF_PLATEAU, Color(1.0, 1.0, 1.0, PUFF_PLATEAU_ALPHA))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	# Centre to the middle of the right edge: a radius of half the texture, so
	# the circle is inscribed and the corners of the rect are transparent.
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = PUFF_TEX_SIZE
	t.height = PUFF_TEX_SIZE
	_puff_tex = t
	return _puff_tex

# --- HUD --------------------------------------------------------------------

func bar_color() -> Color:
	return BAR
