extends SkillEffect

## PIT STOP (catalog id "pitstop") — the crew swarms the car for a moment and
## hands back a life that was already spent.
##
## The two self skills that predate this layer are both timed transforms of
## the player's car: Tank Mode swaps its footprint and hands it a cannon for
## 6s, Nitro takes it off the road at 2.85x for 5.3s. MAKE WAY, the first
## modular self skill, leaves the car alone and changes the traffic instead.
## This one is different again, on purpose — it is a single moment with a
## permanent consequence and no transform at all. Nothing about the car, the
## road or the traffic is any different once it lands; what is different is
## the number of crashes the player can still afford. Keeping it that shape
## is the whole reason it earns a slot: with five entries in SELF_SKILLS the
## pool needed something that is not "you are briefly better", and a life is
## the one thing in this mode that no amount of driving well can buy back.
##
## ## What it does
##
##   * One spent life comes back (`board.lives`, capped at MAX_LIVES), and the
##     pip that stood for it goes back onto the road behind the car so the
##     readout agrees with the count.
##   * At full lives it fills the boost bar instead. A pick that does nothing
##     is a pick that feels broken, and a full-lives player is exactly the one
##     the roll would otherwise be wasted on. Boost is what they get because
##     it is the other resource on this board that is normally *earned* — a
##     full bar is ~4.5s of drifting — so the fallback is still worth having
##     rather than a consolation.
##
## ## Why it has a duration at all
##
## The gameplay effect is over the instant activate() returns. duration() is
## nonetheless DURATION (0.8s), not 0.0, purely so there are tick() and
## draw_*() frames to animate the flourish in — an instant skill never joins
## board.active_effects and so never gets a frame of either. bar_color() is
## fully transparent to match: a HUD bar counting down on something that has
## already finished doing its work would be lying about what is left of it.
##
## ## Restoring the pip is the fiddly part
##
## `_build_hearts()` creates MAX_LIVES sprites into fixed slots and
## `_spend_heart()` frees the one at index `lives` (after the decrement),
## leaving the array slot in place — deliberately, so surviving pips never
## shuffle sideways (see _layout_hearts). The invariant everything downstream
## relies on is therefore: exactly `lives` valid sprites, occupying the first
## `lives` slots. A refund has to leave that true or the *next* crash spends
## the wrong pip. So this file frees whatever is in slot `lives` (normally
## nothing; occasionally a pip still mid-pop, see _restore_pip), builds a new
## Sprite2D the way `_build_hearts()` does, and writes it into that one slot.
## Rebuilding the whole row was rejected: it resets every pip to full opacity
## and scale at once, which reads as a flicker across all three, and it
## kills a loss tween that may legitimately be running on a different board
## state than the one being refunded. Rescuing a mid-pop sprite instead of
## replacing it was rejected too — it is half transparent and twice its size
## at that point, and the restore animation starts from precisely that pose
## anyway, so a fresh sprite costs nothing and has no leftover tween state.
##
## The pip coming back is animated for the same reason the pip going away is
## (§5 session X): at 17px, one that changes between two frames is one nobody
## sees change. It plays the loss gesture backwards — swollen and invisible,
## shrinking and solidifying into its slot — off HeartPips' own numbers, then
## lands with a bright pop and a ring on the road so the eye is drawn to the
## slot that just refilled.
##
## ## No Tween, no spawned node
##
## Everything here is driven off time_left from tick() and the draw hooks.
## The one Sprite2D this file creates is handed to board.heart_sprites and is
## the board's from then on, freed by _spend_heart()/_build_hearts() exactly
## like the other two. Animating it with a Tween was rejected because
## Tween.kill() skips the remaining callbacks (§5 session G's leak), and
## deactivate() can arrive mid-effect from a restart or an elimination — a
## pose written from tick() has nothing to skip.

# --- Timing ----------------------------------------------------------------

# Cosmetic only — see the header. Longer than HeartPips.LOSS_DURATION (0.45s)
# so the pip has fully landed before the flourish is over and the landing pop
# gets its own DURATION - LOSS_DURATION of screen time; well under a second so
# it is finished long before the next pickup could possibly matter.
const DURATION := 0.8

# The pip solidifies faster than it shrinks: it is fully opaque this far into
# its LOSS_DURATION, so most of the shrink is watched on a solid pip rather
# than a ghost. Reversing the loss curve exactly (alpha linear over the whole
# window) left it a smear for too long to be read as a heart.
const PIP_FADE_IN_FRAC := 0.5

