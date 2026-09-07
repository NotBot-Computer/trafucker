extends TowerSkill

## CROSSWIND (pack B, id "crosswind") — an opponent skill that attacks the
## victim's *hands*: a wind blows across the tower for their next turn, and
## every gust of it shoves their brick a whole cell sideways.
##
## The push is not a force and not a slide. This mode moves a held brick in
## exact half-cell commands (TowerMode's header), so the wind speaks the same
## language: a gust is `mode._command_move(dir, 1.0)` — the same thing the
## victim's own dash key does, with the same lattice, the same aim bound and
## the same collision check — issued by the weather instead of by them. That
## is what keeps it fair: the brick is never put anywhere the player could
## not have put it, and the counter is exactly one dash the other way (or two
## taps). The skill costs the victim presses and attention, not the ability
## to steer.
##
## Every gust is telegraphed. For GUST_LEAD before a push the streaks over
## the play column brighten and lengthen and a chevron slides in on the
## windward side of the brick, so a player watching their brick sees the
## shove coming and can lean into it — or drop through it, since a soft
## drop is the other honest answer to wind. Three uncountered gusts on a
## five-cell platform put the brick's centre past the edge, so the hex bites
## if it is ignored; read and countered, it is a turn spent working.
##
## Half the turns the wind also VEERS: on one gust, after the push, it
## reverses, and the streaks and the next chevron say so. That is the moment
## this skill is about — a player who has been leaning left for two gusts
## and gets shoved right on the third. It is announced with a toast, because
## a surprise the victim could not have seen coming is a glitch, not a hex.
##
## What it does NOT touch: no lock, no flip, no speed change. A dash lock
## would remove the counter; a flipped steer on top of a wind would be two
## hexes in one icon. Landed bricks are never pushed — this is the pilot's
## air, not the tower's physics. It writes nothing on the mode except the
## commands themselves (which are the player's own steering state, reset by
## the mode at every _begin_turn), adds no node, and deactivate() has
## nothing to put back.

# --- Timing -----------------------------------------------------------------

# Seconds of piloting before the first push. Half a second is long enough
# for the streaks to be seen before anything moves, short enough that a
# player who soft-drops the instant their brick appears (~0.6s to the stack
# at SOFT_DROP_SPEED from spawn) is still caught by it mid-fall.
const FIRST_GUST := 0.5
# Between pushes. The ordinary descent is ~2.5s, so this is two or three
# gusts a turn — enough to need answering, not so many the turn is only
# answering.
const GUST_INTERVAL := 0.9
# One whole cell, the dash's own distance, so the counter is one chord.
const GUST_CELLS := 1.0
# How long before a push the streaks build and the chevron slides in.
const GUST_LEAD := 0.35
# Chance the wind reverses on a gust, and the window (seconds of piloting)
# the reversal is drawn from. The lower bound is after the first gust has
# landed, so a veer is always a *change* the player has already leaned
# against; the upper bound is inside an ordinary descent, so it happens
# before the brick is down.
const VEER_CHANCE := 0.5
const VEER_MIN := 1.2
const VEER_MAX := 2.4

# The streak field rises with the turn and drops once the brick lands: the
# hex is on the pilot, and the wind dying the moment the brick is out of
# their hands says so.
const WIND_RISE := 0.25
const WIND_FALL := 0.4
const FLASH_TIME := 0.3 # the kick in the streaks right after a push

# --- Visuals ----------------------------------------------------------------
# All procedural, in world space over the bricks (draw_over) so the wind is
# in front of the tower, and derived from _clock / _scroll advanced in
# tick() — no tween, no node. Widths are screen px over the camera zoom.