# Extra brightness written into the pip's modulate the frame it lands, decaying
# to 0 by the end of DURATION. Modulate above 1.0 scales the texture up before
# the clamp, so the body flares toward white while the hue-less black outline
# stays black — which is what keeps it a heart while it flashes.
const PIP_LAND_FLASH := 0.9

# --- The road burst at the slot -------------------------------------------

# A ring that expands out of the slot from the moment the pip lands, drawn on
# the road (draw_board). Slots are ~21px apart, so at BURST_R_MAX the ring
# brushes its neighbours — fine for a 2px line that is already fading, and
# the overlap is what makes it read as "this slot, in this row" rather than a
# random circle on the tarmac.
const BURST_R_MIN := 4.0
const BURST_R_MAX := 22.0
const BURST_WIDTH := 2.0

# --- The flourish over the car --------------------------------------------

# The glyph — a cross for a life, a bolt for fuel — rises this many px off
# the car's centre over DURATION, ease-out, so it leaves fast and hangs.
const GLYPH_RISE := 26.0
# Fade-in and fade-out, as fractions of DURATION. The out is the longer of
# the two: appearing is a cut, leaving is a dissolve.
const GLYPH_IN_FRAC := 0.12
const GLYPH_OUT_FRAC := 0.35
# Half-extent of the cross's arms and the thickness of each arm, in px. Sized
# against a ~33px-wide car: big enough to read, small enough to still be
# "over the car" rather than a HUD element.
const CROSS_ARM := 7.0
const CROSS_THICK := 4.0
# Outline drawn under the glyph, in px per side. The heart pip keeps its own
# black outline for exactly this reason (see HeartPips): a bright shape over
# a bright car vanishes without one.
const GLYPH_OUTLINE := 1.5
# The bolt, in half-heights: y runs -1 (top) to +1 (bottom), x is width
# relative to the same unit. Scaled by BOLT_HALF_H at draw time.
const BOLT_SHAPE: Array[Vector2] = [
	Vector2(0.18, -1.0), Vector2(-0.5, 0.12), Vector2(-0.06, 0.12),
	Vector2(-0.22, 1.0), Vector2(0.5, -0.18), Vector2(0.06, -0.18),
]
const BOLT_HALF_H := 10.0

# Spanner glints — four-point sparks that pop up around the car one after
# another, like a crew working its way round it. Offsets are in half car
# sizes (x by half width, y by half height) so they scale with whatever kind
# the player is currently driving. Fixed rather than random: a flourish this
# short has no time to look random, it just looks different each time, and a
# planned sequence reads as work being done.
const GLINT_OFFSETS: Array[Vector2] = [
	Vector2(-1.25, -0.55), Vector2(1.3, -0.15), Vector2(-1.1, 0.4), Vector2(1.2, 0.7),
]
const GLINT_STAGGER := 0.12 # seconds between one glint starting and the next
const GLINT_LIFE := 0.3 # each glint's own on-screen time; the last one is out by 0.66s
const GLINT_ARM := 5.0 # half-length of the long spokes at the glint's peak, px

# --- The boost-bar flash (full-lives fallback) -----------------------------

# The bar refills in one frame, which at the top of a 620px board while the
# player is looking at their car is an event nobody sees. So a highlight
# sweeps across it left to right over this fraction of DURATION and the whole
# bar glows amber behind it, fading over the rest. Drawn from draw_board,
# which runs after the board has drawn the bar in the same _draw() — so it
# lands on top of the bar and, like the bar, under passing traffic.
const BAR_SWEEP_FRAC := 0.55
const BAR_SWEEP_WIDTH := 7.0
const BAR_GLOW_ALPHA := 0.75
const BAR_HALO_PX := 3.0 # how far the glow bleeds outside the bar's rect

# --- Palette ---------------------------------------------------------------

const LIFE_GREEN := Color(0.36, 0.92, 0.46)
const FUEL_AMBER := Color(1.0, 0.76, 0.22)
const OUTLINE := Color(0.06, 0.05, 0.08)
const GLINT := Color(1.0, 1.0, 0.92)

# --- State -----------------------------------------------------------------

# Which of the two things activate() did. Decides every draw call.
const MODE_NONE := 0
const MODE_LIFE := 1
const MODE_FUEL := 2

var _mode: int = MODE_NONE
# The pip this effect built and is posing, and the scale it must end up at.
# Owned by the board (it sits in board.heart_sprites); this is only a
# reference for the animation, which is why every use is guarded with
# is_instance_valid — a crash can spend it out from under us at any frame.
var _pip: Sprite2D = null
var _pip_base_scale: Vector2 = Vector2.ONE
var _pip_slot: int = -1

# --- Lifecycle -------------------------------------------------------------

func duration() -> float:
	return DURATION

func activate() -> void:
	_grant()

# A second PIT STOP inside the 0.8s cosmetic window — the board resets
# time_left and calls this instead of activate(), so without this branch the
# second pick would be swallowed by the first one's flourish. Pickups are
# seconds apart, so it will almost never happen; it is here because "a pick
# must never do nothing" is the rule, not the common case. The pip from the
# first pick is settled first so its half-finished pose is not left behind.
func refresh() -> void:
	_settle_pip()
	_grant()

func tick(_delta: float) -> void:
	if _pip == null:
		return
	if not is_instance_valid(_pip):
		_pip = null
		return
	# Spent out from under us: a crash inside the flourish puts a loss tween
	# on the pip at index `lives`, and if that is our slot the tween now owns
	# the pose. Writing scale and alpha from here as well would make the two
	# fight for up to LOSS_DURATION — a pip flickering between "arriving" and
	# "leaving" on the one frame the player is looking at it. Let it go.
	if _pip_being_spent():
		_pip = null
		return
	_pose_pip(_elapsed())

# Idempotent, and leaves the board exactly as found — with one deliberate
# exception: the life (or the boost charge) is the point of the skill and is
# not undone. Only the pose written onto the pip is put back, and only if the
# pip is still the board's live one. Called mid-effect from start_round()
# (before _build_hearts() frees the row anyway) and from an elimination.
func deactivate() -> void:
	_settle_pip()
	_mode = MODE_NONE

# Transparent on purpose — see the header. The work is done in activate();
# a bar would count down over nothing.
func bar_color() -> Color:
	return Color(0.0, 0.0, 0.0, 0.0)

# --- The grant -------------------------------------------------------------

func _grant() -> void:
	var lives: int = board.lives
	var max_lives: int = board.MAX_LIVES
	if lives >= max_lives:
		# Full bar, not "top up": the tiers only mean anything from a full
		# bar, and a partial refund would land the player in the low tier
		# they were already in. If boost is being held right now the burn
		# simply carries on from a full tank — _draw's burn glow shows it.
		board.boost_charge = 1.0
		_mode = MODE_FUEL
		_pip = null
		_pip_slot = -1
		return
	# `lives` before the increment is the index of the slot that was spent
	# most recently — the same index _spend_heart() freed on the way down.
	board.lives = lives + 1
	_mode = MODE_LIFE
	_restore_pip(lives)

# Puts a fresh pip into `slot`, built exactly the way _build_hearts() builds
# one, and starts it at the far end of the loss gesture.
func _restore_pip(slot: int) -> void:
	var count: int = board.heart_sprites.size()
	if slot < 0 or slot >= count:
		# No row to put it in (never true in a live round — _build_hearts()
		# runs on every start_round). The life still counts; only the pip is
		# skipped, and _layout_hearts() will size the row from what exists.
		_pip = null
		_pip_slot = -1
		return

	# A loss tween can only ever be popping the pip in this same slot: the
	# last crash decremented `lives` to the index it then freed, and that is
	# the index being refilled. If the pick lands inside that 0.45s the tween
	# is still writing scale and alpha to a sprite about to be replaced, and
	# its final callback would free a node this file is no longer using —
	# harmless, but the board's rule (_build_hearts) is that anything which
	# kills the tween frees the pip itself, so both are done here explicitly.
	var loss_tween: Tween = board.heart_loss_tween
	if loss_tween != null and loss_tween.is_valid():
		loss_tween.kill()
	board.heart_loss_tween = null
	# Deliberately untyped. The slot normally holds a pip _spend_heart()
	# already freed, and `board` is untyped here (the cyclic-reference rule),
	# so the read comes back as a Variant — and assigning a Variant that
	# points at a freed object to a typed `Sprite2D` local is a runtime
	# error ("Trying to assign invalid previously freed instance"), before
	# is_instance_valid() ever gets to look at it. PlayerBoard's own
	# _layout_hearts() writes the same line typed and gets away with it only
	# because there the analyzer knows the array's element type and skips
	# the check. SkillProbe caught this on its first refund.
	var stale = board.heart_sprites[slot]
	if is_instance_valid(stale):
		stale.queue_free()

	var tex: Texture2D = HeartPips.tinted(board.body_color)
	var tex_size: Vector2 = tex.get_size()
	var pip: Vector2 = board._heart_size()
	var fresh := Sprite2D.new()
	fresh.texture = tex
	# HEART_Z, not the board's own z: the row has to stay behind everything
	# the car throws out of its tail (boost exhaust and Nitro's shadow at -1),
	# and that is a z rule for every pip, not just the ones _build_hearts()
	# made — see §7.
	fresh.z_index = board.HEART_Z
	board.add_child(fresh)
	board.heart_sprites[slot] = fresh

	_pip = fresh
	_pip_slot = slot
	_pip_base_scale = Vector2(pip.x / tex_size.x, pip.y / tex_size.y)
	# Position it now rather than waiting for _process's _layout_hearts():
	# a Sprite2D added mid-frame otherwise draws at the board's origin for
	# one frame, in the top-left corner, which is a very visible place to
	# flash a heart. Scale and alpha are this file's to write (see
	# _layout_hearts' own comment on why it never touches them).
	board._layout_hearts()
	_pose_pip(0.0)