const STREAK_COUNT := 26
const STREAK_LEN_MIN := 30.0 # world px at rest
const STREAK_LEN_MAX := 90.0
const STREAK_SPEED_MIN := 420.0 # world px/s
const STREAK_SPEED_MAX := 760.0
# How far outside the play column the field extends, so streaks enter and
# leave rather than popping at its edge.
const FIELD_MARGIN_CELLS := 2.5
# A streak is a dark core with a thin light highlight on top. The backdrop
# is a bright pixel-art sky (PROJECT_STATE §7: nothing drawn over it may be
# light alone), and the bricks are saturated colour; the pair reads on both.
const CORE := Color(0.10, 0.13, 0.28)
const HIGHLIGHT := Color(0.96, 0.98, 1.0)
# Measured off a real frame: at 0.32 / 2.5px the streaks read as scratches
# on the sky rather than as air moving; this is the least that reads as
# weather from across a table without hiding the bricks under it.
const CORE_ALPHA := 0.42
const HIGHLIGHT_ALPHA := 0.30
const GUST_ALPHA_GAIN := 1.6 # multiplied in at the peak of a gust
const GUST_LEN_GAIN := 0.9 # streaks lengthen by this fraction at the peak
const GUST_SPEED_GAIN := 0.7 # and the field scrolls this much faster
const CORE_WIDTH := 3.0
const HIGHLIGHT_WIDTH := 1.2
# The chevron that slides in on the windward side during the lead.
const CHEVRON_FAR_CELLS := 2.2 # where it starts, beyond the brick's edge
const CHEVRON_NEAR_CELLS := 0.7 # where it arrives as the push lands
const CHEVRON_SIZE := 12.0 # screen px
const CHEVRON_COLOR := Color(0.96, 0.98, 1.0)
const CHEVRON_RIM := Color(0.10, 0.13, 0.28)
const TOAST := Color(0.82, 0.92, 1.0)

# --- State ------------------------------------------------------------------

var _retired: bool = false
var _dir: int = 1
var _pilot_time: float = 0.0 # seconds of the target's piloting this turn
var _next_gust: float = FIRST_GUST
var _veer_at: float = -1.0 # -1: no veer this turn
var _flash: float = 0.0
var _wind: float = 0.0 # streak envelope, 0..1
var _clock: float = 0.0 # for the small per-streak wobble
# Signed scroll of the field, in "unit speed" px: each streak multiplies it
# by its own speed. Accumulated with _dir so a veer turns the field around
# smoothly instead of teleporting every streak.
var _scroll: float = 0.0
# One entry per streak: {"x0", "yf", "len", "speed", "phase"}. Built once
# per activation and only read after, so each keeps its identity.
var _streaks: Array[Dictionary] = []

# --- Hooks ------------------------------------------------------------------

func hud_tag() -> String:
	return "WINDY"

# --- Lifecycle --------------------------------------------------------------

func activate() -> void:
	_retired = false
	_wind = 0.0
	_clock = 0.0
	_scroll = 0.0
	_build_streaks()
	_arm_turn()

# Only reached with duration_turns() > 1, which this skill does not claim —
# kept correct anyway so the constant can be raised without a surprise.
func on_turn_start() -> void:
	_arm_turn()

func _arm_turn() -> void:
	_dir = 1 if randf() < 0.5 else -1
	_pilot_time = 0.0
	_next_gust = FIRST_GUST
	_flash = 0.0
	_veer_at = randf_range(VEER_MIN, VEER_MAX) if randf() < VEER_CHANCE else -1.0

func tick(delta: float) -> void:
	if _retired or mode == null:
		return
	_clock += delta
	var piloting: bool = mode.state == "piloting" and mode.active_piece != null
	_wind = move_toward(_wind, 1.0 if piloting else 0.0, delta / (WIND_RISE if piloting else WIND_FALL))
	_flash = maxf(0.0, _flash - delta / FLASH_TIME)
	_scroll += delta * float(_dir) * (1.0 + GUST_SPEED_GAIN * _intensity())
	if not piloting:
		return
	_pilot_time += delta
	if _pilot_time >= _next_gust:
		# The push. Through the mode's own command path — lattice, aim bound
		# and collision check included — never the brick's position.
		mode._command_move(_dir, GUST_CELLS)
		_flash = 1.0
		_next_gust += GUST_INTERVAL
		if _veer_at >= 0.0 and _pilot_time >= _veer_at:
			_veer_at = -1.0
			_dir = -_dir
			mode.hud.show_message("THE WIND TURNS %s" % ("→" if _dir > 0 else "←"), TOAST)

# Nothing to put back: the only thing this effect ever wrote on the mode is
# the aim command, which is the player's own steering state and is reset by
# _begin_turn like any other press. No node, no multiplier, no lock.
# Idempotent — a second call finds _retired already set.
func deactivate() -> void:
	_retired = true
	_wind = 0.0

# --- Envelope -----------------------------------------------------------------

# 0 between gusts, rising to 1 over GUST_LEAD before a push, then the
# after-push flash decaying. Both the streaks and the chevron read this.
func _lead() -> float:
	return clampf(1.0 - (_next_gust - _pilot_time) / GUST_LEAD, 0.0, 1.0)

func _intensity() -> float:
	return maxf(_lead(), _flash)

# --- Streak field -----------------------------------------------------------