# True while the board's loss tween is running on the pip in our slot —
# i.e. the life this effect gave back has already been spent again.
func _pip_being_spent() -> bool:
	var loss_tween: Tween = board.heart_loss_tween
	if loss_tween == null or not loss_tween.is_valid():
		return false
	var lives: int = board.lives
	return lives == _pip_slot

# The loss gesture, backwards, plus a landing flash. `t` is seconds since the
# grant. Scale eases out from LOSS_POP to 1.0 — the reverse of the loss curve
# would be an ease-in that arrives at full speed and stops dead; a pip that
# slows into its slot reads as landing, one that slams into it reads as a
# glitch. Alpha is in by PIP_FADE_IN_FRAC of the way so the shrink is watched
# on a solid pip.
func _pose_pip(t: float) -> void:
	if _pip == null or not is_instance_valid(_pip):
		return
	var land: float = HeartPips.LOSS_DURATION
	var k: float = clampf(t / land, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - k, 3.0)
	var grow: float = lerpf(HeartPips.LOSS_POP, 1.0, eased)
	var alpha: float = clampf(k / PIP_FADE_IN_FRAC, 0.0, 1.0)
	# The flash starts the frame the pip lands and decays over what is left
	# of DURATION. It is a step on purpose: the landing is an impact, and an
	# impact that ramps up is not one.
	var flash: float = 0.0
	if t >= land:
		flash = PIP_LAND_FLASH * clampf(1.0 - (t - land) / maxf(DURATION - land, 0.001), 0.0, 1.0)
	_pip.scale = _pip_base_scale * grow
	_pip.modulate = Color(1.0 + flash, 1.0 + flash, 1.0 + flash, alpha)

# Put the pip back to exactly what _build_hearts() would have made: base
# scale, plain white modulate. Skipped when a loss tween owns it, for the
# same reason tick() lets go — the tween is the one leaving it in the right
# state (freed), and a scale write here would stutter its pop for a frame.
func _settle_pip() -> void:
	if _pip != null and is_instance_valid(_pip) and not _pip_being_spent():
		_pip.scale = _pip_base_scale
		_pip.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_pip = null
	_pip_slot = -1

func _elapsed() -> float:
	return clampf(DURATION - time_left, 0.0, DURATION)

# --- Drawing ---------------------------------------------------------------

# On the road, under the traffic and the car: the ring at the refilled slot,
# or the flash across the boost bar. Both anchor to things that already live
# at board z 0 or below (the pips at HEART_Z, the bar in _draw itself), so
# this is the right layer for them — the overlay would put the ring over a
# car that happened to be passing the row.
func draw_board() -> void:
	if _mode == MODE_LIFE:
		_draw_slot_burst()
	elif _mode == MODE_FUEL:
		_draw_bar_flash()

func _draw_slot_burst() -> void:
	if _pip == null or not is_instance_valid(_pip):
		return
	var t: float = _elapsed() - HeartPips.LOSS_DURATION
	if t < 0.0:
		return
	var span: float = maxf(DURATION - HeartPips.LOSS_DURATION, 0.001)
	var k: float = clampf(t / span, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - k, 2.0)
	var fade: float = 1.0 - k
	# The pip's own position, not a second copy of _layout_hearts' slot
	# arithmetic: the board has already placed it this frame and there is
	# nothing to be gained by agreeing with that formula by hand.
	var c: Vector2 = _pip.position
	var r: float = lerpf(BURST_R_MIN, BURST_R_MAX, eased)
	board.draw_arc(c, r, 0.0, TAU, 24, Color(LIFE_GREEN.r, LIFE_GREEN.g, LIFE_GREEN.b, 0.85 * fade), BURST_WIDTH)
	# A brief white wash inside the ring, gone by half-way: this draws at z 0
	# over the pip at -2, so it must not linger or it tints the heart.
	board.draw_circle(c, r * 0.6, Color(1.0, 1.0, 1.0, 0.3 * fade * fade))

func _draw_bar_flash() -> void:
	var t: float = _elapsed()
	var k: float = clampf(t / DURATION, 0.0, 1.0)
	var fade: float = (1.0 - k) * (1.0 - k)
	var board_w: float = board.board_width
	var bar_w: float = board_w * float(board.BOOST_BAR_WIDTH_FRAC)
	var bar_x: float = (board_w - bar_w) * 0.5
	var bar_y: float = float(board.BOOST_BAR_MARGIN_TOP)
	var bar_h: float = float(board.BOOST_BAR_HEIGHT)
	# The glow: the bar's own rect plus a halo, amber fading to nothing.
	var halo := Rect2(bar_x - BAR_HALO_PX, bar_y - BAR_HALO_PX, bar_w + BAR_HALO_PX * 2.0, bar_h + BAR_HALO_PX * 2.0)
	board.draw_rect(halo, Color(FUEL_AMBER.r, FUEL_AMBER.g, FUEL_AMBER.b, 0.35 * fade), true)
	board.draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(FUEL_AMBER.r, FUEL_AMBER.g, FUEL_AMBER.b, BAR_GLOW_ALPHA * fade), true)
	# The sweep: a bright stripe crossing the bar left to right, the "fill"
	# the bar itself skipped. Clipped to the bar's width at both ends.
	var sweep_k: float = clampf(t / (DURATION * BAR_SWEEP_FRAC), 0.0, 1.0)
	if sweep_k < 1.0:
		var sweep_x: float = bar_x + bar_w * sweep_k
		var left: float = maxf(sweep_x - BAR_SWEEP_WIDTH * 0.5, bar_x)
		var right: float = minf(sweep_x + BAR_SWEEP_WIDTH * 0.5, bar_x + bar_w)
		if right > left:
			board.draw_rect(Rect2(left, bar_y, right - left, bar_h), Color(1.0, 1.0, 1.0, 0.9), true)
	board.draw_rect(Rect2(bar_x, bar_y, bar_w, bar_h), Color(1.0, 1.0, 1.0, 0.6 * fade), false, 1.5)

# Above everything: the glyph rising off the car and the glints round it.
#
# NOTE: this hook runs inside SkillOverlay._draw(), not PlayerBoard._draw(),
# so every call goes to board.skill_overlay — board.draw_*() here is refused
# at runtime and paints nothing. Same local space, see SkillEffect.
func draw_overlay() -> void:
	if _mode == MODE_NONE:
		return
	var canvas: CanvasItem = board.skill_overlay
	if canvas == null:
		return
	var t: float = _elapsed()
	var sz: Vector2 = board.car_size()
	# player_car.position, not car_x: the crew is working on the car where it
	# is drawn, so the flourish rides Nitro's lift and shudders with it. The
	# pip row is the thing that must not follow that position (§7); this is
	# not the pip row.
	var car: Vector2 = board.player_car.position
	_draw_glints(canvas, car, sz, t)
	_draw_glyph(canvas, car, t)

func _draw_glints(canvas: CanvasItem, car: Vector2, sz: Vector2, t: float) -> void:
	var tint: Color = LIFE_GREEN if _mode == MODE_LIFE else FUEL_AMBER
	for i in range(GLINT_OFFSETS.size()):
		var off: Vector2 = GLINT_OFFSETS[i]
		var local: float = (t - GLINT_STAGGER * float(i)) / GLINT_LIFE
		if local <= 0.0 or local >= 1.0:
			continue
		# Peaks in the middle of its window, in and out symmetrically.
		var k: float = sin(PI * local)
		var p: Vector2 = car + Vector2(off.x * sz.x * 0.5, off.y * sz.y * 0.5)
		var arm: float = GLINT_ARM * k
		var col := Color(GLINT.r, GLINT.g, GLINT.b, 0.95 * k)
		var soft := Color(tint.r, tint.g, tint.b, 0.35 * k)
		# Long spokes on the axes, short ones on the diagonals: the classic
		# four-point star, which is what a highlight on chrome looks like
		# and what a "spanner glint" is at this size.
		canvas.draw_line(p + Vector2(-arm, 0.0), p + Vector2(arm, 0.0), col, 1.5)
		canvas.draw_line(p + Vector2(0.0, -arm), p + Vector2(0.0, arm), col, 1.5)
		var d: float = arm * 0.45
		canvas.draw_line(p + Vector2(-d, -d), p + Vector2(d, d), soft, 1.0)
		canvas.draw_line(p + Vector2(-d, d), p + Vector2(d, -d), soft, 1.0)
		canvas.draw_circle(p, 1.2 + k, col)