func _build_streaks() -> void:
	_streaks = []
	for _i in range(STREAK_COUNT):
		_streaks.append({
			"x0": randf(),
			"yf": randf(),
			"len": randf_range(STREAK_LEN_MIN, STREAK_LEN_MAX),
			"speed": randf_range(STREAK_SPEED_MIN, STREAK_SPEED_MAX),
			"phase": randf() * TAU,
		})

# --- Drawing ----------------------------------------------------------------

# Above the bricks (TowerSkillOverlay, world space). The field spans the
# air the brick moves through: from the top of the view down to just past
# the stack top, across the play column and a margin either side.
func draw_over(canvas: CanvasItem) -> void:
	if _retired or mode == null or _wind <= 0.001:
		return
	if mode.active_slot != target:
		return
	var zoom: float = float(mode.camera.zoom.x)
	var px: float = 1.0 / zoom
	var cell: float = float(mode.CELL)
	var half_w: float = float(mode.PLATFORM_CELLS) * cell * 0.5
	var reach: float = half_w + float(mode.AIM_BOUND_CELLS) * cell + FIELD_MARGIN_CELLS * cell
	var width: float = reach * 2.0
	var view_h: float = canvas.get_viewport_rect().size.y / zoom
	var top: float = float(mode.camera.position.y) - view_h * 0.5
	var bottom: float = float(mode.stack_top_y) + cell
	if bottom - top < cell:
		return
	var gust: float = _intensity()
	var a_core: float = CORE_ALPHA * _wind * (1.0 + (GUST_ALPHA_GAIN - 1.0) * gust)
	var a_hi: float = HIGHLIGHT_ALPHA * _wind * (1.0 + (GUST_ALPHA_GAIN - 1.0) * gust)
	var len_gain: float = 1.0 + GUST_LEN_GAIN * gust

	for s: Dictionary in _streaks:
		var length: float = float(s["len"]) * len_gain
		# Position is a pure function of the scroll: wrapped across the
		# field's width, so a streak leaving one side re-enters the other.
		var x: float = -reach + fposmod(float(s["x0"]) * width + _scroll * float(s["speed"]), width)
		var y: float = top + float(s["yf"]) * (bottom - top) + sin(_clock * 1.7 + float(s["phase"])) * 3.0
		# The streak trails *behind* its head, so the head leads the way the
		# wind blows.
		var head := Vector2(x, y)
		var tail := Vector2(x - float(_dir) * length, y)
		canvas.draw_line(tail, head, Color(CORE.r, CORE.g, CORE.b, a_core), CORE_WIDTH * px)
		canvas.draw_line(tail, head + Vector2(0.0, -1.0 * px), Color(HIGHLIGHT.r, HIGHLIGHT.g, HIGHLIGHT.b, a_hi), HIGHLIGHT_WIDTH * px)

	_draw_chevron(canvas, px, cell)

# The telegraph: a double chevron on the windward side of the brick, sliding
# toward it over the lead and landing on it as the push does.
func _draw_chevron(canvas: CanvasItem, px: float, cell: float) -> void:
	var lead: float = _lead()
	if lead <= 0.0 or mode.state != "piloting":
		return
	var piece = mode.active_piece
	if piece == null or not is_instance_valid(piece):
		return
	var here: Vector2 = piece.global_position
	var edge: float = float(piece.aim_half_width(int(mode.aim_steps)))
	var dist: float = lerpf(CHEVRON_FAR_CELLS, CHEVRON_NEAR_CELLS, smoothstep(0.0, 1.0, lead)) * cell
	var x: float = here.x - float(_dir) * (edge + dist)
	var s: float = CHEVRON_SIZE * px
	var alpha: float = _wind * clampf(lead * 1.5, 0.0, 1.0)
	for k in range(2):
		var cx: float = x - float(_dir) * float(k) * s * 0.9
		var pts := PackedVector2Array([
			Vector2(cx - float(_dir) * s * 0.5, here.y - s),
			Vector2(cx + float(_dir) * s * 0.5, here.y),
			Vector2(cx - float(_dir) * s * 0.5, here.y + s),
		])
		canvas.draw_polyline(pts, Color(CHEVRON_RIM.r, CHEVRON_RIM.g, CHEVRON_RIM.b, alpha * 0.9), 4.5 * px)
		canvas.draw_polyline(pts, Color(CHEVRON_COLOR.r, CHEVRON_COLOR.g, CHEVRON_COLOR.b, alpha), 2.0 * px)