func _draw_glyph(canvas: CanvasItem, car: Vector2, t: float) -> void:
	var k: float = clampf(t / DURATION, 0.0, 1.0)
	var rise: float = 1.0 - pow(1.0 - k, 2.0)
	var alpha: float = 1.0
	if k < GLYPH_IN_FRAC:
		alpha = k / GLYPH_IN_FRAC
	elif k > 1.0 - GLYPH_OUT_FRAC:
		alpha = (1.0 - k) / GLYPH_OUT_FRAC
	alpha = clampf(alpha, 0.0, 1.0)
	if alpha <= 0.0:
		return
	# -y is up: the glyph leaves the car toward the top of the board.
	var c: Vector2 = car + Vector2(0.0, -GLYPH_RISE * rise)
	if _mode == MODE_LIFE:
		_draw_cross(canvas, c, alpha)
	else:
		_draw_bolt(canvas, c, alpha)

# A plus sign — the universal "repaired / healed" mark, and the one shape a
# player reads at car size without being told. Outline first, then fill.
func _draw_cross(canvas: CanvasItem, c: Vector2, alpha: float) -> void:
	var o: float = GLYPH_OUTLINE
	var half_t: float = CROSS_THICK * 0.5
	var dark := Color(OUTLINE.r, OUTLINE.g, OUTLINE.b, 0.8 * alpha)
	var fill := Color(LIFE_GREEN.r, LIFE_GREEN.g, LIFE_GREEN.b, alpha)
	canvas.draw_rect(Rect2(c.x - CROSS_ARM - o, c.y - half_t - o, (CROSS_ARM + o) * 2.0, (half_t + o) * 2.0), dark, true)
	canvas.draw_rect(Rect2(c.x - half_t - o, c.y - CROSS_ARM - o, (half_t + o) * 2.0, (CROSS_ARM + o) * 2.0), dark, true)
	canvas.draw_rect(Rect2(c.x - CROSS_ARM, c.y - half_t, CROSS_ARM * 2.0, CROSS_THICK), fill, true)
	canvas.draw_rect(Rect2(c.x - half_t, c.y - CROSS_ARM, CROSS_THICK, CROSS_ARM * 2.0), fill, true)
	# A lighter core so it reads as lit rather than painted.
	canvas.draw_rect(Rect2(c.x - half_t * 0.5, c.y - CROSS_ARM * 0.8, half_t, CROSS_ARM * 1.6), Color(1.0, 1.0, 1.0, 0.45 * alpha), true)

# A lightning bolt for the fuel fallback: the boost bar's own vocabulary is
# fire and heat, and a bolt is the one glyph that says "energy, right now"
# without needing the bar in view to explain it.
func _draw_bolt(canvas: CanvasItem, c: Vector2, alpha: float) -> void:
	var pts := PackedVector2Array()
	for i in range(BOLT_SHAPE.size()):
		var v: Vector2 = BOLT_SHAPE[i]
		pts.append(c + v * BOLT_HALF_H)
	var outline := PackedVector2Array(pts)
	outline.append(pts[0])
	canvas.draw_polyline(outline, Color(OUTLINE.r, OUTLINE.g, OUTLINE.b, 0.8 * alpha), GLYPH_OUTLINE * 2.0)
	canvas.draw_colored_polygon(pts, Color(FUEL_AMBER.r, FUEL_AMBER.g, FUEL_AMBER.b, alpha))
	# Same lit core as the cross, along the bolt's spine.
	canvas.draw_line(c + Vector2(0.06, -0.7) * BOLT_HALF_H, c + Vector2(-0.12, 0.7) * BOLT_HALF_H, Color(1.0, 1.0, 1.0, 0.45 * alpha), 1.5)
